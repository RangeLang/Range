/* The type checker: specializations and what typing finds, generics,
 * closures, narrowing, patterns, layout, mutation, and written code. */
#define _XOPEN_SOURCE 700
#include "compiler.h"
#include <ctype.h>
#include <limits.h>
#include <setjmp.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

/* ---- findings ----
 * What typing finds about a node lives beside it: in the node's own record,
 * or in the table of the specialization it was typed for, keyed by node: a
 * generic function's body for one specialization of the function, or a
 * generic construct's or enum's members, payload fields, and method bodies
 * for one specialization of the declaration. A key is
 * that specialization, or NULL for the node's own record. The table holds
 * only what typing found under the key; anything else reads the node's own. */
struct RangeFactTable { RangeNode **nodes; RangeFacts **facts; size_t capacity, count; };

static size_t factSlot(const struct RangeFactTable *table, const RangeNode *node)
{
    size_t mask = table->capacity - 1, at = ((uintptr_t)node >> 4) & mask;
    while (table->nodes[at] && table->nodes[at] != node) at = (at + 1) & mask;
    return at;
}

/* What typing found about `node` under `key`. */
RangeFacts *found(RangeNode *key, RangeNode *node)
{
    struct RangeFactTable *table = key ? key->keyed : NULL;
    if (!table) return &node->facts;
    size_t at = factSlot(table,node);
    return table->nodes[at] ? table->facts[at] : &node->facts;
}

/* ---- case tests ----
 * `phase.loading` and `phase.failed(let reason)` read a case off a value: a
 * Bool, true when the value holds that case. Inside the parentheses each
 * argument is a pattern for its payload field: `let x` binds it, `_` ignores
 * it, `.case(…)` tests it in turn, and any other expression is a value the
 * field must equal, by its type's `=`. Inside an enum's own functions a bare
 * case name tests the receiver. Once the subject is known to hold an enum
 * with that case, typing records beside the member access or call the
 * RangeNodeCaseTest that runs in its place: a the subject, b the case
 * pattern. */

static RangeNode *casePattern(RangeArena *arena, RangeNode *at, const char *name, RangeNode *call);

/* An argument of a case test, as the pattern it is. */
static RangeNode *argumentPattern(RangeArena *arena, RangeNode *value)
{
    if (value->kind == RangeNodePattern) return value;
    if (value->kind == RangeNodeCase) return casePattern(arena,value,value->name,NULL);
    if (value->kind == RangeNodeCall && value->a && value->a->kind == RangeNodeCase)
        return casePattern(arena,value,value->a->name,value);
    RangeNode *pattern = rangeNodeCreate(arena,RangeNodePattern,value->path,value->line,value->column);
    pattern->integer = RangePatternValue;
    pattern->a = value;
    return pattern;
}

static RangeNode *casePattern(RangeArena *arena, RangeNode *at, const char *name, RangeNode *call)
{
    RangeNode *pattern = rangeNodeCreate(arena,RangeNodePattern,at->path,at->line,at->column);
    pattern->integer = RangePatternCase;
    pattern->name = name;
    if (!call) return pattern;
    pattern->flags |= RangeFlagApplication;
    for (size_t i = 0; i < call->itemCount; ++i) {
        RangeNode *argument = rangeNodeCreate(arena,RangeNodeArgument,call->items[i]->path,call->items[i]->line,call->items[i]->column);
        argument->name = call->items[i]->name;
        argument->a = argumentPattern(arena,call->items[i]->a);
        rangeNodeAppend(arena,pattern,argument);
    }
    return pattern;
}

/* The case test the member access `subject.name`, the call
 * `subject.name(…)`, or the bare `name` or `name(…)` (subject flagged
 * implicit: the receiver) is, written beside it. */
static RangeNode *caseTest(RangeArena *arena, RangeNode *at, RangeNode *subject, const char *name, RangeNode *call)
{
    RangeNode *test = rangeNodeCreate(arena,RangeNodeCaseTest,at->path,at->line,at->column);
    test->a = subject;
    test->b = casePattern(arena,at,name,call);
    test->name = name;
    return test;
}

/* The receiver a bare case name tests, inside an enum's own functions. */
static RangeNode *receiverSubject(RangeArena *arena, RangeNode *at)
{
    RangeNode *subject = rangeNodeCreate(arena,RangeNodeName,at->path,at->line,at->column);
    subject->flags |= RangeFlagImplicit;
    return subject;
}

/* A label row as a coverage vector of `width` columns, one per subject: a
 * row pattern's items, or the one pattern; NULL, the default, is wild. */
void patternRow(RangeNode *row, RangeNode **vector, size_t width)
{
    for (size_t k = 0; k < width; ++k) vector[k] = NULL;
    if (!row) return;
    if (row->integer != RangePatternRow) { vector[0] = row; return; }
    for (size_t k = 0; k < width && k < row->itemCount; ++k) vector[k] = row->items[k];
}

static int useful(Typer *, RangeNode ***, size_t, RangeNode **, RangeNode **, size_t);

/* The combinations of the subjects' cases that no row covers, written as
 * '.on & .off' into missing; a subject that is not an enum is `_` there.
 * cases[k] declares subject k's cases, or is NULL. Returns how many. */
static size_t patternMissing(RangeArena *arena, Typer *typer, RangeNode ***rows, size_t count,
                             RangeNode **types, RangeNode **cases, size_t width, const char **names, char *missing, size_t size)
{
    size_t *index = rangeArenaAllocate(arena,width * sizeof(*index)), found = 0, length = strlen(missing);
    RangeNode **q = rangeArenaAllocate(arena,width * sizeof(*q));
    for (size_t k = 0; k < width; ++k) index[k] = 0;
    for (size_t tried = 0; tried < 4096; ++tried) {
        int valid = 1;
        for (size_t k = 0; k < width; ++k) {
            q[k] = NULL;
            if (!cases[k]) continue;
            size_t seen = 0;
            for (size_t i = 0; i < cases[k]->itemCount && !q[k]; ++i)
                if (cases[k]->items[i]->kind == RangeNodeEnumCase && seen++ == index[k]) {
                    q[k] = rangeNodeCreate(arena,RangeNodePattern,cases[k]->path,cases[k]->line,cases[k]->column);
                    q[k]->integer = RangePatternCase;
                    q[k]->name = cases[k]->items[i]->name;
                    q[k]->resolvedDeclaration = cases[k]->items[i];
                }
            if (!q[k]) valid = 0;
        }
        if (valid && useful(typer,rows,count,q,types,width)) {
            char text[256]; size_t used = 0;
            // Named subjects read as the condition that tests them: 'value.present & bits.absent'.
            for (size_t k = 0, written = 0; k < width; ++k) {
                if (names && !q[k]) continue;
                const char *subject = names ? names[k] : "";
                used += (size_t)snprintf(text + used,sizeof(text) > used ? sizeof(text) - used : 0,"%s%s%s%s",
                                         written++ ? " & " : "",subject,q[k] && (!names || *subject) ? "." : q[k] ? "" : "_",
                                         q[k] ? q[k]->name : "");
            }
            if (length + strlen(text) + 8 < size)
                length += (size_t)snprintf(missing + length,size - length,"%s'%s'",found ? ", " : "",text);
            ++found;
        }
        // The next combination: the last subject's case advances first.
        size_t k = width;
        for (;;) {
            if (k == 0) return found;
            --k;
            size_t total = 0;
            for (size_t i = 0; cases[k] && i < cases[k]->itemCount; ++i) total += cases[k]->items[i]->kind == RangeNodeEnumCase;
            if (++index[k] < total) break;
            index[k] = 0;
        }
    }
    return found;
}

/* ---- the static structure of a switch's conditions ----
 * A switch arm's condition is a Bool, but its case tests on stable subjects
 * are a pattern table: a local, a parameter, a member path of one, a
 * #target value, or the receiver, never a call or a name the arm binds.
 * The condition, read as `|` of `&`s, gives one row per alternative, with
 * one column per subject: the case test of that subject, or wild. A row
 * that also needs anything else, a guard, covers nothing for the arms after
 * it. The rows then decide, as a switch over those subjects would, which
 * arms are reached and whether the arms cover every combination. */

static int stablePath(const RangeNode *path, const RangeNode *bindings)
{
    if (!path || path->generics) return 0;
    if (path->kind == RangeNodeName)
        return (path->flags & (RangeFlagImplicit | RangeFlagEarlier)) || !bindings || !bindingNamed(bindings,path->name);
    if (path->kind == RangeNodeEnvironment) return 1;
    return path->kind == RangeNodeMemberAccess && stablePath(path->a,bindings);
}

/* Two subjects read the same path; a narrowing is one more step of it. */
static int samePath(RangeNode *key, RangeNode *a, RangeNode *b)
{
    if (!a || !b || a->kind != b->kind || found(key,a)->narrowed != found(key,b)->narrowed) return 0;
    if ((a->flags & RangeFlagImplicit) || (b->flags & RangeFlagImplicit)) return (a->flags & RangeFlagImplicit) && (b->flags & RangeFlagImplicit);
    if (!same(a->name,b->name)) return 0;
    return a->kind != RangeNodeMemberAccess || samePath(key,a->a,b->a);
}

/* A subject as written, with the case of each narrowing it reads through:
 * `value.present.bits`. */
static const char *pathText(RangeArena *arena, RangeNode *key, RangeNode *path)
{
    if (path->flags & RangeFlagImplicit) return "";
    const char *owner = path->kind == RangeNodeMemberAccess ? pathText(arena,key,path->a) : path->kind == RangeNodeEnvironment ? "#" : "";
    RangeNode *step = found(key,path)->narrowed;
    const char *narrowed = step ? step->name : "";
    size_t length = strlen(owner) + strlen(path->name) + strlen(narrowed) + 3;
    char *text = rangeArenaAllocate(arena,length);
    snprintf(text,length,"%s%s%s%s%s",owner,path->kind == RangeNodeMemberAccess ? "." : "",path->name,*narrowed ? "." : "",narrowed);
    return text;
}

typedef struct { RangeNode **terms; size_t count; int guarded; } ShapeRow;
typedef struct { ShapeRow *rows; size_t count; } ShapeRows;

#define RANGE_SHAPE_ROWS 256

/* The condition as alternatives of case tests; *overflow when there are too many to check. */
static ShapeRows shapeRows(RangeArena *arena, RangeNode *key, RangeNode *node, RangeNode *bindings, int *overflow)
{
    ShapeRows out = {0};
    if (*overflow) return out;
    if (node && node->kind == RangeNodeBinary && (same(node->name,"&") || same(node->name,"|"))) {
        ShapeRows left = shapeRows(arena,key,node->a,bindings,overflow);
        ShapeRows right = shapeRows(arena,key,node->b,bindings,overflow);
        size_t count = same(node->name,"|") ? left.count + right.count : left.count * right.count;
        if (*overflow || count > RANGE_SHAPE_ROWS) { *overflow = 1; return out; }
        out.rows = rangeArenaAllocate(arena,(count ? count : 1) * sizeof(*out.rows));
        if (same(node->name,"|")) {
            memcpy(out.rows,left.rows,left.count * sizeof(*out.rows));
            memcpy(out.rows + left.count,right.rows,right.count * sizeof(*out.rows));
            out.count = count;
            return out;
        }
        for (size_t i = 0; i < left.count; ++i)
            for (size_t j = 0; j < right.count; ++j) {
                ShapeRow *row = &out.rows[out.count++];
                row->count = left.rows[i].count + right.rows[j].count;
                row->terms = rangeArenaAllocate(arena,(row->count ? row->count : 1) * sizeof(*row->terms));
                memcpy(row->terms,left.rows[i].terms,left.rows[i].count * sizeof(*row->terms));
                memcpy(row->terms + left.rows[i].count,right.rows[j].terms,right.rows[j].count * sizeof(*row->terms));
                row->guarded = left.rows[i].guarded || right.rows[j].guarded;
            }
        return out;
    }
    out.rows = rangeArenaAllocate(arena,sizeof(*out.rows));
    out.rows[0] = (ShapeRow){0};
    out.count = 1;
    RangeNode *test = node && found(key,node)->lowered ? found(key,node)->lowered : node;
    if (test && test->kind == RangeNodeCaseTest && stablePath(test->a,bindings)) {
        out.rows[0].terms = rangeArenaAllocate(arena,sizeof(*out.rows[0].terms));
        out.rows[0].terms[0] = test;
        out.rows[0].count = 1;
    } else out.rows[0].guarded = 1;
    return out;
}

/* The pattern table of a switch over conditions: its subjects, and one row
 * per alternative of each arm in order (the default a wild row), each with
 * its arm and whether a guard narrows it. `overflow` marks an arm with too
 * many alternatives to check, which counts as guarded. */
typedef struct {
    RangeNode **subjects; const char **names; size_t width;
    RangeNode ***rows; RangeNode **arms; int *guarded; size_t count;
} ConditionShape;

static void conditionShape(RangeArena *arena, RangeNode *key, RangeNode *node, ConditionShape *shape)
{
    size_t arms = node->itemCount;
    ShapeRows *each = rangeArenaAllocate(arena,(arms ? arms : 1) * sizeof(*each));
    size_t subjectCapacity = 1, total = 0;
    for (size_t i = 0; i < arms; ++i) {
        RangeNode *entry = node->items[i];
        int overflow = 0;
        if (entry->flags & RangeFlagLiteral || !entry->itemCount) each[i] = (ShapeRows){0};
        else each[i] = shapeRows(arena,key,entry->items[0]->b,entry->items[0]->c,&overflow);
        if (overflow) {
            each[i].rows = rangeArenaAllocate(arena,sizeof(*each[i].rows));
            each[i].rows[0] = (ShapeRow){.guarded=1};
            each[i].count = 1;
        }
        if (!each[i].count) {
            each[i].rows = rangeArenaAllocate(arena,sizeof(*each[i].rows));
            each[i].rows[0] = (ShapeRow){0};
            each[i].count = 1;
        }
        total += each[i].count;
        for (size_t r = 0; r < each[i].count; ++r) subjectCapacity += each[i].rows[r].count;
    }
    *shape = (ConditionShape){0};
    shape->subjects = rangeArenaAllocate(arena,subjectCapacity * sizeof(*shape->subjects));
    shape->names = rangeArenaAllocate(arena,subjectCapacity * sizeof(*shape->names));
    for (size_t i = 0; i < arms; ++i)
        for (size_t r = 0; r < each[i].count; ++r)
            for (size_t t = 0; t < each[i].rows[r].count; ++t) {
                RangeNode *subject = each[i].rows[r].terms[t]->a;
                size_t k = 0;
                while (k < shape->width && !samePath(key,shape->subjects[k],subject)) ++k;
                if (k < shape->width) continue;
                shape->subjects[shape->width] = subject;
                shape->names[shape->width++] = pathText(arena,key,subject);
            }
    shape->rows = rangeArenaAllocate(arena,(total ? total : 1) * sizeof(*shape->rows));
    shape->arms = rangeArenaAllocate(arena,(total ? total : 1) * sizeof(*shape->arms));
    shape->guarded = rangeArenaAllocate(arena,(total ? total : 1) * sizeof(*shape->guarded));
    for (size_t i = 0; i < arms; ++i)
        for (size_t r = 0; r < each[i].count; ++r) {
            ShapeRow *row = &each[i].rows[r];
            RangeNode **vector = rangeArenaAllocate(arena,(shape->width ? shape->width : 1) * sizeof(*vector));
            for (size_t k = 0; k < shape->width; ++k) vector[k] = NULL;
            int guarded = row->guarded;
            for (size_t t = 0; t < row->count; ++t) {
                size_t k = 0;
                while (!samePath(key,shape->subjects[k],row->terms[t]->a)) ++k;
                // A second test of one subject narrows the row as a guard does.
                if (vector[k]) guarded = 1;
                else vector[k] = row->terms[t]->b;
            }
            shape->rows[shape->count] = vector;
            shape->arms[shape->count] = node->items[i];
            shape->guarded[shape->count++] = guarded;
        }
}

/* Which rows nothing before them leaves anything for (reached[i] = 0), and
 * the combinations no row covers, written into missing; returns whether the
 * arms cover every combination. cases[k] declares subject k's cases. */
static int conditionCoverage(RangeArena *arena, Typer *typer, ConditionShape *shape,
                             RangeNode **types, RangeNode **cases, int *reached, char *missing, size_t size)
{
    RangeNode ***rows = rangeArenaAllocate(arena,(shape->count ? shape->count : 1) * sizeof(*rows));
    size_t count = 0;
    for (size_t i = 0; i < shape->count; ++i) {
        reached[i] = useful(typer,rows,count,shape->rows[i],types,shape->width);
        if (!shape->guarded[i]) rows[count++] = shape->rows[i];
    }
    RangeNode **wild = rangeArenaAllocate(arena,(shape->width ? shape->width : 1) * sizeof(*wild));
    for (size_t k = 0; k < shape->width; ++k) wild[k] = NULL;
    if (!useful(typer,rows,count,wild,types,shape->width)) return 1;
    *missing = '\0';
    if (shape->width) patternMissing(arena,typer,rows,count,types,cases,shape->width,shape->names,missing,size);
    return 0;
}

/* ---- types -------------------------------------------------------------
 * A type is a specialization: a construct plus one value per generic. Equal
 * specializations are interned to one node, so type equality is identity.
 * Inside a construct's own bodies its type parameters stand for themselves;
 * its members, typed for another specialization, are found under that one.
 * Literals take the type their context requires; a construct's laws (its
 * macro applications) run once per distinct specialization and once per
 * supplied literal. Emission stays on the declaration, so those runs only
 * check. An operator calls the function its operand's type declares; the
 * literal families select the integer default and the condition type. */

/* What the typer is in the middle of. Typing one declaration from inside
 * another saves it first and restores it after, so the outer one goes on as
 * it was. */
typedef struct {
    RangeNode *function, *output, *macro, *inferred, *closureSite, *key;
    int loops, inferring, closures, arguments;
    size_t narrowedFloor, narrowedCount, typingCount;
} TyperContext;

static TyperContext typerSave(const Typer *typer)
{
    return (TyperContext){.function=typer->function,.output=typer->output,.macro=typer->macro,
        .inferred=typer->inferred,.closureSite=typer->closureSite,.key=typer->key,.loops=typer->loops,
        .inferring=typer->inferring,.closures=typer->closures,.arguments=typer->arguments,.narrowedFloor=typer->narrowedFloor,
        .narrowedCount=typer->narrowedCount,.typingCount=typer->typingCount};
}

static void typerRestore(Typer *typer, TyperContext saved)
{
    typer->function = saved.function; typer->output = saved.output; typer->macro = saved.macro;
    typer->inferred = saved.inferred; typer->closureSite = saved.closureSite; typer->key = saved.key; typer->loops = saved.loops;
    typer->inferring = saved.inferring; typer->closures = saved.closures; typer->arguments = saved.arguments;
    typer->narrowedFloor = saved.narrowedFloor; typer->narrowedCount = saved.narrowedCount;
    typer->typingCount = saved.typingCount;
}

/* Typing on demand starts from the top level, as typing in order does; the
 * caller restores the context returned once it is done. */
static TyperContext typerTop(Typer *typer)
{
    TyperContext saved = typerSave(typer);
    typer->function = NULL; typer->output = NULL; typer->macro = NULL; typer->inferred = NULL; typer->closureSite = NULL;
    typer->key = NULL; typer->loops = 0; typer->inferring = 0; typer->closures = 0; typer->arguments = 0;
    typer->narrowedFloor = typer->narrowedCount; typer->typingCount = 0;
    return saved;
}

/* The record typing writes about `node` under the typer's key, made on the
 * first write from the node's own: its resolution and type, and nothing
 * else typing finds there. */
static RangeFacts *finding(Typer *typer, RangeNode *node)
{
    RangeNode *key = typer->key;
    if (!key) return &node->facts;
    RangeArena *arena = typer->report->arena;
    struct RangeFactTable *table = key->keyed;
    if (!table) {
        table = key->keyed = rangeArenaAllocate(arena,sizeof(*table));
        *table = (struct RangeFactTable){.capacity=64};
        table->nodes = rangeArenaAllocate(arena,table->capacity * sizeof(*table->nodes));
        table->facts = rangeArenaAllocate(arena,table->capacity * sizeof(*table->facts));
        memset(table->nodes,0,table->capacity * sizeof(*table->nodes));
    }
    size_t at = factSlot(table,node);
    if (table->nodes[at]) return table->facts[at];
    if (2 * (table->count + 1) > table->capacity) {
        // Grow, keeping every record.
        struct RangeFactTable grown = {.capacity=table->capacity * 2,.count=table->count};
        grown.nodes = rangeArenaAllocate(arena,grown.capacity * sizeof(*grown.nodes));
        grown.facts = rangeArenaAllocate(arena,grown.capacity * sizeof(*grown.facts));
        memset(grown.nodes,0,grown.capacity * sizeof(*grown.nodes));
        for (size_t i = 0; i < table->capacity; ++i) {
            if (!table->nodes[i]) continue;
            size_t j = factSlot(&grown,table->nodes[i]);
            grown.nodes[j] = table->nodes[i]; grown.facts[j] = table->facts[i];
        }
        *table = grown;
        at = factSlot(table,node);
    }
    RangeFacts *facts = rangeArenaAllocate(arena,sizeof(*facts));
    *facts = (RangeFacts){.resolvedDeclaration=node->resolvedDeclaration,.type=node->type};
    table->nodes[at] = node; table->facts[at] = facts; ++table->count;
    return facts;
}

static RangeNode *typeOf(Typer *, SourceScope *, RangeNode *, RangeNode *, RangeNode *);
static RangeNode *declaredType(Typer *, SourceScope *, RangeNode *, RangeNode *);
static RangeNode *declaredTypeIn(Typer *, SourceScope *, RangeNode *, RangeNode *);
static void expectType(Typer *, RangeNode *, RangeNode *, RangeNode *, const char *);
static void coerce(Typer *, RangeNode *, RangeNode *, RangeNode *, const char *);

static void typeError(Typer *typer, RangeNode *at, const char *format, ...)
{
    char text[768]; va_list args; va_start(args,format);
    vsnprintf(text,sizeof(text),format,args); va_end(args);
    // Code a macro emitted is located in the macro; name the application too.
    RangeNode *emitter = typer->function ? typer->function->emittedBy : NULL;
    RangeMacroApplication *app = emitter ? emitter->macroApplication : NULL;
    size_t length = strlen(text);
    if (app && app->target && length < sizeof(text))
        snprintf(text + length,sizeof(text) - length,"; in the code @%s emits for %s at %s:%d",
                 emitter->name,app->target->name,app->target->path,app->target->line);
    // Code typed for one specialization of a generic declaration names it.
    RangeNode *key = typer->key;
    length = strlen(text);
    if (key && length < sizeof(text)) {
        char name[512]; describeType(name,sizeof(name),key);
        snprintf(text + length,sizeof(text) - length,"; in %s, specialized at %s:%d:%d",name,key->path,key->line,key->column);
    }
    sourceDiagnostic(typer->report,at,0,"type","%s",text);
}

static int sameLiteral(const RangeNode *, const RangeNode *);

void describeType(char *out, size_t size, const RangeNode *type)
{
    if (!type) { snprintf(out,size,"<unknown>"); return; }
    if (type->kind == RangeNodeFunctionType) {
        size_t n = (size_t)snprintf(out,size,"(");
        for (size_t i = 0; i < type->itemCount && n < size; ++i) {
            char part[160]; describeType(part,sizeof(part),type->items[i]);
            n += (size_t)snprintf(out + n,size - n,"%s%s",i ? ", " : "",part);
        }
        char result[160] = "?";
        if (type->a) describeType(result,sizeof(result),type->a);
        if (n < size) snprintf(out + n,size - n,") -> %s",result);
        return;
    }
    size_t n = (size_t)snprintf(out,size,"%s",type->name);
    RangeNode *generics = type->kind == RangeNodeSpecialization && type->values ? type->resolvedDeclaration->generics : NULL;
    if (!generics || !generics->itemCount || n >= size) return;
    n += (size_t)snprintf(out + n,size - n,"<");
    for (size_t i = 0; i < generics->itemCount && n < size; ++i) {
        RangeNode *generic = generics->items[i], *value = type->values[i];
        char inner[128];
        if (generic->kind == RangeNodeTypeParameter) describeType(inner,sizeof(inner),value);
        else {
            RangeNodeKind kind; long long integer; const char *text;
            if (!value) snprintf(inner,sizeof(inner),"?");
            else if (!lawInputs(value,&kind,&integer,&text)) snprintf(inner,sizeof(inner),"%s",value->name ? value->name : "?");
            else if (kind == RangeNodeInteger) snprintf(inner,sizeof(inner),"%lld",integer);
            else if (kind == RangeNodeBool) snprintf(inner,sizeof(inner),"%s",integer ? "true" : "false");
            else snprintf(inner,sizeof(inner),"\"%s\"",text);
        }
        n += (size_t)snprintf(out + n,size - n,"%s%s: %s",i ? ", " : "",generic->name,inner);
    }
    if (n < size) snprintf(out + n,size - n,">");
}

/* Two values of one generic: the same type, or equal literals. */
static int sameGenericValue(const RangeNode *generic, RangeNode *x, RangeNode *y)
{
    if (generic->kind == RangeNodeTypeParameter) return x == y;
    return x && y ? sameLiteral(x,y) : x == y;
}

/* Whether a specialization is the one its declaration's bare name names:
 * each of its generics is a value generic holding its default, as in
 * Int<bits: 64, signed: true>, or it has none. */
int bareSpecialization(const RangeNode *specialization)
{
    RangeNode *declared = specialization->resolvedDeclaration->generics;
    for (size_t i = 0; declared && specialization->values && i < declared->itemCount; ++i) {
        RangeNode *generic = declared->items[i];
        if (generic->kind == RangeNodeTypeParameter || !sameGenericValue(generic,specialization->values[i],rangeNodeRHS(generic))) return 0;
    }
    return 1;
}

/* A specialization's values, one per generic of its declaration in order:
 * the type a type parameter names, or the value a value generic holds. */
static RangeNode **genericValues(RangeArena *arena, const RangeNode *declaration)
{
    size_t count = declaration->generics ? declaration->generics->itemCount : 0;
    if (!declaration->generics) return NULL;
    RangeNode **values = rangeArenaAllocate(arena,(count ? count : 1) * sizeof(*values));
    memset(values,0,(count ? count : 1) * sizeof(*values));
    return values;
}

/* The one specialization of a declaration for these generic values: of a
 * construct or enum, or of a generic function within `outer`, its receiver's
 * specialization, located where it is first met. */
