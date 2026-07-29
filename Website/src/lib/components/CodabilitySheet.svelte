<script lang="ts">
  import { onMount } from "svelte";
  import { highlightRange } from "$lib/benchmarks";
  import {
    codabilityChapterIndex,
    codabilityFocusProgress,
    codabilityPlateauScrollProgress,
    nextCodabilityFocusState,
    shouldSynchronizeCodabilityChapter,
    type CodabilityFocusState,
  } from "$lib/codability-focus";
  import codableSource from "../../../../RangeCompiler/Sources/Core/Macro/Codable.range?raw";

  type PaneID = "macro" | "usage";
  type ChapterStep = 1 | 2 | 3 | 4 | 5 | 6 | 7;
  type InspectionID =
    | "decorator"
    | "macro-declaration"
    | "declaration-query"
    | "expansion"
    | "target-mention"
    | "encode-body"
    | "field-synthesis"
    | "property-map"
    | "value-mention"
    | "type-mention"
    | "decode-body";

  type Inspection = {
    id: InspectionID;
    token: string;
    title: string;
    phase?: string;
    result?: string;
    description?: string;
    points?: string[];
    accent?: string;
    accentDescription?: string;
    kind?: "section";
    step?: ChapterStep;
    scopeToken?: string;
  };

  type HighlightedLine = {
    html: string;
    inspectionID?: InspectionID;
    title?: string;
    step?: ChapterStep;
    leadingHTML?: string;
    scopeIDs: InspectionID[];
  };

  function sourceFrom(source: string, marker: string) {
    const markerIndex = source.indexOf(marker);
    return markerIndex === -1 ? source.trim() : source.slice(markerIndex).trim();
  }

  function sourceBetween(source: string, startMarker: string, endMarker: string) {
    const startIndex = source.indexOf(startMarker);
    if (startIndex === -1) return source.trim();
    const endIndex = source.indexOf(endMarker, startIndex + startMarker.length);
    return source.slice(startIndex, endIndex === -1 ? undefined : endIndex).trim();
  }

  function sourceBlock(source: string, marker: string) {
    const start = source.indexOf(marker);
    if (start === -1) return marker;
    const markerBraceOffset = marker.indexOf("{");
    const openingBrace =
      markerBraceOffset === -1
        ? source.indexOf("{", start + marker.length)
        : start + markerBraceOffset;
    if (openingBrace === -1) return marker;
    let depth = 0;

    for (let index = openingBrace; index < source.length; index += 1) {
      if (source[index] === "{") depth += 1;
      if (source[index] === "}") depth -= 1;
      if (depth === 0) return source.slice(start, index + 1);
    }

    return source.slice(start);
  }

  function inlineCodeParts(value: string) {
    return value
      .split(/(`[^`]+`)/g)
      .filter(Boolean)
      .map((part) => {
        const code = part.startsWith("`") && part.endsWith("`");
        return {
          code,
          text: code ? part.slice(1, -1) : part,
        };
      });
  }

  function responsiveIndent(value: string) {
    return value.replace(/(^|\n)( +)/g, (_match, lineStart: string, spaces: string) => {
      const tabCount = Math.floor(spaces.length / 4);
      const remainder = spaces.length % 4;
      return `${lineStart}${"\t".repeat(tabCount)}${" ".repeat(remainder)}`;
    });
  }

  function highlightCode(value: string) {
    return highlightRange(responsiveIndent(value));
  }

  const macroMarker = "macro codable(): Construct";
  const declarationSource = sourceFrom(codableSource, macroMarker).replace(
    /environment\.expand(?=\s*\{)/g,
    "#environment",
  );
  const extensionMarker = "extension #environment.target.Declaration.identifier {";
  const expansionSection = sourceBlock(declarationSource, "#environment");
  const macroDeclarationSection = "macro codable(): Construct { environment in";
  const macroSection = sourceBlock(declarationSource, macroDeclarationSection);
  const extensionSection = sourceBlock(declarationSource, extensionMarker);
  const fieldQuerySection = `    let fields: [@stored](
        environment.target.Declaration.members.filter(all: @stored)
    )`;
  const encodeFunctionSection =
    `            function encode<Format>(to encoder: Encoder<Format>): Result<Void, EncodingError> {
                let container: KeyedEncodingContainer<Format>(encoder.keyedContainer())`;
  const encodeFunctionScope = sourceBlock(
    declarationSource,
    "function encode<Format>(to encoder: Encoder<Format>): Result<Void, EncodingError> {",
  );
  const encodeMapSection = `#fields.map { property in
                    switch container.encode(self.#property.identifier, forKey: #property.identifier.name) {
                    case .success:
                        break
                    case .failure(error):
                        return .failure(cause: error)
                    }
                }`;
  const decodeFunctionSection = sourceBlock(
    declarationSource,
    "function decode<Format>(from decoder: Decoder<Format>): Result<Self, DecodingError> {",
  );
  const userExample = `@codable
construct User {
    let name: String("George")
    state message: String("Working on Range!")
}`;
  const panes = [
    {
      id: "macro",
      label: "Declaration",
      file: "Core/Macro/Codable.range",
      source: declarationSource,
    },
    {
      id: "usage",
      label: "Usage",
      file: "Project/User.range",
      source: userExample,
    },
  ] as const;

  const inspections: Inspection[] = [
    {
      id: "decorator",
      token: "@codable",
      title: "Attaching a macro",
      phase: "declaration",
      result: "one attached macro application",
      description:
        "Attaches codability to the construct. The User now carries `@codable` behavior.",
    },
    {
      id: "macro-declaration",
      token: macroDeclarationSection,
      title: "Declaring the macro",
      description:
        "A standard macro declaration gives the macro:",
      points: [
        "a name",
        "a target",
        "access to the surroundings",
      ],
      kind: "section",
      step: 1,
      scopeToken: macroSection,
    },
    {
      id: "declaration-query",
      token: fieldQuerySection,
      title: "Querying the properties",
      phase: "macro evaluation",
      result: "ordered source-backed fields and state",
      description:
        "Collect the stored properties from the target and filter them. `Declaration.members` exposes the target’s declared members, and `filter(all: @stored)` retains both `let` and `state` properties through their shared storage capability.",
      kind: "section",
      step: 2,
    },
    {
      id: "expansion",
      token: "#environment",
      title: "Normal Range code",
      phase: "macro evaluation",
      result: "generated syntax artifact",
      description:
        "Everything inside the #environment block is normal type-checked code.",
      kind: "section",
      step: 3,
      scopeToken: expansionSection,
    },
    {
      id: "target-mention",
      token: extensionMarker,
      title: "Code splicing",
      phase: "inside expansion",
      result: "an extension of the target construct",
      accent: "#environment.target.Declaration.identifier",
      accentDescription:
        "`Declaration.identifier` is the target construct’s canonical declared name. The # prefix splices that compile-time identifier into the generated extension.",
      kind: "section",
      step: 4,
      scopeToken: extensionSection,
    },
    {
      id: "encode-body",
      token: encodeFunctionSection,
      title: "Ordinary Range code, continued",
      description:
        "The generated `encode<Format>` function keeps the encoder and keyed container on the same coding format, then returns `Result<Void, EncodingError>`.",
      kind: "section",
      step: 5,
      scopeToken: encodeFunctionScope,
    },
    {
      id: "field-synthesis",
      token: encodeMapSection,
      title: "Synthesizing each field",
      description:
        "For every stored property, the macro splices `self.#property.identifier` as the value and its declared identifier name as the coding key.",
      kind: "section",
      step: 6,
      scopeToken: encodeMapSection,
    },
    {
      id: "property-map",
      token: "#fields.map",
      title: "Macro-time collection map",
      phase: "inside expansion",
      result: "one child artifact per property",
      description:
        "The # prefix mentions the compile-time fields collection inside the expansion. map evaluates once per stored field and splices the resulting syntax in order.",
    },
    {
      id: "value-mention",
      token: "#property.identifier",
      title: "Identifier mention",
      phase: "inside expansion",
      result: "a generated field reference",
      description:
        "Mentions the compile-time Identifier value directly in generated syntax, preserving its canonical declaration identity.",
    },
    {
      id: "type-mention",
      token: "#property.type.self",
      title: "Type mention",
      phase: "inside expansion",
      result: "a generated type expression",
      description:
        "Mentions the field’s compile-time TypeReference and projects its type-level self value for decoding.",
    },
    {
      id: "decode-body",
      token: decodeFunctionSection,
      title: "Decoding the construct",
      description:
        "The matching `decode<Format>` function decodes each stored property by its declared type and key, preserves `#property.value` as the default, assigns successful values to `self`, and returns the completed construct.",
      kind: "section",
      step: 7,
      scopeToken: decodeFunctionSection,
    },
  ];
  const inspectionByID = new Map(inspections.map((inspection) => [inspection.id, inspection]));
  const chapters = inspections.filter(
    (inspection): inspection is Inspection & { step: ChapterStep } =>
      inspection.step !== undefined,
  );
  const paneDefaults: Record<PaneID, InspectionID> = {
    macro: "macro-declaration",
    usage: "decorator",
  };

  function tokenIndex(source: string, token: string, fromIndex: number) {
    let index = source.indexOf(token, fromIndex);
    while (index !== -1) {
      const next = source[index + token.length] ?? "";
      if (!/[A-Za-z0-9_]/.test(next)) return index;
      index = source.indexOf(token, index + token.length);
    }
    return -1;
  }

  for (const chapter of chapters) {
    if (tokenIndex(declarationSource, chapter.token, 0) === -1) {
      throw new Error(
        `Codability chapter ${chapter.step} no longer matches Codable.range`,
      );
    }
  }

  function highlightInspectableLines(source: string) {
    const chapterRanges = chapters.flatMap((chapter) => {
      const start = tokenIndex(source, chapter.token, 0);
      return start === -1
        ? []
        : [{ chapter, start, end: start + chapter.token.length }];
    });
    const scopeRanges = chapters.flatMap((chapter) => {
      const scopeToken = chapter.scopeToken ?? chapter.token;
      const start = tokenIndex(source, scopeToken, 0);
      return start === -1
        ? []
        : [{ chapter, start, end: start + scopeToken.length }];
    });
    const lines: HighlightedLine[] = [];
    let lineStart = 0;

    for (const line of source.split("\n")) {
      const lineEnd = lineStart + line.length;
      const intersects = ({ start, end }: { start: number; end: number }) =>
        line.length === 0
          ? lineStart >= start && lineStart < end
          : lineStart < end && lineEnd > start;
      const range = chapterRanges.find(
        intersects,
      );
      const scopeIDs = scopeRanges
        .filter(intersects)
        .map(({ chapter }) => chapter.id);

      if (!range) {
        lines.push({ html: highlightCode(line), scopeIDs });
      } else {
        const isChapterStart =
          lineStart <= range.start && range.start <= lineEnd;
        const leadingWhitespace =
          isChapterStart ? (line.match(/^[\t ]+/)?.[0] ?? "") : "";
        lines.push({
          html: highlightCode(line.slice(leadingWhitespace.length)),
          leadingHTML: highlightCode(leadingWhitespace),
          inspectionID: range.chapter.id,
          title: range.chapter.title,
          step: isChapterStart ? range.chapter.step : undefined,
          scopeIDs,
        });
      }

      lineStart = lineEnd + 1;
    }

    return lines;
  }

  let activeID = $state<PaneID>("macro");
  let activeInspectionID = $state<InspectionID | null>(paneDefaults.macro);
  let stageElement: HTMLDivElement;
  let previewElement: HTMLElement;
  let codeViewportElement: HTMLDivElement;
  let interactionFocused = false;
  let focusState: CodabilityFocusState = "entering";
  let scrollChapterIndex = -1;
  let manualChapterIndex: number | null = null;
  let manualSelectionScrollY = 0;
  let manualSelectionTimestamp = 0;
  let latestStageScrollProgress = 0;
  let storyMode = $state(true);
  let stageFocused = $state(false);
  let activePane = $derived(panes.find((pane) => pane.id === activeID) ?? panes[0]);
  let activeInspection = $derived(
    activeInspectionID ? inspectionByID.get(activeInspectionID) : undefined,
  );
  let activeChapterIndex = $derived(
    chapters.findIndex((chapter) => chapter.id === activeInspectionID),
  );
  let hasChapterSelection = $derived(storyMode && activeChapterIndex >= 0);
  let highlightedLines = $derived(highlightInspectableLines(activePane.source));
  let lineNumbers = $derived(activePane.source.split("\n").map((_, index) => index + 1));

  function selectPane(paneID: PaneID) {
    manualChapterIndex = null;
    activeID = paneID;
    if (paneID === "macro") {
      if (storyMode) {
        scrollChapterIndex = codabilityChapterIndex(
          latestStageScrollProgress,
          chapters.length,
        );
        activeInspectionID =
          chapters[scrollChapterIndex]?.id ?? paneDefaults[paneID];
      } else {
        activeInspectionID = null;
      }
    } else {
      activeInspectionID = paneDefaults[paneID];
    }
  }

  function selectChapter(chapter: (typeof chapters)[number]) {
    storyMode = true;
    activeID = "macro";
    activeInspectionID = chapter.id;
    scrollChapterIndex = chapters.indexOf(chapter);
    manualChapterIndex = scrollChapterIndex;
    manualSelectionScrollY =
      typeof window === "undefined" ? 0 : window.scrollY;
    manualSelectionTimestamp =
      typeof performance === "undefined" ? 0 : performance.now();
    centerChapterInViewport(chapter.id);
  }

  function selectCodeChapter(inspectionID: InspectionID) {
    const chapter = chapters.find((candidate) => candidate.id === inspectionID);
    if (chapter) selectChapter(chapter);
  }

  function isChapterContext(line: HighlightedLine) {
    return (
      activeInspectionID !== null &&
      line.inspectionID !== activeInspectionID &&
      line.scopeIDs.includes(activeInspectionID)
    );
  }

  function moveChapter(direction: -1 | 1) {
    const currentIndex = activeChapterIndex < 0 ? (direction > 0 ? -1 : 0) : activeChapterIndex;
    const nextIndex = (currentIndex + direction + chapters.length) % chapters.length;
    selectChapter(chapters[nextIndex]);
  }

  function setStoryMode(enabled: boolean) {
    manualChapterIndex = null;
    storyMode = enabled;
    if (activeID !== "macro") return;
    if (enabled) {
      scrollChapterIndex = codabilityChapterIndex(
        latestStageScrollProgress,
        chapters.length,
      );
      activeInspectionID =
        chapters[scrollChapterIndex]?.id ?? paneDefaults.macro;
    } else {
      scrollChapterIndex = -1;
      activeInspectionID = null;
    }
    updateStageFocus();
  }

  function centerChapterInViewport(inspectionID: InspectionID) {
    if (!codeViewportElement) return;
    const lines = Array.from(
      codeViewportElement.querySelectorAll<HTMLElement>(
        `[data-inspection-id="${inspectionID}"]`,
      ),
    );
    if (lines.length === 0) return;
    const viewportBounds = codeViewportElement.getBoundingClientRect();
    const firstBounds = lines[0].getBoundingClientRect();
    const lastBounds = lines.at(-1)?.getBoundingClientRect() ?? firstBounds;
    const highlightedCenter = (firstBounds.top + lastBounds.bottom) / 2;
    const viewportCenter = viewportBounds.top + viewportBounds.height / 2;
    const maximumScroll = Math.max(
      0,
      codeViewportElement.scrollHeight - codeViewportElement.clientHeight,
    );
    codeViewportElement.scrollTop = Math.max(
      0,
      Math.min(
        maximumScroll,
        codeViewportElement.scrollTop + highlightedCenter - viewportCenter,
      ),
    );
  }

  function setInteractionFocus(focused: boolean) {
    interactionFocused = focused;
    updateStageFocus();
  }

  function releaseInteractionFocus(event: FocusEvent) {
    const nextTarget = event.relatedTarget;
    if (nextTarget instanceof Node && previewElement.contains(nextTarget)) return;
    setInteractionFocus(false);
  }

  function updateStageFocus(synchronizeStoryChapter = false) {
    if (!stageElement || !previewElement || typeof window === "undefined") return;
    const stageBounds = stageElement.getBoundingClientRect();
    const viewportHeight = window.innerHeight;
    const centerOffset =
      stageBounds.top + stageBounds.height / 2 - viewportHeight / 2;
    const easedProgress = codabilityFocusProgress({
      stageTop: stageBounds.top,
      stageHeight: stageBounds.height,
      viewportHeight,
    });
    const radius = (1 - easedProgress) * 24;

    previewElement.style.setProperty("--focus-progress", easedProgress.toFixed(4));
    previewElement.style.setProperty("--focus-radius", `${radius.toFixed(2)}px`);
    focusState = nextCodabilityFocusState({
      state: focusState,
      progress: easedProgress,
      centerOffset,
      interactionFocused,
    });
    stageFocused = focusState === "focused";
    previewElement.dataset.focusState = focusState;
    previewElement.toggleAttribute("data-stage-focused", stageFocused);

    const stageScrollProgress = codabilityPlateauScrollProgress({
      stageTop: stageBounds.top,
      stageHeight: stageBounds.height,
      viewportHeight,
    });
    latestStageScrollProgress = stageScrollProgress;
    const nextScrollChapterIndex = codabilityChapterIndex(
      stageScrollProgress,
      chapters.length,
    );
    const canSynchronizeStoryChapter =
      synchronizeStoryChapter &&
      shouldSynchronizeCodabilityChapter({
        manualChapterIndex,
        selectionScrollY: manualSelectionScrollY,
        currentScrollY: window.scrollY,
        elapsedMilliseconds:
          (typeof performance === "undefined" ? 0 : performance.now()) -
          manualSelectionTimestamp,
      });
    if (
      storyMode &&
      activeID === "macro" &&
      canSynchronizeStoryChapter &&
      nextScrollChapterIndex !== scrollChapterIndex
    ) {
      manualChapterIndex = null;
      scrollChapterIndex = nextScrollChapterIndex;
      activeInspectionID = chapters[nextScrollChapterIndex]?.id ?? null;
    }
    if (storyMode && activeID === "macro" && activeInspectionID) {
      centerChapterInViewport(activeInspectionID);
    } else {
      const codeScrollDistance = Math.max(
        0,
        codeViewportElement.scrollHeight - codeViewportElement.clientHeight,
      );
      codeViewportElement.scrollTop = codeScrollDistance * stageScrollProgress;
    }
  }

  onMount(() => {
    let frame = 0;
    let pendingStorySynchronization = false;
    const scheduleUpdate = (synchronizeStoryChapter = false) => {
      pendingStorySynchronization ||= synchronizeStoryChapter;
      if (frame) return;
      frame = window.requestAnimationFrame(() => {
        frame = 0;
        const shouldSynchronize = pendingStorySynchronization;
        pendingStorySynchronization = false;
        updateStageFocus(shouldSynchronize);
      });
    };
    const scheduleScrollUpdate = () => scheduleUpdate(true);
    const scheduleGeometryUpdate = () => scheduleUpdate(false);

    updateStageFocus(true);
    window.addEventListener("scroll", scheduleScrollUpdate, { passive: true });
    window.addEventListener("resize", scheduleGeometryUpdate);
    const viewportObserver = new ResizeObserver(scheduleGeometryUpdate);
    viewportObserver.observe(codeViewportElement);

    return () => {
      if (frame) window.cancelAnimationFrame(frame);
      viewportObserver.disconnect();
      window.removeEventListener("scroll", scheduleScrollUpdate);
      window.removeEventListener("resize", scheduleGeometryUpdate);
    };
  });
