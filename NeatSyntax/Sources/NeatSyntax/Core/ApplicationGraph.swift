import Foundation

public struct ParsedSourceFile {
    public let path: String
    public let sourceFile: SourceFileNode

    public init(path: String, sourceFile: SourceFileNode) {
        self.path = path
        self.sourceFile = sourceFile
    }
}

public enum ApplicationGraphNodeKind: String {
    case file
    case construct
    case enumeration
    case protocolDefinition
    case macro
    case typeExtension
    case mainBlock
    case state
    case environment
    case binding
    case derived
    case value
    case initializer
    case function
    case parameter
    case member
    case typeReference
    case macroApplication

    public var semanticKind: SemanticGraphEntityKind {
        switch self {
        case .file: return .file
        case .construct: return .construct
        case .enumeration: return .enumeration
        case .protocolDefinition: return .protocolDefinition
        case .macro: return .macro
        case .typeExtension: return .typeExtension
        case .mainBlock: return .mainBlock
        case .state: return .state
        case .environment: return .environment
        case .binding: return .binding
        case .derived: return .derived
        case .value: return .value
        case .initializer: return .initializer
        case .function: return .function
        case .parameter: return .parameter
        case .member: return .member
        case .typeReference: return .typeReference
        case .macroApplication: return .macroApplication
        }
    }
}

public struct ApplicationGraphNode: Hashable {
    public let id: String
    public let kind: ApplicationGraphNodeKind
    public let label: String

    public var semanticKind: SemanticGraphEntityKind {
        kind.semanticKind
    }
}

public enum ApplicationGraphEdgeKind: String {
    case contains
    case conformsTo
    case extends
    case referencesType
    case referencesIdentity
    case appliesMacro
    case targetsMacro
    case resolvesTo
    case dependsOn
    case mutates
    case aliases
    case calls

    public var semanticKind: SemanticGraphRelationKind {
        switch self {
        case .contains: return .contains
        case .conformsTo: return .conformsTo
        case .extends: return .extends
        case .referencesType: return .referencesType
        case .referencesIdentity: return .referencesIdentity
        case .appliesMacro: return .appliesMacro
        case .targetsMacro: return .targetsMacro
        case .resolvesTo: return .resolvesTo
        case .dependsOn: return .dependsOn
        case .mutates: return .mutates
        case .aliases: return .aliases
        case .calls: return .calls
        }
    }
}

public struct ApplicationGraphEdge: Hashable {
    public let sourceID: String
    public let targetID: String
    public let kind: ApplicationGraphEdgeKind

    public var semanticKind: SemanticGraphRelationKind {
        kind.semanticKind
    }
}

public struct ApplicationGraph {
    public let nodes: [ApplicationGraphNode]
    public let edges: [ApplicationGraphEdge]

    public init(nodes: [ApplicationGraphNode], edges: [ApplicationGraphEdge]) {
        self.nodes = nodes.sorted {
            if $0.kind.rawValue != $1.kind.rawValue {
                return $0.kind.rawValue < $1.kind.rawValue
            }
            return $0.id < $1.id
        }
        self.edges = edges.sorted {
            if $0.sourceID != $1.sourceID {
                return $0.sourceID < $1.sourceID
            }
            if $0.kind.rawValue != $1.kind.rawValue {
                return $0.kind.rawValue < $1.kind.rawValue
            }
            return $0.targetID < $1.targetID
        }
    }

    public func render() -> String {
        let nodeLines = nodes.map { node in
            "  [\(node.kind.rawValue)] \(node.id) :: \(node.label)"
        }
        let edgeLines = edges.map { edge in
            "  \(edge.sourceID) -\(edge.kind.rawValue)-> \(edge.targetID)"
        }

        return """
                Nodes:
                \(nodeLines.joined(separator: "\n"))

                Edges:
                \(edgeLines.joined(separator: "\n"))
            """
    }

