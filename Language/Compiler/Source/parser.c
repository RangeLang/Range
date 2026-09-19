#include "parser.h"
#include <errno.h>
#include <ctype.h>

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Binary operator precedence, loosest first. */
static const char *const RANGE_PRECEDENCE[][7] = {
    {"||", NULL},
    {"&&", NULL},
    {"==", "!=", "<", ">", "<=", ">=", NULL},
    {"+", "-", NULL},
    {"*", "/", "%", NULL}
};
#define RANGE_PRECEDENCE_LEVELS \
    ((int)(sizeof(RANGE_PRECEDENCE) / sizeof(RANGE_PRECEDENCE[0])))

static void parserFail(RangeParser *parser, const RangeToken *token,
                       const char *format, ...)
{
    if (parser->failed) return;
    char detail[384];
    va_list arguments;
    va_start(arguments, format);
    vsnprintf(detail, sizeof(detail), format, arguments);
    va_end(arguments);
    snprintf(parser->error, sizeof(parser->error), "%s:%d:%d: %s",
             parser->path, token->line, token->column, detail);
    parser->failed = 1;
}

static void parserAdvance(RangeParser *parser)
{
    if (parser->failed) return;
    parser->previousEnd = parser->current.offset + parser->current.length;
    if (parser->hasAhead) {
        parser->current = parser->ahead;
        parser->hasAhead = 0;
        return;
    }
    if (!rangeLexerNext(&parser->lexer, &parser->current)) {
        snprintf(parser->error, sizeof(parser->error), "%s", parser->lexer.error);
        parser->failed = 1;
    }
}

static const RangeToken *parserPeek(RangeParser *parser)
{
    if (!parser->hasAhead) {
        RangeToken saved = parser->current;
        if (!rangeLexerNext(&parser->lexer, &parser->ahead)) {
            snprintf(parser->error, sizeof(parser->error), "%s", parser->lexer.error);
            parser->failed = 1;
        }
        parser->hasAhead = 1;
        parser->current = saved;
    }
    return &parser->ahead;
}

static int parserAt(RangeParser *parser, const char *text)
{
    return !parser->failed && rangeTokenIs(&parser->current, text);
}

static int parserAtKind(RangeParser *parser, RangeTokenKind kind)
{
    return !parser->failed && parser->current.kind == kind;
}

static void parserExpect(RangeParser *parser, const char *text)
{
    if (parser->failed) return;
    if (!rangeTokenIs(&parser->current, text)) {
        parserFail(parser, &parser->current, "expected '%s', found '%.*s'",
                   text, (int)parser->current.length, parser->current.text);
        return;
    }
    parserAdvance(parser);
}

static const char *parserExpectName(RangeParser *parser)
{
    if (parser->failed) return "";
    if (parser->current.kind != RangeTokenName) {
        parserFail(parser, &parser->current, "expected a name, found '%.*s'",
                   (int)parser->current.length, parser->current.text);
        return "";
    }
    const char *name = rangeArenaIntern(parser->arena, parser->current.text,
                                        parser->current.length);
    parserAdvance(parser);
    return name;
}

static RangeNode *parserNode(RangeParser *parser, RangeNodeKind kind)
{
    return rangeNodeCreate(parser->arena, kind, parser->path,
                           parser->current.line, parser->current.column);
}

static RangeNode *parseExpression(RangeParser *parser, int level);
static RangeNode *parseFunction(RangeParser *parser, RangeNode *attributes,
                                const char *receiver);
static RangeNode *parseBlock(RangeParser *parser);
static RangeNode *parseStatement(RangeParser *parser);
static void parseArgumentList(RangeParser *parser, RangeNode *owner);
static RangeNode *parseGenericArguments(RangeParser *parser, int typePosition);
static RangeNode *parseGenericMembers(RangeParser *parser);

/* ---- types ---------------------------------------------------------- */

/* Reads a type position, returning the interned name and setting *many when
 * the position is a collection. An empty name means an untyped @many. */
static const char *parseTypeName(RangeParser *parser, int *flags, RangeNode **generics)
{
    *flags = 0;
    if (parserAt(parser, "@")) {
        const RangeToken *ahead = parserPeek(parser);
        if (rangeTokenIs(ahead, "many")) {
            parserAdvance(parser);
            parserAdvance(parser);
            *flags |= RangeFlagMany;
            if (parser->current.kind != RangeTokenName) return "";
        } else if (rangeTokenIs(ahead, "syntax") || rangeTokenIs(ahead, "type")
                   || rangeTokenIs(ahead, "encoding") || rangeTokenIs(ahead, "one")
                   || rangeTokenIs(ahead, "any") || rangeTokenIs(ahead, "member")) {
            parserAdvance(parser);
            const char *name = rangeArenaIntern(parser->arena,
                                                parser->current.text,
                                                parser->current.length);
            parserAdvance(parser);
            if (parserAt(parser, "?")) { parserAdvance(parser); *flags |= RangeFlagOptional; }
            return name;
        }
    }
    const char *name = parserExpectName(parser);
    if (parserAt(parser, "<")) *generics = parseGenericArguments(parser, 1);
    if (parserAt(parser, "?")) { parserAdvance(parser); *flags |= RangeFlagOptional; }
    /* Retain every alternative. Execution may reject a union, but must never
     * silently interpret it as only its first alternative. */
    while (parserAt(parser, "|")) {
        if (*generics) {
            parserFail(parser, &parser->current, "specialized union types are not supported by the compiler parser");
            return name;
        }
        parserAdvance(parser);
        const char *alternative = parserExpectName(parser);
        size_t length = strlen(name) + strlen(alternative) + 2;
        char *combined = rangeArenaAllocate(parser->arena, length);
        snprintf(combined, length, "%s|%s", name, alternative);
        name = combined;
    }
    return name;
}

