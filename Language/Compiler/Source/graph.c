#include "graph.h"
#include <ctype.h>
#include <string.h>

/* Structural dump: one indented line per node, used by the compiler gate to
 * assert that difficult forms are actually represented rather than skipped. */
void rangeGraphWriteTree(FILE *output, const RangeNode *node, int depth)
{
    if (!node) return;
    for (int step = 0; step < depth; ++step) fputs("  ", output);
    fputs(rangeNodeKindName(node->kind), output);
    if (node->name) fprintf(output, " name=%s", node->name);
    if (node->typeName) fprintf(output, " type=%s", node->typeName);
    if (node->flags) fprintf(output, " flags=%d", node->flags);
    if (node->rhsEnd > node->rhsStart) {
        fprintf(output, " rhs=%zu:%zu application=%s", node->rhsStart, node->rhsEnd,
               node->flags & RangeFlagApplication ? "yes" : "no");
    }
    if (node->spanEnd > node->spanStart) {
        fprintf(output, " span=%zu", node->spanEnd - node->spanStart);
    }
    if (node->itemCount) fprintf(output, " items=%zu", node->itemCount);
    fputc('\n', output);
    rangeGraphWriteTree(output, node->a, depth + 1);
    rangeGraphWriteTree(output, node->b, depth + 1);
    rangeGraphWriteTree(output, node->c, depth + 1);
    rangeGraphWriteTree(output, node->annotations, depth + 1);
    rangeGraphWriteTree(output, node->generics, depth + 1);
    rangeGraphWriteTree(output, node->rhsReference, depth + 1);
    for (size_t index = 0; index < node->itemCount; ++index) {
        rangeGraphWriteTree(output, node->items[index], depth + 1);
    }
}

static void indent(FILE *out, int depth)
{
    while (depth-- > 0) fputs("    ", out);
}

static void quoted(FILE *out, const char *text)
{
    fputc('"', out);
    for (const unsigned char *p = (const unsigned char *)text; *p; ++p) {
        switch (*p) {
        case '"': fputs("\\\"", out); break;
        case '\\': fputs("\\\\", out); break;
        case '\n': fputs("\\n", out); break;
        case '\r': fputs("\\r", out); break;
        case '\t': fputs("\\t", out); break;
        default:
            if (*p < 32) fprintf(out, "\\u%04x", *p);
            else fputc(*p, out);
        }
    }
    fputc('"', out);
}

static void graphName(FILE *out, const char *text)
{
    const unsigned char *p = (const unsigned char *)text;
    if (!isalpha(*p) && *p != '_') { quoted(out,text); return; }
    for (++p; *p; ++p) if (!isalnum(*p) && *p != '_') { quoted(out,text); return; }
    fputs(text,out);
}

static void writeNode(FILE *, const RangeNode *, int);

static void field(FILE *out, const char *name, const RangeNode *node, int depth)
{
    if (!node) return;
    indent(out, depth);
    fprintf(out, "%s: ", name);
    writeNode(out, node, depth);
    fputc('\n', out);
}

static void textField(FILE *out, const char *name, const char *value, int depth)
{
    if (!value) return;
    indent(out, depth);
    fprintf(out, "%s: ", name);
    graphName(out, value);
    fputc('\n', out);
}

/* Normalize the parser's two forms of inferred member RHS for display only. */
static const RangeNode *memberValue(const RangeNode *node)
{
    if (node->typeName || node->flags || (node->c && node->c->itemCount)) return node;
    if (node->a) return node->a;
    if (node->itemCount == 1 && !node->items[0]->name) return node->items[0]->a;
    return node;
}

static void list(FILE *out, const char *name, const RangeNode *owner, int depth,
                 int named)
{
    if (!owner || !owner->itemCount) return;
    indent(out, depth);
    fprintf(out, "%s: {\n", name);
    for (size_t i = 0; i < owner->itemCount; ++i) {
        const RangeNode *item = owner->items[i];
        indent(out, depth + 1);
        if (named && item->name) {
            fprintf(out, "%s: ", item->name);
            if (item->kind == RangeNodeMember) item = memberValue(item);
            else if (item->kind == RangeNodeArgument && item->a) item = item->a;
        }
        writeNode(out, item, depth + 1);
        fputc('\n', out);
    }
    indent(out, depth);
    fputs("}\n", out);
}