static RangeNode *internSpecialization(Typer *typer, RangeNode *declaration, RangeNode **values, RangeNode *outer,
                                       RangeNode *at, int *created)
{
    *created = 0;
    RangeNode *list = declaration->kind == RangeNodeFunction ? typer->instances : typer->specializations;
    size_t count = values ? declaration->generics->itemCount : 0;
    for (size_t i = 0; i < list->itemCount; ++i) {
        RangeNode *candidate = list->items[i];
        if (candidate->resolvedDeclaration != declaration || candidate->outer != outer || !candidate->values != !values) continue;
        size_t matched = 0;
        while (matched < count && sameGenericValue(declaration->generics->items[matched],candidate->values[matched],values[matched])) ++matched;
        if (matched == count) return candidate;
    }
    RangeArena *arena = typer->report->arena;
    RangeNode *specialization = rangeNodeCreate(arena,RangeNodeSpecialization,at->path,at->line,at->column);
    specialization->name = declaration->name;
    specialization->resolvedDeclaration = declaration;
    specialization->values = values;
    specialization->outer = outer;
    rangeNodeAppend(arena,list,specialization);
    *created = 1;
    return specialization;
}

/* The inputs a literal gives a law: its kind and value, `-n` as one value. */
int lawInputs(const RangeNode *value, RangeNodeKind *kind, long long *integer, const char **text)
{
    *integer = 0; *text = NULL;
    if (value->kind == RangeNodeUnary && same(value->name,"-") && value->a && value->a->kind == RangeNodeInteger) {
        *kind = RangeNodeInteger;
        *integer = -value->a->integer;
        return value->a->integer != LLONG_MIN;
    }
    *kind = value->kind;
    if (value->kind == RangeNodeInteger || value->kind == RangeNodeBool) { *integer = value->integer; return 1; }
    if (value->kind == RangeNodeString && value->itemCount == 1 && (value->items[0]->flags & RangeFlagLiteral)) {
        *text = value->items[0]->name;
        return 1;
    }
    return 0;
}

/* Where a specialization, or one it is nested in, holds a generic of its
 * declaration: its type or value; NULL when none holds it. */
RangeNode **genericSlot(RangeNode *specialization, RangeNode *generic)
{
    for (; specialization; specialization = specialization->outer) {
        RangeNode *declared = specialization->resolvedDeclaration->generics;
        for (size_t i = 0; declared && specialization->values && i < declared->itemCount; ++i)
            if (declared->items[i] == generic) return &specialization->values[i];
    }
    return NULL;
}

/* Build the specialization named by generic arguments, in the context whose
 * type parameters the arguments may mention. */
RangeNode *specialize(Typer *typer, SourceScope *scope, RangeNode *declaration,
                      RangeNode *arguments, RangeNode *context, RangeNode *at)
{
    RangeArena *arena = typer->report->arena;
    RangeNode *declared = declaration->generics, **values = genericValues(arena,declaration);
    int isDefault = 1;
    size_t positional = 0;
    if (declared) {
        for (size_t i = 0; i < declared->itemCount; ++i) {
            RangeNode *generic = declared->items[i], *argument = NULL;
            size_t unnamed = 0;
            if (arguments) for (size_t j = 0; j < arguments->itemCount; ++j) {
                RangeNode *candidate = arguments->items[j];
                if (candidate->name ? same(candidate->name,generic->name)
                    : generic->kind == RangeNodeTypeParameter && unnamed++ == positional) { argument = candidate; break; }
            }
            if (generic->kind == RangeNodeTypeParameter) {
                ++positional;
                if (!argument) { typeError(typer,at,"'%s' requires generic %s",declaration->name,generic->name); return NULL; }
                RangeNode *reference = argument->a;
                if (!reference || reference->kind != RangeNodeName) { typeError(typer,argument,"generic %s requires a type",generic->name); return NULL; }
                RangeNode *type = resolveTypeReference(typer,scope,reference->name,reference->generics,reference->flags,context,reference);
                if (!type) return NULL;
                values[i] = type;
                isDefault = 0;
            } else if (argument) {
                SourceScope declarationScope = {.owner=declaration};
                RangeNode *expected = declaredTypeIn(typer,&declarationScope,generic,NULL);
                RangeNode *actual = typeOf(typer,scope,argument->a,expected,context);
                if (expected && actual && expected != actual) {
                    char want[160], got[160];
                    describeType(want,sizeof(want),expected); describeType(got,sizeof(got),actual);
                    typeError(typer,argument->a,"generic %s requires %s; found %s",generic->name,want,got);
                    return NULL;
                }
                values[i] = argument->a;
                if (!sameGenericValue(generic,values[i],rangeNodeRHS(generic))) isDefault = 0;
            } else if (generic->typeName) {
                // `<let width: Int>` has no default: each use supplies it.
                typeError(typer,at,"'%s' requires generic %s",declaration->name,generic->name);
                return NULL;
            } else values[i] = rangeNodeRHS(generic);
        }
        size_t unnamed = 0;
        if (arguments) for (size_t j = 0; j < arguments->itemCount; ++j) {
            RangeNode *candidate = arguments->items[j];
            int known = 0;
            if (!candidate->name) known = unnamed++ < positional;
            else for (size_t i = 0; i < declared->itemCount; ++i)
                if (same(candidate->name,declared->items[i]->name)) known = 1;
            if (!known && candidate->name) { typeError(typer,candidate,"'%s' has no generic named '%s'",declaration->name,candidate->name); return NULL; }
            if (!known) { typeError(typer,candidate,"'%s' takes %zu type arguments; %zu supplied",declaration->name,positional,unnamed); return NULL; }
        }
    } else if (arguments && arguments->itemCount) {
        typeError(typer,at,"'%s' takes no generic arguments",declaration->name);
        return NULL;
    }
    int created = 0;
    RangeNode *specialization = internSpecialization(typer,declaration,values,NULL,at,&created);
    if (created) {
        // The declaration's own application already covered its defaults.
        if (isDefault) specialization->found |= RangeFlagChecked;
        else queueLaws(typer,specialization,NULL,at);
    }
    return specialization;
}

/* A construct or enum without generics has one specialization, its own:
 * its bodies are typed there once, in order, in place. NULL for a generic
 * declaration: its bodies are typed only for the specializations the
 * program uses, each under its key, as they are used. */
RangeNode *ownSpecialization(Typer *typer, RangeNode *declaration)
{
    if (declaration->generics && declaration->generics->itemCount) return NULL;
    int created = 0;
    RangeNode *specialization = internSpecialization(typer,declaration,genericValues(typer->report->arena,declaration),NULL,declaration,&created);
    specialization->found |= RangeFlagChecked;
    return specialization;
}

static int parametric(const RangeNode *);
static int graphConstruct(Typer *, const RangeNode *);

/* ---- function types ----
 * `(A, B) -> R` is a parameter's type: the parameter takes a closure, which
 * runs only while the call it is passed to runs. Function types are interned,
 * so equal ones are one node; one whose result is still being inferred, for a
 * generic call, is not interned and has no result. */
static int isFunctionType(const RangeNode *type)
{
    return type && type->kind == RangeNodeFunctionType;
}

static RangeNode *functionType(Typer *typer, RangeNode **parameters, size_t count, RangeNode *result, RangeNode *at)
{
    for (size_t i = 0; result && i < typer->functionTypes->itemCount; ++i) {
        RangeNode *candidate = typer->functionTypes->items[i];
        if (candidate->a != result || candidate->itemCount != count) continue;
        size_t matched = 0;
        while (matched < count && candidate->items[matched] == parameters[matched]) ++matched;
        if (matched == count) return candidate;
    }
    RangeArena *arena = typer->report->arena;
    RangeNode *type = rangeNodeCreate(arena,RangeNodeFunctionType,at->path,at->line,at->column);
    type->name = "->";
    for (size_t i = 0; i < count; ++i) rangeNodeAppend(arena,type,parameters[i]);
    type->a = result;
    if (result) rangeNodeAppend(arena,typer->functionTypes,type);
    return type;
}

/* A construct with no stored members, such as Void: it has one value and
 * holds nothing, so a closure that returns it yields no value, and `return`
 * needs none. The rule is structural; C names no such type. */
int unitType(Typer *typer, const RangeNode *type)
{
    if (!type || type->kind != RangeNodeSpecialization) return 0;
    RangeNode *declaration = type->resolvedDeclaration;
    if (declaration->kind != RangeNodeConstruct || graphConstruct(typer,declaration)) return 0;
    for (size_t i = 0; i < declaration->itemCount; ++i)
        if (rangeNodeDeclaresValue(declaration->items[i]->kind)) return 0;
    return 1;
}

/* ---- macro time ----
 * A macro type, @member, names a declaration of any kind that applies the
 * macro, as a grammar kind such as Let names a declaration of that kind. Its
 * values are declarations, which exist only up to macro time, and so do
 * values of grammar kinds and of types holding them, such as Array<@member>:
 * they have no runtime layout, and the evaluator compares them. A macro
 * type's specialization has the macro as its declaration.
 *
 * Some values' types depend on which declaration a reflection value holds:
 * a member kind's C-backed value, a field only some kinds of a macro type
 * declare, and what an operator or a function makes of a macro type's value.
 * Their type is known at macro time: it is accepted wherever a type is
 * expected, what is computed from it is known at macro time too, and the
 * evaluator checks it when the macro runs. */

static int isMacroType(const RangeNode *type)
{
    return type && type->kind == RangeNodeSpecialization && type->resolvedDeclaration
        && type->resolvedDeclaration->kind == RangeNodeMacro;
}

int deferredType(const Typer *typer, const RangeNode *type)
{
    return type && type == typer->deferred;
}

/* A value whose operations are chosen only at macro time: one known then, or
 * a declaration of some kind a macro type admits. */
static int macroOperand(const Typer *typer, const RangeNode *type)
{
    return deferredType(typer,type) || isMacroType(type);
}

/* Whether values of `type` exist only up to macro time. */
int macroTimeType(Typer *typer, const RangeNode *type)
{
    if (deferredType(typer,type)) return 1;
    if (!type || type->kind != RangeNodeSpecialization) return 0;
    if (isMacroType(type) || graphConstruct(typer,type->resolvedDeclaration)) return 1;
    RangeNode *declared = type->resolvedDeclaration->generics;
    for (size_t i = 0; declared && type->values && i < declared->itemCount; ++i)
        if (declared->items[i]->kind == RangeNodeTypeParameter && macroTimeType(typer,type->values[i])) return 1;
    return 0;
}

/* `@member` as a type: the one macro of that name. */
static RangeNode *macroTypeNamed(Typer *typer, const char *name, RangeNode *at)
{
    RangeNode *macro = NULL;
    size_t found = 0;
    for (size_t u = 0; u < typer->report->count; ++u) for (size_t i = 0; i < typer->report->units[u]->itemCount; ++i) {
        RangeNode *candidate = typer->report->units[u]->items[i];
        if (candidate->kind == RangeNodeMacro && same(candidate->name,name)) { macro = candidate; ++found; }
    }
    if (!found) return NULL; /* undeclared is reported already */
    if (found > 1) { typeError(typer,at,"'@%s' names %zu macros; a macro type names one",name,found); return NULL; }
    int created = 0;
    RangeNode *type = internSpecialization(typer,macro,NULL,NULL,macro,&created);
    if (created) {
        char spelled[160];
        snprintf(spelled,sizeof(spelled),"@%s",name);
        type->name = rangeArenaIntern(typer->report->arena,spelled,strlen(spelled));
        type->found |= RangeFlagChecked; /* the kinds it admits ran their own laws */
    }
    return type;
}

/* A value of a kind is a value of a macro type that kind applies: an Enum is
 * a @nominal. */
static int converts(const RangeNode *expected, const RangeNode *actual)
{
    return isMacroType(expected) && actual && actual->kind == RangeNodeSpecialization
        && appliesMacro(actual->resolvedDeclaration,expected->resolvedDeclaration);
}

RangeNode *resolveTypeReference(Typer *typer, SourceScope *scope, const char *name,
                                RangeNode *generics, int flags, RangeNode *context, RangeNode *at)
{
    if (!name || !*name) return NULL;
    if (flags & RangeFlagFunction) {
        // Each part resolves where the written type stands. A result that
        // does not resolve yet, an unbound type parameter, is inferred.
        if (!generics) return NULL;
        RangeNode **parts = rangeArenaAllocate(typer->report->arena,(generics->itemCount ? generics->itemCount : 1) * sizeof(*parts));
        for (size_t i = 0; i < generics->itemCount; ++i) {
            RangeNode *written = generics->items[i]->a;
            parts[i] = resolveTypeReference(typer,scope,written->name,written->generics,written->flags,context,written);
            if (!parts[i]) return NULL;
        }
        RangeNode *written = generics->a;
        RangeNode *result = written ? resolveTypeReference(typer,scope,written->name,written->generics,written->flags,context,written) : NULL;
        return functionType(typer,parts,generics->itemCount,result,at);
    }
    if (flags & RangeFlagOptional) {
        // `T?` is the construct applying @optional, specialized with T.
        RangeNode *optional = NULL;
        size_t found = 0;
        for (size_t u = 0; u < typer->report->count; ++u) for (size_t i = 0; i < typer->report->units[u]->itemCount; ++i) {
            RangeNode *candidate = typer->report->units[u]->items[i];
            if ((candidate->kind == RangeNodeConstruct || candidate->kind == RangeNodeEnum)
                && appliesBuiltin(candidate,"optional")) { optional = candidate; ++found; }
        }
        if (found != 1) {
            sourceDiagnostic(typer->report,at,0,"undeclared","'%s?' needs exactly one construct applying @optional; found %zu",name,found);
            return NULL;
        }
        RangeArena *arena = typer->report->arena;
        RangeNode *wrapped = rangeNodeCreate(arena,RangeNodeName,at->path,at->line,at->column);
        wrapped->name = name; wrapped->generics = generics; wrapped->flags = flags & ~RangeFlagOptional;
        RangeNode *arguments = rangeNodeCreate(arena,RangeNodeBlock,at->path,at->line,at->column);
        arguments->name = "genericArguments";
        RangeNode *argument = rangeNodeCreate(arena,RangeNodeArgument,at->path,at->line,at->column);
        argument->a = wrapped;
        rangeNodeAppend(arena,arguments,argument);
        return specialize(typer,scope,optional,arguments,context,at);
    }
    if (flags & RangeFlagMacroType) return macroTypeNamed(typer,name,at);
    RangeNode *declared = context && context->kind == RangeNodeSpecialization && context->values ? context->resolvedDeclaration->generics : NULL;
    for (size_t i = 0; declared && i < declared->itemCount; ++i)
        if (declared->items[i]->kind == RangeNodeTypeParameter && same(declared->items[i]->name,name)) return context->values[i];
    RangeNode *declaration = dottedLookup(typer->report,scope,name,2);
    // A generic function's type parameter names the type its specialization binds.
    RangeNode **slot = declaration && declaration->kind == RangeNodeTypeParameter && !generics ? genericSlot(typer->key,declaration) : NULL;
    if (slot && *slot) return *slot;
    if (!declaration || (declaration->kind != RangeNodeConstruct && declaration->kind != RangeNodeEnum))
        return NULL; /* undeclared is reported already */
    // As in Swift, a generic declaration's bare name inside its own bodies is
    // the specialization being typed: `Optional` in Optional<Wrapped>'s methods.
    // Value generics too: `#target.name` in Int's operators is Int<bits: 8> there.
    if (!generics && context && context->kind == RangeNodeSpecialization
        && context->resolvedDeclaration == declaration && declaration->generics) return context;
    return specialize(typer,scope,declaration,generics,context,at);
}

static int optionalWithoutValue(const RangeNode *);

/* The optional's case without a payload, a value written beside `at`: what
 * `let v: T?` starts as. */
static RangeNode *absentValue(Typer *typer, RangeNode *at, RangeNode *type)
{
    if (!optionalWrapped(typer,type,NULL)) return NULL;
    RangeNode *declaration = type->resolvedDeclaration;
    for (size_t i = 0; i < declaration->itemCount; ++i) {
        RangeNode *entry = declaration->items[i];
        if (entry->kind != RangeNodeEnumCase || entry->itemCount) continue;
        RangeNode *value = rangeNodeCreate(typer->report->arena,RangeNodeCase,at->path,at->line,at->column);
        value->name = entry->name;
        value->resolvedDeclaration = entry;
        value->type = type;
        return value;
    }
    return NULL;
}

static RangeNode *declaredType(Typer *typer, SourceScope *scope, RangeNode *node, RangeNode *context)
{
    if (node->kind == RangeNodeParameter)
        return node->b ? resolveTypeReference(typer,scope,node->b->name,node->b->generics,node->flags,context,node->b) : NULL;
    if (node->flags & RangeFlagMany) return NULL; /* @many storage is not a standalone value */
    RangeFacts *facts = found(typer->key,node);
    if (facts->lowered && facts->lowered->kind == RangeNodeCall) return found(typer->key,facts->lowered)->type; /* `let r: step(x: 1)` */
    if (node->typeName && (node->flags & RangeFlagApplication) && facts->type) return facts->type; /* construction */
    // A bare name's resolved declaration decides its meaning: a value is
    // copied, a construct is a requirement.
    if (node->typeName && node->rhsReference && !node->generics) {
        RangeNode *value = sourceLookup(typer->report,scope,node->typeName,0);
        if (value && (rangeNodeDeclaresValue(value->kind) || value->kind == RangeNodeParameter) && value != node) {
            finding(typer,node->rhsReference)->resolvedDeclaration = value;
            return typeOf(typer,scope,node->rhsReference,NULL,context);
        }
    }
    if (node->typeName) {
        RangeNode *type = resolveTypeReference(typer,scope,node->typeName,node->generics,node->flags,context,node);
        // An enum's lets are its cases' payload fields: types, not bindings.
        if (optionalWithoutValue(node) && !(scope && scope->owner && scope->owner->kind == RangeNodeEnum))
            finding(typer,node)->lowered = absentValue(typer,node,type);
        return type;
    }
    // `let inner: Outer.Inner` requires the nested type its path names.
    if ((facts->found & RangeFlagRequired) || requiredPath(typer->report,scope,node)) {
        finding(typer,node)->found |= RangeFlagRequired;
        return resolveTypeReference(typer,scope,typePathText(typer->report,node->items[0]->a),NULL,node->flags,context,node);
    }
    // A literal member of the construct its literal selects (Int's `value: 0`)
    // has that construct's own specialization.
    RangeNode *rhs = rangeNodeRHS(node);
    return rhs ? typeOf(typer,scope,rhs,context,context) : NULL;
}

/* The key a declaration's members, payload fields, and methods are typed
 * under for `type`, a specialization of it: that specialization when the
 * declaration is generic; NULL for one that is not, typed in place. */
RangeNode *keyOf(const RangeNode *declaration, RangeNode *type)
{
    return declaration && declaration->generics && declaration->generics->itemCount && type
        && type->kind == RangeNodeSpecialization && type->resolvedDeclaration == declaration ? type : NULL;
}

static int memberOf(const RangeNode *, const RangeNode *);

/* The declared type of a generic, member, or parameter, for `context`: a
 * member of context's declaration is typed under its key, whatever key the
 * code that asks is typed under, so each specialization keeps its own
 * findings about the declaration's nodes. */
static RangeNode *declaredTypeIn(Typer *typer, SourceScope *scope, RangeNode *node, RangeNode *context)
{
    RangeNode *key = typer->key;
    typer->key = context && memberOf(context->resolvedDeclaration,node) ? keyOf(context->resolvedDeclaration,context) : NULL;
    RangeNode *type = declaredType(typer,scope,node,context);
    typer->key = key;
    return type;
}

static void typeMember(Typer *, SourceScope *, RangeNode *, RangeNode *);
static SourceScope *enclosingScope(Typer *, RangeNode *, SourceScope[33]);

/* A member's or payload field's type in `type`, a specialization of its
 * declaration: typed under that specialization's key, from the top level,
 * the first time it is asked for, wherever that is. */
RangeNode *memberTypeIn(Typer *typer, RangeNode *type, RangeNode *member)
{
    RangeNode *declaration = type->resolvedDeclaration, *key = keyOf(declaration,type);
    if (!(found(key,member)->found & RangeFlagTyped)) {
        SourceScope scopes[33], scope = {.owner=declaration,.parent=enclosingScope(typer,declaration,scopes)};
        TyperContext outer = typerTop(typer);
        typer->key = key;
        typeMember(typer,&scope,member,type);
        typerRestore(typer,outer);
    }
    return found(key,member)->type;
}

RangeNode *findMember(RangeNode *declaration, const char *name)
{
    for (size_t i = 0; i < declaration->itemCount; ++i)
        if (rangeNodeDeclaresValue(declaration->items[i]->kind) && same(declaration->items[i]->name,name))
            return declaration->items[i];
    return NULL;
}

static RangeNode *findFunction(RangeNode *owner, const char *name)
{
    for (size_t i = 0; i < owner->itemCount; ++i)
        if (owner->items[i]->kind == RangeNodeFunction && same(owner->items[i]->name,name)) return owner->items[i];
    return NULL;
}

/* Overloads differ in their labels: a call selects the function whose
 * labels it writes, or else the first of that name, which reports why the
 * call does not fit it. */
RangeNode *findCalledFunction(RangeNode *owner, const char *name, const RangeNode *call)
{
    for (size_t i = 0; call && i < owner->itemCount; ++i) {
        RangeNode *function = owner->items[i];
        if (function->kind != RangeNodeFunction || !same(function->name,name) || function->itemCount != call->itemCount) continue;
        int labels = 1;
        for (size_t j = 0; j < call->itemCount && labels; ++j) labels = argumentFits(call->items[j],function,j);
        if (labels) return function;
    }
    return findFunction(owner,name);
}

/* A member's type in a specialization of its declaration. A grammar kind's
 * builtin member without a type, such as Let's value, is C's reflection of
 * the declaration, known at macro time. */
RangeNode *memberType(Typer *typer, RangeNode *declaration, RangeNode *member, RangeNode *receiver)
{
    if (builtinMember(member) && !member->typeName && graphConstruct(typer,declaration)) return typer->deferred;
    return memberTypeIn(typer,receiver,member);
}

/* The kinds a macro type admits: the constructs and enums applying its macro. */
static size_t macroKinds(Typer *typer, const RangeNode *type, RangeNode **kinds, size_t capacity)
{
    size_t count = 0;
    for (size_t u = 0; u < typer->report->count; ++u) for (size_t i = 0; i < typer->report->units[u]->itemCount; ++i) {
        RangeNode *kind = typer->report->units[u]->items[i];
        if ((kind->kind == RangeNodeConstruct || kind->kind == RangeNodeEnum)
            && appliesMacro(kind,type->resolvedDeclaration) && count < capacity) kinds[count++] = kind;
    }
    return count;
}

/* `member.name` on a value of a macro type: the type every kind admitted
 * gives the field, when all declare it with one type. A field only some
 * kinds declare, or declare with different types, is known at macro time,
 * from the declaration the value holds. */
static RangeNode *macroTypeMember(Typer *typer, RangeNode *type, const char *name, RangeNode *at)
{
    RangeNode *kinds[32], *found = NULL;
    size_t count = macroKinds(typer,type,kinds,32), declaring = 0;
    int agree = 1, function = 0;
    for (size_t i = 0; i < count; ++i) {
        RangeNode *member = findMember(kinds[i],name);
        if (!member) { function |= findFunction(kinds[i],name) != NULL; continue; }
        if (member->flags & RangeFlagMany) { typeError(typer,at,"'%s' holds @many storage and is not a value",name); return NULL; }
        // A generic kind's field has a type only per specialization.
        RangeNode *own = ownSpecialization(typer,kinds[i]);
        RangeNode *field = own ? memberType(typer,kinds[i],member,own) : typer->deferred;
        if (!declaring++) found = field;
        else if (field != found) agree = 0;
    }
    if (!count) return NULL; /* no kind applies the macro: nothing says what its values hold */
    if (!declaring) {
        char t[160]; describeType(t,sizeof(t),type);
        if (function) typeError(typer,at,"'%s.%s' is a function; call it",t,name);
        else typeError(typer,at,"%s has no member '%s'",t,name);
        return NULL;
    }
    return declaring == count && agree && found ? found : typer->deferred;
}

static RangeNode *lookupFunction(SourceReport *report, SourceScope *scope, const char *name)
{
    for (; scope; scope = scope->parent) {
        RangeNode *function = findFunction(scope->owner,name);
        if (function) return function;
    }
    for (size_t u = 0; u < report->count; ++u) {
        RangeNode *function = findFunction(report->units[u],name);
        if (function) return function;
    }
    return NULL;
}

/* ---- enums ----
 * An enum is a closed union: a value is one of its cases, and a case may carry
 * payload fields. A case's fields are Let nodes named by label, or by position
 * when unlabeled. The case's ordinal is its tag. */

int isEnum(const RangeNode *type)
{
    return type && type->kind == RangeNodeSpecialization && type->resolvedDeclaration
        && type->resolvedDeclaration->kind == RangeNodeEnum;
}

RangeNode *enumCase(const RangeNode *declaration, const char *name)
{
    for (size_t i = 0; declaration && name && i < declaration->itemCount; ++i)
        if (declaration->items[i]->kind == RangeNodeEnumCase && same(declaration->items[i]->name,name))
            return declaration->items[i];
    return NULL;
}

static int enumPayloads(const RangeNode *declaration)
{
    for (size_t i = 0; i < declaration->itemCount; ++i)
        if (declaration->items[i]->kind == RangeNodeEnumCase && declaration->items[i]->itemCount) return 1;
    return 0;
}

static int labeledField(const RangeNode *field)
{
    return field->name && !(field->name[0] >= '0' && field->name[0] <= '9');
}

static int parametric(const RangeNode *declaration)
{
    for (size_t i = 0; declaration->generics && i < declaration->generics->itemCount; ++i)
        if (declaration->generics->items[i]->kind == RangeNodeTypeParameter) return 1;
    return 0;
}

/* A literal of an enum names the case spelled like it: `true` is case true. */
static const char *literalSpelling(const RangeNode *literal)
{
    if (literal->kind == RangeNodeBool) return literal->integer ? "true" : "false";
    if (literal->kind == RangeNodeInteger) return literal->name;
    return NULL;
}

RangeNode *literalCase(const RangeNode *declaration, const RangeNode *literal)
{
    return enumCase(declaration,literalSpelling(literal));
}

/* The enum a `.case` names: the one its context expects. */
static RangeNode *contextualEnum(Typer *typer, RangeNode *at, RangeNode *expected)
{
    if (isEnum(expected)) return expected;
    if (expected) {
        char want[160]; describeType(want,sizeof(want),expected);
        typeError(typer,at,"'.%s' names an enum case, but the context expects %s",at->name,want);
    } else typeError(typer,at,"'.%s' needs a context that names its enum",at->name);
    return NULL;
}