    public func renderHTML(title: String = "Neat Application Graph") -> String {
        let payload = makeHTMLPayload()

        return """
            <!doctype html>
            <html lang="en">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <title>\(escapeHTML(title))</title>
              <style>
                :root {
                  --bg: #f5f1e8;
                  --panel: rgba(255,255,255,0.82);
                  --ink: #1f1d1a;
                  --muted: #726a5f;
                  --line: rgba(48, 41, 34, 0.18);
                }
                * { box-sizing: border-box; }
                body {
                  margin: 0;
                  font-family: "Iowan Old Style", "Palatino Linotype", serif;
                  color: var(--ink);
                  background:
                    radial-gradient(circle at top left, rgba(193, 168, 135, 0.18), transparent 30%),
                    radial-gradient(circle at bottom right, rgba(112, 139, 159, 0.16), transparent 28%),
                    linear-gradient(180deg, #f8f4ed 0%, var(--bg) 100%);
                }
                .layout {
                  display: grid;
                  grid-template-columns: minmax(280px, 360px) 1fr;
                  min-height: 100vh;
                }
                .sidebar {
                  padding: 24px;
                  border-right: 1px solid rgba(48, 41, 34, 0.12);
                  background: var(--panel);
                  backdrop-filter: blur(10px);
                }
                h1 {
                  margin: 0 0 10px;
                  font-size: 28px;
                  line-height: 1.05;
                }
                .meta, .hint {
                  color: var(--muted);
                  font-size: 14px;
                  line-height: 1.4;
                }
                .legend {
                  margin-top: 22px;
                  display: grid;
                  gap: 10px;
                }
                .mode-switch {
                  margin-top: 18px;
                  display: inline-flex;
                  padding: 4px;
                  gap: 4px;
                  border-radius: 999px;
                  background: rgba(48, 41, 34, 0.08);
                }
                .mode-button {
                  border: 0;
                  border-radius: 999px;
                  padding: 8px 12px;
                  font: inherit;
                  font-size: 13px;
                  color: var(--muted);
                  background: transparent;
                  cursor: pointer;
                }
                .mode-button.active {
                  color: var(--ink);
                  background: rgba(255,255,255,0.92);
                  box-shadow: 0 1px 2px rgba(48, 41, 34, 0.1);
                }
                .legend-row {
                  display: flex;
                  align-items: center;
                  gap: 10px;
                  font-size: 14px;
                }
                .swatch {
                  width: 12px;
                  height: 12px;
                  border-radius: 999px;
                  box-shadow: inset 0 0 0 1px rgba(0,0,0,0.08);
                }
                .details {
                  margin-top: 24px;
                  padding: 14px;
                  border-radius: 18px;
                  background: rgba(255,255,255,0.78);
                  border: 1px solid rgba(48, 41, 34, 0.08);
                  min-height: 120px;
                }
                .details h2 {
                  margin: 0 0 8px;
                  font-size: 17px;
                }
                .details pre {
                  margin: 0;
                  white-space: pre-wrap;
                  word-break: break-word;
                  font-size: 13px;
                  color: var(--muted);
                }
                .canvas-wrap {
                  position: relative;
                  min-height: 100vh;
                  overflow: auto;
                  padding: 24px;
                  overscroll-behavior: contain;
                }
                svg {
                  display: block;
                  max-width: none;
                  max-height: none;
                }
                .edge {
                  stroke: var(--line);
                  stroke-width: 1.5;
                }
                .edge-label {
                  fill: #867a6a;
                  font-size: 11px;
                  text-anchor: middle;
                }
                .node {
                  cursor: pointer;
                  touch-action: none;
                  user-select: none;
                }
                .node circle {
                  stroke: rgba(33, 29, 25, 0.25);
                  stroke-width: 1.2;
                }
                .node text {
                  fill: #201d19;
                  font-size: 12px;
                  font-family: "SF Mono", "Menlo", monospace;
                  pointer-events: none;
                }
                .node .node-badge {
                  fill: #76716a;
                  font-weight: 700;
                }
                .node.selected circle {
                  stroke: #111;
                  stroke-width: 2.5;
                }
                .node.dragging {
                  cursor: grabbing;
                }
                @media (max-width: 900px) {
                  .layout { grid-template-columns: 1fr; }
                  .sidebar { border-right: 0; border-bottom: 1px solid rgba(48, 41, 34, 0.12); }
                }
              </style>
            </head>
            <body>
              <div class="layout">
                <aside class="sidebar">
                  <h1>\(escapeHTML(title))</h1>
                  <div class="meta">\(nodes.count) nodes, \(edges.count) edges</div>
                  <p class="hint">Structured by containment first, with related nodes pulled together. Drag nodes to inspect clusters and scroll when the graph grows.</p>
                  <div class="mode-switch" id="mode-switch">
                    <button class="mode-button active" data-mode="declaration">Declaration</button>
                    <button class="mode-button" data-mode="memory">Memory</button>
                  </div>
                  <div class="legend" id="legend"></div>
                  <section class="details">
                    <h2 id="details-title">Nothing selected</h2>
                    <pre id="details-body">Click a node to inspect its id, kind, and connected edges.</pre>
                  </section>
                </aside>
                <main class="canvas-wrap">
                  <svg id="graph" preserveAspectRatio="xMinYMin meet"></svg>
                </main>
              </div>
              <script>
                const payload = \(payload);
                const colorByKind = {
                  file: "#577590",
                  construct: "#c8553d",
                  enumeration: "#9c6644",
                  protocolDefinition: "#6d597a",
                  macro: "#355070",
                  typeExtension: "#4d908e",
                  mainBlock: "#e9c46a",
                  state: "#bc6c25",
                  environment: "#90a955",
                  binding: "#7f5539",
                  derived: "#2a9d8f",
                  value: "#b56576",
                  initializer: "#6c757d",
                  function: "#3a86ff",
                  parameter: "#8d99ae",
                  member: "#588157",
                  typeReference: "#adb5bd",
                  macroApplication: "#f28482"
                };

                const nodes = payload.nodes.map((node, index) => ({
                  ...node,
                  attachedTypes: [],
                  x: 0,
                  y: 0,
                  vx: 0,
                  vy: 0,
                  index
                }));
                const nodesById = new Map(nodes.map(node => [node.id, node]));
                const rawEdges = payload.edges.map(edge => ({
                  ...edge,
                  source: nodesById.get(edge.sourceID),
                  target: nodesById.get(edge.targetID)
                })).filter(edge => edge.source && edge.target);

                const attachedTypeOwnerIDsByTypeID = new Map();
                for (const edge of rawEdges) {
                  const isAttachedTypeEdge = (edge.kind === "referencesType" || edge.kind === "referencesIdentity" || edge.kind === "conformsTo")
                    && edge.target.kind === "typeReference";
                  if (!isAttachedTypeEdge) continue;
                  edge.source.attachedTypes.push(edge.target.label);
                  if (!attachedTypeOwnerIDsByTypeID.has(edge.targetID)) {
                    attachedTypeOwnerIDsByTypeID.set(edge.targetID, []);
                  }
                  attachedTypeOwnerIDsByTypeID.get(edge.targetID).push(edge.sourceID);
                }

                for (const node of nodes) {
                  if (node.attachedTypes.length > 1) {
                    node.attachedTypes.sort((a, b) => a.localeCompare(b));
                  }
                }

                const hiddenNodeIDs = new Set(attachedTypeOwnerIDsByTypeID.keys());
                const visibleNodes = nodes.filter(node => !hiddenNodeIDs.has(node.id));
                const visibleNodesById = new Map(visibleNodes.map(node => [node.id, node]));

                const reroutedEdges = [];
                for (const edge of rawEdges) {
                  if (edge.kind !== "resolvesTo" || !hiddenNodeIDs.has(edge.sourceID)) continue;
                  const ownerIDs = attachedTypeOwnerIDsByTypeID.get(edge.sourceID) || [];
                  for (const ownerID of ownerIDs) {
                    const owner = visibleNodesById.get(ownerID);
                    const target = visibleNodesById.get(edge.targetID);
                    if (!owner || !target) continue;
                    reroutedEdges.push({
                      sourceID: ownerID,
                      targetID: edge.targetID,
                      kind: edge.kind,
                      source: owner,
                      target
                    });
                  }
                }

                const edges = rawEdges
                  .filter(edge => {
                    if (hiddenNodeIDs.has(edge.sourceID) || hiddenNodeIDs.has(edge.targetID)) {
                      return false;
                    }
                    return true;
                  })
                  .map(edge => ({
                    ...edge,
                    source: visibleNodesById.get(edge.sourceID),
                    target: visibleNodesById.get(edge.targetID)
                  }))
                  .filter(edge => edge.source && edge.target);
                edges.push(...reroutedEdges);

                const svg = document.getElementById("graph");
                const detailsTitle = document.getElementById("details-title");
                const detailsBody = document.getElementById("details-body");
                const legend = document.getElementById("legend");
                const modeSwitch = document.getElementById("mode-switch");

                const edgeLayer = document.createElementNS("http://www.w3.org/2000/svg", "g");
                const edgeLabelLayer = document.createElementNS("http://www.w3.org/2000/svg", "g");
                const nodeLayer = document.createElementNS("http://www.w3.org/2000/svg", "g");
                svg.append(edgeLayer, edgeLabelLayer, nodeLayer);

                const kinds = [...new Set(visibleNodes.map(node => node.kind))].sort();
                for (const kind of kinds) {
                  const row = document.createElement("div");
                  row.className = "legend-row";
                  row.innerHTML = `<span class="swatch" style="background:${colorByKind[kind] || "#999"}"></span><span>${kind}</span>`;
                  legend.append(row);
                }

                const edgeElements = edges.map(edge => {
                  const line = document.createElementNS("http://www.w3.org/2000/svg", "line");
                  line.setAttribute("class", "edge");
                  edgeLayer.append(line);

                  const label = document.createElementNS("http://www.w3.org/2000/svg", "text");
                  label.setAttribute("class", "edge-label");
                  label.textContent = edge.kind;
                  edgeLabelLayer.append(label);

                  return { edge, line, label };
                });

                let selectedNode = null;
                let draggedNode = null;
                let svgWidth = 1600;
                let svgHeight = 1200;

                const neighborsById = new Map(visibleNodes.map(node => [node.id, new Set()]));
                const containsParents = new Map();
                const containsChildren = new Map(visibleNodes.map(node => [node.id, []]));
                for (const edge of edges) {
                  neighborsById.get(edge.sourceID)?.add(edge.targetID);
                  neighborsById.get(edge.targetID)?.add(edge.sourceID);
                  if (edge.kind === "contains") {
                    containsParents.set(edge.targetID, edge.sourceID);
                    containsChildren.get(edge.sourceID)?.push(edge.targetID);
                  }
                }

                const kindPriority = new Map([
                  ["file", 0],
                  ["mainBlock", 1],
                  ["construct", 2],
                  ["enumeration", 3],
                  ["protocolDefinition", 4],
                  ["macro", 5],
                  ["typeExtension", 6],
                  ["state", 7],
                  ["environment", 8],
                  ["value", 9],
                  ["binding", 10],
                  ["derived", 11],
                  ["initializer", 12],
                  ["function", 13],
                  ["parameter", 14],
                  ["member", 15],
                  ["macroApplication", 16],
                  ["typeReference", 17]
                ]);

                function hashString(value) {
                  let hash = 2166136261;
                  for (let index = 0; index < value.length; index += 1) {
                    hash ^= value.charCodeAt(index);
                    hash = Math.imul(hash, 16777619);
                  }
                  return hash >>> 0;
                }

                function seededUnit(value, salt) {
                  const hash = hashString(`${value}:${salt}`);
                  return (hash % 10000) / 10000;
                }

                function sortedChildren(nodeID) {
                  return [...(containsChildren.get(nodeID) || [])]
                    .map(id => nodesById.get(id))
                    .filter(Boolean)
                    .sort((a, b) => {
                      const priorityDiff = (kindPriority.get(a.kind) ?? 999) - (kindPriority.get(b.kind) ?? 999);
                      if (priorityDiff !== 0) return priorityDiff;
                      const labelDiff = a.label.localeCompare(b.label);
                      if (labelDiff !== 0) return labelDiff;
                      return a.id.localeCompare(b.id);
                    });
                }

                function rootNodes() {
                  return visibleNodes
                    .filter(node => !containsParents.has(node.id))
                    .sort((a, b) => {
                      const priorityDiff = (kindPriority.get(a.kind) ?? 999) - (kindPriority.get(b.kind) ?? 999);
                      if (priorityDiff !== 0) return priorityDiff;
                      const labelDiff = a.label.localeCompare(b.label);
                      if (labelDiff !== 0) return labelDiff;
                      return a.id.localeCompare(b.id);
                    });
                }

                function measureSubtree(nodeID, depth = 0, visited = new Set()) {
                  if (visited.has(nodeID)) return 1;
                  visited.add(nodeID);
                  const children = sortedChildren(nodeID);
                  if (children.length === 0) return 1;
                  let width = 0;
                  for (const child of children) {
                    width += measureSubtree(child.id, depth + 1, visited);
                  }
                  return Math.max(1, width);
                }

                function positionSubtree(nodeID, centerX, topY, visited = new Set()) {
                  if (visited.has(nodeID)) return;
                  visited.add(nodeID);

                  const node = nodesById.get(nodeID);
                  if (!node) return;
                  node.x = centerX;
                  node.y = topY;

                  const children = sortedChildren(nodeID);
                  if (children.length === 0) return;

                  const columnWidth = 180;
                  const rowHeight = 150;
                  const widths = children.map(child => measureSubtree(child.id));
                  const totalWidth = widths.reduce((sum, width) => sum + width, 0) * columnWidth;
                  let cursor = centerX - totalWidth / 2;

                  children.forEach((child, index) => {
                    const subtreeWidth = widths[index] * columnWidth;
                    const childCenterX = cursor + subtreeWidth / 2;
                    positionSubtree(child.id, childCenterX, topY + rowHeight, visited);
                    cursor += subtreeWidth;
                  });
                }

                function placeDetachedNodes(startX, startY) {
                  const placed = new Set();
                  for (const node of visibleNodes) {
                    if (Number.isFinite(node.x) && Number.isFinite(node.y) && (node.x !== 0 || node.y !== 0)) {
                      placed.add(node.id);
                    }
                  }

                  const detached = visibleNodes
                    .filter(node => !placed.has(node.id))
                    .sort((a, b) => a.label.localeCompare(b.label) || a.id.localeCompare(b.id));

                  detached.forEach((node, index) => {
                    node.x = startX + (index % 4) * 180;
                    node.y = startY + Math.floor(index / 4) * 140;
                  });
                }

                function initializeLayout() {
                  const roots = rootNodes();
                  const columnWidth = 220;
                  const rootGap = 140;
                  let cursorX = 180;
                  let maxDepthY = 180;

                  for (const root of roots) {
                    const subtreeWidth = measureSubtree(root.id) * columnWidth;
                    const centerX = cursorX + subtreeWidth / 2;
                    positionSubtree(root.id, centerX, 140);
                    cursorX += subtreeWidth + rootGap;
                  }

                  for (const node of visibleNodes) {
                    maxDepthY = Math.max(maxDepthY, node.y);
                  }

                  placeDetachedNodes(220, maxDepthY + 180);
                }

                function runLayout(iterations = 140) {
                  if (visibleNodes.length === 0) return;

                  const idealEdgeLength = 165;
                  const repulsion = 22000;
                  const gravity = 0.0012;
                  const damping = 0.8;
                  const verticalBias = 0.08;

                  for (let step = 0; step < iterations; step += 1) {
                    for (const node of visibleNodes) {
                      node.vx *= 0.6;
                      node.vy *= 0.6;
                    }

                    for (let i = 0; i < visibleNodes.length; i += 1) {
                      for (let j = i + 1; j < visibleNodes.length; j += 1) {
                        const a = visibleNodes[i];
                        const b = visibleNodes[j];
                        let dx = b.x - a.x;
                        let dy = b.y - a.y;
                        let distanceSquared = dx * dx + dy * dy;
                        if (distanceSquared < 0.01) {
                          dx = 0.1 + seededUnit(a.id, b.id) * 0.2;
                          dy = 0.1 + seededUnit(b.id, a.id) * 0.2;
                          distanceSquared = dx * dx + dy * dy;
                        }
                        const distance = Math.sqrt(distanceSquared);
                        const force = repulsion / distanceSquared;
                        const fx = (dx / distance) * force;
                        const fy = (dy / distance) * force;
                        a.vx -= fx;
                        a.vy -= fy;
                        b.vx += fx;
                        b.vy += fy;
                      }
                    }

                    for (const edge of edges) {
                      const source = edge.source;
                      const target = edge.target;
                      const dx = target.x - source.x;
                      const dy = target.y - source.y;
                      const distance = Math.max(1, Math.sqrt(dx * dx + dy * dy));
                      const springStrength = edge.kind === "contains" ? 0.024 : 0.01;
                      const spring = (distance - idealEdgeLength) * springStrength;
                      const fx = (dx / distance) * spring;
                      const fy = (dy / distance) * spring;
                      source.vx += fx;
                      source.vy += fy;
                      target.vx -= fx;
                      target.vy -= fy;

                      if (edge.kind === "contains") {
                        const targetY = source.y + 145;
                        const yForce = (targetY - target.y) * verticalBias;
                        target.vy += yForce;
                        source.vy -= yForce * 0.12;
                      }
                    }

                    for (const node of visibleNodes) {
                      node.vx += (900 - node.x) * gravity;
                      node.vy += (500 - node.y) * gravity;
                      node.vx *= damping;
                      node.vy *= damping;
                      node.x += node.vx;
                      node.y += node.vy;
                    }
                  }
                }

                function updateCanvasBounds() {
                  if (visibleNodes.length === 0) {
                    svgWidth = 1200;
                    svgHeight = 900;
                    svg.setAttribute("viewBox", `0 0 ${svgWidth} ${svgHeight}`);
                    svg.setAttribute("width", String(svgWidth));
                    svg.setAttribute("height", String(svgHeight));
                    svg.style.width = `${svgWidth}px`;
                    svg.style.height = `${svgHeight}px`;
                    return;
                  }

                  const margin = 220;
                  const minX = Math.min(...visibleNodes.map(node => node.x)) - margin;
                  const maxX = Math.max(...visibleNodes.map(node => node.x)) + margin;
                  const minY = Math.min(...visibleNodes.map(node => node.y)) - margin;
                  const maxY = Math.max(...visibleNodes.map(node => node.y)) + margin;
                  svgWidth = Math.max(1200, maxX - minX);
                  svgHeight = Math.max(900, maxY - minY);
                  svg.setAttribute("viewBox", `${minX} ${minY} ${svgWidth} ${svgHeight}`);
                  svg.setAttribute("width", String(svgWidth));
                  svg.setAttribute("height", String(svgHeight));
                  svg.style.width = `${svgWidth}px`;
                  svg.style.height = `${svgHeight}px`;
                }

                const nodeElements = visibleNodes.map(node => {
                  const group = document.createElementNS("http://www.w3.org/2000/svg", "g");
                  group.setAttribute("class", "node");

                  const circle = document.createElementNS("http://www.w3.org/2000/svg", "circle");
                  circle.setAttribute("r", "16");
                  circle.setAttribute("fill", colorByKind[node.kind] || "#999");

                  const label = document.createElementNS("http://www.w3.org/2000/svg", "text");
                  label.setAttribute("x", "22");
                  label.setAttribute("y", "4");
                  label.textContent = node.label;

                  const badge = document.createElementNS("http://www.w3.org/2000/svg", "text");
                  badge.setAttribute("class", "node-badge");
                  badge.setAttribute("y", "4");
                  badge.textContent = node.attachedTypes.length > 0
                    ? `: ${node.attachedTypes.join(", ")}`
                    : "";

                  group.append(circle, label, badge);
                  nodeLayer.append(group);

                  group.addEventListener("click", () => selectNode(node));
                  group.addEventListener("pointerdown", event => {
                    draggedNode = node;
                    group.classList.add("dragging");
                    group.setPointerCapture(event.pointerId);
                  });
                  group.addEventListener("pointermove", event => {
                    if (!draggedNode || draggedNode !== node) return;
                    const point = svg.createSVGPoint();
                    point.x = event.clientX;
                    point.y = event.clientY;
                    const transformed = point.matrixTransform(svg.getScreenCTM().inverse());
                    node.x = transformed.x;
                    node.y = transformed.y;
                    updateCanvasBounds();
                    render();
                  });
                  group.addEventListener("pointerup", event => {
                    if (group.hasPointerCapture(event.pointerId)) {
                      group.releasePointerCapture(event.pointerId);
                    }
                    group.classList.remove("dragging");
                    draggedNode = null;
                  });
                  group.addEventListener("pointercancel", event => {
                    if (group.hasPointerCapture(event.pointerId)) {
                      group.releasePointerCapture(event.pointerId);
                    }
                    group.classList.remove("dragging");
                    draggedNode = null;
                  });

                  return { node, group, label, badge };
                });

                const declarationEdgeKinds = new Set([
                  "contains",
                  "conformsTo",
                  "extends",
                  "referencesType",
                  "referencesIdentity",
                  "appliesMacro",
                  "targetsMacro",
                  "resolvesTo"
                ]);
                const memoryEdgeKinds = new Set([
                  "contains",
                  "dependsOn",
                  "mutates",
                  "aliases",
                  "calls"
                ]);

                function isDeclarationNode(node) {
                  if (node.kind === "member") return false;
                  if (node.id.includes("/main/local:")) return false;
                  if (node.id.includes("/local-derived:")) return false;
                  if (node.id.includes("/call:")) return false;
                  return true;
                }

                function isMemoryNode(node) {
                  if (node.id.includes("/main/local:")) return true;
                  if (node.id.includes("/local-derived:")) return true;
                  if (node.id.includes("/call:")) return true;
                  if (node.kind === "member") return true;
                  if (node.kind === "mainBlock") return true;
                  if (node.kind === "function" || node.kind === "binding" || node.kind === "state" || node.kind === "derived") {
                    return true;
                  }
                  return false;
                }

                function applyMode(mode) {
                  const allowedEdgeKinds = mode === "memory" ? memoryEdgeKinds : declarationEdgeKinds;
                  const eligibleNodeIDs = new Set(
                    nodeElements
                      .filter(({ node }) => mode === "memory" ? isMemoryNode(node) : isDeclarationNode(node))
                      .map(({ node }) => node.id)
                  );

                  const visibleEdgeKeys = new Set();
                  const connectedNodeIDs = new Set();

                  for (const { edge, line, label } of edgeElements) {
                    const visible =
                      allowedEdgeKinds.has(edge.kind)
                      && eligibleNodeIDs.has(edge.sourceID)
                      && eligibleNodeIDs.has(edge.targetID);
                    line.style.display = visible ? "" : "none";
                    label.style.display = visible ? "" : "none";
                    if (visible) {
                      visibleEdgeKeys.add(`${edge.sourceID}:${edge.kind}:${edge.targetID}`);
                      connectedNodeIDs.add(edge.sourceID);
                      connectedNodeIDs.add(edge.targetID);
                    }
                  }

                  for (const { node, group } of nodeElements) {
                    const visible = connectedNodeIDs.has(node.id);
                    group.style.display = visible ? "" : "none";
                  }

                  for (const row of legend.children) {
                    const kind = row.getAttribute("data-kind");
                    const hasVisibleNode = nodeElements.some(({ node, group }) =>
                      node.kind === kind && group.style.display !== "none"
                    );
                    row.style.display = hasVisibleNode ? "" : "none";
                  }

                  if (selectedNode) {
                    const selectedVisible = connectedNodeIDs.has(selectedNode.id);
                    if (!selectedVisible) {
                      selectedNode = null;
                      detailsTitle.textContent = "Nothing selected";
                      detailsBody.textContent = "Click a node to inspect its id, kind, and connected edges.";
                    } else {
                      const connectedEdges = edges
                        .filter(edge => visibleEdgeKeys.has(`${edge.sourceID}:${edge.kind}:${edge.targetID}`))
                        .filter(edge => edge.sourceID === selectedNode.id || edge.targetID === selectedNode.id)
                        .map(edge => `${edge.sourceID} -${edge.kind}-> ${edge.targetID}`);

                      detailsTitle.textContent = selectedNode.label;
                      detailsBody.textContent = [
                        `kind: ${selectedNode.kind}`,
                        `id: ${selectedNode.id}`,
                        ...(selectedNode.attachedTypes.length > 0 ? [`type: ${selectedNode.attachedTypes.join(", ")}`] : []),
                        "",
                        "connected edges:",
                        ...(connectedEdges.length ? connectedEdges : ["  none"])
                      ].join("\\n");
                    }
                  }

                  for (const { node: current, group } of nodeElements) {
                    group.classList.toggle("selected", current === selectedNode && group.style.display !== "none");
                  }

                  for (const button of modeSwitch.querySelectorAll(".mode-button")) {
                    button.classList.toggle("active", button.dataset.mode === mode);
                  }
                }

                function selectNode(node) {
                  selectedNode = node;
                  for (const { node: current, group } of nodeElements) {
                    group.classList.toggle("selected", current === node);
                  }

                  const connectedEdges = edges
                    .filter(edge => edge.sourceID === node.id || edge.targetID === node.id)
                    .map(edge => `${edge.sourceID} -${edge.kind}-> ${edge.targetID}`);

                  detailsTitle.textContent = node.label;
                  detailsBody.textContent = [
                    `kind: ${node.kind}`,
                    `id: ${node.id}`,
                    ...(node.attachedTypes.length > 0 ? [`type: ${node.attachedTypes.join(", ")}`] : []),
                    "",
                    "connected edges:",
                    ...(connectedEdges.length ? connectedEdges : ["  none"])
                  ].join("\\n");
                }

                function render() {
                  updateCanvasBounds();
                  for (const { edge, line, label } of edgeElements) {
                    line.setAttribute("x1", edge.source.x);
                    line.setAttribute("y1", edge.source.y);
                    line.setAttribute("x2", edge.target.x);
                    line.setAttribute("y2", edge.target.y);
                    label.setAttribute("x", (edge.source.x + edge.target.x) / 2);
                    label.setAttribute("y", (edge.source.y + edge.target.y) / 2 - 6);
                  }

                  for (const { node, group, label, badge } of nodeElements) {
                    group.setAttribute("transform", `translate(${node.x}, ${node.y})`);
                    const labelWidth = label.getComputedTextLength();
                    badge.setAttribute("x", String(28 + labelWidth));
                  }
                }

                initializeLayout();
                runLayout();
                render();

                for (const row of legend.children) {
                  const kind = row.textContent?.trim() || "";
                  row.setAttribute("data-kind", kind);
                }

                for (const button of modeSwitch.querySelectorAll(".mode-button")) {
                  button.addEventListener("click", () => applyMode(button.dataset.mode || "declaration"));
                }

                applyMode("declaration");
              </script>
            </body>
            </html>
            """
    }

