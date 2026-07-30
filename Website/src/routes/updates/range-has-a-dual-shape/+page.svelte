<script lang="ts">
  import CodeBlock from "$lib/components/CodeBlock.svelte";
  import EssayPage from "$lib/components/EssayPage.svelte";

  const macroOrganization = `RangeView/
├── Macros/
│   └── Core.range
├── RangeView.range
└── README.md`;

  const appMacro = `macro app(): Construct -> Void { environment in
    let namedRoutes: [Derived](
        environment.target.Declaration.members.filter(all: Derived) { property in
            property.identifier.name == "routes"
        }
    )
    let routeTrees: [Derived<Route>](
        environment.target.Declaration.members.filter(all: Derived<Route>) { property in
            property.identifier.name == "routes"
        }
    )

    if namedRoutes.count == 0 {
        environment.diagnostics.error("@app requires one derived routes declaration.")
    }
    if namedRoutes.count > 1 {
        environment.diagnostics.error("@app routes declaration must not be duplicated.")
    }
    if namedRoutes.count == 1 && routeTrees.count != 1 {
        environment.diagnostics.error("@app routes must have type Route.")
    }
}`;

  const route = `construct Route {
    let _ path: String
    binding _ page: @page?(nil)
    binding _ children: () -> [Route]
}`;

  const functionTypeReference = `@syntax
construct FunctionTypeReference {
    let parameters: [TypeReference]
    let returnType: TypeReference
}`;

  const vStack = `@entry
@component
construct VStack {
    state spacing: Float
    binding _ children: () -> [@component]

    derived body: [@component] {
        children()
    }

    function emit(): Fragment {
        return Fragment(
            html: "<div class=\\"range-view-v-stack\\" style=\\"--range-view-v-stack-spacing: \\(spacing)px\\">\\n",
            css: ".range-view-v-stack { display: flex; flex-direction: column; gap: var(--range-view-v-stack-spacing); }\\n",
            children: children()
        )
    }
}`;
</script>

<EssayPage
  title="Range Has a Dual Shape"
  description="Meta + concrete + late representation."
  category="Observation"
  date="July 30, 2026"
  heroShaderPalette={4}
>
  <section>
    <h2>No language is ever done</h2>
    <p>
      No programming language is ever finished. C is more than fifty years
      old, yet it continues to receive new standards and revisions. Its
      longevity does not mean language design has been settled. It means the
      field remains open.
    </p>

    <p>
      Each new language begins with requirements that existing languages did
      not make central. Its philosophies, theories, and experiments give
      those requirements a concrete form. Once a language makes one of them
      legible, it becomes harder for later languages to ignore.
    </p>

    <p>
      A new language therefore does more than answer a requirement. It can
      create one. What begins as a concept in one language becomes an
      expectation across the field.
    </p>

    <p>
      Range is one such experiment. Its premise is that a program has two
      shapes: the semantic shape held in the graph, and the concrete shape
      chosen when that program must finally be represented.
    </p>
  </section>

  <section>
    <h2>RangeView</h2>
    <p>
      RangeView is idealized Range. It can show the intended language before
      every part of it compiles.
    </p>
  </section>

  <section>
    <h2>Late representation</h2>
    <p>
      <code>VStack</code> keeps its component identity, state, binding, and
      body in the graph. HTML and CSS appear only when <code>emit()</code>
      asks for a concrete fragment.
    </p>

    <CodeBlock
      source={vStack}
      syntax="range"
      label="Meta, concrete, and the representation boundary"
    />
  </section>

  <section>
    <h2>Macros</h2>
    <p>
      I moved every RangeView macro into <code>Macros/</code>.
      <code>@app</code>, <code>@component</code>, and <code>@page</code> now
      live in <code>Macros/Core.range</code>.
    </p>

    <CodeBlock source={macroOrganization} syntax="text" label="RangeView source layout" />
  </section>

  <section>
    <h2>Routes</h2>
    <p>
      An app has exactly one route tree. The macro checks that it exists, is not
      duplicated, and is a derived <code>Route</code>.
    </p>

    <CodeBlock source={appMacro} syntax="range" label="RangeView/Macros/Core.range" />

    <p>
      The route builder does not need an explicit empty default.
    </p>

    <CodeBlock source={route} syntax="range" label="The idealized Route declaration" />

    <p>
      No children already means no routes.
    </p>
  </section>

  <section>
    <h2>The reference knot</h2>
    <p>
      The shape <code>() -&gt; [Route]</code> exposed a larger problem.
    </p>

    <CodeBlock
      source={functionTypeReference}
      syntax="range"
      label="The current FunctionTypeReference wrapper"
    />

    <p>
      This creates a triangle between the binding, a constructed type-reference
      wrapper, and the actual closure. The representation wants a
      higher-dimensional shape.
    </p>
  </section>

  <p>
    The RangeView source above exists today. The complete closure-identity
    model does not compile yet.
  </p>
</EssayPage>