/* ---- attributes ------------------------------------------------------ */

/* True when the current token opens a type position rather than an inferred
 * initialiser. `let x: Int(0)` is typed; `let m: #environment.filter(...)` and
 * `let author: "George"` place the initialising expression in that position. */
static int atTypePosition(RangeParser *parser)
{
    if (parser->current.kind == RangeTokenName)
        return !parserAt(parser,"true") && !parserAt(parser,"false");
    if (!parserAt(parser, "@")) return 0;
    const RangeToken *ahead = parserPeek(parser);
    return rangeTokenIs(ahead, "many") || rangeTokenIs(ahead, "syntax")
        || rangeTokenIs(ahead, "type") || rangeTokenIs(ahead, "encoding")
        || rangeTokenIs(ahead, "one") || rangeTokenIs(ahead, "any")
        || rangeTokenIs(ahead, "member");
}

static RangeNode *parseAttributes(RangeParser *parser)
{
    RangeNode *list = parserNode(parser, RangeNodeAttribute);
    while (parserAt(parser, "@")) {
        RangeNode *attribute = parserNode(parser, RangeNodeAttribute);
        parserAdvance(parser);
        attribute->name = parserExpectName(parser);
        if (strcmp(attribute->name, "syntax") == 0) {
            parserFail(parser, &parser->current, "@syntax is deferred; structural syntax is defined in C");
            return list;
        } else {
            if (parserAt(parser, "<")) attribute->generics = parseGenericArguments(parser, 0);
            if (parserAt(parser, "(")) parseArgumentList(parser, attribute);
        }
        rangeNodeAppend(parser->arena, list, attribute);
        if (parser->failed) break;
        if (strcmp(attribute->name, "main") == 0) break;
    }
    return list;
}

static int attributesContain(const RangeNode *attributes, const char *name)
{
    for (size_t index = 0; index < attributes->itemCount; ++index) {
        if (strcmp(attributes->items[index]->name, name) == 0) return 1;
    }
    return 0;
}

/* ---- expressions ----------------------------------------------------- */

static RangeNode *parseString(RangeParser *parser)
{
    RangeNode *node = parserNode(parser, RangeNodeString);
    RangeToken token = parser->current;
    parserAdvance(parser);

    const char *source = parser->source;
    size_t cursor = token.bodyStart;
    /* Preserve every byte, including literals larger than a diagnostic buffer. */
    char *literal = rangeArenaAllocate(parser->arena, token.bodyEnd - token.bodyStart + 1);
    size_t literalLength = 0;

    while (cursor < token.bodyEnd) {
        char c = source[cursor];
        if (c == '\\' && cursor + 1 < token.bodyEnd) {
            char escaped = source[cursor + 1];
            if (escaped == '(') {
                if (literalLength) {
                    RangeNode *part = parserNode(parser, RangeNodeStringPart);
                    part->flags = RangeFlagLiteral;
                    part->name = rangeArenaIntern(parser->arena, literal, literalLength);
                    part->integer = (long long)literalLength;
                    rangeNodeAppend(parser->arena, node, part);
                    literalLength = 0;
                }
                size_t start = cursor + 2;
                size_t scan = start;
                int depth = 0;
                while (scan < token.bodyEnd) {
                    char inner = source[scan];
                    if (inner == '(') depth += 1;
                    else if (inner == ')') { if (depth == 0) break; depth -= 1; }
                    else if (inner == '"') {
                        scan += 1;
                        while (scan < token.bodyEnd && source[scan] != '"') {
                            if (source[scan] == '\\') scan += 1;
                            scan += 1;
                        }
                    }
                    scan += 1;
                }
                RangeParser inner;
                memset(&inner, 0, sizeof(inner));
                inner.arena = parser->arena;
                inner.path = parser->path;
                inner.source = parser->source;
                rangeLexerInit(&inner.lexer, parser->path, parser->source,
                               start, scan, token.line);
                parserAdvance(&inner);
                RangeNode *expression = parseExpression(&inner, 0);
                if (!inner.failed && inner.current.kind != RangeTokenEnd) {
                    parserFail(&inner, &inner.current, "trailing tokens in interpolation");
                }
                if (inner.failed) {
                    snprintf(parser->error, sizeof(parser->error), "%s", inner.error);
                    parser->failed = 1;
                    return node;
                }
                RangeNode *part = parserNode(parser, RangeNodeStringPart);
                part->a = expression;
                rangeNodeAppend(parser->arena, node, part);
                cursor = scan + 1;
                continue;
            }
            char decoded;
            switch (escaped) {
                case 'n': decoded = '\n'; break;
                case 't': decoded = '\t'; break;
                case '0': decoded = '\0'; break;
                case '\\': decoded = '\\'; break;
                case '"': decoded = '"'; break;
                default:
                    parserFail(parser, &token, "unknown string escape '\\%c'", escaped);
                    return node;
            }
            literal[literalLength++] = decoded;
            cursor += 2;
            continue;
        }
        literal[literalLength++] = c;
        cursor += 1;
    }
    if (literalLength || node->itemCount == 0) {
        RangeNode *part = parserNode(parser, RangeNodeStringPart);
        part->flags = RangeFlagLiteral;
        part->name = rangeArenaIntern(parser->arena, literal, literalLength);
        part->integer = (long long)literalLength;
        rangeNodeAppend(parser->arena, node, part);
    }
    return node;
}