    private func makeHTMLPayload() -> String {
        let nodesPayload = nodes.map { node in
            [
                "id": node.id,
                "kind": node.kind.rawValue,
                "label": node.label,
            ]
        }
        let edgesPayload = edges.map { edge in
            [
                "sourceID": edge.sourceID,
                "targetID": edge.targetID,
                "kind": edge.kind.rawValue,
            ]
        }

        let payload: [String: Any] = [
            "nodes": nodesPayload,
            "edges": edgesPayload,
        ]

        guard
            let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
            let string = String(data: data, encoding: .utf8)
        else {
            return "{\"nodes\":[],\"edges\":[]}"
        }

        return string
    }

    private func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

public struct ApplicationGraphBuilder {
    private let passes: [any ApplicationGraphBuildPass] = [
        ApplicationGraphSeedPass(),
        ApplicationGraphFileAnalysisPass(),
        ApplicationGraphResolutionPass(),
    ]

    public init() {}

    public func build(program: CompiledProgram) -> ApplicationGraph {
        build(
            files: program.expandedFiles,
            declarationGraph: program.declarationGraph
        )
    }

    public func build(files: [ParsedSourceFile]) -> ApplicationGraph {
        build(
            files: files,
            declarationGraph: DeclarationGraph(files: files)
        )
    }