/* `Light.red`: the enum written in the path, specialized by its context when
 * the path supplies no generic arguments. */
static RangeNode *pathEnum(Typer *typer, SourceScope *scope, RangeNode *declaration, RangeNode *path,
                           RangeNode *expected, RangeNode *context, RangeNode *at)
{
    if (path->generics) return specialize(typer,scope,declaration,path->generics,context,at);
    if (expected && expected->kind == RangeNodeSpecialization && expected->resolvedDeclaration == declaration) return expected;
    if (context && context->resolvedDeclaration == declaration) return context;
    if (!parametric(declaration)) return specialize(typer,scope,declaration,NULL,context,at);
    typeError(typer,at,"'%s' needs its generic arguments here; the context does not supply them",declaration->name);
    return NULL;
}

/* `Int?` written before `.case`, as in `Int?.absent`: the optional of the
 * type, the enum applying @optional specialized with it. */
static RangeNode *optionalPath(Typer *typer, SourceScope *scope, RangeNode *path, RangeNode *context)
{
    if (!path || path->kind != RangeNodeName || !(path->flags & RangeFlagOptional)) return NULL;
    RangeNode *type = resolveTypeReference(typer,scope,path->name,path->generics,RangeFlagOptional,context,path);
    return isEnum(type) ? type : NULL;
}

static RangeNode *namedCase(Typer *typer, RangeNode *type, const char *name, RangeNode *at)
{
    RangeNode *found = enumCase(type->resolvedDeclaration,name);
    if (!found) { char t[160]; describeType(t,sizeof(t),type); typeError(typer,at,"%s has no case '%s'",t,name); }
    return found;
}

/* `.value(number: 7)`: one argument per payload field, in order, labeled as
 * the field is. */
static void typePayload(Typer *typer, SourceScope *scope, RangeNode *at, RangeNode *type, RangeNode *entry,
                        RangeNode **arguments, size_t count, RangeNode *context)
{
    char t[160]; describeType(t,sizeof(t),type);
    if (count != entry->itemCount)
        typeError(typer,at,"case '%s' of %s takes %zu payload fields; %zu supplied",entry->name,t,entry->itemCount,count);
    for (size_t i = 0; i < count && i < entry->itemCount; ++i) {
        RangeNode *argument = arguments[i], *field = entry->items[i];
        if (labeledField(field) && !same(argument->name,field->name))
            typeError(typer,argument,"payload field %zu of '%s' requires label '%s'",i + 1,entry->name,field->name);
        else if (!labeledField(field) && argument->name)
            typeError(typer,argument,"payload field %zu of '%s' takes no label",i + 1,entry->name);
        finding(typer,argument)->resolvedDeclaration = field;
        RangeNode *expected = memberTypeIn(typer,type,field);
        char what[200]; snprintf(what,sizeof(what),"payload field %zu of '%s'",i + 1,entry->name);
        coerce(typer,argument->a,expected,typeOf(typer,scope,argument->a,expected,context),what);
    }
}

static int isLiteral(const RangeNode *node)
{
    return node->kind == RangeNodeInteger || node->kind == RangeNodeBool || node->kind == RangeNodeString;
}

/* Operands typed from the other side: literals and `.case` forms. */
static int contextual(const RangeNode *node)
{
    return node && (isLiteral(node) || node->kind == RangeNodeCase
        || (node->kind == RangeNodeCall && node->a && node->a->kind == RangeNodeCase));
}

/* A construct whose layout is the bytes primitive: UTF-8 bytes C holds. */
int bytesDeclaration(const RangeNode *declaration)
{
    for (size_t i = 0; declaration && i < declaration->itemCount; ++i)
        if (builtinMember(declaration->items[i]) && same(declaration->items[i]->name,"bytes")) return 1;
    return 0;
}

int bytesType(const RangeNode *type)
{
    return type && type->kind == RangeNodeSpecialization && bytesDeclaration(type->resolvedDeclaration);
}

typedef struct { RangeNode *seen[64]; size_t count; } Comparing;

/* `a + b` calls the function named by the operator, `+`, that a's type
 * declares, with b as its one argument; `-a` calls the `-` that takes none.
 * The symbol and the arity are the key; overloads with the same signature are
 * rejected, so a type has at most one such function. */
RangeNode *operatorFunction(const RangeNode *declaration, const char *symbol, size_t arity)
{
    if (declaration && (declaration->kind == RangeNodeConstruct || declaration->kind == RangeNodeEnum))
        for (size_t i = 0; i < declaration->itemCount; ++i)
            if (declaration->items[i]->kind == RangeNodeFunction && same(declaration->items[i]->name,symbol)
                && declaration->items[i]->itemCount == arity) return declaration->items[i];
    return NULL;
}

/* A function named by an operator symbol rather than a name. */
int operatorName(const char *name)
{
    return name && *name && !isalpha((unsigned char)*name) && *name != '_';
}

/* `&` and `|` evaluate their right operand only when the left does not
 * decide the result: their builtin functions are C control flow. */
int shortCircuit(const RangeNode *function)
{
    return function && (function->flags & RangeFlagBuiltin) && (same(function->name,"&") || same(function->name,"|"));
}

/* `=` on values of `type` is checked once every type is known: layouts and
 * member types are complete then. */
static void noteEquality(Typer *typer, RangeNode *type, RangeNode *at)
{
    if (macroTimeType(typer,type)) {
        // Values that exist only up to macro time hold declarations.
        sourceDiagnostic(typer->report,at,1,"C-implementation","'=' here compares values that exist only up to macro time, in C: declarations by their identity");
        return;
    }
    // A generic body typed for several specializations compares one type there once.
    for (size_t i = 0; i < typer->equalityCount; ++i)
        if (typer->equalities[i].type == type && typer->equalities[i].at == at) return;
    if (typer->equalityCount == typer->equalityCapacity) {
        typer->equalityCapacity = typer->equalityCapacity ? typer->equalityCapacity * 2 : 64;
        void *grown = rangeArenaAllocate(typer->report->arena,typer->equalityCapacity * sizeof(*typer->equalities));
        if (typer->equalityCount) memcpy(grown,typer->equalities,typer->equalityCount * sizeof(*typer->equalities));
        typer->equalities = grown;
    }
    typer->equalities[typer->equalityCount].type = type;
    typer->equalities[typer->equalityCount].key = typer->key;
    typer->equalities[typer->equalityCount++].at = at;
}

static void expectType(Typer *typer, RangeNode *at, RangeNode *expected, RangeNode *actual, const char *what)
{
    if (!expected || !actual || expected == actual || deferredType(typer,expected) || deferredType(typer,actual)
        || converts(expected,actual)) return;
    char want[160], got[160];
    describeType(want,sizeof(want),expected); describeType(got,sizeof(got),actual);
    typeError(typer,at,"%s requires %s; found %s",what,want,got);
}

/* `T?` is the enum applying @optional: its single payload case and, in this
 * specialization, the type that case wraps. */
RangeNode *optionalWrapped(Typer *typer, RangeNode *type, RangeNode **present)
{
    if (!isEnum(type) || !appliesBuiltin(type->resolvedDeclaration,"optional")) return NULL;
    RangeNode *declaration = type->resolvedDeclaration, *payload = NULL;
    size_t payloads = 0;
    for (size_t i = 0; i < declaration->itemCount; ++i) {
        RangeNode *entry = declaration->items[i];
        if (entry->kind != RangeNodeEnumCase || !entry->itemCount) continue;
        payloads += entry->itemCount == 1 ? 1 : 2;
        payload = entry;
    }
    if (payloads != 1) return NULL;
    if (present) *present = payload;
    return memberTypeIn(typer,type,payload->items[0]);
}

/* Optional promotion, as in Swift: where `T?` is expected, a value of T is the
 * present case holding it. The optional is recorded beside the expression,
 * whose type stays T. */
static void coerce(Typer *typer, RangeNode *expr, RangeNode *expected, RangeNode *actual, const char *what)
{
    RangeNode *wrapped = NULL;
    if (expr) finding(typer,expr)->promoted = NULL; /* typing records it afresh */
    if (deferredType(typer,expected) || deferredType(typer,actual) || converts(expected,actual)) return;
    if (expr && expected && actual && expected != actual && (wrapped = optionalWrapped(typer,expected,NULL))
        && (wrapped == actual || converts(wrapped,actual))) {
        finding(typer,expr)->promoted = expected;
        return;
    }
    expectType(typer,expr,expected,actual,what);
}

/* `.north` where `Direction?` is expected names Direction's case, unless the
 * optional has a case of that name. */
static RangeNode *caseContext(Typer *typer, RangeNode *enumeration, const char *name)
{
    if (!enumeration || enumCase(enumeration->resolvedDeclaration,name)) return enumeration;
    RangeNode *wrapped = optionalWrapped(typer,enumeration,NULL);
    return isEnum(wrapped) && enumCase(wrapped->resolvedDeclaration,name) ? wrapped : enumeration;
}

/* The law checks `value`: the literal itself, or `-literal` as one value. */
static RangeNode *typeLiteral(Typer *typer, RangeNode *literal, RangeNode *value, RangeNode *expected)
{
    RangeNode *rule = literal->resolvedDeclaration;
    if (!rule || !rule->literalDefault) return NULL;
    RangeNode *declaration = rule->literalDefault, *type;
    RangeNode *wrapped = optionalWrapped(typer,expected,NULL);
    if (wrapped && expected->resolvedDeclaration != declaration) expected = wrapped; /* promoted where it is used */
    if (expected && expected->kind == RangeNodeSpecialization && expected->resolvedDeclaration == declaration) type = expected;
    else type = specialize(typer,NULL,declaration,NULL,NULL,literal);
    if (type && declaration->kind == RangeNodeEnum) {
        // The literal is one of the enum's cases; the enum's laws ran on the declaration.
        if (value != literal || !literalCase(declaration,literal))
            typeError(typer,value,"this literal names no case of %s",declaration->name);
    } else if (type) queueLaws(typer,type,value,value);
    finding(typer,literal)->type = type;
    return type;
}

/* Construction inputs: let and state members that are neither builtin nor
 * @many storage, which starts empty. A member with a default is optional;
 * one without is required. */
int constructionInput(const RangeNode *member)
{
    return (member->kind == RangeNodeLet || member->kind == RangeNodeState)
        && !builtinMember(member) && !(member->flags & RangeFlagMany);
}

/* `let v: T?` written without a value: it starts as the optional's case
 * without a payload, which typing records beside it. */
static int optionalWithoutValue(const RangeNode *node)
{
    return (node->kind == RangeNodeLet || node->kind == RangeNodeState) && node->typeName
        && (node->flags & RangeFlagOptional) && !(node->flags & (RangeFlagApplication | RangeFlagMacroType))
        && !node->rhsReference && !node->a && !node->itemCount;
}

/* A local's value, or a member's default: what typing recorded beside the
 * declaration; else an inferred RHS; the declaration itself for a
 * construction; or a copied name. A bare type reference or a type path is a
 * requirement and supplies nothing. */
RangeNode *declarationValue(RangeNode *key, RangeNode *node)
{
    RangeFacts *facts = found(key,node);
    if (facts->lowered) return facts->lowered;
    if (facts->found & RangeFlagRequired) return NULL;
    if (!node->typeName) return rangeNodeRHS(node);
    if (node->flags & RangeFlagApplication) return node;
    RangeNode *copied = node->rhsReference ? found(key,node->rhsReference)->resolvedDeclaration : NULL;
    return copied && (rangeNodeDeclaresValue(copied->kind) || copied->kind == RangeNodeParameter) ? node->rhsReference : NULL;
}

/* `Point(x: 1, y: 2)`: each argument names the member it populates, and is
 * typed with that member's type in this specialization. */
static RangeNode *typeConstructionOf(Typer *typer, SourceScope *scope, RangeNode *at, RangeNode *type,
                                     RangeNode **arguments, size_t count, RangeNode *context)
{
    if (!type) return NULL;
    RangeNode *declaration = type->resolvedDeclaration;
    if (declaration->kind == RangeNodeEnum) {
        // `Int?(maybe)` copies the enum value given, promoted if it is a Wrapped.
        // A case has one spelling, Light.red or .red in context, so
        // `Light(.red)` is not one.
        RangeNode *given = count == 1 ? arguments[0]->a : NULL;
        if (given && (given->kind == RangeNodeCase || (given->kind == RangeNodeCall && given->a && given->a->kind == RangeNodeCase))) {
            const char *name = given->kind == RangeNodeCase ? given->name : given->a->name;
            const char *written = at->typeName ? at->typeName : at->kind == RangeNodeCall && at->a && at->a->name ? at->a->name : declaration->name;
            const char *optional = (at->flags & RangeFlagOptional) || (at->kind == RangeNodeCall && at->a && (at->a->flags & RangeFlagOptional)) ? "?" : "";
            typeError(typer,at,"an enum value is written %s%s.%s, or .%s where the context names its type; %s%s(.%s) is not Range",
                      written,optional,name,name,written,optional,name);
            return type;
        }
        // An enum value is always a case. `Int?(5)` was a second spelling of
        // `Int?.present(5)`, and `Int?(maybe)` of letting the type be inferred.
        char t[160];
        {
            const char *written = at->typeName ? at->typeName : at->kind == RangeNodeCall && at->a && at->a->name ? at->a->name : declaration->name;
            const char *optional = (at->flags & RangeFlagOptional) || (at->kind == RangeNodeCall && at->a && (at->a->flags & RangeFlagOptional)) ? "?" : "";
            snprintf(t,sizeof(t),"%s%s",written,optional);
        }
        RangeNode *present = NULL;
        if (optionalWrapped(typer,type,&present))
            typeError(typer,at,"an enum is not constructed: write %s.%s(value), or bind the value directly to infer %s",
                      t,present->name,t);
        else if (uninhabited(type))
            typeError(typer,at,"an enum is not constructed, and %s has no cases, so it has no values",t);
        else
            typeError(typer,at,"an enum is not constructed: write %s.%s, or bind a value of %s directly",t,
                      declaration->itemCount ? declaration->items[0]->name : "case",t);
        return type;
    }
    size_t inputs = 0;
    RangeNode *only = NULL;
    for (size_t i = 0; i < declaration->itemCount; ++i)
        if (constructionInput(declaration->items[i])) { ++inputs; only = declaration->items[i]; }
    char typeName[160]; describeType(typeName,sizeof(typeName),type);
    for (size_t i = 0; i < count; ++i) {
        RangeNode *argument = arguments[i], *member = NULL;
        if (!argument->name) {
            if (inputs != 1 || count != 1) { typeError(typer,argument,"%s requires labeled arguments",typeName); continue; }
            member = only;
        } else for (size_t j = 0; j < declaration->itemCount; ++j)
            if (constructionInput(declaration->items[j]) && same(declaration->items[j]->name,argument->name)) member = declaration->items[j];
        if (!member) {
            RangeNode *named = findMember(declaration,argument->name);
            if (named && named->kind == RangeNodeDerived) typeError(typer,argument,"%s has no input '%s': it is derived",typeName,argument->name);
            else typeError(typer,argument,"%s has no input '%s'",typeName,argument->name);
            continue;
        }
        for (size_t j = 0; j < i; ++j)
            if (found(typer->key,arguments[j])->resolvedDeclaration == member) typeError(typer,argument,"'%s' is supplied twice",member->name);
        finding(typer,argument)->resolvedDeclaration = member;
        RangeNode *expected = memberTypeIn(typer,type,member);
        RangeNode *actual = typeOf(typer,scope,argument->a,expected,context);
        char what[200]; snprintf(what,sizeof(what),"input '%s' of %s",member->name,typeName);
        coerce(typer,argument->a,expected,actual,what);
    }
    for (size_t i = 0; i < declaration->itemCount; ++i) {
        RangeNode *member = declaration->items[i];
        if (!constructionInput(member)) continue;
        (void)memberTypeIn(typer,type,member); /* its default, as this specialization has it */
        if (declarationValue(keyOf(declaration,type),member) || optionalWithoutValue(member)) continue;
        int supplied = 0;
        for (size_t j = 0; j < count; ++j) if (found(typer->key,arguments[j])->resolvedDeclaration == member) supplied = 1;
        if (!supplied) typeError(typer,at,"%s requires input '%s'",typeName,member->name);
    }
    return type;
}

static RangeNode *typeConstruction(Typer *typer, SourceScope *scope, RangeNode *at, const char *name, RangeNode *generics,
                                   int flags, RangeNode **arguments, size_t count, RangeNode *context)
{
    RangeNode *type = resolveTypeReference(typer,scope,name,generics,flags & ~RangeFlagApplication,context,at);
    return typeConstructionOf(typer,scope,at,type,arguments,count,context);
}

/* ---- generic functions ----
 * `function first<Element>(let xs: Array<Element>): Element?` is specialized
 * per instantiation, as a construct is: each distinct set of type arguments
 * is one specialization of the declaration, into which its body is typed and
 * compiled with the type parameters naming those types, and the types it
 * mentions run their laws as any specialization does. Arguments are
 * inferred from the call's arguments, then from the type the context
 * expects; `first<Int>(xs: a)` writes them. There are no constraints: a
 * body that uses an operation its types lack fails while it is typed for
 * that specialization, and the error names the specialization. */

static void typeFunction(Typer *, SourceScope *, RangeNode *, RangeNode *);
static void checkMutations(Typer *, RangeNode *);

/* A generic function: typed and compiled only per specialization. */
int genericTemplate(const RangeNode *function)
{
    return function && function->kind == RangeNodeFunction && function->generics && function->generics->itemCount;
}

/* `function scaled<let factor: 2>(…)`: value generics, constants per
 * instantiation as a construct's are per specialization. */
static size_t valueGenericCount(const RangeNode *function)
{
    size_t count = 0;
    for (size_t i = 0; function->generics && i < function->generics->itemCount; ++i)
        count += function->generics->items[i]->kind != RangeNodeTypeParameter;
    return count;
}

static RangeNode *valueGeneric(const RangeNode *function, size_t index)
{
    for (size_t i = 0, k = 0; function->generics && i < function->generics->itemCount; ++i)
        if (function->generics->items[i]->kind != RangeNodeTypeParameter && k++ == index) return function->generics->items[i];
    return NULL;
}

static size_t valueGenericIndex(const RangeNode *function, const char *name)
{
    for (size_t i = 0, k = 0; function->generics && i < function->generics->itemCount; ++i) {
        if (function->generics->items[i]->kind == RangeNodeTypeParameter) continue;
        if (same(function->generics->items[i]->name,name)) return k;
        ++k;
    }
    return SIZE_MAX;
}

static int sameLiteral(const RangeNode *a, const RangeNode *b)
{
    RangeNodeKind ka, kb; long long ia, ib; const char *ta, *tb;
    if (!lawInputs(a,&ka,&ia,&ta) || !lawInputs(b,&kb,&ib,&tb)) return a == b;
    return ka == kb && ia == ib && (ta == tb || (ta && tb && !strcmp(ta,tb)));
}

static size_t typeParameterIndex(const RangeNode *function, const char *name)
{
    for (size_t i = 0, k = 0; function->generics && i < function->generics->itemCount; ++i) {
        if (function->generics->items[i]->kind != RangeNodeTypeParameter) continue;
        if (same(function->generics->items[i]->name,name)) return k;
        ++k;
    }
    return SIZE_MAX;
}

static size_t typeParameterCount(const RangeNode *function)
{
    size_t count = 0;
    for (size_t i = 0; function->generics && i < function->generics->itemCount; ++i)
        count += function->generics->items[i]->kind == RangeNodeTypeParameter;
    return count;
}

static const char *typeParameterName(const RangeNode *function, size_t index)
{
    for (size_t i = 0, k = 0; function->generics && i < function->generics->itemCount; ++i)
        if (function->generics->items[i]->kind == RangeNodeTypeParameter && k++ == index) return function->generics->items[i]->name;
    return "?";
}

/* Whether a written type, such as Array<Element>?, mentions a type parameter. */
static int mentionsParameter(const RangeNode *function, const char *name, const RangeNode *generics)
{
    if (typeParameterIndex(function,name) != SIZE_MAX) return 1;
    for (size_t i = 0; generics && i < generics->itemCount; ++i) {
        const RangeNode *argument = generics->items[i]->a;
        if (!generics->items[i]->name && argument && argument->kind == RangeNodeName
            && mentionsParameter(function,argument->name,argument->generics)) return 1;
    }
    // A function type's result, as in (Element) -> Result.
    const RangeNode *result = generics && same(generics->name,"functionType") ? generics->a : NULL;
    return result && mentionsParameter(function,result->name,result->generics);
}

/* Bind the type parameters a written type mentions by matching it against a
 * type: `Array<Element>` against Array<Int> binds Element to Int, and
 * `Element?` binds it to the wrapped type, or to a plain value promoted there.
 * Returns 0 when a parameter is already bound to another type. */
static int unifyType(Typer *typer, RangeNode *function, const char *name, RangeNode *generics, int flags,
                     RangeNode *actual, RangeNode **bound, size_t *conflict)
{
    // A function type binds through its parameter types and its result:
    // `(Element) -> Result` against (Int) -> Bool binds Result to Bool.
    if ((flags & RangeFlagFunction) && generics) {
        if (!isFunctionType(actual)) return 1; /* coercion reports it */
        for (size_t i = 0; i < generics->itemCount && i < actual->itemCount; ++i) {
            RangeNode *part = generics->items[i]->a;
            if (!unifyType(typer,function,part->name,part->generics,part->flags,actual->items[i],bound,conflict)) return 0;
        }
        RangeNode *result = generics->a;
        return !result || unifyType(typer,function,result->name,result->generics,result->flags,actual->a,bound,conflict);
    }
    // A type parameter binds to any type.
    if (!actual || actual->kind != RangeNodeSpecialization) return 1;
    if ((flags & RangeFlagOptional) && actual->kind == RangeNodeSpecialization) {
        RangeNode *wrapped = optionalWrapped(typer,actual,NULL);
        if (wrapped) actual = wrapped;
    }
    size_t index = typeParameterIndex(function,name);
    if (index != SIZE_MAX && !generics) {
        if (!bound[index]) { bound[index] = actual; return 1; }
        if (bound[index] == actual) return 1;
        *conflict = index;
        return 0;
    }
    if (!generics || actual->kind != RangeNodeSpecialization) return 1;
    SourceScope scope = {.owner=function};
    RangeNode *declaration = dottedLookup(typer->report,&scope,name,2);
    if (!declaration || actual->resolvedDeclaration != declaration || !actual->values) return 1; /* coercion reports it */
    size_t position = 0;
    for (size_t i = 0; i < generics->itemCount; ++i) {
        RangeNode *argument = generics->items[i];
        if (argument->name || !argument->a || argument->a->kind != RangeNodeName) continue;
        for (size_t j = 0, k = 0; j < declaration->generics->itemCount; ++j) {
            if (declaration->generics->items[j]->kind != RangeNodeTypeParameter || k++ != position) continue;
            if (!unifyType(typer,function,argument->a->name,argument->a->generics,argument->a->flags,actual->values[j],bound,conflict))
                return 0;
        }
        ++position;
    }
    return 1;
}

/* A written type of the declaration, with the type parameters bound so far
 * standing for their types; NULL while one it mentions is unbound, which
 * resolves to no type. */
static RangeNode *boundType(Typer *typer, RangeNode *function, const char *name, RangeNode *generics, int flags,
                            RangeNode **bound, RangeNode *at, RangeNode *receiver)
{
    // The types bound so far, as a specialization of the function that is
    // not interned: typing reads its type parameters there.
    RangeArena *arena = typer->report->arena;
    RangeNode *partial = rangeNodeCreate(arena,RangeNodeSpecialization,function->path,function->line,function->column);
    partial->name = function->name;
    partial->resolvedDeclaration = function;
    partial->outer = receiver;
    partial->values = genericValues(arena,function);
    for (size_t i = 0, k = 0; i < function->generics->itemCount; ++i)
        if (function->generics->items[i]->kind == RangeNodeTypeParameter) partial->values[i] = bound[k++];
    // A method's types also name its receiver's type parameters.
    SourceScope ownerScope = {.owner=receiver ? receiver->resolvedDeclaration : NULL};
    SourceScope scope = {.owner=function,.parent=receiver ? &ownerScope : NULL};
    RangeNode *key = typer->key;
    typer->key = partial;
    RangeNode *type = resolveTypeReference(typer,&scope,name,generics,flags,receiver,at);
    typer->key = key;
    return type;
}

/* The specialization of a generic function for these generic values, of
 * these types for its value generics, within its receiver's specialization.
 * Its body is typed into it on first use. */
static RangeNode *instantiate(Typer *typer, RangeNode *function, RangeNode **values, RangeNode **types, RangeNode *at,
                              RangeNode *receiver)
{
    int created = 0;
    RangeNode *specialization = internSpecialization(typer,function,values,receiver,at,&created);
    if (!created) return specialization;
    // Interned before its body is typed, so a recursive call finds it. A
    // method's specialization is typed in its receiver's.
    TyperContext outer = typerSave(typer);
    typer->key = specialization;
    for (size_t i = 0; i < function->generics->itemCount; ++i) /* a value generic is the constant it was made for */
        if (function->generics->items[i]->kind != RangeNodeTypeParameter) finding(typer,function->generics->items[i])->type = types[i];
    SourceScope ownerScope = {.owner=receiver ? receiver->resolvedDeclaration : NULL};
    typeFunction(typer,receiver ? &ownerScope : NULL,function,receiver);
    typerRestore(typer,outer);
    return specialization;
}

/* A call of a generic function: infer its type arguments, then call the
 * specialization for them. Arguments are typed once each: those whose parameter
 * names no type parameter first, with that parameter's type; then the others
 * that need no context; then the expected result; then the rest, such as
 * literals, with whatever the earlier ones bound. */