static void parseArgumentList(RangeParser *parser, RangeNode *owner)
{
    int outerGenericDepth = parser->genericDepth;
    parser->genericDepth = 0;
    parserExpect(parser, "(");
    while (!parser->failed && !parserAt(parser, ")")) {
        RangeNode *argument = parserNode(parser, RangeNodeArgument);
        if (parser->current.kind == RangeTokenName
            && rangeTokenIs(parserPeek(parser), ":")) {
            argument->name = parserExpectName(parser);
            parserExpect(parser, ":");
        }
        argument->a = parseExpression(parser, 0);
        rangeNodeAppend(parser->arena, owner, argument);
        if (parserAt(parser, ",")) parserAdvance(parser);
    }
    parserExpect(parser, ")");
    parser->genericDepth = outerGenericDepth;
}

static RangeNode *parseGenericArguments(RangeParser *parser, int typePosition)
{
    RangeNode *list = parserNode(parser, RangeNodeBlock);
    list->name = "genericArguments";
    list->spanStart = parser->current.offset;
    parserExpect(parser, "<");
    if (parserAt(parser, ">")) parserFail(parser, &parser->current, "generic arguments cannot be empty");
    while (!parser->failed && !parserAt(parser, ">")) {
        RangeNode *argument = parserNode(parser, RangeNodeArgument);
        if (typePosition && parser->current.kind == RangeTokenName
            && !rangeTokenIs(parserPeek(parser), ":")) {
            // Positional type arguments, including nested Array<Array<Member>>.
            argument->a = parserNode(parser, RangeNodeName);
            argument->a->name = parseTypeName(parser, &argument->a->flags, &argument->a->generics);
        } else {
            argument->name = parserExpectName(parser);
            if (strcmp(argument->name, "_") == 0)
                parserFail(parser, &parser->current, "generic arguments require a named label");
            parserExpect(parser, ":");
            parser->genericDepth += 1;
            argument->a = parseExpression(parser, 0);
            parser->genericDepth -= 1;
        }
        rangeNodeAppend(parser->arena, list, argument);
        if (!parserAt(parser, ">")) parserExpect(parser, ",");
    }
    parserExpect(parser, ">");
    list->spanEnd = parser->previousEnd;
    return list;
}

/* Named arguments distinguish specialization from comparisons such as a < b.
 * Look ahead without allocating AST nodes or changing the real lexer state. */
static int startsGenericArguments(RangeParser *parser)
{
    if (!parserAt(parser, "<")) return 0;
    RangeParser probe = *parser;
    parserAdvance(&probe);
    if (parserAt(&probe, ">")) return 1;
    return probe.current.kind == RangeTokenName && rangeTokenIs(parserPeek(&probe), ":");
}

static RangeNode *parsePrimary(RangeParser *parser)
{
    if (parser->failed) return NULL;
    RangeToken token = parser->current;

    if (token.kind == RangeTokenInteger) {
        RangeNode *node = parserNode(parser, RangeNodeInteger);
        char buffer[64];
        size_t width = token.length < sizeof(buffer) - 1 ? token.length : sizeof(buffer) - 1;
        memcpy(buffer, token.text, width);
        buffer[width] = '\0';
        node->name = rangeArenaIntern(parser->arena, token.text, token.length);
        errno = 0;
        node->integer = strtoll(buffer, NULL, 10);
        if (errno == ERANGE || token.length >= sizeof(buffer)) {
            parserFail(parser, &token, "integer literal exceeds signed 64-bit range");
        }
        parserAdvance(parser);
        return node;
    }
    if (token.kind == RangeTokenString) return parseString(parser);
    if (rangeTokenIs(&token, "true") || rangeTokenIs(&token, "false")) {
        RangeNode *node = parserNode(parser, RangeNodeBool);
        node->integer = rangeTokenIs(&token, "true") ? 1 : 0;
        parserAdvance(parser);
        return node;
    }
    if (parserAt(parser, ".")) {
        RangeNode *node = parserNode(parser, RangeNodeCase);
        parserAdvance(parser);
        node->name = parserExpectName(parser);
        return node;
    }
    if (parserAt(parser, "#")) {
        RangeNode *node = parserNode(parser, RangeNodeEnvironment);
        parserAdvance(parser);
        node->name = parserExpectName(parser);
        if (parser->conditionDepth == 0 && parserAt(parser, "{")) {
            RangeNode *emission = parserNode(parser, RangeNodeEmission);
            emission->a = node;
            emission->b = parseBlock(parser);
            return emission;
        }
        return node;
    }
    if (parserAt(parser, "$")) {
        RangeNode *node = parserNode(parser, RangeNodeSyntaxTemplate);
        parserAdvance(parser);
        node->name = parserExpectName(parser);
        return node;
    }
    if (parserAt(parser, "@")) {
        const RangeToken *ahead = parserPeek(parser);
        if (rangeTokenIs(ahead, "many") || rangeTokenIs(ahead, "any")
            || rangeTokenIs(ahead, "one")) {
            RangeNode *node = parserNode(parser, RangeNodeManyLiteral);
            parserAdvance(parser);
            node->name = rangeArenaIntern(parser->arena, parser->current.text,
                                          parser->current.length);
            parserAdvance(parser);
            if (parserAt(parser, "(")) parseArgumentList(parser, node);
            return node;
        }
        RangeNode *node = parserNode(parser, RangeNodeAttribute);
        parserAdvance(parser);
        node->name = parserExpectName(parser);
        if (parserAt(parser, "(")) parseArgumentList(parser, node);
        return node;
    }
    if (parserAt(parser, "(")) {
        int outerGenericDepth = parser->genericDepth;
        parser->genericDepth = 0;
        parserAdvance(parser);
        RangeNode *inner = parseExpression(parser, 0);
        parserExpect(parser, ")");
        parser->genericDepth = outerGenericDepth;
        return inner;
    }
    if (token.kind == RangeTokenName) {
        RangeNode *node = parserNode(parser, RangeNodeName);
        node->name = parserExpectName(parser);
        return node;
    }
    parserFail(parser, &token, "unexpected '%.*s' in expression",
               (int)token.length, token.text);
    return NULL;
}

