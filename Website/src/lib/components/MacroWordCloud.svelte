<script lang="ts">
  import { getContext, onDestroy, onMount } from "svelte";
  import {
    voronoiMapSimulation,
    type VoronoiMapPolygon,
  } from "d3-voronoi-map";
  import { hierarchy, pack } from "d3-hierarchy";
  import {
    RANGE_SOUND_MANAGER_CONTEXT,
    RANGE_RHYTHM_SUBDIVISION_MS,
    type RangeSoundManager,
    type RangeSoundRoute,
  } from "$lib/audio/sound-manager";
  import {
    RANGE_LAYOUT_TRACKER_CONTEXT,
    type RangeLayoutTracker,
  } from "$lib/layout/layout-tracker";

  const layoutTracker = getContext<RangeLayoutTracker | undefined>(
    RANGE_LAYOUT_TRACKER_CONTEXT,
  );

  type Point = [number, number];
  type MacroDatum = { text: string; weight: number };
  type MacroClusterDatum = { text: string; weight: number };
  type MacroCell = {
    text: string;
    weight: number;
    polygon: Point[];
    x: number;
    y: number;
    fontSize: number;
  };
  type MacroFlowRow = {
    cells: MacroCell[];
    loopWidth: number;
    duration: number;
    phase: number;
  };
  type MacroTreeEdge = {
    id: string;
    source: Point;
    target: Point;
    targetWord: string;
    activationWords: readonly string[];
  };
  type VoronoiEdge = {
    id: string;
    owners: [string, string];
  };
  type MacroActivationChain = {
    nodes: string[];
  };
  type MacroChord = {
    oscillators: OscillatorNode[];
    filters: BiquadFilterNode[];
    gains: GainNode[];
    panners: StereoPannerNode[];
    environmentResonators?: BiquadFilterNode[];
    environmentRootFrequency?: number;
    environmentVoiceFrequencies?: number[];
    environmentWave?: {
      output: GainNode;
      fuzz: WaveShaperNode;
      presence: GainNode;
      oscillator: OscillatorNode;
      depth: GainNode;
    };
    environmentBed?: {
      sources: AudioBufferSourceNode[];
      filters: BiquadFilterNode[];
      gains: GainNode[];
      panners: StereoPannerNode[];
    };
  };
  type MacroTail = {
    input: GainNode;
    tone: BiquadFilterNode;
    convolver: ConvolverNode;
    dry: GainNode;
    wet: GainNode;
  };
  type MacroTwinkleGroup = {
    words: readonly string[];
  };
  type MacroVisualEnvelope = {
    word: string;
    attackStart: number;
    attackTimeConstant: number;
    releaseStart?: number;
    releaseLevel?: number;
    releaseTimeConstant: number;
  };
  type MacroGroupPulse = {
    id: number;
    x: number;
    y: number;
    tone: string;
  };
  type MacroPackNode = {
    children?: MacroPackNode[];
    text?: string;
    weight?: number;
  };
  const soundManager = getContext<RangeSoundManager | undefined>(
    RANGE_SOUND_MANAGER_CONTEXT,
  );
  const macroWords = [
    { text: "@equatable", weight: 100 },
    { text: "@codable", weight: 94 },
    { text: "@comparable", weight: 90 },
    { text: "@hashable", weight: 86 },
    { text: "#environment", weight: 88 },
    { text: "@background", weight: 56 },
    { text: "@component", weight: 82 },
    { text: "@app", weight: 74 },
    { text: "@page", weight: 70 },
    { text: "@modifier", weight: 66 },
    { text: "@project", weight: 64 },
    { text: "@package", weight: 62 },
    { text: "@command", weight: 60 },
    { text: "@module", weight: 58 },
    { text: "@commandGroup", weight: 54 },
  ];

  const fieldWidth = 960;
  const fieldHeight = 1_180;
  const fieldInset = 28;
  const macroGraphBottom = 400;
  const macroSemanticGroups = [
    ["@project", "@command", "@commandGroup", "@package", "@module"],
    ["@equatable", "@codable", "@hashable", "@comparable"],
    ["@app", "@page", "@component", "@modifier"],
    ["@background"],
    ["#environment", "@background"],
  ] as const;
  const macroCategoryCells = [
    { x: 30, y: 42, width: 404, height: 204, weight: 370 },
    { x: 500, y: 36, width: 422, height: 150, weight: 226 },
    { x: 545, y: 216, width: 377, height: 108, weight: 178 },
    { x: 32, y: 278, width: 264, height: 56, weight: 121 },
    { x: 320, y: 272, width: 205, height: 58, weight: 88 },
  ] as const;
  const macroTrackGroups = [
    [4],
  ] as const;
  const macroSequenceStartOffset = 6;
  const macroGroupRestTicks = 8;
  // A long binary-log phrase: the distance between entries doubles outward,
  // then returns through a different ordering so it stays directional rather
  // than acquiring a swung pulse.
  const macroBackgroundIntervalPattern = [1, 2, 4, 8, 4, 2, 1, 2, 4, 8, 2, 4] as const;
  const backgroundMacroWords = macroWords
    .map((word) => word.text)
    .filter((word) => word !== "#environment" && word !== "@background");
  // Broken C Dorian arpeggios crawl from C3 through C5. Octave-displaced
  // returns make each group a phrase without leaving the shared scale.
  const macroGroupPatterns = [
    [0, 7, 3, 14, 12, 10, 19, 15, 24],
    [5, 15, 10, 17, 14, 7, 22],
    [12, 19, 15, 24, 21, 17, 10, 22],
    [22, 14, 24, 17, 21, 19, 12],
    [0],
  ] as const;
  const macroRouteLevel = 0.3;
  const environmentResonanceHarmonics = [1, 2, 4, 8] as const;
  const environmentResonanceGains = [3.4, 2.8, 2.2, 1.6] as const;
  const environmentResonanceCents = [-5, 7, -8, 4] as const;
  const environmentDyadCents = [
    [-4, 696],
    [6, 711],
    [-8, 689],
    [3, 704],
  ] as const;
  const environmentDyadTicks = 16;
  const macroTwinkleGroups: readonly MacroTwinkleGroup[] = [
    { words: ["@project", "@command", "@commandGroup", "@package", "@module"] },
    { words: ["@equatable", "@codable", "@hashable", "@comparable"] },
    { words: ["@app", "@page", "@component", "@modifier"] },
    { words: ["@background"] },
    { words: ["#environment", "@background"] },
  ];

  function strategicMacroCells(): MacroCell[] {
    const wordsByText = new Map(macroWords.map((word) => [word.text, word]));
    const anchors = new Map<string, { x: number; y: number; weight: number }>();
    const random = seededRandom(0x4d414352);
    const cells = macroSemanticGroups.flatMap((group, categoryIndex) => {
      const category = macroCategoryCells[categoryIndex];
      if (!category) return [];
      const categoryScale = 0.72 + (category.weight / 370) * 0.5;
      const clusterAngle = random() * Math.PI * 2;
      return group.flatMap((text, wordIndex) => {
        const word = wordsByText.get(text);
        if (!word) return [];
        const anchor = {
          x: category.x + category.width * (0.5 + Math.cos(clusterAngle) * 0.1),
          y: category.y + category.height * (0.5 + Math.sin(clusterAngle) * 0.12),
          weight: category.weight,
        };
        anchors.set(text, anchor);
        const weightedSize = 36 * categoryScale * Math.sqrt(word.weight / 100);
        const fittedSize = (category.width * 0.68) / (word.text.length * 0.61);
        const fontSize = Math.min(54, Math.max(17, Math.min(weightedSize, fittedSize)));
        const angle = (wordIndex / group.length) * Math.PI * 2
          + random() * 0.7 + categoryIndex * 0.53;
        const radius = group.length === 1 ? 0 : 18 + fontSize * (0.72 + random() * 0.72);
        return [{
          text: word.text,
          weight: word.weight,
          polygon: [],
          x: anchor.x + Math.cos(angle) * radius,
          y: anchor.y + Math.sin(angle) * radius,
          fontSize,
        }];
      });
    });
    for (let iteration = 0; iteration < 320; iteration += 1) {
      for (let firstIndex = 0; firstIndex < cells.length; firstIndex += 1) {
        const first = cells[firstIndex];
        for (let secondIndex = firstIndex + 1; secondIndex < cells.length; secondIndex += 1) {
          const second = cells[secondIndex];
          const dx = second.x - first.x;
          const dy = second.y - first.y;
          const overlapX = (first.text.length * first.fontSize * 0.31)
            + (second.text.length * second.fontSize * 0.31) + 14 - Math.abs(dx);
          const overlapY = first.fontSize * 0.66 + second.fontSize * 0.66 + 10 - Math.abs(dy);
          if (overlapX <= 0 || overlapY <= 0) continue;
          if (overlapX < overlapY) {
            const shift = overlapX * 0.52 * (dx === 0 ? 1 : Math.sign(dx));
            first.x -= shift;
            second.x += shift;
          } else {
            const shift = overlapY * 0.52 * (dy === 0 ? 1 : Math.sign(dy));
            first.y -= shift;
            second.y += shift;
          }
        }
      }
      cells.forEach((cell) => {
        const anchor = anchors.get(cell.text);
        if (!anchor) return;
        const pull = 0.011 + (anchor.weight / 370) * 0.009;
        cell.x += (anchor.x - cell.x) * pull;
        cell.y += (anchor.y - cell.y) * pull;
        const halfWidth = cell.text.length * cell.fontSize * 0.31;
        cell.x = Math.max(fieldInset + halfWidth, Math.min(fieldWidth - fieldInset - halfWidth, cell.x));
        cell.y = Math.max(fieldInset + cell.fontSize * 0.68, Math.min(fieldHeight - fieldInset - cell.fontSize * 0.68, cell.y));
      });
    }
    return cells;
  }
  const fieldPolygon: Point[] = [
    [fieldInset, fieldInset],
    [fieldWidth - fieldInset, fieldInset],
    [fieldWidth - fieldInset, fieldHeight - fieldInset],
    [fieldInset, fieldHeight - fieldInset],
  ];
  const macroGraphPolygon: Point[] = [
    [fieldInset, fieldInset],
    [fieldWidth - fieldInset, fieldInset],
    [fieldWidth - fieldInset, macroGraphBottom],
    [fieldInset, macroGraphBottom],
  ];

  function seededRandom(seed: number) {
    let state = seed >>> 0;
    return () => {
      state = (state * 1664525 + 1013904223) >>> 0;
      return state / 4294967296;
    };
  }

  function packedMacroPositions() {
    const wordsByText = new Map(macroWords.map((word) => [word.text, word]));
    const root = hierarchy<MacroPackNode>({
      children: macroSemanticGroups.map((group) => ({
        children: group.map((text) => {
          const word = wordsByText.get(text)!;
          return { text, weight: word.weight };
        }),
      })),
    })
      .sum((node) => node.weight ?? 0)
      .sort((left, right) => (right.value ?? 0) - (left.value ?? 0));
    pack<MacroPackNode>()
      .size([fieldWidth - fieldInset * 2, fieldHeight - fieldInset * 2])
      .padding(24)(root);

    const positions = new Map<string, Point>();
    root.leaves().forEach((leaf) => {
      if (!leaf.data.text) return;
      positions.set(leaf.data.text, [leaf.x + fieldInset, leaf.y + fieldInset]);
    });
    return positions;
  }

  const macroPackedPositions = packedMacroPositions();

  function macroGridPosition(index: number): Point {
    const word = macroWords[index];
    return macroPackedPositions.get(word?.text ?? "")
      ?? [fieldWidth / 2, fieldHeight / 2];
  }

  function distributedMacroPosition(_datum: MacroDatum, index: number): Point {
    return macroGridPosition(index);
  }

  function pointInPolygon([x, y]: Point, polygon: Point[]) {
    let inside = false;
    for (let index = 0, previous = polygon.length - 1; index < polygon.length; previous = index++) {
      const [x1, y1] = polygon[index];
      const [x2, y2] = polygon[previous];
      if ((y1 > y) !== (y2 > y) && x < ((x2 - x1) * (y - y1)) / (y2 - y1) + x1) {
        inside = !inside;
      }
    }
    return inside;
  }

  function distanceToSegment(point: Point, start: Point, end: Point) {
    const dx = end[0] - start[0];
    const dy = end[1] - start[1];
    const lengthSquared = dx * dx + dy * dy;
    const projection = lengthSquared === 0
      ? 0
      : Math.max(0, Math.min(1, ((point[0] - start[0]) * dx + (point[1] - start[1]) * dy) / lengthSquared));
    const x = start[0] + projection * dx;
    const y = start[1] + projection * dy;
    return Math.hypot(point[0] - x, point[1] - y);
  }

  function distanceToEdges(point: Point, polygon: Point[]) {
    return polygon.reduce((distance, edgeStart, index) => {
      const edgeEnd = polygon[(index + 1) % polygon.length];
      return Math.min(distance, distanceToSegment(point, edgeStart, edgeEnd));
    }, Number.POSITIVE_INFINITY);
  }

  function visualCenter(polygon: Point[]) {
    let minX = Math.min(...polygon.map(([x]) => x));
    let maxX = Math.max(...polygon.map(([x]) => x));
    let minY = Math.min(...polygon.map(([, y]) => y));
    let maxY = Math.max(...polygon.map(([, y]) => y));
    let best: Point = [
      polygon.reduce((sum, [x]) => sum + x, 0) / polygon.length,
      polygon.reduce((sum, [, y]) => sum + y, 0) / polygon.length,
    ];
    let bestDistance = distanceToEdges(best, polygon);

    for (let refinement = 0; refinement < 4; refinement += 1) {
      const stepX = (maxX - minX) / 10;
      const stepY = (maxY - minY) / 10;
      for (let xIndex = 0; xIndex <= 10; xIndex += 1) {
        for (let yIndex = 0; yIndex <= 10; yIndex += 1) {
          const candidate: Point = [minX + stepX * xIndex, minY + stepY * yIndex];
          if (!pointInPolygon(candidate, polygon)) continue;
          const distance = distanceToEdges(candidate, polygon);
          if (distance > bestDistance) {
            best = candidate;
            bestDistance = distance;
          }
        }
      }
      minX = best[0] - stepX;
      maxX = best[0] + stepX;
      minY = best[1] - stepY;
      maxY = best[1] + stepY;
    }

    return { point: best, radius: bestDistance };
  }

  function spansThrough([x, y]: Point, polygon: Point[]) {
    const horizontal: number[] = [];
    const vertical: number[] = [];

    polygon.forEach((start, index) => {
      const end = polygon[(index + 1) % polygon.length];
      if ((start[1] <= y && end[1] > y) || (end[1] <= y && start[1] > y)) {
        horizontal.push(start[0] + ((y - start[1]) * (end[0] - start[0])) / (end[1] - start[1]));
      }
      if ((start[0] <= x && end[0] > x) || (end[0] <= x && start[0] > x)) {
        vertical.push(start[1] + ((x - start[0]) * (end[1] - start[1])) / (end[0] - start[0]));
      }
    });

    return {
      width: Math.max(...horizontal) - Math.min(...horizontal),
      height: Math.max(...vertical) - Math.min(...vertical),
    };
  }

  function createSimulation(maxIterationCount: number, convergenceRatio: number) {
    return voronoiMapSimulation<MacroDatum>(macroWords)
      .clip(fieldPolygon)
      .weight((datum) => datum.weight)
      .initialPosition(distributedMacroPosition)
      .convergenceRatio(convergenceRatio)
      .maxIterationCount(maxIterationCount)
      .prng(seededRandom(0x72616e67))
      .stop();
  }

  function cellsFromPolygons(polygons: VoronoiMapPolygon<MacroDatum>[]) {
    return polygons.map((weightedPolygon): MacroCell => {
      const polygon = [...weightedPolygon] as Point[];
      const { point } = visualCenter(polygon);
      const datum = weightedPolygon.site.originalObject.data.originalData;
      const text = datum.text;
      const spans = spansThrough(point, polygon);
      const fittedSize = Math.min(
        64,
        (spans.width * 0.82) / (text.length * 0.61),
        spans.height * 0.62,
      );
      return {
        text,
        weight: datum.weight,
        polygon,
        x: point[0],
        y: point[1],
        fontSize: Math.max(9, fittedSize),
      };
    });
  }

  function makeSettledCells() {
    const simulation = createSimulation(140, 0.00005);
    for (let iteration = 0; iteration < 90; iteration += 1) simulation.tick();
    return cellsFromPolygons(simulation.state().polygons);
  }

  function makeInternalEdges(voronoiCells: MacroCell[]) {
    const edges = new Map<
      string,
      { start: Point; end: Point; owners: string[] }
    >();
    const pointKey = ([x, y]: Point) => `${x.toFixed(2)},${y.toFixed(2)}`;

    voronoiCells.forEach((cell) => {
      cell.polygon.forEach((start, index) => {
        const end = cell.polygon[(index + 1) % cell.polygon.length];
        const startKey = pointKey(start);
        const endKey = pointKey(end);
        const key = startKey < endKey
          ? `${startKey}|${endKey}`
          : `${endKey}|${startKey}`;
        const existing = edges.get(key);
        if (existing) existing.owners.push(cell.text);
        else edges.set(key, { start, end, owners: [cell.text] });
      });
    });

    return [...edges.values()]
      .filter((edge) => edge.owners.length > 1)
      .map((edge) => {
        const owners = [...new Set(edge.owners)].sort();
        return {
          id: owners.join("|"),
          owners: [owners[0]!, owners[1]!] as [string, string],
        };
      });
  }

  function smoothingAmount(elapsed: number) {
    return 1 - Math.exp(-elapsed / 260);
  }

  function interpolateCells(
    currentCells: MacroCell[],
    targetCells: MacroCell[],
    amount: number,
  ) {
    const currentByText = new Map(currentCells.map((cell) => [cell.text, cell]));
    return targetCells.map((target) => {
      const current = currentByText.get(target.text) ?? target;
      return {
        ...target,
        x: current.x + (target.x - current.x) * amount,
        y: current.y + (target.y - current.y) * amount,
        fontSize: current.fontSize
          + (target.fontSize - current.fontSize) * amount,
      };
    });
  }

  function pullNodesTowardGrid(polygons: VoronoiMapPolygon<MacroDatum>[]) {
    polygons.forEach((polygon) => {
      const node = polygon.site.originalObject;
      const index = macroWords.findIndex(
        (word) => word.text === node.data.originalData.text,
      );
      const [x, y] = macroGridPosition(Math.max(0, index));
      const weightRatio = node.data.originalData.weight / macroWords[0].weight;
      const gridForce = 0.004 + weightRatio * 0.004;
      node.x += (x - node.x) * gridForce;
      node.y += (y - node.y) * gridForce;
    });
  }

  function shortestMacroPath(
    edges: VoronoiEdge[],
    start: string,
    end: string,
  ) {
    const adjacent = new Map<string, string[]>();
    for (const edge of edges) {
      const [first, second] = edge.owners;
      adjacent.set(first, [...(adjacent.get(first) ?? []), second]);
      adjacent.set(second, [...(adjacent.get(second) ?? []), first]);
    }

    const previous = new Map<string, string | undefined>();
    const queue = [start];
    previous.set(start, undefined);

    for (let index = 0; index < queue.length; index += 1) {
      const current = queue[index];
      if (current === end) break;
      for (const next of adjacent.get(current) ?? []) {
        if (previous.has(next)) continue;
        previous.set(next, current);
        queue.push(next);
      }
    }

    if (!previous.has(end)) return [start];
    const path: string[] = [];
    for (let current: string | undefined = end; current !== undefined; current = previous.get(current)) {
      path.push(current);
    }
    return path.reverse();
  }

  function macroChainFromWaypoints(edges: VoronoiEdge[], waypoints: string[]) {
    const nodes = waypoints.slice(0, 1);
    for (let index = 1; index < waypoints.length; index += 1) {
      const from = nodes.at(-1) ?? waypoints[index - 1];
      nodes.push(...shortestMacroPath(edges, from, waypoints[index]).slice(1));
    }
    return {
      nodes,
    } satisfies MacroActivationChain;
  }

  function makeClusteredMacroCells() {
    const wordsByText = new Map(macroWords.map((word) => [word.text, word]));
    const graphGroups = [
      ...macroSemanticGroups.slice(0, 3),
      ["@background"] as const,
    ];
    const clusters: MacroClusterDatum[] = graphGroups.map((group, index) => ({
      text: `cluster-${index}`,
      weight: group.reduce(
        (sum, text) => sum + (wordsByText.get(text)?.weight ?? 0),
        0,
      ),
    }));
    const clusterAnchors: Point[] = [
      [225, 125],
      [735, 120],
      [735, 305],
      [225, 305],
      [fieldWidth / 2, 220],
    ];
    const clusterSimulation = voronoiMapSimulation<MacroClusterDatum>(clusters)
      .clip(macroGraphPolygon)
      .weight((cluster) => cluster.weight)
      .initialPosition((_cluster, index) => clusterAnchors[index] ?? [fieldWidth / 2, fieldHeight / 2])
      .convergenceRatio(0.00008)
      .maxIterationCount(180)
      .prng(seededRandom(0x43454c4c))
      .stop();
    for (let iteration = 0; iteration < 130; iteration += 1) {
      clusterSimulation.tick();
    }

    const graphCells = clusterSimulation.state().polygons.flatMap((clusterPolygon) => {
      const clusterDatum = clusterPolygon.site.originalObject.data.originalData;
      const groupIndex = Number(clusterDatum.text.replace("cluster-", ""));
      const group = graphGroups[groupIndex];
      if (!group) return [];
      const polygon = [...clusterPolygon] as Point[];
      const clusterCenter = visualCenter(polygon).point;

      if (group.length === 1) {
        const word = wordsByText.get(group[0]);
        if (!word) return [];
        const spans = spansThrough(clusterCenter, polygon);
        const fontSize = Math.max(
          18,
          Math.min(
            48,
            18 + word.weight * 0.24,
            (spans.width * 0.72) / (word.text.length * 0.61),
            spans.height * 0.5,
          ),
        );
        return [{
          text: word.text,
          weight: word.weight,
          polygon,
          x: word.text === "#environment" ? fieldWidth / 2 : clusterCenter[0],
          y: word.text === "#environment" ? fieldHeight / 2 : clusterCenter[1],
          fontSize,
        }];
      }

      const groupWords = group.flatMap((text) => {
        const word = wordsByText.get(text);
        return word ? [word] : [];
      });
      const innerSimulation = voronoiMapSimulation<MacroDatum>(groupWords)
        .clip(polygon)
        .weight((word) => word.weight)
        .convergenceRatio(0.00006)
        .maxIterationCount(160)
        .prng(seededRandom(0x4d414352 + groupIndex * 0x101))
        .stop();
      for (let iteration = 0; iteration < 110; iteration += 1) {
        innerSimulation.tick();
      }

      return cellsFromPolygons(innerSimulation.state().polygons).map((cell) => ({
        ...cell,
        // Pull each inner cell slightly toward its family centroid. The outer
        // Voronoi still determines territory, while this creates readable air
        // between neighboring semantic families.
        x: clusterCenter[0] + (cell.x - clusterCenter[0]) * 0.8,
        y: clusterCenter[1] + (cell.y - clusterCenter[1]) * 0.8,
        fontSize: Math.max(
          16,
          Math.min(48, cell.fontSize, 18 + cell.weight * 0.24),
        ),
      }));
    });

    const environment = wordsByText.get("#environment");
    return [
      ...graphCells,
      ...(environment ? [{
        text: environment.text,
        weight: environment.weight,
        polygon: [],
        x: fieldWidth / 2,
        y: 505,
        fontSize: 46,
      }] : []),
    ];
  }

  function makeMacroFlowRows(): MacroFlowRow[] {
    const wordsByText = new Map(macroWords.map((word) => [word.text, word]));
    const rows = [
      ["@project", "@command", "@commandGroup", "@package", "@module"],
      ["@equatable", "@codable", "@hashable", "@comparable"],
      ["@app", "@page", "@component", "@modifier"],
    ] as const;
    const rowY = [105, 255, 405] as const;
    const durations = [82, 96, 88] as const;
    const phases = [19, 51, 7] as const;
    const fontSize = 32;
    const characterWidth = fontSize * 0.59;

    return rows.map((row, rowIndex) => {
      const wordsWidth = row.reduce(
        (width, text) => width + text.length * characterWidth,
        0,
      );
      const gap = Math.max(76, (1_180 - wordsWidth) / row.length);
      const loopWidth = wordsWidth + gap * row.length;
      let cursor = gap / 2;
      const rowCells = row.flatMap((text) => {
        const word = wordsByText.get(text);
        if (!word) return [];
        const width = text.length * characterWidth;
        const cell: MacroCell = {
          text,
          weight: word.weight,
          polygon: [],
          x: cursor + width / 2,
          y: rowY[rowIndex],
          fontSize,
        };
        cursor += width + gap;
        return [cell];
      });
      return {
        cells: rowCells,
        loopWidth,
        duration: durations[rowIndex],
        phase: phases[rowIndex],
      };
    });
  }

  function makeEnvironmentCell(): MacroCell {
    const environment = macroWords.find((word) => word.text === "#environment")!;
    return {
      text: environment.text,
      weight: environment.weight,
      polygon: [],
      x: fieldWidth / 2,
      y: 1_075,
      fontSize: 40,
    };
  }

  function makeMacroTreeLayout() {
    const wordsByText = new Map(macroWords.map((word) => [word.text, word]));
    const groupWeights = macroSemanticGroups.map((group) =>
      group.reduce((sum, text) => sum + (wordsByText.get(text)?.weight ?? 0), 0)
    );
    const visualWeights = groupWeights.map((weight) => Math.sqrt(weight));
    const totalVisualWeight = visualWeights.reduce((sum, weight) => sum + weight, 0);
    const usableWidth = fieldWidth - fieldInset * 2;
    const random = seededRandom(0x74726565);
    const cells: MacroCell[] = [];
    const edges: MacroTreeEdge[] = [];
    const treeRoot: Point = [fieldWidth / 2, 28];
    let laneStart = fieldInset;

    macroSemanticGroups.forEach((group, groupIndex) => {
      const laneWidth = usableWidth * (visualWeights[groupIndex] / totalVisualWeight);
      const laneCenter = laneStart + laneWidth / 2;
      const groupWeight = groupWeights[groupIndex];
      const rootText = group[0];
      const rootWord = wordsByText.get(rootText);
      if (!rootWord) return;

      // Larger semantic families sit closer to the meta root. The small,
      // deterministic offsets keep the tree authored rather than mechanical.
      const rootY = 116 + (1 - groupWeight / groupWeights[0]) * 54
        + (random() - 0.5) * 12;
      const rootX = laneCenter + (random() - 0.5) * Math.min(24, laneWidth * 0.12);
      const rootCell: MacroCell = {
        text: rootText,
        weight: rootWord.weight,
        polygon: [],
        x: rootX,
        y: rootY,
        fontSize: Math.min(42, 18 + rootWord.weight * 0.24),
      };
      cells.push(rootCell);
      edges.push({
        id: `root-${rootText}`,
        source: treeRoot,
        target: [rootX, rootY - rootCell.fontSize * 0.58],
        targetWord: rootText,
        activationWords: group,
      });

      const children = group.slice(1);
      children.forEach((text, childIndex) => {
        const word = wordsByText.get(text);
        if (!word) return;
        const side = childIndex % 2 === 0 ? -1 : 1;
        const row = Math.floor(childIndex / 2);
        const spread = Math.min(laneWidth * 0.27, 52 + row * 13);
        const weightDistance = (1 - word.weight / 100) * 72;
        const childX = laneCenter + side * spread + (random() - 0.5) * 18;
        const childY = 278 + row * 104 + weightDistance + (random() - 0.5) * 18;
        const weightedSize = 15 + word.weight * 0.2;
        const fittedSize = (laneWidth * 0.88) / (text.length * 0.59);
        const fontSize = Math.max(17, Math.min(35, weightedSize, fittedSize));
        cells.push({ text, weight: word.weight, polygon: [], x: childX, y: childY, fontSize });
        edges.push({
          id: `${rootText}-${text}`,
          source: [rootX, rootY + rootCell.fontSize * 0.58],
          target: [childX, childY - fontSize * 0.62],
          targetWord: text,
          activationWords: [text],
        });
      });
      laneStart += laneWidth;
    });

    return { cells, edges, treeRoot };
  }

  function macroTreePath(edge: MacroTreeEdge) {
    const middleY = edge.source[1] + (edge.target[1] - edge.source[1]) * 0.5;
    return `M ${edge.source[0]} ${edge.source[1]} C ${edge.source[0]} ${middleY}, ${edge.target[0]} ${middleY}, ${edge.target[0]} ${edge.target[1]}`;
  }

  function resolveMacroTextCollisions(sourceCells: MacroCell[]) {
    const cells = sourceCells.map((cell) => ({ ...cell }));
    const targets = new Map(cells.map((cell) => [cell.text, [cell.x, cell.y] as Point]));
    const fixed = new Set(["#environment"]);
    const halfWidth = (cell: MacroCell) =>
      cell.text.length * cell.fontSize * 0.31
      + (cell.text === "#environment" ? 68 : 10);
    const halfHeight = (cell: MacroCell) =>
      cell.fontSize * 0.62
      + (cell.text === "#environment" ? 58 : 8);

    for (let iteration = 0; iteration < 420; iteration += 1) {
      for (let firstIndex = 0; firstIndex < cells.length; firstIndex += 1) {
        const first = cells[firstIndex];
        for (let secondIndex = firstIndex + 1; secondIndex < cells.length; secondIndex += 1) {
          const second = cells[secondIndex];
          const dx = second.x - first.x;
          const dy = second.y - first.y;
          const overlapX = halfWidth(first) + halfWidth(second) - Math.abs(dx);
          const overlapY = halfHeight(first) + halfHeight(second) - Math.abs(dy);
          if (overlapX <= 0 || overlapY <= 0) continue;

          const firstFixed = fixed.has(first.text);
          const secondFixed = fixed.has(second.text);
          if (firstFixed && secondFixed) continue;
          const firstShare = firstFixed ? 0 : secondFixed ? 1 : 0.5;
          const secondShare = secondFixed ? 0 : firstFixed ? 1 : 0.5;
          if (overlapX < overlapY) {
            const direction = dx === 0 ? (firstIndex % 2 === 0 ? 1 : -1) : Math.sign(dx);
            const separation = overlapX + 1.5;
            first.x -= direction * separation * firstShare;
            second.x += direction * separation * secondShare;
          } else {
            const direction = dy === 0 ? (firstIndex % 2 === 0 ? 1 : -1) : Math.sign(dy);
            const separation = overlapY + 1.5;
            first.y -= direction * separation * firstShare;
            second.y += direction * separation * secondShare;
          }
        }
      }

      cells.forEach((cell) => {
        const target = targets.get(cell.text);
        if (!fixed.has(cell.text) && target) {
          cell.x += (target[0] - cell.x) * 0.004;
          cell.y += (target[1] - cell.y) * 0.004;
        }
        const horizontalInset = fieldInset + halfWidth(cell);
        const verticalInset = fieldInset + halfHeight(cell);
        cell.x = Math.max(horizontalInset, Math.min(fieldWidth - horizontalInset, cell.x));
        cell.y = Math.max(verticalInset, Math.min(fieldHeight - verticalInset, cell.y));
      });
    }
    return cells;
  }

  const macroFlowRows = makeMacroFlowRows();
  const environmentCell = makeEnvironmentCell();
  const cells = [...macroFlowRows.flatMap((row) => row.cells), environmentCell];

  function macroPanForWord(word: string | undefined, fallback = 0) {
    const cell = cells.find((candidate) => candidate.text === word);
    if (!cell) return fallback;
    return Math.max(
      -0.92,
      Math.min(0.92, ((cell.x / fieldWidth) * 2 - 1) * 0.96),
    );
  }
  let transportRunning = $state(false);
  let macroTransportGeneration = 0;
  let macroCloudElement: HTMLElement;
  let macroFieldElement: SVGGraphicsElement;
  let environmentKeyElement: SVGGraphicsElement;
  let macroAudioRoute: RangeSoundRoute | undefined;
  let macroTail: MacroTail | undefined;
  let environmentTail: MacroTail | undefined;
  let backgroundTail: MacroTail | undefined;
  let macroSpaceInput: GainNode | undefined;
  let macroSpaceFilter: BiquadFilterNode | undefined;
  let macroSpaceCompressor: DynamicsCompressorNode | undefined;
  let macroSpaceOutput: GainNode | undefined;
  let macroRouteOpen = false;
  let macroFieldViewportPresence = 0;
  let activeMacroWords = $state<[string | undefined, string | undefined]>([undefined, undefined]);
  let macroVisualEnvelopes = $state<[MacroVisualEnvelope | undefined, MacroVisualEnvelope | undefined]>([undefined, undefined]);
  let backgroundVisualEnvelopes = $state<MacroVisualEnvelope[]>([]);
  let macroVisualTime = $state(0);
  let macroGroupPulse = $state<MacroGroupPulse | undefined>();
  let macroGroupPulseId = 0;
  let macroChords: [MacroChord | undefined, MacroChord | undefined] = [undefined, undefined];
  let macroChordActive = $state(false);
  let environmentWindowPresence = $state(0);
  let macroTrackLastGroups = [undefined] as (number | undefined)[];
  let macroClockwiseGroupPosition = 0;
  const macroClockwiseDirections = [1];
  let macroSequenceTick = 0;
  let macroNextNoteTick = macroSequenceStartOffset;
  let macroNextSupportTick = macroSequenceStartOffset;
  let macroHatRollIndex = 0;
  let macroBackgroundIntervalIndex = 0;
  let macroSelectionRandomState = 0x4d414352;
  let macroReleaseTick = -1;
  let macroClockInitialized = false;
  let macroGroupNoteIndex = 0;
  let macroPatternDirection = 1;
  let environmentDyadIndex = 0;
  let environmentNextDyadTick = -1;
  let macroSidechainPulseId = 0;

  function macroTone(text: string) {
    if (text === "#environment") return "syntaxSplice";
    return "syntaxMacro";
  }

  function macroCellActivation(text: string) {
    return [...macroVisualEnvelopes, ...backgroundVisualEnvelopes].reduce((strongest, envelope) => {
      if (!envelope || envelope.word !== text) return strongest;
      const elapsedAttack = Math.max(0, macroVisualTime - envelope.attackStart);
      const attackLevel = 1 - Math.exp(-elapsedAttack / envelope.attackTimeConstant);
      if (envelope.releaseStart === undefined || macroVisualTime < envelope.releaseStart) {
        return Math.max(strongest, attackLevel);
      }
      const releaseLevel = envelope.releaseLevel ?? attackLevel;
      const elapsedRelease = macroVisualTime - envelope.releaseStart;
      return Math.max(
        strongest,
        releaseLevel * Math.exp(-elapsedRelease / envelope.releaseTimeConstant),
      );
    }, 0);
  }

  function macroCellHitScale(text: string, activation: number) {
    const latestEnvelope = [...macroVisualEnvelopes, ...backgroundVisualEnvelopes]
      .filter((envelope): envelope is MacroVisualEnvelope => envelope?.word === text)
      .sort((first, second) => second.attackStart - first.attackStart)[0];
    if (!latestEnvelope || activation <= 0.001) return 1;

    const elapsed = Math.max(0, macroVisualTime - latestEnvelope.attackStart);
    const rebound = -Math.sin(Math.min(elapsed, 0.9) * 18) * 0.018
      * Math.exp(-elapsed / 0.34);
    return Math.max(0.925, Math.min(1.015, 1 - activation * 0.045 + rebound));
  }

  function macroBranchActivation(edge: MacroTreeEdge) {
    return edge.activationWords.reduce(
      (strongest, word) => Math.max(strongest, macroCellActivation(word)),
      0,
    );
  }

  function createMacroTail(
    audio: AudioContext,
    destination: AudioNode,
    {
      duration = 3.6,
      decay = 3.4,
      cutoff = 1_450,
      dryLevel = 1,
      wetLevel = 0.28,
      impulseLevel = 1,
    }: {
      duration?: number;
      decay?: number;
      cutoff?: number;
      dryLevel?: number;
      wetLevel?: number;
      impulseLevel?: number;
    } = {},
  ) {
    const input = audio.createGain();
    const tone = audio.createBiquadFilter();
    const convolver = audio.createConvolver();
    const dry = audio.createGain();
    const wet = audio.createGain();
    const frameCount = Math.floor(audio.sampleRate * duration);
    const impulse = audio.createBuffer(2, frameCount, audio.sampleRate);
    let seed = 0x52414e47;
    const random = () => {
      seed = (seed * 1664525 + 1013904223) >>> 0;
      return seed / 4294967296;
    };
    for (let channel = 0; channel < impulse.numberOfChannels; channel += 1) {
      const samples = impulse.getChannelData(channel);
      for (let index = 0; index < samples.length; index += 1) {
        const progress = index / samples.length;
        samples[index] = (random() * 2 - 1)
          * Math.pow(1 - progress, decay)
          * impulseLevel;
      }
    }
    tone.type = "lowpass";
    tone.frequency.value = cutoff;
    tone.Q.value = 0.55;
    tone.channelCount = 1;
    tone.channelCountMode = "explicit";
    tone.channelInterpretation = "speakers";
    convolver.buffer = impulse;
    dry.gain.value = dryLevel;
    wet.gain.value = wetLevel;
    input.connect(dry).connect(destination);
    input.connect(tone).connect(convolver).connect(wet).connect(destination);
    return { input, tone, convolver, dry, wet } satisfies MacroTail;
  }

  function createAirNoiseBuffer(audio: AudioContext, seed: number) {
    const duration = 5.4;
    const buffer = audio.createBuffer(
      1,
      Math.floor(audio.sampleRate * duration),
      audio.sampleRate,
    );
    const samples = buffer.getChannelData(0);
    let randomState = seed >>> 0;
    let breath = 0;
    for (let index = 0; index < samples.length; index += 1) {
      randomState = (randomState * 1664525 + 1013904223) >>> 0;
      const white = (randomState / 4294967296) * 2 - 1;
      breath = breath * 0.94 + white * 0.06;
      samples[index] = white * 0.18 + breath * 0.82;
    }
    return buffer;
  }

  async function ensureMacroAudioRoute() {
    const manager = soundManager;
    if (!manager?.isEnabled()) return;
    const audio = await manager.resume();
    if (!audio) return;
    if (!macroAudioRoute) {
      macroAudioRoute = manager.register("range-macros", 0.0001);
      macroSpaceInput = audio.createGain();
      macroSpaceFilter = audio.createBiquadFilter();
      macroSpaceCompressor = audio.createDynamicsCompressor();
      macroSpaceOutput = audio.createGain();
      macroSpaceFilter.type = "lowpass";
      macroSpaceFilter.frequency.value = 14_000;
      macroSpaceFilter.Q.value = 0.32;
      macroSpaceCompressor.threshold.value = -14;
      macroSpaceCompressor.knee.value = 18;
      macroSpaceCompressor.ratio.value = 1.4;
      macroSpaceCompressor.attack.value = 0.035;
      macroSpaceCompressor.release.value = 0.72;
      macroSpaceOutput.gain.value = 1;
      macroSpaceInput
        .connect(macroSpaceFilter)
        .connect(macroSpaceCompressor)
        .connect(macroSpaceOutput)
        .connect(macroAudioRoute.input);
      macroTail = createMacroTail(audio, macroSpaceInput);
      environmentTail = createMacroTail(audio, macroSpaceInput, {
        duration: 9.6,
        decay: 1.42,
        cutoff: 1_800,
        dryLevel: 0.08,
        wetLevel: 0.72,
        impulseLevel: 0.22,
      });
      backgroundTail = createMacroTail(audio, macroSpaceInput, {
        duration: 2.2,
        decay: 3.8,
        cutoff: 9_000,
        dryLevel: 1,
        wetLevel: 0.22,
        impulseLevel: 0.16,
      });
    }
    if (macroAudioRoute && !macroRouteOpen) {
      const now = audio.currentTime;
      const routeGain = macroAudioRoute.input.gain;
      routeGain.cancelScheduledValues(now);
      routeGain.setValueAtTime(Math.max(0.0001, routeGain.value), now);
      macroRouteOpen = true;
    }
  }

  function releaseMacroVisualEnvelopes(now: number, releaseTimeConstant: number) {
    macroVisualEnvelopes = macroVisualEnvelopes.map((envelope) => {
      if (!envelope || envelope.releaseStart !== undefined) return envelope;
      const elapsedAttack = Math.max(0, now - envelope.attackStart);
      const releaseLevel = 1 - Math.exp(-elapsedAttack / envelope.attackTimeConstant);
      return {
        ...envelope,
        releaseStart: now,
        releaseLevel,
        releaseTimeConstant,
      };
    }) as [MacroVisualEnvelope | undefined, MacroVisualEnvelope | undefined];
  }

  function releaseMacroVisualEnvelope(
    trackIndex: number,
    now: number,
    releaseTimeConstant: number,
  ) {
    const envelope = macroVisualEnvelopes[trackIndex];
    if (!envelope || envelope.releaseStart !== undefined) return;
    const elapsedAttack = Math.max(0, now - envelope.attackStart);
    const releaseLevel = 1 - Math.exp(-elapsedAttack / envelope.attackTimeConstant);
    const next = [...macroVisualEnvelopes] as [MacroVisualEnvelope | undefined, MacroVisualEnvelope | undefined];
    next[trackIndex] = {
      ...envelope,
      releaseStart: now,
      releaseLevel,
      releaseTimeConstant,
    };
    macroVisualEnvelopes = next;
  }

  function stopMacroTracks() {
    macroSidechainPulseId += 1;
    soundManager?.setLayerPresence?.("macros", 0);
    const now = macroAudioRoute?.audioContext.currentTime ?? 0;
    if (macroAudioRoute) {
      const routeGain = macroAudioRoute.input.gain;
      routeGain.cancelScheduledValues(now);
      routeGain.setTargetAtTime(0.0001, now, 1.4);
      macroRouteOpen = false;
    }
    macroChords.forEach((chord) => {
      if (!chord) return;
      const environmentRelease = chord.environmentWave !== undefined;
      const releaseTime = environmentRelease ? 1.15 : 0.08;
      const stopTime = environmentRelease ? now + 3.4 : now + 0.3;
      chord.gains.forEach((gain) => {
        gain.gain.cancelScheduledValues(now);
        gain.gain.setTargetAtTime(0.0001, now, releaseTime);
      });
      chord.environmentBed?.gains.forEach((gain) => {
        gain.gain.cancelScheduledValues(now);
        gain.gain.setTargetAtTime(0.0001, now, 1.2);
      });
      chord.oscillators.forEach((oscillator) => oscillator.stop(stopTime));
      chord.environmentBed?.sources.forEach((source) => source.stop(stopTime));
      if (chord.environmentWave) {
        const { oscillator, depth, output, fuzz, presence } = chord.environmentWave;
        depth.gain.cancelScheduledValues(now);
        depth.gain.setTargetAtTime(0, now, 0.9);
        output.gain.cancelScheduledValues(now);
        output.gain.setTargetAtTime(0.0001, now, 1.15);
        presence.gain.cancelScheduledValues(now);
        presence.gain.setTargetAtTime(0.0001, now, 1.15);
        oscillator.stop(stopTime);
        oscillator.addEventListener("ended", () => {
          depth.disconnect();
          output.disconnect();
          fuzz.disconnect();
          presence.disconnect();
          chord.filters.forEach((filter) => filter.disconnect());
          chord.environmentResonators?.forEach((filter) => filter.disconnect());
          chord.panners.forEach((panner) => panner.disconnect());
          chord.environmentBed?.filters.forEach((filter) => filter.disconnect());
          chord.environmentBed?.panners.forEach((panner) => panner.disconnect());
        }, { once: true });
      } else {
        chord.filters.forEach((filter) => filter.disconnect());
        chord.panners.forEach((panner) => panner.disconnect());
      }
    });
    releaseMacroVisualEnvelopes(now, 0.08);
    macroChords = [undefined, undefined];
    macroChordActive = false;
    activeMacroWords = [undefined, undefined];
    backgroundVisualEnvelopes = [];
    macroGroupPulse = undefined;
  }

  function releaseMacroNote(trackIndex: number) {
    const now = macroAudioRoute?.audioContext.currentTime ?? 0;
    const activeWord = activeMacroWords[trackIndex];
    const releaseTimeConstant = activeWord === "#environment"
      ? 2.4
      : activeWord === "@background"
        ? 0.24
        : 0.85;
    macroChords[trackIndex]?.gains.forEach((gain) => {
      gain.gain.cancelScheduledValues(now);
      gain.gain.setTargetAtTime(0.0001, now, releaseTimeConstant);
    });
    macroChords[trackIndex]?.environmentBed?.gains.forEach((gain) => {
      gain.gain.cancelScheduledValues(now);
      gain.gain.setTargetAtTime(0.0001, now, 2.8);
    });
    releaseMacroVisualEnvelope(trackIndex, now, releaseTimeConstant);
    const nextActiveWords = [...activeMacroWords] as [string | undefined, string | undefined];
    nextActiveWords[trackIndex] = undefined;
    activeMacroWords = nextActiveWords;
    macroChordActive = nextActiveWords.some(Boolean);
  }

  function macroAttackTimeConstant(word: string, holdSeconds: number) {
    if (word === "#environment") return 1.05;
    if (word === "@background") return 0.022;
    return Math.min(0.12, holdSeconds * 0.3);
  }

  function shiftEnvironmentResonanceBand(
    centerProximity: number,
    now: number,
  ) {
    const harmonicShift = Math.max(0, Math.min(1, centerProximity));
    const centerRatio = Math.pow(2, (harmonicShift * 96) / 1_200);
    macroChords.forEach((chord) => {
      const root = chord?.environmentRootFrequency;
      if (!chord?.environmentResonators || !root) return;
      chord.oscillators.forEach((_, voiceIndex) => {
        environmentResonanceHarmonics.forEach((harmonic, harmonicIndex) => {
          const resonatorIndex =
            voiceIndex * environmentResonanceHarmonics.length + harmonicIndex;
          const resonator = chord.environmentResonators?.[resonatorIndex];
          if (!resonator) return;
          resonator.frequency.cancelScheduledValues(now);
          resonator.frequency.setTargetAtTime(
            root
              * harmonic
              * centerRatio
              * Math.pow(
                2,
                (environmentResonanceCents[harmonicIndex] ?? 0) / 1_200,
              ),
            now,
            0.38 + harmonicIndex * 0.07,
          );
        });
      });
    });
  }

  function selectEnvironmentDyad(dyadIndex: number, now: number) {
    const chord = macroChords[0];
    const root = chord?.environmentRootFrequency;
    const dyad = environmentDyadCents[dyadIndex % environmentDyadCents.length];
    if (!chord || !root || !dyad) return;
    chord.environmentVoiceFrequencies ??= [];
    chord.oscillators.forEach((oscillator, voiceIndex) => {
      const cents = dyad[voiceIndex] ?? dyad[dyad.length - 1] ?? 0;
      const frequency = root * Math.pow(2, cents / 1_200);
      chord.environmentVoiceFrequencies![voiceIndex] = frequency;
      oscillator.frequency.cancelScheduledValues(now);
      oscillator.frequency.setTargetAtTime(frequency, now, 0.92);
    });
  }

  function sustainMacroChord(
    trackIndex: number,
    noteStep: number,
    intensity: number,
    holdSeconds: number,
    word: string,
    onsetTime?: number,
  ) {
    if (!soundManager?.isEnabled() || !macroAudioRoute) return false;
    const audio = macroAudioRoute.audioContext;
    const now = Math.max(audio.currentTime + 0.008, onsetTime ?? 0);
    const macroRoot = 261.63; // C4: a lighter lead register.
    const environmentHit = word === "#environment";
    const backgroundSupport = word === "@background";
    const wordPan = macroPanForWord(word);
    if (!macroChords[trackIndex]) {
      const oscillators: OscillatorNode[] = [];
      const filters: BiquadFilterNode[] = [];
      const gains: GainNode[] = [];
      const panners: StereoPannerNode[] = [];
      const environmentResonators: BiquadFilterNode[] = [];
      let environmentWave: MacroChord["environmentWave"];
      if (environmentHit) {
        const output = audio.createGain();
        const fuzz = audio.createWaveShaper();
        const presence = audio.createGain();
        const oscillator = audio.createOscillator();
        const depth = audio.createGain();
        output.gain.value = 0.7;
        const fuzzCurve = new Float32Array(1_024);
        for (let index = 0; index < fuzzCurve.length; index += 1) {
          const input = (index / (fuzzCurve.length - 1)) * 2 - 1;
          fuzzCurve[index] = Math.tanh(input * 2.1) / Math.tanh(2.1);
        }
        fuzz.curve = fuzzCurve;
        fuzz.oversample = "4x";
        presence.gain.value = 0.0001;
        oscillator.type = "sine";
        oscillator.frequency.value = 0.068;
        depth.gain.value = 0.18;
        oscillator.connect(depth).connect(output.gain);
        output
          .connect(fuzz)
          .connect(presence)
          .connect(environmentTail?.input ?? macroAudioRoute.input);
        oscillator.start(now);
        environmentWave = { output, fuzz, presence, oscillator, depth };

      }
      for (let voiceIndex = 0; voiceIndex < 2; voiceIndex += 1) {
        const oscillator = audio.createOscillator();
        const filter = audio.createBiquadFilter();
        const gain = audio.createGain();
        const panner = audio.createStereoPanner();
        oscillator.type = voiceIndex === 0 ? "triangle" : "sawtooth";
        oscillator.detune.value = voiceIndex === 0 ? -2.5 : 3.5;
        filter.type = "lowpass";
        filter.Q.value = voiceIndex === 0 ? 2.2 : 1.65;
        gain.gain.setValueAtTime(0.0001, now);
        let voiceOutput: AudioNode = oscillator;
        if (environmentHit) {
          let resonantOutput: AudioNode = oscillator;
          environmentResonanceHarmonics.forEach((_, harmonicIndex) => {
            const resonator = audio.createBiquadFilter();
            resonator.type = "peaking";
            resonator.Q.value = 0.46 - harmonicIndex * 0.035;
            resonator.gain.value = environmentResonanceGains[harmonicIndex] ?? 1.5;
            resonantOutput.connect(resonator);
            resonantOutput = resonator;
            environmentResonators.push(resonator);
          });
          voiceOutput = resonantOutput;
        }
        voiceOutput
          .connect(filter)
          .connect(gain)
          .connect(panner)
          .connect(
            environmentHit
              ? (environmentWave?.output ?? environmentTail?.input ?? macroAudioRoute.input)
              : (macroTail?.input ?? macroAudioRoute.input),
          );
        oscillator.start(now);
        oscillators.push(oscillator);
        filters.push(filter);
        gains.push(gain);
        panners.push(panner);
      }
      let environmentBed: MacroChord["environmentBed"];
      if (environmentHit) {
        const sources: AudioBufferSourceNode[] = [];
        const bedFilters: BiquadFilterNode[] = [];
        const bedGains: GainNode[] = [];
        const bedPanners: StereoPannerNode[] = [];
        for (let sideIndex = 0; sideIndex < 2; sideIndex += 1) {
          const source = audio.createBufferSource();
          const filter = audio.createBiquadFilter();
          const gain = audio.createGain();
          const panner = audio.createStereoPanner();
          source.buffer = createAirNoiseBuffer(
            audio,
            0x454e5600 + sideIndex * 0x13579,
          );
          source.loop = true;
          source.playbackRate.value = sideIndex === 0 ? 0.992 : 1.008;
          filter.type = "bandpass";
          filter.frequency.value = sideIndex === 0 ? 3_200 : 4_600;
          filter.Q.value = 0.52;
          gain.gain.setValueAtTime(0.0001, now);
          panner.pan.value = sideIndex === 0 ? -0.86 : 0.86;
          source
            .connect(filter)
            .connect(gain)
            .connect(panner)
            .connect(
              environmentWave?.output
                ?? environmentTail?.input
                ?? macroAudioRoute.input,
            );
          source.start(now, sideIndex * 0.73);
          sources.push(source);
          bedFilters.push(filter);
          bedGains.push(gain);
          bedPanners.push(panner);
        }
        environmentBed = {
          sources,
          filters: bedFilters,
          gains: bedGains,
          panners: bedPanners,
        };
      }
      macroChords[trackIndex] = {
        oscillators,
        filters,
        gains,
        panners,
        environmentResonators,
        environmentWave,
        environmentBed,
      };
    }

    const chord = macroChords[trackIndex];
    if (!chord) return false;
    chord.oscillators.forEach((oscillator, voiceIndex) => {
      const gain = chord.gains[voiceIndex];
      if (!gain) return;
      oscillator.type = environmentHit
        ? "triangle"
        : backgroundSupport
          ? (voiceIndex === 0 ? "square" : "triangle")
          : (voiceIndex === 0 ? "triangle" : "sawtooth");
      const detuneSide = voiceIndex === 0 ? -1 : 1;
      oscillator.detune.setValueAtTime(
        environmentHit ? detuneSide * 2.2 : detuneSide * (backgroundSupport ? 1.2 : 3.5),
        now,
      );
      const panner = chord.panners[voiceIndex];
      if (panner) {
        const side = voiceIndex === 0 ? -1 : 1;
        panner.pan.cancelScheduledValues(now);
        if (environmentHit) {
          panner.pan.setValueAtTime(side * 0.38, now);
          panner.pan.linearRampToValueAtTime(
            side * 0.68,
            now + Math.max(0.16, holdSeconds * 0.92),
          );
        } else {
          const voiceSpread = voiceIndex === 0 ? -0.06 : 0.06;
          panner.pan.setValueAtTime(
            Math.max(-1, Math.min(1, wordPan + voiceSpread)),
            now,
          );
        }
      }
      gain.gain.cancelScheduledValues(now);
      const level = (environmentHit ? 0.16 : backgroundSupport ? 0.16 : 0.032)
        * (0.56 + intensity * 0.28);
      const voiceLevel = level * (
        environmentHit
          ? (voiceIndex === 0 ? 0.58 : 0.42)
          : backgroundSupport
            ? (voiceIndex === 0 ? 0.76 : 0.24)
          : (voiceIndex === 0 ? 0.84 : 0.16)
      );
      gain.gain.cancelAndHoldAtTime(now);
      gain.gain.setTargetAtTime(
        voiceLevel,
        now,
        macroAttackTimeConstant(word, holdSeconds),
      );
      const octaveOffset = backgroundSupport ? 36 : environmentHit ? 24 : 0;
      const target = macroRoot * Math.pow(2, (noteStep - octaveOffset) / 12);
      if (environmentHit) chord.environmentRootFrequency = target;
      const environmentDyad = environmentDyadCents[
        environmentDyadIndex % environmentDyadCents.length
      ];
      const environmentCents = environmentDyad?.[voiceIndex]
        ?? environmentDyad?.[environmentDyad.length - 1]
        ?? 0;
      const voiceTarget = environmentHit
        ? target * Math.pow(2, environmentCents / 1_200)
        : target * (
          backgroundSupport && voiceIndex === 1
            ? 2
            : 1
        );
      if (environmentHit) {
        chord.environmentVoiceFrequencies ??= [];
        chord.environmentVoiceFrequencies[voiceIndex] = voiceTarget;
      }
      oscillator.frequency.cancelScheduledValues(now);
      oscillator.frequency.setValueAtTime(voiceTarget, now);
      environmentResonanceHarmonics.forEach((harmonic, harmonicIndex) => {
        const resonatorIndex =
          voiceIndex * environmentResonanceHarmonics.length + harmonicIndex;
        const resonator = chord.environmentResonators?.[resonatorIndex];
        if (!resonator) return;
        resonator.frequency.cancelScheduledValues(now);
        resonator.frequency.setTargetAtTime(
          target * harmonic,
          now,
          0.7 + harmonicIndex * 0.22,
        );
      });
      const filter = chord.filters[voiceIndex];
      if (filter) {
        filter.type = environmentHit ? "peaking" : "lowpass";
        filter.Q.value = environmentHit
          ? (voiceIndex === 0 ? 0.38 : 0.46)
          : backgroundSupport
            ? (voiceIndex === 0 ? 0.72 : 0.55)
          : (voiceIndex === 0 ? 2.2 : 1.65);
        filter.gain.value = environmentHit
          ? (voiceIndex === 0 ? 2.6 : 1.8)
          : 0;
        filter.frequency.cancelScheduledValues(now);
        const restingCutoff = backgroundSupport
          ? Math.max(340, Math.min(720, voiceTarget * 8.2))
          : environmentHit
          ? (voiceIndex === 0 ? 760 : 1_150)
          : Math.max(720, Math.min(1_900, target * 2.4));
        const peakCutoff = backgroundSupport
          ? Math.max(820, Math.min(1_450, voiceTarget * 24))
          : environmentHit
          ? restingCutoff
          : Math.max(1_100, Math.min(3_400, target * 5.2));
        filter.frequency.setValueAtTime(restingCutoff, now);
        filter.frequency.setTargetAtTime(
          peakCutoff,
          now,
          backgroundSupport ? 0.035 : environmentHit ? 0.82 : 0.075,
        );
        filter.frequency.setTargetAtTime(
          restingCutoff,
          now + Math.min(
            backgroundSupport ? 0.7 : environmentHit ? 1.4 : 0.24,
            holdSeconds * 0.42,
          ),
          backgroundSupport ? 0.18 : environmentHit ? 1.6 : 0.38,
        );
      }
    });
    if (environmentHit && chord.environmentBed) {
      chord.environmentBed.gains.forEach((gain, sideIndex) => {
        gain.gain.cancelAndHoldAtTime(now);
        gain.gain.setTargetAtTime(
          (sideIndex === 0 ? 0.012 : 0.01) * (0.72 + intensity * 0.24),
          now,
          1.05,
        );
      });
    }

    macroChordActive = true;
    return true;
  }

  function activateMacroNote(
    trackIndex: number,
    word: string,
    noteStep: number,
    intensity: number,
    holdSeconds: number,
    onsetTime?: number,
  ) {
    if (!sustainMacroChord(
      trackIndex,
      noteStep,
      intensity,
      holdSeconds,
      word,
      onsetTime,
    )) return false;
    const audio = macroAudioRoute?.audioContext;
    if (!audio) return false;
    const attackStart = Math.max(audio.currentTime + 0.008, onsetTime ?? 0);
    const nextVisualEnvelopes = [...macroVisualEnvelopes] as [MacroVisualEnvelope | undefined, MacroVisualEnvelope | undefined];
    nextVisualEnvelopes[trackIndex] = {
      word,
      attackStart,
      attackTimeConstant: macroAttackTimeConstant(word, holdSeconds),
      releaseTimeConstant: 0.85,
    };
    macroVisualEnvelopes = nextVisualEnvelopes;
    const nextActiveWords = [...activeMacroWords] as [string | undefined, string | undefined];
    nextActiveWords[trackIndex] = word;
    activeMacroWords = nextActiveWords;
    return true;
  }

  function macroGroupInterval(groupSize: number, groupIndex: number) {
    if (groupIndex === 4) return 4;
    if (groupSize <= 1) return 4;
    if (groupSize === 2) return 3;
    if (groupSize === 3) return 2;
    return 1;
  }

  function advanceMacroActivation(onsetTime: number | undefined) {
    const trackIndex = 0;
    const groups = macroTrackGroups[trackIndex] ?? macroTrackGroups[0];
    const direction = macroClockwiseDirections[trackIndex] ?? 1;
    const groupSlot = ((macroClockwiseGroupPosition % groups.length) + groups.length) % groups.length;
    const groupIndex = groups[groupSlot];
    const groupWords = macroTwinkleGroups[groupIndex]?.words ?? ["#environment"];
    const groupSize = groupWords.length;
    const intervalTicks = macroGroupInterval(groupSize, groupIndex);
    const pattern = macroGroupPatterns[groupIndex] ?? macroGroupPatterns[0];
    const patternIndex = macroPatternDirection > 0
      ? macroGroupNoteIndex % pattern.length
      : pattern.length - 1 - (macroGroupNoteIndex % pattern.length);
    const noteStep = pattern[patternIndex] ?? pattern[0];
    const wordPatternIndex = macroPatternDirection > 0
      ? macroGroupNoteIndex % groupSize
      : groupSize - 1 - (macroGroupNoteIndex % groupSize);
    const activeWord = groupIndex === 4
      ? "#environment"
      : groupWords[wordPatternIndex] ?? groupWords[0];
    const enteringNewGroup = macroTrackLastGroups[trackIndex] !== groupIndex;
    macroTrackLastGroups[trackIndex] = groupIndex;
    if (groupIndex === 4) {
      if (activeMacroWords[trackIndex] === "#environment") {
        releaseMacroNote(trackIndex);
      }
      macroGroupNoteIndex = 0;
      macroClockwiseGroupPosition += direction;
      macroPatternDirection *= -1;
      macroReleaseTick = -1;
      macroNextNoteTick = macroSequenceTick + intervalTicks + 8;
      return true;
    }
    const intensity = 0.48 + Math.min(groupSize, 4) * 0.025;
    const holdSeconds = (RANGE_RHYTHM_SUBDIVISION_MS / 1_000) * intervalTicks;
    const activated = activateMacroNote(
      trackIndex,
      activeWord,
      noteStep,
      intensity,
      holdSeconds,
      onsetTime,
    );
    if (!activated) return false;
    if (enteringNewGroup) {
      const activeCell = cells.find((cell) => cell.text === activeWord);
      if (activeCell) {
        macroGroupPulseId += 1;
        macroGroupPulse = {
          id: macroGroupPulseId,
          x: activeCell.x,
          y: activeCell.y,
          tone: macroTone(activeWord),
        };
      }
    }

    macroGroupNoteIndex += 1;
    macroReleaseTick = macroSequenceTick + intervalTicks;
    if (macroGroupNoteIndex >= pattern.length) {
      macroGroupNoteIndex = 0;
      macroClockwiseGroupPosition += direction;
      macroPatternDirection *= -1;
      // Environment is the fifth count: four ticks of presence followed by
      // eight ticks of space complete the shared twelve-step phrase.
      const groupRestTicks = groupIndex === 4 ? 8 : macroGroupRestTicks;
      macroNextNoteTick = macroSequenceTick
        + intervalTicks
        + groupRestTicks;
    } else {
      macroNextNoteTick = macroSequenceTick + intervalTicks;
    }
    return true;
  }

  function createSnareNoiseBuffer(
    audio: AudioContext,
    seed: number,
  ) {
    const duration = 0.62;
    const buffer = audio.createBuffer(
      1,
      Math.floor(audio.sampleRate * duration),
      audio.sampleRate,
    );
    const samples = buffer.getChannelData(0);
    let randomState = seed >>> 0;
    let smooth = 0;
    for (let index = 0; index < samples.length; index += 1) {
      randomState = (randomState * 1664525 + 1013904223) >>> 0;
      const white = (randomState / 4294967296) * 2 - 1;
      smooth = smooth * 0.78 + white * 0.22;
      const progress = index / samples.length;
      samples[index] = (white * 0.68 + smooth * 0.32)
        * Math.exp(-progress * 7.5);
    }
    return buffer;
  }

  function randomBackgroundMacro(excluded: Set<string>) {
    const available = backgroundMacroWords.filter((word) => !excluded.has(word));
    const pool = available.length > 0 ? available : backgroundMacroWords;
    macroSelectionRandomState ^= macroSelectionRandomState << 13;
    macroSelectionRandomState ^= macroSelectionRandomState >>> 17;
    macroSelectionRandomState ^= macroSelectionRandomState << 5;
    const index = (macroSelectionRandomState >>> 0) % pool.length;
    return pool[index];
  }

  function playMacroSnare(
    pan: number,
    onsetTime: number,
    seed: number,
    accent: number,
    tailSeconds: number,
  ) {
    if (!macroAudioRoute) return;
    const audio = macroAudioRoute.audioContext;
    const source = audio.createBufferSource();
    const highpass = audio.createBiquadFilter();
    const crisp = audio.createBiquadFilter();
    const gain = audio.createGain();
    const panner = audio.createStereoPanner();
    const body = audio.createOscillator();
    const bodyGain = audio.createGain();
    source.buffer = createSnareNoiseBuffer(audio, seed);
    highpass.type = "highpass";
    highpass.frequency.value = 420;
    highpass.Q.value = 0.48;
    crisp.type = "bandpass";
    crisp.frequency.value = 1_850;
    crisp.Q.value = 0.64;
    gain.gain.setValueAtTime(0.0001, onsetTime);
    gain.gain.linearRampToValueAtTime(accent, onsetTime + 0.006);
    gain.gain.exponentialRampToValueAtTime(0.0001, onsetTime + tailSeconds);
    body.type = "triangle";
    body.frequency.setValueAtTime(172, onsetTime);
    body.frequency.exponentialRampToValueAtTime(104, onsetTime + 0.055);
    bodyGain.gain.setValueAtTime(accent * 0.46, onsetTime);
    bodyGain.gain.exponentialRampToValueAtTime(
      0.0001,
      onsetTime + Math.min(0.12, tailSeconds * 0.48),
    );
    panner.pan.value = pan;
    source
      .connect(highpass)
      .connect(crisp)
      .connect(gain)
      .connect(panner)
      .connect(backgroundTail?.input ?? macroAudioRoute.input);
    body
      .connect(bodyGain)
      .connect(panner);
    source.start(onsetTime);
    body.start(onsetTime);
    body.stop(onsetTime + Math.min(0.14, tailSeconds * 0.52));
    macroSidechainPulseId += 1;
    const sidechainPulseId = macroSidechainPulseId;
    soundManager?.setLayerPresence?.(
      "macros",
      Math.min(0.95, accent / 0.21),
    );
    window.setTimeout(() => {
      if (sidechainPulseId !== macroSidechainPulseId) return;
      soundManager?.setLayerPresence?.("macros", 0);
    }, Math.max(80, tailSeconds * 420));
    source.addEventListener("ended", () => {
      source.disconnect();
      body.disconnect();
      bodyGain.disconnect();
      highpass.disconnect();
      crisp.disconnect();
      gain.disconnect();
      panner.disconnect();
    }, { once: true });
  }

  function activateBackgroundSupport(onsetTime: number | undefined) {
    if (!soundManager?.isEnabled() || !macroAudioRoute) return false;
    const audio = macroAudioRoute.audioContext;
    const now = Math.max(audio.currentTime + 0.008, onsetTime ?? 0);
    const decayingWords = new Set(
      backgroundVisualEnvelopes
        .filter((envelope) =>
          envelope.releaseStart === undefined ||
          now - envelope.releaseStart < envelope.releaseTimeConstant * 3
        )
        .map((envelope) => envelope.word),
    );
    const word = randomBackgroundMacro(decayingWords);
    const tailSeconds = 0.12
      + Math.pow(macroFieldViewportPresence, 0.72) * 0.4;
    const intervalPosition = macroBackgroundIntervalIndex
      % macroBackgroundIntervalPattern.length;
    const interval = macroBackgroundIntervalPattern[intervalPosition]
      ?? macroBackgroundIntervalPattern[0];
    const accent = interval === 8 ? 0.2 : interval === 4 ? 0.17 : 0.138;
    const fallbackPan = macroHatRollIndex % 2 === 0 ? -0.24 : 0.24;
    playMacroSnare(
      macroPanForWord(word, fallbackPan),
      now,
      0x534e4152 + macroHatRollIndex * 97,
      accent,
      tailSeconds,
    );
    backgroundVisualEnvelopes = [
      ...backgroundVisualEnvelopes,
      ...(word ? [{
        word,
        attackStart: now,
        attackTimeConstant: 0.035,
        releaseStart: now + tailSeconds * 0.18,
        releaseLevel: 0.84,
        releaseTimeConstant: Math.max(0.12, tailSeconds * 0.72),
      }] : []),
    ];
    macroHatRollIndex += 1;
    macroBackgroundIntervalIndex = (
      macroBackgroundIntervalIndex + 1
    ) % macroBackgroundIntervalPattern.length;
    macroNextSupportTick = macroSequenceTick + interval;
    return true;
  }

  onMount(() => {
    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
    if (reducedMotion.matches) return;

    let visible = false;
    let sectionIntersects = false;
    let macroFieldPassed = false;
    let envelopeFrame = 0;
    let viewportFrame = 0;
    let macroFieldProximity = 0;
    let environmentProximity = 0;
    const layoutRect = (element: Element) =>
      layoutTracker?.locate(element).rect ?? element.getBoundingClientRect();
    const viewportProximity = (element: SVGGraphicsElement | undefined) => {
      if (!element) return 0;
      const bounds = layoutRect(element);
      const viewportHeight = window.innerHeight;
      const center = bounds.top + bounds.height / 2;
      const reach = viewportHeight * 0.68 + bounds.height / 2;
      const linear = Math.max(
        0,
        Math.min(1, 1 - Math.abs(center - viewportHeight / 2) / reach),
      );
      return linear * linear * (3 - 2 * linear);
    };
    const viewportPresence = (element: SVGGraphicsElement | undefined) => {
      if (!element) return 0;
      const bounds = layoutRect(element);
      const viewportHeight = window.innerHeight;
      const fadeDistance = Math.max(96, viewportHeight * 0.2);
      const entering = Math.max(
        0,
        Math.min(1, (viewportHeight - bounds.top) / fadeDistance),
      );
      const leaving = Math.max(
        0,
        Math.min(1, bounds.bottom / fadeDistance),
      );
      const linear = Math.min(entering, leaving);
      return linear * linear * (3 - 2 * linear);
    };
    const applyEnvironmentPresence = () => {
      const effectivePresence = environmentProximity;
      soundManager?.setLayerPresence?.("environment", effectivePresence);

      if (!macroAudioRoute || !macroRouteOpen) return;
      const now = macroAudioRoute.audioContext.currentTime;
      const environmentAmount = effectivePresence * effectivePresence
        * (3 - 2 * effectivePresence);
      macroSpaceFilter?.frequency.cancelScheduledValues(now);
      macroSpaceFilter?.frequency.setTargetAtTime(
        14_000 * Math.pow(680 / 14_000, environmentAmount),
        now,
        1.1,
      );
      macroSpaceCompressor?.threshold.setTargetAtTime(
        -14 - environmentAmount * 24,
        now,
        1.1,
      );
      macroSpaceCompressor?.ratio.setTargetAtTime(
        1.4 + environmentAmount * 8.6,
        now,
        1.1,
      );
      macroSpaceOutput?.gain.setTargetAtTime(
        1 - environmentAmount * 0.66,
        now,
        1.1,
      );
    };
    const updateViewportMix = () => {
      viewportFrame = 0;
      const fieldBounds = macroFieldElement
        ? layoutRect(macroFieldElement)
        : undefined;
      if (fieldBounds) {
        if (fieldBounds.bottom <= window.innerHeight * 0.46) {
          macroFieldPassed = true;
        } else if (fieldBounds.top >= window.innerHeight * 0.72) {
          macroFieldPassed = false;
        }
      }
      macroFieldViewportPresence = viewportProximity(macroFieldElement);
      macroFieldProximity = Math.max(
        macroFieldViewportPresence,
        macroFieldPassed ? 0.42 : 0,
      );
      environmentWindowPresence = viewportPresence(environmentKeyElement);
      environmentProximity = environmentWindowPresence;
      applyEnvironmentPresence();
      const shouldBeVisible = sectionIntersects || macroFieldPassed;
      if (shouldBeVisible !== visible) {
        visible = shouldBeVisible;
        if (visible && !document.hidden) void start();
        else if (!visible) stop(true);
      }
      if (!macroAudioRoute || !macroRouteOpen) return;
      const proximity = Math.max(macroFieldProximity, environmentProximity);
      const target = Math.max(0.0001, macroRouteLevel * proximity);
      const gain = macroAudioRoute.input.gain;
      const now = macroAudioRoute.audioContext.currentTime;
      gain.cancelScheduledValues(now);
      gain.setTargetAtTime(target, now, target > gain.value ? 0.52 : 0.88);
      if (activeMacroWords[0] === "#environment") {
        releaseMacroNote(0);
        environmentNextDyadTick = -1;
      }
    };
    const scheduleViewportMix = () => {
      if (viewportFrame) return;
      viewportFrame = requestAnimationFrame(updateViewportMix);
    };
    const updateVisualEnvelope = () => {
      if (macroAudioRoute) {
        macroVisualTime = macroAudioRoute.audioContext.currentTime;
        backgroundVisualEnvelopes = backgroundVisualEnvelopes.filter(
          (envelope) =>
            envelope.releaseStart === undefined ||
            macroVisualTime - envelope.releaseStart < envelope.releaseTimeConstant * 7,
        );
      }
      envelopeFrame = requestAnimationFrame(updateVisualEnvelope);
    };
    envelopeFrame = requestAnimationFrame(updateVisualEnvelope);
    const stop = (resetGesture = true) => {
      stopMacroTracks();
      if (resetGesture) {
        macroTrackLastGroups = [undefined];
        macroClockwiseGroupPosition = 0;
        macroSequenceTick = 0;
        macroNextNoteTick = macroSequenceStartOffset;
        macroNextSupportTick = macroSequenceStartOffset;
        macroHatRollIndex = 0;
        macroBackgroundIntervalIndex = 0;
        macroSelectionRandomState = 0x4d414352;
        macroReleaseTick = -1;
        macroClockInitialized = false;
        macroGroupNoteIndex = 0;
        macroPatternDirection = 1;
        environmentDyadIndex = 0;
        environmentNextDyadTick = -1;
      }
    };
    const start = async () => {
      if (!transportRunning || !visible || document.hidden) return;
      await ensureMacroAudioRoute();
      updateViewportMix();
    };
    const observer = new IntersectionObserver(
      ([entry]) => {
        sectionIntersects = entry?.isIntersecting ?? false;
        updateViewportMix();
      },
      { rootMargin: "14% 0px 14%" },
    );
    const unsubscribeSound = soundManager?.subscribe((enabled) => {
      const generation = ++macroTransportGeneration;
      if (!enabled) {
        transportRunning = false;
        stopMacroTracks();
      } else if (visible && !document.hidden) {
        transportRunning = false;
        window.setTimeout(() => {
          if (
            generation === macroTransportGeneration &&
            visible &&
            !document.hidden
          ) {
            transportRunning = true;
            void start();
          }
        }, 920);
      } else {
        transportRunning = true;
      }
    });
    const unsubscribeRhythm = soundManager?.subscribeRhythmBeat?.(({ tick, audioTime }) => {
      if (!visible || document.hidden) return;
      if (!macroClockInitialized) {
        macroSequenceTick = tick;
        macroNextNoteTick = tick + macroSequenceStartOffset;
        macroNextSupportTick = tick + macroSequenceStartOffset;
        macroHatRollIndex = 0;
        macroBackgroundIntervalIndex = 0;
        macroSelectionRandomState = 0x4d414352;
        macroReleaseTick = -1;
        macroClockInitialized = true;
      } else {
        macroSequenceTick = tick;
      }
      if (
        macroReleaseTick >= 0 &&
        macroSequenceTick >= macroReleaseTick &&
        activeMacroWords[0] !== "#environment"
      ) {
        releaseMacroNote(0);
        macroReleaseTick = -1;
      }
      if (
        macroFieldProximity > 0.035 &&
        macroSequenceTick >= macroNextSupportTick
      ) {
        activateBackgroundSupport(audioTime);
      }
    });
    const handleVisibilityChange = () => {
      if (document.hidden) {
        environmentProximity = 0;
        environmentWindowPresence = 0;
        applyEnvironmentPresence();
        stop(false);
      } else {
        updateViewportMix();
        void start();
      }
    };
    observer.observe(macroCloudElement);
    const stopTrackingLayout = layoutTracker?.observe(
      '[data-range-layout="macro-cloud"]',
      scheduleViewportMix,
    );
    document.addEventListener("visibilitychange", handleVisibilityChange);
    return () => {
      stop();
      cancelAnimationFrame(envelopeFrame);
      if (viewportFrame) cancelAnimationFrame(viewportFrame);
      observer.disconnect();
      unsubscribeSound?.();
      unsubscribeRhythm?.();
      stopTrackingLayout?.();
      soundManager?.setLayerPresence?.("environment", 0);
      document.removeEventListener("visibilitychange", handleVisibilityChange);
    };
  });

  onDestroy(() => {
    soundManager?.setLayerPresence?.("environment", 0);
    soundManager?.setLayerPresence?.("macros", 0);
    stopMacroTracks();
    macroTail?.input.disconnect();
    macroTail?.tone.disconnect();
    macroTail?.convolver.disconnect();
    macroTail?.dry.disconnect();
    macroTail?.wet.disconnect();
    environmentTail?.input.disconnect();
    environmentTail?.tone.disconnect();
    environmentTail?.convolver.disconnect();
    environmentTail?.dry.disconnect();
    environmentTail?.wet.disconnect();
    backgroundTail?.input.disconnect();
    backgroundTail?.tone.disconnect();
    backgroundTail?.convolver.disconnect();
    backgroundTail?.dry.disconnect();
    backgroundTail?.wet.disconnect();
    macroSpaceInput?.disconnect();
    macroSpaceFilter?.disconnect();
    macroSpaceCompressor?.disconnect();
    macroSpaceOutput?.disconnect();
    macroAudioRoute?.dispose();
  });