    public func build(
        files: [ParsedSourceFile],
        declarationGraph: DeclarationGraph
    ) -> ApplicationGraph {
        var collector = GraphCollector(declarationGraph: declarationGraph)
        let sortedFiles = files.sorted(by: { $0.path < $1.path })
        for pass in passes {
            pass.apply(to: &collector, files: sortedFiles)
        }
        return collector.materialize()
    }
}

private protocol ApplicationGraphBuildPass {
    var name: String { get }

    func apply(to collector: inout GraphCollector, files: [ParsedSourceFile])
}

private struct ApplicationGraphSeedPass: ApplicationGraphBuildPass {
    let name = "ApplicationGraphSeed"

    func apply(to collector: inout GraphCollector, files: [ParsedSourceFile]) {
        collector.seedDeclarationProjection()
    }
}

private struct ApplicationGraphFileAnalysisPass: ApplicationGraphBuildPass {
    let name = "ApplicationGraphFileAnalysis"

    func apply(to collector: inout GraphCollector, files: [ParsedSourceFile]) {
        for file in files {
            collector.add(file)
        }
    }
}

private struct ApplicationGraphResolutionPass: ApplicationGraphBuildPass {
    let name = "ApplicationGraphResolution"

    func apply(to collector: inout GraphCollector, files: [ParsedSourceFile]) {
        collector.resolveApplicationEdges()
    }
}

private struct GraphCollector {
    private let declarationGraph: DeclarationGraph
    private let baseSemanticGraph: SemanticGraph
    private let baseEntityIDs: Set<String>
    private let baseEdges: Set<ApplicationGraphEdge>
    private var nodesByID: [String: ApplicationGraphNode] = [:]
    private var edges: Set<ApplicationGraphEdge> = []
    private let registryView: DeclarationRegistryView
    private var resolutionIndex = DependencyResolutionIndex()
    private var flowState = DependencyFlowState()

