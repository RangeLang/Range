# RangeCompiler

RangeCompiler is Compiler B: a new compiler application authored in Range.
It is intentionally structured like RangeView rather than as another mutable
copy of Compiler A.

During bootstrap, Compiler A owns only the application that compiles Compiler
B's Range sources into an executable. Compiler B owns the entire product-input
pipeline:

```text
Compiler A + Compiler B.range -> Compiler B executable
Compiler B + product source -> tokens -> SourceGraph
    -> Resolution -> CFG -> Ownership -> MIR -> Product
```

Compiler A never opens Compiler B's product input. Compiler B must not import
`Sources/Compiler/Body`, serialized compiler records, `CompilerBodyArena`, or
LLVM-specific semantic authority. Each phase consumes stable identities from
the preceding Range value and produces an identified delta. RangeView is the
first product gate. Compiler B compiling itself is reserved for deliberate
checkpoint proof, not the normal development loop.

The initial executable slice opens one `.range` file and performs one
Range-authored streaming lexical/graph-construction pass. It recognizes
declarations, applications, Blocks, controls, literals, and nesting
relationships and rejects malformed lexical or brace structure. All facts are
retained in one typed eight-column integer matrix with source-stable signed
identities. B validates the matrix's row shapes, spans, roles, ordinals, and
relationship endpoints before destroying it at the current phase boundary.
The first Resolution slice already queries Application and Declaration rows by
stable identity and source-backed name span and appends a typed resolution row
without rescanning tokens. Subsequent slices complete that product and the
SourceGraph vocabulary, then eventually lift owned matrix transfer across
phase boundaries when B provides the capability.