</script>

<section
  class="macroCloud"
  data-range-layout="macro-cloud"
  class:transportStopped={!transportRunning}
  aria-label="Macros"
  bind:this={macroCloudElement}
>
  <svg
    class="macroCloudGraphic"
    viewBox={`0 0 ${fieldWidth} ${fieldHeight}`}
    role="img"
    aria-label="Flowing strip of Range macro forms activating in sequence"
  >
    <defs>
      <linearGradient id="macro-flow-edge-fade" x1="0" y1="0" x2="1" y2="0">
        <stop offset="0" stop-color="white" stop-opacity="0" />
        <stop offset="0.085" stop-color="white" stop-opacity="1" />
        <stop offset="0.915" stop-color="white" stop-opacity="1" />
        <stop offset="1" stop-color="white" stop-opacity="0" />
      </linearGradient>
      <mask id="macro-flow-mask" maskUnits="userSpaceOnUse" x="0" y="0" width={fieldWidth} height="475">
        <rect width={fieldWidth} height="475" fill="url(#macro-flow-edge-fade)" />
      </mask>
    </defs>
    {#if macroGroupPulse}
      {#key macroGroupPulse.id}
        <g
          class={`macroGroupPulse ${macroGroupPulse.tone}`}
          transform={`translate(${macroGroupPulse.x} ${macroGroupPulse.y})`}
          aria-hidden="true"
        >
          <defs>
            <radialGradient id={`macro-group-pulse-${macroGroupPulse.id}`}>
              <stop offset="0" stop-color="var(--pulse-color)" stop-opacity="0.72" />
              <stop offset="0.3" stop-color="var(--pulse-color)" stop-opacity="0.32" />
              <stop offset="0.7" stop-color="var(--pulse-color)" stop-opacity="0.09" />
              <stop offset="1" stop-color="var(--pulse-color)" stop-opacity="0" />
            </radialGradient>
          </defs>
          <circle
            class="macroGroupPulseCircle"
            cx="0"
            cy="0"
            r="190"
            fill={`url(#macro-group-pulse-${macroGroupPulse.id})`}
          />
        </g>
      {/key}
    {/if}
    <g bind:this={macroFieldElement} mask="url(#macro-flow-mask)">
      {#each macroFlowRows as row, rowIndex}
        <g
          class={`macroFlowRow macroFlowRow${rowIndex + 1}`}
          style={`--flow-distance: ${-row.loopWidth}px; --flow-duration: ${row.duration}s; --flow-delay: -${row.phase}s`}
        >
          {#each [0, 1] as copyIndex}
            {#each row.cells as cell, cellIndex (`${copyIndex}-${cell.text}`)}
              {@const activation = macroCellActivation(cell.text)}
              {@const hitScale = macroCellHitScale(cell.text, activation)}
              {@const tone = macroTone(cell.text)}
              <g
                class="macroKey macroFlowWord"
                style={`--float-delay: -${(cellIndex * 1.7 + copyIndex * 0.8).toFixed(1)}s; --macro-hit-scale: ${hitScale}`}
              >
                <text
                  class={`macroCellLabel ${tone}`}
                  x={cell.x + copyIndex * row.loopWidth}
                  y={cell.y}
                  font-size={cell.fontSize}
                  font-weight="600"
                  text-anchor="middle"
                  dominant-baseline="central"
                >{cell.text}</text>
                <text
                  class={`macroCellGlow ${tone}`}
                  style={`--activation: ${activation}`}
                  x={cell.x + copyIndex * row.loopWidth}
                  y={cell.y}
                  font-size={cell.fontSize}
                  font-weight="600"
                  text-anchor="middle"
                  dominant-baseline="central"
                  aria-hidden="true"
                >{cell.text}</text>
              </g>
            {/each}
          {/each}
        </g>
      {/each}
    </g>
    <foreignObject x="180" y="665" width="600" height="150">
      <div
        class="macroBridge"
        xmlns="http://www.w3.org/1999/xhtml"
      >
        <p>
          Source is always the truth. The graph is just one representation.
        </p>
      </div>
    </foreignObject>
    {#each [environmentCell] as cell}
      <g
        bind:this={environmentKeyElement}
        class="macroKey environmentKey"
        aria-label="Environment"
      >
        <text
          class="macroCellLabel environmentLabel"
          x={cell.x}
          y={cell.y}
          font-size={cell.fontSize}
          font-weight="600"
          text-anchor="middle"
          dominant-baseline="central"
        >{cell.text}</text>
      </g>
    {/each}
  </svg>
  <ul class="macroCloudText">
    {#each macroWords as word}
      <li>{word.text}</li>
    {/each}
  </ul>
</section>

<style>
  .macroCloud {
    box-sizing: border-box;
    width: 100vw;
    margin-left: calc(50% - 50vw);
    padding: 24px clamp(28px, 5vw, 112px) 72px;
  }

  .macroCloudGraphic {
    width: 100%;
    height: auto;
    display: block;
    overflow: visible;
  }

  .macroCloudGraphic text {
    font-family: var(--font-geist-mono), monospace;
    font-variant-ligatures: none;
  }

  .macroBridge {
    width: 100%;
    height: 100%;
    display: grid;
    place-items: center;
    color: oklch(0.31 0.012 255);
    font-family: var(--font-geist-sans), sans-serif;
    font-size: 22px;
    line-height: 1.42;
    text-align: center;
  }

  .macroBridge p {
    max-width: 560px;
    margin: 0;
  }

  .macroTreeEdge {
    fill: none;
    stroke: oklch(0.8 0.018 250 / 0.62);
    stroke-width: calc(1.15px + var(--activation) * 1.35px);
    opacity: calc(0.36 + var(--activation) * 0.64);
    stroke-linecap: round;
    vector-effect: non-scaling-stroke;
  }

  .macroTreeEdge.activeTreeEdge {
    stroke: var(--range);
  }

  .macroTreeEdge.macroLilac.activeTreeEdge { stroke: oklch(0.77 0.25 307); }
  .macroTreeEdge.macroAmber.activeTreeEdge { stroke: oklch(0.82 0.21 74); }
  .macroTreeEdge.macroGrape.activeTreeEdge { stroke: oklch(0.72 0.25 315); }
  .macroTreeEdge.macroCyan.activeTreeEdge { stroke: oklch(0.8 0.18 220); }
  .macroTreeEdge.macroPink.activeTreeEdge { stroke: oklch(0.77 0.23 350); }

  .macroTreeRoot {
    fill: white;
    stroke: oklch(0.62 0.035 250);
    stroke-width: 1.4;
    vector-effect: non-scaling-stroke;
  }

  .macroGroupPulse {
    --pulse-color: oklch(0.75 0.22 255);
    pointer-events: none;
  }

  .macroGroupPulse.macroLilac { --pulse-color: oklch(0.77 0.25 307); }
  .macroGroupPulse.macroAmber { --pulse-color: oklch(0.82 0.21 74); }
  .macroGroupPulse.macroGrape { --pulse-color: oklch(0.72 0.25 315); }
  .macroGroupPulse.macroCyan { --pulse-color: oklch(0.8 0.18 220); }
  .macroGroupPulse.macroPink { --pulse-color: oklch(0.77 0.23 350); }
  .macroGroupPulse.macroYellow { --pulse-color: oklch(0.88 0.18 92); }
  .macroGroupPulse.syntaxMacro { --pulse-color: var(--range); }
  .macroGroupPulse.syntaxSplice { --pulse-color: oklch(0.62 0.18 290); }
  .macroGroupPulse.syntaxType { --pulse-color: oklch(0.55 0.16 190); }

  .macroGroupPulseCircle {
    opacity: 0;
    transform-box: fill-box;
    transform-origin: center;
    animation: macroGroupEmit 4.8s cubic-bezier(0.16, 0.72, 0.24, 1) both;
  }

  @keyframes macroGroupEmit {
    0% {
      opacity: 0;
      transform: scale(0.04);
    }
    12% {
      opacity: 0.68;
    }
    58% {
      opacity: 0.3;
    }
    100% {
      opacity: 0;
      transform: scale(1.28);
    }
  }

  .macroKey {
    pointer-events: none;
  }

  .macroFlowRow {
    transform-box: view-box;
    transform-origin: 0 0;
    animation: macroRowFlow var(--flow-duration) linear var(--flow-delay) infinite;
    will-change: transform;
  }

  .macroCloud.transportStopped .macroFlowRow,
  .macroCloud.transportStopped .macroFlowWord,
  .macroCloud.transportStopped .macroGroupPulseCircle {
    animation-play-state: paused;
  }

  @keyframes macroRowFlow {
    from { transform: translateX(0); }
    to { transform: translateX(var(--flow-distance)); }
  }

  .macroFlowWord {
    transform-box: fill-box;
    transform-origin: center;
    animation: macroWordFloat 9s ease-in-out var(--float-delay) infinite;
  }

  .macroFlowRow2 .macroFlowWord {
    animation-duration: 11s;
  }

  .macroFlowRow3 .macroFlowWord {
    animation-duration: 10s;
  }

  @keyframes macroWordFloat {
    0%, 100% { transform: translateY(-3px); }
    50% { transform: translateY(3px); }
  }

  .macroCellLabel {
    fill: white;
    transition: fill 1.4s cubic-bezier(0.22, 0.61, 0.36, 1);
  }

  .macroCellLabel,
  .macroCellGlow {
    transform: scale(var(--macro-hit-scale, 1));
    transform-box: fill-box;
    transform-origin: center;
  }

  .macroCellLabel.macroLilac { fill: oklch(0.82 0.09 307); }
  .macroCellLabel.macroAmber { fill: oklch(0.84 0.1 74); }
  .macroCellLabel.macroGrape { fill: oklch(0.79 0.09 315); }
  .macroCellLabel.macroCyan { fill: oklch(0.83 0.08 220); }
  .macroCellLabel.macroPink { fill: oklch(0.82 0.08 350); }
  .macroCellLabel.macroYellow { fill: oklch(0.88 0.09 92); }
  .macroCellLabel.syntaxMacro { fill: var(--range); }
  .macroCellLabel.syntaxSplice { fill: oklch(0.62 0.18 290); }
  .macroCellLabel.syntaxType { fill: oklch(0.55 0.16 190); }

  .macroCellLabel.activeMacroLabel {
    fill: var(--range);
  }

  .macroCellLabel.macroLilac.activeMacroLabel {
    fill: oklch(0.77 0.25 307);
  }

  .macroCellLabel.macroAmber.activeMacroLabel {
    fill: oklch(0.82 0.21 74);
  }

  .macroCellLabel.macroGrape.activeMacroLabel {
    fill: oklch(0.72 0.25 315);
  }

  .macroCellLabel.macroCyan.activeMacroLabel {
    fill: oklch(0.8 0.18 220);
  }

  .macroCellLabel.macroMint.activeMacroLabel {
    fill: oklch(0.83 0.18 163);
  }

  .macroCellLabel.macroCoral.activeMacroLabel { fill: oklch(0.78 0.23 35); }
  .macroCellLabel.macroBlue.activeMacroLabel { fill: oklch(0.75 0.22 255); }
  .macroCellLabel.macroYellow.activeMacroLabel { fill: oklch(0.88 0.21 97); }
  .macroCellLabel.macroRed.activeMacroLabel { fill: oklch(0.73 0.25 25); }
  .macroCellLabel.macroPink.activeMacroLabel { fill: oklch(0.77 0.23 350); }
  .macroCellLabel.macroTeal.activeMacroLabel { fill: oklch(0.79 0.17 190); }
  .macroCellLabel.syntaxMacro.activeMacroLabel { fill: var(--range); }
  .macroCellLabel.syntaxSplice.activeMacroLabel { fill: oklch(0.71 0.18 290); }
  .macroCellLabel.syntaxType.activeMacroLabel { fill: oklch(0.67 0.16 190); }

  .macroCellGlow {
    fill: color-mix(in oklch, var(--range) 18%, white);
    stroke: color-mix(in oklch, var(--range) 10%, white);
    stroke-width: calc(var(--activation) * 0.34px);
    paint-order: stroke fill;
    opacity: calc(var(--activation) * 0.96);
    filter:
      drop-shadow(0 0 3px color-mix(in oklch, white, transparent 24%))
      drop-shadow(0 0 9px color-mix(in oklch, var(--range), transparent 56%));
  }

  .macroCellGlow.macroLilac {
    fill: oklch(0.77 0.25 307);
    filter: drop-shadow(0 0 5px oklch(0.77 0.25 307 / 0.5));
  }

  .macroCellGlow.macroAmber {
    fill: oklch(0.82 0.21 74);
    filter: drop-shadow(0 0 5px oklch(0.82 0.21 74 / 0.5));
  }

  .macroCellGlow.macroGrape {
    fill: oklch(0.72 0.25 315);
    filter: drop-shadow(0 0 5px oklch(0.72 0.25 315 / 0.5));
  }

  .macroCellGlow.macroCyan {
    fill: oklch(0.8 0.18 220);
    filter: drop-shadow(0 0 5px oklch(0.8 0.18 220 / 0.5));
  }

  .macroCellGlow.macroMint {
    fill: oklch(0.83 0.18 163);
    filter: drop-shadow(0 0 5px oklch(0.83 0.18 163 / 0.5));
  }

  .macroCellGlow.macroCoral { fill: oklch(0.78 0.23 35); filter: drop-shadow(0 0 5px oklch(0.78 0.23 35 / 0.5)); }
  .macroCellGlow.macroBlue { fill: oklch(0.75 0.22 255); filter: drop-shadow(0 0 5px oklch(0.75 0.22 255 / 0.5)); }
  .macroCellGlow.macroYellow { fill: oklch(0.88 0.21 97); filter: drop-shadow(0 0 5px oklch(0.88 0.21 97 / 0.5)); }
  .macroCellGlow.macroRed { fill: oklch(0.73 0.25 25); filter: drop-shadow(0 0 5px oklch(0.73 0.25 25 / 0.5)); }
  .macroCellGlow.macroPink { fill: oklch(0.77 0.23 350); filter: drop-shadow(0 0 5px oklch(0.77 0.23 350 / 0.5)); }
  .macroCellGlow.macroTeal { fill: oklch(0.79 0.17 190); filter: drop-shadow(0 0 5px oklch(0.79 0.17 190 / 0.5)); }
  .macroCellGlow.syntaxMacro {
    fill: color-mix(in oklch, var(--range) 18%, white);
    filter: drop-shadow(
        0 0 3px color-mix(in oklch, white, transparent 24%)
      )
      drop-shadow(
        0 0 9px color-mix(in oklch, var(--range), transparent 56%)
      );
  }
  .macroCellGlow.syntaxSplice { fill: oklch(0.71 0.18 290); filter: drop-shadow(0 0 5px oklch(0.62 0.18 290 / 0.5)); }
  .macroCellGlow.syntaxType { fill: oklch(0.67 0.16 190); filter: drop-shadow(0 0 5px oklch(0.55 0.16 190 / 0.5)); }

  .environmentKey {
    opacity: 1;
  }

  .environmentLabel {
    fill: oklch(0.7 0.16 295);
    letter-spacing: -0.035em;
  }

  .macroCloudText {
    position: absolute;
    width: 1px;
    height: 1px;
    margin: -1px;
    padding: 0;
    overflow: hidden;
    clip: rect(0 0 0 0);
    clip-path: inset(50%);
    white-space: nowrap;
  }

  @media (max-width: 520px) {
    .macroCloud {
      padding: 16px 20px 52px;
    }

  }
</style>
