# Declaration Headers

Neat uses declaration headers to describe what a declaration is and where it projects.

Examples:

```neat
#Theme {
}

#Logger: Service {
    @write(text: String)
}

#Formatter on Record: Service {
    @format(text: String)
}

#SharedTools: Service {
    Record@normalize()
}
```

Current direction:

- `#Name` declares a named language object
- `on Target` sets a default projection target for the declaration
- `: Contract` describes the declaration's composed contract or category
- `@name(...)` declares a callable member
- `Target@name(...)` attaches a callable to a specific target directly