static RangeNode *parsePostfix(RangeParser *parser)
{
    RangeNode *value = parsePrimary(parser);
    while (!parser->failed) {
        if (value && startsGenericArguments(parser)) {
            if (value->generics) {
                parserFail(parser, &parser->current, "duplicate generic argument list");
                break;
            }
            value->generics = parseGenericArguments(parser, 0);
            continue;
        }
        if (parserAt(parser, ".")) {
            RangeNode *access = parserNode(parser, RangeNodeMemberAccess);
            parserAdvance(parser);
            access->a = value;
            access->name = parserExpectName(parser);
            if (parserAt(parser, "(")) {
                RangeNode *call = parserNode(parser, RangeNodeCall);
                call->a = access;
                parseArgumentList(parser, call);
                value = call;
            } else {
                value = access;
            }
            continue;
        }
        if (parserAt(parser, "(")) {
            RangeNode *call = parserNode(parser, RangeNodeCall);
            call->a = value;
            parseArgumentList(parser, call);
            value = call;
            continue;
        }
        if (parser->conditionDepth == 0 && parserAt(parser, "{")
            && parserPeek(parser)->kind == RangeTokenName) {
            /* Only a `{ name in` block is a closure; `if x.y {` is not. */
            size_t savedCursor = parser->lexer.cursor;
            int savedLine = parser->lexer.line;
            int savedColumn = parser->lexer.column;
            RangeToken savedCurrent = parser->current;
            RangeToken savedAhead = parser->ahead;
            int savedHasAhead = parser->hasAhead;
            RangeNode *closure = parserNode(parser, RangeNodeClosure);
            parserAdvance(parser);
            const char *binding = rangeArenaIntern(parser->arena,
                                                   parser->current.text,
                                                   parser->current.length);
            parserAdvance(parser);
            if (parserAt(parser, "in")) {
                parserAdvance(parser);
                closure->name = binding;
                RangeNode *body = parserNode(parser, RangeNodeBlock);
                while (!parser->failed && !parserAt(parser, "}")
                       && !parserAtKind(parser, RangeTokenEnd)) {
                    RangeNode *statement = parseStatement(parser);
                    if (statement) rangeNodeAppend(parser->arena, body, statement);
                }
                parserExpect(parser, "}");
                closure->a = body;
                RangeNode *argument = parserNode(parser, RangeNodeArgument);
                argument->a = closure;
                if (value->kind != RangeNodeCall) {
                    RangeNode *call = parserNode(parser, RangeNodeCall);
                    call->a = value;
                    value = call;
                }
                rangeNodeAppend(parser->arena, value, argument);
                continue;
            }
            parser->lexer.cursor = savedCursor;
            parser->lexer.line = savedLine;
            parser->lexer.column = savedColumn;
            parser->current = savedCurrent;
            parser->ahead = savedAhead;
            parser->hasAhead = savedHasAhead;
        }
        break;
    }
    return value;
}

static RangeNode *parseUnary(RangeParser *parser)
{
    if (parserAt(parser, "!") || parserAt(parser, "-")) {
        RangeNode *node = parserNode(parser, RangeNodeUnary);
        node->name = rangeArenaIntern(parser->arena, parser->current.text,
                                      parser->current.length);
        parserAdvance(parser);
        node->a = parseUnary(parser);
        return node;
    }
    return parsePostfix(parser);
}

static RangeNode *parseExpression(RangeParser *parser, int level)
{
    if (level >= RANGE_PRECEDENCE_LEVELS) return parseUnary(parser);
    RangeNode *left = parseExpression(parser, level + 1);
    while (!parser->failed && parser->current.kind == RangeTokenSymbol) {
        if (parser->genericDepth > 0 && parserAt(parser, ">")) break;
        const char *matched = NULL;
        for (int index = 0; RANGE_PRECEDENCE[level][index] != NULL; ++index) {
            if (rangeTokenIs(&parser->current, RANGE_PRECEDENCE[level][index])) {
                matched = RANGE_PRECEDENCE[level][index];
                break;
            }
        }
        if (!matched) break;
        RangeNode *node = parserNode(parser, RangeNodeBinary);
        node->name = matched;
        node->a = left;
        parserAdvance(parser);
        node->b = parseExpression(parser, level + 1);
        left = node;
    }
    return left;
}

/* ---- statements ------------------------------------------------------ */