    init(declarationGraph: DeclarationGraph) {
        self.declarationGraph = declarationGraph
        self.baseSemanticGraph = declarationGraph.semanticGraph
        self.baseEntityIDs = Set(declarationGraph.semanticGraph.entities.map(\.id))
        self.baseEdges = Set(
            declarationGraph.semanticGraph.relations.compactMap { relation in
                guard let applicationKind = Self.applicationEdgeKind(for: relation.kind) else {
                    return nil
                }
                return ApplicationGraphEdge(
                    sourceID: relation.sourceID,
                    targetID: relation.targetID,
                    kind: applicationKind
                )
            }
        )
        self.registryView = declarationGraph.registryView
    }

    mutating func seedDeclarationProjection() {
        indexBaseSemanticGraph()
    }

    mutating func resolveApplicationEdges() {
        addResolutionEdges()
    }

    func materialize() -> ApplicationGraph {
        let baseNodes = baseSemanticGraph.entities.compactMap { entity in
            applicationNode(for: entity)
        }
        return ApplicationGraph(
            nodes: baseNodes + Array(nodesByID.values),
            edges: Array(baseEdges.union(edges))
        )
    }

    mutating func add(_ parsedFile: ParsedSourceFile) {
        let fileID = "file:\(parsedFile.path)"

        switch parsedFile.sourceFile {
        case .construct(let declaration):
            analyzeConstructDeclaration(declaration, parentID: fileID)
        case .enumeration, .protocolDefinition, .macro, .extensions:
            return
        case .module(let module):
            let topLevelStates = declarationGraph.topLevelStates(inFilePath: parsedFile.path)
            for state in topLevelStates {
                analyzeStateDeclaration(state, parentID: fileID)
            }
            for declaration in module.constructs {
                analyzeConstructDeclaration(declaration, parentID: fileID)
            }
            let moduleScope = MemoryScope(
                symbols: Dictionary(uniqueKeysWithValues: topLevelStates.map { state in
                    (state.name, "\(fileID)/state:\(state.name)")
                })
            )
            for callable in module.callables {
                analyzeCallableDeclaration(callable, parentID: fileID, scope: moduleScope)
            }

            if let mainBlock = module.mainBlock {
                analyzeMainBlock(
                    mainBlock,
                    parentID: fileID,
                    topLevelStates: topLevelStates
                )
            }
        case .mainBlock(let mainBlock):
            analyzeMainBlock(mainBlock, parentID: fileID, topLevelStates: [])
        }
    }

    private mutating func analyzeConstructDeclaration(
        _ declaration: ConstructDeclaration,
        parentID: String
    ) {
        let constructID = "\(parentID)/construct:\(declaration.name)"
        let scope = makeScope(
            bindings: declaration.bindings.map { ($0.name, "\(constructID)/binding:\($0.name)") },
            deriveds: declaration.deriveds.map { ($0.name, "\(constructID)/derived:\($0.name)") },
            environments: declaration.environments.map {
                ($0.name, "\(constructID)/environment:\($0.name)")
            },
            states: declaration.states.map { ($0.name, "\(constructID)/state:\($0.name)") },
            values: declaration.values.map { ($0.name, "\(constructID)/value:\($0.name)") },
            selfID: constructID
        )

        for binding in declaration.bindings where declarationGraph.hasConstruct(named: binding.typeName) {
            flowState.inferredConstructTypeByNodeID["\(constructID)/binding:\(binding.name)"] =
                binding.typeName
        }
        for value in declaration.values where declarationGraph.hasConstruct(named: value.typeName) {
            flowState.inferredConstructTypeByNodeID["\(constructID)/value:\(value.name)"] =
                value.typeName
        }
        for state in declaration.states {
            analyzeStateDeclaration(state, parentID: constructID)
        }
        for derived in declaration.deriveds {
            let derivedID = "\(constructID)/derived:\(derived.name)"
            if let body = derived.body {
                analyzeStatements(body, ownerID: derivedID, scope: scope)
            }
        }
        for initializer in declaration.initializers {
            let initializerID = "\(constructID)/init:\(renderParameterList(initializer.parameters))"
            var initializerScope = scope
            for parameter in initializer.parameters {
                let label = parameter.externalLabel ?? "_"
                let parameterID = "\(initializerID)/parameter:\(label):\(parameter.localName)"
                initializerScope.symbols[parameter.name] = parameterID
                if let typeReference = parameter.typeReference,
                    case .named(let name) = typeReference,
                    declarationGraph.hasConstruct(named: name)
                {
                    flowState.inferredConstructTypeByNodeID[parameterID] = name
                }
            }
            if let body = initializer.body {
                analyzeStatements(body, ownerID: initializerID, scope: initializerScope)
            }
        }
        for callable in declaration.callables {
            analyzeCallableDeclaration(callable, parentID: constructID, scope: scope)
        }
        for nested in declaration.constructs {
            analyzeConstructDeclaration(nested, parentID: constructID)
        }
    }