static void sourceLines(FILE *, const char *, size_t, size_t, int);
static void writeMacroBody(FILE *, const RangeNode *, const char *, int);

static void writeSyntax(FILE *out, const RangeNode *attribute, int depth)
{
    if (!attribute->source || !attribute->spanEnd || !attribute->name
        || strcmp(attribute->name,"syntax")) return;
    indent(out,depth);
    fputs("template:\n",out);
    sourceLines(out,attribute->source,attribute->spanStart,attribute->spanEnd,depth + 1);
}

static void graphValue(FILE *out, RangeGraphValue value, const RangeMacroApplication *app, int depth)
{
    if (value.kind == RangeGraphNone) { fputs("none",out); return; }
    if (value.kind == RangeGraphText) { graphName(out,value.text); return; }
    if (value.kind == RangeGraphNodes) {
        fputs("{\n",out);
        for (size_t i = 0; i < value.count; ++i) {
            indent(out,depth + 1);
            graphValue(out,(RangeGraphValue){.kind=RangeGraphNode,.node=value.nodes[i]},app,depth + 1);
            fputc('\n',out);
        }
        indent(out,depth); fputc('}',out); return;
    }
    const RangeNode *node = value.node;
    if (node->kind == RangeNodeBlock && node->graphType) {
        writeMacroBody(out,node,app->unit->source,depth);
        return;
    }
    if (node->kind == RangeNodeEmission && node->b) {
        fprintf(out,"#%s {\n",node->a->name);
        sourceLines(out,app->unit->source,node->b->spanStart,node->b->spanEnd,depth + 1);
        indent(out,depth); fputc('}',out);
    } else if (node->kind == RangeNodeLocal) {
        fprintf(out,"%s %s: ",node->flags & RangeFlagMutable ? "state" : "let",node->name);
        fwrite(app->unit->source + node->rhsStart,1,node->rhsEnd - node->rhsStart,out);
    } else if (node->kind == RangeNodeMember && memberValue(node) != node) {
        fputs("Member { name: ",out); graphName(out,node->name);
        fputs(" value: ",out); writeNode(out,memberValue(node),depth); fputs(" }",out);
    } else if (node->kind == RangeNodeMacro || node->kind == RangeNodeConstruct) {
        fprintf(out,"%s { name: ",node->kind == RangeNodeMacro ? "Macro" : "Construct");
        graphName(out,node->name); fputs(" }",out);
    } else writeNode(out,node,depth);
}

static void resolvedBindings(FILE *out, const RangeMacroApplication *app, int depth)
{
    if (!app) return;
    int opened = 0;
    for (size_t i = 0; i < app->count; ++i) {
        const RangeGraphBinding *binding = &app->bindings[i];
        if (binding->state != 2) continue;
        if (!opened++) { indent(out,depth); fputs("resolved: {\n",out); }
        indent(out,depth + 1); fprintf(out,"%s: ",binding->definition->name);
        graphValue(out,binding->value,app,depth + 1); fputc('\n',out);
    }
    if (opened) { indent(out,depth); fputs("}\n",out); }
}

static void macros(FILE *out, const RangeNode *attributes, int depth)
{
    if (!attributes || !attributes->itemCount) return;
    /* A single simple application uses the compact shape shown for Int. */
    const RangeNode *item = attributes->items[0];
    if (attributes->itemCount == 1 && item->name && !item->itemCount) {
        indent(out, depth);
        fputs("macros: {\n", out);
        textField(out, "name", item->name, depth + 1);
        writeSyntax(out,item,depth + 1);
        resolvedBindings(out,item->macroApplication,depth + 1);
        indent(out, depth);
        fputs("}\n", out);
    } else list(out, "macros", attributes, depth, 0);
}

