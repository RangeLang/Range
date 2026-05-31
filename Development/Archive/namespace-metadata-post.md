# Namespace Metadata

A namespace is metadata attached to a declaration shape, not just a named block.

## Addition

```range
@namespace
construct Host {
  macro cpu(): Construct -> Host {
    return Host.cpu
  }

  macro gpu(): Construct -> Host {
    return Host.gpu
  }

  macro defaultDevice(): Construct { target, diagnostics in
  }
}

@Host
@Host.gpu
@Host.defaultDevice
construct Renderer {
  Float<.32>
  Memory<.shared>
}
```

## Reason

`@namespace` turns `Host` into a namespace-shaped metadata declaration. The construct is not the runtime thing; it is the surface that collects shared names.

The namespace gathers its macros, functions, and nested declarations under `Host.*`, then makes that metadata available globally through the namespace name. This keeps package-wide concepts visible without scattering every helper into the top-level space.
