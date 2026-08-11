# Compiler B

Run the first Compiler B application with:

```text
scripts/range compiler b
```

Compiler A compiles Compiler B as an ordinary Range application. The resulting
B process opens the supplied product source, lexes it, and constructs the first
declaration/application graph directly without importing the legacy compiler.
The product reports vocabulary counts and a deterministic identity checksum.
Exit 65 means B rejected the product source. Successful and rejected products
and application records are both retained. `scripts/range check-compiler-b`
proves 48 retained fact rows, including one graph-derived
Application-to-Declaration Resolution, for the positive fixture and exact
unclosed-Block rejection for the negative fixture.
