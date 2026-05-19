import Foundation

extension ApplicationGraph {
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