static void writeNode(FILE *out, const RangeNode *node, int depth)
{
    if (node->kind == RangeNodeBlock) {
        fputs("{\n",out);
        for (size_t i = 0; i < node->itemCount; ++i) {
            indent(out,depth + 1);
            writeNode(out,node->items[i],depth + 1);
            fputc('\n',out);
        }
        indent(out,depth); fputc('}',out); return;
    }
    if (node->kind == RangeNodeFunction) {
        fputs("Function {\n",out);
        macros(out,node->c,depth + 1);
        macros(out,node->annotations,depth + 1);
        textField(out,"name",node->name,depth + 1);
        textField(out,"receiver",node->typeName,depth + 1);
        list(out,"generics",node->generics,depth + 1,1);
        list(out,"parameters",node,depth + 1,0);
        if (node->b && node->b->kind == RangeNodeName && !node->b->flags
            && !node->b->generics && !node->b->a && !node->b->itemCount)
            textField(out,"output",node->b->name,depth + 1);
        else field(out,"output",node->b,depth + 1);
        field(out,"body",node->a,depth + 1);
        indent(out,depth); fputc('}',out); return;
    }
    if (node->kind == RangeNodeMember && node->graphType) {
        fputs("Member {\n",out);
        textField(out,"name",node->name,depth + 1);
        RangeNode *rhs = rangeNodeRHS((RangeNode *)node);
        if (rhs) field(out,"value",rhs,depth + 1);
        else if (node->source && node->rhsEnd > node->rhsStart) {
            indent(out,depth + 1); fputs("value: ",out);
            fwrite(node->source + node->rhsStart,1,node->rhsEnd - node->rhsStart,out);
            fputc('\n',out);
        }
        indent(out,depth); fputc('}',out); return;
    }
    if (node->kind == RangeNodeInteger) {
        if (node->name) fputs(node->name,out);
        else fprintf(out,"%lld",node->integer);
        return;
    }
    if (node->kind == RangeNodeBool) {
        fputs(node->integer ? "true" : "false",out);
        return;
    }
    if (node->kind == RangeNodeStringPart && (node->flags & RangeFlagLiteral)) {
        fputs("String { value: ", out);
        quoted(out, node->name ? node->name : "");
        fputs(" }", out);
        return;
    }
    if (node->kind == RangeNodeString && node->itemCount == 1
        && (node->items[0]->flags & RangeFlagLiteral)) {
        writeNode(out, node->items[0], depth);
        return;
    }
    const char *kind = rangeNodeKindName(node->kind);
    fputc(toupper((unsigned char)*kind), out);
    fprintf(out, "%s {\n", kind + 1);
    int inner = depth + 1;
    int declaration = node->kind == RangeNodeConstruct || node->kind == RangeNodeEnum
        || node->kind == RangeNodeFunction || node->kind == RangeNodeMacro
        || node->kind == RangeNodeMember || node->kind == RangeNodeLocal;
    if (declaration) macros(out, node->c, inner);
    macros(out, node->annotations, inner);
    textField(out, "name", node->name, inner);
    if (node->kind == RangeNodeAttribute) {
        writeSyntax(out,node,inner);
        resolvedBindings(out,node->macroApplication,inner);
    }
    textField(out, node->kind == RangeNodeFunction ? "receiver" : "type", node->typeName, inner);
    if (node->flags & RangeFlagMutable) textField(out, "binding", "state", inner);
    if (node->flags & RangeFlagDerived) textField(out, "binding", "derived", inner);
    if (node->flags & RangeFlagBinding) textField(out, "binding", "binding", inner);
    list(out, "generics", node->generics, inner, 1);
    const char *a = "value", *b = "type", *c = "body", *items = "values";
    switch (node->kind) {
    case RangeNodeConstruct: items = "members"; break;
    case RangeNodeEnum: items = "cases"; break;
    case RangeNodeFunction: a = "body"; b = "returns"; items = "parameters"; break;
    case RangeNodeMacro: a = "body"; b = "target"; items = "parameters"; break;
    case RangeNodeBlock: items = "statements"; break;
    case RangeNodeCall: a = "target"; items = "arguments"; break;
    case RangeNodeAttribute: items = "arguments"; break;
    case RangeNodeMemberAccess: a = "target"; break;
    case RangeNodeBinary: a = "left"; b = "right"; break;
    case RangeNodeAssign: a = "target"; b = "value"; break;
    case RangeNodeIf: a = "condition"; b = "then"; c = "else"; break;
    case RangeNodeWhile: a = "condition"; b = "body"; break;
    case RangeNodeMember: case RangeNodeLocal: case RangeNodeParameter: items = "arguments"; break;
    case RangeNodeString: items = "parts"; break;
    default: break;
    }
    field(out, a, node->a, inner);
    field(out, b, node->b, inner);
    if (!declaration) field(out, c, node->c, inner);
    list(out, items, node, inner, node->kind == RangeNodeConstruct);
    indent(out, depth);
    fputc('}', out);
}