static RangeNode *parseIf(RangeParser *parser)
{
    RangeNode *node = parserNode(parser, RangeNodeIf);
    parserExpect(parser, "if");
    parser->conditionDepth += 1;
    node->a = parseExpression(parser, 0);
    parser->conditionDepth -= 1;
    node->b = parseBlock(parser);
    if (parserAt(parser, "else")) {
        parserAdvance(parser);
        node->c = parserAt(parser, "if") ? parseIf(parser) : parseBlock(parser);
    }
    return node;
}

static RangeNode *parseStatement(RangeParser *parser)
{
    if (parser->failed) return NULL;
    if (parserAt(parser, "@")) {
        RangeNode *attributes = parseAttributes(parser);
        if (parserAt(parser, "{")) {
            RangeNode *emitted = parserNode(parser, RangeNodeMain);
            emitted->a = parseBlock(parser);
            emitted->b = attributes;
            return emitted;
        }
        if (parserAt(parser, "}") || parserAtKind(parser, RangeTokenEnd)) {
            /* Attributes not modifying a declaration are macro applications.
             * Each one is its own statement; a run of them becomes a block. */
            if (attributes->itemCount == 1) {
                RangeNode *application =
                    parserNode(parser, RangeNodeExpressionStatement);
                application->a = attributes->items[0];
                return application;
            }
            RangeNode *group = parserNode(parser, RangeNodeBlock);
            for (size_t index = 0; index < attributes->itemCount; ++index) {
                RangeNode *application =
                    parserNode(parser, RangeNodeExpressionStatement);
                application->a = attributes->items[index];
                rangeNodeAppend(parser->arena, group, application);
            }
            return group;
        }
        RangeNode *statement = parseStatement(parser);
        if (statement) {
            statement->annotations = attributes;
            if (statement->kind == RangeNodeLocal && attributesContain(attributes, "many")) {
                statement->flags |= RangeFlagMany;
            }
        }
        return statement;
    }
    if (parserAt(parser, "let") || parserAt(parser, "state")) {
        RangeNode *node = parserNode(parser, RangeNodeLocal);
        if (parserAt(parser, "state")) node->flags |= RangeFlagMutable;
        parserAdvance(parser);
        node->name = parserExpectName(parser);
        if (!parserAt(parser, ":") && !(node->flags & RangeFlagMutable)) return node;
        parserExpect(parser, ":");
        node->rhsStart = parser->current.offset;
        RangeToken rhsToken = parser->current;
        if (atTypePosition(parser)) {
            int typeFlags = 0;
            node->typeName = parseTypeName(parser, &typeFlags, &node->generics);
            node->flags |= typeFlags;
            if (parserAt(parser, "(")) {
                node->flags |= RangeFlagApplication;
                parseArgumentList(parser, node);
            }
        } else {
            node->typeName = NULL;
            RangeNode *argument = parserNode(parser, RangeNodeArgument);
            argument->a = parseExpression(parser, 0);
            rangeNodeAppend(parser->arena, node, argument);
        }
        node->rhsEnd = parser->previousEnd;
        if (node->typeName && node->flags == 0 && node->itemCount == 0) {
            node->rhsReference = rangeNodeCreate(parser->arena, RangeNodeName,
                parser->path, rhsToken.line, rhsToken.column);
            node->rhsReference->name = node->typeName;
            node->rhsReference->generics = node->generics;
        } else if (node->typeName && node->flags == RangeFlagMutable && node->itemCount == 0) {
            node->rhsReference = rangeNodeCreate(parser->arena, RangeNodeName,
                parser->path, rhsToken.line, rhsToken.column);
            node->rhsReference->name = node->typeName;
            node->rhsReference->generics = node->generics;
        }
        return node;
    }
    if (parserAt(parser, "if")) return parseIf(parser);
    if (parserAt(parser, "switch")) {
        RangeNode *node = parserNode(parser, RangeNodeSwitch);
        parserAdvance(parser);
        parser->conditionDepth += 1;
        node->a = parseExpression(parser, 0);
        parser->conditionDepth -= 1;
        parserExpect(parser, "{");
        while (!parser->failed && !parserAt(parser, "}")
               && !parserAtKind(parser, RangeTokenEnd)) {
            RangeNode *entry = parserNode(parser, RangeNodeSwitchCase);
            if (parserAt(parser, "default")) {
                parserAdvance(parser);
                entry->flags |= RangeFlagLiteral;   /* marks the default arm */
            } else {
                parserExpect(parser, "case");
                /* Patterns are either a relational form such as `case < 0:`
                 * or an ordinary expression such as `case .none:`. */
                if (parser->current.kind == RangeTokenSymbol
                    && !parserAt(parser, ".")) {
                    entry->name = rangeArenaIntern(parser->arena,
                                                   parser->current.text,
                                                   parser->current.length);
                    parserAdvance(parser);
                }
                entry->a = parseExpression(parser, 0);
            }
            parserExpect(parser, ":");
            RangeNode *body = parserNode(parser, RangeNodeBlock);
            while (!parser->failed && !parserAt(parser, "case")
                   && !parserAt(parser, "default") && !parserAt(parser, "}")
                   && !parserAtKind(parser, RangeTokenEnd)) {
                RangeNode *statement = parseStatement(parser);
                if (statement) rangeNodeAppend(parser->arena, body, statement);
            }
            entry->b = body;
            rangeNodeAppend(parser->arena, node, entry);
        }
        parserExpect(parser, "}");
        return node;
    }
    if (parserAt(parser, "extension")) {
        /* Declaration emitted into another declaration's surface. */
        RangeNode *node = parserNode(parser, RangeNodeExtension);
        parserAdvance(parser);
        parser->conditionDepth += 1;
        node->a = parseExpression(parser, 0);
        parser->conditionDepth -= 1;
        node->b = parseBlock(parser);
        return node;
    }
    if (parserAt(parser, "while")) {
        RangeNode *node = parserNode(parser, RangeNodeWhile);
        parserAdvance(parser);
        parser->conditionDepth += 1;
        node->a = parseExpression(parser, 0);
        parser->conditionDepth -= 1;
        node->b = parseBlock(parser);
        return node;
    }
    if (parserAt(parser,"return")) {
        RangeNode *node = parserNode(parser,RangeNodeReturn);
        parserAdvance(parser);
        if (!parserAt(parser,"}")) node->a = parseExpression(parser,0);
        return node;
    }
    RangeNode *target = parseExpression(parser, 0);
    if (parserAt(parser, ":")) {
        RangeNode *node = parserNode(parser, RangeNodeAssign);
        parserAdvance(parser);
        node->a = target;
        node->b = parseExpression(parser, 0);
        return node;
    }
    RangeNode *node = parserNode(parser, RangeNodeExpressionStatement);
    node->a = target;
    return node;
}

