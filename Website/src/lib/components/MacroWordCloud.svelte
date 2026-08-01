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
  };
  type MacroTail = {
    input: GainNode;
    tone: BiquadFilterNode;
    convolver: ConvolverNode;
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
    { text: "@project", weight: 64 },
    { text: "@command", weight: 60 },
    { text: "@commandGroup", weight: 54 },
    { text: "@stored", weight: 46 },
    { text: "@graph", weight: 39 },
    { text: "@syntax", weight: 36 },
  ];

  const fieldWidth = 960;
  const fieldHeight = 500;
  const fieldInset = 28;
  const macroSemanticGroups = [
    ["@equatable", "@codable", "@comparable", "@hashable"],
    ["@app", "@component", "@page"],
    ["@project", "@command", "@commandGroup"],
    ["@graph", "@syntax", "@stored"],
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
  const macroBackgroundStepTicks = 12;
  const macroBackgroundHoldPattern = [3, 3, 9, 3, 3] as const;
  // Broken C Dorian arpeggios crawl from C3 through C5. Octave-displaced
  // returns make each group a phrase without leaving the shared scale.
  const macroGroupPatterns = [
    [0, 7, 3, 14, 12, 10, 19, 15, 24],
    [5, 15, 10, 17, 14, 7, 22],
    [12, 19, 15, 24, 21, 17, 10, 22],
    [22, 14, 24, 17, 21, 19, 12],
    [0, 0],
  ] as const;
  const macroRouteLevel = 0.68;
  const macroTwinkleGroups: readonly MacroTwinkleGroup[] = [
    { words: ["@equatable", "@codable", "@comparable", "@hashable"] },
    { words: ["@app", "@component", "@page"] },
    { words: ["@project", "@command", "@commandGroup"] },
    { words: ["@graph", "@syntax", "@stored"] },
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
    const clusters: MacroClusterDatum[] = macroSemanticGroups.map((group, index) => ({
      text: `cluster-${index}`,
      weight: group.reduce(
        (sum, text) => sum + (wordsByText.get(text)?.weight ?? 0),
        0,
      ),
    }));
    const clusterAnchors: Point[] = [
      [225, 155],
      [735, 145],
      [735, 365],
      [225, 365],
      [fieldWidth / 2, fieldHeight / 2],
    ];
    const clusterSimulation = voronoiMapSimulation<MacroClusterDatum>(clusters)
      .clip(fieldPolygon)
      .weight((cluster) => cluster.weight)
      .initialPosition((_cluster, index) => clusterAnchors[index] ?? [fieldWidth / 2, fieldHeight / 2])
      .convergenceRatio(0.00008)
      .maxIterationCount(180)
      .prng(seededRandom(0x43454c4c))
      .stop();
    for (let iteration = 0; iteration < 130; iteration += 1) {
      clusterSimulation.tick();
    }

    return clusterSimulation.state().polygons.flatMap((clusterPolygon) => {
      const clusterDatum = clusterPolygon.site.originalObject.data.originalData;
      const groupIndex = Number(clusterDatum.text.replace("cluster-", ""));
      const group = macroSemanticGroups[groupIndex];
      if (!group) return [];
      const polygon = [...clusterPolygon] as Point[];
      const clusterCenter = visualCenter(polygon).point;

      if (group.includes("#environment")) {
        return group.flatMap((text, index) => {
          const word = wordsByText.get(text);
          if (!word) return [];
          return [{
            text,
            weight: word.weight,
            polygon,
            x: fieldWidth / 2,
            y: index === 0 ? fieldHeight / 2 : fieldHeight - 48,
            fontSize: index === 0 ? 46 : 23,
          }];
        });
      }

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
    const fixed = new Set(["#environment", "@background"]);
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

  const cells = resolveMacroTextCollisions(makeClusteredMacroCells());
  let macroCloudElement: HTMLElement;
  let macroAudioRoute: RangeSoundRoute | undefined;
  let macroTail: MacroTail | undefined;
  let macroRouteOpen = false;
  let activeMacroWords = $state<[string | undefined, string | undefined]>([undefined, undefined]);
  let macroVisualEnvelopes = $state<[MacroVisualEnvelope | undefined, MacroVisualEnvelope | undefined]>([undefined, undefined]);
  let macroVisualTime = $state(0);
  let macroGroupPulse = $state<MacroGroupPulse | undefined>();
  let macroGroupPulseId = 0;
  let macroChords: [MacroChord | undefined, MacroChord | undefined] = [undefined, undefined];
  let macroChordActive = $state(false);
  let macroTrackLastGroups = [undefined] as (number | undefined)[];
  let macroClockwiseGroupPosition = 0;
  const macroClockwiseDirections = [1];
  let macroSequenceTick = 0;
  let macroNextNoteTick = macroSequenceStartOffset;
  let macroNextSupportTick = macroSequenceStartOffset;
  let macroBackgroundSubdivisionIndex = 0;
  let macroReleaseTick = -1;
  let macroSupportReleaseTick = -1;
  let macroClockInitialized = false;
  let macroGroupNoteIndex = 0;
  let macroPatternDirection = 1;

  function macroTone(text: string) {
    if (text === "#environment") return "macroLilac";
    if (text === "@background") return "macroYellow";
    if (["@equatable", "@codable", "@comparable", "@hashable"].includes(text)) return "macroLilac";
    if (text === "@app" || text === "@component" || text === "@page") return "macroAmber";
    if (text === "@project" || text === "@command" || text === "@commandGroup") return "macroGrape";
    if (["@graph", "@syntax", "@stored", "@capture"].includes(text)) return "macroCyan";
    if (["@construct", "@enum", "@function", "@extension"].includes(text)) return "macroCoral";
    if (["@let", "@state", "@derived", "@property", "@value"].includes(text)) return "macroBlue";
    if (["@member", "@parameter", "@self", "@type", "@variadic"].includes(text)) return "macroMint";
    if (["@literal", "@string", "@integer", "@bool", "@array", "@void"].includes(text)) return "macroYellow";
    if (["@if", "@while", "@break", "@continue", "@return", "@statement", "@defer"].includes(text)) return "macroRed";
    if (["@macro", "@init", "@assignment", "@case", "@llvm"].includes(text)) return "macroPink";
    if (["@registrable", "@encoding", "@description"].includes(text)) return "macroTeal";
    return "macroBlue";
  }

  function macroCellActivation(text: string) {
    return macroVisualEnvelopes.reduce((strongest, envelope) => {
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

  function macroBranchActivation(edge: MacroTreeEdge) {
    return edge.activationWords.reduce(
      (strongest, word) => Math.max(strongest, macroCellActivation(word)),
      0,
    );
  }

  function createMacroTail(audio: AudioContext, destination: AudioNode) {
    const input = audio.createGain();
    const tone = audio.createBiquadFilter();
    const convolver = audio.createConvolver();
    const wet = audio.createGain();
    const duration = 3.6;
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
        samples[index] = (random() * 2 - 1) * Math.pow(1 - progress, 3.4);
      }
    }
    tone.type = "lowpass";
    tone.frequency.value = 1_450;
    tone.Q.value = 0.55;
    convolver.buffer = impulse;
    wet.gain.value = 0.28;
    input.connect(destination);
    input.connect(tone).connect(convolver).connect(wet).connect(destination);
    return { input, tone, convolver, wet } satisfies MacroTail;
  }

  async function ensureMacroAudioRoute() {
    const manager = soundManager;
    if (!manager?.isEnabled()) return;
    const audio = await manager.resume();
    if (!audio) return;
    if (!macroAudioRoute) {
      macroAudioRoute = manager.register("range-macros", 0.0001);
      macroTail = createMacroTail(audio, macroAudioRoute.input);
    }
    if (macroAudioRoute && !macroRouteOpen) {
      const now = audio.currentTime;
      const routeGain = macroAudioRoute.input.gain;
      routeGain.cancelScheduledValues(now);
      routeGain.setValueAtTime(Math.max(0.0001, routeGain.value), now);
      routeGain.exponentialRampToValueAtTime(macroRouteLevel, now + 0.9);
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
    const now = macroAudioRoute?.audioContext.currentTime ?? 0;
    if (macroAudioRoute) {
      const routeGain = macroAudioRoute.input.gain;
      routeGain.cancelScheduledValues(now);
      routeGain.setTargetAtTime(0.0001, now, 1.4);
      macroRouteOpen = false;
    }
    macroChords.forEach((chord) => {
      if (!chord) return;
      chord.gains.forEach((gain) => {
        gain.gain.cancelScheduledValues(now);
        gain.gain.setTargetAtTime(0.0001, now, 0.08);
      });
      chord.oscillators.forEach((oscillator) => oscillator.stop(now + 0.3));
      chord.filters.forEach((filter) => filter.disconnect());
      chord.panners.forEach((panner) => panner.disconnect());
    });
    releaseMacroVisualEnvelopes(now, 0.08);
    macroChords = [undefined, undefined];
    macroChordActive = false;
    activeMacroWords = [undefined, undefined];
    macroGroupPulse = undefined;
  }

  function releaseMacroNote(trackIndex: number) {
    const now = macroAudioRoute?.audioContext.currentTime ?? 0;
    const activeWord = activeMacroWords[trackIndex];
    const releaseTimeConstant = activeWord === "#environment"
      ? 0.28
      : activeWord === "@background"
        ? 0.24
        : 0.85;
    macroChords[trackIndex]?.gains.forEach((gain) => {
      gain.gain.cancelScheduledValues(now);
      gain.gain.setTargetAtTime(0.0001, now, releaseTimeConstant);
    });
    releaseMacroVisualEnvelope(trackIndex, now, releaseTimeConstant);
    const nextActiveWords = [...activeMacroWords] as [string | undefined, string | undefined];
    nextActiveWords[trackIndex] = undefined;
    activeMacroWords = nextActiveWords;
    macroChordActive = nextActiveWords.some(Boolean);
  }

  function macroAttackTimeConstant(word: string, holdSeconds: number) {
    if (word === "#environment") return 0.065;
    if (word === "@background") return 0.022;
    return Math.min(0.12, holdSeconds * 0.3);
  }

  let environmentNoiseSeed = 0x454e5652;
  function playEnvironmentAir(
    audio: AudioContext,
    now: number,
    destination: AudioNode,
  ) {
    const duration = 0.82;
    const frameCount = Math.floor(audio.sampleRate * duration);
    const buffer = audio.createBuffer(2, frameCount, audio.sampleRate);
    const random = () => {
      environmentNoiseSeed = (
        environmentNoiseSeed * 1664525 + 1013904223
      ) >>> 0;
      return environmentNoiseSeed / 4294967296;
    };
    for (let channel = 0; channel < buffer.numberOfChannels; channel += 1) {
      const samples = buffer.getChannelData(channel);
      let smoothed = 0;
      for (let index = 0; index < samples.length; index += 1) {
        smoothed += ((random() * 2 - 1) - smoothed) * 0.34;
        samples[index] = smoothed;
      }
    }

    const source = audio.createBufferSource();
    const airBand = audio.createBiquadFilter();
    const airTone = audio.createBiquadFilter();
    const airGain = audio.createGain();
    source.buffer = buffer;
    airBand.type = "bandpass";
    airBand.frequency.value = 1_420;
    airBand.Q.value = 0.62;
    airTone.type = "lowpass";
    airTone.frequency.value = 3_200;
    airTone.Q.value = 0.4;
    airGain.gain.setValueAtTime(0.0001, now);
    airGain.gain.exponentialRampToValueAtTime(0.075, now + 0.13);
    airGain.gain.setTargetAtTime(0.052, now + 0.16, 0.18);
    airGain.gain.exponentialRampToValueAtTime(0.0001, now + duration);
    source.connect(airBand).connect(airTone).connect(airGain).connect(destination);
    source.start(now);
    source.stop(now + duration + 0.02);
    source.addEventListener("ended", () => {
      source.disconnect();
      airBand.disconnect();
      airTone.disconnect();
      airGain.disconnect();
    }, { once: true });
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
    if (!macroChords[trackIndex]) {
      const oscillators: OscillatorNode[] = [];
      const filters: BiquadFilterNode[] = [];
      const gains: GainNode[] = [];
      const panners: StereoPannerNode[] = [];
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
        oscillator
          .connect(filter)
          .connect(gain)
          .connect(panner)
          .connect(macroTail?.input ?? macroAudioRoute.input);
        oscillator.start(now);
        oscillators.push(oscillator);
        filters.push(filter);
        gains.push(gain);
        panners.push(panner);
      }
      macroChords[trackIndex] = { oscillators, filters, gains, panners };
    }

    const chord = macroChords[trackIndex];
    if (!chord) return false;
    chord.oscillators.forEach((oscillator, voiceIndex) => {
      const gain = chord.gains[voiceIndex];
      if (!gain) return;
      oscillator.type = environmentHit
        ? "sine"
        : backgroundSupport
          ? (voiceIndex === 0 ? "square" : "triangle")
          : (voiceIndex === 0 ? "triangle" : "sawtooth");
      const detuneSide = voiceIndex === 0 ? -1 : 1;
      oscillator.detune.setValueAtTime(
        detuneSide * (environmentHit ? 3.5 : backgroundSupport ? 1.2 : 3.5),
        now,
      );
      const panner = chord.panners[voiceIndex];
      if (panner) {
        const side = voiceIndex === 0 ? -1 : 1;
        panner.pan.cancelScheduledValues(now);
        if (environmentHit) {
          panner.pan.setValueAtTime(side * 0.08, now);
          panner.pan.linearRampToValueAtTime(
            side * 0.84,
            now + Math.max(0.16, holdSeconds * 0.92),
          );
        } else {
          panner.pan.setValueAtTime(
            side * (backgroundSupport ? 0.12 : 0.24),
            now,
          );
        }
      }
      gain.gain.cancelScheduledValues(now);
      const level = (environmentHit ? 0.18 : backgroundSupport ? 0.16 : 0.032)
        * (0.56 + intensity * 0.28);
      const voiceLevel = level * (
        environmentHit
          ? (voiceIndex === 0 ? 0.62 : 0.38)
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
      const octaveOffset = backgroundSupport ? 36 : environmentHit ? 27 : 0;
      const target = macroRoot * Math.pow(2, (noteStep - octaveOffset) / 12);
      const voiceTarget = target * (
        (environmentHit || backgroundSupport) && voiceIndex === 1 ? 2 : 1
      );
      oscillator.frequency.cancelScheduledValues(now);
      oscillator.frequency.setValueAtTime(voiceTarget, now);
      const filter = chord.filters[voiceIndex];
      if (filter) {
        filter.Q.value = environmentHit
          ? (voiceIndex === 0 ? 0.85 : 0.65)
          : backgroundSupport
            ? (voiceIndex === 0 ? 0.72 : 0.55)
          : (voiceIndex === 0 ? 2.2 : 1.65);
        filter.frequency.cancelScheduledValues(now);
        const restingCutoff = backgroundSupport
          ? Math.max(340, Math.min(720, voiceTarget * 8.2))
          : environmentHit
          ? Math.max(480, Math.min(1_050, voiceTarget * 8.4))
          : Math.max(720, Math.min(1_900, target * 2.4));
        const peakCutoff = backgroundSupport
          ? Math.max(820, Math.min(1_450, voiceTarget * 24))
          : environmentHit
          ? Math.max(1_200, Math.min(2_100, voiceTarget * 26))
          : Math.max(1_100, Math.min(3_400, target * 5.2));
        filter.frequency.setValueAtTime(restingCutoff, now);
        filter.frequency.setTargetAtTime(
          peakCutoff,
          now,
          backgroundSupport ? 0.035 : environmentHit ? 0.14 : 0.075,
        );
        filter.frequency.setTargetAtTime(
          restingCutoff,
          now + Math.min(
            backgroundSupport ? 0.7 : environmentHit ? 0.12 : 0.24,
            holdSeconds * 0.42,
          ),
          backgroundSupport ? 0.18 : environmentHit ? 0.16 : 0.38,
        );
      }
    });

    if (environmentHit) {
      playEnvironmentAir(
        audio,
        now,
        macroTail?.input ?? macroAudioRoute.input,
      );
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
    if (groupIndex === 4) return 2;
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
      // Two environment hits consume four ticks; 32 silent ticks complete
      // an exact 36-tick recurrence from one first hit to the next.
      const groupRestTicks = groupIndex === 4 ? 32 : macroGroupRestTicks;
      macroNextNoteTick = macroSequenceTick
        + intervalTicks
        + groupRestTicks;
    } else {
      macroNextNoteTick = macroSequenceTick + intervalTicks;
    }
    return true;
  }

  function activateBackgroundSupport(onsetTime: number | undefined) {
    const holdTicks = macroBackgroundHoldPattern[macroBackgroundSubdivisionIndex]
      ?? macroBackgroundHoldPattern[0];
    const holdSeconds = (RANGE_RHYTHM_SUBDIVISION_MS / 1_000)
      * holdTicks;
    if (!activateMacroNote(
      1,
      "@background",
      0,
      0.42,
      holdSeconds,
      onsetTime,
    )) return false;
    macroSupportReleaseTick = macroSequenceTick + holdTicks;
    macroBackgroundSubdivisionIndex = (
      macroBackgroundSubdivisionIndex + 1
    ) % macroBackgroundHoldPattern.length;
    macroNextSupportTick = macroSequenceTick + macroBackgroundStepTicks;
    return true;
  }

  onMount(() => {
    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
    if (reducedMotion.matches) return;

    let visible = false;
    let envelopeFrame = 0;
    const updateVisualEnvelope = () => {
      if (macroAudioRoute) macroVisualTime = macroAudioRoute.audioContext.currentTime;
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
        macroBackgroundSubdivisionIndex = 0;
        macroReleaseTick = -1;
        macroSupportReleaseTick = -1;
        macroClockInitialized = false;
        macroGroupNoteIndex = 0;
        macroPatternDirection = 1;
      }
    };
    const start = async () => {
      if (!visible || document.hidden) return;
      await ensureMacroAudioRoute();
    };
    const observer = new IntersectionObserver(
      ([entry]) => {
        visible = entry?.isIntersecting ?? false;
        if (visible) void start();
        else stop(true);
      },
      { rootMargin: "14% 0px 14%" },
    );
    const unsubscribeSound = soundManager?.subscribe((enabled) => {
      if (!enabled) {
        stopMacroTracks();
      } else if (visible && !document.hidden) {
        void start();
      }
    });
    const unsubscribeRhythm = soundManager?.subscribeRhythmBeat?.(({ step, tick, audioTime }) => {
      if (!visible || document.hidden) return;
      if (!macroClockInitialized) {
        macroSequenceTick = tick;
        macroNextNoteTick = tick + macroSequenceStartOffset;
        macroNextSupportTick = tick + macroSequenceStartOffset;
        macroBackgroundSubdivisionIndex = 0;
        macroReleaseTick = -1;
        macroSupportReleaseTick = -1;
        macroClockInitialized = true;
      } else {
        macroSequenceTick = tick;
      }
      if (macroReleaseTick >= 0 && macroSequenceTick >= macroReleaseTick) {
        releaseMacroNote(0);
        macroReleaseTick = -1;
      }
      if (
        macroSupportReleaseTick >= 0
        && macroSequenceTick >= macroSupportReleaseTick
      ) {
        releaseMacroNote(1);
        macroSupportReleaseTick = -1;
      }
      const strikesVertex = step % 3 === 0 || step % 4 === 0 || step % 6 === 0;
      const strikesBackgroundVertex = step % 4 === 0;
      if (strikesBackgroundVertex && macroSequenceTick >= macroNextSupportTick) {
        activateBackgroundSupport(audioTime);
      }
      if (strikesVertex && macroSequenceTick >= macroNextNoteTick) {
        advanceMacroActivation(audioTime);
      }
    });
    const handleVisibilityChange = () => {
      if (document.hidden) stop(false);
      else void start();
    };
    observer.observe(macroCloudElement);
    document.addEventListener("visibilitychange", handleVisibilityChange);
    return () => {
      stop();
      cancelAnimationFrame(envelopeFrame);
      observer.disconnect();
      unsubscribeSound?.();
      unsubscribeRhythm?.();
      document.removeEventListener("visibilitychange", handleVisibilityChange);
    };
  });

  onDestroy(() => {
    stopMacroTracks();
    macroTail?.input.disconnect();
    macroTail?.tone.disconnect();
    macroTail?.convolver.disconnect();
    macroTail?.wet.disconnect();
    macroAudioRoute?.dispose();
  });
</script>

<section class="macroCloud" aria-label="Macros" bind:this={macroCloudElement}>
  <svg
    class="macroCloudGraphic"
    viewBox={`0 0 ${fieldWidth} ${fieldHeight}`}
    role="img"
    aria-label="Weighted cellular field of Range macro families, with related macro forms activating in sequence"
  >
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
    {#each cells as cell (cell.text)}
      {@const activation = macroCellActivation(cell.text)}
      {@const tone = macroTone(cell.text)}
      <g class="macroKey">
        <text
          class={`macroCellLabel ${tone ?? ""}`}
          x={cell.x}
          y={cell.y}
          font-size={cell.fontSize}
          font-weight={cell.weight >= 80 ? 650 : 540}
          text-anchor="middle"
          dominant-baseline="central"
        >{cell.text}</text>
        <text
          class={`macroCellGlow ${tone ?? ""}`}
          style={`--activation: ${activation}`}
          x={cell.x}
          y={cell.y}
          font-size={cell.fontSize}
          font-weight={cell.weight >= 80 ? 650 : 540}
          text-anchor="middle"
          dominant-baseline="central"
          aria-hidden="true"
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

  .macroCellLabel {
    fill: white;
    transition: fill 1.4s cubic-bezier(0.22, 0.61, 0.36, 1);
  }

  .macroCellLabel.macroLilac { fill: oklch(0.82 0.09 307); }
  .macroCellLabel.macroAmber { fill: oklch(0.84 0.1 74); }
  .macroCellLabel.macroGrape { fill: oklch(0.79 0.09 315); }
  .macroCellLabel.macroCyan { fill: oklch(0.83 0.08 220); }
  .macroCellLabel.macroPink { fill: oklch(0.82 0.08 350); }
  .macroCellLabel.macroYellow { fill: oklch(0.88 0.09 92); }

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

  .macroCellGlow {
    fill: var(--range);
    opacity: calc(var(--activation) * 0.92);
    filter: drop-shadow(0 0 5px color-mix(in oklch, var(--range), transparent 28%));
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
