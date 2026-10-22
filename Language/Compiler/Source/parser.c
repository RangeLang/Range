#include "parser.h"
#include <errno.h>
#include <ctype.h>

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Binary operator precedence, loosest first. As in Swift, `..<` forms an
 * interval below arithmetic and above comparison, and does not chain. */
static const char *const RANGE_PRECEDENCE[][7] = {
    {"||", NULL},
    {"&&", NULL},
    {"=", "!=", "<", ">", "<=", ">=", NULL},
    {"..<", NULL},
    {"+", "-", NULL},
    {"*", "/", "%", NULL}
};
#define RANGE_PRECEDENCE_LEVELS \
    ((int)(sizeof(RANGE_PRECEDENCE) / sizeof(RANGE_PRECEDENCE[0])))
/* The level of `..<`, and of arithmetic: a pattern's value is arithmetic. */
#define RANGE_INTERVAL_LEVEL 3
#define RANGE_ARITHMETIC_LEVEL 4

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

/* Items of a list are separated by `,`, with none after the last: after an
 * item, the list closes or a comma and another item follow. */
static void parseSeparator(RangeParser *parser, const char *close, const char *what)
{
    if (parser->failed || rangeTokenIs(&parser->current, close)) return;
    if (!rangeTokenIs(&parser->current, ",")) {
        parserFail(parser, &parser->current, "expected ',' between %s or '%s', found '%.*s'",
                   what, close, (int)parser->current.length, parser->current.text);
        return;
    }
    parserAdvance(parser);
    if (rangeTokenIs(&parser->current, close))
        parserFail(parser, &parser->current, "no ',' after the last of the %s", what);
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
static int parseDeclaration(RangeParser *parser, RangeNode *owner);
static RangeNode *parseConstruct(RangeParser *parser, RangeNode *attributes);
static RangeNode *parseEnum(RangeParser *parser, RangeNode *attributes);
static RangeNode *parseSwitch(RangeParser *parser, int value);
static int rejectSelector(RangeParser *parser);

/* ---- types ---------------------------------------------------------- */

/* Reads a type position, returning the interned name and setting *many when
 * the position is a collection. An empty name means an untyped @many. Any other
 * @name is a macro type: declarations that applied that macro. */
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
        } else if (ahead->kind == RangeTokenName) {
            parserAdvance(parser);
            const char *name = parserExpectName(parser);
            *flags |= RangeFlagMacroType;
            if (parserAt(parser, "?")) { parserAdvance(parser); *flags |= RangeFlagOptional; }
            return name;
        }
    }
    const char *name = parserExpectName(parser);
    /* A nested declaration is named through its owners: Outer.Inner. */
    while (parserAt(parser, ".") && parserPeek(parser)->kind == RangeTokenName) {
        parserAdvance(parser);
        const char *inner = parserExpectName(parser);
        size_t length = strlen(name) + strlen(inner) + 2;
        char *path = rangeArenaAllocate(parser->arena, length);
        snprintf(path, length, "%s.%s", name, inner);
        name = path;
    }
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
 * initialiser. `let x: Int(0)` is typed; `let m: #members.filter(...)` and
 * `let author: "George"` place the initialising expression in that position. */
