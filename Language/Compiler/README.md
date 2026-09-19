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
one text file per source, including the loaded language grammar definitions. It does not emit the retired compiler schema files. Numeric
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

## Structural syntax in C, language definitions in Range

C directly parses constructs, functions, members, returns, and other structural
syntax. `Language/Grammar` supplies ordinary `Construct`, `Function`, `Member`,
and `Return` declarations. During resolution, C links its parsed nodes and macro
target references to those declaration identities. Reflective field access
continues to use C storage adapters. Duplicate grammar identities, duplicate
fields, and fields without adapters are rejected.

There is no active `@syntax` macro, template validator, or capture-binding table.
The former templates are preserved in `Development/DeferredCompiler/SyntaxTemplates`
as reference material; `@syntax` annotations are rejected by the active parser.
Grammar definitions do not control parsing or require a general macro interpreter.

`@literal` remains in Range: declarations supply recognition patterns and default
construct relationships, while C supplies whole-string regex matching. The lexer
still determines numeric/boolean literal candidates; regex patterns do not control
tokenization. Literal conversion and validation remain unfinished.

Bare immutable members and locals support `let name` alongside `let name: value`.
Type positions accept positional arguments such as `Array<Member>` and nested
`Array<Array<Member>>`; named generic arguments remain supported. This retains
the type syntax without implementing generic specialization or array storage.
`--tree` remains a raw C parse without grammar identity resolution.

The `Function.body` draft (`Array<Return>`) is not enforced as a restriction to
return statements: C still stores a block containing all parsed statements.
Its Range representation remains a separate design question. Grammar field type
validation and native emission are not implemented by these identity bindings.

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