static RangeNode *parseBlock(RangeParser *parser)
{
    RangeNode *node = parserNode(parser, RangeNodeBlock);
    node->spanStart = parser->current.offset + parser->current.length;
    parserExpect(parser, "{");
    while (!parser->failed && !parserAt(parser, "}")
           && !parserAtKind(parser, RangeTokenEnd)) {
        if (parserAt(parser, "function")) {
            /* Macro bodies emit declarations as well as statements. */
            RangeNode *empty = parserNode(parser, RangeNodeAttribute);
            rangeNodeAppend(parser->arena, node,
                            parseFunction(parser, empty, NULL));
            continue;
        }
        RangeNode *statement = parseStatement(parser);
        if (statement) rangeNodeAppend(parser->arena, node, statement);
    }
    node->spanEnd = parser->current.offset;
    parserExpect(parser, "}");
    return node;
}

/* Generic declarations reuse immutable member nodes. Their RHS is a parsed
 * expression: a type requirement, default literal, or ordinary application. */
static RangeNode *parseGenericMembers(RangeParser *parser)
{
    RangeNode *list = parserNode(parser, RangeNodeBlock);
    list->name = "genericMembers";
    list->spanStart = parser->current.offset;
    parserExpect(parser, "<");
    if (parserAt(parser, ">")) parserFail(parser, &parser->current, "generic members cannot be empty");
    while (!parser->failed && !parserAt(parser, ">")) {
        RangeNode *member = parserNode(parser, RangeNodeMember);
        if (!parserAt(parser, "let")) {
            parserFail(parser, &parser->current, "generic members require explicit let");
            break;
        }
        parserAdvance(parser);
        member->name = parserExpectName(parser);
        if (strcmp(member->name, "_") == 0)
            parserFail(parser, &parser->current, "generic members require a single named identity");
        parserExpect(parser, ":");
        member->rhsStart = parser->current.offset;
        parser->genericDepth += 1;
        member->a = parseExpression(parser, 0);
        parser->genericDepth -= 1;
        member->rhsEnd = parser->previousEnd;
        rangeNodeAppend(parser->arena, list, member);
        if (!parserAt(parser, ">")) parserExpect(parser, ",");
    }
    parserExpect(parser, ">");
    list->spanEnd = parser->previousEnd;
    return list;
}

/* ---- declarations ---------------------------------------------------- */

static RangeNode *parseFunction(RangeParser *parser, RangeNode *attributes,
                                const char *receiver)
{
    RangeNode *node = parserNode(parser, RangeNodeFunction);
    parserExpect(parser, "function");
    node->name = parserExpectName(parser);
    if (parserAt(parser, "<")) node->generics = parseGenericMembers(parser);
    node->typeName = receiver;
    node->c = attributes;
    if (attributesContain(attributes, "extern")) node->flags |= RangeFlagExtern;
    if (attributesContain(attributes, "builtin")) node->flags |= RangeFlagBuiltin;
    parserExpect(parser, "(");
    while (!parser->failed && !parserAt(parser, ")")) {
        RangeNode *parameter = parserNode(parser, RangeNodeParameter);
        if (parserAt(parser, "binding")) parameter->flags |= RangeFlagBinding;
        else if (!parserAt(parser, "let")) {
            parserFail(parser, &parser->current, "inputs require explicit let or binding");
            break;
        }
        parserAdvance(parser);
        parameter->name = parserExpectName(parser);
        if (strcmp(parameter->name, "_") == 0 || parser->current.kind == RangeTokenName)
            parserFail(parser, &parser->current, "parameters require a single name used as the argument label");
        parserExpect(parser, ":");
        int typeFlags = 0;
        RangeNode *typeGenerics = NULL;
        const char *typeName = parseTypeName(parser, &typeFlags, &typeGenerics);
        parameter->flags |= typeFlags;
        parameter->b = rangeNodeCreate(parser->arena, RangeNodeName, parser->path,
                                       parameter->line, parameter->column);
        ((RangeNode *)parameter->b)->name = typeName;
        parameter->b->generics = typeGenerics;
        if (parserAt(parser, "(")) parseArgumentList(parser, parameter);
        if (parserAt(parser, ":"))
            parserFail(parser, &parser->current,
                       "parameter defaults require construction syntax, not a second colon");
        rangeNodeAppend(parser->arena, node, parameter);
        if (parserAt(parser, ",")) parserAdvance(parser);
    }
    parserExpect(parser, ")");
    if (parserAt(parser, ":")) {
        parserAdvance(parser);
        int typeFlags = 0;
        RangeNode *returnGenerics = NULL;
        const char *returns = parseTypeName(parser, &typeFlags, &returnGenerics);
        node->b = rangeNodeCreate(parser->arena, RangeNodeName, parser->path,
                                  node->line, node->column);
        ((RangeNode *)node->b)->name = returns;
        node->b->generics = returnGenerics;
        ((RangeNode *)node->b)->flags = typeFlags;
    }
    if (parserAt(parser, "{")) {
        node->a = parseBlock(parser);
    } else if (!(node->flags & (RangeFlagExtern | RangeFlagBuiltin))) {
        /* Only @extern and @builtin declarations may omit a body. */
        parserFail(parser, &parser->current,
                   "function %s has no body and is neither @extern nor @builtin",
                   node->name);
    }
    return node;
}

