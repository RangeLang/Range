#include "graph.h"

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
