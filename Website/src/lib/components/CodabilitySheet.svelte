<script lang="ts">
  import { getContext, onMount } from "svelte";
  import {
    RANGE_LAYOUT_TRACKER_CONTEXT,
    type RangeLayoutTracker,
  } from "$lib/layout/layout-tracker";
  import { highlightRange } from "$lib/benchmarks";
  import {
    codabilityChapterIndex,
    codabilityFocusProgress,
    codabilityStickyScrollProgress,
    nextCodabilityFocusState,
    shouldSynchronizeCodabilityChapter,
    type CodabilityFocusState,
  } from "$lib/codability-focus";
  import codableSource from "$lib/sources/Codable.range?raw";
  import commandGroupSource from "../../../../Language/Core/Macros/CommandGroup.range?raw";

  const layoutTracker = getContext<RangeLayoutTracker | undefined>(
    RANGE_LAYOUT_TRACKER_CONTEXT,
  );

  let {
    variant = "codability",
    showIntro = true,
  }: {
    variant?: "codability" | "commandGroup";
    showIntro?: boolean;
  } = $props();

  type ChapterStep = 1 | 2 | 3 | 4 | 5 | 6 | 7;
  type ChapterScrollState =
    | { phase: "idle"; chapterIndex: number }
    | {
        phase: "manual";
        chapterIndex: number;
        selectionScrollY: number;
        selectedAt: number;
      };
  type ChapterScrollEvent =
    | { type: "select"; chapterIndex: number; scrollY: number; now: number }
    | { type: "release-manual" }
    | { type: "reset"; chapterIndex: number };
  type InspectionID =
    | "macro-declaration"
    | "declaration-query"
    | "expansion"
    | "target-mention"
    | "encode-body"
    | "field-synthesis"
    | "property-map"
    | "value-mention"
    | "type-mention"
    | "decode-body"
    | "command-declaration"
    | "command-query"
    | "command-validation"
    | "command-expansion"
    | "command-map";

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

  function transitionChapterScroll(
    state: ChapterScrollState,
    event: ChapterScrollEvent,
  ): ChapterScrollState {
    if (event.type === "select") {
      return {
        phase: "manual",
        chapterIndex: event.chapterIndex,
        selectionScrollY: event.scrollY,
        selectedAt: event.now,
      };
    }
    if (event.type === "reset") {
      return { phase: "idle", chapterIndex: event.chapterIndex };
    }
    if (event.type === "release-manual") {
      return state.phase === "manual"
        ? { phase: "idle", chapterIndex: state.chapterIndex }
        : state;
    }
    return state;
  }

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
    const highlighted = highlightRange(responsiveIndent(value));
    return highlighted.replace(
      /(<[^>]+>)|([^<]+)/g,
      (_match, tag: string | undefined, text: string | undefined) => {
        if (tag) return tag;
        return (text ?? "")
          .match(/&(?:#\d+|#x[\da-f]+|[a-z]+);|[\s\S]/gi)
          ?.map((glyph) => `<span class="waveGlyph">${glyph}</span>`)
          .join("") ?? "";
      },
    );
  }

  const isCommandGroup = variant === "commandGroup";
  const breakdown = isCommandGroup
    ? {
        index: "02 · macro breakdown",
        title: "Registration by Declaration",
        summary:
          "@commandGroup reads annotated functions, validates the group, and expands a construct-owned command set.",
        file: "Core/Macro/CommandGroup.range",
        flow: [
          { number: "01", title: "Collect", detail: "@command functions" },
          { number: "02", title: "Validate", detail: "non-empty group" },
          { number: "03", title: "Expand", detail: "Command enum" },
        ],
      }
    : {
        index: "01 · macro breakdown",
        title: "Codability Under 100",
        summary:
          "@codable reads the target construct’s stored values, maps each field through Range-authored helpers, and expands a typed coding extension.",
        file: "Core/Macro/Codable.range",
        flow: [
          { number: "01", title: "Collect", detail: "stored properties" },
          { number: "02", title: "Map", detail: "property keys and types" },
          { number: "04", title: "Expand", detail: "encode + decode bodies" },
        ],
      };
  const macroMarker = isCommandGroup
    ? "macro command(): Function"
    : "macro codable(): Construct";
  const declarationSource = sourceFrom(
    isCommandGroup ? commandGroupSource : codableSource,
    macroMarker,
  ).replace(
    /environment\.expand(?=\s*\{)/g,
    "#environment",
  );
  const extensionMarker = "extension #environment.target.Declaration.identity {";
  const expansionSection = sourceBlock(declarationSource, "#environment");
  const macroDeclarationSection = "macro codable(): Construct {";
  const macroSection = sourceBlock(declarationSource, macroDeclarationSection);
  const extensionSection = sourceBlock(declarationSource, extensionMarker);
  const fieldQuerySection = sourceBetween(
    declarationSource,
    "    let fields:",
    "\n\n    #environment",
  );
  const encodeFunctionSection =
    `            function encode<Format>(to encoder: Encoder<Format>): Result<Void, EncodingError> {
                let container: KeyedEncodingContainer<Format>(encoder.keyedContainer())`;
  const encodeFunctionScope = sourceBlock(
    declarationSource,
    "function encode<Format>(to encoder: Encoder<Format>): Result<Void, EncodingError> {",
  );
  const encodeMapSection = `#fields.map { property in
                    switch container.encode(#property.identity, forKey: #property.identity.name) {
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
  const panes = [
    {
      id: "macro",
      label: "Declaration",
      file: breakdown.file,
      source: declarationSource,
    },
  ] as const;

  const codabilityInspections: Inspection[] = [
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
      accent: "#environment.target.Declaration.identity",
      accentDescription:
        "`Declaration.identity` is the target construct’s canonical declared identity. The # prefix splices that compile-time identity into the generated extension.",
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
        "For every stored property, the macro splices `#property.identity` as the value and uses its declared identity name as the coding key.",
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
      token: "#property.identity",
      title: "Identity mention",
      phase: "inside expansion",
      result: "a generated field reference",
      description:
        "Mentions the compile-time Identity value directly in generated syntax, preserving its canonical declaration identity.",
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
  const commandGroupInspections: Inspection[] = [
    {
      id: "command-declaration",
      token: "macro command(): Function {}",
      title: "Declare the registration marker",
      description:
        "@command is a typed Function marker. It records registration in the declaration graph without creating a runtime registry.",
      kind: "section",
      step: 1,
    },
    {
      id: "command-query",
      token: sourceBetween(declarationSource, "    let commands:", "\n\n    if commands.count"),
      title: "Discover registered commands",
      description:
        "The group queries its own declared members and retains only those carrying @command, producing an ordered typed collection.",
      kind: "section",
      step: 2,
    },
    {
      id: "command-validation",
      token: sourceBlock(declarationSource, "if commands.count == 0"),
      title: "Validate the registration set",
      description:
        "An empty group is rejected with a specific diagnostic before the macro emits any generated declarations.",
      kind: "section",
      step: 3,
    },
    {
      id: "command-expansion",
      token: "#environment",
      title: "Expand onto the target",
      description:
        "The macro emits an extension on the command-group construct, keeping the generated command surface owned by its target.",
      kind: "section",
      step: 4,
      scopeToken: sourceBlock(declarationSource, "#environment"),
    },
    {
      id: "command-map",
      token: "#commands.map",
      title: "Generate one case per registration",
      description:
        "Each registered command declaration is mapped to an enum case. The generated Command set stays synchronized with the annotations.",
      kind: "section",
      step: 5,
      scopeToken: sourceBlock(declarationSource, "#commands.map"),
    },
  ];
  const inspections = isCommandGroup
    ? commandGroupInspections
    : codabilityInspections;
  const inspectionByID = new Map(inspections.map((inspection) => [inspection.id, inspection]));
  const chapters = inspections.filter(
    (inspection): inspection is Inspection & { step: ChapterStep } =>
      inspection.step !== undefined,
  );
  const initialInspectionID: InspectionID = isCommandGroup
    ? "command-declaration"
    : "macro-declaration";

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
        `${breakdown.title} chapter ${chapter.step} no longer matches ${breakdown.file}`,
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

  let activeInspectionID = $state<InspectionID | null>(initialInspectionID);
  let stageElement: HTMLDivElement;
  let previewElement: HTMLElement;
  let codeViewportElement: HTMLDivElement;
  let interactionFocused = false;
  let focusState: CodabilityFocusState = "entering";
  let scrollChapterIndex = -1;
  let latestStageScrollProgress = 0;
  let chapterScrollState: ChapterScrollState = {
    phase: "idle",
    chapterIndex: 0,
  };
  let wavedTokens: HTMLElement[] = [];
  let visualScrollProgress = 0;
  let targetVisualScrollProgress = 0;
  let visualScrollFrame = 0;
  let visualScrollLastTime = 0;
  let visualScrollInitialized = false;
  let storyMode = $state(true);
  let stageFocused = $state(false);
  let activePane = $derived(panes[0]);
  let activeInspection = $derived(
    activeInspectionID ? inspectionByID.get(activeInspectionID) : undefined,
  );
  let highlightedLines = $derived(highlightInspectableLines(activePane.source));
  let lineNumbers = $derived(activePane.source.split("\n").map((_, index) => index + 1));

  function selectChapter(chapter: (typeof chapters)[number]) {
    storyMode = true;
    activeInspectionID = chapter.id;
    scrollChapterIndex = chapters.indexOf(chapter);
    chapterScrollState = transitionChapterScroll(chapterScrollState, {
      type: "select",
      chapterIndex: scrollChapterIndex,
      scrollY: typeof window === "undefined" ? 0 : window.scrollY,
      now: typeof performance === "undefined" ? 0 : performance.now(),
    });
    stopVisualScrollProgress();
    visualScrollProgress = (scrollChapterIndex + 0.5) / chapters.length;
    targetVisualScrollProgress = visualScrollProgress;
    visualScrollInitialized = true;
    applyVisualScrollProgress(visualScrollProgress);
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

  function setStoryMode(enabled: boolean) {
    storyMode = enabled;
    if (enabled) {
      scrollChapterIndex = codabilityChapterIndex(
        latestStageScrollProgress,
        chapters.length,
      );
      activeInspectionID =
        chapters[scrollChapterIndex]?.id ?? initialInspectionID;
    } else {
      scrollChapterIndex = -1;
      activeInspectionID = null;
    }
    chapterScrollState = transitionChapterScroll(chapterScrollState, {
      type: "reset",
      chapterIndex: Math.max(0, scrollChapterIndex),
    });
    updateStageFocus();
  }

  function chapterScrollPosition(inspectionID: InspectionID) {
    if (!codeViewportElement) return undefined;
    const lines = Array.from(
      codeViewportElement.querySelectorAll<HTMLElement>(
        `[data-inspection-id="${inspectionID}"]`,
      ),
    );
    if (lines.length === 0) return undefined;
    const viewportBounds = layoutTracker?.locate(codeViewportElement).rect
      ?? codeViewportElement.getBoundingClientRect();
    const firstBounds = layoutTracker?.locate(lines[0]).rect
      ?? lines[0].getBoundingClientRect();
    const lastLine = lines.at(-1);
    const lastBounds = lastLine
      ? layoutTracker?.locate(lastLine).rect ?? lastLine.getBoundingClientRect()
      : firstBounds;
    const highlightedCenter = (firstBounds.top + lastBounds.bottom) / 2;
    const viewportCenter = viewportBounds.top + viewportBounds.height / 2;
    const maximumScroll = Math.max(
      0,
      codeViewportElement.scrollHeight - codeViewportElement.clientHeight,
    );
    return Math.max(
      0,
      Math.min(
        maximumScroll,
        codeViewportElement.scrollTop + highlightedCenter - viewportCenter,
      ),
    );
  }

  function centerChapterInViewport(inspectionID: InspectionID) {
    const scrollPosition = chapterScrollPosition(inspectionID);
    if (scrollPosition !== undefined) {
      codeViewportElement.scrollTop = scrollPosition;
    }
  }

  function scrollCodeBetweenChapters(progress: number) {
    if (!codeViewportElement || chapters.length === 0) return;
    const chapterPosition = Math.max(
      0,
      Math.min(chapters.length - 1, progress * chapters.length - 0.5),
    );
    const fromIndex = Math.floor(chapterPosition);
    const toIndex = Math.min(chapters.length - 1, fromIndex + 1);
    const linearAmount = chapterPosition - fromIndex;
    const amount = linearAmount * linearAmount * (3 - 2 * linearAmount);
    const from = chapterScrollPosition(chapters[fromIndex].id);
    const to = chapterScrollPosition(chapters[toIndex].id);
    if (from === undefined || to === undefined) return;
    codeViewportElement.scrollTop = from + (to - from) * amount;
  }

  function resetCodeToken(glyph: HTMLElement) {
    glyph.style.removeProperty("--token-wave-x");
    glyph.style.removeProperty("--token-wave-y");
    glyph.style.removeProperty("--token-wave-z");
    glyph.style.removeProperty("--token-wave-scale");
    glyph.style.removeProperty("--token-wave-rotate-y");
    glyph.style.removeProperty("--token-wave-brightness");
    glyph.style.removeProperty("--token-wave-saturation");
    glyph.style.removeProperty("--token-wave-shadow-alpha");
  }

  function resetCodeTokenWave() {
    wavedTokens.forEach(resetCodeToken);
    wavedTokens = [];
  }

  function updateCodeTokenWave(progress: number) {
    if (!codeViewportElement || chapters.length === 0) return;
    const chapterPosition = Math.min(
      chapters.length - Number.EPSILON,
      Math.max(0, progress) * chapters.length,
    );
    const chapterIndex = Math.floor(chapterPosition);
    const chapterProgress = chapterPosition - chapterIndex;
    const chapter = chapters[chapterIndex];
    if (!chapter) return;
    const glyphs = Array.from(
      codeViewportElement.querySelectorAll<HTMLElement>(
        `[data-inspection-id="${chapter.id}"] .lineCodeContent .waveGlyph`,
      ),
    );
    const nextTokens = new Set(glyphs);
    wavedTokens.filter((glyph) => !nextTokens.has(glyph)).forEach(resetCodeToken);
    const radius = Math.max(0.115, 1.8 / Math.max(1, glyphs.length));
    glyphs.forEach((glyph, index) => {
      const glyphPosition = glyphs.length <= 1 ? 0.5 : index / (glyphs.length - 1);
      const distance = Math.abs(chapterProgress - glyphPosition);
      const wave = distance >= radius
        ? 0
        : 0.5 + 0.5 * Math.cos(Math.PI * distance / radius);
      glyph.style.setProperty("--token-wave-x", `${(wave * 1.2).toFixed(3)}px`);
      glyph.style.setProperty("--token-wave-y", `${(-wave * 1.2).toFixed(3)}px`);
      glyph.style.setProperty("--token-wave-z", `${(wave * 6).toFixed(3)}px`);
      glyph.style.setProperty("--token-wave-scale", (1 + wave * 0.055).toFixed(4));
      glyph.style.setProperty("--token-wave-rotate-y", `${(wave * 5).toFixed(3)}deg`);
      glyph.style.setProperty("--token-wave-brightness", (1 + wave * 0.2).toFixed(4));
      glyph.style.setProperty("--token-wave-saturation", (1 + wave * 0.04).toFixed(4));
      glyph.style.setProperty("--token-wave-shadow-alpha", (wave * 0.09).toFixed(4));
    });
    wavedTokens = glyphs;
  }

  function applyVisualScrollProgress(progress: number) {
    scrollCodeBetweenChapters(progress);
    updateCodeTokenWave(progress);
  }

  function setVisualScrollProgress(progress: number) {
    targetVisualScrollProgress = Math.max(0, Math.min(1, progress));
    if (!visualScrollInitialized) {
      visualScrollInitialized = true;
      visualScrollProgress = targetVisualScrollProgress;
      applyVisualScrollProgress(visualScrollProgress);
      return;
    }
    if (visualScrollFrame || typeof window === "undefined") return;
    visualScrollLastTime = performance.now();
    const render = (now: number) => {
      const elapsed = Math.min(34, Math.max(1, now - visualScrollLastTime));
      visualScrollLastTime = now;
      const amount = 1 - Math.exp(-elapsed / 72);
      visualScrollProgress += (
        targetVisualScrollProgress - visualScrollProgress
      ) * amount;
      if (Math.abs(targetVisualScrollProgress - visualScrollProgress) < 0.00008) {
        visualScrollProgress = targetVisualScrollProgress;
      }
      applyVisualScrollProgress(visualScrollProgress);
      if (visualScrollProgress === targetVisualScrollProgress) {
        visualScrollFrame = 0;
        return;
      }
      visualScrollFrame = window.requestAnimationFrame(render);
    };
    visualScrollFrame = window.requestAnimationFrame(render);
  }

  function stopVisualScrollProgress() {
    if (visualScrollFrame && typeof window !== "undefined") {
      window.cancelAnimationFrame(visualScrollFrame);
    }
    visualScrollFrame = 0;
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
    const stageBounds = layoutTracker?.query('[data-range-layout="codability-stage"]')?.rect
      ?? stageElement.getBoundingClientRect();
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

    const stageScrollProgress = codabilityStickyScrollProgress({
      stageTop: stageBounds.top,
      stageHeight: stageBounds.height,
      viewportHeight,
    });
    latestStageScrollProgress = stageScrollProgress;
    const rawScrollChapterIndex = codabilityChapterIndex(
      stageScrollProgress,
      chapters.length,
    );
    const nextScrollChapterIndex = rawScrollChapterIndex;
    const desiredVisualScrollProgress = stageScrollProgress;
    const manualState = chapterScrollState.phase === "manual"
      ? chapterScrollState
      : null;
    const canSynchronizeStoryChapter =
      synchronizeStoryChapter &&
      (
        manualState === null ||
        shouldSynchronizeCodabilityChapter({
          manualChapterIndex: manualState.chapterIndex,
          selectionScrollY: manualState.selectionScrollY,
          currentScrollY: window.scrollY,
          elapsedMilliseconds:
            (typeof performance === "undefined" ? 0 : performance.now()) -
            manualState.selectedAt,
        })
      );
    if (manualState && canSynchronizeStoryChapter) {
      chapterScrollState = transitionChapterScroll(chapterScrollState, {
        type: "release-manual",
      });
    }
    if (
      storyMode &&
      canSynchronizeStoryChapter &&
      nextScrollChapterIndex !== scrollChapterIndex
    ) {
      scrollChapterIndex = nextScrollChapterIndex;
      activeInspectionID = chapters[nextScrollChapterIndex]?.id ?? null;
    }
    if (
      chapterScrollState.phase === "idle" &&
      chapterScrollState.chapterIndex !== nextScrollChapterIndex
    ) {
      chapterScrollState = transitionChapterScroll(chapterScrollState, {
        type: "reset",
        chapterIndex: nextScrollChapterIndex,
      });
    }
    if (storyMode && activeInspectionID) {
      if (manualState !== null && !canSynchronizeStoryChapter) {
        centerChapterInViewport(activeInspectionID);
      } else {
        setVisualScrollProgress(desiredVisualScrollProgress);
      }
    } else {
      stopVisualScrollProgress();
      resetCodeTokenWave();
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
    const scheduleScrollUpdate = () => {
      const currentScrollY = window.scrollY;
      if (chapterScrollState.phase === "manual") {
        const releaseManualSelection = shouldSynchronizeCodabilityChapter({
          manualChapterIndex: chapterScrollState.chapterIndex,
          selectionScrollY: chapterScrollState.selectionScrollY,
          currentScrollY,
          elapsedMilliseconds: performance.now() - chapterScrollState.selectedAt,
        });
        if (releaseManualSelection) {
          chapterScrollState = transitionChapterScroll(chapterScrollState, {
            type: "release-manual",
          });
        }
      }
      scheduleUpdate(true);
    };
    const scheduleGeometryUpdate = () => scheduleUpdate(false);

    updateStageFocus(true);
    const stopTrackingStage = layoutTracker?.observe(
      '[data-range-layout="codability-stage"]',
      scheduleScrollUpdate,
    );
    const stopTrackingViewport = layoutTracker?.observe(
      '[data-range-layout="codability-code"]',
      scheduleGeometryUpdate,
    );

    return () => {
      if (frame) window.cancelAnimationFrame(frame);
      stopVisualScrollProgress();
      resetCodeTokenWave();
      chapterScrollState = transitionChapterScroll(chapterScrollState, {
        type: "reset",
        chapterIndex: Math.max(0, scrollChapterIndex),
      });
      stopTrackingStage?.();
      stopTrackingViewport?.();
    };
  });
</script>

<section class="codabilitySheet" aria-labelledby="codability-title">
  {#if showIntro}
    <div class="codabilityIntro">
      <p class="sheetIndex">{breakdown.index}</p>
      <h1 class="codabilityTitle" id="codability-title">{breakdown.title}</h1>
      <p class="sheetSummary">
        {breakdown.summary}
      </p>

      <ol class="codabilityFlow">
        {#each breakdown.flow as step}
          <li>
            <span>{step.number}</span>
            <div><strong>{step.title}</strong><small>{step.detail}</small></div>
          </li>
        {/each}
      </ol>
    </div>
  {/if}

  <div
    class="codabilityStage"
    data-range-layout="codability-stage"
    bind:this={stageElement}
  >
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
        <button
          class="storyModeToggle"
          type="button"
          aria-label="Story mode"
          aria-pressed={storyMode}
          onclick={() => setStoryMode(!storyMode)}
        >
          Story
        </button>
      </div>
    </header>

    <div
      class="codeWorkspace"
      class:inspectionVisible={activeInspection !== undefined}
    >
      <div
        class="codeViewport"
        data-range-layout="codability-code"
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
          <pre class="rangeSource language-range"><code>{#each highlightedLines as line}{#if line.inspectionID}<span
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
    isolation: isolate;
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
    position: relative;
    z-index: 1;
    perspective: 500px;
    opacity: 1;
    filter: blur(0);
  }

  :global(.codePreviewCard .lineCodeContent .waveGlyph) {
    display: inline-block;
    transform:
      translate3d(
        var(--token-wave-x, 0px),
        var(--token-wave-y, 0px),
        var(--token-wave-z, 0px)
      )
      scale(var(--token-wave-scale, 1))
      rotateY(var(--token-wave-rotate-y, 0deg));
    transform-style: preserve-3d;
    filter:
      brightness(var(--token-wave-brightness, 1))
      saturate(var(--token-wave-saturation, 1));
    text-shadow:
      1px 0 0.7px
      oklch(0.75 0.09 305 / var(--token-wave-shadow-alpha, 0));
    transition:
      transform 64ms linear,
      filter 64ms linear,
      text-shadow 64ms linear;
  }

  :global(.codePreviewCard .chapterBadge) {
    position: absolute;
    top: 50%;
    left: -2.25em;
    transform: translateY(-50%) scale(0.82);
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
    opacity: 0.2;
    transition:
      opacity 520ms ease,
      transform 520ms cubic-bezier(0.22, 0.61, 0.36, 1),
      box-shadow 520ms ease;
  }

  :global(.codePreviewCard .chapterActive .chapterBadge) {
    opacity: 1;
    transform: translateY(-50%) scale(1);
    box-shadow: 0 0 0.8em color-mix(in oklch, var(--range), transparent 62%);
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
