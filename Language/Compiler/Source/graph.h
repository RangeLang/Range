/* Human-readable views of the existing graph, not an executable format. */
#ifndef RANGE_COMPILER_GRAPH_H
#define RANGE_COMPILER_GRAPH_H

#include "model.h"
#include <stdio.h>

void rangeGraphWrite(FILE *output, const RangeNode *unit);
void rangeGraphWriteTree(FILE *output, const RangeNode *node, int depth);

#endif