static RangeNode *parseConstruct(RangeParser *parser, RangeNode *attributes)
{
    RangeNode *node = parserNode(parser, RangeNodeConstruct);
    parserExpect(parser, "construct");
    node->name = parserExpectName(parser);
    if (parserAt(parser, "<")) node->generics = parseGenericMembers(parser);
    node->c = attributes;
    if (!parserAt(parser, "{")) return node;
    parserExpect(parser, "{");
    while (!parser->failed && !parserAt(parser, "}")) {
        RangeNode *memberAttributes = parseAttributes(parser);
        if (parserAt(parser, "function")) {
            rangeNodeAppend(parser->arena, node,
                            parseFunction(parser, memberAttributes, node->name));
            continue;
        }
        if (parserAt(parser, "construct")) {
            rangeNodeAppend(parser->arena, node,
                            parseConstruct(parser, memberAttributes));
            continue;
        }
        RangeNode *member = parserNode(parser, RangeNodeMember);
        member->c = memberAttributes;
        if (attributesContain(memberAttributes, "many")) member->flags |= RangeFlagMany;
        if (parserAt(parser, "state")) member->flags |= RangeFlagMutable;
        else if (parserAt(parser, "derived")) member->flags |= RangeFlagDerived;
        else if (parserAt(parser, "binding")) member->flags |= RangeFlagBinding;
        else if (!parserAt(parser, "let")) {
            parserFail(parser, &parser->current,
                       "expected a member declaration in construct %s, found '%.*s'",
                       node->name, (int)parser->current.length, parser->current.text);
            break;
        }
        parserAdvance(parser);
        member->name = parserExpectName(parser);
        if (!parserAt(parser, ":") && !(member->flags & (RangeFlagMutable|RangeFlagDerived|RangeFlagBinding))) {
            rangeNodeAppend(parser->arena, node, member);
            continue;
        }
        parserExpect(parser, ":");
        member->rhsStart = parser->current.offset;
        RangeToken rhsToken = parser->current;
        int typeFlags = 0;
        if (atTypePosition(parser)) {
            member->typeName = parseTypeName(parser, &typeFlags, &member->generics);
            member->flags |= typeFlags;
        } else {
            /* Inferred member type: the initialiser stands in the type
             * position, as in `let author: "George"`. */
            member->typeName = NULL;
            RangeNode *argument = parserNode(parser, RangeNodeArgument);
            argument->a = parseExpression(parser, 0);
            rangeNodeAppend(parser->arena, member, argument);
            member->rhsEnd = parser->previousEnd;
            rangeNodeAppend(parser->arena, node, member);
            continue;
        }
        if ((member->flags & RangeFlagDerived) && parserAt(parser, "{")) {
            member->a = parseBlock(parser);
        } else if (parserAt(parser, "{")) {
            member->a = parseBlock(parser);
        } else if (parserAt(parser, "(")) {
            member->flags |= RangeFlagApplication;
            parseArgumentList(parser, member);
        }
        member->rhsEnd = parser->previousEnd;
        if (member->typeName && !member->a && !member->itemCount
            && !(member->flags & ~RangeFlagMutable)) {
            member->rhsReference = rangeNodeCreate(parser->arena, RangeNodeName,
                parser->path, rhsToken.line, rhsToken.column);
            member->rhsReference->name = member->typeName;
            member->rhsReference->generics = member->generics;
        }
        rangeNodeAppend(parser->arena, node, member);
    }
    parserExpect(parser, "}");
    return node;
}

static RangeNode *parseEnum(RangeParser *parser, RangeNode *attributes)
{
    RangeNode *node = parserNode(parser, RangeNodeEnum);
    parserExpect(parser, "enum");
    node->name = parserExpectName(parser);
    node->c = attributes;
    parserExpect(parser, "{");
    long long ordinal = 0;
    while (!parser->failed && !parserAt(parser, "}")) {
        RangeNode *entry = parserNode(parser, RangeNodeEnumCase);
        parserExpect(parser, "case");
        entry->name = parserExpectName(parser);
        entry->integer = ordinal++;
        if (parserAt(parser, "(")) parseArgumentList(parser, entry);
        rangeNodeAppend(parser->arena, node, entry);
    }
    parserExpect(parser, "}");
    return node;
}

