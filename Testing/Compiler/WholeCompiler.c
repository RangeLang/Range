/* Every layer of the compiler in one translation unit, so a test reaches the
 * functions each layer keeps static. A test renames main before including it. */
#include "../../Language/Compiler/Source/resolution.c"
#include "../../Language/Compiler/Source/macros.c"
#include "../../Language/Compiler/Source/typing.c"
#include "../../Language/Compiler/Source/evaluator.c"
#include "../../Language/Compiler/Source/codegen.c"
#include "../../Language/Compiler/Source/compiler.c"