static RangeNode *typeGenericCall(Typer *typer, SourceScope *scope, RangeNode *call, RangeNode *function,
                                  RangeNode *expected, RangeNode *context, RangeNode *receiver)
{
    RangeNode *callee = call->a;
    size_t count = typeParameterCount(function), conflict = SIZE_MAX;
    RangeNode **bound = rangeArenaAllocate(typer->report->arena,(count ? count : 1) * sizeof(*bound));
    memset(bound,0,(count ? count : 1) * sizeof(*bound));
    if (call->itemCount != function->itemCount)
        typeError(typer,call,"'%s' takes %zu arguments; %zu supplied",function->name,function->itemCount,call->itemCount);
    size_t n = call->itemCount < function->itemCount ? call->itemCount : function->itemCount;
    for (size_t i = 0; i < n; ++i)
        if (callee->name && !argumentFits(call->items[i],function,i))
            typeError(typer,call->items[i],"argument %zu of '%s' requires label '%s'",i + 1,function->name,function->items[i]->name);
    // Value generics: written by label, or their defaults.
    size_t valueCount = valueGenericCount(function);
    RangeNode **values = rangeArenaAllocate(typer->report->arena,(valueCount ? valueCount : 1) * sizeof(*values));
    RangeNode **types = rangeArenaAllocate(typer->report->arena,(valueCount ? valueCount : 1) * sizeof(*types));
    memset(values,0,(valueCount ? valueCount : 1) * sizeof(*values));
    // Written type arguments: positional, or labeled by parameter name.
    size_t positional = 0;
    for (size_t i = 0; callee->generics && i < callee->generics->itemCount; ++i) {
        RangeNode *argument = callee->generics->items[i], *reference = argument->a;
        size_t value = argument->name ? valueGenericIndex(function,argument->name) : SIZE_MAX;
        if (value != SIZE_MAX) { values[value] = argument->a; continue; }
        size_t index = argument->name ? typeParameterIndex(function,argument->name) : positional++;
        if (index >= count) {
            if (argument->name) typeError(typer,argument,"'%s' has no generic '%s'",function->name,argument->name);
            else typeError(typer,argument,"'%s' takes %zu type argument%s",function->name,count,count == 1 ? "" : "s");
            return NULL;
        }
        if (!reference || reference->kind != RangeNodeName) { typeError(typer,argument,"type argument %s requires a type",typeParameterName(function,index)); return NULL; }
        bound[index] = resolveTypeReference(typer,scope,reference->name,reference->generics,reference->flags,context,reference);
        if (!bound[index]) return NULL;
    }
    // A method's signature also names its receiver's type parameters and types.
    SourceScope ownerScope = {.owner=receiver ? receiver->resolvedDeclaration : NULL};
    SourceScope declarationScope = {.owner=function,.parent=receiver ? &ownerScope : NULL};
    RangeNode **actual = rangeArenaAllocate(typer->report->arena,(n ? n : 1) * sizeof(*actual));
    int *done = rangeArenaAllocate(typer->report->arena,(n ? n : 1) * sizeof(*done));
    memset(done,0,(n ? n : 1) * sizeof(*done));
    // A closure for a generic function type is typed last, once the other
    // arguments have bound what its parameters need; its result binds the rest.
    for (int pass = 0; pass < 4; ++pass) {
        if (pass == 2 && expected && function->b)
            (void)unifyType(typer,function,function->b->name,function->b->generics,function->b->flags,expected,bound,&(size_t){0});
        for (size_t i = 0; i < n; ++i) {
            RangeNode *parameter = function->items[i], *value = call->items[i]->a;
            int generic = parameter->b && mentionsParameter(function,parameter->b->name,parameter->b->generics);
            int closure = (parameter->flags & RangeFlagFunction) != 0;
            if (done[i] || (pass == 0 && generic) || (pass == 1 && (!generic || contextual(value) || closure))
                || (pass == 2 && closure)) continue;
            RangeNode *want = !generic ? declaredTypeIn(typer,&declarationScope,parameter,receiver)
                : boundType(typer,function,parameter->b->name,parameter->b->generics,parameter->flags,bound,parameter->b,receiver);
            if (closure && !want) {
                typeError(typer,value,"the parameter types of this closure for '%s' are not known: write the generic arguments, as in %s<…>(…)",
                          function->name,function->name);
                return NULL;
            }
            RangeNode *site = typer->closureSite;
            typer->closureSite = isFunctionType(want) ? value : NULL;
            actual[i] = typeOf(typer,scope,value,want,context);
            typer->closureSite = site;
            done[i] = 1;
            if (generic && !unifyType(typer,function,parameter->b->name,parameter->b->generics,parameter->flags,actual[i],bound,&conflict)) {
                char first[160], second[160];
                describeType(first,sizeof(first),bound[conflict]); describeType(second,sizeof(second),actual[i]);
                typeError(typer,value,"type parameter %s of '%s' is %s from an earlier argument, but argument '%s' is %s",
                          typeParameterName(function,conflict),function->name,first,parameter->name,second);
                return NULL;
            }
        }
    }
    for (size_t k = 0; k < count; ++k)
        if (!bound[k]) {
            typeError(typer,call,"cannot infer type parameter %s of '%s'; write it, as in %s<…>(…)",
                      typeParameterName(function,k),function->name,function->name);
            return NULL;
        }
    // A value generic is a literal of its declared type, checked by that type's laws.
    for (size_t v = 0; v < valueCount; ++v) {
        RangeNode *generic = valueGeneric(function,v);
        RangeNode *want = declaredTypeIn(typer,&declarationScope,generic,receiver);
        if (!values[v] && generic->typeName) {
            typeError(typer,call,"'%s' requires generic %s; write it, as in %s<%s: …>(…)",function->name,generic->name,function->name,generic->name);
            return NULL;
        }
        if (!values[v]) values[v] = rangeNodeRHS(generic);
        RangeNodeKind kind; long long integer; const char *text;
        if (!values[v] || !lawInputs(values[v],&kind,&integer,&text)) {
            typeError(typer,values[v] ? values[v] : call,"generic %s of '%s' requires a literal value",generic->name,function->name);
            return NULL;
        }
        char what[160]; snprintf(what,sizeof(what),"generic %s of '%s'",generic->name,function->name);
        types[v] = typeOf(typer,scope,values[v],want,context);
        expectType(typer,values[v],want,types[v],what);
        if (!types[v] || (want && types[v] != want)) return NULL;
    }
    // The specialization these make, within the receiver's: a method of
    // Box<T> is typed per specialization of Box, so its types are known.
    RangeNode **slots = genericValues(typer->report->arena,function), **slotTypes = genericValues(typer->report->arena,function);
    for (size_t i = 0, k = 0, v = 0; i < function->generics->itemCount; ++i) {
        if (function->generics->items[i]->kind == RangeNodeTypeParameter) slots[i] = bound[k++];
        else { slots[i] = values[v]; slotTypes[i] = types[v++]; }
    }
    RangeNode *specialization = instantiate(typer,function,slots,slotTypes,call,receiver);
    finding(typer,callee)->resolvedDeclaration = function;
    finding(typer,callee)->specialization = specialization;
    for (size_t i = 0; i < n; ++i) {
        char what[160];
        snprintf(what,sizeof(what),"argument '%s' of '%s'",function->items[i]->name,function->name);
        coerce(typer,call->items[i]->a,found(specialization,function->items[i])->type,actual[i],what);
    }
    return found(specialization,function)->type;
}

/* ---- closures ----
 * `{ x in body }` is an argument for a function-typed parameter, typed with
 * that parameter's type: its parameters take the type's parameter types, and
 * its body returns the type's result. A body that is one expression yields
 * it; otherwise `return` does, and returns from the closure only. A closure
 * whose result is a unit type such as Void yields no value. It sees the
 * names where it is written, and may change a `state` there: it runs while
 * the call it is passed to runs, never after. So a closure, and a parameter
 * holding one, is only called or passed on to a function-typed parameter. */

static void typeBlock(Typer *, SourceScope *, RangeNode *, RangeNode *, RangeNode *);
static int exits(RangeNode *, RangeNode *, int);

/* The expression a closure body is: its switch read as an expression, or its
 * one expression statement. */
static RangeNode *closureValue(RangeNode *closure)
{
    if (closure->b) return closure->b;
    RangeNode *body = closure->a;
    if (!body || body->itemCount != 1 || body->items[0]->kind != RangeNodeExpressionStatement) return NULL;
    RangeNode *value = body->items[0]->a;
    return value && value->kind != RangeNodeAttribute ? value : NULL;
}

/* What a typed closure yields: its one expression, unless its result is a
 * unit type; otherwise its body runs and `return` gives the value. */
RangeNode *closureResult(Typer *typer, RangeNode *key, RangeNode *closure)
{
    RangeNode *value = closureValue(closure), *type = found(key,closure)->type;
    return value && !(isFunctionType(type) && unitType(typer,type->a)) ? value : NULL;
}

static RangeNode *typeClosure(Typer *typer, SourceScope *scope, RangeNode *closure, RangeNode *expected, RangeNode *context)
{
    char t[320]; describeType(t,sizeof(t),expected);
    if (closure->itemCount != expected->itemCount) {
        typeError(typer,closure,"this closure takes %zu parameter%s; %s takes %zu",closure->itemCount,
                  closure->itemCount == 1 ? "" : "s",t,expected->itemCount);
        return NULL;
    }
    for (size_t i = 0; i < closure->itemCount; ++i) {
        for (size_t j = 0; j < i; ++j)
            if (same(closure->items[j]->name,closure->items[i]->name))
                typeError(typer,closure->items[i],"'%s' names two parameters of this closure",closure->items[i]->name);
        finding(typer,closure->items[i])->type = expected->items[i];
    }
    SourceScope own = {.owner=closure,.parent=scope};
    RangeNode *result = expected->a, *value = closureValue(closure);
    int unit = unitType(typer,result);
    // `break` and `continue` do not leave the closure; `return` returns from it.
    int loops = typer->loops, inferring = typer->inferring;
    RangeNode *output = typer->output, *inferred = typer->inferred, *site = typer->closureSite;
    typer->loops = 0;
    typer->closures += 1;
    typer->closureSite = NULL;
    typer->output = result;
    typer->inferring = !result;
    typer->inferred = NULL;
    if (value && !unit) {
        RangeNode *actual = typeOf(typer,&own,value,result,context);
        if (result) coerce(typer,value,result,actual,"the result of this closure");
        else result = actual;
    } else {
        typeBlock(typer,&own,closure->a,context,result);
        if (!result) result = typer->inferred;
        if (!result) typeError(typer,closure,"the result of this closure is not known: return a value, or make its body one expression");
        else if (!unit && !exits(typer->key,closure->a,0))
            typeError(typer,closure,"this closure returns %s: return a value on every path, or make its body one expression",
                      (describeType(t,sizeof(t),result),t));
    }
    typer->loops = loops; typer->inferring = inferring; typer->closures -= 1;
    typer->output = output; typer->inferred = inferred; typer->closureSite = site;
    if (!result) return NULL;
    RangeNode **parameters = rangeArenaAllocate(typer->report->arena,(expected->itemCount ? expected->itemCount : 1) * sizeof(*parameters));
    for (size_t i = 0; i < expected->itemCount; ++i) parameters[i] = expected->items[i];
    return functionType(typer,parameters,expected->itemCount,result,closure);
}

/* `where(element)`: a call of the closure a parameter holds, with one
 * unlabeled argument per parameter of its type. */
static RangeNode *typeClosureCall(Typer *typer, SourceScope *scope, RangeNode *call, RangeNode *value, RangeNode *context)
{
    RangeNode *callee = call->a, *type = found(typer->key,value)->type;
    finding(typer,callee)->resolvedDeclaration = value;
    finding(typer,callee)->type = type;
    char t[320]; describeType(t,sizeof(t),type);
    if (callee->generics) typeError(typer,callee,"'%s' is a closure, %s; it takes no type arguments",callee->name,t);
    if (call->itemCount != type->itemCount)
        typeError(typer,call,"'%s' is %s: it takes %zu argument%s; %zu supplied",callee->name,t,type->itemCount,
                  type->itemCount == 1 ? "" : "s",call->itemCount);
    for (size_t i = 0; i < call->itemCount; ++i) {
        RangeNode *argument = call->items[i];
        if (argument->name)
            typeError(typer,argument,"a closure's arguments take no labels: write %s(…) with argument %zu unlabeled",callee->name,i + 1);
        RangeNode *expected = i < type->itemCount ? type->items[i] : NULL;
        RangeNode *actual = typeOf(typer,scope,argument->a,expected,context);
        char what[160]; snprintf(what,sizeof(what),"argument %zu of '%s'",i + 1,callee->name);
        coerce(typer,argument->a,expected,actual,what);
    }
    return type->a;
}

static void typePattern(Typer *, SourceScope *, RangeNode *, RangeNode *, RangeNode *);

/* Inside an enum's own functions, a bare name that is one of its cases
 * tests the receiver; the enum declares no member of that name. */
static int receiverCase(Typer *typer, RangeNode *context, const char *name)
{
    return typer->function && typer->function->typeName && isEnum(context) && enumCase(context->resolvedDeclaration,name);
}

/* A name bound on the right of `|` stands for the left side's: same type. */
static void typeSharedBindings(Typer *typer, RangeNode *pattern)
{
    if (!pattern) return;
    RangeNode *first = pattern->integer == RangePatternBind ? found(typer->key,pattern->a)->resolvedDeclaration : NULL;
    if (first) {
        RangeNode *left = found(typer->key,first)->type, *right = found(typer->key,pattern->a)->type;
        if (left && right && left != right) {
            char f[160], o[160]; describeType(f,sizeof(f),left); describeType(o,sizeof(o),right);
            typeError(typer,pattern->a,"both sides of '|' bind '%s' with one type; the left side binds %s, this side %s",
                      pattern->a->name,f,o);
        }
        return;
    }
    for (size_t i = 0; i < pattern->itemCount; ++i) typeSharedBindings(typer,pattern->items[i]->a);
}

/* ---- narrowing ----
 * A test of a stable optional value for its present case, with no pattern,
 * as in `manager.present`, narrows the value: to the right of the test in
 * the same `&` chain, and in the arm's body or the loop's, the value is the
 * payload of the present case, read with no check. A stable value is a let,
 * a parameter, a #target value, or a member path of one; a state can
 * change and a call is computed again, so neither narrows. A test under `!`
 * or on one side of `|` narrows nothing beyond it, unless both sides of the
 * `|` narrow the same value. The optional is the enum applying @optional.
 * A value known only at macro time is not narrowed: typing does not know
 * that it holds an optional. */

static int narrowablePath(RangeNode *key, RangeNode *path)
{
    if (!path || path->generics) return 0;
    if (path->kind == RangeNodeEnvironment) return 1;
    const RangeNode *declaration = found(key,path)->resolvedDeclaration;
    if (path->kind == RangeNodeMemberAccess)
        return declaration && rangeNodeDeclaresValue(declaration->kind) && narrowablePath(key,path->a);
    if (path->kind != RangeNodeName || (path->flags & RangeFlagImplicit) || !declaration) return 0;
    return declaration->kind == RangeNodeLet || (declaration->kind == RangeNodeParameter && !(declaration->flags & RangeFlagBinding));
}

/* Two narrowable paths read the same value: each step reads the same
 * declaration, narrowed alike. */
static int sameNarrowedPath(RangeNode *key, RangeNode *a, RangeNode *b)
{
    if (!a || !b || a->kind != b->kind) return 0;
    RangeFacts *x = found(key,a), *y = found(key,b);
    if (x->narrowed != y->narrowed) return 0;
    if (a->kind == RangeNodeName) return x->resolvedDeclaration && x->resolvedDeclaration == y->resolvedDeclaration;
    if (a->kind == RangeNodeEnvironment) return same(a->name,b->name);
    return a->kind == RangeNodeMemberAccess && x->resolvedDeclaration == y->resolvedDeclaration && sameNarrowedPath(key,a->a,b->a);
}

static void pushNarrowed(Typer *typer, RangeNode *path, RangeNode *entry, RangeNode *type)
{
    if (typer->narrowedCount == typer->narrowedCapacity) {
        typer->narrowedCapacity = typer->narrowedCapacity ? typer->narrowedCapacity * 2 : 16;
        void *grown = rangeArenaAllocate(typer->report->arena,typer->narrowedCapacity * sizeof(*typer->narrowed));
        if (typer->narrowedCount) memcpy(grown,typer->narrowed,typer->narrowedCount * sizeof(*typer->narrowed));
        typer->narrowed = grown;
    }
    typer->narrowed[typer->narrowedCount].path = path;
    typer->narrowed[typer->narrowedCount].entry = entry;
    typer->narrowed[typer->narrowedCount++].type = type;
}

/* A read of a narrowed value reads its payload: the present case it goes
 * through is recorded beside it, and its type is the payload's. */
static RangeNode *narrowedRead(Typer *typer, RangeNode *expr, RangeNode *type)
{
    if (!type || found(typer->key,expr)->lowered
        || (expr->kind != RangeNodeName && expr->kind != RangeNodeMemberAccess && expr->kind != RangeNodeEnvironment)) return type;
    for (size_t i = typer->narrowedCount; i-- > typer->narrowedFloor;) {
        if (!sameNarrowedPath(typer->key,typer->narrowed[i].path,expr)) continue;
        finding(typer,expr)->narrowed = typer->narrowed[i].entry;
        return finding(typer,expr)->type = typer->narrowed[i].type;
    }
    return type;
}

static RangeNode *typeOperator(Typer *, SourceScope *, RangeNode *, RangeNode *, RangeNode *, RangeNode *);

/* `a | b` narrows what both sides narrow; each side's narrowing holds
 * only within it. */
static RangeNode *typeEither(Typer *typer, SourceScope *scope, RangeNode *expr, RangeNode *context)
{
    size_t mark = typer->narrowedCount;
    RangeNode *left = typeOf(typer,scope,expr->a,NULL,context);
    size_t leftCount = typer->narrowedCount - mark;
    RangeNode **paths = rangeArenaAllocate(typer->report->arena,(leftCount ? leftCount : 1) * sizeof(*paths));
    for (size_t i = 0; i < leftCount; ++i) paths[i] = typer->narrowed[mark + i].path;
    typer->narrowedCount = mark;
    RangeNode *type = left ? typeOperator(typer,scope,expr,left,NULL,context) : (typeOf(typer,scope,expr->b,NULL,context), NULL);
    size_t end = typer->narrowedCount, kept = mark;
    for (size_t i = mark; i < end; ++i) {
        int both = 0;
        for (size_t k = 0; k < leftCount && !both; ++k) both = sameNarrowedPath(typer->key,paths[k],typer->narrowed[i].path);
        if (both) typer->narrowed[kept++] = typer->narrowed[i];
    }
    typer->narrowedCount = kept;
    return type;
}

static RangeNode *typeCaseTest(Typer *typer, SourceScope *scope, RangeNode *test, RangeNode *context)
{
    RangeNode *subject = test->a, *type;
    size_t mark = typer->narrowedCount;
    if (subject->flags & RangeFlagImplicit) {
        finding(typer,subject)->resolvedDeclaration = methodReceiver(typer->report,typer->function);
        finding(typer,subject)->type = type = context;
    } else type = typeOf(typer,scope,subject,NULL,context);
    if (!type) return NULL;
    typePattern(typer,scope,test->b,type,context);
    typeSharedBindings(typer,test->b);
    typer->narrowedCount = mark;
    RangeNode *present = NULL, *payload = optionalWrapped(typer,type,&present), *pattern = test->b;
    if (payload && found(typer->key,pattern)->resolvedDeclaration == present && narrowablePath(typer->key,subject)) {
        RangeNode *bound = pattern->itemCount == 1 ? pattern->items[0]->a : NULL;
        if (!(pattern->flags & RangeFlagApplication)) pushNarrowed(typer,subject,present,payload);
        else if (subject->kind == RangeNodeName && bound && bound->integer == RangePatternBind && same(bound->a->name,subject->name))
            typeError(typer,bound->a,"'%s' is already narrowed to the payload here; related: a test of an optional "
                      "value for its present case narrows that value",subject->name);
    }
    return finding(typer,test)->type = typer->booleanType;
}

/* The arguments of a call, or of a macro application, against the
 * parameters of `callable`, a function or a macro: one per parameter,
 * labeled with its name in order unless `labeled` is 0, each typed where it
 * is written and coerced to its parameter's type in `signature`. */
static void typeArguments(Typer *typer, SourceScope *scope, RangeNode *site, RangeNode *callable, int labeled,
                          SourceScope *signature, RangeNode *receiver, RangeNode *context)
{
    char name[160];
    snprintf(name,sizeof(name),"%s%s",callable->kind == RangeNodeMacro ? "@" : "",callable->name);
    if (site->itemCount != callable->itemCount)
        typeError(typer,site,"'%s' takes %zu arguments; %zu supplied",name,callable->itemCount,site->itemCount);
    for (size_t i = 0; i < site->itemCount && i < callable->itemCount; ++i) {
        RangeNode *argument = site->items[i], *parameter = callable->items[i];
        if (labeled && !argumentFits(argument,callable,i))
            typeError(typer,argument,"argument %zu of '%s' requires label '%s'",i + 1,name,parameter->name);
        RangeNode *expected = declaredTypeIn(typer,signature,parameter,receiver);
        RangeNode *closure = typer->closureSite;
        typer->closureSite = isFunctionType(expected) ? argument->a : NULL;
        RangeNode *actual = typeOf(typer,scope,argument->a,expected,context);
        typer->closureSite = closure;
        char what[200];
        snprintf(what,sizeof(what),"argument '%s' of '%s'",parameter->name,name);
        coerce(typer,argument->a,expected,actual,what);
    }
}

static RangeNode *typeCall(Typer *typer, SourceScope *scope, RangeNode *call, RangeNode *expected, RangeNode *context)
{
    RangeNode *callee = call->a, *function = NULL, *receiver = NULL;
    if (!callee) return NULL;
    if (callee->kind == RangeNodeCase) {
        // `.value(number: 7)`: a case with its payload, of the enum the context expects.
        RangeNode *type = caseContext(typer,contextualEnum(typer,callee,expected),callee->name);
        RangeNode *entry = type ? namedCase(typer,type,callee->name,callee) : NULL;
        if (!entry) return NULL;
        if (!entry->itemCount) { typeError(typer,call,"case '%s' has no payload; write .%s",entry->name,entry->name); return NULL; }
        finding(typer,callee)->resolvedDeclaration = entry;
        typePayload(typer,scope,call,type,entry,call->items,call->itemCount,context);
        return type;
    }
    if (callee->kind == RangeNodeMemberAccess && callee->name) {
        RangeNode *optional = optionalPath(typer,scope,callee->a,context);
        RangeNode *owner = optional ? optional->resolvedDeclaration : typePath(typer->report,scope,callee->a);
        if (owner) {
            // `Outer.Inner(…)` constructs a nested type; `Tree.leaf(value: 1)` a case.
            RangeNode *nested = nestedDeclaration(owner,callee->name,strlen(callee->name));
            if (nested) {
                finding(typer,callee)->resolvedDeclaration = nested;
                return typeConstructionOf(typer,scope,call,specialize(typer,scope,nested,callee->generics,context,call),
                                          call->items,call->itemCount,context);
            }
            if (owner->kind != RangeNodeEnum) {
                typeError(typer,callee,"'%s' has no case or nested type '%s'",owner->name,callee->name);
                return NULL;
            }
            RangeNode *type = optional ? optional : pathEnum(typer,scope,owner,callee->a,expected,context,callee);
            RangeNode *entry = type ? namedCase(typer,type,callee->name,callee) : NULL;
            if (!entry) return NULL;
            if (!entry->itemCount) { typeError(typer,call,"case '%s' has no payload; write %s.%s",entry->name,owner->name,entry->name); return NULL; }
            finding(typer,callee)->resolvedDeclaration = entry;
            typePayload(typer,scope,call,type,entry,call->items,call->itemCount,context);
            return type;
        }
    }
    if (callee->kind == RangeNodeName) {
        // `where(element)` calls the closure a function-typed parameter holds.
        RangeNode *value = sourceLookup(typer->report,scope,callee->name,0);
        if (!value && receiverCase(typer,context,callee->name)) {
            RangeNode *test = finding(typer,call)->lowered = caseTest(typer->report->arena,call,receiverSubject(typer->report->arena,callee),callee->name,call);
            return typeCaseTest(typer,scope,test,context);
        }
        if (value && (value->kind == RangeNodeParameter || rangeNodeDeclaresValue(value->kind)) && isFunctionType(found(typer->key,value)->type))
            return typeClosureCall(typer,scope,call,value,context);
        function = lookupFunction(typer->report,scope,callee->name);
        if (function && function->owner) function = findCalledFunction(function->owner,callee->name,call);
        if (!function) {
            RangeNode *declaration = sourceLookup(typer->report,scope,callee->name,0);
            if (!declaration) declaration = sourceLookup(typer->report,scope,callee->name,2);
            if (declaration && (declaration->kind == RangeNodeConstruct || declaration->kind == RangeNodeEnum
                                || declaration->kind == RangeNodeTypeParameter)) {
                finding(typer,callee)->resolvedDeclaration = declaration;
                return typeConstruction(typer,scope,call,callee->name,callee->generics,callee->flags,call->items,call->itemCount,context);
            }
            if (declaration) typeError(typer,call,"'%s' is not a function",callee->name);
            return NULL; /* undeclared names are reported already */
        }
        if (genericTemplate(function)) return typeGenericCall(typer,scope,call,function,expected,context,function->typeName ? context : NULL);
        if (callee->generics) { typeError(typer,callee,"'%s' takes no type arguments",function->name); return NULL; }
        receiver = function->typeName ? context : NULL;
    } else if (callee->kind == RangeNodeMemberAccess) {
        receiver = typeOf(typer,scope,callee->a,NULL,context);
        if (!receiver) return NULL;
        if (macroOperand(typer,receiver)) {
            // Which function this calls depends on the declaration the value
            // holds: its result is known at macro time.
            RangeNode *kinds[32];
            size_t count = isMacroType(receiver) ? macroKinds(typer,receiver,kinds,32) : 0, declaring = 0;
            for (size_t i = 0; i < count; ++i) declaring += findFunction(kinds[i],callee->name) != NULL;
            if (count && !declaring) {
                char type[160]; describeType(type,sizeof(type),receiver);
                typeError(typer,callee,"%s has no function '%s'",type,callee->name);
                return NULL;
            }
            for (size_t i = 0; i < call->itemCount; ++i) {
                RangeNode *argument = call->items[i]->a;
                if (argument && argument->kind == RangeNodeClosure)
                    typeError(typer,argument,"this closure's parameter types are not known: '%s' is called on a value known only at macro time",
                              callee->name);
                else if (argument) (void)typeOf(typer,scope,argument,NULL,context);
            }
            return typer->deferred;
        }
        if (isEnum(receiver) && callee->name && enumCase(receiver->resolvedDeclaration,callee->name)) {
            // `phase.failed(let reason)`: whether phase holds the case, with its payload's patterns.
            RangeNode *test = finding(typer,call)->lowered = caseTest(typer->report->arena,call,callee->a,callee->name,call);
            return typeCaseTest(typer,scope,test,context);
        }
        // A member with no name is one `for … in` resolved by its @iteration role.
        function = callee->name ? findCalledFunction(receiver->resolvedDeclaration,callee->name,call) : found(typer->key,callee)->resolvedDeclaration;
        if (!function) {
            char type[160]; describeType(type,sizeof(type),receiver);
            typeError(typer,callee,"%s has no function '%s'",type,callee->name);
            return NULL;
        }
        if (genericTemplate(function)) return typeGenericCall(typer,scope,call,function,expected,context,receiver);
    } else {
        typeError(typer,call,"call target is not a function");
        return NULL;
    }
    finding(typer,callee)->resolvedDeclaration = function;
    // A method of a generic declaration runs in its receiver's specialization.
    if (keyOf(function->owner,receiver)) finding(typer,callee)->specialization = typeOnDemand(typer,function,receiver);
    // A method's signature names types in its owner, such as a nested enum.
    SourceScope ownerScope = {.owner=receiver && receiver->kind == RangeNodeSpecialization ? receiver->resolvedDeclaration : NULL};
    SourceScope functionScope = {.owner=function,.parent=ownerScope.owner ? &ownerScope : NULL};
    // A function chosen by its role, as `for … in` chooses its @iteration
    // function, takes its arguments in order, unlabeled.
    typeArguments(typer,scope,call,function,callee->name != NULL,&functionScope,receiver,context);
    RangeNode *output = function->b;
    return output ? resolveTypeReference(typer,&functionScope,output->name,output->generics,output->flags,receiver,output) : NULL;
}