/* Source spelling preserves deferred Range code, including comments and syntax
 * that this inspection view should not reinterpret. Strip common indentation. */
static void sourceLines(FILE *out, const char *source, size_t start, size_t end, int depth)
{
    size_t margin = (size_t)-1;
    for (size_t line = start; line < end;) {
        size_t next = line;
        while (next < end && source[next] != '\n') ++next;
        size_t text = line;
        while (text < next && (source[text] == ' ' || source[text] == '\t' || source[text] == '\r')) ++text;
        if (text < next && text - line < margin) margin = text - line;
        line = next + (next < end);
    }
    if (margin == (size_t)-1) return;
    while (start < end && (source[start] == '\n' || source[start] == '\r')) ++start;
    while (end > start && isspace((unsigned char)source[end - 1])) --end;
    for (size_t line = start; line < end;) {
        size_t next = line;
        while (next < end && source[next] != '\n') ++next;
        size_t text = line;
        while (text < next && text - line < margin
               && (source[text] == ' ' || source[text] == '\t')) ++text;
        if (text < next) {
            indent(out, depth);
            fwrite(source + text, 1, next - text, out);
        }
        fputc('\n', out);
        line = next + (next < end);
    }
}

static void environmentBlocks(FILE *out, const RangeNode *node, const char *source, int depth)
{
    if (!node || node->kind == RangeNodeFunction || node->kind == RangeNodeMacro) return;
    if (node->kind == RangeNodeEmission && node->a && node->a->name
        && !strcmp(node->a->name, "environment") && node->b) {
        indent(out, depth);
        fputs("environment: {\n", out);
        sourceLines(out, source, node->b->spanStart, node->b->spanEnd, depth + 1);
        indent(out, depth);
        fputs("}\n", out);
        return; /* Nested expansions already appear in the retained code. */
    }
    environmentBlocks(out, node->a, source, depth);
    environmentBlocks(out, node->b, source, depth);
    environmentBlocks(out, node->c, source, depth);
    for (size_t i = 0; i < node->itemCount; ++i)
        environmentBlocks(out, node->items[i], source, depth);
}

static void writeMacroBody(FILE *out, const RangeNode *body, const char *source, int depth)
{
    fputs("{\n",out);
    int members = 0;
    for (size_t i = 0; i < body->itemCount; ++i) {
        const RangeNode *member = body->items[i];
        if (member->kind != RangeNodeLocal || !rangeNodeHasContextReference(member)) continue;
        if (!members++) { indent(out,depth + 1); fputs("members: {\n", out); }
        indent(out,depth + 2); fprintf(out, "%s: ", member->name);
        fwrite(source + member->rhsStart, 1, member->rhsEnd - member->rhsStart, out);
        fputc('\n', out);
    }
    if (members) { indent(out,depth + 1); fputs("}\n", out); }
    environmentBlocks(out,body,source,depth + 1);
    indent(out,depth); fputc('}',out);
}

static void writeMacro(FILE *out, const RangeNode *node, const char *source)
{
    fputs("Macro {\n",out);
    macros(out,node->c,1);
    textField(out,"name",node->name,1);
    textField(out,"target",node->b ? node->b->name : node->typeName,1);
    list(out,"parameters",node,1,0);
    if (node->a) {
        fputs("    body: ",out); writeMacroBody(out,node->a,source,1); fputc('\n',out);
    }
    fputs("}", out);
}

void rangeGraphWrite(FILE *output, const RangeNode *unit)
{
    if (!unit) return;
    if (unit->kind != RangeNodeUnit) {
        writeNode(output, unit, 0);
        fputc('\n', output);
        return;
    }
    int written = 0;
    for (size_t i = 0; i < unit->itemCount; ++i) {
        const RangeNode *node = unit->items[i];
        if (written++) fputc('\n', output);
        if (node->kind == RangeNodeMacro && unit->source) writeMacro(output, node, unit->source);
        else writeNode(output, node, 0);
        fputc('\n', output);
    }
}
