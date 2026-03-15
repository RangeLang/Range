# NeatSyntax TODO

- Treat optional callable and initializer parameters as omission-capable in core signature matching and duplicate-signature validation. Continue improving LSP and IDE presentation so omission-aware invocation shapes are surfaced clearly without requiring authors to duplicate declarations.
- Allow uninitialized `state name: Type` declarations when initialization is completed through `init`, including chained callable-based initialization kicked off from `init`. Add definite-initialization semantics so constructs cannot be used before all required state has been initialized.