static int atTypePosition(RangeParser *parser)
{
    if (parser->current.kind == RangeTokenName) {
        if (parserAt(parser,"true") || parserAt(parser,"false")) return 0;
        // `let x: switch c { … }` is a value; a removed selector is reported there.
        static const char *const selectors[] = {"switch", "if", "guard", "else", NULL};
        for (size_t i = 0; selectors[i]; ++i) if (parserAt(parser, selectors[i])) return 0;
        // `let s: bag.snapshot()` and `let n: a + 1` are expressions; a `<`
        // after the name stays a generic list, as in `Array<Int>`.
        static const char *const expression[] = {".", "+", "-", "*", "/", "%", "=", "!=", "<=", ">=", "&&", "||", ">", NULL};
        const RangeToken *ahead = parserPeek(parser);
        for (size_t i = 0; expression[i]; ++i) if (rangeTokenIs(ahead, expression[i])) return 0;
        // `let v: Int(2) + 1` and `let v: f(n: 1) = 1` are expressions: skip
        // the name, any generic list and argument list, and look for an
        // operator after them.
        RangeParser probe = *parser;
        parserAdvance(&probe);
        const char *const groups[][2] = {{"<", ">"}, {"(", ")"}};
        for (size_t g = 0; g < 2; ++g) {
            if (!parserAt(&probe, groups[g][0])) continue;
            int depth = 0;
            do {
                if (parserAt(&probe, groups[g][0])) ++depth;
                else if (parserAt(&probe, groups[g][1])) --depth;
                // A `<` that never closes before a brace is a comparison.
                else if (g == 0 && (parserAt(&probe, "{") || parserAt(&probe, "}"))) return 1;
                parserAdvance(&probe);
            } while (depth > 0 && !probe.failed && probe.current.kind != RangeTokenEnd);
            if (depth > 0) return 1;
        }
        for (size_t i = 0; expression[i]; ++i) if (parserAt(&probe, expression[i])) return 0;
        if (parserAt(&probe, "<") || parserAt(&probe, "..<")) return 0;
        // `let none: Int?.absent` is a case of the optional type.
        if (parserAt(&probe, "?") && rangeTokenIs(parserPeek(&probe), ".")) return 0;
        return 1;
    }
    if (!parserAt(parser, "@")) return 0;
    return parserPeek(parser)->kind == RangeTokenName;
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
        } else if (strcmp(attribute->name, "builtin") == 0
                   && (parserAt(parser, "<") || parserAt(parser, "("))) {
            /* The declaration's own name selects the compiler primitive. */
            parserFail(parser, &parser->current, "@builtin takes no arguments; the declaration name selects the primitive");
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

/* The declaring keyword is the node kind: let, state, derived, or binding. */
static int valueDeclarationKind(RangeParser *parser, RangeNodeKind *kind)
{
    if (parserAt(parser, "let")) *kind = RangeNodeLet;
    else if (parserAt(parser, "state")) *kind = RangeNodeState;
    else if (parserAt(parser, "derived")) *kind = RangeNodeDerived;
    else if (parserAt(parser, "binding")) *kind = RangeNodeBinding;
    else return 0;
    return 1;
}

static RangeNode *parseString(RangeParser *parser)
{
    RangeNode *node = parserNode(parser, RangeNodeString);
    RangeToken token = parser->current;
    parserAdvance(parser);
    /* The quoted source spelling selects the literal's Core construct. */
    node->spanStart = token.offset;
    node->spanEnd = token.offset + token.length;

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
        parseSeparator(parser, ")", "arguments");
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
        if (typePosition && (parserAt(parser, "@") || (parser->current.kind == RangeTokenName
            && !rangeTokenIs(parserPeek(parser), ":")))) {
            // Positional type arguments, including Array<Array<@member>>.
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
        parseSeparator(parser, ">", "generic arguments");
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
    if (probe.current.kind == RangeTokenName && rangeTokenIs(parserPeek(&probe), ":")) return 1;
    // Positional arguments, as in `Array<Int>()`: as in Swift, `<` opens a
    // generic list when a matching `>` follows with only type-like tokens
    // inside and `(` or `.` after it; otherwise it is a comparison.
    int depth = 1;
    while (depth > 0) {
        if (parserAt(&probe, "<")) ++depth;
        else if (parserAt(&probe, ">")) --depth;
        else if (!(probe.current.kind == RangeTokenName || probe.current.kind == RangeTokenInteger
                   || parserAt(&probe, ",") || parserAt(&probe, ".") || parserAt(&probe, "?")
                   || parserAt(&probe, ":"))) return 0;
        parserAdvance(&probe);
        if (probe.failed) return 0;
    }
    return parserAt(&probe, "(") || parserAt(&probe, ".");
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
            parserFail(parser, &token, "numeric literal exceeds the C parser's signed 64-bit storage; Range literal materialization is not implemented");
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
            /* #graph quotes ordinary top-level declarations; inside it, #name
             * splices a macro-time value and a bare name resolves where the
             * code lands. */
            if (strcmp(node->name, "graph") != 0) {
                parserFail(parser, &parser->current, "only #graph opens emitted code");
                return node;
            }
            RangeNode *emission = parserNode(parser, RangeNodeEmission);
            emission->a = node;
            emission->b = parserNode(parser, RangeNodeBlock);
            emission->b->name = "graph";
            parserExpect(parser, "{");
            while (!parser->failed && !parserAt(parser, "}")
                   && !parserAtKind(parser, RangeTokenEnd)) {
                if (!parseDeclaration(parser, emission->b)) break;
            }
            parserExpect(parser, "}");
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
    if (rejectSelector(parser)) return NULL;
    if (parserAt(parser, "switch")) return parseSwitch(parser, 1);
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
            value->generics = parseGenericArguments(parser, 1);
            continue;
        }
        if (value && value->kind == RangeNodeName && !(value->flags & RangeFlagOptional)
            && parserAt(parser, "?") && rangeTokenIs(parserPeek(parser), ".")) {
            /* `Int?.absent`: a case of the optional type, as in a type position. */
            parserAdvance(parser);
            value->flags |= RangeFlagOptional;
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
            /* Only a `{ name in` block is a closure; `switch x.y {` is not. */
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
        if (level == RANGE_INTERVAL_LEVEL) {
            if (parserAt(parser, "..<"))
                parserFail(parser, &parser->current, "'..<' does not chain; parenthesize one interval");
            break;
        }
    }
    return left;
}

/* ---- patterns -------------------------------------------------------- */

static const char *const RANGE_RELATIONS[] = {"<", ">", "<=", ">=", "=", "!=", NULL};

/* An arm's label, and each payload sub-pattern of a case:
 *   _                 any value
 *   let name          any value, bound to name: a Let collected into `bindings`
 *   .case, .case(…)   a case of the subject's type; one sub-pattern per payload field
 *   200, -1, "quit"   a literal, compared with `=`
 *   < 0, = limit      the subject type's operator applied with the operand
 * A label never starts with a name: `.name` is a case, and `= name` compares
 * with a value. */
static RangeNode *parsePattern(RangeParser *parser, RangeNode *bindings)
{
    if (parser->failed) return NULL;
    RangeNode *pattern = parserNode(parser, RangeNodePattern);
    if (parserAt(parser, "_")) {
        parserAdvance(parser);
        pattern->integer = RangePatternAny;
        return pattern;
    }
    if (parserAt(parser, "let")) {
        parserAdvance(parser);
        RangeNode *binding = parserNode(parser, RangeNodeLet);
        binding->name = parserExpectName(parser);
        pattern->integer = RangePatternBind;
        pattern->a = binding;
        rangeNodeAppend(parser->arena, bindings, binding);
        return pattern;
    }
    for (size_t i = 0; RANGE_RELATIONS[i]; ++i)
        if (parserAt(parser, RANGE_RELATIONS[i])) {
            pattern->integer = RangePatternRelation;
            pattern->name = RANGE_RELATIONS[i];
            parserAdvance(parser);
            pattern->a = parseExpression(parser, RANGE_ARITHMETIC_LEVEL);
            return pattern;
        }
    if (parserAt(parser, ".")) {
        pattern->integer = RangePatternCase;
        parserAdvance(parser);
        pattern->name = parserExpectName(parser);
        if (parserAt(parser, "(")) {
            pattern->flags |= RangeFlagApplication;
            parserAdvance(parser);
            while (!parser->failed && !parserAt(parser, ")")) {
                RangeNode *argument = parserNode(parser, RangeNodeArgument);
                if (parser->current.kind == RangeTokenName && rangeTokenIs(parserPeek(parser), ":")) {
                    argument->name = parserExpectName(parser);
                    parserExpect(parser, ":");
                }
                argument->a = parsePattern(parser, bindings);
                rangeNodeAppend(parser->arena, pattern, argument);
                parseSeparator(parser, ")", "payload patterns");
            }
            parserExpect(parser, ")");
        }
        return pattern;
    }
    const RangeToken *token = &parser->current;
    if (parserAt(parser, "true") || parserAt(parser, "false")) {
        parserFail(parser, token, "a Bool case is written .%.*s; a label without a dot is a literal to compare",
                   (int)token->length, token->text);
        return NULL;
    }
    if (token->kind == RangeTokenName) {
        if (rangeTokenIs(parserPeek(parser), "."))
            parserFail(parser, token, "a label does not start with a name: write .case for a case of the subject's type, "
                       "without the type, or '= %.*s…' to compare with a value", (int)token->length, token->text);
        else
            parserFail(parser, token, "a bare name is not a label: write .%.*s for a case of the subject's type, "
                       "or '= %.*s' to compare with a value", (int)token->length, token->text, (int)token->length, token->text);
        return NULL;
    }
    if (token->kind == RangeTokenInteger || token->kind == RangeTokenString) {
        pattern->integer = RangePatternValue;
        pattern->a = parsePrimary(parser);
        return pattern;
    }
    if (parserAt(parser, "-") && parserPeek(parser)->kind == RangeTokenInteger) {
        pattern->integer = RangePatternValue;
        pattern->a = parserNode(parser, RangeNodeUnary);
        pattern->a->name = "-";
        parserAdvance(parser);
        pattern->a->a = parsePrimary(parser);
        return pattern;
    }
    parserFail(parser, token, "expected a switch label: .case, a literal, _, let name, or a relation such as < 0 or = value; found '%.*s'",
               (int)token->length, token->text);
    return NULL;
}

/* ---- statements ------------------------------------------------------ */

/* `switch` is the only selector: if, else, and guard are not Range. */
static int rejectSelector(RangeParser *parser)
{
    if (parser->failed || parser->current.kind != RangeTokenName) return 0;
    const char *message = NULL;
    if (parserAt(parser, "if")) {
        const RangeToken *ahead = parserPeek(parser);
        message = rangeTokenIs(ahead, "let")
            ? "Range has no 'if let'; use switch, e.g. switch value { .present(let x): …, .absent: {} }"
            : rangeTokenIs(ahead, "case")
            ? "Range has no 'if case'; use switch, e.g. switch value { .case(let x): …, default: {} }"
            : "Range has no 'if'; use switch, e.g. switch c { .true: …, .false: {} }";
    } else if (parserAt(parser, "guard")) {
        const RangeToken *ahead = parserPeek(parser);
        message = rangeTokenIs(ahead, "let")
            ? "Range has no 'guard let'; use a switch expression whose other arm diverges, e.g. let x: switch value { .present(let x): x, .absent: { return } }"
            : rangeTokenIs(ahead, "case")
            ? "Range has no 'guard case'; use switch, e.g. let x: switch value { .case(let x): x, default: { return } }"
            : "Range has no 'guard'; use switch, e.g. switch c { .false: return, .true: {} }";
    } else if (parserAt(parser, "else")) {
        message = "Range has no 'else'; use switch, whose arms handle each case, e.g. switch c { .true: …, .false: … }";
    } else return 0;
    parserFail(parser, &parser->current, "%s", message);
    return 1;
}

/* One arm's body. In a statement switch: a block (`{}` does nothing), or one
 * statement: return, break, continue, an assignment, an effect such as
 * @print(…), a switch, or an expression. In a switch expression: an
 * expression, which the arm yields (its a), or a block, or one return, break,
 * continue, or effect, which must diverge; `{}` and assignments yield nothing. */
static void parseArm(RangeParser *parser, RangeNode *entry, int value)
{
    RangeNode *body = parserNode(parser, RangeNodeBlock);
    entry->b = body;
    if (parserAt(parser, "{")) {
        RangeToken open = parser->current;
        entry->b = parseBlock(parser);
        if (value && !parser->failed && !entry->b->itemCount)
            parserFail(parser, &open, "'{}' does nothing, so it is not an arm of a switch expression; "
                       "yield a value, or diverge with return, break, continue, or @diagnostic");
        return;
    }
    static const char *const blocks[] = {"let", "state", "derived", "binding", "while", "for", "function", NULL};
    for (size_t i = 0; blocks[i]; ++i)
        if (parserAt(parser, blocks[i])) {
            parserFail(parser, &parser->current, "'%s' is not an arm body by itself; write the arm as a block, { %s … }",
                       blocks[i], blocks[i]);
            return;
        }
    if (parserAt(parser, "return") || parserAt(parser, "break") || parserAt(parser, "continue")
        || parserAt(parser, "@") || (!value && parserAt(parser, "switch"))) {
        RangeNode *statement = parseStatement(parser);
        if (statement) rangeNodeAppend(parser->arena, body, statement);
        return;
    }
    RangeNode *expression = parseExpression(parser, 0);
    if (parserAt(parser, ":")) {
        if (value) {
            parserFail(parser, &parser->current, "an assignment yields no value; an arm of a switch expression yields its value or diverges");
            return;
        }
        RangeNode *assign = parserNode(parser, RangeNodeAssign);
        parserAdvance(parser);
        assign->a = expression;
        assign->b = parseExpression(parser, 0);
        rangeNodeAppend(parser->arena, body, assign);
        return;
    }
    if (value) { entry->a = expression; return; }
    RangeNode *statement = parserNode(parser, RangeNodeExpressionStatement);
    statement->a = expression;
    rangeNodeAppend(parser->arena, body, statement);
}

/* `switch subject { label: body, … }`: arms are separated by `,`, with none
 * after the last. A label is `default`, which comes last, or patterns joined
 * by `|`, each binding the same names, then an optional `where` guard for the
 * arm. The first pattern's bindings block is the arm's (its c). As a
 * statement the switch runs its arm; as an expression (RangeFlagValue) it is
 * the value its arm yields. */
static RangeNode *parseSwitch(RangeParser *parser, int value)
{
    RangeNode *node = parserNode(parser, RangeNodeSwitch);
    if (value) node->flags |= RangeFlagValue;
    parserExpect(parser, "switch");
    parser->conditionDepth += 1;
    node->a = parseExpression(parser, 0);
    parser->conditionDepth -= 1;
    int outerCondition = parser->conditionDepth, outerGeneric = parser->genericDepth;
    parser->conditionDepth = 0;
    parser->genericDepth = 0;
    parserExpect(parser, "{");
    while (!parser->failed && !parserAt(parser, "}") && !parserAtKind(parser, RangeTokenEnd)) {
        RangeNode *entry = parserNode(parser, RangeNodeSwitchCase);
        if (parserAt(parser, "case")) {
            parserFail(parser, &parser->current, "switch arms take no 'case'; the pattern is the arm's label, e.g. .east | .west: …");
            break;
        }
        if (parserAt(parser, "default") && rangeTokenIs(parserPeek(parser), ":")) {
            parserAdvance(parser);
            entry->flags |= RangeFlagLiteral; /* marks the default arm */
        } else {
            for (;;) {
                RangeNode *bindings = parserNode(parser, RangeNodeBlock);
                bindings->name = "bindings";
                RangeNode *pattern = parsePattern(parser, bindings);
                if (!pattern) break;
                pattern->c = bindings;
                if (!entry->c) entry->c = bindings;
                rangeNodeAppend(parser->arena, entry, pattern);
                if (!parserAt(parser, "|")) break;
                parserAdvance(parser);
            }
            if (parserAt(parser, "where")) {
                parserAdvance(parser);
                RangeNode *guard = parseExpression(parser, 0);
                for (size_t i = 0; i < entry->itemCount; ++i) entry->items[i]->b = guard;
            }
        }
        parserExpect(parser, ":");
        parseArm(parser, entry, value);
        rangeNodeAppend(parser->arena, node, entry);
        if (parser->failed || parserAt(parser, "}")) break;
        if (!parserAt(parser, ",")) {
            parserFail(parser, &parser->current, "expected ',' between switch arms or '}', found '%.*s'",
                       (int)parser->current.length, parser->current.text);
            break;
        }
        parserAdvance(parser);
        if (parserAt(parser, "}")) parserFail(parser, &parser->current, "no ',' after the last switch arm");
    }
    parserExpect(parser, "}");
    parser->conditionDepth = outerCondition;
    parser->genericDepth = outerGeneric;
    return node;
}

static RangeNode *forNode(RangeParser *parser, RangeNode *at, RangeNodeKind kind, const char *name)
{
    RangeNode *node = rangeNodeCreate(parser->arena, kind, at->path, at->line, at->column);
    node->name = name ? rangeArenaIntern(parser->arena, name, strlen(name)) : NULL;
    return node;
}

static RangeNode *forArgument(RangeParser *parser, RangeNode *at, const char *label, RangeNode *value)
{
    RangeNode *argument = forNode(parser, at, RangeNodeArgument, label);
    argument->a = value;
    return argument;
}

static RangeNode *forInteger(RangeParser *parser, RangeNode *at, long long value)
{
    RangeNode *literal = forNode(parser, at, RangeNodeInteger, value ? "1" : "0");
    literal->integer = value;
    return literal;
}

/* The one switch `for` lowers to: `switch subject { pattern where guard: body,
 * default: otherwise }`, its default written by the compiler. */
static RangeNode *forSwitch(RangeParser *parser, RangeNode *at, RangeNode *subject, RangeNode *pattern,
                            RangeNode *guard, RangeNode *body, RangeNode *otherwise)
{
    RangeNode *node = forNode(parser, at, RangeNodeSwitch, NULL);
    node->a = subject;
    RangeNode *entry = forNode(parser, at, RangeNodeSwitchCase, NULL);
    pattern->b = guard;
    entry->c = pattern->c;
    rangeNodeAppend(parser->arena, entry, pattern);
    entry->b = body;
    rangeNodeAppend(parser->arena, node, entry);
    RangeNode *rest = forNode(parser, at, RangeNodeSwitchCase, NULL);
    rest->flags |= RangeFlagLiteral | RangeFlagImplicit;
    rest->b = otherwise;
    rangeNodeAppend(parser->arena, node, rest);
    return node;
}

/* `for pattern in sequence where guard { body }` calls the function the
 * sequence's type declares with @iteration, at positions 0, 1, 2, … until it
 * returns absence. A pattern is a name, `_`, or, after a leading dot, a case
 * pattern: `for .group(let items) in shapes where items.count > 3 { … }`.
 * The loop is written in ordinary nodes; the names it adds contain a space,
 * so source cannot name them:
 *
 *   let <for sequence>: sequence     (a copy: changing the sequence in the
 *   state <for index>: 0              body does not change the iteration)
 *   while {                          (a while without a condition)
 *       switch <for sequence>.<@iteration>(<position>: <for index>) {
 *           <present>(let element): {
 *               <for index>: <for index> + 1
 *               switch element { pattern where guard: body, default: {} }
 *           },
 *           default: break
 *       }
 *   }
 *
 * <present> is the payload case of the optional the function returns; the
 * inner switch is written only for a case pattern or a guard. The parser
 * knows no member or case names: the call's member and label are left empty,
 * and the type checker fills them from the @iteration function of the
 * sequence's type once that type is known. The element binding is a let, so a
 * loop variable cannot be assigned; the position advances before the body, so
 * `continue` advances it too. */
static RangeNode *parseFor(RangeParser *parser)
{
    RangeNode *node = parserNode(parser, RangeNodeFor);
    parserExpect(parser, "for");
    RangeNode *pattern = NULL;
    const char *element = "for element";
    if (parserAt(parser, "case")) {
        parserFail(parser, &parser->current, "'for' takes no 'case'; write the case pattern after 'for', e.g. for .group(let items) in shapes");
        return node;
    }
    if (parserAt(parser, ".")) {
        RangeNode *bindings = parserNode(parser, RangeNodeBlock);
        bindings->name = "bindings";
        pattern = parsePattern(parser, bindings);
        if (!pattern) return node;
        pattern->c = bindings;
    } else if (parserAt(parser, "_")) {
        parserAdvance(parser);
    } else element = parserExpectName(parser);
    parserExpect(parser, "in");
    parser->conditionDepth += 1;
    RangeNode *sequence = parseExpression(parser, 0);
    RangeNode *where = NULL;
    if (parserAt(parser, "where")) {
        parserAdvance(parser);
        where = parseExpression(parser, 0);
    }
    parser->conditionDepth -= 1;
    RangeNode *body = parseBlock(parser);
    if (parser->failed) return node;

    RangeNode *loop = forNode(parser, node, RangeNodeBlock, NULL);
    RangeNode *copy = forNode(parser, node, RangeNodeLet, "for sequence");
    rangeNodeAppend(parser->arena, copy, forArgument(parser, node, NULL, sequence));
    RangeNode *index = forNode(parser, node, RangeNodeState, "for index");
    rangeNodeAppend(parser->arena, index, forArgument(parser, node, NULL, forInteger(parser, node, 0)));
    rangeNodeAppend(parser->arena, loop, copy);
    rangeNodeAppend(parser->arena, loop, index);

    RangeNode *repeat = forNode(parser, node, RangeNodeWhile, NULL);
    repeat->b = forNode(parser, node, RangeNodeBlock, NULL);

    /* The member and label are filled in by the type checker. */
    RangeNode *next = forNode(parser, node, RangeNodeCall, NULL);
    next->a = forNode(parser, node, RangeNodeMemberAccess, NULL);
    next->a->a = forNode(parser, node, RangeNodeName, "for sequence");
    rangeNodeAppend(parser->arena, next, forArgument(parser, node, NULL, forNode(parser, node, RangeNodeName, "for index")));

    RangeNode *bound = forNode(parser, node, RangeNodePattern, NULL);
    bound->integer = RangePatternPresent;
    bound->c = forNode(parser, node, RangeNodeBlock, "bindings");
    RangeNode *value = forNode(parser, node, RangeNodeLet, NULL);
    value->name = element;
    rangeNodeAppend(parser->arena, bound->c, value);
    bound->a = value;
    RangeNode *found = forNode(parser, node, RangeNodeBlock, NULL);
    RangeNode *end = forNode(parser, node, RangeNodeBlock, NULL);
    rangeNodeAppend(parser->arena, end, forNode(parser, node, RangeNodeBreak, NULL));
    rangeNodeAppend(parser->arena, repeat->b, forSwitch(parser, node, next, bound, NULL, found, end));

    RangeNode *step = forNode(parser, node, RangeNodeAssign, NULL);
    step->a = forNode(parser, node, RangeNodeName, "for index");
    step->b = forNode(parser, node, RangeNodeBinary, "+");
    step->b->a = forNode(parser, node, RangeNodeName, "for index");
    step->b->b = forInteger(parser, node, 1);
    rangeNodeAppend(parser->arena, found, step);

    RangeNode *run = body;
    if (pattern || where) {
        /* Only the elements that match the pattern and the guard run the body. */
        if (!pattern) {
            pattern = forNode(parser, node, RangeNodePattern, NULL);
            pattern->integer = RangePatternAny;
        }
        run = forSwitch(parser, node, forNode(parser, node, RangeNodeName, element), pattern, where, body,
                        forNode(parser, node, RangeNodeBlock, NULL));
    }
    rangeNodeAppend(parser->arena, found, run);
    rangeNodeAppend(parser->arena, loop, repeat);
    node->a = loop;
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
        RangeNodeKind declared;
        if (parserAt(parser, "}") || parserAtKind(parser, RangeTokenEnd)
            || !(valueDeclarationKind(parser, &declared) || parserAt(parser, "function")
                 || parserAt(parser, "construct"))) {
            /* Attributes annotate declarations; before anything else they are
             * effects, like @print(…), and the next statement stands alone.
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
            if (rangeNodeDeclaresValue(statement->kind) && attributesContain(attributes, "many")) {
                statement->flags |= RangeFlagMany;
            }
        }
        return statement;
    }
    if (parserAt(parser, "let") || parserAt(parser, "state")) {
        RangeNode *node = parserNode(parser, parserAt(parser, "state") ? RangeNodeState : RangeNodeLet);
        parserAdvance(parser);
        node->name = parserExpectName(parser);
        if (!parserAt(parser, ":") && node->kind == RangeNodeLet) return node;
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
        }
        return node;
    }
    if (rejectSelector(parser)) return NULL;
    if (parserAt(parser, "switch")) return parseSwitch(parser, 0);
    if (parserAt(parser, "extension")) {
        parserFail(parser, &parser->current, "extension is a top-level declaration");
        return NULL;
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
    if (parserAt(parser, "for")) return parseFor(parser);
    if (parserAt(parser, "break") || parserAt(parser, "continue")) {
        RangeNode *node = parserNode(parser, parserAt(parser, "break") ? RangeNodeBreak : RangeNodeContinue);
        parserAdvance(parser);
        return node;
    }
    if (parserAt(parser,"return")) {
        RangeNode *node = parserNode(parser,RangeNodeReturn);
        parserAdvance(parser);
        /* In a switch arm, `return` may end before the next arm's `,`. */
        if (!parserAt(parser,"}") && !parserAt(parser,",")) node->a = parseExpression(parser,0);
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

/* A value generic is a Let, `let name: rhs`, whose RHS is a parsed
 * expression: a type requirement, default literal, or ordinary application.
 * A type parameter is a bare name and its own node kind. */
static RangeNode *parseGenericMembers(RangeParser *parser)
{
    RangeNode *list = parserNode(parser, RangeNodeBlock);
    list->name = "genericMembers";
    list->spanStart = parser->current.offset;
    parserExpect(parser, "<");
    if (parserAt(parser, ">")) parserFail(parser, &parser->current, "generic members cannot be empty");
    while (!parser->failed && !parserAt(parser, ">")) {
        RangeNode *member = parserNode(parser, RangeNodeLet);
        int value = parserAt(parser, "let");
        if (value) parserAdvance(parser);
        member->name = parserExpectName(parser);
        if (strcmp(member->name, "_") == 0)
            parserFail(parser, &parser->current, "generic members require a single named identity");
        if (!value) {
            member->kind = RangeNodeTypeParameter;
            if (parserAt(parser, ":"))
                parserFail(parser, &parser->current, "value generics require explicit let");
            rangeNodeAppend(parser->arena, list, member);
            parseSeparator(parser, ">", "generic members");
            continue;
        }
        parserExpect(parser, ":");
        member->rhsStart = parser->current.offset;
        parser->genericDepth += 1;
        member->a = parseExpression(parser, 0);
        parser->genericDepth -= 1;
        member->rhsEnd = parser->previousEnd;
        /* `<let n: Int>` names the value's type: a requirement, written at
         * each use, as a member's `let n: Int` is. `<let n: 2>` is a default. */
        if (member->a && member->a->kind == RangeNodeName) {
            member->typeName = member->a->name;
            member->generics = member->a->generics;
            if (!member->generics) member->rhsReference = member->a;
            member->a = NULL;
        }
        rangeNodeAppend(parser->arena, list, member);
        parseSeparator(parser, ">", "generic members");
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
    /* `function +(let other: T): T` declares the function `a + b` calls on
     * a's type, and `function -(): T` the one `-a` calls: the operator symbol
     * is the function's name. `!=` is the negation of `=` and `..<` the
     * @interval sugar, so neither is declared. */
    static const char *const declarable[] = {"=", "+", "-", "*", "/", "%", "<", ">", "<=", ">=", "!", "&&", "||", NULL};
    if (parser->current.kind == RangeTokenSymbol && !parserAt(parser, "(")) {
        for (size_t i = 0; declarable[i] && !node->name; ++i)
            if (parserAt(parser, declarable[i])) node->name = rangeArenaIntern(parser->arena, declarable[i], strlen(declarable[i]));
        if (!node->name) {
            parserFail(parser, &parser->current,
                       parserAt(parser, "!=") ? "operator '!=' cannot be declared: it is the negation of '='"
                       : "operator '%.*s' cannot be declared as a function",
                       (int)parser->current.length, parser->current.text);
            return node;
        }
        parserAdvance(parser);
    } else node->name = parserExpectName(parser);
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
        if (parser->macroDepth && parserAt(parser, "#")) {
            /* Inside a macro's #graph, `let other: #name` splices the type. */
            parameter->b = parsePrimary(parser);
            rangeNodeAppend(parser->arena, node, parameter);
            parseSeparator(parser, ")", "parameters");
            continue;
        }
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
        parseSeparator(parser, ")", "parameters");
    }
    parserExpect(parser, ")");
    if (parserAt(parser, ":") && parser->macroDepth && rangeTokenIs(parserPeek(parser), "#")) {
        /* Inside a macro's #graph, `): #name` splices the result type. */
        parserAdvance(parser);
        parser->conditionDepth += 1; /* a body may follow: `#name {` is not #graph */
        node->b = parsePrimary(parser);
        parser->conditionDepth -= 1;
    } else if (parserAt(parser, ":")) {
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

/* Members, functions, and nested constructs; extensions share this body.
 * receiver names the owner of member functions, when known while parsing. */
static void parseConstructBody(RangeParser *parser, RangeNode *node, const char *receiver)
{
    const char *owner = receiver ? receiver : "extension";
    parserExpect(parser, "{");
    while (!parser->failed && !parserAt(parser, "}")) {
        RangeNode *memberAttributes = parseAttributes(parser);
        if (parserAt(parser, "function")) {
            rangeNodeAppend(parser->arena, node,
                            parseFunction(parser, memberAttributes, receiver));
            continue;
        }
        if (parserAt(parser, "construct")) {
            rangeNodeAppend(parser->arena, node,
                            parseConstruct(parser, memberAttributes));
            continue;
        }
        if (parserAt(parser, "enum")) {
            rangeNodeAppend(parser->arena, node, parseEnum(parser, memberAttributes));
            continue;
        }
        RangeNodeKind kind;
        if (!valueDeclarationKind(parser, &kind)) {
            parserFail(parser, &parser->current,
                       "expected a member declaration in construct %s, found '%.*s'",
                       owner, (int)parser->current.length, parser->current.text);
            break;
        }
        RangeNode *member = parserNode(parser, kind);
        member->c = memberAttributes;
        if (attributesContain(memberAttributes, "many")) member->flags |= RangeFlagMany;
        parserAdvance(parser);
        member->name = parserExpectName(parser);
        if (!parserAt(parser, ":") && kind == RangeNodeLet) {
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
        if (parserAt(parser, "{")) {
            member->a = parseBlock(parser);
        } else if (parserAt(parser, "(")) {
            member->flags |= RangeFlagApplication;
            parseArgumentList(parser, member);
        }
        member->rhsEnd = parser->previousEnd;
        if (member->typeName && !member->a && !member->itemCount && !member->flags) {
            member->rhsReference = rangeNodeCreate(parser->arena, RangeNodeName,
                parser->path, rhsToken.line, rhsToken.column);
            member->rhsReference->name = member->typeName;
            member->rhsReference->generics = member->generics;
        }
        rangeNodeAppend(parser->arena, node, member);
    }
    parserExpect(parser, "}");
}

static RangeNode *parseConstruct(RangeParser *parser, RangeNode *attributes)
{
    RangeNode *node = parserNode(parser, RangeNodeConstruct);
    parserExpect(parser, "construct");
    node->name = parserExpectName(parser);
    if (parserAt(parser, "<")) node->generics = parseGenericMembers(parser);
    node->c = attributes;
    if (parserAt(parser, "{")) parseConstructBody(parser, node, node->name);
    return node;
}

/* `extension Name { … }` adds construct members to the declaration it names.
 * Inside #graph, the subject may be a splice such as `#name`. Macro
 * applications written on the extension apply to that declaration. */
static RangeNode *parseExtension(RangeParser *parser, RangeNode *attributes)
{
    RangeNode *node = parserNode(parser, RangeNodeExtension);
    node->c = attributes;
    parserExpect(parser, "extension");
    parser->conditionDepth += 1;
    node->a = parseExpression(parser, 0);
    parser->conditionDepth -= 1;
    RangeNode *root = node->a;
    while (root && (root->kind == RangeNodeMemberAccess || root->kind == RangeNodeCall)) root = root->a;
    if (node->a && node->a->kind == RangeNodeName && !node->a->generics) node->name = node->a->name;
    else if (!root || root->kind != RangeNodeEnvironment)
        parserFail(parser, &parser->current, "extension requires a declaration name");
    parseConstructBody(parser, node, node->name);
    return node;
}

/* `enum Name<Generics> { case a, b  case value(number: Int)  case present(Wrapped) }`.
 * Functions in the body are methods, as in a construct.
 * Each case carries its payload as Let fields: a labeled field is named by its
 * label, an unlabeled one by its position ("0", "1", …), as a Swift tuple
 * element is. Constructs and enums may nest among the cases. */
static RangeNode *parseEnum(RangeParser *parser, RangeNode *attributes)
{
    RangeNode *node = parserNode(parser, RangeNodeEnum);
    parserExpect(parser, "enum");
    node->name = parserExpectName(parser);
    if (parserAt(parser, "<")) node->generics = parseGenericMembers(parser);
    node->c = attributes;
    parserExpect(parser, "{");
    long long ordinal = 0;
    while (!parser->failed && !parserAt(parser, "}")) {
        RangeNode *memberAttributes = parseAttributes(parser);
        if (parserAt(parser, "construct")) {
            rangeNodeAppend(parser->arena, node, parseConstruct(parser, memberAttributes));
            continue;
        }
        if (parserAt(parser, "enum")) {
            rangeNodeAppend(parser->arena, node, parseEnum(parser, memberAttributes));
            continue;
        }
        if (parserAt(parser, "function")) {
            rangeNodeAppend(parser->arena, node, parseFunction(parser, memberAttributes, node->name));
            continue;
        }
        if (memberAttributes->itemCount)
            parserFail(parser, &parser->current, "enum cases do not take macro applications");
        if (!parserAt(parser, "case")) {
            parserFail(parser, &parser->current, "expected 'case' in enum %s, found '%.*s'",
                       node->name, (int)parser->current.length, parser->current.text);
            break;
        }
        parserAdvance(parser);
        for (;;) {
            RangeNode *entry = parserNode(parser, RangeNodeEnumCase);
            entry->name = parserExpectName(parser);
            entry->integer = ordinal++;
            if (parserAt(parser, "(")) {
                parserAdvance(parser);
                if (parserAt(parser, ")")) parserFail(parser, &parser->current, "a payload needs at least one field; omit the parentheses");
                while (!parser->failed && !parserAt(parser, ")")) {
                    RangeNode *field = parserNode(parser, RangeNodeLet);
                    if (parser->current.kind == RangeTokenName && rangeTokenIs(parserPeek(parser), ":")) {
                        field->name = parserExpectName(parser);
                        parserExpect(parser, ":");
                    } else {
                        char position[24];
                        snprintf(position, sizeof(position), "%zu", entry->itemCount);
                        field->name = rangeArenaIntern(parser->arena, position, strlen(position));
                    }
                    field->rhsStart = parser->current.offset;
                    int typeFlags = 0;
                    field->typeName = parseTypeName(parser, &typeFlags, &field->generics);
                    field->flags |= typeFlags;
                    field->rhsEnd = parser->previousEnd;
                    rangeNodeAppend(parser->arena, entry, field);
                    parseSeparator(parser, ")", "payload fields");
                }
                parserExpect(parser, ")");
            }
            rangeNodeAppend(parser->arena, node, entry);
            if (!parserAt(parser, ",")) break;
            parserAdvance(parser);
        }
    }
    parserExpect(parser, "}");
    return node;
}

/* Macro declarations are parsed in full: parameters with defaults, the target
 * and result type positions, and the body as a real block. Macro bodies are
 * compile-time programs: they may read #fields, emit #graph blocks, use $
 * templates, and end in a bare implicit result. Nothing here is retained as a
 * raw span. */
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
        parseSeparator(parser, ")", "parameters");
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

/* One top-level declaration. #graph blocks use the same loop, so emitted code
 * is ordinary file-scope Range code. Returns 0 when parsing stops. */
static int parseDeclaration(RangeParser *parser, RangeNode *owner)
{
    RangeNode *attributes = parseAttributes(parser);
    if (parserAt(parser, "construct")) {
        rangeNodeAppend(parser->arena, owner, parseConstruct(parser, attributes));
    } else if (parserAt(parser, "enum")) {
        rangeNodeAppend(parser->arena, owner, parseEnum(parser, attributes));
    } else if (parserAt(parser, "function")) {
        rangeNodeAppend(parser->arena, owner, parseFunction(parser, attributes, NULL));
    } else if (parserAt(parser, "macro")) {
        rangeNodeAppend(parser->arena, owner, parseMacro(parser, attributes));
    } else if (parserAt(parser, "extension")) {
        rangeNodeAppend(parser->arena, owner, parseExtension(parser, attributes));
    } else if (parserAt(parser, "{")) {
        RangeNode *emitted = parserNode(parser, RangeNodeMain);
        emitted->a = parseBlock(parser);
        emitted->b = attributes;
        rangeNodeAppend(parser->arena, owner, emitted);
    } else if (parserAtKind(parser, RangeTokenEnd)) {
        return 0;
    } else {
        parserFail(parser, &parser->current,
                   "unexpected '%.*s' at top level",
                   (int)parser->current.length, parser->current.text);
        return 0;
    }
    return !parser->failed;
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
        if (!parseDeclaration(&parser, unit)) break;
    }
    if (parser.failed) {
        snprintf(error, errorSize, "%s", parser.error);
        return NULL;
    }
    error[0] = '\0';
    unit->source = rangeArenaIntern(arena, source, length);
    return unit;
}