/* `a..<b` is sugar for the construct applying @interval, constructed with
 * lower: a and upper: b: that construction, typed, is what runs in its place. */
static RangeNode *typeInterval(Typer *typer, SourceScope *scope, RangeNode *expr, RangeNode *context)
{
    RangeNode *interval = NULL;
    size_t found = 0;
    for (size_t u = 0; u < typer->report->count; ++u) for (size_t i = 0; i < typer->report->units[u]->itemCount; ++i) {
        RangeNode *candidate = typer->report->units[u]->items[i];
        if (candidate->kind == RangeNodeConstruct && appliesBuiltin(candidate,"interval")) { interval = candidate; ++found; }
    }
    if (found != 1) {
        sourceDiagnostic(typer->report,expr,0,"undeclared","'..<' needs exactly one construct applying @interval; found %zu",found);
        return NULL;
    }
    RangeArena *arena = typer->report->arena;
    RangeNode *callee = rangeNodeCreate(arena,RangeNodeName,expr->path,expr->line,expr->column);
    callee->name = interval->name;
    callee->resolvedDeclaration = interval;
    RangeNode *call = rangeNodeCreate(arena,RangeNodeCall,expr->path,expr->line,expr->column);
    call->a = callee;
    static const char *const labels[] = {"lower","upper"};
    for (int side = 0; side < 2; ++side) {
        RangeNode *argument = rangeNodeCreate(arena,RangeNodeArgument,expr->path,expr->line,expr->column);
        argument->name = labels[side];
        argument->a = side ? expr->b : expr->a;
        rangeNodeAppend(arena,call,argument);
    }
    finding(typer,expr)->lowered = call;
    RangeNode *type = specialize(typer,scope,interval,NULL,context,expr);
    return call->type = typeConstructionOf(typer,scope,call,type,call->items,call->itemCount,context);
}

/* `a + b` and `-a`: the function the operator names on the operand's type.
 * Its parameter and result are typed in that type, as a method's are, so
 * inside Int<bits: 8> `#target.name` is Int<bits: 8>. A function with a body is
 * called: that call, typed, is what runs in the operator's place. A builtin
 * one is the C primitive its name selects, lowered where the operator is. */
static RangeNode *typeOperator(Typer *typer, SourceScope *scope, RangeNode *expr, RangeNode *operand,
                               RangeNode *right, RangeNode *context)
{
    RangeNode *function = operand && operand->kind == RangeNodeSpecialization
        ? operatorFunction(operand->resolvedDeclaration,expr->name,expr->kind == RangeNodeBinary) : NULL;
    char t[160];
    describeType(t,sizeof(t),operand);
    if (!function) {
        if (expr->kind == RangeNodeBinary && !right) (void)typeOf(typer,scope,expr->b,NULL,context);
        typeError(typer,expr,"'%s' is not declared on %s",expr->name,t);
        return NULL;
    }
    if ((function->flags & RangeFlagBuiltin) && (same(expr->name,"!") || shortCircuit(function))
        && operand->resolvedDeclaration != typer->boolean)
        typeError(typer,expr,"builtin '%s' is a C primitive of the condition type only; %s declares it",expr->name,t);
    finding(typer,expr)->resolvedDeclaration = function;
    SourceScope ownerScope = {.owner=operand->resolvedDeclaration};
    SourceScope functionScope = {.owner=function,.parent=&ownerScope};
    if (expr->kind == RangeNodeBinary) {
        RangeNode *parameter = declaredTypeIn(typer,&functionScope,function->items[0],operand);
        if (!right) right = typeOf(typer,scope,expr->b,parameter,context);
        if (!right) return NULL;
        if (parameter == operand && right != operand && optionalWrapped(typer,parameter,NULL) != right && !deferredType(typer,right)) {
            char r[160]; describeType(r,sizeof(r),right);
            typeError(typer,expr,"operator '%s' requires matching types; found %s and %s",expr->name,t,r);
            return NULL;
        }
        char what[160]; snprintf(what,sizeof(what),"the right operand of '%s'",expr->name);
        coerce(typer,expr->b,parameter,right,what);
    }
    RangeNode *output = function->b;
    RangeNode *type = output ? resolveTypeReference(typer,&functionScope,output->name,output->generics,output->flags,operand,output) : NULL;
    if (!(function->flags & RangeFlagBuiltin)) {
        // The call the operator stands for, already typed: receiver.op(other: b).
        RangeArena *arena = typer->report->arena;
        RangeNode *callee = rangeNodeCreate(arena,RangeNodeMemberAccess,expr->path,expr->line,expr->column);
        callee->a = expr->a;
        callee->resolvedDeclaration = function;
        callee->type = type;
        if (keyOf(function->owner,operand)) callee->specialization = typeOnDemand(typer,function,operand);
        RangeNode *call = rangeNodeCreate(arena,RangeNodeCall,expr->path,expr->line,expr->column);
        call->a = callee;
        call->type = type;
        if (expr->kind == RangeNodeBinary) {
            RangeNode *argument = rangeNodeCreate(arena,RangeNodeArgument,expr->path,expr->line,expr->column);
            argument->name = function->items[0]->name;
            argument->a = expr->b;
            rangeNodeAppend(arena,call,argument);
        }
        finding(typer,expr)->lowered = call;
    }
    return type;
}

static RangeNode *typeSwitch(Typer *, SourceScope *, RangeNode *, RangeNode *, RangeNode *, RangeNode *);
static RangeNode *typeExpression(Typer *, SourceScope *, RangeNode *, RangeNode *, RangeNode *);

/* `derived a: b * 2` and `derived b: a + 1` compute each from the other, so
 * neither has a value; any other declarations whose types wait on each
 * other have no type. The cycle is named in source order. */
static void derivedCycle(Typer *typer, RangeNode *declaration, RangeNode **cycle, size_t count)
{
    int derived = 1;
    for (size_t i = 0; i < count; ++i) derived &= cycle[i]->kind == RangeNodeDerived;
    if (!derived) { typeError(typer,declaration,"the type of '%s' depends on itself",declaration->name); return; }
    if (count == 1) { typeError(typer,declaration,"'%s' is derived from itself; it must be state",declaration->name); return; }
    RangeNode *sorted[64];
    for (size_t i = 0; i < count; ++i) {
        size_t j = i;
        for (; j > 0 && (sorted[j - 1]->line > cycle[i]->line
                         || (sorted[j - 1]->line == cycle[i]->line && sorted[j - 1]->column > cycle[i]->column)); --j)
            sorted[j] = sorted[j - 1];
        sorted[j] = cycle[i];
    }
    char names[512] = "";
    for (size_t i = 0; i < count; ++i) {
        size_t used = strlen(names);
        snprintf(names + used,sizeof(names) - used,"%s'%s'",i == 0 ? "" : i + 1 == count ? " and " : ", ",sorted[i]->name);
    }
    typeError(typer,sorted[0],"%s are derived from each other; one of them must be state",names);
}

/* A local of a block in scope whose statement is not typed yet: it is
 * declared later than where it is read. Names a pattern binds are declared
 * by their case tests. */
static int declaredLater(RangeNode *key, SourceScope *scope, RangeNode *declaration)
{
    if ((declaration->kind != RangeNodeLet && declaration->kind != RangeNodeState && declaration->kind != RangeNodeDerived)
        || (found(key,declaration)->found & RangeFlagTyped)) return 0;
    for (; scope; scope = scope->parent)
        if (scope->owner && scope->owner->kind == RangeNodeBlock && !same(scope->owner->name,"bindings"))
            for (size_t i = 0; i < scope->owner->itemCount; ++i) if (scope->owner->items[i] == declaration) return 1;
    return 0;
}

/* The local, binding, or parameter a splice `#width` names: one declared, in
 * the scopes the #graph block is written in, before it. */
static RangeNode *spliceLocal(RangeNode *key, SourceScope *scope, const char *name)
{
    for (SourceScope *at = scope; at; at = at->parent) {
        RangeNode *owner = at->owner;
        for (size_t i = 0; owner && owner->kind != RangeNodeUnit && i < owner->itemCount; ++i) {
            RangeNode *item = owner->items[i];
            if ((rangeNodeDeclaresValue(item->kind) || item->kind == RangeNodeParameter) && same(item->name,name)
                && !declaredLater(key,scope,item)) return item;
        }
    }
    return NULL;
}

/* Quoted code is typed where it lands; its splices are typed where the
 * macro runs. `#target` is the declaration the macro is attached to; any
 * other `#x` is the macro's local x. A nested macro's splices are its own. */
static void typeSplices(Typer *typer, SourceScope *scope, RangeNode *node)
{
    if (!node || node->kind == RangeNodeMacro) return;
    if (spliceChain(node)) {
        RangeNode *root = node;
        while (root->kind != RangeNodeEnvironment) root = root->a;
        RangeNode *local = same(root->name,"target") ? NULL : spliceLocal(typer->key,scope,root->name);
        if (!local && !same(root->name,"target"))
            typeError(typer,root,"#%s names no macro local declared before this #graph block; #target is the declaration the macro is attached to",root->name);
        else {
            finding(typer,root)->resolvedDeclaration = local;
            (void)typeOf(typer,scope,node,NULL,NULL);
        }
        return;
    }
    typeSplices(typer,scope,node->a); typeSplices(typer,scope,node->b); typeSplices(typer,scope,node->c);
    typeSplices(typer,scope,node->generics); typeSplices(typer,scope,node->annotations); typeSplices(typer,scope,node->rhsReference);
    for (size_t i = 0; i < node->itemCount; ++i) typeSplices(typer,scope,node->items[i]);
}

/* An expression's type. A case test's narrowing holds beyond it only
 * through `&` and `|`; reads of a narrowed value read its payload. */
static RangeNode *typeOf(Typer *typer, SourceScope *scope, RangeNode *expr, RangeNode *expected, RangeNode *context)
{
    if (!expr) return NULL;
    RangeFacts *facts = found(typer->key,expr);
    if (facts->narrowed) return facts->type; /* a read narrowed where it is written keeps that narrowing */
    finding(typer,expr)->lowered = NULL; /* typing records it afresh */
    size_t mark = typer->narrowedCount;
    int logic = expr->kind == RangeNodeBinary && (same(expr->name,"&") || same(expr->name,"|"));
    RangeNode *type;
    if (logic && same(expr->name,"|")) {
        type = typeEither(typer,scope,expr,context);
        finding(typer,expr)->type = type;
    } else type = typeExpression(typer,scope,expr,expected,context);
    RangeNode *lowered = found(typer->key,expr)->lowered;
    if (!logic && !(lowered && lowered->kind == RangeNodeCaseTest)) typer->narrowedCount = mark;
    type = narrowedRead(typer,expr,type);
    return type;
}

static RangeNode *typeExpression(Typer *typer, SourceScope *scope, RangeNode *expr, RangeNode *expected, RangeNode *context)
{
    if (!expr) return NULL;
    RangeNode *type = NULL;
    switch (expr->kind) {
    case RangeNodeInteger: case RangeNodeBool: case RangeNodeString:
        type = typeLiteral(typer,expr,expr,expected);
        // An interpolated value is typed where it is written, and written as
        // text: an integer, a case without payloads (a boolean among them),
        // or a string; at macro time also a declaration, by its name.
        for (size_t i = 0; expr->kind == RangeNodeString && i < expr->itemCount; ++i) {
            RangeNode *part = expr->items[i];
            if (part->flags & RangeFlagLiteral) continue;
            RangeNode *written = typeOf(typer,scope,part->a,NULL,context);
            if (!written || ((typer->macro || typer->arguments) && macroTimeType(typer,written))) continue;
            RangeNode *declaration = written->kind == RangeNodeSpecialization ? written->resolvedDeclaration : NULL;
            if (declaration && (declaration == typer->integer || declaration == typer->boolean
                || (isEnum(written) && !enumPayloads(declaration)) || (type && declaration == type->resolvedDeclaration))) continue;
            char name[160]; describeType(name,sizeof(name),written);
            typeError(typer,part->a,"an interpolated value is an integer, a case without payloads, or a string; this one is %s",name);
        }
        break;
    case RangeNodeName: {
        RangeNode *declaration = nameLookup(typer->report,scope,expr);
        finding(typer,expr)->resolvedDeclaration = declaration;
        if (declaration && declaredLater(typer->key,scope,declaration)) {
            typeError(typer,expr,"'%s' is read before its declaration",expr->name);
            break;
        }
        if (!declaration && receiverCase(typer,context,expr->name)) {
            RangeNode *test = finding(typer,expr)->lowered = caseTest(typer->report->arena,expr,receiverSubject(typer->report->arena,expr),expr->name,NULL);
            type = typeCaseTest(typer,scope,test,context);
            break;
        }
        if (!declaration) break;
        if (rangeNodeDeclaresValue(declaration->kind) || declaration->kind == RangeNodeParameter) {
            if (declaration->flags & RangeFlagMany) typeError(typer,expr,"'%s' holds @many storage and is not a value",expr->name);
            // The type was computed where the name was declared, in this same
            // context; a use does not re-derive it (or rerun its laws).
            else if (found(typer->key,declaration)->type) type = found(typer->key,declaration)->type;
            else {
                // `let a: b  let b: a` has no type: each is the other's.
                size_t depth = typer->typingCount;
                for (size_t i = 0; i < depth; ++i)
                    if (typer->typing[i] == declaration) {
                        derivedCycle(typer,declaration,typer->typing + i,depth - i);
                        depth = SIZE_MAX;
                        break;
                    }
                if (depth == SIZE_MAX) break;
                if (depth == sizeof(typer->typing)/sizeof(*typer->typing)) { typeError(typer,expr,"'%s' is derived through too many values to type",expr->name); break; }
                typer->typing[typer->typingCount++] = declaration;
                type = declaredTypeIn(typer,scope,declaration,context);
                --typer->typingCount;
            }
        } else if (declaration->kind == RangeNodeFunction) typeError(typer,expr,"'%s' is a function; call it",expr->name);
        else if ((typer->macro || typer->arguments) && (declaration->kind == RangeNodeConstruct || declaration->kind == RangeNodeEnum)) {
            // At macro time a type is a value of its grammar kind. Written
            // bare, it is the declaration: `written.output != Bool` compares
            // declarations, and `@wraps(type: Int)` passes one. Written with
            // generic arguments, it is the specialization they select, which
            // is interned, so `Array<Int> = Array<Int>`; one that holds only
            // its declaration's defaults is what the bare name names, the
            // declaration: `Int<bits: 64, signed: true> = Int`.
            if (expr->generics) {
                RangeNode *specialization = specialize(typer,scope,declaration,expr->generics,context,expr);
                if (!specialization) break;
                finding(typer,expr)->specialization = specialization;
            }
            RangeNode *kind = declaration->grammarDefinition;
            if (kind && kind->kind == RangeNodeConstruct) type = specialize(typer,NULL,kind,NULL,NULL,expr);
        } else if (declaration->kind == RangeNodeTypeParameter || declaration->kind == RangeNodeConstruct || declaration->kind == RangeNodeEnum)
            typeError(typer,expr,"'%s' names a type, not a value",expr->name);
        if (isFunctionType(type) && (expr != typer->closureSite || !isFunctionType(expected))) {
            typeError(typer,expr,"'%s' holds a closure: call it, as in %s(…), or pass it on to a function-typed parameter; "
                      "it runs only while the call it was passed to runs, so it is not stored, returned, or held in a value",
                      expr->name,expr->name);
            type = NULL;
        }
        break;
    }
    case RangeNodeClosure:
        if (expr != typer->closureSite || !isFunctionType(expected)) {
            typeError(typer,expr,"a closure is an argument for a function-typed parameter, as in xs.filter(where: { x in … }); "
                      "it runs only while that call runs, so it is not stored, returned, or held in a value");
            break;
        }
        type = typeClosure(typer,scope,expr,expected,context);
        break;
    case RangeNodeCase: {
        // `.red`: a case of the enum the context expects.
        RangeNode *enumeration = caseContext(typer,contextualEnum(typer,expr,expected),expr->name);
        RangeNode *entry = enumeration ? namedCase(typer,enumeration,expr->name,expr) : NULL;
        if (!entry) break;
        if (entry->itemCount) { typeError(typer,expr,"case '%s' carries a payload; write .%s(…)",entry->name,entry->name); break; }
        finding(typer,expr)->resolvedDeclaration = entry;
        type = enumeration;
        break;
    }
    case RangeNodeMemberAccess: {
        RangeNode *optional = optionalPath(typer,scope,expr->a,context);
        RangeNode *owner = optional ? optional->resolvedDeclaration : typePath(typer->report,scope,expr->a);
        if (owner) {
            // `Light.red` is a case; `Outer.Inner` names a type.
            if (nestedDeclaration(owner,expr->name,strlen(expr->name))) {
                typeError(typer,expr,"'%s.%s' names a type, not a value",owner->name,expr->name);
                break;
            }
            if (owner->kind != RangeNodeEnum) { typeError(typer,expr,"'%s' names a type, not a value",owner->name); break; }
            RangeNode *enumeration = optional ? optional : pathEnum(typer,scope,owner,expr->a,expected,context,expr);
            RangeNode *entry = enumeration ? namedCase(typer,enumeration,expr->name,expr) : NULL;
            if (!entry) break;
            if (entry->itemCount) { typeError(typer,expr,"case '%s' carries a payload; write %s.%s(…)",entry->name,owner->name,entry->name); break; }
            finding(typer,expr)->resolvedDeclaration = entry;
            type = enumeration;
            break;
        }
        RangeNode *receiver = typeOf(typer,scope,expr->a,NULL,context);
        if (!receiver) break;
        if (deferredType(typer,receiver)) { type = receiver; break; }
        if (isMacroType(receiver)) { type = macroTypeMember(typer,receiver,expr->name,expr); break; }
        RangeNode *declaration = receiver->resolvedDeclaration;
        if (isEnum(receiver) && enumCase(declaration,expr->name)) {
            // `phase.loading`: whether phase holds the case.
            RangeNode *test = finding(typer,expr)->lowered = caseTest(typer->report->arena,expr,expr->a,expr->name,NULL);
            type = typeCaseTest(typer,scope,test,context);
            break;
        }
        RangeNode *member = findMember(declaration,expr->name);
        finding(typer,expr)->resolvedDeclaration = member;
        if (member) {
            if (member->flags & RangeFlagMany) typeError(typer,expr,"'%s' holds @many storage and is not a value",expr->name);
            else type = memberType(typer,declaration,member,receiver);
        } else if (findFunction(declaration,expr->name)) typeError(typer,expr,"'%s.%s' is a function; call it",declaration->name,expr->name);
        else { char t[160]; describeType(t,sizeof(t),receiver); typeError(typer,expr,"%s has no %s '%s'",t,isEnum(receiver) ? "case" : "member",expr->name); }
        break;
    }
    case RangeNodeCall:
        type = typeCall(typer,scope,expr,expected,context);
        break;
    case RangeNodeEnvironment: {
        // A splice of a macro local is that local.
        RangeNode *local = found(typer->key,expr)->resolvedDeclaration;
        if (local) { type = found(typer->key,local)->type; break; }
        // `#target`: the declaration the macro is attached to, a value of
        // its target type; `#target.cases` is a member of it. A target with
        // no grammar declaration has fields without Range types; a field C
        // has no adapter for is reported where the macro resolves.
        if (!same(expr->name,"target")) { typeError(typer,expr,"'#%s' names nothing here; in macro code, #target is the declaration the macro is attached to",expr->name); break; }
        RangeNode *target = typer->macro && typer->macro->b ? typer->macro->b->resolvedDeclaration : NULL;
        if (!typer->macro) typeError(typer,expr,"#target is written only in a macro's body");
        else if (target && target->kind == RangeNodeMacro) type = macroTypeNamed(typer,target->name,expr);
        else if (target && target->kind == RangeNodeConstruct) type = ownSpecialization(typer,target);
        break;
    }
    case RangeNodeEmission:
        if (!typer->macro) { typeError(typer,expr,"#graph is written only in a macro's body"); break; }
        typeSplices(typer,scope,expr->b);
        break;
    case RangeNodePattern:
        // A case test's pattern argument anywhere else.
        if (expr->integer == RangePatternBind)
            typeError(typer,expr,"'let %s' binds a payload field only in a case test",expr->a->name);
        else typeError(typer,expr,"'_' stands for a payload field only in a case test");
        break;
    case RangeNodeSwitch:
        type = typeSwitch(typer,scope,expr,expected,context,typer->output);
        break;
    case RangeNodeUnary: {
        if (same(expr->name,"-") && expr->a && expr->a->kind == RangeNodeInteger) {
            // -128 is one literal: the law sees the negative value.
            type = typeLiteral(typer,expr->a,expr,expected);
            break;
        }
        RangeNode *operand = typeOf(typer,scope,expr->a,expected,context);
        if (macroOperand(typer,operand)) type = typer->deferred; /* its operator is chosen at macro time */
        else if (operand) type = typeOperator(typer,scope,expr,operand,NULL,context);
        break;
    }
    case RangeNodeBinary: {
        const char *op = expr->name;
        if (same(op,"..<")) { type = typeInterval(typer,scope,expr,context); break; }
        int comparison = same(op,"<") || same(op,">") || same(op,"<=") || same(op,">=");
        int equality = same(op,"=") || same(op,"!=");
        RangeNode *want = comparison || equality ? NULL : expected;
        RangeNode *left, *right = NULL;
        // A literal or `.case` takes the other operand's type when that side is neither.
        int rightFirst = contextual(expr->a) && !contextual(expr->b);
        if (rightFirst) {
            right = typeOf(typer,scope,expr->b,want,context);
            left = typeOf(typer,scope,expr->a,right ? right : want,context);
        } else left = typeOf(typer,scope,expr->a,want,context);
        if (!equality) {
            // Any other operator calls the function its left operand's type
            // declares; on a value of a macro type, that is chosen at macro time.
            if (macroOperand(typer,left)) {
                if (!rightFirst) (void)typeOf(typer,scope,expr->b,NULL,context);
                type = typer->deferred;
            } else if (left) type = typeOperator(typer,scope,expr,left,right,context);
            else if (!rightFirst) (void)typeOf(typer,scope,expr->b,NULL,context);
            break;
        }
        if (!rightFirst) right = typeOf(typer,scope,expr->b,deferredType(typer,left) ? NULL : left,context);
        if (!left || !right) break;
        // `=` gives Bool: the built-in structural comparison, or the type's equality function.
        if (deferredType(typer,left) || deferredType(typer,right)) { type = typer->booleanType; break; }
        if (left != right) {
            // A kind's value compares with a value of a macro type it applies,
            // and `maybe = 5` with the present case holding 5.
            RangeNode *leftWrapped = optionalWrapped(typer,left,NULL), *rightWrapped = optionalWrapped(typer,right,NULL);
            if (converts(left,right)) right = left;
            else if (converts(right,left)) left = right;
            else if (leftWrapped && (leftWrapped == right || converts(leftWrapped,right))) { coerce(typer,expr->b,left,right,"operand"); right = left; }
            else if (rightWrapped && (rightWrapped == left || converts(rightWrapped,left))) { coerce(typer,expr->a,right,left,"operand"); left = right; }
        }
        if (left != right) {
            char l[160], r[160]; describeType(l,sizeof(l),left); describeType(r,sizeof(r),right);
            typeError(typer,expr,"operator '%s' requires matching types; found %s and %s",op,l,r);
            break;
        }
        noteEquality(typer,left,expr);
        type = typer->booleanType;
        break;
    }
    default: break; /* unsupported forms are reported already */
    }
    finding(typer,expr)->type = type;
    return type;
}

static void typeBlock(Typer *, SourceScope *, RangeNode *, RangeNode *, RangeNode *);
static RangeNode *typeSwitch(Typer *, SourceScope *, RangeNode *, RangeNode *, RangeNode *, RangeNode *);

/* Whether a type has no values: an enum without cases, such as Never. The
 * rule is structural; C names no such type. */
int uninhabited(const RangeNode *type)
{
    if (!type || type->kind != RangeNodeSpecialization || type->resolvedDeclaration->kind != RangeNodeEnum) return 0;
    for (size_t i = 0; i < type->resolvedDeclaration->itemCount; ++i)
        if (type->resolvedDeclaration->items[i]->kind == RangeNodeEnumCase) return 0;
    return 1;
}

/* Whether a call never returns, as typing under `key` found it: its result
 * type has no values to return, as diagnostic's Never has none. */
static int diverges(RangeNode *key, RangeNode *call)
{
    return call && call->kind == RangeNodeCall && uninhabited(found(key,call)->type);
}

/* Whether control cannot reach the end of `node`: it returns, breaks, or
 * continues on every path, or calls a function that never returns. `break`
 * and `continue` leave the innermost loop; a switch is never their target. A
 * loop nested here ends its own breaks, so they do not leave `node`. */
static int exits(RangeNode *key, RangeNode *node, int breaking)
{
    if (!node) return 0;
    switch (node->kind) {
    case RangeNodeReturn: return 1;
    case RangeNodeBreak: case RangeNodeContinue: return breaking;
    case RangeNodeBlock:
        for (size_t i = 0; i < node->itemCount; ++i) if (exits(key,node->items[i],breaking)) return 1;
        return 0;
    case RangeNodeSwitch:
        if (!node->itemCount) return 0;
        for (size_t i = 0; i < node->itemCount; ++i) {
            RangeNode *entry = node->items[i];
            if (!exits(key,entry->a ? entry->a : entry->b,breaking)) return 0;
        }
        return 1;
    case RangeNodeExpressionStatement: return diverges(key,node->a);
    case RangeNodeCall: return diverges(key,node);
    default: return 0;
    }
}

/* The function a construct or enum declares with @iteration, which `for … in`
 * calls; *count is how many it declares. The role, not a name, selects it. */