/* Macro declarations are parsed in full: parameters with defaults, the target
 * and result type positions, and the body as a real block. Macro bodies are
 * compile-time programs, so they may reference #environment and $ templates and
 * may end in a bare implicit result. Nothing here is retained as a raw span. */
static RangeNode *parseMacro(RangeParser *parser, RangeNode *attributes)
{
    RangeNode *node = parserNode(parser, RangeNodeMacro);
    parserExpect(parser, "macro");
    node->name = parserExpectName(parser);
    if (parserAt(parser, "<")) node->generics = parseGenericMembers(parser);
    node->c = attributes;

    parserExpect(parser, "(");
    while (!parser->failed && !parserAt(parser, ")")) {
        RangeNode *parameter = parserNode(parser, RangeNodeParameter);
        if (parserAt(parser, "binding")) parameter->flags |= RangeFlagBinding;
        else if (!parserAt(parser, "let")) {
            parserFail(parser, &parser->current, "inputs require explicit let or binding");
            break;
        }
        parserAdvance(parser);
        parameter->name = parserExpectName(parser);
        if (strcmp(parameter->name, "_") == 0 || parser->current.kind == RangeTokenName)
            parserFail(parser, &parser->current, "parameters require a single name used as the argument label");
        parserExpect(parser, ":");
        int typeFlags = 0;
        RangeNode *typeGenerics = NULL;
        const char *typeName = parseTypeName(parser, &typeFlags, &typeGenerics);
        parameter->flags |= typeFlags;
        parameter->b = rangeNodeCreate(parser->arena, RangeNodeName, parser->path,
                                       parameter->line, parameter->column);
        ((RangeNode *)parameter->b)->name = typeName;
        parameter->b->generics = typeGenerics;
        /* Defaults use ordinary construction, e.g. symbol: String(""). */
        if (parserAt(parser, ":")) {
            parserFail(parser, &parser->current,
                       "parameter defaults require construction syntax, not a second colon");
        } else if (parserAt(parser, "(")) {
            parseArgumentList(parser, parameter);
        }
        rangeNodeAppend(parser->arena, node, parameter);
        if (parserAt(parser, ",")) parserAdvance(parser);
    }
    parserExpect(parser, ")");

    if (parserAt(parser, ":")) {
        parserAdvance(parser);
        int targetFlags = 0;
        RangeNode *targetGenerics = NULL;
        const char *target = parseTypeName(parser, &targetFlags, &targetGenerics);
        node->typeName = target;
        node->b = rangeNodeCreate(parser->arena, RangeNodeName, parser->path,
                                  node->line, node->column);
        ((RangeNode *)node->b)->name = target;
        node->b->generics = targetGenerics;
        ((RangeNode *)node->b)->flags = targetFlags;
        if (parserAt(parser, "-")) {
            parserAdvance(parser);
            parserExpect(parser, ">");
            int resultFlags = 0;
            RangeNode *resultGenerics = NULL;
            const char *result = parseTypeName(parser, &resultFlags, &resultGenerics);
            RangeNode *returns = rangeNodeCreate(parser->arena, RangeNodeName,
                                                 parser->path, node->line,
                                                 node->column);
            returns->name = result;
            returns->generics = resultGenerics;
            returns->flags = resultFlags;
            ((RangeNode *)node->b)->a = returns;
        }
    }

    if (parserAt(parser, "{")) {
        parser->macroDepth += 1;
        node->a = parseBlock(parser);
        parser->macroDepth -= 1;
    }
    return node;
}

RangeNode *rangeParseUnit(RangeArena *arena, const char *path,
                          const char *source, size_t length,
                          char *error, size_t errorSize)
{
    RangeParser parser;
    memset(&parser, 0, sizeof(parser));
    parser.arena = arena;
    parser.path = path;
    parser.source = source;
    rangeLexerInit(&parser.lexer, path, source, 0, length, 1);
    parserAdvance(&parser);

    RangeNode *unit = rangeNodeCreate(arena, RangeNodeUnit, path, 1, 1);
    while (!parser.failed && !parserAtKind(&parser, RangeTokenEnd)) {
        RangeNode *attributes = parseAttributes(&parser);
        if (parserAt(&parser, "construct")) {
            rangeNodeAppend(arena, unit, parseConstruct(&parser, attributes));
        } else if (parserAt(&parser, "enum")) {
            rangeNodeAppend(arena, unit, parseEnum(&parser, attributes));
        } else if (parserAt(&parser, "function")) {
            rangeNodeAppend(arena, unit, parseFunction(&parser, attributes, NULL));
        } else if (parserAt(&parser, "macro")) {
            rangeNodeAppend(arena, unit, parseMacro(&parser, attributes));
        } else if (parserAt(&parser, "{")) {
            RangeNode *emitted = rangeNodeCreate(arena, RangeNodeMain, path,
                                                 parser.current.line,
                                                 parser.current.column);
            emitted->a = parseBlock(&parser);
            emitted->b = attributes;
            rangeNodeAppend(arena, unit, emitted);
        } else if (parserAtKind(&parser, RangeTokenEnd)) {
            break;
        } else {
            parserFail(&parser, &parser.current,
                       "unexpected '%.*s' at top level",
                       (int)parser.current.length, parser.current.text);
        }
    }
    if (parser.failed) {
        snprintf(error, errorSize, "%s", parser.error);
        return NULL;
    }
    error[0] = '\0';
    unit->source = rangeArenaIntern(arena, source, length);
    return unit;
}
