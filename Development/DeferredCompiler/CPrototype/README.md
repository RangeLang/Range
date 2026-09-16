# Retired C prototype components

Preserved on 2026-09-14 when the active compiler dropped runtime-loaded graph
templates, syntax recipes, and the ordinary-program interpreter. These files
are historical recovery copies, not active build inputs or runnable tests.

`compiler.c` is a snapshot before removing the interpreter. The nested Language
and Testing directories retain the retired definitions and template-only tests.
Core definitions were not retired. The active compiler now uses C-owned graph
shapes and resolves sources without requesting a text dump. Native emission is
still to be implemented.
