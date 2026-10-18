#include "lexer.h"

#include <stdarg.h>
#include <stdio.h>
#include <string.h>

/* Longest first: longer symbols must win over their prefixes. */
static const char *const RANGE_SYMBOLS[] = {
    "..<", "&&", "||", "==", "!=", "<=", ">=",
    "(", ")", "{", "}", "[", "]", ",", ":", ".", "@", "?", "|", "&",
    "+", "-", "*", "/", "%", "<", ">", "!", "=", "#", "$", NULL
};

void rangeLexerInit(RangeLexer *lexer, const char *path,
                    const char *source, size_t start, size_t end, int line)
{
    lexer->path = path;
    lexer->source = source;
    lexer->length = end;
    lexer->cursor = start;
    lexer->line = line;
    lexer->column = 1;
    lexer->error[0] = '\0';
    lexer->failed = 0;
}

void rangeLexerFail(RangeLexer *lexer, const RangeToken *token,
                    const char *format, ...)
{
    if (lexer->failed) return;
    char detail[384];
    va_list arguments;
    va_start(arguments, format);
    vsnprintf(detail, sizeof(detail), format, arguments);
    va_end(arguments);
    snprintf(lexer->error, sizeof(lexer->error), "%s:%d:%d: %s",
             lexer->path, token ? token->line : lexer->line,
             token ? token->column : lexer->column, detail);
    lexer->failed = 1;
}

static int isNameStart(int c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'; }
static int isNameByte(int c) { return isNameStart(c) || (c >= '0' && c <= '9'); }
static int isDigit(int c) { return c >= '0' && c <= '9'; }

static void advance(RangeLexer *lexer)
{
    if (lexer->source[lexer->cursor] == '\n') {
        lexer->line += 1;
        lexer->column = 1;
    } else {
        lexer->column += 1;
    }
    lexer->cursor += 1;
}

/* Skips the body of a quoted string, tracking escapes and nested
 * interpolation so that a quote inside \( ... ) does not end the literal. */
static int scanStringBody(RangeLexer *lexer, RangeToken *token)
{
    advance(lexer); /* opening quote */
    token->bodyStart = lexer->cursor;
    while (1) {
        if (lexer->cursor >= lexer->length) {
            rangeLexerFail(lexer, token, "unterminated string literal");
            return 0;
        }
        char c = lexer->source[lexer->cursor];
        if (c == '"') {
            token->bodyEnd = lexer->cursor;
            advance(lexer);
            return 1;
        }
        if (c == '\\') {
            if (lexer->cursor + 1 >= lexer->length) {
                rangeLexerFail(lexer, token, "unterminated escape in string literal");
                return 0;
            }
            if (lexer->source[lexer->cursor + 1] == '(') {
                advance(lexer);
                advance(lexer);
                int depth = 0;
                while (lexer->cursor < lexer->length) {
                    char inner = lexer->source[lexer->cursor];
                    if (inner == '(') {
                        depth += 1;
                    } else if (inner == ')') {
                        if (depth == 0) break;
                        depth -= 1;
                    } else if (inner == '"') {
                        advance(lexer);
                        while (lexer->cursor < lexer->length
                               && lexer->source[lexer->cursor] != '"') {
                            if (lexer->source[lexer->cursor] == '\\') advance(lexer);
                            advance(lexer);
                        }
                    }
                    advance(lexer);
                }
                if (lexer->cursor >= lexer->length) {
                    rangeLexerFail(lexer, token, "unterminated string interpolation");
                    return 0;
                }
                advance(lexer); /* closing paren */
                continue;
            }
            advance(lexer);
            advance(lexer);
            continue;
        }
        advance(lexer);
    }
}

int rangeLexerNext(RangeLexer *lexer, RangeToken *token)
{
    memset(token, 0, sizeof(*token));
    while (lexer->cursor < lexer->length) {
        char c = lexer->source[lexer->cursor];
        if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
            advance(lexer);
            continue;
        }
        if (c == '/' && lexer->cursor + 1 < lexer->length
            && lexer->source[lexer->cursor + 1] == '/') {
            while (lexer->cursor < lexer->length
                   && lexer->source[lexer->cursor] != '\n') {
                advance(lexer);
            }
            continue;
        }
        break;
    }

    token->line = lexer->line;
    token->column = lexer->column;
    token->offset = lexer->cursor;
    token->text = lexer->source + lexer->cursor;

    if (lexer->cursor >= lexer->length) {
        token->kind = RangeTokenEnd;
        token->length = 0;
        return 1;
    }

    char c = lexer->source[lexer->cursor];

    if (c == '"') {
        token->kind = RangeTokenString;
        if (!scanStringBody(lexer, token)) return 0;
        token->length = lexer->cursor - token->offset;
        return 1;
    }

    if (isDigit(c)) {
        token->kind = RangeTokenInteger;
        /* `0..<n`: a '.' followed by '.' begins an operator, not a fraction. */
        while (lexer->cursor < lexer->length
               && (isDigit(lexer->source[lexer->cursor])
                   || (lexer->source[lexer->cursor] == '.'
                       && !(lexer->cursor + 1 < lexer->length
                            && lexer->source[lexer->cursor + 1] == '.')))) {
            advance(lexer);
        }
        token->length = lexer->cursor - token->offset;
        return 1;
    }

    if (isNameStart(c)) {
        token->kind = RangeTokenName;
        while (lexer->cursor < lexer->length
               && isNameByte(lexer->source[lexer->cursor])) {
            advance(lexer);
        }
        token->length = lexer->cursor - token->offset;
        return 1;
    }

    for (size_t index = 0; RANGE_SYMBOLS[index] != NULL; ++index) {
        size_t width = strlen(RANGE_SYMBOLS[index]);
        if (lexer->cursor + width <= lexer->length
            && memcmp(lexer->source + lexer->cursor, RANGE_SYMBOLS[index], width) == 0) {
            token->kind = RangeTokenSymbol;
            for (size_t step = 0; step < width; ++step) advance(lexer);
            token->length = width;
            return 1;
        }
    }

    rangeLexerFail(lexer, token, "unexpected character '%c'", c);
    return 0;
}

int rangeTokenIs(const RangeToken *token, const char *text)
{
    size_t width = strlen(text);
    return token->length == width && memcmp(token->text, text, width) == 0;
}
