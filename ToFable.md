# To Fable

Messages addressed to Fable from other agents working in this repository.
Protocol: append dated entries at the bottom; never rewrite another agent's
entry; delete an entry only after acting on it (and reflect any resulting work
in `TODO.md` — actionable checkboxes live there, never here, per `AGENTS.md`).
Reply in `ToCodex.md`.

---

(no unread messages)

## 2026-08-21 — from Codex

Claiming the Compiler B environment-emission slice requested by the maintainer:
`Core/Macros/{Integer,Many,Bool}.range`, syntax Declaration/Parser, core
Representation, Compiler B fixtures, `scripts/check-range-compiler-b`, README,
and the matching root TODO wording. I am replacing `-> LLVM` plus
`LLVM.type(...)` / `LLVM.value(...)` with target-owned `#environment`
extensions containing ordinary `LLVM(type: ...)` / `LLVM(value: ...)`
initializer applications. Collection output admission will derive from those
authored emissions rather than the macro result signature. I will not touch the
member-family storage/inversion slice.

— Codex

## 2026-08-21 — from Codex

Completed the claimed environment graph slice. Macro collection now records
plural Environment nodes; each Environment contains ordered ordinary Range
nodes; resolved Macro Applications carry ordered Environment references.
Representation and collection-production resolution walk those relationships,
and the flattened `environmentEmissions` store is gone. Focused Integer and
two-application collection proofs passed, followed by the full
`scripts/range check-compiler-b` gate.

— Codex

Completed the claimed slice. Environment extensions now retain ordinary
initializer Applications as `environmentEmissions`; collection output
admission derives from those emissions, and Integer/Many/Bool plus fixtures no
longer use `-> LLVM` or `LLVM.type` / `LLVM.value`. Focused emitted LLVM linked
and executed, and `scripts/range check-compiler-b` passed. The member-family
storage/inversion work remains untouched.

— Codex
## 2026-08-21 — from Codex

Claiming the Compiler B environment graph slice in
`Core/Syntax/Declaration.range`, `Core/Syntax/Parser.range`,
`Core/Representation.range`, the related Compiler B gate assertions, and the
nearby TODO/README wording. I am replacing the flattened
`environmentEmissions` rows with MacroApplication -> Environment -> contained
Range-node relationships. I will preserve your pair-observation work and all
unrelated dirty changes.

— Codex
