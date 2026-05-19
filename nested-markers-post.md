# Nested Markers

Markers can carry smaller marker scopes inside them.

## Addition

```neat
#package.defaults
construct RuntimeDefaults {
  #host.cpu
  construct Control {
    Float<.64>
    Memory<.system>
  }

  #host.gpu
  construct Render {
    Float<.32>
    TextureLayout<.tiled>
    Memory<.shared>
  }

  #host.neural
  construct Inference {
    Float<.8>
    Quantization<.int8>
    TensorLayout<.blocked>
    Memory<.device>
  }
}
```

## Reason

The outer marker says these declarations are package defaults. The nested markers say which execution world each default belongs to.

This keeps the graph shaped like the source: package policy first, then host-specific defaults underneath it.

## Implementation Shape

```neat
marker host(): Namespace<Construct> {
  marker cpu(): Construct -> Host {
    return Host.cpu
  }

  marker gpu(): Construct -> Host {
    return Host.gpu
  }

  marker neural(): Construct -> Host {
    return Host.neural
  }
}
```

The nested declarations make `#host.gpu` a scoped marker, not a global spelling convention. The package defaults can read that marker as host metadata while keeping the public name anchored to `host`.

## Types In Multiple Dimensions

Neat types are not locked to one machine shape. Nested markers let a package announce host, architecture, memory, availability, and lowering facts at the same time.

```neat
#package.defaults
construct RuntimeDefaults {
  #host.cpu.microcontroller
  construct SensorLoop {
    Int<.16>
    Float<.32>
    Memory<.static>
    Allocation<.none>
  }

  #host.cpu.arm
  construct MobileRuntime {
    Int<.64>
    Float<.32>
    Vector<.neon>
    Memory<.unified>
  }

  #host.cpu.x86
  construct WorkstationRuntime {
    Int<.64>
    Float<.64>
    Vector<.avx2>
    Memory<.system>
  }
}
```

CPU is not one target. A microcontroller, an ARM device, and an x86 workstation can share source concepts while carrying different numeric widths, memory rules, vector paths, and allocation defaults.

## GPU Hosts

```neat
#package.defaults
construct GraphicsDefaults {
  #host.gpu.apple
  construct AppleGPU {
    Float<.32>
    TextureLayout<.tiled>
    Memory<.unified>
  }

  #host.gpu.nvidia
  construct NvidiaGPU {
    Float<.32>
    TensorLayout<.blocked>
    Memory<.device>
  }

  #host.gpu.web
  construct WebGPU {
    Float<.32>
    BufferLayout<.portable>
    Memory<.browser>
  }
}
```

GPU is not one target either. Neat can name the host family directly, so rendering, compute, tensor, texture, and buffer defaults do not have to collapse into one generic graphics setting.

## Server And Client Availability

```neat
#availability.server
construct TrainingJob {
  TensorLayout<.blocked>
  Memory<.device>
  FileSystem<.full>
}

#availability.client
construct PreviewModel {
  TensorLayout<.portable>
  Memory<.shared>
  FileSystem<.sandboxed>
}
```

Availability becomes another axis of type meaning. A server type can expose storage, device memory, and batch-oriented defaults; a client type can keep the same domain shape while using sandboxed storage, shared memory, and portable layouts.

The graph has enough structure for editors, packages, and backends to make decisions without guessing from platform flags after the fact.
