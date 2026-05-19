# Namespace Metadata

A namespace is metadata attached to a declaration shape, not just a named block.

## Addition

```neat
#namespace
construct Host {
  marker cpu(): Construct -> Host {
    return Host.cpu
  }

  marker gpu(): Construct -> Host {
    return Host.gpu
  }

  macro defaultDevice(): Construct { target, diagnostics in
  }
}

@Host
#Host.gpu
#Host.defaultDevice
construct Renderer {
  Float<.32>
  Memory<.shared>
}
```

## Reason

`#namespace` turns `Host` into a namespace-shaped metadata declaration. The construct is not the runtime thing; it is the surface that collects shared names.

The namespace gathers its markers, macros, functions, and nested declarations under `Host.*`, then makes that metadata available globally through the namespace name. This keeps package-wide concepts visible without scattering every helper into the top-level space.
