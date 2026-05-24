import RangeSyntax
import SwiftUI
import UniformTypeIdentifiers

struct DeclarationGraphWorkspaceView: View {
    @State private var document: DeclarationGraphDocument?
    @State private var selectedNodeID: String?
    @State private var searchText = ""
    @State private var hiddenKinds: Set<String> = []
    @State private var hiddenRelationKinds: Set<String> = []
    @State private var errorMessage: String?
    @State private var isLoading = false

    private var filteredGraph: DeclarationGraphSnapshot? {
        guard let graph = document?.graph else {
            return nil
        }

        let matchedNodes = graph.nodes.filter { node in
            let matchesSearch = searchText.isEmpty
                || node.label.localizedCaseInsensitiveContains(searchText)
                || node.id.localizedCaseInsensitiveContains(searchText)
                || node.kind.rawValue.localizedCaseInsensitiveContains(searchText)
            return matchesSearch && !hiddenKinds.contains(node.kind.rawValue)
        }
        let visibleIDs = Set(matchedNodes.map(\.id))
        let matchedEdges = graph.edges.filter {
            visibleIDs.contains($0.sourceID)
                && visibleIDs.contains($0.targetID)
                && !hiddenRelationKinds.contains($0.kind.rawValue)
        }
        return DeclarationGraphSnapshot(nodes: matchedNodes, edges: matchedEdges)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if let graph = filteredGraph {
                DeclarationGraphCanvasView(
                    graph: graph,
                    displayMode: .diagram,
                    selectedNodeID: $selectedNodeID
                )
                .overlay(alignment: .topLeading) {
                    graphSummary(visible: graph, total: document?.graph)
                }
            } else {
                emptyState
            }
        }
        .frame(minWidth: 1180, minHeight: 760)
        .alert("Could not load graph", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error.")
        }
        .task {
            loadDefaultExampleIfNeeded()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Declaration Graph")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    openSource()
                } label: {
                    Image(systemName: "folder")
                }
                .help("Open .range file or folder")
            }

            if let document {
                Text(document.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            searchField

            if isLoading {
                ProgressView()
            }

            if let document, let visibleGraph = filteredGraph {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        metrics(for: document.graph, visibleGraph: visibleGraph)
                        sourceOutline(for: document.graph)
                        filterPanel(for: document.graph)
                        nodeBrowser(for: visibleGraph, fullGraph: document.graph)
                        selectedNodeDetails(in: document.graph)
                    }
                    .padding(.vertical, 2)
                }
            } else {
                Text("Open a Range source file or project folder to build the first declaration graph visualization.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 440)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search nodes", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 7))
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 54))
                .foregroundStyle(.secondary)
            Text("No Declaration Graph Loaded")
                .font(.title2.weight(.semibold))
            Button {
                openSource()
            } label: {
                Label("Open Source", systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func metrics(
        for graph: DeclarationGraphSnapshot,
        visibleGraph: DeclarationGraphSnapshot
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Overview", systemImage: "chart.bar.xaxis")
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                GridRow {
                    metricValue("\(visibleGraph.nodes.count)")
                    metricLabel("visible nodes")
                    metricValue("\(graph.nodes.count)")
                    metricLabel("total")
                }
                GridRow {
                    metricValue("\(visibleGraph.edges.count)")
                    metricLabel("visible edges")
                    metricValue("\(graph.visibleRelationKinds.count)")
                    metricLabel("relation types")
                }
                GridRow {
                    metricValue("\(graph.nodes.filter { $0.kind == .file }.count)")
                    metricLabel("files")
                    metricValue("\(graph.nodes.filter { $0.kind == .construct }.count)")
                    metricLabel("constructs")
                }
            }
        }
    }

    private func metricValue(_ value: String) -> some View {
        Text(value)
            .font(.callout.monospacedDigit().weight(.semibold))
    }

    private func metricLabel(_ value: String) -> some View {
        Text(value)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func sourceOutline(for graph: DeclarationGraphSnapshot) -> some View {
        let entries = fileOutlineEntries(for: graph)

        return VStack(alignment: .leading, spacing: 9) {
            sectionHeader("Files", systemImage: "doc.text")
            if entries.isEmpty {
                Text("No file ownership relationships were emitted.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries) { entry in
                    sourceOutlineEntry(entry)
                }
            }
        }
    }

    private func sourceOutlineEntry(_ entry: FileOutlineEntry) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Button {
                selectedNodeID = entry.file.id
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc")
                        .foregroundStyle(.secondary)
                    Text(entry.file.label)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Spacer()
                    Text("\(entry.children.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(selectionFill(for: entry.file.id), in: RoundedRectangle(cornerRadius: 6))

            ForEach(Array(entry.children.prefix(8))) { child in
                Button {
                    selectedNodeID = child.id
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(DeclarationGraphPalette.fill(for: child.kind))
                            .frame(width: 7, height: 7)
                        Text(child.label)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Text(child.kind.rawValue)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 3)
                .padding(.horizontal, 6)
                .padding(.leading, 18)
                .background(selectionFill(for: child.id), in: RoundedRectangle(cornerRadius: 6))
            }

            if entry.children.count > 8 {
                Text("\(entry.children.count - 8) more declarations")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 32)
            }
        }
    }

    private func filterPanel(for graph: DeclarationGraphSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Filters", systemImage: "line.3.horizontal.decrease.circle")
            VStack(alignment: .leading, spacing: 8) {
                Text("Node Kinds")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                kindFilters(for: graph)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Relations")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                relationFilters(for: graph)
            }
        }
    }

    private func kindFilters(for graph: DeclarationGraphSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(graph.visibleKinds, id: \.rawValue) { kind in
                Toggle(isOn: kindBinding(kind)) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(DeclarationGraphPalette.fill(for: kind))
                            .frame(width: 10, height: 10)
                        Text(kind.rawValue)
                            .lineLimit(1)
                        Spacer()
                        Text("\(graph.nodes.filter { $0.kind == kind }.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }
        }
    }

    private func relationFilters(for graph: DeclarationGraphSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(graph.visibleRelationKinds, id: \.rawValue) { kind in
                Toggle(isOn: relationKindBinding(kind)) {
                    HStack(spacing: 8) {
                        Capsule()
                            .fill(DeclarationGraphPalette.stroke(for: kind))
                            .frame(width: 18, height: 4)
                        Text(kind.rawValue)
                            .lineLimit(1)
                        Spacer()
                        Text("\(graph.edges.filter { $0.kind == kind }.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }
        }
    }

    private func nodeBrowser(
        for visibleGraph: DeclarationGraphSnapshot,
        fullGraph: DeclarationGraphSnapshot
    ) -> some View {
        let nodes = visibleGraph.nodes.sorted(by: nodeSort)

        return VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Nodes", systemImage: "circle.grid.cross")
            if nodes.isEmpty {
                Text("No visible nodes match the current search and filters.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(nodes) { node in
                        nodeBrowserRow(node, graph: fullGraph)
                    }
                }
            }
        }
    }

    private func nodeBrowserRow(
        _ node: DeclarationGraphNode,
        graph: DeclarationGraphSnapshot
    ) -> some View {
        Button {
            selectedNodeID = node.id
        } label: {
            HStack(spacing: 9) {
                Circle()
                    .fill(DeclarationGraphPalette.fill(for: node.kind))
                    .frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.label)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(node.kind.rawValue)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Label("\(degree(for: node, in: graph))", systemImage: "arrow.triangle.branch")
                    .labelStyle(.titleAndIcon)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)
        .padding(.horizontal, 7)
        .background(selectionFill(for: node.id), in: RoundedRectangle(cornerRadius: 6))
    }

    private func selectedNodeDetails(in graph: DeclarationGraphSnapshot) -> some View {
        let node = selectedNodeID.flatMap { graph.nodeByID[$0] }
        let incoming = node.map { selected in
            graph.edges
                .filter { $0.targetID == selected.id }
                .sorted { relationshipSort($0, $1, graph: graph, direction: .incoming) }
        } ?? []
        let outgoing = node.map { selected in
            graph.edges
                .filter { $0.sourceID == selected.id }
                .sorted { relationshipSort($0, $1, graph: graph, direction: .outgoing) }
        } ?? []

        return VStack(alignment: .leading, spacing: 9) {
            sectionHeader("Selection", systemImage: "scope")
            if let node {
                VStack(alignment: .leading, spacing: 4) {
                    Text(node.label)
                        .font(.callout.weight(.semibold))
                        .textSelection(.enabled)
                    HStack(spacing: 8) {
                        Circle()
                            .fill(DeclarationGraphPalette.fill(for: node.kind))
                            .frame(width: 8, height: 8)
                        Text(node.kind.rawValue)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Text(node.id)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }

                relationshipSection("Outgoing", edges: outgoing, graph: graph, direction: .outgoing)
                relationshipSection("Incoming", edges: incoming, graph: graph, direction: .incoming)
            } else {
                Text("Select a node to inspect its declaration identity and relationships.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func relationshipSection(
        _ title: String,
        edges: [DeclarationGraphEdge],
        graph: DeclarationGraphSnapshot,
        direction: RelationshipDirection
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(edges.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if edges.isEmpty {
                Text("None")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(Array(edges.prefix(16))) { edge in
                    relationshipRow(edge, graph: graph, direction: direction)
                }
                if edges.count > 16 {
                    Text("\(edges.count - 16) more relationships")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, 4)
    }

    private func relationshipRow(
        _ edge: DeclarationGraphEdge,
        graph: DeclarationGraphSnapshot,
        direction: RelationshipDirection
    ) -> some View {
        let otherID = direction == .outgoing ? edge.targetID : edge.sourceID
        let other = graph.nodeByID[otherID]

        return Button {
            selectedNodeID = otherID
        } label: {
            HStack(spacing: 8) {
                Image(systemName: direction == .outgoing ? "arrow.up.right" : "arrow.down.left")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(other?.label ?? otherID)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    Text(edge.kind.rawValue)
                        .font(.caption2.monospaced())
                        .foregroundStyle(DeclarationGraphPalette.stroke(for: edge.kind))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if let other {
                    Text(other.kind.rawValue)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(selectionFill(for: otherID), in: RoundedRectangle(cornerRadius: 6))
    }

    private func graphSummary(
        visible graph: DeclarationGraphSnapshot,
        total: DeclarationGraphSnapshot?
    ) -> some View {
        HStack(spacing: 12) {
            Label("\(graph.nodes.count)", systemImage: "circle.grid.cross")
            Label("\(graph.edges.count)", systemImage: "arrow.triangle.branch")
            if let total, total.nodes.count != graph.nodes.count || total.edges.count != graph.edges.count {
                Text("of \(total.nodes.count) / \(total.edges.count)")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding(14)
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
    }

    private func selectionFill(for id: String) -> Color {
        selectedNodeID == id ? Color.accentColor.opacity(0.15) : Color.clear
    }

    private func fileOutlineEntries(for graph: DeclarationGraphSnapshot) -> [FileOutlineEntry] {
        let nodeByID = graph.nodeByID
        let fileNodes = graph.nodes
            .filter { $0.kind == .file }
            .sorted { $0.label < $1.label }

        return fileNodes.map { file in
            let children = graph.edges
                .filter { $0.kind == .contains && $0.sourceID == file.id }
                .compactMap { nodeByID[$0.targetID] }
                .filter { Self.sourceOutlineKinds.contains($0.kind) }
                .sorted(by: nodeSort)
            return FileOutlineEntry(file: file, children: children)
        }
    }

    private func degree(for node: DeclarationGraphNode, in graph: DeclarationGraphSnapshot) -> Int {
        graph.edges.filter { $0.sourceID == node.id || $0.targetID == node.id }.count
    }

    private func nodeSort(_ lhs: DeclarationGraphNode, _ rhs: DeclarationGraphNode) -> Bool {
        if lhs.kind.rawValue != rhs.kind.rawValue {
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
        if lhs.label != rhs.label {
            return lhs.label < rhs.label
        }
        return lhs.id < rhs.id
    }

    private func relationshipSort(
        _ lhs: DeclarationGraphEdge,
        _ rhs: DeclarationGraphEdge,
        graph: DeclarationGraphSnapshot,
        direction: RelationshipDirection
    ) -> Bool {
        if lhs.kind.rawValue != rhs.kind.rawValue {
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
        let leftID = direction == .outgoing ? lhs.targetID : lhs.sourceID
        let rightID = direction == .outgoing ? rhs.targetID : rhs.sourceID
        let left = graph.nodeByID[leftID]?.label ?? leftID
        let right = graph.nodeByID[rightID]?.label ?? rightID
        return left < right
    }

    private func kindBinding(_ kind: SemanticGraphEntityKind) -> Binding<Bool> {
        Binding {
            !hiddenKinds.contains(kind.rawValue)
        } set: { isVisible in
            if isVisible {
                hiddenKinds.remove(kind.rawValue)
            } else {
                hiddenKinds.insert(kind.rawValue)
            }
        }
    }

    private func relationKindBinding(_ kind: SemanticGraphRelationKind) -> Binding<Bool> {
        Binding {
            !hiddenRelationKinds.contains(kind.rawValue)
        } set: { isVisible in
            if isVisible {
                hiddenRelationKinds.remove(kind.rawValue)
            } else {
                hiddenRelationKinds.insert(kind.rawValue)
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func openSource() {
        let panel = NSOpenPanel()
        panel.title = "Open Range Source"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.folder, .init(filenameExtension: "range")!]

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        isLoading = true
        selectedNodeID = nil
        do {
            document = try DeclarationGraphLoader.load(from: url)
            hiddenKinds = []
            hiddenRelationKinds = []
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadDefaultExampleIfNeeded() {
        guard document == nil, !isLoading else {
            return
        }

        isLoading = true
        do {
            document = try DeclarationGraphLoader.load(from: DeclarationGraphLoader.defaultExampleURL)
            hiddenKinds = []
            hiddenRelationKinds = []
            selectedNodeID = document?.graph.nodes.first?.id
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private static let sourceOutlineKinds: Set<SemanticGraphEntityKind> = [
        .construct,
        .enumeration,
        .protocolDefinition,
        .namespace,
        .macro,
        .marker,
        .typeExtension,
        .mainBlock,
    ]
}

private struct FileOutlineEntry: Identifiable {
    let file: DeclarationGraphNode
    let children: [DeclarationGraphNode]

    var id: String {
        file.id
    }
}

private enum RelationshipDirection {
    case incoming
    case outgoing
}