RangeNode *iterationFunction(const RangeNode *declaration, size_t *count)
{
    RangeNode *found = NULL;
    *count = 0;
    if (declaration && (declaration->kind == RangeNodeConstruct || declaration->kind == RangeNodeEnum))
        for (size_t i = 0; i < declaration->itemCount; ++i)
            if (declaration->items[i]->kind == RangeNodeFunction && appliesBuiltin(declaration->items[i],"iteration")) {
                found = declaration->items[i];
                ++*count;
            }
    return found;
}

/* A method's parameter's type, or its result's without one, in `view`, a
 * specialization of its owner: what a call on that receiver sees. */
static RangeNode *signatureType(Typer *typer, RangeNode *function, RangeNode *parameter, RangeNode *view)
{
    SourceScope ownerScope = {.owner=view->resolvedDeclaration}, scope = {.owner=function,.parent=&ownerScope};
    if (parameter) return declaredTypeIn(typer,&scope,parameter,view);
    RangeNode *output = function->b;
    return output ? resolveTypeReference(typer,&scope,output->name,output->generics,output->flags,view,output) : NULL;
}

/* The @iteration law, checked in C: a type declares at most one such function,
 * and, in `view`, each specialization of the type, it takes one Int position
 * and returns an optional (the enum applying @optional), absent past the
 * end. The count is checked once, in the declaration's own typing. */
static void checkIteration(Typer *typer, RangeNode *declaration, RangeNode *view)
{
    size_t count = 0;
    RangeNode *function = iterationFunction(declaration,&count);
    if (count > 1 && !typer->key)
        typeError(typer,declaration,"%s '%s' declares %zu @iteration functions; a type declares exactly one",
            rangeNodeKindName(declaration->kind),declaration->name,count);
    if (count != 1 || !view) return;
    RangeNode *integer = typer->integer ? specialize(typer,NULL,typer->integer,NULL,NULL,typer->integer) : NULL;
    RangeNode *output = signatureType(typer,function,NULL,view);
    int position = function->itemCount == 1 && integer && signatureType(typer,function,function->items[0],view) == integer;
    int optional = isEnum(output) && appliesBuiltin(output->resolvedDeclaration,"optional");
    if (!position || !optional)
        typeError(typer,function,"@iteration function '%s' of '%s' must take one Int position and return an optional, such as (let at: Int): Element?",
            function->name,declaration->name);
}

/* The @insertion law, checked in C: a type declares at most one such function,
 * and it takes one element and adds it. When the type also declares an
 * @iteration function, the element is the type that function yields in
 * `view`, each specialization of the type. */
static void checkInsertion(Typer *typer, RangeNode *declaration, RangeNode *view)
{
    size_t count = 0;
    RangeNode *function = insertionFunction(declaration,&count);
    if (count > 1 && !typer->key)
        typeError(typer,declaration,"%s '%s' declares %zu @insertion functions; a type declares at most one",
            rangeNodeKindName(declaration->kind),declaration->name,count);
    if (count != 1 || !view) return;
    RangeNode *iteration = iterationFunction(declaration,&count);
    RangeNode *yields = count == 1 ? signatureType(typer,iteration,NULL,view) : NULL;
    RangeNode *element = yields ? optionalWrapped(typer,yields,NULL) : NULL;
    if (function->itemCount != 1 || (element && signatureType(typer,function,function->items[0],view) != element)) {
        char t[160] = "one element";
        if (element) { char e[140]; describeType(e,sizeof(e),element); snprintf(t,sizeof(t),"one %s, the element its @iteration function yields",e); }
        typeError(typer,function,"@insertion function '%s' of '%s' must take %s",function->name,declaration->name,t);
    }
}

static void typeStatementOnly(Typer *, SourceScope *, RangeNode *, RangeNode *, RangeNode *);

/* A statement's case tests narrow nothing beyond it. */
static void typeStatement(Typer *typer, SourceScope *scope, RangeNode *node, RangeNode *context, RangeNode *output)
{
    size_t mark = typer->narrowedCount;
    typeStatementOnly(typer,scope,node,context,output);
    typer->narrowedCount = mark;
    // A local is declared once its statement is typed: later ones may read it.
    if (node && (node->kind == RangeNodeLet || node->kind == RangeNodeState || node->kind == RangeNodeDerived))
        finding(typer,node)->found |= RangeFlagTyped;
}

/* `let r: step(x: 1)` calls a function: the call, over the written
 * arguments, is the value typing records beside the declaration. */
static RangeNode *typeInitializerCall(Typer *typer, SourceScope *scope, RangeNode *node, RangeNode *context)
{
    RangeNode *callee = rangeNodeCreate(typer->report->arena,RangeNodeName,node->path,node->line,node->column);
    callee->name = node->typeName;
    callee->generics = node->generics;
    RangeNode *call = rangeNodeCreate(typer->report->arena,RangeNodeCall,node->path,node->line,node->column);
    call->a = callee;
    for (size_t i = 0; i < node->itemCount; ++i) rangeNodeAppend(typer->report->arena,call,node->items[i]);
    finding(typer,node)->lowered = call;
    return typeOf(typer,scope,call,NULL,context);
}

static void typeStatementOnly(Typer *typer, SourceScope *scope, RangeNode *node, RangeNode *context, RangeNode *output)
{
    if (!node) return;
    switch (node->kind) {
    case RangeNodeBlock: typeBlock(typer,scope,node,context,output); break;
    case RangeNodeLet: case RangeNodeState: case RangeNodeDerived:
        if (node->typeName && (node->flags & RangeFlagApplication)) {
            // `let r: step(x: 1)` calls a function; a construct here is construction.
            if (!lookupFunction(typer->report,scope,node->typeName)) {
                finding(typer,node)->type = typeConstruction(typer,scope,node,node->typeName,node->generics,node->flags,node->items,node->itemCount,context);
                break;
            }
            finding(typer,node)->type = typeInitializerCall(typer,scope,node,context);
            break;
        }
        finding(typer,node)->type = declaredType(typer,scope,node,context);
        // A local names a value: `let v: Int` alone states a type, and only a
        // construct's member may leave its value to construction.
        if ((node->typeName || (found(typer->key,node)->found & RangeFlagRequired)) && !(node->flags & RangeFlagApplication)
            && !declarationValue(typer->key,node) && !optionalWithoutValue(node))
            typeError(typer,node,node->kind == RangeNodeDerived ? "derived '%s' needs the expression it is computed from"
                      : "'%s' needs an initial value",node->name);
        break;
    case RangeNodeAssign: {
        RangeNode *target = node->a;
        if (target && target->kind == RangeNodeMemberAccess) {
            // `p.x: 5` changes a state member of a state value.
            RangeNode *expected = typeOf(typer,scope,target,NULL,context);
            RangeNode *member = found(typer->key,target)->resolvedDeclaration, *root = target;
            if (member && member->kind == RangeNodeDerived) {
                typeError(typer,node,"'%s' is derived from other values; it is not assigned",member->name);
                break;
            }
            for (;;) {
                RangeNode *through = found(typer->key,root)->resolvedDeclaration;
                if ((root->kind == RangeNodeMemberAccess || root->kind == RangeNodeName) && through && through->kind != RangeNodeState)
                    typeError(typer,node,"cannot assign through %s '%s'",rangeNodeKindName(through->kind),root->name);
                if (root->kind != RangeNodeMemberAccess) break;
                root = root->a;
            }
            if (member) {
                RangeNode *actual = typeOf(typer,scope,node->b,expected,context);
                char what[160]; snprintf(what,sizeof(what),"assignment to '%s'",member->name);
                coerce(typer,node->b,expected,actual,what);
            }
            break;
        }
        if (!target || target->kind != RangeNodeName) { sourceDiagnostic(typer->report,node,0,"not-implemented","assignment to this target is not implemented"); break; }
        RangeNode *declaration = sourceLookup(typer->report,scope,target->name,0);
        finding(typer,target)->resolvedDeclaration = declaration;
        if (!declaration) break;
        if (declaration->kind == RangeNodeDerived) { typeError(typer,node,"'%s' is derived from other values; it is not assigned",target->name); break; }
        if (declaration->kind != RangeNodeState) { typeError(typer,node,"cannot assign to %s '%s'",rangeNodeKindName(declaration->kind),target->name); break; }
        // The state's type was computed where it was declared; an assignment does not re-derive it.
        RangeNode *expected = found(typer->key,declaration)->type ? found(typer->key,declaration)->type : declaredTypeIn(typer,scope,declaration,context);
        RangeNode *actual = typeOf(typer,scope,node->b,expected,context);
        char what[160]; snprintf(what,sizeof(what),"assignment to '%s'",target->name);
        coerce(typer,node->b,expected,actual,what);
        break;
    }
    case RangeNodeWhile: {
        // A while without a condition is the loop `for … in` is written as; it ends at break.
        if (node->a) {
            RangeNode *condition = typeOf(typer,scope,node->a,typer->booleanType,context);
            expectType(typer,node->a,typer->booleanType,condition,"condition");
        }
        typer->loops += 1;
        typeStatement(typer,scope,node->b,context,output);
        typer->loops -= 1;
        break;
    }
    case RangeNodeFor: {
        // The sequence is typed first: its type's @iteration function is the
        // member the loop calls, its one argument the position.
        RangeNode *loop = node->a;
        if (!loop || loop->itemCount != 3) break;
        SourceScope body = {.owner=loop,.parent=scope};
        RangeNode *sequence = loop->items[0];
        typeStatement(typer,&body,sequence,context,output);
        RangeNode *type = found(typer->key,sequence)->type;
        if (!type) break;
        size_t count = 0;
        RangeNode *function = type->kind == RangeNodeSpecialization ? iterationFunction(type->resolvedDeclaration,&count) : NULL;
        if (count != 1) {
            char t[160]; describeType(t,sizeof(t),type);
            if (count) typeError(typer,rangeNodeRHS(sequence),"'for … in' needs one @iteration function; %s declares %zu",t,count);
            else typeError(typer,rangeNodeRHS(sequence),"'for … in' cannot iterate %s: it declares no @iteration function",t);
            break;
        }
        RangeNode *next = loop->items[2]->b->items[0]->a; /* the subject of the switch over the next element */
        finding(typer,next->a)->resolvedDeclaration = function;
        typeStatement(typer,&body,loop->items[1],context,output);
        typeStatement(typer,&body,loop->items[2],context,output);
        break;
    }
    case RangeNodeBreak: case RangeNodeContinue:
        if (!typer->loops)
            typeError(typer,node,"'%s' is only allowed inside a loop%s",node->kind == RangeNodeBreak ? "break" : "continue",
                      typer->closures ? "; a closure's body does not leave a loop around the closure" : "");
        break;
    case RangeNodeReturn:
        if (!output && typer->inferring) {
            // A closure whose result is inferred: its first return decides it.
            if (!node->a) { typeError(typer,node,"return a value: the result of this closure is not known"); break; }
            RangeNode *actual = typeOf(typer,scope,node->a,typer->inferred,context);
            if (!typer->inferred) typer->inferred = actual;
            else coerce(typer,node->a,typer->inferred,actual,"return");
            break;
        }
        if (output) {
            if (!node->a && unitType(typer,output)) break; /* a unit result, such as Void, needs no value */
            if (!node->a) { char t[160]; describeType(t,sizeof(t),output); typeError(typer,node,"return requires %s",t); break; }
            coerce(typer,node->a,output,typeOf(typer,scope,node->a,output,context),"return");
        } else if (node->a) {
            (void)typeOf(typer,scope,node->a,NULL,context);
            typeError(typer,node,"this function returns no value");
        }
        break;
    case RangeNodeSwitch:
        (void)typeSwitch(typer,scope,node,NULL,context,output);
        break;
    case RangeNodeExpressionStatement:
        if (node->a) (void)typeOf(typer,scope,node->a,NULL,context);
        break;
    default: break; /* declarations, and forms reported as not implemented */
    }
}

/* ---- patterns ----
 * A switch covers every combination of its case tests' subjects, by its
 * arms or a default, and runs exactly one arm; an arm that no earlier arm
 * leaves anything for is an error. Coverage is the usefulness of a pattern
 * vector over the rows before it (Maranget's algorithm), one column per
 * subject: an enum case splits a column into its payload fields; values and
 * rows with a guard cover nothing for the rows after them. */

static int patternWild(const RangeNode *pattern)
{
    return !pattern || pattern->integer == RangePatternAny || pattern->integer == RangePatternBind;
}

static RangeNode *patternCase(RangeNode *key, RangeNode *pattern)
{
    return pattern && pattern->integer == RangePatternCase ? found(key,pattern)->resolvedDeclaration : NULL;
}

static RangeNode *patternField(const RangeNode *pattern, size_t index)
{
    return pattern && (pattern->flags & RangeFlagApplication) && index < pattern->itemCount ? pattern->items[index]->a : NULL;
}

static int literalValue(const RangeNode *value, long long *out)
{
    if (!value) return 0;
    if (value->kind == RangeNodeInteger || value->kind == RangeNodeBool) { *out = value->integer; return 1; }
    if (value->kind == RangeNodeUnary && same(value->name,"-") && value->a && value->a->kind == RangeNodeInteger) {
        *out = -value->a->integer;
        return 1;
    }
    return 0;
}

static int sameValuePattern(const RangeNode *a, const RangeNode *b)
{
    long long x, y;
    return a && b && a->integer == RangePatternValue && b->integer == RangePatternValue
        && literalValue(a->a,&x) && literalValue(b->a,&y) && x == y;
}

/* Rows and the vector specialized to one case: its payload fields replace the column. */
static int usefulCase(Typer *typer, RangeNode ***rows, size_t count, RangeNode **q, RangeNode **types, size_t width,
                      RangeNode *entry)
{
    RangeArena *arena = typer->report->arena;
    size_t arity = entry->itemCount, w = arity + width - 1;
    RangeNode **ntypes = rangeArenaAllocate(arena,(w ? w : 1) * sizeof(*ntypes));
    for (size_t i = 0; i < arity; ++i) ntypes[i] = memberTypeIn(typer,types[0],entry->items[i]);
    for (size_t i = 1; i < width; ++i) ntypes[arity + i - 1] = types[i];
    RangeNode ***nrows = rangeArenaAllocate(arena,(count ? count : 1) * sizeof(*nrows));
    size_t n = 0;
    for (size_t r = 0; r <= count; ++r) {
        RangeNode **source = r < count ? rows[r] : q;
        if (r < count && !patternWild(source[0]) && patternCase(typer->key,source[0]) != entry) continue;
        RangeNode **row = rangeArenaAllocate(arena,(w ? w : 1) * sizeof(*row));
        for (size_t i = 0; i < arity; ++i) row[i] = patternWild(source[0]) ? NULL : patternField(source[0],i);
        for (size_t i = 1; i < width; ++i) row[arity + i - 1] = source[i];
        if (r < count) nrows[n++] = row; else q = row;
    }
    return useful(typer,nrows,n,q,ntypes,w);
}

static int useful(Typer *typer, RangeNode ***rows, size_t count, RangeNode **q, RangeNode **types, size_t width)
{
    if (!width) return count == 0;
    RangeArena *arena = typer->report->arena;
    RangeNode *head = q[0], *type = types[0];
    if (head && head->integer == RangePatternCase) {
        RangeNode *entry = patternCase(typer->key,head);
        return entry ? usefulCase(typer,rows,count,q,types,width,entry) : 1;
    }
    RangeNode ***rest = rangeArenaAllocate(arena,(count ? count : 1) * sizeof(*rest));
    size_t n = 0;
    if (!patternWild(head)) {
        // A value or a relation: only rows that are wild here or the same value remain.
        for (size_t r = 0; r < count; ++r)
            if (patternWild(rows[r][0]) || sameValuePattern(rows[r][0],head)) rest[n++] = rows[r] + 1;
        return useful(typer,rest,n,q + 1,types + 1,width - 1);
    }
    if (isEnum(type)) {
        RangeNode *declaration = type->resolvedDeclaration;
        int complete = 1;
        size_t cases = 0;
        for (size_t i = 0; i < declaration->itemCount; ++i) {
            RangeNode *entry = declaration->items[i];
            if (entry->kind != RangeNodeEnumCase) continue;
            ++cases;
            int found = 0;
            for (size_t r = 0; r < count && !found; ++r) found = patternCase(typer->key,rows[r][0]) == entry;
            if (!found) complete = 0;
        }
        if (!cases) return 0; /* no value to match */
        if (complete) {
            for (size_t i = 0; i < declaration->itemCount; ++i)
                if (declaration->items[i]->kind == RangeNodeEnumCase
                    && usefulCase(typer,rows,count,q,types,width,declaration->items[i])) return 1;
            return 0;
        }
    }
    for (size_t r = 0; r < count; ++r) if (patternWild(rows[r][0])) rest[n++] = rows[r] + 1;
    return useful(typer,rest,n,q + 1,types + 1,width - 1);
}

static void typePattern(Typer *typer, SourceScope *scope, RangeNode *pattern, RangeNode *type, RangeNode *context)
{
    if (!pattern) return;
    finding(typer,pattern)->type = type;
    if (deferredType(typer,type)) {
        // Which cases the subject has is known at macro time: what the
        // pattern binds is known then too.
        if (pattern->integer == RangePatternBind) finding(typer,pattern->a)->type = type;
        else if (pattern->integer == RangePatternValue) (void)typeOf(typer,scope,pattern->a,NULL,context);
        else for (size_t i = 0; i < pattern->itemCount; ++i) typePattern(typer,scope,pattern->items[i]->a,type,context);
        return;
    }
    char t[160]; describeType(t,sizeof(t),type);
    switch (pattern->integer) {
    case RangePatternAny: return;
    case RangePatternBind: finding(typer,pattern->a)->type = type; return;
    case RangePatternCase: {
        // `.name` is always a case of the subject's type. The case `for … in`
        // writes without a name is the payload case of the @optional
        // declaration, whose payload is the element.
        if (!type) return;
        RangeNode *entry = NULL;
        if (!pattern->name) {
            (void)optionalWrapped(typer,type,&entry);
            if (!entry) { typeError(typer,pattern,"'for … in' unwraps an optional element; found %s",t); return; }
        } else if (!isEnum(type)) {
            typeError(typer,pattern,"'.%s' matches an enum case, but the subject is %s",pattern->name,t);
            return;
        } else entry = namedCase(typer,type,pattern->name,pattern);
        if (!entry) return;
        finding(typer,pattern)->resolvedDeclaration = entry;
        if (!(pattern->flags & RangeFlagApplication)) return; /* `.value` matches any payload */
        if (!entry->itemCount) { typeError(typer,pattern,"case '%s' has no payload to match",entry->name); return; }
        if (pattern->itemCount != entry->itemCount) {
            typeError(typer,pattern,"case '%s' has %zu payload fields; the pattern matches %zu",entry->name,entry->itemCount,pattern->itemCount);
            return;
        }
        for (size_t i = 0; i < entry->itemCount; ++i) {
            RangeNode *argument = pattern->items[i], *field = entry->items[i];
            if (argument->name && !same(argument->name,field->name))
                typeError(typer,argument,"payload field %zu of '%s' is %s",i + 1,entry->name,
                          labeledField(field) ? field->name : "unlabeled");
            finding(typer,argument)->resolvedDeclaration = field;
            typePattern(typer,scope,argument->a,memberTypeIn(typer,type,field),context);
        }
        return;
    }
    case RangePatternValue: {
        RangeNode *actual = typeOf(typer,scope,pattern->a,type,context);
        expectType(typer,pattern->a,type,actual,"pattern");
        // A literal that names a case of a literal enum is that case's pattern.
        if (isEnum(type) && actual == type) {
            RangeNode *value = pattern->a, *entry = NULL;
            if (isLiteral(value)) entry = literalCase(type->resolvedDeclaration,value);
            else if (found(typer->key,value)->resolvedDeclaration && found(typer->key,value)->resolvedDeclaration->kind == RangeNodeEnumCase)
                entry = found(typer->key,value)->resolvedDeclaration;
            if (entry) { pattern->integer = RangePatternCase; finding(typer,pattern)->resolvedDeclaration = entry; pattern->name = entry->name; return; }
        }
        // Any other value is compared with `=`.
        if (actual == type) noteEquality(typer,type,pattern);
        return;
    }
    }
}


/* The type a switch expression has, from its arms' values: the first arm's,
 * or the optional one arm's value promotes the others to. */
static RangeNode *armsType(Typer *typer, RangeNode *node, RangeNode *type, RangeNode *arm, RangeNode *actual)
{
    if (!type || !actual || type == actual) return type ? type : actual;
    if (deferredType(typer,type) || deferredType(typer,actual)) return typer->deferred;
    if (optionalWrapped(typer,type,NULL) == actual) {
        coerce(typer,arm,type,actual,"an arm of a switch expression");
        return type;
    }
    if (optionalWrapped(typer,actual,NULL) == type) {
        // An earlier arm's value is promoted to the optional this one yields.
        for (size_t i = 0; i < node->itemCount && node->items[i]->a != arm; ++i) {
            RangeNode *earlier = node->items[i]->a;
            if (earlier && (found(typer->key,earlier)->promoted ? found(typer->key,earlier)->promoted : found(typer->key,earlier)->type) == type)
                coerce(typer,earlier,actual,type,"an arm of a switch expression");
        }
        return actual;
    }
    char t[160], a[160]; describeType(t,sizeof(t),type); describeType(a,sizeof(a),actual);
    typeError(typer,arm,"the arms of a switch expression yield one type; this arm yields %s, an earlier one %s",a,t);
    return type;
}

/* A row's patterns, each typed with its subject's type. */
static void typeRow(Typer *typer, SourceScope *scope, RangeNode *row, RangeNode **types, size_t width, RangeNode *context)
{
    if (row->integer != RangePatternRow) { typePattern(typer,scope,row,types[0],context); return; }
    for (size_t k = 0; k < width && k < row->itemCount; ++k) typePattern(typer,scope,row->items[k],types[k],context);
}

/* `switch { condition: body, … }`: every arm must be reachable, and unless
 * a default ends it, the arms' case tests must cover every combination of
 * their subjects' cases. */
static void typeConditionCoverage(Typer *typer, RangeNode *node)
{
    RangeArena *arena = typer->report->arena;
    ConditionShape shape;
    conditionShape(arena,typer->key,node,&shape);
    size_t width = shape.width;
    RangeNode **types = rangeArenaAllocate(arena,(width ? width : 1) * sizeof(*types));
    RangeNode **cases = rangeArenaAllocate(arena,(width ? width : 1) * sizeof(*cases));
    for (size_t k = 0; k < width; ++k) {
        types[k] = found(typer->key,shape.subjects[k])->type;
        cases[k] = isEnum(types[k]) ? types[k]->resolvedDeclaration : NULL;
    }
    int *reached = rangeArenaAllocate(arena,(shape.count ? shape.count : 1) * sizeof(*reached));
    char missing[512] = "";
    int complete = conditionCoverage(arena,typer,&shape,types,cases,reached,missing,sizeof(missing));
    RangeNode *reported = NULL;
    for (size_t i = 0; i < shape.count; ++i) {
        RangeNode *entry = shape.arms[i];
        if (reached[i] || (entry->flags & RangeFlagImplicit) || entry == reported) continue;
        reported = entry;
        if (entry->flags & RangeFlagLiteral) typeError(typer,entry,"'default' is never reached: the arms above match every value");
        else typeError(typer,entry->items[0]->b,"this condition is already handled by earlier arms");
    }
    if (complete) return;
    if (!*missing) { typeError(typer,node,"switch must be exhaustive; add a default"); return; }
    int many = strchr(missing,',') != NULL;
    typeError(typer,node,"switch must be exhaustive: %s %s not handled; add %s or a default",missing,
              many ? "are" : "is",many ? "arms for them" : "an arm for it");
}

/* A switch statement, or, with RangeFlagValue, a switch expression: its type
 * is the one its arms yield, each typed with `expected` (or, without one,
 * with the first value's type) as context, as any value is. An arm that does
 * not yield is a block that must diverge. A switch over conditions has no
 * subjects; the switch a for loop lowers to has one. */
