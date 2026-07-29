# GPU Canvas

This example attaches `@gpuCanvas` to a Range construct. The macro expands an
ordinary `writeGPUCanvas(path:)` function, which calls the authored host
function that materializes a self-contained HTML/WGSL application.

```text
Range macro
  → generated Range function
  → native LLVM executable
  → HTML + WGSL artifact
  → browser WebGPU render pass
```

From the repository root, run the single-file Range application:

```sh
range run GPUCanvas
```

That compiles and links the Range sources, runs `@main`, writes
`/tmp/RangeGPUCanvas.html`, and opens it in the default browser.

Build and validate the complete Range-owned path without launching a browser:

```sh
scripts/range check-gpu-canvas
```

To write the application to a chosen path instead:

```sh
range run GPUCanvas -- /tmp/GPUCanvas.html
```

This is a real WebGPU drawing target, but not a native Range GPU backend. The
browser owns WebGPU adapter selection, WGSL compilation, and command
submission. A future native lowering should consume typed shader values and
Graph 0 dependencies rather than hard-coding shader concepts into the compiler.