</script>

<section class="codabilitySheet" aria-labelledby="codability-title">
  <div class="codabilityIntro">
    <p class="sheetIndex">01 · metaprogramming</p>
    <h1 class="codabilityTitle" id="codability-title">Codability Under 100</h1>
    <p class="sheetSummary">
      <code>@codable</code> reads the target construct’s stored values, maps
      each field through Range-authored helpers, and expands a typed coding
      extension.
    </p>

    <ol class="codabilityFlow">
      <li>
        <span>01</span>
        <div><strong>Collect</strong><small>stored properties</small></div>
      </li>
      <li>
        <span>02</span>
        <div><strong>Map</strong><small>property keys and types</small></div>
      </li>
      <li>
        <span>04</span>
        <div><strong>Expand</strong><small>encode + decode bodies</small></div>
      </li>
    </ol>
  </div>

  <div class="codabilityStage" bind:this={stageElement}>
  <article
    class="codePreviewCard"
    class:stageFocused
    bind:this={previewElement}
    aria-label="Range codability source preview"
    onfocusin={() => setInteractionFocus(true)}
    onfocusout={releaseInteractionFocus}
  >
    <header class="previewHeader">
      <div class="sourceIdentity">
        <span class="sourcePulse" aria-hidden="true"></span>
        <div>
          <strong>{activePane.file}</strong>
        </div>
      </div>

      <div class="previewControls">
        {#if activeID === "macro"}
          <button
            class="storyModeToggle"
            type="button"
            aria-label="Story mode"
            aria-pressed={storyMode}
            onclick={() => setStoryMode(!storyMode)}
          >
            Story
          </button>
        {/if}
        <div class="previewTabs" role="tablist" aria-label="Codability source view">
          {#each panes as pane}
            <button
              type="button"
              role="tab"
              aria-selected={activeID === pane.id}
              aria-controls="codability-source"
              onclick={() => selectPane(pane.id)}
            >
              {pane.label}
            </button>
          {/each}
        </div>
      </div>
    </header>

    {#if activeID === "macro" && storyMode}
      <nav class="chapterNav" aria-label="Codability chapters">
        <button
          type="button"
          aria-label="Previous chapter"
          onclick={() => moveChapter(-1)}
        >
          <svg viewBox="0 0 16 16" aria-hidden="true">
            <path d="m4.5 10 3.5-3.5 3.5 3.5"></path>
          </svg>
        </button>
        {#each chapters as chapter}
          <button
            type="button"
            aria-label={`Chapter ${chapter.step}: ${chapter.title}`}
            aria-current={activeInspectionID === chapter.id ? "step" : undefined}
            aria-pressed={activeInspectionID === chapter.id}
            onclick={() => selectChapter(chapter)}
          >
            {chapter.step}
          </button>
        {/each}
        <button
          type="button"
          aria-label="Next chapter"
          onclick={() => moveChapter(1)}
        >
          <svg viewBox="0 0 16 16" aria-hidden="true">
            <path d="m4.5 6 3.5 3.5L11.5 6"></path>
          </svg>
        </button>
      </nav>
    {/if}

    <div
      class="codeWorkspace"
      class:inspectionVisible={activeInspection !== undefined}
    >
      <div
        class="codeViewport"
        bind:this={codeViewportElement}
        id="codability-source"
        role="tabpanel"
        tabindex="0"
        aria-label={`${activePane.label} source`}
      >
        <div class="codeCanvas">
          <ol class="lineNumbers" aria-hidden="true">
            {#each lineNumbers as line}
              <li>{line}</li>
            {/each}
          </ol>
          <pre class="rangeSource language-range"><code class:chapterFiltered={hasChapterSelection}>{#each highlightedLines as line}{#if line.inspectionID}<span
                class="codeLine"
                class:chapterActive={activeInspectionID === line.inspectionID}
              data-inspection-id={line.inspectionID}
              >{@html line.leadingHTML ?? ""}<button
                  type="button"
                  class="inspectToken inspectSection"
                  class:chapterStart={line.step !== undefined}
                  aria-label={line.title}
                  aria-pressed={activeInspectionID === line.inspectionID}
                  onclick={() => selectCodeChapter(line.inspectionID!)}
                >{#if line.step}<span class="chapterBadge" data-step={line.step} aria-hidden="true">{line.step}</span>{/if}<span class="lineCodeContent" class:chapterContext={isChapterContext(line)}>{@html line.html}</span></button></span>{:else}<span class="codeLine"><span class="lineCodeContent" class:chapterContext={isChapterContext(line)}>{@html line.html}</span></span>{/if}{/each}</code></pre>
        </div>
      </div>

      {#if activeInspection}
        <aside
          class="codeInspector"
          id="codability-inspector"
          aria-live="polite"
          aria-label="Code inspection"
        >
          <div class="inspectorBody">
            <h3>{activeInspection.title}</h3>
            {#if activeInspection.accent || activeInspection.description}
              <div class="inspectorDescription">
                {#if activeInspection.description}
                  <p>
                    {#each inlineCodeParts(activeInspection.description) as part}
                      {#if part.code}
                        <code class="inspectorInlineCode">{part.text}</code>
                      {:else}
                        {part.text}
                      {/if}
                    {/each}
                  </p>
                {/if}
                {#if activeInspection.points}
                  <ul class="inspectorPoints">
                    {#each activeInspection.points as point}
                      <li>{point}</li>
                    {/each}
                  </ul>
                {/if}
                {#if activeInspection.accent}
                  <code class="inspectionAccent">{activeInspection.accent}</code>
                {/if}
                {#if activeInspection.accentDescription}
                  <p class="inspectionAccentDescription">
                    {#each inlineCodeParts(activeInspection.accentDescription) as part}
                      {#if part.code}
                        <code class="inspectorInlineCode">{part.text}</code>
                      {:else}
                        {part.text}
                      {/if}
                    {/each}
                  </p>
                {/if}
              </div>
            {/if}
          </div>
        </aside>
      {/if}
    </div>

  </article>
  </div>
</section>

<style>
  .codabilitySheet {
    display: grid;
    gap: clamp(44px, 6vw, 72px);
    align-items: start;
    padding: clamp(72px, 9vw, 112px) 0 0;
  }

  .codabilityIntro {
    display: grid;
    grid-template-columns: minmax(0, 1fr) minmax(320px, 0.72fr);
    column-gap: clamp(44px, 8vw, 108px);
    align-content: start;
  }

  .sheetIndex,
  .codabilityTitle,
  .sheetSummary {
    grid-column: 1;
  }

  .sheetIndex {
    margin: 0 0 22px;
    color: var(--range);
    font-family: var(--font-geist-mono), monospace;
    font-size: 10px;
    font-weight: 550;
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }

  .codabilityTitle {
    max-width: 390px;
    margin: 0;
    font-size: clamp(34px, 4.4vw, 58px);
    font-weight: 500;
    letter-spacing: -0.055em;
    line-height: 0.98;
  }

  .sheetSummary {
    max-width: 410px;
    margin: 28px 0 0;
    color: var(--muted);
    font-size: 15px;
    line-height: 1.58;
  }

  .sheetSummary code {
    color: var(--ink);
    font-family: var(--font-geist-mono), monospace;
    font-size: 0.9em;
  }

  .codabilityFlow {
    grid-column: 2;
    grid-row: 1 / span 3;
    display: grid;
    gap: 0;
    margin: 0;
    padding: 0;
    border-top: 1px solid var(--line);
    list-style: none;
  }

  .codabilityFlow li {
    display: grid;
    grid-template-columns: 30px minmax(0, 1fr);
    gap: 12px;
    align-items: start;
    padding: 14px 0;
    border-bottom: 1px solid var(--line);
  }

  .codabilityFlow li > span {
    padding-top: 2px;
    color: var(--range);
    font-family: var(--font-geist-mono), monospace;
    font-size: 9px;
  }

  .codabilityFlow li > div {
    display: grid;
    gap: 3px;
  }

  .codabilityFlow strong {
    font-size: 13px;
    font-weight: 550;
  }

  .codabilityFlow small {
    color: var(--muted);
    font-size: 11px;
  }

  .codePreviewCard {
    --focus-progress: 0;
    --focus-radius: 24px;
    position: sticky;
    z-index: 5;
    top: 0;
    width: 100vw;
    height: 100svh;
    min-width: 0;
    display: grid;
    grid-template-rows: auto minmax(0, 1fr);
    overflow: hidden;
    border: 0;
    border-radius: var(--focus-radius);
    background: #fff;
    box-shadow: none;
    will-change: border-radius;
  }

  .codabilityStage {
    position: relative;
    width: 100vw;
    height: 220svh;
    margin-left: calc(50% - 50vw);
  }

  .codeWorkspace {
    display: grid;
    grid-template-columns: minmax(0, 1fr);
    min-height: 0;
    overflow: hidden;
  }

  .codeWorkspace.inspectionVisible {
    grid-template-columns: minmax(0, 1fr);
    grid-template-rows: minmax(0, 1fr) clamp(165px, 18svh, 185px);
  }

  .previewHeader {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 24px;
    padding: clamp(18px, 2vw, 28px) clamp(24px, 4vw, 72px);
    background: oklch(0.992 0.003 255);
  }

  .sourceIdentity {
    min-width: 0;
    display: flex;
    align-items: center;
    gap: 10px;
  }

  .sourcePulse {
    width: 9px;
    height: 9px;
    flex: 0 0 auto;
    border-radius: 50%;
    background: var(--range);
    box-shadow: 0 0 0 4px color-mix(in oklch, var(--range), transparent 90%);
  }

  .sourceIdentity > div {
    min-width: 0;
    display: grid;
    gap: 2px;
  }

  .sourceIdentity strong {
    overflow: hidden;
    font-family: var(--font-geist-mono), monospace;
    font-size: 13px;
    font-weight: 500;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .previewControls {
    display: inline-flex;
    flex: 0 0 auto;
    gap: 6px;
    align-items: center;
  }

  .storyModeToggle,
  .previewTabs {
    font-family: var(--font-geist-mono), monospace;
  }

  .storyModeToggle {
    min-height: 31px;
    padding: 0 10px;
    border: 0;
    border-radius: 8px;
    background: transparent;
    color: var(--muted);
    cursor: pointer;
    font-size: 11px;
  }

  .storyModeToggle[aria-pressed="true"] {
    color: var(--range);
    font-weight: 600;
  }

  .storyModeToggle:focus-visible {
    outline: 2px solid var(--range);
    outline-offset: 2px;
  }

  .previewTabs {
    display: inline-flex;
    flex: 0 0 auto;
    gap: 2px;
    padding: 2px;
    border: 0;
    border-radius: 12px;
    background: color-mix(in oklch, var(--line), transparent 68%);
  }

  .previewTabs button {
    min-height: 31px;
    padding: 0 10px;
    border: 0;
    border-radius: 8px;
    background: transparent;
    color: var(--muted);
    cursor: pointer;
    font-family: inherit;
    font-size: 11px;
  }

  .previewTabs button[aria-selected="true"] {
    background: var(--paper);
    box-shadow: 0 1px 3px color-mix(in oklch, var(--ink), transparent 90%);
    color: var(--ink);
  }

  .previewTabs button:focus-visible {
    outline: 2px solid var(--range);
    outline-offset: 2px;
  }

  .codeViewport {
    container-type: inline-size;
    height: auto;
    min-height: 0;
    overflow: hidden;
    background: #fff;
    scrollbar-width: none;
  }

  .codeViewport::-webkit-scrollbar {
    width: 0;
    height: 0;
  }

  .codePreviewCard.stageFocused .codeViewport {
    overflow-x: auto;
    overflow-y: hidden;
  }

  .codeCanvas {
    width: max-content;
    min-width: 100%;
    display: grid;
    grid-template-columns: 70px minmax(max-content, 1fr);
  }

  .lineNumbers {
    display: grid;
    align-content: start;
    margin: 0;
    padding: 30px 16px 34px 0;
    background: #fff;
    color: color-mix(in oklch, var(--muted), transparent 32%);
    font-family: var(--font-geist-mono), monospace;
    font-size: 12px;
    line-height: 1.8;
    list-style: none;
    text-align: right;
    user-select: none;
  }

  pre {
    min-width: 0;
    margin: 0;
    padding: 30px clamp(28px, 4vw, 64px) 34px 24px;
    color: #000000d9;
    font-family: var(--font-geist-mono), monospace;
    font-size: clamp(13px, 1.15vw, 16px);
    line-height: 1.8;
    tab-size: clamp(1.15rem, 2.5cqw, 2rem);
  }

  code {
    font-family: inherit;
  }

  :global(.codePreviewCard .inspectToken) {
    display: inline;
    appearance: none;
    border: 0;
    margin: 0;
    padding: 0;
    background: transparent;
    color: inherit;
    font: inherit;
    line-height: inherit;
    text-align: inherit;
    text-decoration: none;
  }

  :global(.codePreviewCard .inspectSection) {
    position: relative;
    cursor: pointer;
    text-decoration: none;
  }

  :global(.codePreviewCard .inspectSection:focus-visible) {
    outline: 2px solid var(--range);
    outline-offset: 3px;
  }

  :global(.codePreviewCard .codeLine) {
    position: relative;
    display: block;
    min-height: 1.8em;
  }

  :global(.codePreviewCard .chapterStart.inspectSection) {
    position: static;
  }

  :global(.codePreviewCard .lineCodeContent) {
    opacity: 1;
    filter: blur(0);
  }

  :global(.codePreviewCard .chapterFiltered .lineCodeContent) {
    opacity: 0.24;
  }

  :global(.codePreviewCard .chapterFiltered .chapterContext) {
    opacity: 0.48;
    filter: blur(0);
  }

  :global(.codePreviewCard .chapterFiltered .chapterActive .lineCodeContent) {
    opacity: 1;
  }

  :global(.codePreviewCard .chapterBadge) {
    position: absolute;
    top: 50%;
    left: -2.25em;
    transform: translateY(-50%);
    display: inline-grid;
    width: 1.45em;
    height: 1.45em;
    place-items: center;
    border: 0;
    border-radius: 50%;
    background: var(--range);
    color: white;
    font-size: 0.68em;
    font-weight: 700;
    line-height: 1;
    opacity: 1;
  }

  .codeInspector {
    position: relative;
    grid-row: 2;
    min-width: 0;
    display: block;
    background: linear-gradient(
      160deg,
      oklch(0.994 0.004 300),
      oklch(0.998 0.002 255)
    );
  }

  .chapterNav {
    position: absolute;
    z-index: 2;
    top: 50svh;
    right: clamp(10px, 1.25vw, 20px);
    display: grid;
    gap: 3px;
    padding: 5px;
    border-radius: 999px;
    background: color-mix(in oklch, white, transparent 18%);
    box-shadow: 0 8px 28px color-mix(in oklch, var(--ink), transparent 94%);
    transform: translateY(-50%);
    contain: layout paint;
  }

  .chapterNav button {
    width: 28px;
    height: 28px;
    display: grid;
    place-items: center;
    padding: 0;
    border: 0;
    border-radius: 50%;
    background: transparent;
    color: color-mix(in oklch, var(--muted), transparent 10%);
    cursor: pointer;
    font-family: var(--font-geist-mono), monospace;
    font-size: 10px;
    font-weight: 560;
    line-height: 1;
  }

  .chapterNav button:hover {
    color: var(--ink);
  }

  .chapterNav button[aria-current="step"] {
    background: var(--range);
    color: white;
  }

  .chapterNav button:focus-visible {
    outline: 2px solid var(--range);
    outline-offset: 1px;
  }

  .chapterNav svg {
    width: 14px;
    height: 14px;
    fill: none;
    stroke: currentColor;
    stroke-linecap: round;
    stroke-linejoin: round;
    stroke-width: 1.5;
  }

  .inspectorBody {
    width: 100%;
    height: 100%;
    align-self: stretch;
    box-sizing: border-box;
    display: grid;
    grid-template-columns: minmax(220px, 0.38fr) minmax(0, 1fr);
    align-content: start;
    column-gap: clamp(28px, 4vw, 64px);
    padding: clamp(20px, 2.5vw, 34px) clamp(24px, 4vw, 72px);
  }

  .inspectorBody h3 {
    grid-column: 1;
    margin: 0;
    font-size: clamp(26px, 2.2vw, 38px);
    font-weight: 520;
    letter-spacing: -0.035em;
    line-height: 1.1;
    align-self: start;
  }

  .inspectorBody p {
    margin: 0;
    color: var(--muted);
    font-size: clamp(13px, 1.2vw, 17px);
    line-height: 1.62;
  }

  .inspectorBody p + p {
    margin-top: 8px;
  }

  .inspectorPoints {
    display: grid;
    gap: 2px;
    margin: 8px 0 0;
    padding-left: 1.2em;
    color: var(--muted);
    font-size: clamp(12px, 1.05vw, 15px);
    line-height: 1.45;
  }

  .inspectorInlineCode {
    padding: 0.1em 0.3em;
    border-radius: 0.28em;
    background: oklch(0.975 0 0);
    color: oklch(0.5 0 0);
    font-family: var(--font-geist-mono), monospace;
    font-size: 0.88em;
    font-weight: 560;
    white-space: nowrap;
  }

  .inspectionAccent {
    display: block;
    margin-top: 10px;
    color: var(--range);
    font-family: var(--font-geist-mono), monospace;
    font-size: clamp(13px, 1.15vw, 16px);
    font-weight: 650;
    line-height: 1.5;
    overflow-wrap: anywhere;
  }

  .inspectorBody .inspectionAccentDescription {
    margin-top: 10px;
  }

  .inspectorDescription {
    grid-column: 2;
    grid-row: 1;
    align-self: center;
  }

  @media (max-width: 900px) {
    .codabilityIntro {
      grid-template-columns: minmax(0, 1fr) minmax(220px, 0.72fr);
      column-gap: 40px;
    }

    .codeWorkspace {
      grid-template-columns: 1fr;
      grid-template-rows: minmax(0, 1fr);
    }

    .codeWorkspace.inspectionVisible {
      grid-template-rows: minmax(0, 1fr) clamp(180px, 22svh, 210px);
    }

    .codeInspector {
      width: 100%;
      height: 100%;
      min-height: 0;
      overflow: hidden;
    }

    .inspectorBody {
      grid-column: 1 / -1;
      display: grid;
      grid-template-columns: 160px minmax(0, 1fr);
      column-gap: 24px;
      padding: clamp(28px, 4vw, 56px) clamp(22px, 3vw, 44px);
    }

    .inspectorBody h3 {
      grid-column: 1;
    }

    .inspectorDescription {
      grid-column: 2;
      grid-row: 1;
    }

    .inspectionAccent,
    .inspectorDescription p {
      margin-top: 0;
    }

    .inspectorDescription p + .inspectionAccent {
      margin-top: 12px;
    }

  }

  @media (max-width: 620px) {
    .codeWorkspace.inspectionVisible {
      grid-template-rows: minmax(0, 1fr) clamp(210px, 28svh, 250px);
    }

    .codabilitySheet {
      padding: 68px 0;
    }

    .codabilityIntro {
      display: grid;
      grid-template-columns: 1fr;
    }

    .sheetIndex,
    .codabilityTitle,
    .sheetSummary,
    .codabilityFlow {
      grid-column: 1;
    }

    .codabilityFlow {
      grid-row: auto;
      margin-top: 34px;
    }

    .previewHeader {
      display: grid;
      gap: 13px;
    }

    .previewTabs {
      width: 100%;
    }

    .previewTabs button {
      flex: 1 1 0;
    }

    .codeInspector {
      display: grid;
      grid-template-columns: 1fr;
    }

    .inspectorBody {
      display: grid;
      grid-template-columns: 1fr;
      padding: 22px 18px;
    }

    .inspectorBody h3,
    .inspectorDescription {
      grid-column: 1;
    }

    .inspectorDescription {
      grid-row: auto;
      margin-top: 13px;
    }

  }

  @media (prefers-reduced-motion: reduce) {
    .codePreviewCard {
      border-radius: 0;
      transform: none;
      transition: none;
    }
  }
</style>
