# Making Neural Language

CPUs gave us one default shape for general computing. GPUs broke that illusion by making parallel work feel like a different world.

Now neural engines, NPUs, DSPs, custom SoC blocks, and whatever comes next are doing the same thing again.

A language should not pretend there is one host anymore.

Gradient needs package-level parameters for the execution world it is describing.

One package may want heavy quantized defaults:

```gradient
#package.defaults
construct NeuralRuntime {
  Float<.8>
  Quantization<.int8>
  TensorLayout<.blocked>
  Engine<.neural>
  Memory<.device>
}
```

Another package may be a rendering framework:

```gradient
#package.defaults
construct RenderRuntime {
  Float<.32>
  Color<.linear>
  TextureLayout<.tiled>
  Engine<.gpu>
  Memory<.shared>
}
```

Multihost solutions are frustrating because they usually glue separate worlds together after the fact.

The better shape is a language that understands the meta system first: CPU, GPU, neural engine, operating system, memory model, bridge, and backend lowering as connected parts of one graph.
