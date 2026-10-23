/* Parser for the Range compiler. */
#ifndef RANGE_COMPILER_PARSER_H
#define RANGE_COMPILER_PARSER_H

#include "model.h"
#include "lexer.h"

typedef struct {
    RangeArena *arena;
    RangeLexer lexer;
    RangeToken current;
    RangeToken ahead;
    int hasAhead;
    const char *path;
    const char *source;
    char error[512];
    int failed;
    int conditionDepth;   /* trailing closures do not bind inside conditions */
    int genericDepth;     /* > terminates an unparenthesized generic RHS */
    int macroDepth;       /* macro bodies permit a bare implicit result */
    int functionTypes;    /* a function type may be written here: a parameter's type */
    int closureStatement; /* the next statement is a closure body's: it may be one comparison */
    size_t previousEnd;   /* end of last consumed token, excluding trivia */
} RangeParser;

RangeNode *rangeParseUnit(RangeArena *arena, const char *path,
                          const char *source, size_t length,
                          char *error, size_t errorSize);

#endif
