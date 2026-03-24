# Environment

## Definition

An environment is a graph binding that reads state from higher up in the graph.

## Properties

- Can read outer state without explicit passing

```neat
environment theme: Theme
```

- Supports a read-only form

```neat
environment theme: Theme
```

- Supports a read-write form

```neat
environment state theme: Theme
```

- Resolves by walking outward through the graph

```neat
state theme: Theme = .dark

construct Button {
    environment theme: Theme
}
```

`Button` reads `theme` from the nearest matching outer state.

- Avoids prop drilling through intermediate constructs

```neat
state theme: Theme = .dark

construct Button {
    environment theme: Theme
}
```

- Can drive derived values from outer state

```neat
construct Button {
    environment theme: Theme

    derived backgroundColor: Color {
        return theme == .dark ? .black : .white
    }
}
```

- Can mutate outer state only through the `environment state` form

```neat
construct ThemeToggle {
    environment state theme: Theme

    function toggle() {
        theme = .dark
    }
}
```
