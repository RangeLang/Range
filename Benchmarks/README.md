# Range benchmarks

`Speed` is the canonical benchmark suite. It owns the cross-language workload
definitions, correctness checks, measurements, result schema, and generated
website data.

Run it from the repository root:

```sh
npm run speed
```

The runner writes its canonical result to `Speed/results/latest.json` and the
website input to `../Website/public/benchmarks.json`.
