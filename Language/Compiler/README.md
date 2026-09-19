# Range compiler

The compiler is implemented in C. Core supplies language-level declarations and
macro rules; C owns parsing, graph storage, field access, resolution mechanisms,
and eventually machine-code emission. Self-hosting and seed verification are not
part of the development loop.

## Current pipeline

`source → parse → resolve graph → optional text inspection`

The normal command resolves the loaded sources and reports a census. Native
ARM64/Mach-O emission is not implemented yet: a successful resolution is not a
compiled executable. There is no ordinary-program interpreter or `--run` command.

C maintains the graph node shapes and reflective fields directly. There is no
runtime dependency on `Compiler/Types`, no general template-driven parser, and no
`--graph-types` option. The retired prototype and templates are preserved under
`Development/DeferredCompiler/CPrototype`, outside the active build.

## Build and inspect

```sh
Language/Compiler/Tools/build-range-compiler Language/.range/Build/range-compiler
Language/.range/Build/range-compiler Language/Grammar Language/Macros Language/Types Testing/Compiler/Graph/Functions
Language/.range/Build/range-compiler --emit-graph Language/.range/Build Language/Grammar Language/Macros Language/Types Testing/Compiler/Graph/Functions
Language/.range/Build/range-compiler --tree Language/Grammar Language/Macros Language/Types
Testing/Tools/check-compiler-parser
Testing/Tools/check-compiler-graph
Testing/Tools/check-compiler-literal
```

Rebuild C when compiler code changes. Core and program edits are read by the
existing executable on the next invocation. Sanitized checks are correctness
tests, not required seed/bootstrap steps.

`--emit-graph` runs the same resolution path as the normal command and writes
one text file per source, including the loaded Core grammar definitions and their
syntax templates. It does not emit the retired compiler schema files. Numeric
and boolean literals display directly as `64` and `true`. These files are an
inspection view, never compiler input. `--tree` deliberately shows the raw
parser tree without requiring semantic resolution.

## Implemented resolution

- Parameterless macros attached to constructs get independent application contexts.
- Queries support names, target members/generics, `filter(named:)`, `first`, and
  member values. Unknown fields and cyclic queries fail with source locations.
- `#target` identifies the annotated construct. `#body.members` and
  `#body.environment` expose a macro body's named declarations and retained
  environment blocks. Other statements remain parsed but deferred.
- Plain output names on top-level non-generic functions link to loaded top-level
  constructs. Missing names, specialization, and nested-scope lookup remain deferred.
- Literal-bearing Core macros require one Core construct as their default.
  Numeric and boolean literal nodes link to matching Core rules and their default
  constructs. Project attachments do not override Core defaults; duplicate defaults
  and overlapping matches fail. Linking a literal does not instantiate its type.

Macro validation statements, general macro execution, literal conversion,
return-type compatibility checks, memory-management semantics, and native emission
remain unfinished. The graph resolver is not a substitute for those stages.

## Core grammar bindings

`Language/Grammar` declares `Construct`, `Function`, `Member`, and `Return` with
co-located `@syntax` blocks. `Language/Macros/Syntax.range` declares the C-backed
`macro syntax(): Construct`. During graph resolution, C checks each template
against its supported bootstrap forms and links each `$field` capture to the
actual member declaration. Parsed nodes and macro target references link to the
corresponding Core construct identity. C still owns storage and reflective field
access; these definitions do not load the retired schema engine.

This is the fixed C adapter step: templates are checked and bound after parsing,
not executed to parse the input. Changing a keyword or capture layout to an
unsupported form fails explicitly. The templates describe the basic forms;
existing C parsing of generics, annotations, receivers, and control flow remains
available. `let name` is now supported for bare immutable members and locals,
alongside `let name: value`. General template matching and macro execution are
not implemented. `--tree` remains a raw bootstrap parse without these bindings.
Type positions accept positional arguments such as `Array<Member>` and nested
`Array<Array<Member>>`; named generic arguments remain supported. This retains
the type syntax without implementing generic specialization or array storage.

The `Function.body` draft (`@many Return?`) is not enforced as a restriction to
return statements: C still stores a block containing all parsed statements.
The Core representation of that block needs a design decision before the grammar
field types can govern materialization. The bindings do not claim to validate
those field types or make native execution available.

## Literal recognition probe

Core's `@builtin("literal")` macro provides C-backed POSIX extended regex matching
of entire candidate strings, in the C locale. No numeric conversion is performed.

```sh
Language/.range/Build/range-compiler --match-literal decimal 64 \
  Language/Macros/Literal.range Testing/Compiler/Literal/Rules.range
```

This diagnostic command prints `match=true` or `match=false`; both exit 0.
Invalid patterns, wrong targets, duplicate rules, or missing declarations exit 65.
It remains independent of automatic lexer dispatch.

Directories are loaded recursively, canonicalized, sorted, and deduplicated.
Pass `Language/Grammar`, `Language/Macros`, and `Language/Types` as separate
inputs alongside project sources. Their order does not matter. Those three
folders identify language-owned definitions for grammar bindings and literal
defaults; `Language/Compiler` and generated output do not.
No sources or inaccessible inputs exit 66; parse/resolution errors exit 65;
unsupported options exit 64. Duplicate output basenames are rejected before
graph files are written.