static RangeNode *typeSwitch(Typer *typer, SourceScope *scope, RangeNode *node, RangeNode *expected, RangeNode *context, RangeNode *output)
{
    size_t errors = typer->report->errors;
    RangeArena *arena = typer->report->arena;
    size_t width = node->c ? node->c->itemCount : 1;
    RangeNode **types = rangeArenaAllocate(arena,(width ? width : 1) * sizeof(*types));
    int typed = 1;
    for (size_t k = 0; k < width; ++k) {
        types[k] = typeOf(typer,scope,node->c ? node->c->items[k] : node->a,NULL,context);
        typed &= types[k] != NULL;
    }
    int value = (node->flags & RangeFlagValue) != 0;
    RangeNode *type = NULL;
    for (size_t i = 0; i < node->itemCount; ++i) {
        RangeNode *entry = node->items[i];
        size_t narrowed = typer->narrowedCount; /* what the arm's condition narrows holds in its body */
        if ((entry->flags & RangeFlagLiteral) && i + 1 != node->itemCount)
            typeError(typer,entry,"'default' must be the last arm of a switch");
        for (size_t j = 0; j < entry->itemCount; ++j) {
            // The parser checked where the row binds; its condition sees its bindings.
            RangeNode *row = entry->items[j], *bindings = row->c;
            typeRow(typer,scope,row,types,width,context);
            if (row->b) {
                SourceScope bound = {.owner=bindings ? bindings : entry,.parent=scope};
                expectType(typer,row->b,typer->booleanType,typeOf(typer,&bound,row->b,typer->booleanType,context),"condition");
            }
        }
        SourceScope body = {.owner=entry->c ? entry->c : entry,.parent=scope};
        if (entry->a) {
            RangeNode *actual = typeOf(typer,&body,entry->a,expected ? expected : type,context);
            RangeNode *callee = entry->a->kind == RangeNodeCall && entry->a->a ? found(typer->key,entry->a->a)->resolvedDeclaration : NULL;
            // A call of a function without a result yields nothing; one that
            // never returns diverges, so its arm yields no value.
            if (!actual && callee && callee->kind == RangeNodeFunction && !callee->b)
                typeError(typer,entry->a,"an arm of a switch expression yields a value or diverges; '%s' returns no value",callee->name);
            if (!diverges(typer->key,entry->a)) type = armsType(typer,node,type,entry->a,actual);
            typer->narrowedCount = narrowed;
            continue;
        }
        typeBlock(typer,&body,entry->b,context,output);
        typer->narrowedCount = narrowed;
        if (value && !exits(typer->key,entry->b,typer->loops > 0))
            typeError(typer,entry->b,"an arm of a switch expression yields a value or diverges; this block ends without return, break, continue, or a call that never returns");
    }
    if (value && !type && typer->report->errors == errors)
        typeError(typer,node,"no arm of this switch expression yields a value");
    finding(typer,node)->type = type;
    if (!typed || typer->report->errors != errors) return type;
    if (!width) { typeConditionCoverage(typer,node); return type; }
    // Each row must match something the earlier ones do not; together they
    // must match every value, or every combination of the subjects' values.
    // A row with a condition covers nothing for the rows after it.
    size_t capacity = 1;
    for (size_t i = 0; i < node->itemCount; ++i) capacity += node->items[i]->itemCount + 1;
    RangeNode ***rows = rangeArenaAllocate(arena,capacity * sizeof(*rows));
    size_t count = 0;
    for (size_t i = 0; i < node->itemCount; ++i) {
        RangeNode *entry = node->items[i];
        size_t patterns = (entry->flags & RangeFlagLiteral) ? 1 : entry->itemCount;
        for (size_t j = 0; j < patterns; ++j) {
            RangeNode *pattern = (entry->flags & RangeFlagLiteral) ? NULL : entry->items[j];
            RangeNode **row = rangeArenaAllocate(arena,width * sizeof(*row));
            patternRow(pattern,row,width);
            // A default the compiler wrote for a lowering may be unreachable.
            if (!useful(typer,rows,count,row,types,width) && !(entry->flags & RangeFlagImplicit)) {
                if (pattern) typeError(typer,pattern,"this pattern is already handled by earlier arms");
                else typeError(typer,entry,"'default' is never reached: the arms above match every value");
            }
            if (!pattern || !pattern->b) rows[count++] = row;
        }
    }
    RangeNode **wild = rangeArenaAllocate(arena,width * sizeof(*wild));
    patternRow(NULL,wild,width);
    if (!useful(typer,rows,count,wild,types,width)) return type;
    char t[480] = "";
    for (size_t k = 0, used = 0; k < width; ++k) {
        char one[160]; describeType(one,sizeof(one),types[k]);
        used += (size_t)snprintf(t + used,sizeof(t) > used ? sizeof(t) - used : 0,"%s%s",k ? ", " : "",one);
    }
    char missing[512] = "";
    RangeNode *subject = types[0];
    size_t length = 0;
    if (isEnum(subject))
        for (size_t i = 0; i < subject->resolvedDeclaration->itemCount; ++i) {
            RangeNode *entry = subject->resolvedDeclaration->items[i];
            if (entry->kind != RangeNodeEnumCase || !usefulCase(typer,rows,count,wild,types,1,entry)) continue;
            if (length + strlen(entry->name) + 8 < sizeof(missing))
                length += (size_t)snprintf(missing + length,sizeof(missing) - length,"%s'.%s'",length ? ", " : "",entry->name);
        }
    if (length) typeError(typer,node,"switch over %s must be exhaustive: %s %s not handled; add %s or a default",t,missing,
                          strchr(missing,',') ? "are" : "is",strchr(missing,',') ? "those cases" : "that case");
    else typeError(typer,node,"switch over %s must be exhaustive; add a default",t);
    return type;
}

static void typeBlock(Typer *typer, SourceScope *parent, RangeNode *block, RangeNode *context, RangeNode *output)
{
    if (!block) return;
    SourceScope scope = {.owner=block,.parent=parent};
    for (size_t i = 0; i < block->itemCount; ++i) typeStatement(typer,&scope,block->items[i],context,output);
}

static void typeFunction(Typer *typer, SourceScope *parent, RangeNode *function, RangeNode *context)
{
    if (found(typer->key,function)->found & RangeFlagTyped) return;
    finding(typer,function)->found |= RangeFlagTyped;
    SourceScope scope = {.owner=function,.parent=parent};
    // An operator takes its right operand, or nothing when it is prefix.
    if (function->typeName && operatorName(function->name)) {
        int prefix = same(function->name,"-") || same(function->name,"!");
        int binary = !same(function->name,"!");
        if (!((binary && function->itemCount == 1) || (prefix && function->itemCount == 0)))
            typeError(typer,function,"operator '%s' takes %s; %s.%s takes %zu",function->name,
                      prefix && binary ? "one parameter, the right operand, or none as a prefix" : prefix ? "no parameters" : "one parameter, the right operand",
                      function->typeName,function->name,function->itemCount);
    }
    // `&` and `|` are the condition type's short-circuit logic, and they join
    // the patterns and conditions of a switch label: no other type declares them.
    if (function->typeName && (same(function->name,"&") || same(function->name,"|"))
        && (!(function->flags & RangeFlagBuiltin) || !context || context->resolvedDeclaration != typer->boolean))
        typeError(typer,function,"'%s' is reserved for Bool logic; %s cannot declare it",
                  function->name,function->typeName);
    // A method's receiver is specialized by the receiver's own parameters.
    if (function->typeName && context) finding(typer,methodReceiver(typer->report,function))->type = context;
    TyperContext outer = typerSave(typer);
    typer->narrowedFloor = typer->narrowedCount;
    typer->loops = 0;
    typer->inferring = 0;
    typer->closures = 0;
    typer->closureSite = NULL;
    typer->macro = NULL; /* a function a macro instantiates is not macro code */
    typer->arguments = 0;
    typer->function = function;
    for (size_t i = 0; i < function->itemCount; ++i)
        finding(typer,function->items[i])->type = declaredType(typer,&scope,function->items[i],context);
    RangeNode *output = function->b
        ? resolveTypeReference(typer,&scope,function->b->name,function->b->generics,function->b->flags,context,function->b) : NULL;
    finding(typer,function)->type = output;
    typer->output = output;
    if (function->a) typeBlock(typer,&scope,function->a,context,output);
    // A result type without values has nothing to return: every path ends
    // in a call that never returns, so a call of the function diverges.
    if (function->a && uninhabited(output) && !exits(typer->key,function->a,0)) {
        char name[160]; describeType(name,sizeof(name),output);
        typeError(typer,function,"'%s' returns %s, which has no values: every path of its body ends in a call that never returns",
                  function->name,name);
    }
    typerRestore(typer,outer);
}

/* A macro's body is typed as a function's is, returning no value, in place
 * and once, as it is first applied: its parameters, its locals, and
 * top-level functions are in scope; `#target` is the declaration it is
 * attached to, a value of its target type; #graph code is typed where it lands, its splices here. Typing at
 * the first application reports what the source pass would then, and a body
 * with anything unresolved or mistyped does not run. A macro never applied
 * is typed after macro time; the source pass checked it. */
static void typeMacro(Typer *typer, SourceScope *parent, RangeNode *macro, int diagnose)
{
    if (!macro->a || (macro->found & RangeFlagTyped)) return; /* a @builtin macro has no body */
    size_t errors = typer->report->errors;
    if (diagnose) diagnoseSourceNode(typer->report,parent,macro,0);
    macro->found |= RangeFlagTyped;
    SourceScope scope = {.owner=macro,.parent=parent};
    TyperContext outer = typerSave(typer);
    typer->narrowedFloor = typer->narrowedCount;
    typer->function = NULL;
    typer->output = NULL;
    typer->macro = macro;
    typer->key = NULL; /* a macro's body is typed once, in place */
    for (size_t i = 0; i < macro->itemCount; ++i) finding(typer,macro->items[i])->type = declaredType(typer,&scope,macro->items[i],NULL);
    typeBlock(typer,&scope,macro->a,NULL,NULL);
    checkMutations(typer,macro->a);
    typerRestore(typer,outer);
    if (typer->report->errors != errors) macro->found |= RangeFlagInvalid;
}

/* Two written types are the same when they are spelled alike: name, flags,
 * and generic arguments. Used where types are not resolved: generic templates. */
static int sameTypeSyntax(const RangeNode *x, const RangeNode *y)
{
    if (!x || !y) return x == y;
    if (x->kind != y->kind || !same(x->name ? x->name : "",y->name ? y->name : "") || x->integer != y->integer
        || x->flags != y->flags || x->itemCount != y->itemCount) return 0;
    if (!sameTypeSyntax(x->a,y->a) || !sameTypeSyntax(x->generics,y->generics)) return 0;
    for (size_t i = 0; i < x->itemCount; ++i) if (!sameTypeSyntax(x->items[i],y->items[i])) return 0;
    return 1;
}

/* Overloads differ in their labels or parameter types. Two functions of one
 * scope with the same name, labels, and parameter types are ambiguous: no
 * call could choose between them. */
static void checkOverloads(Typer *typer, RangeNode *owner)
{
    for (size_t i = 0; i < owner->itemCount; ++i) {
        RangeNode *second = owner->items[i];
        if (second->kind != RangeNodeFunction) continue;
        for (size_t j = 0; j < i; ++j) {
            RangeNode *first = owner->items[j];
            if (first->kind != RangeNodeFunction || !same(first->name,second->name) || first->itemCount != second->itemCount) continue;
            int differ = 0;
            for (size_t k = 0; k < first->itemCount && !differ; ++k) {
                RangeNode *x = first->items[k], *y = second->items[k];
                if (!same(x->name,y->name)) differ = 1;
                else if (found(typer->key,x)->type && found(typer->key,y)->type) differ = found(typer->key,x)->type != found(typer->key,y)->type;
                else differ = (x->flags & ~RangeFlagBinding) != (y->flags & ~RangeFlagBinding) || !sameTypeSyntax(x->b,y->b);
            }
            if (differ) continue;
            char origin[512];
            if (first->emittedBy) snprintf(origin,sizeof(origin),"first emitted by @%s at %s:%d",first->emittedBy->name,first->emittedBy->path,first->emittedBy->line);
            else snprintf(origin,sizeof(origin),"first declared at %s:%d",first->path,first->line);
            RangeNode *at = second->emittedBy ? second->emittedBy : second;
            sourceDiagnostic(typer->report,at,0,"type","ambiguous: %s is declared twice with the same signature; %s",second->name,origin);
            break;
        }
    }
}

static void typeConstruct(Typer *, SourceScope *, RangeNode *);
static void typeLaws(Typer *, RangeNode *, RangeNode *);

/* A case's payload fields are typed in the enum's own specialization; its
 * methods see that specialization as `self`. A generic enum's are typed per
 * specialization the program uses, as they are used. */
static void typeEnum(Typer *typer, SourceScope *parent, RangeNode *declaration)
{
    RangeNode *context = ownSpecialization(typer,declaration);
    SourceScope scope = {.owner=declaration,.parent=parent};
    for (size_t i = 0; i < declaration->itemCount; ++i) {
        RangeNode *item = declaration->items[i];
        if (item->kind == RangeNodeEnumCase && context)
            for (size_t j = 0; j < item->itemCount; ++j) typeMember(typer,&scope,item->items[j],context);
        else if (item->kind == RangeNodeConstruct) typeConstruct(typer,&scope,item);
        else if (item->kind == RangeNodeEnum) typeEnum(typer,&scope,item);
    }
    // Methods are typed once every case's payload is; a generic one per specialization.
    for (size_t i = 0; context && i < declaration->itemCount; ++i)
        if (declaration->items[i]->kind == RangeNodeFunction && !genericTemplate(declaration->items[i]))
            typeFunction(typer,&scope,declaration->items[i],context);
    typeLaws(typer,declaration,context);
    checkOverloads(typer,declaration);
}

/* The first member of `declaration`, at `index` or later, that a member
 * default refers to by bare name: defaults run in declaration order, so they
 * see only the members before them. */
static RangeNode *laterMember(RangeNode *key, RangeNode *declaration, size_t index, RangeNode *node, unsigned depth)
{
    if (!node || depth > 64 || node->kind == RangeNodeFunction || node->kind == RangeNodeConstruct || node->kind == RangeNodeEnum) return NULL;
    RangeNode *target = node->kind == RangeNodeName ? found(key,node)->resolvedDeclaration : NULL;
    for (size_t i = index; target && i < declaration->itemCount; ++i)
        if (declaration->items[i] == target) return target;
    // A derived member before it is computed from its own expression, read now.
    if (target && target->kind == RangeNodeDerived && memberOf(declaration,target)) {
        RangeNode *value = declarationValue(key,target);
        RangeNode *later = value == target ? NULL : laterMember(key,declaration,index,value,depth + 1);
        for (size_t i = 0; !later && value == target && i < target->itemCount; ++i)
            later = laterMember(key,declaration,index,target->items[i],depth + 1);
        if (later) return later;
    }
    RangeNode *later = laterMember(key,declaration,index,node->a,depth);
    if (!later) later = laterMember(key,declaration,index,node->b,depth);
    for (size_t i = 0; !later && i < node->itemCount; ++i) later = laterMember(key,declaration,index,node->items[i],depth);
    return later;
}

/* `let height: width` and `let area: width * 2` are defaults computed at
 * construction from the members declared before them, supplied or defaulted.
 * Unlike `derived`, they are evaluated once. */
static void checkMemberDefaults(Typer *typer, RangeNode *declaration)
{
    for (size_t i = 0; i < declaration->itemCount; ++i) {
        RangeNode *member = declaration->items[i];
        if (!constructionInput(member)) continue;
        RangeNode *later = NULL;
        if (member->typeName && !(member->flags & RangeFlagApplication)) {
            // A bare name: a member copied, or a type required.
            RangeNode *named = !member->generics && !(member->flags & RangeFlagOptional) ? findMember(declaration,member->typeName) : NULL;
            for (size_t j = i; named && j < declaration->itemCount; ++j) if (declaration->items[j] == named) later = named;
            if (!later && named && named->kind == RangeNodeDerived && member->rhsReference)
                later = laterMember(typer->key,declaration,i,member->rhsReference,0);
        } else if (member->typeName) {
            for (size_t j = 0; !later && j < member->itemCount; ++j) later = laterMember(typer->key,declaration,i,member->items[j],0);
        } else later = laterMember(typer->key,declaration,i,rangeNodeRHS(member),0);
        if (later == member)
            typeError(typer,member,"the default of '%s' refers to '%s' itself",member->name,member->name);
        else if (later)
            typeError(typer,member,"the default of '%s' refers to '%s', which is declared after it; a default sees only the members before it",
                      member->name,later->name);
    }
}

/* The C laws on a construct's or enum's members and functions, in `view`,
 * one of its specializations, under its key, with every member and payload
 * field typed there: its own as typing in order reaches it, any other once
 * typing is done. Without a view, only what holds for every specialization. */
static void typeLaws(Typer *typer, RangeNode *declaration, RangeNode *view)
{
    TyperContext outer = typerTop(typer);
    typer->key = keyOf(declaration,view);
    for (size_t i = 0; view && i < declaration->itemCount; ++i) {
        RangeNode *item = declaration->items[i];
        if (rangeNodeDeclaresValue(item->kind)) (void)memberTypeIn(typer,view,item);
        for (size_t j = 0; item->kind == RangeNodeEnumCase && j < item->itemCount; ++j) (void)memberTypeIn(typer,view,item->items[j]);
    }
    if (view) checkMemberDefaults(typer,declaration);
    checkIteration(typer,declaration,view);
    checkInsertion(typer,declaration,view);
    typerRestore(typer,outer);
}

/* A member's type in a specialization of its construct, once. */
static void typeMember(Typer *typer, SourceScope *scope, RangeNode *item, RangeNode *context)
{
    if (found(typer->key,item)->found & RangeFlagTyped) return;
    finding(typer,item)->found |= RangeFlagTyped;
    // A derived member is computed on the instance it is read on, an instance of its owner.
    if (item->kind == RangeNodeDerived && scope && scope->owner && scope->owner->kind == RangeNodeConstruct) item->owner = scope->owner;
    if (item->typeName && (item->flags & RangeFlagApplication)) {
        // A member initialized by construction, e.g. `state from: Point(x: 0)`.
        if (!lookupFunction(typer->report,scope,item->typeName))
            finding(typer,item)->type = typeConstruction(typer,scope,item,item->typeName,item->generics,item->flags,
                                          item->items,item->itemCount,context);
        else if (item->kind == RangeNodeDerived) finding(typer,item)->type = typeInitializerCall(typer,scope,item,context); /* computed on each read */
        else typeError(typer,item,"member '%s' cannot be initialized by calling '%s'",item->name,item->typeName);
        return;
    }
    finding(typer,item)->type = declaredType(typer,scope,item,context);
    // A derived member is computed from its expression on every read; it is never supplied.
    if (item->kind == RangeNodeDerived && !declarationValue(typer->key,item))
        typeError(typer,item,"derived '%s' needs the expression it is computed from",item->name);
}

/* A construct's members and methods are typed in its own specialization,
 * in order; a generic construct's per specialization the program uses, as
 * they are used. */
static void typeConstruct(Typer *typer, SourceScope *parent, RangeNode *declaration)
{
    RangeNode *context = ownSpecialization(typer,declaration);
    SourceScope scope = {.owner=declaration,.parent=parent};
    for (size_t i = 0; i < declaration->itemCount; ++i) {
        RangeNode *item = declaration->items[i];
        if (rangeNodeDeclaresValue(item->kind) && context) typeMember(typer,&scope,item,context);
        else if (item->kind == RangeNodeFunction && !genericTemplate(item) && context) typeFunction(typer,&scope,item,context);
        else if (item->kind == RangeNodeConstruct) typeConstruct(typer,&scope,item);
        else if (item->kind == RangeNodeEnum) typeEnum(typer,&scope,item);
    }
    typeLaws(typer,declaration,context);
    checkOverloads(typer,declaration);
}

int builtinMember(const RangeNode *member)
{
    if (!rangeNodeDeclaresValue(member->kind) || !member->c) return 0;
    for (size_t i = 0; i < member->c->itemCount; ++i)
        if (same(member->c->items[i]->name,"builtin")) return 1;
    return 0;
}

/* ---- layout --------------------------------------------------------------
 * A construct with a builtin `storage` member is a scalar exactly that many
 * bits wide; its other members are its meaning, not separate storage. Any
 * other construct lays its members out in order with natural alignment. A
 * @many member is an 8-byte address. C reads widths from the specialization
 * it materialized; it never names a construct or a generic. */

/* A builtin member's value in a specialization: the generic its value
 * names, as the specialization holds it, or the value written. */
RangeNode *builtinValue(RangeNode *specialization, RangeNode *member)
{
    RangeNode *value = rangeNodeRHS(member), *declared = specialization->resolvedDeclaration->generics;
    for (size_t i = 0; value && value->kind == RangeNodeName && declared && specialization->values && i < declared->itemCount; ++i)
        if (same(declared->items[i]->name,value->name)) return specialization->values[i];
    return value;
}

static long long storageBits(Typer *typer, RangeNode *specialization, RangeNode *storage)
{
    RangeNode *value = builtinValue(specialization,storage);
    if (!value || value->kind != RangeNodeInteger) {
        sourceDiagnostic(typer->report,storage,0,"layout","builtin 'storage' requires an integer bit width");
        return 0;
    }
    return value->integer;
}

/* Grammar constructs describe C's graph nodes: C provides their values at
 * compile time, and they have no runtime layout. */
static int graphConstruct(Typer *typer, const RangeNode *declaration)
{
    RangeNode *shapes = typer->report->arena->graphTypes;
    for (size_t i = 0; shapes && i < shapes->itemCount; ++i)
        if (shapes->items[i]->resolvedDeclaration == declaration) return 1;
    return 0;
}

/* Whether a value of `type` holds a value of `target` in its own bytes,
 * through construct members and enum payloads stored inline. */
typedef struct { RangeNode *seen[64]; size_t count; } Containment;

static int containsInline(Typer *typer, RangeNode *type, RangeNode *target, Containment *visit)
{
    if (type == target) return 1;
    if (!type || type->kind != RangeNodeSpecialization || type->scalarBits) return 0;
    RangeNode *declaration = type->resolvedDeclaration;
    if (graphConstruct(typer,declaration)) return 0;
    for (size_t i = 0; i < visit->count; ++i) if (visit->seen[i] == type) return 0;
    if (visit->count == sizeof(visit->seen)/sizeof(*visit->seen)) return 1; /* too deep to tell: store it out of line */
    visit->seen[visit->count++] = type;
    size_t field = 0;
    for (size_t i = 0; i < declaration->itemCount; ++i) {
        RangeNode *item = declaration->items[i];
        if (declaration->kind == RangeNodeEnum) {
            if (item->kind != RangeNodeEnumCase) continue;
            for (size_t j = 0; j < item->itemCount; ++j, ++field) {
                if (type->layout == 2 && type->memberBoxed && type->memberBoxed[field]) continue;
                if (containsInline(typer,memberTypeIn(typer,type,item->items[j]),target,visit)) return 1;
            }
        } else if (rangeNodeDeclaresValue(item->kind) && item->kind != RangeNodeDerived && !builtinMember(item) && !(item->flags & RangeFlagMany)
                   && containsInline(typer,memberTypeIn(typer,type,item),target,visit)) return 1;
    }
    return 0;
}

/* A union: a tag, then the largest case's payload inline. A field whose type
 * contains the union itself, directly or through constructs and other enums,
 * is stored out of line in a reference-counted block like @many storage, with
 * one slot. A union without payloads is a scalar: just its tag. */
static int layoutVariant(Typer *typer, RangeNode *specialization, RangeNode *at)
{
    RangeNode *declaration = specialization->resolvedDeclaration;
    size_t cases = 0, fields = 0;
    for (size_t i = 0; i < declaration->itemCount; ++i)
        if (declaration->items[i]->kind == RangeNodeEnumCase) { ++cases; fields += declaration->items[i]->itemCount; }
    size_t tag = cases <= 256 ? 1 : cases <= 65536 ? 2 : 4;
    specialization->variantTag = (int)tag;
    if (!fields) {
        int bits = 1;
        while (bits < 32 && ((size_t)1 << bits) < cases) ++bits;
        specialization->scalarBits = bits;
        specialization->scalarSigned = 0;
        specialization->size = specialization->alignment = tag;
        specialization->layout = 2;
        return 1;
    }
    RangeArena *arena = typer->report->arena;
    specialization->memberOffsets = rangeArenaAllocate(arena,fields * sizeof(size_t));
    specialization->memberTypes = rangeArenaAllocate(arena,fields * sizeof(RangeNode *));
    specialization->memberBoxed = rangeArenaAllocate(arena,fields);
    size_t *sizes = rangeArenaAllocate(arena,fields * sizeof(size_t)), payloadAlignment = 1;
    int known = 1;
    for (size_t i = 0, k = 0; i < declaration->itemCount; ++i) {
        RangeNode *entry = declaration->items[i];
        if (entry->kind != RangeNodeEnumCase) continue;
        for (size_t j = 0; j < entry->itemCount; ++j, ++k) {
            RangeNode *type = memberTypeIn(typer,specialization,entry->items[j]);
            specialization->memberTypes[k] = type;
            specialization->memberOffsets[k] = SIZE_MAX;
            Containment visit = {.count=0};
            specialization->memberBoxed[k] = type && type->kind == RangeNodeSpecialization
                && containsInline(typer,type,specialization,&visit);
            size_t alignment;
            if (specialization->memberBoxed[k]) { sizes[k] = 8; alignment = 8; }
            else if (!type || type->kind != RangeNodeSpecialization || !layoutOf(typer,type,entry->items[j])) {
                known = 0;
                specialization->integer = 1; /* the cause lies in a field's type, reported there */
                continue;
            } else { sizes[k] = type->size; alignment = type->alignment; }
            if (alignment > payloadAlignment) payloadAlignment = alignment;
        }
    }
    if (!known) { specialization->layout = 2; specialization->size = specialization->alignment = 0; return 0; }
    size_t start = (tag + payloadAlignment - 1) / payloadAlignment * payloadAlignment, end = start;
    for (size_t i = 0, k = 0; i < declaration->itemCount; ++i) {
        RangeNode *entry = declaration->items[i];
        if (entry->kind != RangeNodeEnumCase) continue;
        size_t offset = start;
        for (size_t j = 0; j < entry->itemCount; ++j, ++k) {
            size_t alignment = specialization->memberBoxed[k] ? 8 : specialization->memberTypes[k]->alignment;
            offset = (offset + alignment - 1) / alignment * alignment;
            specialization->memberOffsets[k] = offset;
            offset += sizes[k];
        }
        if (offset > end) end = offset;
    }
    size_t alignment = payloadAlignment > tag ? payloadAlignment : tag;
    specialization->alignment = alignment;
    specialization->size = (end + alignment - 1) / alignment * alignment;
    specialization->layout = 2;
    (void)at;
    return 1;
}

int layoutOf(Typer *typer, RangeNode *specialization, RangeNode *at)
{
    if (!specialization || specialization->kind != RangeNodeSpecialization) return 0;
    if (specialization->layout == 2) return specialization->size || specialization->alignment;
    RangeNode *declaration = specialization->resolvedDeclaration;
    char name[160];
    if (specialization->layout == 1) {
        describeType(name,sizeof(name),specialization);
        sourceDiagnostic(typer->report,at,0,"layout","%s has no layout: it contains itself",name);
        return 0;
    }
    // A grammar kind's values and a macro type's are declarations, which
    // exist only up to macro time.
    if (graphConstruct(typer,declaration) || declaration->kind == RangeNodeMacro) {
        specialization->layout = 2;
        specialization->integer = 1; /* graph value: runtime uses report it */
        return 0;
    }
    specialization->layout = 1;
    if (declaration->kind == RangeNodeEnum) return layoutVariant(typer,specialization,at);
    size_t size = 0, alignment = 1;
    int known = 1;
    RangeNode *storage = NULL, *sign = NULL, *bytes = NULL;
    for (size_t i = 0; i < declaration->itemCount; ++i) {
        if (builtinMember(declaration->items[i]) && same(declaration->items[i]->name,"storage")) storage = declaration->items[i];
        if (builtinMember(declaration->items[i]) && same(declaration->items[i]->name,"signed")) sign = declaration->items[i];
        if (builtinMember(declaration->items[i]) && same(declaration->items[i]->name,"bytes")) bytes = declaration->items[i];
    }
    if (bytes) {
        // UTF-8 bytes held by C: an address, a byte count, and the block that
        // owns them, or zero for a literal's bytes in the executable. Its
        // other members are its meaning, not separate storage.
        size = 24;
        alignment = 8;
    } else if (storage) {
        long long bits = storageBits(typer,specialization,storage);
        RangeNode *signedness = sign ? builtinValue(specialization,sign) : NULL;
        if (sign && (!signedness || signedness->kind != RangeNodeBool))
            sourceDiagnostic(typer->report,sign,0,"layout","builtin 'signed' requires a boolean");
        specialization->scalarBits = bits > 0 && bits <= 64 ? (int)bits : 0;
        specialization->scalarSigned = signedness && signedness->kind == RangeNodeBool && signedness->integer;
        if (bits <= 0 || bits > 64) {
            if (bits > 64) sourceDiagnostic(typer->report,storage,0,"layout","scalars wider than 64 bits are not implemented");
            known = 0;
        } else {
            size = (size_t)((bits + 7) / 8);
            alignment = size <= 1 ? 1 : size <= 2 ? 2 : size <= 4 ? 4 : 8;
            size = alignment; /* a scalar occupies its aligned width */
        }
    } else {
        RangeArena *arena = typer->report->arena;
        size_t items = declaration->itemCount ? declaration->itemCount : 1;
        specialization->memberOffsets = rangeArenaAllocate(arena,items * sizeof(size_t));
        specialization->memberTypes = rangeArenaAllocate(arena,items * sizeof(RangeNode *));
        for (size_t i = 0; i < declaration->itemCount; ++i) {
            specialization->memberOffsets[i] = SIZE_MAX;
            specialization->memberTypes[i] = NULL;
        }
        for (size_t i = 0; i < declaration->itemCount; ++i) {
            RangeNode *member = declaration->items[i];
            // A derived member is computed where it is read: it takes no storage.
            if (!rangeNodeDeclaresValue(member->kind) || builtinMember(member) || member->kind == RangeNodeDerived) continue;
            size_t memberSize, memberAlignment;
            RangeNode *type = NULL;
            if (member->flags & RangeFlagMany) { memberSize = 8; memberAlignment = 8; }
            else {
                type = memberTypeIn(typer,specialization,member);
                if (!type || type->kind != RangeNodeSpecialization || !layoutOf(typer,type,member)) {
                    known = 0;
                    specialization->integer = 1; /* the cause lies in a member's type, reported there */
                    continue;
                }
                memberSize = type->size; memberAlignment = type->alignment;
            }
            size = (size + memberAlignment - 1) / memberAlignment * memberAlignment;
            specialization->memberOffsets[i] = size;
            specialization->memberTypes[i] = type;
            size += memberSize;
            if (memberAlignment > alignment) alignment = memberAlignment;
        }
        size = (size + alignment - 1) / alignment * alignment;
    }
    specialization->layout = 2;
    if (!known) { specialization->size = 0; specialization->alignment = 0; return 0; }
    specialization->size = size;
    specialization->alignment = alignment;
    return 1;
}