    private mutating func analyzeStateDeclaration(
        _ declaration: StateDeclaration,
        parentID: String
    ) {
        let stateID = "\(parentID)/state:\(declaration.name)"
        if case .stored(let expression) = declaration.storage {
            captureConstructType(for: stateID, from: expression)
            analyzeInitializer(expression, ownerID: stateID, scope: MemoryScope(), visitedCalls: [])
        }
    }

    private mutating func analyzeCallableDeclaration(
        _ declaration: CallableDeclaration,
        parentID: String,
        scope: MemoryScope
    ) {
        let callableID =
            "\(parentID)/function:\(declaration.name)(\(renderParameterList(declaration.parameters)))"
        var callableScope = scope
        for parameter in declaration.parameters {
            let label = parameter.externalLabel ?? "_"
            let parameterID = "\(callableID)/parameter:\(label):\(parameter.localName)"
            callableScope.symbols[parameter.name] = parameterID
            if let typeReference = parameter.typeReference,
                case .named(let name) = typeReference,
                declarationGraph.hasConstruct(named: name)
            {
                flowState.inferredConstructTypeByNodeID[parameterID] = name
            }
        }
        if let body = declaration.body {
            analyzeStatements(body, ownerID: callableID, scope: callableScope)
        }
    }

    private mutating func addNode(id: String, kind: ApplicationGraphNodeKind, label: String) {
        guard !baseEntityIDs.contains(id) else { return }
        nodesByID[id] = ApplicationGraphNode(id: id, kind: kind, label: label)
    }

    private mutating func addEdge(
        from sourceID: String, to targetID: String, kind: ApplicationGraphEdgeKind
    ) {
        let edge = ApplicationGraphEdge(sourceID: sourceID, targetID: targetID, kind: kind)
        guard !baseEdges.contains(edge) else { return }
        edges.insert(edge)
    }

    private mutating func addStorageTypeReference(_ reference: TypeReference, from sourceID: String)
    {
        let edgeKind: ApplicationGraphEdgeKind
        if case .named(let name) = reference,
            declarationGraph.hasConstruct(named: name),
            !declarationGraph.isCoreConstruct(named: name)
        {
            edgeKind = .referencesIdentity
        } else {
            edgeKind = .referencesType
        }

        let typeID = "type:\(reference.displayName)"
        addNode(id: typeID, kind: .typeReference, label: reference.displayName)
        addEdge(from: sourceID, to: typeID, kind: edgeKind)
    }

    private mutating func indexBaseSemanticGraph() {
        for entity in baseSemanticGraph.entities {
            guard let applicationKind = Self.applicationNodeKind(for: entity.kind) else {
                continue
            }
            registerDeclarationProjectionIfNeeded(
                entityID: entity.id,
                kind: applicationKind,
                label: entity.label
            )
        }
    }

    private func applicationNode(for entity: SemanticGraphEntity) -> ApplicationGraphNode? {
        guard let applicationKind = Self.applicationNodeKind(for: entity.kind) else {
            return nil
        }
        return ApplicationGraphNode(id: entity.id, kind: applicationKind, label: entity.label)
    }

    private static func applicationNodeKind(for kind: SemanticGraphEntityKind) -> ApplicationGraphNodeKind? {
        switch kind {
        case .file: return .file
        case .construct: return .construct
        case .enumeration: return .enumeration
        case .protocolDefinition: return .protocolDefinition
        case .macro: return .macro
        case .typeExtension: return .typeExtension
        case .mainBlock: return .mainBlock
        case .state: return .state
        case .environment: return .environment
        case .binding: return .binding
        case .derived: return .derived
        case .value: return .value
        case .initializer: return .initializer
        case .function: return .function
        case .parameter: return .parameter
        case .member: return .member
        case .typeReference: return .typeReference
        case .macroApplication: return .macroApplication
        case .localSymbol, .unresolved: return nil
        }
    }

    private static func applicationEdgeKind(for kind: SemanticGraphRelationKind) -> ApplicationGraphEdgeKind? {
        switch kind {
        case .contains: return .contains
        case .conformsTo: return .conformsTo
        case .extends: return .extends
        case .referencesType: return .referencesType
        case .referencesIdentity: return .referencesIdentity
        case .appliesMacro: return .appliesMacro
        case .targetsMacro: return .targetsMacro
        case .resolvesTo: return .resolvesTo
        case .dependsOn: return .dependsOn
        case .mutates: return .mutates
        case .aliases: return .aliases
        case .calls: return .calls
        }
    }

    private mutating func registerDeclarationProjectionIfNeeded(
        entityID: String,
        kind: ApplicationGraphNodeKind,
        label: String
    ) {
        switch kind {
        case .construct, .enumeration, .protocolDefinition, .macro:
            let name = declarationName(for: entityID, fallbackLabel: label)
            resolutionIndex.declarationProjectionNodeIDsByName[name, default: []].insert(entityID)
        case .function:
            guard
                let parentComponent = entityID.split(separator: "/").dropLast().last,
                parentComponent.hasPrefix("construct:")
            else {
                break
            }
            let constructName = String(parentComponent.dropFirst("construct:".count))
            resolutionIndex.constructCallableProjectionNodeIDs[constructName, default: [:]][label] =
                entityID
        default:
            break
        }
    }

    private func declarationName(for entityID: String, fallbackLabel: String) -> String {
        if let component = entityID.split(separator: "/").last {
            let raw = String(component)
            if let colonIndex = raw.firstIndex(of: ":") {
                return String(raw[raw.index(after: colonIndex)...])
            }
        }
        return fallbackLabel
    }

    private mutating func addResolutionEdges() {
        let typeNodes =
            baseSemanticGraph.entities.compactMap { applicationNode(for: $0) }.filter {
                $0.kind == .typeReference
            }
            + nodesByID.values.filter { $0.kind == .typeReference }
        for typeNode in typeNodes {
            guard let targetNodeIDs = resolutionIndex.declarationProjectionNodeIDsByName[typeNode.label] else {
                continue
            }
            for targetNodeID in targetNodeIDs {
                addEdge(from: typeNode.id, to: targetNodeID, kind: .resolvesTo)
            }
        }
    }

    private mutating func analyzeMainBlock(
        _ mainBlock: MainBlockNode,
        parentID: String,
        topLevelStates: [StateDeclaration]
    ) {
        let mainID = "\(parentID)/main"
        var scope = MemoryScope()
        for state in topLevelStates {
            scope.symbols[state.name] = "\(parentID)/state:\(state.name)"
        }
        analyzeStatements(mainBlock.body, ownerID: mainID, scope: scope)
    }

