/* Structural parser dump for debugging. */
#ifndef RANGE_COMPILER_GRAPH_H
#define RANGE_COMPILER_GRAPH_H

#include "model.h"
#include <stdio.h>

void rangeGraphWriteTree(FILE *output, const RangeNode *node, int depth);

#endif