/* ---- mutation -------------------------------------------------------------
 * A method changes its receiver when it assigns one of its construct's members,
 * calls a sibling that does, or calls the slot builtins resize and write. Such a
 * method may only be called on a state value: `state` is what permits change. */

static RangeNode *ownerOf(Typer *typer, const RangeNode *function)
{
    if (!function->typeName) return NULL;
    RangeNode *owner = sourceLookup(typer->report,NULL,function->typeName,2);
    return owner && owner->kind == RangeNodeConstruct ? owner : NULL;
}

static int memberOf(const RangeNode *owner, const RangeNode *node)
{
    for (size_t i = 0; owner && node && i < owner->itemCount; ++i) if (owner->items[i] == node) return 1;
    return 0;
}

static int mutates(Typer *, RangeNode *, RangeNode *);

static int mutatesIn(Typer *typer, RangeNode *owner, RangeNode *node)
{
    if (!node) return 0;
    if (node->kind == RangeNodeFunction || node->kind == RangeNodeConstruct) return 0;
    if (node->kind == RangeNodeAssign) {
        RangeNode *root = node->a;
        while (root && root->kind == RangeNodeMemberAccess) root = root->a;
        if (root && root->kind == RangeNodeName && memberOf(owner,found(typer->key,root)->resolvedDeclaration)) return 1;
    }
    if (node->kind == RangeNodeCall && node->a && node->a->kind == RangeNodeName) {
        RangeFacts *call = found(typer->key,node->a);
        RangeNode *callee = call->resolvedDeclaration;
        if (callee && callee->kind == RangeNodeFunction && memberOf(owner,callee) && mutates(typer,callee,call->specialization)) return 1;
    }
    if (mutatesIn(typer,owner,node->a) || mutatesIn(typer,owner,node->b) || mutatesIn(typer,owner,node->c)
        || mutatesIn(typer,owner,found(typer->key,node)->lowered)) return 1;
    for (size_t i = 0; i < node->itemCount; ++i) if (mutatesIn(typer,owner,node->items[i])) return 1;
    return 0;
}

/* Whether `function`, as typed under `key`, changes its receiver. */
static int mutates(Typer *typer, RangeNode *function, RangeNode *key)
{
    RangeFacts *facts = found(key,function);
    if (facts->found & RangeFlagMutationKnown) return (facts->found & RangeFlagMutating) != 0;
    RangeNode *outer = typer->key;
    typer->key = key;
    finding(typer,function)->found |= RangeFlagMutationKnown; /* recursion assumes no change until shown */
    int result = (function->flags & RangeFlagBuiltin) ? same(function->name,"resize") || same(function->name,"write")
        : mutatesIn(typer,ownerOf(typer,function),function->a);
    if (result) finding(typer,function)->found |= RangeFlagMutating;
    typer->key = outer;
    return result;
}

/* Whether `node` is `within` or written inside it. */
static int inside(const RangeNode *within, const RangeNode *node)
{
    if (!within || !node) return 0;
    if (within == node) return 1;
    if (inside(within->a,node) || inside(within->b,node) || inside(within->c,node) || inside(within->rhsReference,node)) return 1;
    for (size_t i = 0; i < within->itemCount; ++i) if (inside(within->items[i],node)) return 1;
    return 0;
}

/* A derived value is computed from others and changes nothing: its
 * expression writes no value declared outside it, directly or by calling a
 * method that changes its receiver. The first such write is reported. */
static int derivedWrites(Typer *typer, RangeNode *derived, RangeNode *node)
{
    if (!node || node->kind == RangeNodeFunction || node->kind == RangeNodeConstruct) return 0;
    if (node->kind == RangeNodeAssign) {
        RangeNode *root = node->a;
        while (root && root->kind == RangeNodeMemberAccess) root = root->a;
        RangeNode *declaration = root && root->kind == RangeNodeName ? found(typer->key,root)->resolvedDeclaration : NULL;
        if (declaration && !inside(derived,declaration)) {
            typeError(typer,node,"'%s' is derived; it cannot write '%s'",derived->name,root->name);
            return 1;
        }
    }
    if (node->kind == RangeNodeCall && node->a && (node->a->kind == RangeNodeMemberAccess || node->a->kind == RangeNodeName)) {
        RangeFacts *call = found(typer->key,node->a);
        RangeNode *function = call->resolvedDeclaration;
        if (function && function->kind == RangeNodeFunction && function->typeName && mutates(typer,function,call->specialization)) {
            RangeNode *root = node->a->kind == RangeNodeMemberAccess ? node->a->a : NULL;
            while (root && root->kind == RangeNodeMemberAccess) root = root->a;
            RangeNode *declaration = root && root->kind == RangeNodeName ? found(typer->key,root)->resolvedDeclaration : NULL;
            if (node->a->kind == RangeNodeName) {
                typeError(typer,node,"'%s' is derived; it cannot call '%s', which changes its receiver",derived->name,function->name);
                return 1;
            }
            if (declaration && !inside(derived,declaration)) {
                typeError(typer,node,"'%s' is derived; it cannot write '%s' by calling '%s'",derived->name,root->name,function->name);
                return 1;
            }
        }
    }
    if (derivedWrites(typer,derived,node->a) || derivedWrites(typer,derived,node->b) || derivedWrites(typer,derived,node->c)
        || derivedWrites(typer,derived,found(typer->key,node)->lowered)) return 1;
    for (size_t i = 0; i < node->itemCount; ++i) if (derivedWrites(typer,derived,node->items[i])) return 1;
    return 0;
}

static void checkMutations(Typer *typer, RangeNode *node)
{
    if (!node) return;
    if (node->kind == RangeNodeDerived) {
        RangeNode *value = declarationValue(typer->key,node);
        if (value && value != node) (void)derivedWrites(typer,node,value);
        for (size_t i = 0; value == node && i < node->itemCount; ++i) if (derivedWrites(typer,node,node->items[i])) break;
    }
    if (node->kind == RangeNodeCall && node->a && node->a->kind == RangeNodeMemberAccess) {
        RangeFacts *call = found(typer->key,node->a);
        RangeNode *function = call->resolvedDeclaration;
        if (function && function->kind == RangeNodeFunction && mutates(typer,function,call->specialization)) {
            // A derived value along the way is computed, not a place to change.
            RangeNode *root = node->a->a, *derived = NULL;
            for (; root && root->kind == RangeNodeMemberAccess; root = root->a) {
                RangeNode *step = found(typer->key,root)->resolvedDeclaration;
                if (step && step->kind == RangeNodeDerived) derived = step;
            }
            RangeNode *declaration = root && root->kind == RangeNodeName ? found(typer->key,root)->resolvedDeclaration : NULL;
            if (declaration && declaration->kind == RangeNodeDerived) derived = declaration;
            if (derived)
                typeError(typer,node,"'%s' changes its receiver, and '%s' is derived from other values; it is not changed",function->name,derived->name);
            else if (!declaration || declaration->kind != RangeNodeState)
                typeError(typer,node,"'%s' changes its receiver, which must be declared with state",function->name);
        }
    }
    checkMutations(typer,node->a); checkMutations(typer,node->b); checkMutations(typer,node->c);
    checkMutations(typer,found(typer->key,node)->lowered);
    for (size_t i = 0; i < node->itemCount; ++i) checkMutations(typer,node->items[i]);
}

/* The function `=` calls on values of a type: the `=` with a body the type
 * declares, written or emitted. Without one, `=` is C's built-in structural
 * comparison. */
RangeNode *equalityFunction(const RangeNode *type)
{
    RangeNode *function = type && type->kind == RangeNodeSpecialization ? operatorFunction(type->resolvedDeclaration,"=",1) : NULL;
    return function && !(function->flags & RangeFlagBuiltin) ? function : NULL;
}

/* Whether `=` can compare values of `type`. A type with an equality function
 * calls it; any other type is compared structurally, which needs every
 * stored member, or every payload field, to be comparable in turn. A type
 * already being compared counts as comparable, so recursive enums are. On
 * failure, `why` says which field stops it. */
static int comparable(Typer *typer, RangeNode *type, Comparing *visit, char *why, size_t size)
{
    char name[160]; describeType(name,sizeof(name),type);
    if (!type || type->kind != RangeNodeSpecialization) { snprintf(why,size,"%s is not a value type",name); return 0; }
    RangeNode *declaration = type->resolvedDeclaration, *function = equalityFunction(type);
    if (function) {
        // The `=` it calls is typed in its specialization, as a call would type it.
        if (keyOf(function->owner,type)) (void)typeOnDemand(typer,function,type);
        return 1;
    }
    for (size_t i = 0; i < visit->count; ++i) if (visit->seen[i] == type) return 1;
    if (visit->count == sizeof(visit->seen)/sizeof(*visit->seen)) { snprintf(why,size,"%s nests too deeply to compare",name); return 0; }
    visit->seen[visit->count++] = type;
    if (!layoutOf(typer,type,declaration)) { snprintf(why,size,"%s has no runtime layout",name); return 0; }
    if (type->scalarBits || bytesType(type)) return 1;
    char inner[512];
    if (type->variantTag) {
        for (size_t i = 0, k = 0; i < declaration->itemCount; ++i) {
            RangeNode *entry = declaration->items[i];
            if (entry->kind != RangeNodeEnumCase) continue;
            for (size_t j = 0; j < entry->itemCount; ++j, ++k) {
                if (comparable(typer,type->memberTypes[k],visit,inner,sizeof(inner))) continue;
                char field[160]; describeType(field,sizeof(field),type->memberTypes[k]);
                snprintf(why,size,"payload field '%s' of case '%s' is %s%s%s",entry->items[j]->name,entry->name,field,
                         type->memberTypes[k] && type->memberTypes[k]->kind == RangeNodeSpecialization ? ", and " : "",
                         type->memberTypes[k] && type->memberTypes[k]->kind == RangeNodeSpecialization ? inner : "");
                return 0;
            }
        }
        return 1;
    }
    for (size_t i = 0; i < declaration->itemCount; ++i) {
        if (!type->memberOffsets || type->memberOffsets[i] == SIZE_MAX) continue;
        RangeNode *member = declaration->items[i];
        if (member->flags & RangeFlagMany) {
            snprintf(why,size,"field '%s' of %s is @many storage, which the structural '=' does not compare",member->name,name);
            return 0;
        }
        if (comparable(typer,type->memberTypes[i],visit,inner,sizeof(inner))) continue;
        char field[160]; describeType(field,sizeof(field),type->memberTypes[i]);
        snprintf(why,size,"field '%s' is %s, and %s",member->name,field,inner);
        return 0;
    }
    return 1;
}

static void checkEqualities(Typer *typer)
{
    for (size_t i = 0; i < typer->equalityCount; ++i) {
        RangeNode *type = typer->equalities[i].type;
        Comparing visit = {.count=0};
        char why[512], name[160];
        if (comparable(typer,type,&visit,why,sizeof(why))) {
            if (!equalityFunction(type))
                sourceDiagnostic(typer->report,typer->equalities[i].at,1,"C-implementation","'=' here is C's built-in structural comparison: "
                    "every stored member, or the case then its payload fields; it is emitted only for the types a program compares");
            continue;
        }
        describeType(name,sizeof(name),type);
        typer->key = typer->equalities[i].key;
        typeError(typer,typer->equalities[i].at,"'=' cannot compare %s: %s",name,why);
        typer->key = NULL;
    }
}

/* The integer and boolean literal rules select the default integer and the
 * condition type; C names neither. */
static RangeNode *literalFamily(Typer *typer, const char *spelling)
{
    for (size_t u = 0; u < typer->report->count; ++u) for (size_t i = 0; i < typer->report->units[u]->itemCount; ++i) {
        RangeNode *macro = typer->report->units[u]->items[i];
        if (macro->kind != RangeNodeMacro || !macro->literalPattern || !macro->literalDefault) continue;
        if (literalMatch(typer->vm,macro,macro->literalPattern,spelling)) return macro->literalDefault;
    }
    return NULL;
}

/* ---- written code ----
 * Written code is read once and never changed: what the compiler finds lives
 * beside it. Each leaf declaration, a function, a macro, the entry block, a
 * member, an enum case, or a construct's generics, is kept with the hash of
 * what was written when it is read: parsed units before any macro runs, and
 * what a #graph block or an extension adds as it joins. The #graph door adds
 * declarations to units and constructs, never inside a leaf. */
void noteWritten(Typer *typer, RangeNode *node)
{
    if (!node || node->kind == RangeNodeExtension) return; /* its members are kept where they land */
    if (node->kind == RangeNodeUnit || node->kind == RangeNodeConstruct || node->kind == RangeNodeEnum) {
        noteWritten(typer,node->generics);
        for (size_t i = 0; i < node->itemCount; ++i) noteWritten(typer,node->items[i]);
        return;
    }
    if (typer->writtenCount == typer->writtenCapacity) {
        typer->writtenCapacity = typer->writtenCapacity ? typer->writtenCapacity * 2 : 256;
        void *grown = rangeArenaAllocate(typer->report->arena,typer->writtenCapacity * sizeof(*typer->written));
        if (typer->writtenCount) memcpy(grown,typer->written,typer->writtenCount * sizeof(*typer->written));
        typer->written = grown;
    }
    typer->written[typer->writtenCount].node = node;
    typer->written[typer->writtenCount++].hash = rangeWrittenHash(node);
}

/* The first leaf declaration, in `path` or anywhere, whose written code
 * changed after it was read; NULL when none did. */
static RangeNode *writtenChanged(Typer *typer, const char *path)
{
    for (size_t i = 0; i < typer->writtenCount; ++i) {
        RangeNode *node = typer->written[i].node;
        if ((!path || same(node->path,path)) && rangeWrittenHash(node) != typer->written[i].hash) return node;
    }
    return NULL;
}

/* A change to written code is C's mistake, reported where it was written. */
void diagnoseWritten(Typer *typer)
{
    RangeNode *changed = writtenChanged(typer,NULL);
    if (changed) sourceDiagnostic(typer->report,changed,0,"internal","C changed %s%s%s%s after reading it",
        rangeNodeKindName(changed->kind),changed->name ? " '" : "",changed->name ? changed->name : "",changed->name ? "'" : "");
}

Typer *newTyper(SourceReport *report, Resolver *vm)
{
    Typer *typer = rangeArenaAllocate(report->arena,sizeof(*typer));
    *typer = (Typer){.report=report,.vm=vm};
    typer->specializations = rangeNodeCreate(report->arena,RangeNodeBlock,"<compiler>",1,1);
    typer->instances = rangeNodeCreate(report->arena,RangeNodeBlock,"<compiler>",1,1);
    typer->functionTypes = rangeNodeCreate(report->arena,RangeNodeBlock,"<compiler>",1,1);
    typer->deferred = rangeNodeCreate(report->arena,RangeNodeType,"<compiler>",1,1);
    typer->deferred->name = "a value known at macro time";
    return typer;
}

/* What the language's declarations give the typer before any macro runs:
 * the integer default and the condition type. */
void typerLanguage(Typer *typer)
{
    SourceReport *report = typer->report;
    typer->integer = literalFamily(typer,"0");
    typer->boolean = literalFamily(typer,"true");
    if (typer->boolean) typer->booleanType = specialize(typer,NULL,typer->boolean,NULL,NULL,typer->boolean);
    if (typer->boolean && typer->boolean->kind == RangeNodeEnum) {
        // Conditions branch on zero, and comparisons produce 0 or 1: the
        // condition enum's false case is tag 0 and its true case tag 1.
        RangeNode *no = enumCase(typer->boolean,"false"), *yes = enumCase(typer->boolean,"true");
        if (!no || !yes || no->integer != 0 || yes->integer != 1 || enumPayloads(typer->boolean))
            sourceDiagnostic(report,typer->boolean,0,"layout","%s is the condition type, so it needs case false, then case true, without payloads",
                typer->boolean->name);
    }
}

/* ---- typing on demand ----
 * Macro time runs code before typing in order reaches it: a function is
 * typed when it is first called, a construct's members when it is first
 * constructed, a member when `.value` reads its initializer, and a macro's
 * body when it is first applied. A generic declaration's members and
 * methods are typed this way at any time, per specialization, as they are
 * used. Each is typed once, from the top level, in the scopes it is
 * declared in. Typing sees the program as it stands then: code typed before
 * a later round emits what it names reports it missing, and keeps that
 * report. */

/* The scopes a declaration sees around it, innermost first: the constructs
 * and enums enclosing it, then its unit; NULL when no unit holds it. */
static SourceScope *enclosingScope(Typer *typer, RangeNode *declaration, SourceScope scopes[33])
{
    RangeNode *chain[32];
    for (size_t u = 0; u < typer->report->count; ++u) {
        size_t count = 0;
        if (!enclosing(typer->report->units[u],declaration,chain,&count,32)) continue;
        scopes[count] = (SourceScope){.owner=typer->report->units[u]};
        for (size_t i = count; i-- > 0;) scopes[i] = (SourceScope){.owner=chain[i],.parent=&scopes[i + 1]};
        return &scopes[0];
    }
    return NULL;
}

/* A function, before it is called or runs: typed in its owner's own
 * specialization, as typing in order types it, or, a method of a generic
 * declaration, in its receiver's specialization, under that key, the first
 * time it is used there. Code that does not type does not run at macro
 * time. Returns the key it is typed under. */
RangeNode *typeOnDemand(Typer *typer, RangeNode *function, RangeNode *receiver)
{
    RangeNode *key = keyOf(function->owner,receiver);
    if (!(found(key,function)->found & RangeFlagTyped)) {
        SourceScope scopes[33];
        size_t errors = typer->report->errors;
        TyperContext outer = typerTop(typer);
        typer->key = key;
        typeFunction(typer,enclosingScope(typer,function,scopes),function,
                     key ? receiver : function->owner ? ownSpecialization(typer,function->owner) : NULL);
        if (typer->report->errors != errors) finding(typer,function)->found |= RangeFlagInvalid;
        typerRestore(typer,outer);
    }
    return key;
}

/* A member whose initializer `.value` reads: a non-generic construct's, in
 * its own specialization; only a construct's members are typed on their own. */
void typeValueOnDemand(Typer *typer, RangeNode *member)
{
    SourceScope scopes[33], *scope = member->found & RangeFlagTyped ? NULL : enclosingScope(typer,member,scopes);
    RangeNode *own = scope && scope->owner->kind == RangeNodeConstruct ? ownSpecialization(typer,scope->owner) : NULL;
    if (own) (void)memberTypeIn(typer,own,member);
}

/* A macro's body, before its first application runs it. Returns whether it may run. */
int typeMacroOnDemand(Typer *typer, RangeMacroApplication *app)
{
    RangeNode *macro = app->declaration;
    if (!(macro->found & RangeFlagTyped)) {
        SourceScope unit = {.owner=app->unit};
        TyperContext outer = typerTop(typer);
        typeMacro(typer,&unit,macro,1);
        typerRestore(typer,outer);
    }
    return !(macro->found & RangeFlagInvalid);
}

/* An application's arguments, before it first runs, or after macro time
 * for one that never runs: typed as a call's are, against the parameters of
 * the macro it selected, where the application is written: in the scopes
 * around its target, never the target's own. They run at macro time, so a
 * type's name is a value there. Returns whether they typed. */
int typeApplicationOnDemand(Typer *typer, RangeMacroApplication *app)
{
    if (!app->argued) {
        RangeNode *macro = app->declaration;
        SourceScope written[33], declared[33], unit = {.owner=app->unit};
        SourceScope *scope = enclosingScope(typer,app->target,written);
        SourceScope signature = {.owner=macro,.parent=enclosingScope(typer,macro,declared)};
        size_t errors = typer->report->errors;
        TyperContext outer = typerTop(typer);
        typer->arguments = 1;
        typeArguments(typer,scope ? scope : &unit,app->attribute,macro,1,&signature,NULL,NULL);
        typerRestore(typer,outer);
        app->argued = typer->report->errors == errors ? 1 : -1;
    }
    return app->argued == 1;
}

/* The arguments of applications that never ran, such as @literal's. */
static void typeApplications(Typer *typer, RangeNode *declaration)
{
    for (size_t i = 0; declaration->c && i < declaration->c->itemCount; ++i)
        if (declaration->c->items[i]->kind == RangeNodeAttribute && declaration->c->items[i]->macroApplication)
            (void)typeApplicationOnDemand(typer,declaration->c->items[i]->macroApplication);
    if (declaration->kind == RangeNodeConstruct || declaration->kind == RangeNodeEnum)
        for (size_t i = 0; i < declaration->itemCount; ++i) typeApplications(typer,declaration->items[i]);
}

/* Type the program, after macro time: what macros left untyped, and the
 * checks that need every declaration. The typer is kept for code
 * generation, which lays out the types it meets. */
void typeCheck(Typer *typer)
{
    SourceReport *report = typer->report;
    Resolver *vm = typer->vm;
    if (setjmp(vm->failure) != 0) { sourceDiagnostic(report,NULL,0,"type","%s",vm->error); return; }
    // The entry block returns the default integer: the process exit status.
    RangeNode *status = typer->integer ? specialize(typer,NULL,typer->integer,NULL,NULL,typer->integer) : NULL;
    for (size_t u = 0; u < report->count; ++u) {
        SourceScope unit = {.owner=report->units[u]};
        for (size_t i = 0; i < report->units[u]->itemCount; ++i) {
            RangeNode *item = report->units[u]->items[i];
            if (item->kind == RangeNodeConstruct) typeConstruct(typer,&unit,item);
            else if (item->kind == RangeNodeEnum) typeEnum(typer,&unit,item);
            else if (item->kind == RangeNodeMacro) typeMacro(typer,&unit,item,0); /* never applied */
            else if (item->kind == RangeNodeFunction && genericTemplate(item)) continue; /* typed per specialization */
            else if (item->kind == RangeNodeFunction) {
                typeFunction(typer,&unit,item,NULL);
                if (appliesBuiltin(item,"iteration"))
                    typeError(typer,item,"@iteration function '%s' must be a method of the type it iterates",item->name);
                if (appliesBuiltin(item,"insertion"))
                    typeError(typer,item,"@insertion function '%s' must be a method of the type it adds to",item->name);
                if (same(item->name,"="))
                    typeError(typer,item,"'=' must be declared on the type it compares, in the type or an extension of it");
                else if (operatorName(item->name))
                    typeError(typer,item,"'%s' must be declared on the type of its left operand, in the type or an extension of it",item->name);
            }
            else if (item->kind == RangeNodeMain && !(item->found & RangeFlagTyped)) {
                item->found |= RangeFlagTyped;
                item->type = status;
                typer->output = status;
                typeBlock(typer,&unit,item->a,NULL,status);
                typer->output = NULL;
            }
        }
    }
    for (size_t u = 0; u < report->count; ++u)
        for (size_t i = 0; i < report->units[u]->itemCount; ++i) typeApplications(typer,report->units[u]->items[i]);
    drainLaws(typer); /* the specializations and literals typing met */
    for (size_t u = 0; u < report->count; ++u) checkOverloads(typer,report->units[u]);
    checkEqualities(typer);
    // Every type the program mentions is typed in its specialization and
    // gets a layout, or a reason it has none.
    for (size_t i = 0; i < typer->specializations->itemCount; ++i) {
        RangeNode *specialization = typer->specializations->items[i], *declaration = specialization->resolvedDeclaration;
        if (keyOf(declaration,specialization)) typeLaws(typer,declaration,specialization);
        if (specialization->layout == 2 || layoutOf(typer,specialization,declaration) || specialization->integer) continue;
        char name[160]; describeType(name,sizeof(name),specialization);
        sourceDiagnostic(report,declaration,0,"layout","%s has no layout",name);
    }
    // Every body as it was typed: in place, per generic function
    // specialization, and per specialization of a generic declaration.
    for (size_t u = 0; u < report->count; ++u) checkMutations(typer,report->units[u]);
    for (size_t i = 0; i < typer->instances->itemCount; ++i) {
        typer->key = typer->instances->items[i];
        checkMutations(typer,typer->key->resolvedDeclaration);
    }
    for (size_t i = 0; i < typer->specializations->itemCount; ++i) {
        RangeNode *declaration = typer->specializations->items[i]->resolvedDeclaration;
        typer->key = keyOf(declaration,typer->specializations->items[i]);
        for (size_t j = 0; typer->key && j < declaration->itemCount; ++j)
            if ((declaration->items[j]->kind == RangeNodeFunction || declaration->items[j]->kind == RangeNodeDerived)
                && (found(typer->key,declaration->items[j])->found & RangeFlagTyped))
                checkMutations(typer,declaration->items[j]);
    }
    typer->key = NULL;
    drainLaws(typer); /* the specializations comparing and layout met */
}