    private mutating func analyzeStatements(
        _ statements: [Statement],
        ownerID: String,
        scope: MemoryScope,
        visitedCalls: Set<String> = []
    ) {
        var scope = scope
        for (index, statement) in statements.enumerated() {
            let statementID = "\(ownerID)/stmt:\(index)"
            switch statement {
            case .macroInvocation(_, _, let body):
                analyzeStatements(
                    body, ownerID: statementID, scope: scope, visitedCalls: visitedCalls)
            case .background(let background):
                analyzeStatements(
                    background.body, ownerID: statementID, scope: scope, visitedCalls: visitedCalls)
            case .localCallable(let declaration):
                let callableID = "\(statementID)/localCallable:\(declaration.name)"
                addNode(id: callableID, kind: .function, label: declaration.name)
                addEdge(from: ownerID, to: callableID, kind: .contains)
                analyzeStatements(
                    declaration.body, ownerID: callableID, scope: scope, visitedCalls: visitedCalls)
            case .localBinding(let declaration):
                let nodeKind: ApplicationGraphNodeKind =
                    declaration.kind == .mutable ? .state : .value
                let localID = "\(ownerID)/local:\(declaration.name)"
                addNode(id: localID, kind: nodeKind, label: declaration.name)
                addEdge(from: ownerID, to: localID, kind: .contains)
                addStorageTypeReference(declaration.type, from: localID)
                if declarationGraph.hasConstruct(named: declaration.type.displayName) {
                    flowState.inferredConstructTypeByNodeID[localID] = declaration.type.displayName
                }
                captureConstructType(for: localID, from: declaration.expression)
                scope.symbols[declaration.name] = localID
                analyzeInitializer(
                    declaration.expression,
                    ownerID: localID,
                    scope: scope,
                    visitedCalls: visitedCalls
                )

            case .derived(let name, let typeName, let body):
                let derivedID = "\(ownerID)/local-derived:\(name)"
                addNode(id: derivedID, kind: .derived, label: name)
                addEdge(from: ownerID, to: derivedID, kind: .contains)
                addStorageTypeReference(.named(typeName), from: derivedID)
                scope.symbols[name] = derivedID
                analyzeStatements(
                    body, ownerID: derivedID, scope: scope, visitedCalls: visitedCalls)

            case .assignment(let target, let expression):
                let targetID = resolveAssignmentTarget(target, scope: scope)
                addEdge(from: ownerID, to: targetID, kind: .mutates)
                if case .bindingReference(let name) = expression,
                    let sourceID = resolveSimpleName(name, scope: scope)
                {
                    addAlias(from: targetID, to: sourceID)
                } else {
                    analyzeExpression(
                        expression, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)
                }

            case .compoundAssignment(let target, _, let expression):
                let targetID = resolveAssignmentTarget(target, scope: scope)
                addEdge(from: ownerID, to: targetID, kind: .mutates)
                addEdge(from: ownerID, to: targetID, kind: .dependsOn)
                analyzeExpression(
                    expression, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)

            case .expression(let expression):
                analyzeExpression(
                    expression, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)

            case .forEach(let name, let sequence, let body):
                analyzeExpression(
                    sequence, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)
                let loopID = "\(statementID)/forEach:\(name)"
                addNode(id: loopID, kind: .value, label: name)
                addEdge(from: ownerID, to: loopID, kind: .contains)
                var loopScope = scope
                loopScope.symbols[name] = loopID
                analyzeStatements(
                    body, ownerID: ownerID, scope: loopScope, visitedCalls: visitedCalls)

            case .whileLoop(let condition, let body):
                analyzeExpression(
                    condition, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)
                analyzeStatements(body, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)

            case .conditional(let branches):
                for branch in branches {
                    if let condition = branch.condition {
                        analyzeExpression(
                            condition, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)
                    }
                    analyzeStatements(
                        branch.body, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)
                }

            case .return(let expression):
                if let expression {
                    analyzeExpression(
                        expression, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)
                }

            case .switchStatement(let expression, let cases, let defaultBody):
                analyzeExpression(
                    expression, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)
                for switchCase in cases {
                    analyzeSwitchCasePattern(
                        switchCase.pattern,
                        ownerID: ownerID,
                        scope: scope,
                        visitedCalls: visitedCalls
                    )
                    analyzeStatements(
                        switchCase.body, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)
                }
                if let defaultBody {
                    analyzeStatements(
                        defaultBody, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)
                }

            case .environmentProvision, .break, .continue:
                continue
            }
        }
    }

    private mutating func analyzeSwitchCasePattern(
        _ pattern: SwitchCasePattern,
        ownerID: String,
        scope: MemoryScope,
        visitedCalls: Set<String>
    ) {
        if case .expression(let expression) = pattern {
            analyzeExpression(
                expression,
                ownerID: ownerID,
                scope: scope,
                visitedCalls: visitedCalls
            )
        }
    }

    private mutating func analyzeInitializer(
        _ expression: Expression,
        ownerID: String,
        scope: MemoryScope,
        visitedCalls: Set<String>
    ) {
        analyzeExpression(expression, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)
        if case .bindingReference(let name) = expression,
            let sourceID = resolveSimpleName(name, scope: scope)
        {
            addAlias(from: ownerID, to: sourceID)
        }
        if case .call(let name, let arguments) = expression,
            declarationGraph.hasConstruct(named: name)
        {
            flowState.inferredConstructTypeByNodeID[ownerID] = name
            bindConstructArguments(
                ownerID: ownerID, constructName: name, arguments: arguments, scope: scope)
        }
    }

    private mutating func analyzeExpression(
        _ expression: Expression,
        ownerID: String,
        scope: MemoryScope,
        visitedCalls: Set<String>
    ) {
        switch expression {
        case .identifier(let name):
            if let resolved = resolvePath(name, scope: scope) {
                addEdge(from: ownerID, to: resolved, kind: .dependsOn)
            }
        case .bindingReference(let name):
            if let resolved = resolveSimpleName(name, scope: scope) {
                addEdge(from: ownerID, to: resolved, kind: .dependsOn)
            }
        case .macroInvocation(_, let arguments):
            for argument in arguments {
                analyzeExpression(
                    argument.value, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)
            }
        case .call(let name, let arguments):
            for argument in arguments {
                analyzeExpression(
                    argument.value, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)
            }
            analyzeCall(
                name: name, arguments: arguments, ownerID: ownerID, scope: scope,
                visitedCalls: visitedCalls)
        case .interpolatedString(let string):
            for segment in string.segments {
                if case .expression(let expression) = segment {
                    analyzeExpression(
                        expression, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)
                }
            }
        case .array(let elements):
            for element in elements {
                analyzeExpression(
                    element, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)
            }
        case .dictionary(let elements):
            for element in elements {
                analyzeExpression(
                    element.key, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)
                analyzeExpression(
                    element.value, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)
            }
        case .ternary(let condition, let trueExpression, let falseExpression):
            analyzeExpression(condition, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)
            analyzeExpression(
                trueExpression, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)
            analyzeExpression(
                falseExpression, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)
        case .unary(_, let expression):
            analyzeExpression(
                expression, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)
        case .binary(let lhs, _, let rhs):
            analyzeExpression(lhs, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)
            analyzeExpression(rhs, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)
        case .block:
            return
        case .integer, .double, .string, .boolean, .nilLiteral:
            return
        }
    }

    private mutating func analyzeCall(
        name: String,
        arguments: [CallArgument],
        ownerID: String,
        scope: MemoryScope,
        visitedCalls: Set<String>
    ) {
        let parts = name.split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return }
        let basePath = parts.dropLast().joined(separator: ".")
        let methodName = parts.last ?? name
        guard let baseNodeID = resolvePath(basePath, scope: scope) else { return }
        let canonicalBaseID = resolvedAlias(of: baseNodeID)
        guard
            let constructName = flowState.inferredConstructTypeByNodeID[canonicalBaseID]
                ?? flowState.inferredConstructTypeByNodeID[baseNodeID]
        else {
            return
        }
        guard
            let callable = declarationGraph.callable(named: methodName, onConstruct: constructName),
            let callableNodeID = resolutionIndex.constructCallableProjectionNodeIDs[constructName]?[methodName]
        else {
            return
        }

        addEdge(from: ownerID, to: callableNodeID, kind: .calls)

        let callKey = "\(ownerID)->\(callableNodeID)->\(canonicalBaseID)"
        guard !visitedCalls.contains(callKey) else { return }

        var callableScope = scopeForConstructInstance(
            instanceNodeID: baseNodeID,
            constructName: constructName
        )
        for (index, parameter) in callable.parameters.enumerated() {
            let parameterID = "\(ownerID)/call:\(methodName)/parameter:\(parameter.name):\(index)"
            addNode(id: parameterID, kind: .parameter, label: parameter.name)
            addEdge(from: ownerID, to: parameterID, kind: .contains)
            callableScope.symbols[parameter.name] = parameterID
            if index < arguments.count {
                analyzeInitializer(
                    arguments[index].value,
                    ownerID: parameterID,
                    scope: scope,
                    visitedCalls: visitedCalls.union([callKey])
                )
            }
        }

        if let body = callable.body {
            analyzeStatements(
                body,
                ownerID: ownerID,
                scope: callableScope,
                visitedCalls: visitedCalls.union([callKey])
            )
        }
    }

    private mutating func bindConstructArguments(
        ownerID: String,
        constructName: String,
        arguments: [CallArgument],
        scope: MemoryScope
    ) {
        let memberKinds = declarationGraph.memberKinds(forConstruct: constructName)

        for argument in arguments {
            guard let label = argument.label, let kind = memberKinds[label] else { continue }
            let memberID = ensureMemberNode(baseID: ownerID, name: label, kind: kind)
            captureConstructTypeForMember(
                named: label,
                onConstruct: constructName,
                nodeID: memberID
            )
            if case .bindingReference(let name) = argument.value,
                let sourceID = resolveSimpleName(name, scope: scope)
            {
                addAlias(from: memberID, to: sourceID)
            } else if let resolved = resolveExpressionNode(argument.value, scope: scope) {
                addEdge(from: memberID, to: resolved, kind: .dependsOn)
            }
        }
    }

    private mutating func scopeForConstructInstance(
        instanceNodeID: String,
        constructName: String
    ) -> MemoryScope {
        var scope = MemoryScope()
        scope.symbols["self"] = instanceNodeID
        let memberKinds = declarationGraph.memberKinds(forConstruct: constructName)
        let constructTypedMembers = declarationGraph.constructTypedMemberNames(
            forConstruct: constructName
        )

        for (memberName, kind) in memberKinds {
            guard kind == .state else { continue }
            scope.symbols[memberName] = ensureMemberNode(
                baseID: instanceNodeID, name: memberName, kind: kind)
        }
        for (memberName, kind) in memberKinds {
            guard kind == .environment else { continue }
            scope.symbols[memberName] = ensureMemberNode(
                baseID: instanceNodeID, name: memberName, kind: kind)
        }
        for (memberName, kind) in memberKinds {
            guard kind == .binding || kind == .derived || kind == .value else { continue }
            let nodeID = ensureMemberNode(baseID: instanceNodeID, name: memberName, kind: kind)
            if let typeName = constructTypedMembers[memberName] {
                flowState.inferredConstructTypeByNodeID[nodeID] = typeName
            }
            scope.symbols[memberName] = nodeID
        }
        return scope
    }

    private mutating func captureConstructType(for nodeID: String, from expression: Expression) {
        guard case .call(let name, _) = expression, declarationGraph.hasConstruct(named: name) else {
            return
        }
        flowState.inferredConstructTypeByNodeID[nodeID] = name
    }

    private mutating func captureConstructTypeForMember(
        named memberName: String,
        onConstruct constructName: String,
        nodeID: String
    ) {
        if let typeName = declarationGraph.constructTypedMemberNames(
            forConstruct: constructName
        )[memberName] {
            flowState.inferredConstructTypeByNodeID[nodeID] = typeName
        }
    }

    private mutating func resolveAssignmentTarget(
        _ target: AssignmentTarget,
        scope: MemoryScope
    ) -> String {
        switch target {
        case .state(let name), .binding(let name), .environment(let name), .local(let name):
            return resolveSimpleName(name, scope: scope) ?? ensureFallbackNode(name: name)
        case .member(let base, let name):
            let baseID = resolveAssignmentTarget(base, scope: scope)
            return ensureMemberNode(baseID: baseID, name: name, kind: .member)
        }
    }

    private mutating func resolveExpressionNode(
        _ expression: Expression,
        scope: MemoryScope
    ) -> String? {
        switch expression {
        case .identifier(let name):
            return resolvePath(name, scope: scope)
        case .bindingReference(let name):
            return resolvePath(name, scope: scope)
        default:
            return nil
        }
    }

    private mutating func resolvePath(_ path: String, scope: MemoryScope) -> String? {
        let parts = path.split(separator: ".").map(String.init)
        guard let first = parts.first, var currentID = resolveSimpleName(first, scope: scope) else {
            return nil
        }
        for member in parts.dropFirst() {
            currentID = ensureMemberNode(baseID: currentID, name: member, kind: .member)
        }
        return currentID
    }

    private func resolveSimpleName(_ name: String, scope: MemoryScope) -> String? {
        scope.symbols[name]
    }

    private mutating func ensureMemberNode(
        baseID: String,
        name: String,
        kind: ApplicationGraphNodeKind
    ) -> String {
        let memberID = "\(baseID)/member:\(name)"
        if nodesByID[memberID] == nil {
            addNode(id: memberID, kind: kind, label: name)
            addEdge(from: baseID, to: memberID, kind: .contains)
        }

        let canonicalBaseID = resolvedAlias(of: baseID)
        if canonicalBaseID != baseID {
            let canonicalMemberID = ensureMemberNode(
                baseID: canonicalBaseID, name: name, kind: kind)
            addAlias(from: memberID, to: canonicalMemberID)
            if let constructName = flowState.inferredConstructTypeByNodeID[canonicalMemberID] {
                flowState.inferredConstructTypeByNodeID[memberID] = constructName
            }
        }

        return memberID
    }

    private mutating func addAlias(from sourceID: String, to targetID: String) {
        flowState.aliasTargetByNodeID[sourceID] = targetID
        addEdge(from: sourceID, to: targetID, kind: .aliases)
        if let constructName = flowState.inferredConstructTypeByNodeID[targetID] {
            flowState.inferredConstructTypeByNodeID[sourceID] = constructName
        }
    }

    private func resolvedAlias(of nodeID: String) -> String {
        var current = nodeID
        var seen: Set<String> = []
        while let next = flowState.aliasTargetByNodeID[current], !seen.contains(next) {
            seen.insert(current)
            current = next
        }
        return current
    }

    private mutating func ensureFallbackNode(name: String) -> String {
        let fallbackID = "unresolved:\(name)"
        if nodesByID[fallbackID] == nil {
            addNode(id: fallbackID, kind: .member, label: name)
        }
        return fallbackID
    }

    private func makeScope(
        bindings: [(String, String)],
        deriveds: [(String, String)],
        environments: [(String, String)],
        states: [(String, String)],
        values: [(String, String)],
        selfID: String? = nil
    ) -> MemoryScope {
        var scope = MemoryScope()
        if let selfID {
            scope.symbols["self"] = selfID
        }
        for (name, id) in states + environments + bindings + deriveds + values {
            scope.symbols[name] = id
        }
        return scope
    }

    private func renderParameterList(_ parameters: [NeatFunctionParameter]) -> String {
        parameters.map { parameter in
            let typeName =
                parameter.slotName.map { "@\($0)" } ?? parameter.typeReference?.displayName
                ?? "_"
            let label = parameter.externalLabel ?? "_"
            return "\(label):\(typeName)"
        }.joined(separator: ",")
    }
}

private struct DependencyResolutionIndex {
    var declarationProjectionNodeIDsByName: [String: Set<String>] = [:]
    var constructCallableProjectionNodeIDs: [String: [String: String]] = [:]
}

private struct DependencyFlowState {
    var aliasTargetByNodeID: [String: String] = [:]
    var inferredConstructTypeByNodeID: [String: String] = [:]
}

private struct MemoryScope {
    var symbols: [String: String] = [:]
}
