import AppKit
import RangeSyntax
import SwiftUI

struct DeclarationGraphCanvasView: NSViewRepresentable {
    let graph: DeclarationGraphSnapshot
    let displayMode: DeclarationGraphDisplayMode
    @Binding var selectedNodeID: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedNodeID: $selectedNodeID)
    }

    func makeNSView(context: Context) -> DeclarationGraphCanvasHostView {
        let view = DeclarationGraphCanvasHostView()
        view.onSelectNode = { id in
            context.coordinator.selectedNodeID = id
        }
        return view
    }

    func updateNSView(_ view: DeclarationGraphCanvasHostView, context: Context) {
        view.graph = graph
        view.displayMode = displayMode
        view.selectedNodeID = selectedNodeID
    }

    final class Coordinator {
        @Binding var selectedNodeID: String?

        init(selectedNodeID: Binding<String?>) {
            _selectedNodeID = selectedNodeID
        }
    }
}

final class DeclarationGraphCanvasHostView: NSView {
    var graph = DeclarationGraphSnapshot(nodes: [], edges: []) {
        didSet {
            quartzView.graph = graph
            metalView.graph = graph
        }
    }
    var selectedNodeID: String? {
        didSet {
            quartzView.selectedNodeID = selectedNodeID
            metalView.selectedNodeID = selectedNodeID
        }
    }
    var displayMode: DeclarationGraphDisplayMode = .diagram {
        didSet {
            quartzView.displayMode = displayMode
            metalView.isHidden = displayMode != .artistic
            quartzView.isHidden = displayMode == .artistic
            metalView.isPaused = displayMode != .artistic
            needsLayout = true
        }
    }
    var onSelectNode: ((String?) -> Void)? {
        didSet {
            quartzView.onSelectNode = onSelectNode
            metalView.onSelectNode = onSelectNode
        }
    }

    private let quartzView = QuartzDeclarationGraphView()
    private let metalView = MetalSunGraphView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(quartzView)
        addSubview(metalView)
        metalView.isHidden = true
        metalView.isPaused = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        quartzView.frame = bounds
        metalView.frame = bounds
    }
}

final class QuartzDeclarationGraphView: NSView {
    var graph = DeclarationGraphSnapshot(nodes: [], edges: []) {
        didSet {
            cachedLayout = nil
            hasUserAdjustedViewport = false
            needsDisplay = true
        }
    }
    var selectedNodeID: String? {
        didSet {
            needsDisplay = true
        }
    }
    var displayMode: DeclarationGraphDisplayMode = .diagram {
        didSet {
            guard displayMode != oldValue else {
                return
            }
            cachedLayout = nil
            hasUserAdjustedViewport = false
            updateAnimationTimer()
            needsDisplay = true
        }
    }
    var onSelectNode: ((String?) -> Void)?

    private var zoomScale: CGFloat = 1
    private var panOffset = CGPoint.zero
    private var lastDragLocation: CGPoint?
    private var cachedLayout: [PositionedDeclarationNode]?
    private var cachedLayoutSize: CGSize?
    private var animationTimer: Timer?
    private var hasUserAdjustedViewport = false

    private struct ArtisticRelationshipPair {
        let sourceID: String
        let targetID: String
        let strength: CGFloat
    }

    private struct MagneticSource {
        let id: String
        let position: CGPoint
        let projectedPosition: CGPoint
        let radius: CGFloat
        let projectedRadius: CGFloat
        let strength: CGFloat
        let polarity: CGFloat
        let moment: CGVector
        let z: CGFloat
        let perspective: CGFloat
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAnimationTimer()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            animationTimer?.invalidate()
            animationTimer = nil
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }

        drawBackground(in: bounds, context: context)

        let layout = positionedNodes(in: bounds.size)
        applyInitialViewportFitIfNeeded(for: layout, in: bounds.size)
        let positions = Dictionary(uniqueKeysWithValues: layout.map { ($0.id, $0.position) })
        let layoutByID = Dictionary(uniqueKeysWithValues: layout.map { ($0.id, $0) })
        let visibleIDs = Set(positions.keys)

        context.saveGState()
        context.translateBy(x: panOffset.x, y: panOffset.y)
        context.scaleBy(x: zoomScale, y: zoomScale)

        if displayMode != .artistic {
            drawDiagramNodes(layout.filter { $0.node.kind == .file }, context: context)
            drawEdges(
                graph.edges.filter {
                    visibleIDs.contains($0.sourceID) && visibleIDs.contains($0.targetID)
                },
                layoutByID: layoutByID,
                context: context
            )
            drawDiagramNodes(layout.filter { $0.node.kind != .file }, context: context)
        } else {
            drawNodes(layout, context: context)
        }

        context.restoreGState()
    }

    private func updateAnimationTimer() {
        animationTimer?.invalidate()
        animationTimer = nil
        guard window != nil, displayMode == .artistic else {
            return
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = graphPoint(from: convert(event.locationInWindow, from: nil))
        if let hit = hitNode(at: point) {
            selectedNodeID = hit.id
            onSelectNode?(hit.id)
        } else {
            selectedNodeID = nil
            onSelectNode?(nil)
        }
        lastDragLocation = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        guard let lastDragLocation else {
            self.lastDragLocation = location
            return
        }
        panOffset.x += location.x - lastDragLocation.x
        panOffset.y += location.y - lastDragLocation.y
        hasUserAdjustedViewport = true
        self.lastDragLocation = location
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        lastDragLocation = nil
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.option) || event.phase == .mayBegin {
            let delta = event.scrollingDeltaY == 0 ? event.scrollingDeltaX : event.scrollingDeltaY
            zoom(around: convert(event.locationInWindow, from: nil), by: 1 + delta * 0.01)
            return
        }

        panOffset.x -= event.scrollingDeltaX
        panOffset.y -= event.scrollingDeltaY
        hasUserAdjustedViewport = true
        needsDisplay = true
    }

    override func magnify(with event: NSEvent) {
        zoom(around: convert(event.locationInWindow, from: nil), by: 1 + event.magnification)
    }

    override func keyDown(with event: NSEvent) {
        switch event.charactersIgnoringModifiers {
        case "0":
            if displayMode == .artistic {
                zoomScale = 1
                panOffset = .zero
            } else {
                hasUserAdjustedViewport = false
            }
            needsDisplay = true
        case "+":
            zoom(around: CGPoint(x: bounds.midX, y: bounds.midY), by: 1.1)
        case "-":
            zoom(around: CGPoint(x: bounds.midX, y: bounds.midY), by: 0.9)
        default:
            super.keyDown(with: event)
        }
    }

    private func drawBackground(in rect: CGRect, context: CGContext) {
        let fill = displayMode == .artistic ? NSColor.black : NSColor.windowBackgroundColor
        context.setFillColor(fill.cgColor)
        context.fill(rect)
    }

    private func drawEdges(
        _ edges: [DeclarationGraphEdge],
        layoutByID: [String: PositionedDeclarationNode],
        context: CGContext
    ) {
        let orderedEdges = edges.sorted { left, right in
            let leftSelected = isEdgeSelected(left)
            let rightSelected = isEdgeSelected(right)
            if leftSelected != rightSelected {
                return !leftSelected && rightSelected
            }
            return left.id < right.id
        }

        for edge in orderedEdges {
            if isFileContainmentEdge(edge, layoutByID: layoutByID) {
                continue
            }
            guard let sourceNode = layoutByID[edge.sourceID],
                let targetNode = layoutByID[edge.targetID]
            else {
                continue
            }

            if displayMode == .artistic,
                edge.kind != .contains,
                edge.kind != .conformsTo,
                edge.kind != .extends
            {
                continue
            }

            let source = edgeAnchor(
                from: sourceNode.position,
                toward: targetNode.position,
                size: sourceNode.size
            )
            let target = edgeAnchor(
                from: targetNode.position,
                toward: sourceNode.position,
                size: targetNode.size
            )
            let controlOffset = max(50, abs(target.x - source.x) * 0.35)
            let control2 = CGPoint(x: target.x - controlOffset, y: target.y)
            let path = CGMutablePath()
            path.move(to: source)
            path.addCurve(
                to: target,
                control1: CGPoint(x: source.x + controlOffset, y: source.y),
                control2: control2
            )

            let selectedEdge = isEdgeSelected(edge)
            let dimmed = selectedNodeID != nil && !selectedEdge
            let stroke = edgeStrokeColor(edge.kind, selected: selectedEdge, dimmed: dimmed)
            let lineWidth = selectedEdge ? 2.2 : 1.1

            context.addPath(path)
            context.setStrokeColor(stroke.cgColor)
            context.setLineWidth(edge.kind == .contains ? lineWidth + 0.3 : lineWidth)
            context.setLineCap(.round)
            context.strokePath()

            let angle = atan2(target.y - control2.y, target.x - control2.x)
            drawArrowhead(at: target, angle: angle, color: stroke, size: selectedEdge ? 8 : 6, context: context)

            if selectedEdge {
                drawEdgeLabel(edge.kind.rawValue, near: source, target: target, color: stroke, context: context)
            }
        }
    }

    private func isFileContainmentEdge(
        _ edge: DeclarationGraphEdge,
        layoutByID: [String: PositionedDeclarationNode]
    ) -> Bool {
        edge.kind == .contains
            && layoutByID[edge.sourceID]?.node.kind == .file
            && layoutByID[edge.targetID] != nil
    }

    private func isEdgeSelected(_ edge: DeclarationGraphEdge) -> Bool {
        guard let selectedNodeID else {
            return false
        }
        return edge.sourceID == selectedNodeID || edge.targetID == selectedNodeID
    }

    private func edgeStrokeColor(
        _ kind: SemanticGraphRelationKind,
        selected: Bool,
        dimmed: Bool
    ) -> NSColor {
        if dimmed {
            return edgeColor(kind).withAlphaComponent(isDarkAppearance ? 0.11 : 0.13)
        }
        if selected {
            return edgeColor(kind).withAlphaComponent(isDarkAppearance ? 0.82 : 0.78)
        }
        return edgeColor(kind)
    }

    private func edgeAnchor(from center: CGPoint, toward target: CGPoint, size: CGSize) -> CGPoint {
        let dx = target.x - center.x
        let dy = target.y - center.y
        guard abs(dx) > 0.001 || abs(dy) > 0.001 else {
            return center
        }

        let halfWidth = max(1, size.width / 2)
        let halfHeight = max(1, size.height / 2)
        let scaleX = abs(dx) < 0.001 ? CGFloat.greatestFiniteMagnitude : halfWidth / abs(dx)
        let scaleY = abs(dy) < 0.001 ? CGFloat.greatestFiniteMagnitude : halfHeight / abs(dy)
        let scale = min(scaleX, scaleY) * 0.94
        return CGPoint(x: center.x + dx * scale, y: center.y + dy * scale)
    }

    private func drawArrowhead(
        at point: CGPoint,
        angle: CGFloat,
        color: NSColor,
        size: CGFloat,
        context: CGContext
    ) {
        let wing = CGFloat.pi * 0.82
        let left = CGPoint(
            x: point.x + cos(angle + wing) * size,
            y: point.y + sin(angle + wing) * size
        )
        let right = CGPoint(
            x: point.x + cos(angle - wing) * size,
            y: point.y + sin(angle - wing) * size
        )
        let path = CGMutablePath()
        path.move(to: point)
        path.addLine(to: left)
        path.addLine(to: right)
        path.closeSubpath()

        context.addPath(path)
        context.setFillColor(color.cgColor)
        context.fillPath()
    }

    private func drawEdgeLabel(
        _ label: String,
        near source: CGPoint,
        target: CGPoint,
        color: NSColor,
        context: CGContext
    ) {
        let midpoint = CGPoint(
            x: source.x + (target.x - source.x) * 0.5,
            y: source.y + (target.y - source.y) * 0.5
        )
        let font = NSFont.monospacedSystemFont(ofSize: 9, weight: .medium)
        let width = min(120, max(42, measuredTextWidth(label, font: font) + 14))
        let rect = CGRect(x: midpoint.x - width / 2, y: midpoint.y - 9, width: width, height: 18)
        let path = CGPath(roundedRect: rect, cornerWidth: 5, cornerHeight: 5, transform: nil)

        context.saveGState()
        context.addPath(path)
        context.setFillColor(NSColor.windowBackgroundColor.withAlphaComponent(isDarkAppearance ? 0.78 : 0.88).cgColor)
        context.fillPath()
        context.addPath(path)
        context.setStrokeColor(color.withAlphaComponent(0.42).cgColor)
        context.setLineWidth(0.8)
        context.strokePath()
        context.restoreGState()

        drawText(label, in: rect.insetBy(dx: 7, dy: 3), font: font, color: color)
    }

    private func drawNodes(_ layout: [PositionedDeclarationNode], context: CGContext) {
        if displayMode == .artistic {
            let center = graphCenter(for: layout)
            let sources = magneticSources(
                for: layout,
                sceneCenter: center
            )
            drawMagneticFieldLines(sources, context: context)
            for source in sources {
                drawArtisticSourceNode(source, context: context)
            }
            return
        }

        drawDiagramNodes(layout, context: context)
    }

    private func drawDiagramNodes(_ layout: [PositionedDeclarationNode], context: CGContext) {
        for positioned in layout {
            drawDiagramNode(positioned, context: context)
        }
    }

    private func drawDiagramNode(_ positioned: PositionedDeclarationNode, context: CGContext) {
        let node = positioned.node
        let padding = DiagramCardMetrics.padding
        let rect = CGRect(
            x: positioned.position.x - positioned.size.width / 2,
            y: positioned.position.y - positioned.size.height / 2,
            width: positioned.size.width,
            height: positioned.size.height
        )
        let path = CGPath(
            roundedRect: rect,
            cornerWidth: node.kind == .file ? 10 : 8,
            cornerHeight: node.kind == .file ? 10 : 8,
            transform: nil
        )

        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: 2),
            blur: selectedNodeID == node.id ? 8 : 3,
            color: NSColor.black.withAlphaComponent(selectedNodeID == node.id ? 0.18 : 0.08).cgColor
        )
        context.addPath(path)
        drawDiagramCardGradient(in: rect, clippedTo: path, context: context)
        context.restoreGState()

        context.addPath(path)
        context.setStrokeColor(
            selectedNodeID == node.id
                ? NSColor.controlAccentColor.cgColor
                : diagramCardStrokeColor().cgColor
        )
        context.setLineWidth(selectedNodeID == node.id ? 2 : 1)
        context.strokePath()

        context.saveGState()
        context.addPath(path)
        context.clip()
        if node.kind == .file {
            drawFileCard(node, in: rect, padding: padding)
            context.restoreGState()
            return
        }

        drawText(
            node.kind.rawValue,
            in: CGRect(
                x: rect.minX + padding,
                y: rect.minY + padding,
                width: rect.width - padding * 2,
                height: DiagramCardMetrics.kindHeight
            ),
            font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
            color: diagramSecondaryTextColor()
        )
        drawText(
            node.label,
            in: CGRect(
                x: rect.minX + padding,
                y: rect.minY + padding + DiagramCardMetrics.kindHeight + DiagramCardMetrics.headerGap,
                width: rect.width - padding * 2,
                height: DiagramCardMetrics.nameHeight
            ),
            font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            color: diagramPrimaryTextColor()
        )

        guard !positioned.rows.isEmpty else {
            context.restoreGState()
            return
        }

        let dividerY = rect.minY + DiagramCardMetrics.headerHeight
        context.setStrokeColor(diagramDividerColor().cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: rect.minX + padding, y: dividerY))
        context.addLine(to: CGPoint(x: rect.maxX - padding, y: dividerY))
        context.strokePath()

        for (index, row) in positioned.rows.enumerated() {
            let y = dividerY + padding + CGFloat(index) * DiagramCardMetrics.rowHeight
            let kindWidth = min(84, max(46, measuredTextWidth(
                row.kind.rawValue,
                font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
            ) + 8))
            drawText(
                row.kind.rawValue,
                in: CGRect(x: rect.minX + padding, y: y, width: kindWidth, height: DiagramCardMetrics.rowTextHeight),
                font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular),
                color: diagramSecondaryTextColor()
            )
            drawText(
                row.label,
                in: CGRect(
                    x: rect.minX + padding + kindWidth,
                    y: y,
                    width: rect.width - padding * 2 - kindWidth,
                    height: DiagramCardMetrics.rowTextHeight
                ),
                font: NSFont.systemFont(ofSize: 11, weight: .medium),
                color: diagramPrimaryTextColor()
            )
        }
        context.restoreGState()
    }

    private func drawDiagramCardGradient(
        in rect: CGRect,
        clippedTo path: CGPath,
        context: CGContext
    ) {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let gradient = CGGradient(
                colorsSpace: colorSpace,
                colors: diagramCardGradientColors() as CFArray,
                locations: [0.0, 1.0]
            )
        else {
            context.addPath(path)
            context.setFillColor(NSColor.controlBackgroundColor.withAlphaComponent(0.94).cgColor)
            context.fillPath()
            return
        }

        context.saveGState()
        context.addPath(path)
        context.clip()
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.midX, y: rect.minY),
            end: CGPoint(x: rect.midX, y: rect.maxY),
            options: []
        )
        context.restoreGState()
    }

    private func drawFileCard(
        _ node: DeclarationGraphNode,
        in rect: CGRect,
        padding: CGFloat
    ) {
        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }

        let headerY = rect.minY + DiagramFileContainerMetrics.headerPadding
        let iconRect = CGRect(
            x: rect.minX + padding,
            y: headerY + 1,
            width: 13,
            height: 15
        )
        drawFileIcon(in: iconRect, color: diagramSecondaryTextColor())
        drawText(
            node.label,
            in: CGRect(
                x: iconRect.maxX + 8,
                y: headerY,
                width: rect.width - padding * 2 - iconRect.width - 8,
                height: 18
            ),
            font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            color: diagramPrimaryTextColor()
        )

        let dividerY = rect.minY + DiagramFileContainerMetrics.headerHeight
        context.setStrokeColor(diagramDividerColor().withAlphaComponent(0.72).cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: rect.minX + padding, y: dividerY))
        context.addLine(to: CGPoint(x: rect.maxX - padding, y: dividerY))
        context.strokePath()
    }

    private func diagramPrimaryTextColor() -> NSColor {
        if isDarkAppearance {
            return NSColor(calibratedWhite: 0.94, alpha: 1)
        }
        return NSColor(calibratedWhite: 0.11, alpha: 1)
    }

    private func diagramSecondaryTextColor() -> NSColor {
        if isDarkAppearance {
            return NSColor(calibratedWhite: 0.68, alpha: 1)
        }
        return NSColor(calibratedWhite: 0.38, alpha: 1)
    }

    private func diagramCardStrokeColor() -> NSColor {
        if isDarkAppearance {
            return NSColor.separatorColor.withAlphaComponent(0.45)
        }
        return NSColor(calibratedWhite: 0.70, alpha: 0.62)
    }

    private func diagramDividerColor() -> NSColor {
        if isDarkAppearance {
            return NSColor.separatorColor.withAlphaComponent(0.28)
        }
        return NSColor(calibratedWhite: 0.73, alpha: 0.50)
    }

    private func diagramCardGradientColors() -> [CGColor] {
        if isDarkAppearance {
            return [
                NSColor(calibratedWhite: 0.145, alpha: 0.98).cgColor,
                NSColor(calibratedWhite: 0.115, alpha: 0.98).cgColor,
            ]
        }
        return [
            NSColor(calibratedWhite: 0.985, alpha: 0.98).cgColor,
            NSColor(calibratedWhite: 0.925, alpha: 0.98).cgColor,
        ]
    }

    private var isDarkAppearance: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private func drawFileIcon(in rect: CGRect, color: NSColor) {
        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }
        let fold = min(rect.width, rect.height) * 0.34
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + fold))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()

        context.addPath(path)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(1.4)
        context.strokePath()

        let foldPath = CGMutablePath()
        foldPath.move(to: CGPoint(x: rect.maxX - fold, y: rect.minY))
        foldPath.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.minY + fold))
        foldPath.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + fold))
        context.addPath(foldPath)
        context.strokePath()
    }

    private func drawArtisticNode(_ positioned: PositionedDeclarationNode, context: CGContext) {
        let node = positioned.node
        let diameter = min(positioned.size.width, positioned.size.height)
        let rect = CGRect(
            x: positioned.position.x - diameter / 2,
            y: positioned.position.y - diameter / 2,
            width: diameter,
            height: diameter
        )
        let color = NSColor.black

        context.setFillColor(color.cgColor)
        context.fillEllipse(in: rect)

        if selectedNodeID == node.id {
            context.setFillColor(NSColor.white.withAlphaComponent(0.16).cgColor)
            context.fillEllipse(in: rect.insetBy(dx: -8, dy: -8))
            context.setFillColor(color.cgColor)
            context.fillEllipse(in: rect)
        }
    }

    private func drawArtisticSourceNode(_ source: MagneticSource, context: CGContext) {
        let diameter = source.projectedRadius * 2
        let rect = CGRect(
            x: source.projectedPosition.x - source.projectedRadius,
            y: source.projectedPosition.y - source.projectedRadius,
            width: diameter,
            height: diameter
        )

        context.setFillColor(NSColor.black.cgColor)
        context.fillEllipse(in: rect)

        if selectedNodeID == source.id {
            context.setFillColor(NSColor.white.withAlphaComponent(0.16).cgColor)
            context.fillEllipse(in: rect.insetBy(dx: -8, dy: -8))
            context.setFillColor(NSColor.black.cgColor)
            context.fillEllipse(in: rect)
        }
    }

    private func drawMagneticSun(
        _ positioned: PositionedDeclarationNode,
        sceneCenter: CGPoint,
        relatedNodes: [(PositionedDeclarationNode, CGFloat)],
        context: CGContext
    ) {
        let diameter = min(positioned.size.width, positioned.size.height)
        let radius = diameter / 2
        let center = positioned.position
        let color = artisticSolarColor()
        let matrixShade = artisticShadeMatrixValue(at: center)
        let emission = artisticEmissionFactor(for: positioned)
        let intensity = (positioned.node.kind == .construct ? 1.22 : 1.08) * matrixShade * emission
        let flareRadius = radius * (positioned.node.kind == .construct ? 3.35 : 2.85)

        context.saveGState()
        context.setBlendMode(.screen)

        drawRadialFlare(
            center: center,
            radius: flareRadius * 1.08,
            color: color,
            alpha: min(1.0, 0.58 * intensity),
            context: context
        )
        drawRadialFlare(
            center: center,
            radius: radius * 1.72,
            color: color,
            alpha: min(1.0, 0.88 * intensity),
            context: context
        )
        drawRadialFlare(
            center: center,
            radius: max(7, radius * 0.72),
            color: leakCoreColor(for: color),
            alpha: min(1.0, 1.04 * intensity),
            context: context
        )

        context.restoreGState()
    }

    private func drawRadialFlare(
        center: CGPoint,
        radius: CGFloat,
        color: NSColor,
        alpha: CGFloat,
        context: CGContext
    ) {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let gradient = CGGradient(
                colorsSpace: colorSpace,
                colors: [
                    color.withAlphaComponent(alpha).cgColor,
                    color.withAlphaComponent(alpha * 0.48).cgColor,
                    color.withAlphaComponent(alpha * 0.14).cgColor,
                    color.withAlphaComponent(0).cgColor,
                ] as CFArray,
                locations: [0.0, 0.30, 0.70, 1.0]
            )
        else {
            return
        }

        context.drawRadialGradient(
            gradient,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: radius,
            options: [.drawsAfterEndLocation]
        )
    }

    private func leakCoreColor(for color: NSColor) -> NSColor {
        interpolate(.white, color, 0.38)
    }

    private func magneticSources(
        for layout: [PositionedDeclarationNode],
        sceneCenter: CGPoint
    ) -> [MagneticSource] {
        layout.map { positioned in
            let radius = min(positioned.size.width, positioned.size.height) / 2
            let depthSeed = CGFloat(stableVisualHash(positioned.id + "|z") % 10_000) / 10_000
            let z = (depthSeed - 0.5) * 520
            let perspective = 820 / (820 + z)
            let radialX = positioned.position.x - sceneCenter.x
            let radialY = positioned.position.y - sceneCenter.y
            let projectedPosition = CGPoint(
                x: sceneCenter.x + radialX * perspective,
                y: sceneCenter.y + radialY * perspective
            )
            let projectedRadius = radius * perspective
            let spin = CGFloat(stableVisualHash(positioned.id + "|spin") % 6283) / 1000
            let mx = cos(spin) * 0.42 + radialX * 0.005
            let my = sin(spin) * 0.42 + radialY * 0.005
            let momentLength = max(1, hypot(mx, my))
            let polarity: CGFloat = stableVisualHash(positioned.id).isMultiple(of: 2) ? 1 : -1
            return MagneticSource(
                id: positioned.id,
                position: positioned.position,
                projectedPosition: projectedPosition,
                radius: radius,
                projectedRadius: projectedRadius,
                strength: (positioned.node.kind == .construct ? 1.35 : 0.95) * projectedRadius,
                polarity: polarity,
                moment: CGVector(dx: mx / momentLength, dy: my / momentLength),
                z: z,
                perspective: perspective
            )
        }
    }

    private func drawMagneticFieldLines(_ sources: [MagneticSource], context: CGContext) {
        guard sources.count > 1 else {
            return
        }

        let color = artisticSolarColor()
        let fieldPath = CGMutablePath()
        let highlightPath = CGMutablePath()
        context.saveGState()
        context.setBlendMode(.screen)

        for leftIndex in 0..<(sources.count - 1) {
            for rightIndex in (leftIndex + 1)..<sources.count {
                appendMagneticPairBundle(
                    from: sources[leftIndex],
                    to: sources[rightIndex],
                    to: fieldPath,
                    highlightPath: highlightPath
                )
            }
        }

        drawGlowingPath(
            fieldPath,
            color: color,
            coreAlpha: 0.20,
            coreWidth: 0.74,
            glowAlpha: 0.12,
            glowWidth: 5.8,
            context: context
        )
        drawGlowingPath(
            highlightPath,
            color: leakCoreColor(for: color),
            coreAlpha: 0.34,
            coreWidth: 0.46,
            glowAlpha: 0.18,
            glowWidth: 3.4,
            context: context
        )

        context.restoreGState()
    }

    private func appendMagneticPairBundle(
        from left: MagneticSource,
        to right: MagneticSource,
        to path: CGMutablePath,
        highlightPath: CGMutablePath
    ) {
        let dx = right.projectedPosition.x - left.projectedPosition.x
        let dy = right.projectedPosition.y - left.projectedPosition.y
        let distance = max(1, hypot(dx, dy))
        let axis = atan2(dy, dx)
        let normal = axis + .pi / 2
        let pairSources = [left, right]
        let strandCount = max(8, min(28, Int(distance / 18)))

        for index in 0..<strandCount {
            let fraction = strandCount == 1 ? 0.5 : CGFloat(index) / CGFloat(strandCount - 1)
            let offset = (fraction - 0.5) * min(distance * 0.26, left.projectedRadius + right.projectedRadius)
            let start = CGPoint(
                x: left.projectedPosition.x + cos(axis) * left.projectedRadius * 0.92 + cos(normal) * offset,
                y: left.projectedPosition.y + sin(axis) * left.projectedRadius * 0.92 + sin(normal) * offset
            )
            appendMagneticPairStreamline(
                from: start,
                left: left,
                right: right,
                pairSources: pairSources,
                target: right,
                to: path
            )

            if index.isMultiple(of: 6) {
                appendMagneticPairStreamline(
                    from: start,
                    left: left,
                    right: right,
                    pairSources: pairSources,
                    target: right,
                    to: highlightPath
                )
            }
        }
    }

    private func drawGlowingPath(
        _ path: CGPath,
        color: NSColor,
        coreAlpha: CGFloat,
        coreWidth: CGFloat,
        glowAlpha: CGFloat,
        glowWidth: CGFloat,
        context: CGContext
    ) {
        context.saveGState()
        context.addPath(path)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(color.withAlphaComponent(glowAlpha * 0.38).cgColor)
        context.setLineWidth(glowWidth * 2.4)
        context.strokePath()
        context.restoreGState()

        context.saveGState()
        context.addPath(path)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(color.withAlphaComponent(glowAlpha).cgColor)
        context.setLineWidth(glowWidth)
        context.strokePath()
        context.restoreGState()

        context.saveGState()
        context.addPath(path)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(color.withAlphaComponent(coreAlpha).cgColor)
        context.setLineWidth(coreWidth)
        context.strokePath()
        context.restoreGState()
    }

    private func appendMagneticPairStreamline(
        from start: CGPoint,
        left: MagneticSource,
        right: MagneticSource,
        pairSources: [MagneticSource],
        target: MagneticSource,
        to path: CGMutablePath
    ) {
        var point = start
        var points: [CGPoint] = [point]
        var previousDirection = CGVector.zero
        let pairDistance = max(1, hypot(
            right.projectedPosition.x - left.projectedPosition.x,
            right.projectedPosition.y - left.projectedPosition.y
        ))
        let step: CGFloat = max(2.4, min(left.projectedRadius, right.projectedRadius) * 0.075)
        let maxSteps = max(42, min(180, Int(pairDistance / step) + 48))
        var reachedTarget = false

        for stepIndex in 0..<maxSteps {
            var field = magneticField(at: point, sources: pairSources)
            let attraction = pairConnectionField(at: point, target: target)
            field.dx += attraction.dx
            field.dy += attraction.dy
            let length = hypot(field.dx, field.dy)
            guard length > 0.0001 else {
                break
            }

            field.dx /= length
            field.dy /= length
            if previousDirection.dx != 0 || previousDirection.dy != 0 {
                field.dx = previousDirection.dx * 0.62 + field.dx * 0.38
                field.dy = previousDirection.dy * 0.62 + field.dy * 0.38
                let smoothedLength = max(0.0001, hypot(field.dx, field.dy))
                field.dx /= smoothedLength
                field.dy /= smoothedLength
            }
            previousDirection = field

            point.x += field.dx * step
            point.y += field.dy * step
            points.append(point)

            if stepIndex > 10,
                hypot(point.x - target.projectedPosition.x, point.y - target.projectedPosition.y) < target.projectedRadius * 0.86
            {
                reachedTarget = true
                break
            }
        }

        guard !reachedTarget else {
            appendSmoothPath(points, to: path)
            return
        }

        let dx = target.projectedPosition.x - point.x
        let dy = target.projectedPosition.y - point.y
        let distance = max(1, hypot(dx, dy))
        let end = CGPoint(
            x: target.projectedPosition.x - dx / distance * target.projectedRadius * 0.72,
            y: target.projectedPosition.y - dy / distance * target.projectedRadius * 0.72
        )
        points.append(end)
        appendSmoothPath(points, to: path)
    }

    private func appendSmoothPath(_ points: [CGPoint], to path: CGMutablePath) {
        guard let first = points.first else {
            return
        }
        guard points.count > 2 else {
            path.move(to: first)
            if let last = points.last, last != first {
                path.addLine(to: last)
            }
            return
        }

        path.move(to: first)
        for index in 0..<(points.count - 1) {
            let previous = index == 0 ? points[index] : points[index - 1]
            let current = points[index]
            let next = points[index + 1]
            let nextNext = index + 2 < points.count ? points[index + 2] : next
            let control1 = CGPoint(
                x: current.x + (next.x - previous.x) / 6,
                y: current.y + (next.y - previous.y) / 6
            )
            let control2 = CGPoint(
                x: next.x - (nextNext.x - current.x) / 6,
                y: next.y - (nextNext.y - current.y) / 6
            )
            path.addCurve(to: next, control1: control1, control2: control2)
        }
    }

    private func pairConnectionField(at point: CGPoint, target: MagneticSource) -> CGVector {
        let dx = target.projectedPosition.x - point.x
        let dy = target.projectedPosition.y - point.y
        let distance = max(1, hypot(dx, dy))
        let gain = min(0.020, target.projectedRadius / (distance * distance) * 0.18)
        return CGVector(dx: dx / distance * gain, dy: dy / distance * gain)
    }

    private func magneticField(at point: CGPoint, sources: [MagneticSource]) -> CGVector {
        var x: CGFloat = 0
        var y: CGFloat = 0

        for source in sources {
            let rx = point.x - source.projectedPosition.x
            let ry = point.y - source.projectedPosition.y
            let distanceSquared = max(source.projectedRadius * source.projectedRadius * 0.18, rx * rx + ry * ry)
            let distance = sqrt(distanceSquared)
            let rhatX = rx / distance
            let rhatY = ry / distance
            let dot = source.moment.dx * rhatX + source.moment.dy * rhatY
            let depthGain = max(0.46, min(1.42, source.perspective))
            let falloff = source.strength * depthGain / distanceSquared

            let dipoleX = (2 * dot * rhatX - source.moment.dx) * source.polarity
            let dipoleY = (2 * dot * rhatY - source.moment.dy) * source.polarity
            let swirl = source.projectedRadius / max(distance, 1) * 0.28

            x += (dipoleX + -rhatY * swirl) * falloff
            y += (dipoleY + rhatX * swirl) * falloff
        }

        return CGVector(dx: x, dy: y)
    }

    private func drawSolarEruptionField(
        _ positioned: PositionedDeclarationNode,
        axis: CGFloat,
        radius: CGFloat,
        flareRadius: CGFloat,
        color: NSColor,
        intensity: CGFloat,
        relatedNodes: [(PositionedDeclarationNode, CGFloat)],
        context: CGContext
    ) {
        let seed = CGFloat(stableVisualHash(positioned.id) % 6283) / 1000
        let time = CGFloat(CFAbsoluteTimeGetCurrent())
        let samples = positioned.node.kind == .construct ? 220 : 176
        let relationshipDirections = relatedNodes.prefix(5).map { target, strength in
            (
                angle: atan2(
                    target.position.y - positioned.position.y,
                    target.position.x - positioned.position.x
                ),
                distance: max(1, hypot(
                    target.position.x - positioned.position.x,
                    target.position.y - positioned.position.y
                )),
                strength: strength,
                phase: CGFloat(stableVisualHash(positioned.id + target.id) % 6283) / 1000
            )
        }

        for layer in 0..<3 {
            let layerScale = CGFloat(layer)
            let path = CGMutablePath()
            for index in 0...samples {
                let fraction = CGFloat(index) / CGFloat(samples)
                let theta = distortedSolarAngle(
                    axis + fraction * .pi * 2,
                    time: time,
                    seed: seed,
                    layer: layerScale,
                    relationshipDirections: relationshipDirections
                )
                let eruption = solarEruptionRadius(
                    theta: theta,
                    seed: seed,
                    time: time,
                    baseRadius: flareRadius,
                    layer: layerScale,
                    relationshipDirections: relationshipDirections
                )
                let point = CGPoint(
                    x: positioned.position.x + cos(theta) * eruption,
                    y: positioned.position.y + sin(theta) * eruption
                )
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            path.closeSubpath()

            drawEruptionLayer(
                path: path,
                center: positioned.position,
                radius: flareRadius * (1.45 + layerScale * 0.24),
                color: layer == 2 ? leakCoreColor(for: color) : color,
                alpha: min(0.58, intensity * (0.16 - layerScale * 0.032)),
                context: context
            )
        }

        drawRefractedRayProjection(
            positioned,
            axis: axis,
            seed: seed,
            time: time,
            innerRadius: radius * 0.46,
            flareRadius: flareRadius,
            intensity: intensity,
            relationshipDirections: relationshipDirections,
            context: context
        )
    }

    private func solarEruptionRadius(
        theta: CGFloat,
        seed: CGFloat,
        time: CGFloat,
        baseRadius: CGFloat,
        layer: CGFloat,
        relationshipDirections: [(angle: CGFloat, distance: CGFloat, strength: CGFloat, phase: CGFloat)]
    ) -> CGFloat {
        let fieldW = sin(time * 0.71 + seed * 1.3 + layer * 0.8)
        let fieldV = cos(time * 0.47 - seed * 0.9 + layer * 1.4)
        let wave1 = sin(theta * 7 + time * 1.25 + seed + fieldW)
        let wave2 = sin(theta * 13 - time * 1.74 + seed * 1.7 + fieldV)
        let wave3 = sin(theta * 23 + time * 2.58 + seed * 0.4 + fieldW * fieldV)
        let wave4 = sin((theta + fieldW) * 5 + (theta - fieldV) * 3 + time * 0.93)
        let wave5 = sin(theta * 41 - time * 3.7 + seed * 2.9)
        let wave6 = sin(theta * 67 + time * 4.4 - seed * 1.2)
        let turbulence = 0.38 + 0.20 * wave1 + 0.15 * wave2 + 0.10 * wave3 + 0.08 * wave4 + 0.06 * wave5 + 0.035 * wave6
        var relationshipLift: CGFloat = 0

        for relationship in relationshipDirections {
            let delta = abs(shortestAngleDelta(from: theta, to: relationship.angle))
            let width = 0.24 + relationship.strength * 0.34
            let lobe = exp(-(delta * delta) / max(0.001, width * width))
            let reach = min(1.2, max(0.28, relationship.distance / max(baseRadius, 1)))
            let magneticPulse = 0.72 + 0.28 * sin(time * 1.35 + relationship.phase + layer)
            let twistedLobe = lobe * (0.72 + 0.28 * sin(delta * 18 - time * 2.2 + relationship.phase))
            relationshipLift += twistedLobe * relationship.strength * reach * magneticPulse * 0.54
        }

        let pulse = 0.88 + 0.12 * sin(time * 2.4 + seed * 2 + layer)
        return baseRadius * (0.54 + layer * 0.17 + max(0, turbulence) * 0.56 + relationshipLift) * pulse
    }

    private func distortedSolarAngle(
        _ theta: CGFloat,
        time: CGFloat,
        seed: CGFloat,
        layer: CGFloat,
        relationshipDirections: [(angle: CGFloat, distance: CGFloat, strength: CGFloat, phase: CGFloat)]
    ) -> CGFloat {
        var distortion = sin(theta * 4 + time * 0.82 + seed + layer) * 0.018
        for relationship in relationshipDirections {
            let delta = shortestAngleDelta(from: theta, to: relationship.angle)
            let field = exp(-(delta * delta) / max(0.001, 0.52 * 0.52))
            let twist = sin(time * 1.1 + relationship.phase + layer * 0.7)
            distortion += delta * field * relationship.strength * (0.20 + 0.08 * twist)
        }
        return theta + distortion
    }

    private func drawRefractedRayProjection(
        _ positioned: PositionedDeclarationNode,
        axis: CGFloat,
        seed: CGFloat,
        time: CGFloat,
        innerRadius: CGFloat,
        flareRadius: CGFloat,
        intensity: CGFloat,
        relationshipDirections: [(angle: CGFloat, distance: CGFloat, strength: CGFloat, phase: CGFloat)],
        context: CGContext
    ) {
        let rayCount = positioned.node.kind == .construct ? 164 : 124
        for index in 0..<rayCount {
            let fraction = CGFloat(index) / CGFloat(rayCount)
            let baseTheta = axis + fraction * .pi * 2 + seed * 0.11
            let theta = distortedSolarAngle(
                baseTheta,
                time: time * 1.17,
                seed: seed + fraction,
                layer: 1.8,
                relationshipDirections: relationshipDirections
            )
            let stopColor = circularProjectionColor(at: fraction, baseColor: artisticSolarColor())
            let micro = 0.5 + 0.5 * sin(fraction * .pi * 96 + time * 5.0 + seed)
            let macro = 0.5 + 0.5 * sin(fraction * .pi * 13 - time * 1.7 + seed * 2)
            let eruption = solarEruptionRadius(
                theta: theta,
                seed: seed,
                time: time,
                baseRadius: flareRadius,
                layer: 1.35,
                relationshipDirections: relationshipDirections
            )
            let length = max(4, eruption - innerRadius) * (0.46 + 0.42 * macro)
            let thickness = max(0.7, flareRadius * (0.004 + 0.012 * micro))
            let alpha = min(0.34, intensity * (0.045 + 0.085 * micro))
            drawProjectedRay(
                center: positioned.position,
                angle: theta,
                innerRadius: innerRadius,
                length: length,
                thickness: thickness,
                color: stopColor,
                alpha: alpha,
                context: context
            )
        }
    }

    private func drawProjectedRay(
        center: CGPoint,
        angle: CGFloat,
        innerRadius: CGFloat,
        length: CGFloat,
        thickness: CGFloat,
        color: NSColor,
        alpha: CGFloat,
        context: CGContext
    ) {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let gradient = CGGradient(
                colorsSpace: colorSpace,
                colors: [
                    color.withAlphaComponent(0).cgColor,
                    color.withAlphaComponent(alpha * 0.72).cgColor,
                    leakCoreColor(for: color).withAlphaComponent(alpha).cgColor,
                    color.withAlphaComponent(alpha * 0.34).cgColor,
                    color.withAlphaComponent(0).cgColor,
                ] as CFArray,
                locations: [0.0, 0.18, 0.42, 0.72, 1.0]
            )
        else {
            return
        }

        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: angle)
        let rect = CGRect(x: innerRadius, y: -thickness / 2, width: length, height: thickness)
        context.addEllipse(in: rect)
        context.clip()
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: 0),
            end: CGPoint(x: rect.maxX, y: 0),
            options: []
        )
        context.restoreGState()
    }

    private func circularProjectionColor(at fraction: CGFloat, baseColor: NSColor) -> NSColor {
        let stops: [NSColor] = [
            baseColor,
            NSColor(calibratedRed: 0.15, green: 0.42, blue: 1.0, alpha: 1),
            NSColor(calibratedRed: 0.68, green: 0.28, blue: 1.0, alpha: 1),
            NSColor(calibratedRed: 0.88, green: 0.98, blue: 1.0, alpha: 1),
            baseColor,
        ]
        let position = max(0, min(0.999, fraction)) * CGFloat(stops.count - 1)
        let lowerIndex = Int(floor(position))
        let upperIndex = min(stops.count - 1, lowerIndex + 1)
        return interpolate(stops[lowerIndex], stops[upperIndex], position - CGFloat(lowerIndex))
    }

    private func drawEruptionLayer(
        path: CGPath,
        center: CGPoint,
        radius: CGFloat,
        color: NSColor,
        alpha: CGFloat,
        context: CGContext
    ) {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let gradient = CGGradient(
                colorsSpace: colorSpace,
                colors: [
                    color.withAlphaComponent(alpha).cgColor,
                    color.withAlphaComponent(alpha * 0.42).cgColor,
                    color.withAlphaComponent(alpha * 0.10).cgColor,
                    color.withAlphaComponent(0).cgColor,
                ] as CFArray,
                locations: [0.0, 0.38, 0.78, 1.0]
            )
        else {
            return
        }

        context.saveGState()
        context.addPath(path)
        context.clip()
        context.drawRadialGradient(
            gradient,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: radius,
            options: [.drawsAfterEndLocation]
        )
        context.restoreGState()
    }

    private func closestRelationshipDirection(
        to angle: CGFloat,
        directions: [(angle: CGFloat, distance: CGFloat, strength: CGFloat)]
    ) -> (angle: CGFloat, distance: CGFloat, strength: CGFloat)? {
        directions.min {
            abs(shortestAngleDelta(from: angle, to: $0.angle)) < abs(shortestAngleDelta(from: angle, to: $1.angle))
        }
    }

    private func lerpAngle(from start: CGFloat, to end: CGFloat, amount: CGFloat) -> CGFloat {
        start + shortestAngleDelta(from: start, to: end) * max(0, min(1, amount))
    }

    private func shortestAngleDelta(from start: CGFloat, to end: CGFloat) -> CGFloat {
        var delta = end - start
        while delta > .pi {
            delta -= .pi * 2
        }
        while delta < -.pi {
            delta += .pi * 2
        }
        return delta
    }

    private func stableVisualHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }

    private func drawFlareStreak(
        center: CGPoint,
        length: CGFloat,
        thickness: CGFloat,
        angle: CGFloat,
        color: NSColor,
        alpha: CGFloat,
        context: CGContext
    ) {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let gradient = CGGradient(
                colorsSpace: colorSpace,
                colors: [
                    color.withAlphaComponent(0).cgColor,
                    color.withAlphaComponent(alpha * 0.44).cgColor,
                    color.withAlphaComponent(alpha).cgColor,
                    color.withAlphaComponent(alpha * 0.44).cgColor,
                    color.withAlphaComponent(0).cgColor,
                ] as CFArray,
                locations: [0.0, 0.24, 0.5, 0.76, 1.0]
            )
        else {
            return
        }

        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: angle)
        let rect = CGRect(
            x: -length / 2,
            y: -thickness / 2,
            width: length,
            height: thickness
        )
        context.addEllipse(in: rect)
        context.clip()
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: 0),
            end: CGPoint(x: rect.maxX, y: 0),
            options: []
        )
        context.restoreGState()
    }

    private func flareAxis(
        for positioned: PositionedDeclarationNode,
        sceneCenter: CGPoint,
        relatedNodes: [(PositionedDeclarationNode, CGFloat)]
    ) -> CGFloat {
        guard !relatedNodes.isEmpty else {
            return atan2(positioned.position.y - sceneCenter.y, positioned.position.x - sceneCenter.x)
        }

        var vx: CGFloat = 0
        var vy: CGFloat = 0
        for (target, strength) in relatedNodes {
            let dx = target.position.x - positioned.position.x
            let dy = target.position.y - positioned.position.y
            let distance = max(1, hypot(dx, dy))
            let weight = max(0.08, strength) / distance
            vx += dx * weight
            vy += dy * weight
        }
        return atan2(vy, vx)
    }

    private func artisticRelatedNodesByID(
        for layout: [PositionedDeclarationNode]
    ) -> [String: [(PositionedDeclarationNode, CGFloat)]] {
        let positionedByID = Dictionary(uniqueKeysWithValues: layout.map { ($0.id, $0) })
        var related: [String: [(PositionedDeclarationNode, CGFloat)]] = [:]

        for relationship in artisticRelationshipPairs(for: layout) {
            guard let source = positionedByID[relationship.sourceID],
                let target = positionedByID[relationship.targetID]
            else {
                continue
            }
            related[source.id, default: []].append((target, relationship.strength))
            related[target.id, default: []].append((source, relationship.strength * 0.86))
        }

        for key in related.keys {
            related[key]?.sort {
                if $0.1 != $1.1 {
                    return $0.1 > $1.1
                }
                return $0.0.id < $1.0.id
            }
        }

        return related
    }

    private func artisticEmissionFactor(for positioned: PositionedDeclarationNode) -> CGFloat {
        let diameter = max(1, min(positioned.size.width, positioned.size.height))
        let referenceDiameter: CGFloat = 64
        let inverseSize = pow(referenceDiameter / diameter, 0.62)
        return max(0.48, min(1.65, inverseSize))
    }

    private func makeParametricDepthGlowImage(color: NSColor, intensity: CGFloat) -> CGImage? {
        let dimension = 224
        let bytesPerPixel = 4
        let bytesPerRow = dimension * bytesPerPixel
        let componentColor = color.usingColorSpace(.sRGB) ?? color
        let red = componentColor.redComponent
        let green = componentColor.greenComponent
        let blue = componentColor.blueComponent
        var pixels = [UInt8](repeating: 0, count: dimension * bytesPerRow)

        for y in 0..<dimension {
            for x in 0..<dimension {
                let nx = (CGFloat(x) + 0.5) / CGFloat(dimension) * 2 - 1
                let ny = (CGFloat(y) + 0.5) / CGFloat(dimension) * 2 - 1
                let radiusSquared = nx * nx + ny * ny
                let offset = y * bytesPerRow + x * bytesPerPixel
                guard radiusSquared <= 1 else {
                    continue
                }

                let z = sqrt(max(0, 1 - radiusSquared))
                let normalX = nx * 0.36
                let normalY = ny * 0.36
                let normalZ = z
                let normalLength = max(0.001, sqrt(normalX * normalX + normalY * normalY + normalZ * normalZ))
                let light = max(0, (normalX * -0.28 + normalY * -0.62 + normalZ * 0.73) / normalLength)
                let depth = 0.62 + 0.38 * light
                let radial = sqrt(radiusSquared)
                let falloff = pow(max(0, 1 - smoothstep(radial)), 2.2)
                let axialDepth = 0.80 + 0.20 * (1 - smoothstep((ny + 1) / 2))
                let alpha = min(1, intensity * falloff * depth * axialDepth * 0.74)
                let shade = 0.82 + 0.18 * depth
                let premultiplied = alpha * shade

                pixels[offset] = UInt8(max(0, min(255, red * premultiplied * 255)))
                pixels[offset + 1] = UInt8(max(0, min(255, green * premultiplied * 255)))
                pixels[offset + 2] = UInt8(max(0, min(255, blue * premultiplied * 255)))
                pixels[offset + 3] = UInt8(max(0, min(255, alpha * 255)))
            }
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        else {
            return nil
        }

        return CGImage(
            width: dimension,
            height: dimension,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    private func artisticRelationshipStrengths(
        for layout: [PositionedDeclarationNode]
    ) -> [String: CGFloat] {
        Dictionary(uniqueKeysWithValues: artisticRelationshipPairs(for: layout).map {
            (artisticRelationshipKey($0.sourceID, $0.targetID), $0.strength)
        })
    }

    private func artisticRelationshipPairs(
        for layout: [PositionedDeclarationNode]
    ) -> [ArtisticRelationshipPair] {
        let visibleIDs = Set(layout.map(\.id))
        let nodesByID = graph.nodeByID
        var ownerByMemberID: [String: String] = [:]
        var pairsByKey: [String: ArtisticRelationshipPair] = [:]

        for edge in graph.edges where edge.kind == .contains {
            guard let source = nodesByID[edge.sourceID],
                let target = nodesByID[edge.targetID],
                source.kind == .construct,
                Self.artisticAggregatedMemberKinds.contains(target.kind)
            else {
                continue
            }
            ownerByMemberID[target.id] = edge.sourceID
        }

        for edge in graph.edges {
            let sourceID = visibleIDs.contains(edge.sourceID) ? edge.sourceID : ownerByMemberID[edge.sourceID]
            let targetID = visibleIDs.contains(edge.targetID) ? edge.targetID : ownerByMemberID[edge.targetID]
            guard let sourceID,
                let targetID,
                sourceID != targetID,
                visibleIDs.contains(sourceID),
                visibleIDs.contains(targetID)
            else {
                continue
            }

            let key = artisticRelationshipKey(sourceID, targetID)
            let strength = artisticRelationshipStrength(for: edge.kind)
            if let current = pairsByKey[key] {
                pairsByKey[key] = ArtisticRelationshipPair(
                    sourceID: current.sourceID,
                    targetID: current.targetID,
                    strength: max(current.strength, strength)
                )
            } else {
                pairsByKey[key] = ArtisticRelationshipPair(
                    sourceID: sourceID,
                    targetID: targetID,
                    strength: strength
                )
            }
        }

        return pairsByKey.values.sorted {
            if $0.strength != $1.strength {
                return $0.strength > $1.strength
            }
            if $0.sourceID != $1.sourceID {
                return $0.sourceID < $1.sourceID
            }
            return $0.targetID < $1.targetID
        }
    }

    private func artisticRelationshipKey(_ leftID: String, _ rightID: String) -> String {
        leftID < rightID ? "\(leftID)|\(rightID)" : "\(rightID)|\(leftID)"
    }

    private func artisticRelationshipStrength(for kind: SemanticGraphRelationKind) -> CGFloat {
        switch kind {
        case .contains:
            return 0.92
        case .conformsTo, .extends:
            return 0.82
        case .referencesType, .resolvesTo:
            return 0.74
        case .calls:
            return 0.58
        case .dependsOn:
            return 0.52
        default:
            return 0.42
        }
    }

    private func smoothstep(_ value: CGFloat) -> CGFloat {
        let t = max(0, min(1, value))
        return t * t * (3 - 2 * t)
    }

    private static let artisticAggregatedMemberKinds: Set<SemanticGraphEntityKind> = [
        .state,
        .binding,
        .derived,
        .value,
        .function,
        .initializer,
    ]

    private func graphCenter(for layout: [PositionedDeclarationNode]) -> CGPoint {
        guard !layout.isEmpty else {
            return CGPoint(x: bounds.midX, y: bounds.midY)
        }

        let total = layout.reduce(CGPoint.zero) { partial, positioned in
            CGPoint(
                x: partial.x + positioned.position.x,
                y: partial.y + positioned.position.y
            )
        }
        return CGPoint(
            x: total.x / CGFloat(layout.count),
            y: total.y / CGFloat(layout.count)
        )
    }

    private func artisticNodeColor() -> NSColor {
        NSColor(calibratedRed: 0.18, green: 0.78, blue: 0.92, alpha: 1)
    }

    private func artisticSolarColor() -> NSColor {
        NSColor(calibratedRed: 0.08, green: 0.86, blue: 1.0, alpha: 1)
    }

    private func artisticShadeMatrixValue(at point: CGPoint) -> CGFloat {
        let nx = max(0, min(1, point.x / max(1, bounds.width)))
        let ny = max(0, min(1, point.y / max(1, bounds.height)))
        let horizontal = 0.82 + 0.18 * nx
        let vertical = 0.74 + 0.26 * (1 - abs(ny - 0.5) * 2)
        return horizontal * vertical
    }

    private func interpolate(_ lhs: NSColor, _ rhs: NSColor, _ amount: CGFloat) -> NSColor {
        let t = max(0, min(1, amount))
        let left = lhs.usingColorSpace(.sRGB) ?? lhs
        let right = rhs.usingColorSpace(.sRGB) ?? rhs
        return NSColor(
            calibratedRed: left.redComponent + (right.redComponent - left.redComponent) * t,
            green: left.greenComponent + (right.greenComponent - left.greenComponent) * t,
            blue: left.blueComponent + (right.blueComponent - left.blueComponent) * t,
            alpha: left.alphaComponent + (right.alphaComponent - left.alphaComponent) * t
        )
    }

    private func interpolate(row: [NSColor], amount: CGFloat) -> NSColor {
        let t = max(0, min(1, amount))
        if t < 0.5 {
            return interpolate(row[0], row[1], t * 2)
        }
        return interpolate(row[1], row[2], (t - 0.5) * 2)
    }

    private func drawText(_ string: String, in rect: CGRect, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        NSString(string: string).draw(in: rect, withAttributes: attributes)
    }

    private func measuredTextWidth(_ string: String, font: NSFont) -> CGFloat {
        NSString(string: string).size(withAttributes: [.font: font]).width
    }

    private func positionedNodes(in size: CGSize) -> [PositionedDeclarationNode] {
        if let cachedLayout, cachedLayoutSize == size {
            return cachedLayout
        }

        let layout = ForceDirectedDeclarationLayout(
            nodes: graph.nodes,
            edges: graph.edges,
            displayMode: displayMode,
            viewportSize: size
        )
        .solve()

        cachedLayout = layout
        cachedLayoutSize = size
        return layout
    }

    private func applyInitialViewportFitIfNeeded(
        for layout: [PositionedDeclarationNode],
        in size: CGSize
    ) {
        guard displayMode == .diagram,
            !hasUserAdjustedViewport,
            let graphBounds = graphBounds(for: layout),
            graphBounds.width > 0,
            graphBounds.height > 0,
            size.width > 0,
            size.height > 0
        else {
            return
        }

        let padding: CGFloat = 34
        let availableWidth = max(1, size.width - padding * 2)
        let availableHeight = max(1, size.height - padding * 2)
        let fittedScale = min(
            1,
            max(
                0.18,
                min(
                    availableWidth / graphBounds.width,
                    availableHeight / graphBounds.height
                )
            )
        )

        zoomScale = fittedScale
        panOffset = CGPoint(
            x: (size.width - graphBounds.width * fittedScale) / 2 - graphBounds.minX * fittedScale,
            y: (size.height - graphBounds.height * fittedScale) / 2 - graphBounds.minY * fittedScale
        )
    }

    private func graphBounds(for layout: [PositionedDeclarationNode]) -> CGRect? {
        guard let first = layout.first else {
            return nil
        }

        var rect = diagramRect(for: first)
        for positioned in layout.dropFirst() {
            rect = rect.union(diagramRect(for: positioned))
        }
        return rect
    }

    private func hitNode(at point: CGPoint) -> PositionedDeclarationNode? {
        let layout = positionedNodes(in: bounds.size)
        if displayMode != .artistic {
            if let foregroundHit = layout.reversed().first(where: { positioned in
                positioned.node.kind != .file && diagramRect(for: positioned).contains(point)
            }) {
                return foregroundHit
            }
            return layout.reversed().first { positioned in
                positioned.node.kind == .file && diagramRect(for: positioned).contains(point)
            }
        }

        return layout.last { positioned in
            let radius = min(positioned.size.width, positioned.size.height) / 2
            return hypot(point.x - positioned.position.x, point.y - positioned.position.y) <= radius
        }
    }

    private func diagramRect(for positioned: PositionedDeclarationNode) -> CGRect {
        CGRect(
            x: positioned.position.x - positioned.size.width / 2,
            y: positioned.position.y - positioned.size.height / 2,
            width: positioned.size.width,
            height: positioned.size.height
        )
    }

    private func graphPoint(from viewPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: (viewPoint.x - panOffset.x) / zoomScale,
            y: (viewPoint.y - panOffset.y) / zoomScale
        )
    }

    private func zoom(around anchor: CGPoint, by factor: CGFloat) {
        let oldScale = zoomScale
        let newScale = min(2.4, max(0.18, oldScale * factor))
        guard newScale != oldScale else {
            return
        }

        let graphAnchor = graphPoint(from: anchor)
        zoomScale = newScale
        hasUserAdjustedViewport = true
        panOffset = CGPoint(
            x: anchor.x - graphAnchor.x * newScale,
            y: anchor.y - graphAnchor.y * newScale
        )
        needsDisplay = true
    }

    private func nodeColor(_ kind: SemanticGraphEntityKind) -> NSColor {
        switch kind {
        case .file: return NSColor(calibratedRed: 0.30, green: 0.43, blue: 0.55, alpha: 1)
        case .packageSpace: return NSColor(calibratedRed: 0.49, green: 0.38, blue: 0.64, alpha: 1)
        case .packageEntry: return NSColor(calibratedRed: 0.63, green: 0.47, blue: 0.70, alpha: 1)
        case .namespace: return NSColor(calibratedRed: 0.23, green: 0.54, blue: 0.54, alpha: 1)
        case .construct: return NSColor(calibratedRed: 0.74, green: 0.28, blue: 0.22, alpha: 1)
        case .enumeration: return NSColor(calibratedRed: 0.60, green: 0.37, blue: 0.24, alpha: 1)
        case .protocolDefinition: return NSColor(calibratedRed: 0.39, green: 0.32, blue: 0.48, alpha: 1)
        case .macro: return NSColor(calibratedRed: 0.18, green: 0.32, blue: 0.44, alpha: 1)
        case .typeExtension: return NSColor(calibratedRed: 0.30, green: 0.57, blue: 0.55, alpha: 1)
        case .mainBlock: return NSColor(calibratedRed: 0.86, green: 0.66, blue: 0.22, alpha: 1)
        case .state: return NSColor(calibratedRed: 0.70, green: 0.35, blue: 0.15, alpha: 1)
        case .binding: return NSColor(calibratedRed: 0.49, green: 0.34, blue: 0.24, alpha: 1)
        case .derived: return NSColor(calibratedRed: 0.16, green: 0.58, blue: 0.52, alpha: 1)
        case .value: return NSColor(calibratedRed: 0.64, green: 0.34, blue: 0.43, alpha: 1)
        case .initializer: return NSColor(calibratedRed: 0.42, green: 0.45, blue: 0.49, alpha: 1)
        case .function: return NSColor(calibratedRed: 0.16, green: 0.42, blue: 0.84, alpha: 1)
        case .parameter: return NSColor(calibratedRed: 0.51, green: 0.56, blue: 0.64, alpha: 1)
        case .member: return NSColor(calibratedRed: 0.34, green: 0.51, blue: 0.34, alpha: 1)
        case .typeReference: return NSColor(calibratedRed: 0.62, green: 0.65, blue: 0.68, alpha: 1)
        case .macroApplication: return NSColor(calibratedRed: 0.86, green: 0.39, blue: 0.37, alpha: 1)
        case .localSymbol: return NSColor(calibratedRed: 0.35, green: 0.38, blue: 0.42, alpha: 1)
        case .unresolved: return NSColor(calibratedWhite: 0.44, alpha: 1)
        }
    }

    private func edgeColor(_ kind: SemanticGraphRelationKind) -> NSColor {
        if displayMode == .artistic {
            switch kind {
            case .contains:
                return NSColor.white.withAlphaComponent(0.20)
            case .conformsTo, .extends:
                return NSColor(calibratedRed: 0.48, green: 0.92, blue: 0.86, alpha: 0.34)
            case .referencesType, .referencesIdentity, .resolvesTo:
                return NSColor.white.withAlphaComponent(0.10)
            case .appliesMacro, .targetsMacro:
                return NSColor(calibratedRed: 1.00, green: 0.36, blue: 0.58, alpha: 0.25)
            case .dependsOn, .mutates, .aliases, .calls:
                return NSColor.white.withAlphaComponent(0.12)
            }
        }

        switch kind {
        case .contains:
            return NSColor.labelColor.withAlphaComponent(0.24)
        case .conformsTo, .extends:
            return NSColor(calibratedRed: 0.21, green: 0.45, blue: 0.45, alpha: 0.56)
        case .referencesType, .referencesIdentity, .resolvesTo:
            return NSColor(calibratedRed: 0.16, green: 0.36, blue: 0.72, alpha: 0.48)
        case .appliesMacro, .targetsMacro:
            return NSColor(calibratedRed: 0.72, green: 0.22, blue: 0.28, alpha: 0.50)
        case .dependsOn, .mutates, .aliases, .calls:
            return NSColor(calibratedRed: 0.45, green: 0.35, blue: 0.24, alpha: 0.44)
        }
    }
}

private enum DeclarationNodeMetrics {
    private static let minWidth: CGFloat = 150
    private static let constructMinWidth: CGFloat = 210
    private static let maxWidth: CGFloat = 420

    static func size(for node: DeclarationGraphNode) -> CGSize {
        size(for: node, displayMode: .diagram)
    }

    static func size(
        for node: DeclarationGraphNode,
        displayMode: DeclarationGraphDisplayMode,
        fieldCount: Int = 0,
        rows: [DeclarationGraphNode] = []
    ) -> CGSize {
        guard displayMode == .diagram else {
            let diameter = artisticDiameter(for: node.kind, fieldCount: fieldCount)
            return CGSize(width: diameter, height: diameter)
        }

        if node.kind == .file {
            return DiagramFileContainerLayout.size(for: node, childSizes: [])
        }

        if node.kind == .construct {
            let headerWidth = ceil(measuredWidth(node.label, font: nameFont()))
            let rowWidth = rows.map {
                ceil(measuredWidth($0.label, font: rowFont()))
                    + ceil(measuredWidth($0.kind.rawValue, font: kindFont()))
                    + 8
            }.max() ?? 0
            let width = min(
                maxWidth,
                max(
                    constructMinWidth,
                    max(
                        headerWidth + DiagramCardMetrics.padding * 2,
                        rowWidth + DiagramCardMetrics.padding * 2
                    )
                )
            )
            let rowBlockHeight = rows.isEmpty
                ? 0
                : DiagramCardMetrics.padding + CGFloat(rows.count) * DiagramCardMetrics.rowHeight
            let height = DiagramCardMetrics.headerHeight + rowBlockHeight + DiagramCardMetrics.padding
            return CGSize(width: width, height: height)
        }

        let labelWidth = ceil(measuredWidth(node.label, font: nameFont()))
        let kindWidth = ceil(measuredWidth(node.kind.rawValue, font: kindFont()))
        let contentWidth = max(labelWidth, kindWidth) + DiagramCardMetrics.padding * 2
        return CGSize(
            width: min(maxWidth, max(minWidth, contentWidth)),
            height: DiagramCardMetrics.headerHeight
        )
    }

    private static func artisticDiameter(
        for kind: SemanticGraphEntityKind,
        fieldCount: Int
    ) -> CGFloat {
        switch kind {
        case .construct:
            return 92 + min(92, sqrt(CGFloat(fieldCount)) * 24)
        case .mainBlock, .file:
            return 72
        case .state, .binding, .derived, .value:
            return 28
        case .function, .initializer:
            return 34
        case .protocolDefinition, .enumeration, .typeExtension, .namespace:
            return 54
        case .typeReference:
            return 18
        case .parameter, .member, .macroApplication, .packageEntry, .localSymbol:
            return 22
        case .macro, .packageSpace:
            return 40
        case .unresolved:
            return 16
        }
    }

    private static func nameFont() -> NSFont {
        NSFont.systemFont(ofSize: 13, weight: .semibold)
    }

    private static func kindFont() -> NSFont {
        NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
    }

    private static func rowFont() -> NSFont {
        NSFont.systemFont(ofSize: 11, weight: .medium)
    }

    private static func measuredWidth(_ string: String, font: NSFont) -> CGFloat {
        NSString(string: string).size(withAttributes: [.font: font]).width
    }
}

private enum DiagramCardMetrics {
    static let padding: CGFloat = 16
    static let headerGap: CGFloat = 4
    static let kindHeight: CGFloat = 14
    static let nameHeight: CGFloat = 17
    static let rowHeight: CGFloat = 24
    static let rowTextHeight: CGFloat = 14

    static var headerHeight: CGFloat {
        padding + kindHeight + headerGap + nameHeight + padding
    }
}

private enum DiagramFileContainerMetrics {
    static let minimumWidth: CGFloat = 280
    static let maximumColumns = 2
    static let padding: CGFloat = 18
    static let gap: CGFloat = 14
    static let headerHeight: CGFloat = 40
    static let headerPadding: CGFloat = 11
}

private struct DiagramFileContainerPacking {
    let size: CGSize
    let columns: Int
    let columnWidths: [CGFloat]
    let rowHeights: [CGFloat]
}

private enum DiagramFileContainerLayout {
    static func size(for file: DeclarationGraphNode, childSizes: [CGSize]) -> CGSize {
        packing(for: file, childSizes: childSizes).size
    }

    static func childCenter(
        in file: ForceDirectedDeclarationLayout.Body,
        offset: Int,
        childSizes: [CGSize]
    ) -> CGPoint {
        let packing = packing(for: file.node, childSizes: childSizes)
        guard !packing.columnWidths.isEmpty, !packing.rowHeights.isEmpty else {
            return CGPoint(x: file.x, y: file.y + DiagramFileContainerMetrics.headerHeight)
        }

        let column = min(packing.columns - 1, offset % packing.columns)
        let row = min(packing.rowHeights.count - 1, offset / packing.columns)
        let leadingWidth = packing.columnWidths.prefix(column).reduce(CGFloat.zero, +)
            + CGFloat(column) * DiagramFileContainerMetrics.gap
        let leadingHeight = packing.rowHeights.prefix(row).reduce(CGFloat.zero, +)
            + CGFloat(row) * DiagramFileContainerMetrics.gap
        let origin = CGPoint(
            x: file.x - packing.size.width / 2 + DiagramFileContainerMetrics.padding,
            y: file.y - packing.size.height / 2 + DiagramFileContainerMetrics.headerHeight + DiagramFileContainerMetrics.padding
        )

        return CGPoint(
            x: origin.x + leadingWidth + packing.columnWidths[column] / 2,
            y: origin.y + leadingHeight + packing.rowHeights[row] / 2
        )
    }

    static func packing(for file: DeclarationGraphNode, childSizes: [CGSize]) -> DiagramFileContainerPacking {
        let columns = columnCount(for: childSizes.count)
        let rows = childSizes.isEmpty ? 0 : Int(ceil(CGFloat(childSizes.count) / CGFloat(columns)))
        var columnWidths = Array(repeating: CGFloat.zero, count: max(columns, 1))
        var rowHeights = Array(repeating: CGFloat.zero, count: max(rows, 0))

        for (index, size) in childSizes.enumerated() {
            let column = index % columns
            let row = index / columns
            columnWidths[column] = max(columnWidths[column], size.width)
            rowHeights[row] = max(rowHeights[row], size.height)
        }

        let contentWidth = childSizes.isEmpty
            ? CGFloat.zero
            : columnWidths.reduce(CGFloat.zero, +) + CGFloat(max(0, columns - 1)) * DiagramFileContainerMetrics.gap
        let contentHeight = childSizes.isEmpty
            ? CGFloat.zero
            : rowHeights.reduce(CGFloat.zero, +) + CGFloat(max(0, rows - 1)) * DiagramFileContainerMetrics.gap
        let titleWidth = ceil(measuredWidth(file.label, font: titleFont()))
            + DiagramFileContainerMetrics.padding * 2
            + 24
        let width = max(
            DiagramFileContainerMetrics.minimumWidth,
            titleWidth,
            contentWidth + DiagramFileContainerMetrics.padding * 2
        )
        let height = DiagramFileContainerMetrics.headerHeight
            + DiagramFileContainerMetrics.padding
            + max(contentHeight, 54)
            + DiagramFileContainerMetrics.padding

        return DiagramFileContainerPacking(
            size: CGSize(width: ceil(width), height: ceil(height)),
            columns: max(columns, 1),
            columnWidths: columnWidths,
            rowHeights: rowHeights
        )
    }

    private static func columnCount(for childCount: Int) -> Int {
        guard childCount > 0 else {
            return 1
        }
        return min(DiagramFileContainerMetrics.maximumColumns, max(1, Int(ceil(sqrt(CGFloat(childCount))))))
    }

    private static func titleFont() -> NSFont {
        NSFont.systemFont(ofSize: 13, weight: .semibold)
    }

    private static func measuredWidth(_ string: String, font: NSFont) -> CGFloat {
        NSString(string: string).size(withAttributes: [.font: font]).width
    }
}

struct ForceDirectedDeclarationLayout {
    struct Body {
        let node: DeclarationGraphNode
        var size: CGSize
        var x: CGFloat
        var y: CGFloat
        var vx: CGFloat = 0
        var vy: CGFloat = 0

        var radius: CGFloat {
            hypot(size.width, size.height) / 2
        }
    }

    let nodes: [DeclarationGraphNode]
    let edges: [DeclarationGraphEdge]
    let displayMode: DeclarationGraphDisplayMode
    let viewportSize: CGSize

    func solve() -> [PositionedDeclarationNode] {
        guard !nodes.isEmpty else {
            return []
        }

        if displayMode == .diagram {
            return solveDiagramBoard()
        }

        var bodies = seededBodies()
        guard !bodies.isEmpty else {
            return []
        }
        let indexByID = Dictionary(uniqueKeysWithValues: bodies.enumerated().map { ($0.element.node.id, $0.offset) })
        let fileContainmentPairs = fileContainmentPairKeys(in: bodies)
        let links = simulationEdges().compactMap { edge -> ForceLink? in
            guard let sourceIndex = indexByID[edge.sourceID],
                let targetIndex = indexByID[edge.targetID],
                sourceIndex != targetIndex
            else {
                return nil
            }
            return ForceLink(
                sourceIndex: sourceIndex,
                targetIndex: targetIndex,
                distance: linkDistance(
                    for: edge.kind,
                    sourceSize: bodies[sourceIndex].size,
                    targetSize: bodies[targetIndex].size
                ),
                strength: linkStrength(for: edge.kind)
            )
        }

        let iterations = displayMode == .artistic
            ? min(420, max(160, bodies.count * 9))
            : min(180, max(60, bodies.count * 5))
        var alpha: CGFloat = 1
        let alphaDecay: CGFloat = 1 - pow(0.001, 1 / CGFloat(iterations))

        for _ in 0..<iterations {
            applyManyBodyForce(to: &bodies, alpha: alpha, fileContainmentPairs: fileContainmentPairs)
            applyLinkForce(links, to: &bodies, alpha: alpha)
            applyConstructGroupConstraint(to: &bodies, alpha: alpha)
            applyFileHierarchyConstraint(to: &bodies, alpha: alpha)
            applyCenterForce(to: &bodies, alpha: alpha)
            applyCollisionForce(to: &bodies, alpha: alpha, fileContainmentPairs: fileContainmentPairs)
            integrate(&bodies, alpha: alpha)
            alpha += (0 - alpha) * alphaDecay
        }

        if displayMode == .artistic {
            separateArtisticBodies(&bodies, strength: 0.72)
            normalize(&bodies)
        } else {
            arrangeDiagramFileContainers(&bodies)
            separateDiagramBodies(
                &bodies,
                strength: 0.86,
                iterations: 70,
                fileContainmentPairs: fileContainmentPairs
            )
            arrangeDiagramFileContainers(&bodies)
            normalize(&bodies)
        }
        let rowsByConstructID = constructRowsByID()
        return bodies.map {
            PositionedDeclarationNode(
                node: $0.node,
                position: CGPoint(x: $0.x, y: $0.y),
                size: $0.size,
                rows: rowsByConstructID[$0.node.id, default: []]
            )
        }
    }

    private func solveDiagramBoard() -> [PositionedDeclarationNode] {
        let rowsByConstructID = constructRowsByID()
        let visible = visibleNodes().sorted(by: nodeSort)
        let visibleIDs = Set(visible.map(\.id))
        let childrenByFileID = fileChildNodesByID(visibleIDs: visibleIDs)
        let childIDs = Set(childrenByFileID.values.flatMap { $0.map(\.id) })
        let files = visible
            .filter { $0.kind == .file }
            .sorted { $0.label < $1.label }
        let looseNodes = visible
            .filter { $0.kind != .file && !childIDs.contains($0.id) }
            .sorted(by: nodeSort)

        var sizeByID: [String: CGSize] = [:]
        for node in visible where node.kind != .file {
            sizeByID[node.id] = DeclarationNodeMetrics.size(
                for: node,
                displayMode: .diagram,
                rows: rowsByConstructID[node.id, default: []]
            )
        }
        for file in files {
            let childSizes = childrenByFileID[file.id, default: []].compactMap { sizeByID[$0.id] }
            sizeByID[file.id] = DiagramFileContainerLayout.size(for: file, childSizes: childSizes)
        }

        var positioned: [PositionedDeclarationNode] = []
        let fileColumnCount = max(1, min(files.count, files.count <= 3 ? files.count : 3))
        let fileRowCount = files.isEmpty ? 0 : Int(ceil(CGFloat(files.count) / CGFloat(fileColumnCount)))
        var columnWidths = Array(repeating: CGFloat.zero, count: max(fileColumnCount, 1))
        var rowHeights = Array(repeating: CGFloat.zero, count: max(fileRowCount, 0))

        for (index, file) in files.enumerated() {
            let size = sizeByID[file.id, default: DiagramFileContainerLayout.size(for: file, childSizes: [])]
            let column = index % fileColumnCount
            let row = index / fileColumnCount
            columnWidths[column] = max(columnWidths[column], size.width)
            rowHeights[row] = max(rowHeights[row], size.height)
        }

        let boardPadding: CGFloat = 90
        let fileGap: CGFloat = 46
        var rowTops: [CGFloat] = []
        var currentY = boardPadding
        for rowHeight in rowHeights {
            rowTops.append(currentY)
            currentY += rowHeight + fileGap
        }

        var columnLefts: [CGFloat] = []
        var currentX = boardPadding
        for columnWidth in columnWidths {
            columnLefts.append(currentX)
            currentX += columnWidth + fileGap
        }

        for (index, file) in files.enumerated() {
            let column = index % fileColumnCount
            let row = index / fileColumnCount
            let fileSize = sizeByID[file.id, default: DiagramFileContainerLayout.size(for: file, childSizes: [])]
            let fileBody = Body(
                node: file,
                size: fileSize,
                x: columnLefts[column] + fileSize.width / 2,
                y: rowTops[row] + fileSize.height / 2
            )
            let children = childrenByFileID[file.id, default: []]
            let childSizes = children.compactMap { sizeByID[$0.id] }

            positioned.append(
                PositionedDeclarationNode(
                    node: file,
                    position: CGPoint(x: fileBody.x, y: fileBody.y),
                    size: fileBody.size,
                    rows: []
                )
            )

            for (childOffset, child) in children.enumerated() {
                let childPosition = DiagramFileContainerLayout.childCenter(
                    in: fileBody,
                    offset: childOffset,
                    childSizes: childSizes
                )
                positioned.append(
                    PositionedDeclarationNode(
                        node: child,
                        position: childPosition,
                        size: sizeByID[child.id, default: DeclarationNodeMetrics.size(
                            for: child,
                            displayMode: .diagram,
                            rows: rowsByConstructID[child.id, default: []]
                        )],
                        rows: rowsByConstructID[child.id, default: []]
                    )
                )
            }
        }

        guard !looseNodes.isEmpty else {
            return positioned
        }

        let looseStartY = (rowTops.last ?? boardPadding)
            + (rowHeights.last ?? 0)
            + fileGap
        let looseColumnCount = max(1, min(3, looseNodes.count))
        var looseColumnWidths = Array(repeating: CGFloat.zero, count: looseColumnCount)
        let looseSizes = looseNodes.map {
            sizeByID[$0.id, default: DeclarationNodeMetrics.size(for: $0, displayMode: .diagram)]
        }
        for (index, size) in looseSizes.enumerated() {
            looseColumnWidths[index % looseColumnCount] = max(looseColumnWidths[index % looseColumnCount], size.width)
        }
        let looseRowHeight = (looseSizes.map(\.height).max() ?? DiagramCardMetrics.headerHeight) + 22

        for (index, node) in looseNodes.enumerated() {
            let column = index % looseColumnCount
            let row = index / looseColumnCount
            let x = boardPadding
                + looseColumnWidths.prefix(column).reduce(CGFloat.zero, +)
                + CGFloat(column) * 28
                + looseColumnWidths[column] / 2
            let y = looseStartY + CGFloat(row) * looseRowHeight + looseSizes[index].height / 2
            positioned.append(
                PositionedDeclarationNode(
                    node: node,
                    position: CGPoint(x: x, y: y),
                    size: looseSizes[index],
                    rows: rowsByConstructID[node.id, default: []]
                )
            )
        }

        return positioned
    }

    private func seededBodies() -> [Body] {
        let fieldCounts = aggregatedFieldCountsByConstructID()
        let rowsByConstructID = constructRowsByID()
        let sortedNodes = visibleNodes().sorted {
            if $0.kind.rawValue != $1.kind.rawValue {
                return $0.kind.rawValue < $1.kind.rawValue
            }
            if $0.label != $1.label {
                return $0.label < $1.label
            }
            return $0.id < $1.id
        }

        let center = CGPoint(
            x: max(viewportSize.width, 900) / 2,
            y: max(viewportSize.height, 640) / 2
        )
        let visibleIDs = Set(sortedNodes.map(\.id))
        let fileChildrenByID = fileChildNodesByID(visibleIDs: visibleIDs)
        var sizeByID: [String: CGSize] = [:]

        for node in sortedNodes where node.kind != .file {
            sizeByID[node.id] = DeclarationNodeMetrics.size(
                for: node,
                displayMode: displayMode,
                fieldCount: fieldCounts[node.id, default: 0],
                rows: rowsByConstructID[node.id, default: []]
            )
        }

        for node in sortedNodes where node.kind == .file {
            let childSizes = fileChildrenByID[node.id, default: []].compactMap { sizeByID[$0.id] }
            sizeByID[node.id] = displayMode == .diagram
                ? DiagramFileContainerLayout.size(for: node, childSizes: childSizes)
                : DeclarationNodeMetrics.size(
                    for: node,
                    displayMode: displayMode,
                    fieldCount: fieldCounts[node.id, default: 0],
                    rows: rowsByConstructID[node.id, default: []]
                )
        }

        let measuredNodes = sortedNodes.map { node in
            (
                node: node,
                size: sizeByID[node.id] ?? DeclarationNodeMetrics.size(
                    for: node,
                    displayMode: displayMode,
                    fieldCount: fieldCounts[node.id, default: 0],
                    rows: rowsByConstructID[node.id, default: []]
                )
            )
        }
        let averageRadius = measuredNodes.reduce(CGFloat.zero) { partial, measured in
            partial + hypot(measured.size.width, measured.size.height) / 2
        } / CGFloat(max(measuredNodes.count, 1))
        let radiusStep = max(52, averageRadius * 0.72)
        let goldenAngle = CGFloat.pi * (3 - sqrt(5))

        return measuredNodes.enumerated().map { index, measured in
            let radius = sqrt(CGFloat(index + 1)) * radiusStep
            let angle = CGFloat(index) * goldenAngle
            return Body(
                node: measured.node,
                size: measured.size,
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
        }
    }

    private func visibleNodes() -> [DeclarationGraphNode] {
        guard displayMode == .artistic else {
            let hiddenIDs = diagramEmbeddedMemberNodeIDs()
                .union(diagramEmbeddedMainBlockNodeIDs())
            return nodes.filter { node in
                Self.diagramStandaloneNodeKinds.contains(node.kind)
                    && !hiddenIDs.contains(node.id)
            }
        }

        let hiddenIDs = aggregatedFieldNodeIDs()
        return nodes.filter { !hiddenIDs.contains($0.id) }
    }

    private func diagramEmbeddedMainBlockNodeIDs() -> Set<String> {
        let nodesByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        var hiddenIDs = Set<String>()

        for edge in edges where edge.kind == .contains {
            guard nodesByID[edge.sourceID]?.kind == .mainBlock,
                nodesByID[edge.targetID] != nil
            else {
                continue
            }
            hiddenIDs.insert(edge.targetID)
        }
        return hiddenIDs
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

    private func fileChildNodesByID(visibleIDs: Set<String>) -> [String: [DeclarationGraphNode]] {
        guard displayMode == .diagram else {
            return [:]
        }

        let nodesByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        var childrenByFileID: [String: [DeclarationGraphNode]] = [:]

        for edge in edges where edge.kind == .contains {
            guard visibleIDs.contains(edge.sourceID),
                visibleIDs.contains(edge.targetID),
                nodesByID[edge.sourceID]?.kind == .file,
                let target = nodesByID[edge.targetID],
                Self.fileCardRowKinds.contains(target.kind)
            else {
                continue
            }
            childrenByFileID[edge.sourceID, default: []].append(target)
        }

        for key in childrenByFileID.keys {
            childrenByFileID[key]?.sort(by: nodeSort)
        }
        return childrenByFileID
    }

    private func constructRowsByID() -> [String: [DeclarationGraphNode]] {
        guard displayMode == .diagram else {
            return [:]
        }

        let nodesByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        var rows: [String: [DeclarationGraphNode]] = [:]

        for edge in edges where edge.kind == .contains {
            guard let source = nodesByID[edge.sourceID],
                let target = nodesByID[edge.targetID]
            else {
                continue
            }
            guard source.kind == .construct,
                Self.constructCardRowKinds.contains(target.kind)
            else { continue }
            rows[edge.sourceID, default: []].append(target)
        }

        for key in rows.keys {
            rows[key]?.sort {
                if $0.kind.rawValue != $1.kind.rawValue {
                    return $0.kind.rawValue < $1.kind.rawValue
                }
                return $0.label < $1.label
            }
        }
        return rows
    }

    private func diagramEmbeddedMemberNodeIDs() -> Set<String> {
        let nodesByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        var hiddenIDs = Set<String>()

        for edge in edges where edge.kind == .contains {
            guard nodesByID[edge.sourceID]?.kind == .construct,
                let target = nodesByID[edge.targetID],
                Self.constructCardRowKinds.contains(target.kind)
            else {
                continue
            }
            hiddenIDs.insert(target.id)
        }
        return hiddenIDs
    }

    private func aggregatedFieldCountsByConstructID() -> [String: Int] {
        guard displayMode == .artistic else {
            return [:]
        }

        let nodesByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        var counts: [String: Int] = [:]
        for edge in edges where edge.kind == .contains {
            guard nodesByID[edge.sourceID]?.kind == .construct,
                let target = nodesByID[edge.targetID],
                Self.aggregatedConstructMemberKinds.contains(target.kind)
            else {
                continue
            }
            counts[edge.sourceID, default: 0] += 1
        }
        return counts
    }

    private func aggregatedFieldNodeIDs() -> Set<String> {
        let nodesByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        var hiddenIDs = Set<String>()

        for edge in edges where edge.kind == .contains {
            guard nodesByID[edge.sourceID]?.kind == .construct,
                let target = nodesByID[edge.targetID],
                Self.aggregatedConstructMemberKinds.contains(target.kind)
            else {
                continue
            }
        hiddenIDs.insert(target.id)
        }
        return hiddenIDs
    }

    private func simulationEdges() -> [DeclarationGraphEdge] {
        guard displayMode == .diagram else {
            return edges
        }

        let hiddenIDs = diagramEmbeddedMemberNodeIDs()
            .union(diagramEmbeddedMainBlockNodeIDs())
        let nodesByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        let visibleEdges = edges.filter {
            !hiddenIDs.contains($0.sourceID)
                && !hiddenIDs.contains($0.targetID)
                && !isFileDeclarationContainment($0, nodesByID: nodesByID)
        }
        let constructReferenceEdges = derivedConstructReferenceEdges()
        return visibleEdges + constructReferenceEdges
    }

    private func isFileDeclarationContainment(
        _ edge: DeclarationGraphEdge,
        nodesByID: [String: DeclarationGraphNode]
    ) -> Bool {
        edge.kind == .contains
            && nodesByID[edge.sourceID]?.kind == .file
            && edge.targetID != edge.sourceID
    }

    private func derivedConstructReferenceEdges() -> [DeclarationGraphEdge] {
        let nodesByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        let constructIDs = Set(nodes.filter { $0.kind == .construct }.map(\.id))
        let ownerByMemberID = constructOwnerByMemberID()
        var derived: [DeclarationGraphEdge] = []
        var seen = Set<String>()

        for edge in edges where edge.kind == .referencesType || edge.kind == .resolvesTo {
            let sourceConstructID: String?
            if constructIDs.contains(edge.sourceID) {
                sourceConstructID = edge.sourceID
            } else {
                sourceConstructID = ownerByMemberID[edge.sourceID]
            }

            let targetConstructID: String?
            if constructIDs.contains(edge.targetID) {
                targetConstructID = edge.targetID
            } else {
                targetConstructID = ownerByMemberID[edge.targetID]
            }

            guard let sourceConstructID,
                let targetConstructID,
                sourceConstructID != targetConstructID,
                nodesByID[sourceConstructID] != nil,
                nodesByID[targetConstructID] != nil
            else {
                continue
            }

            let key = "\(sourceConstructID)->\(targetConstructID)"
            guard seen.insert(key).inserted else {
                continue
            }
            derived.append(
                DeclarationGraphEdge(
                    sourceID: sourceConstructID,
                    targetID: targetConstructID,
                    kind: .referencesType
                )
            )
        }
        return derived
    }

    private func constructOwnerByMemberID() -> [String: String] {
        let nodesByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        var ownerByMemberID: [String: String] = [:]

        for edge in edges where edge.kind == .contains {
            guard nodesByID[edge.sourceID]?.kind == .construct,
                let target = nodesByID[edge.targetID],
                Self.constructGroupedMemberKinds.contains(target.kind)
            else {
                continue
            }
            ownerByMemberID[target.id] = edge.sourceID
        }
        return ownerByMemberID
    }

    private static let aggregatedConstructMemberKinds: Set<SemanticGraphEntityKind> = [
        .state,
        .binding,
        .derived,
        .value,
        .function,
        .initializer,
    ]

    private static let constructGroupedMemberKinds: Set<SemanticGraphEntityKind> = [
        .state,
        .binding,
        .derived,
        .value,
        .function,
        .initializer,
        .member,
        .parameter,
    ]

    private static let constructCardRowKinds: Set<SemanticGraphEntityKind> = [
        .state,
        .binding,
        .derived,
        .value,
        .function,
        .initializer,
    ]

    private static let fileCardRowKinds: Set<SemanticGraphEntityKind> = [
        .construct,
        .enumeration,
        .protocolDefinition,
        .namespace,
        .macro,
        .typeExtension,
        .mainBlock,
        .function,
    ]

    private static let diagramStandaloneNodeKinds: Set<SemanticGraphEntityKind> = [
        .file,
        .packageSpace,
        .packageEntry,
        .namespace,
        .construct,
        .enumeration,
        .protocolDefinition,
        .macro,
        .typeExtension,
        .mainBlock,
        .function,
    ]

    private func applyManyBodyForce(
        to bodies: inout [Body],
        alpha: CGFloat,
        fileContainmentPairs: Set<String>
    ) {
        guard bodies.count > 1 else {
            return
        }

        let minimumDistance: CGFloat = 28
        let maximumDistance: CGFloat = 520

        for leftIndex in 0..<(bodies.count - 1) {
            for rightIndex in (leftIndex + 1)..<bodies.count {
                if isDiagramFileContainerPair(
                    bodies[leftIndex],
                    bodies[rightIndex],
                    fileContainmentPairs: fileContainmentPairs
                ) {
                    continue
                }

                var dx = bodies[rightIndex].x - bodies[leftIndex].x
                var dy = bodies[rightIndex].y - bodies[leftIndex].y
                var distanceSquared = dx * dx + dy * dy

                if distanceSquared < 0.01 {
                    let jitter = deterministicJitter(left: bodies[leftIndex].node.id, right: bodies[rightIndex].node.id)
                    dx = jitter.x
                    dy = jitter.y
                    distanceSquared = dx * dx + dy * dy
                }

                let distance = max(minimumDistance, min(maximumDistance, sqrt(distanceSquared)))
                let averageRadius = (bodies[leftIndex].radius + bodies[rightIndex].radius) / 2
                let charge = averageRadius * averageRadius * 1.9
                let force = charge / (distance * distance) * alpha
                let nx = dx / distance
                let ny = dy / distance

                bodies[leftIndex].vx -= nx * force
                bodies[leftIndex].vy -= ny * force
                bodies[rightIndex].vx += nx * force
                bodies[rightIndex].vy += ny * force
            }
        }
    }

    private func applyLinkForce(_ links: [ForceLink], to bodies: inout [Body], alpha: CGFloat) {
        for link in links {
            let source = bodies[link.sourceIndex]
            let target = bodies[link.targetIndex]
            var dx = target.x - source.x
            var dy = target.y - source.y
            var distance = sqrt(dx * dx + dy * dy)

            if distance < 0.01 {
                let jitter = deterministicJitter(left: source.node.id, right: target.node.id)
                dx = jitter.x
                dy = jitter.y
                distance = sqrt(dx * dx + dy * dy)
            }

            let displacement = (distance - link.distance) / distance * link.strength * alpha
            let fx = dx * displacement
            let fy = dy * displacement

            bodies[link.sourceIndex].vx += fx * 0.5
            bodies[link.sourceIndex].vy += fy * 0.5
            bodies[link.targetIndex].vx -= fx * 0.5
            bodies[link.targetIndex].vy -= fy * 0.5
        }
    }

    private func applyCenterForce(to bodies: inout [Body], alpha: CGFloat) {
        let center = CGPoint(
            x: max(viewportSize.width, 900) / 2,
            y: max(viewportSize.height, 640) / 2
        )
        let strength: CGFloat = displayMode == .artistic ? 0.020 : 0.035

        for index in bodies.indices {
            bodies[index].vx += (center.x - bodies[index].x) * strength * alpha
            bodies[index].vy += (center.y - bodies[index].y) * strength * alpha
        }
    }

    private func applyCollisionForce(
        to bodies: inout [Body],
        alpha: CGFloat,
        fileContainmentPairs: Set<String>
    ) {
        guard bodies.count > 1 else {
            return
        }

        let strength: CGFloat = (displayMode == .artistic ? 0.70 : 0.96) * alpha

        for leftIndex in 0..<(bodies.count - 1) {
            for rightIndex in (leftIndex + 1)..<bodies.count {
                let dx = bodies[rightIndex].x - bodies[leftIndex].x
                let dy = bodies[rightIndex].y - bodies[leftIndex].y
                if displayMode == .artistic {
                    var distance = hypot(dx, dy)
                    var nx = dx
                    var ny = dy
                    if distance < 0.01 {
                        let jitter = deterministicJitter(
                            left: bodies[leftIndex].node.id,
                            right: bodies[rightIndex].node.id
                        )
                        nx = jitter.x
                        ny = jitter.y
                        distance = hypot(nx, ny)
                    }

                    let minimumDistance = bodies[leftIndex].radius + bodies[rightIndex].radius + 10
                    let overlap = minimumDistance - distance
                    guard overlap > 0 else {
                        continue
                    }

                    nx /= distance
                    ny /= distance
                    let push = overlap * 0.5 * strength
                    bodies[leftIndex].vx -= nx * push
                    bodies[leftIndex].vy -= ny * push
                    bodies[rightIndex].vx += nx * push
                    bodies[rightIndex].vy += ny * push
                    continue
                }

                if isDiagramFileContainerPair(
                    bodies[leftIndex],
                    bodies[rightIndex],
                    fileContainmentPairs: fileContainmentPairs
                ) {
                    continue
                }

                let minimumX = (bodies[leftIndex].size.width + bodies[rightIndex].size.width) / 2 + 42
                let minimumY = (bodies[leftIndex].size.height + bodies[rightIndex].size.height) / 2 + 34
                let overlapX = minimumX - abs(dx)
                let overlapY = minimumY - abs(dy)

                guard overlapX > 0, overlapY > 0 else {
                    continue
                }

                if overlapX < overlapY {
                    let direction: CGFloat = dx >= 0 ? 1 : -1
                    let push = overlapX * 0.5 * strength
                    bodies[leftIndex].vx -= direction * push
                    bodies[rightIndex].vx += direction * push
                } else {
                    let direction: CGFloat = dy >= 0 ? 1 : -1
                    let push = overlapY * 0.5 * strength
                    bodies[leftIndex].vy -= direction * push
                    bodies[rightIndex].vy += direction * push
                }
            }
        }
    }

    private func separateDiagramBodies(
        _ bodies: inout [Body],
        strength: CGFloat,
        iterations: Int,
        fileContainmentPairs: Set<String>
    ) {
        guard bodies.count > 1 else {
            return
        }

        for _ in 0..<iterations {
            var moved = false
            for leftIndex in 0..<(bodies.count - 1) {
                for rightIndex in (leftIndex + 1)..<bodies.count {
                    var dx = bodies[rightIndex].x - bodies[leftIndex].x
                    var dy = bodies[rightIndex].y - bodies[leftIndex].y
                    if abs(dx) < 0.01, abs(dy) < 0.01 {
                        let jitter = deterministicJitter(
                            left: bodies[leftIndex].node.id,
                            right: bodies[rightIndex].node.id
                        )
                        dx = jitter.x
                        dy = jitter.y
                    }

                    if isDiagramFileContainerPair(
                        bodies[leftIndex],
                        bodies[rightIndex],
                        fileContainmentPairs: fileContainmentPairs
                    ) {
                        continue
                    }

                    let minimumX = (bodies[leftIndex].size.width + bodies[rightIndex].size.width) / 2 + 46
                    let minimumY = (bodies[leftIndex].size.height + bodies[rightIndex].size.height) / 2 + 38
                    let overlapX = minimumX - abs(dx)
                    let overlapY = minimumY - abs(dy)

                    guard overlapX > 0, overlapY > 0 else {
                        continue
                    }

                    moved = true
                    if overlapX < overlapY {
                        let direction: CGFloat = dx >= 0 ? 1 : -1
                        let push = overlapX * 0.5 * strength
                        bodies[leftIndex].x -= direction * push
                        bodies[rightIndex].x += direction * push
                    } else {
                        let direction: CGFloat = dy >= 0 ? 1 : -1
                        let push = overlapY * 0.5 * strength
                        bodies[leftIndex].y -= direction * push
                        bodies[rightIndex].y += direction * push
                    }
                }
            }

            if !moved {
                return
            }
        }
    }

    private func fileContainmentPairKeys(in bodies: [Body]) -> Set<String> {
        guard displayMode == .diagram else {
            return []
        }

        let nodeKindsByID = Dictionary(uniqueKeysWithValues: bodies.map { ($0.node.id, $0.node.kind) })
        var pairs = Set<String>()
        for edge in edges where edge.kind == .contains {
            guard nodeKindsByID[edge.sourceID] == .file,
                nodeKindsByID[edge.targetID] != nil
            else {
                continue
            }
            pairs.insert(pairKey(edge.sourceID, edge.targetID))
        }
        return pairs
    }

    private func isDiagramFileContainerPair(
        _ left: Body,
        _ right: Body,
        fileContainmentPairs: Set<String>
    ) -> Bool {
        guard displayMode == .diagram else {
            return false
        }

        return fileContainmentPairs.contains(pairKey(left.node.id, right.node.id))
    }

    private func pairKey(_ leftID: String, _ rightID: String) -> String {
        leftID < rightID ? "\(leftID)|\(rightID)" : "\(rightID)|\(leftID)"
    }

    private func applyTailConstraint(to bodies: inout [Body], alpha: CGFloat) {
        let tailPairs = constructTailPairs(in: bodies)
        guard !tailPairs.isEmpty else {
            return
        }

        let strength: CGFloat = 0.34 * alpha
        for pair in tailPairs {
            let construct = bodies[pair.constructIndex]
            let child = bodies[pair.childIndex]
            let desiredPosition = tailPosition(
                construct: construct,
                child: child,
                offset: pair.offset
            )

            bodies[pair.childIndex].vx += (desiredPosition.x - child.x) * strength
            bodies[pair.childIndex].vy += (desiredPosition.y - child.y) * strength
            bodies[pair.constructIndex].vx -= (desiredPosition.x - child.x) * strength * 0.05
            bodies[pair.constructIndex].vy -= (desiredPosition.y - child.y) * strength * 0.05
        }
    }

    private func integrate(_ bodies: inout [Body], alpha: CGFloat) {
        let damping: CGFloat = 0.78
        let maxVelocity: CGFloat = 24 + alpha * 24

        for index in bodies.indices {
            bodies[index].vx *= damping
            bodies[index].vy *= damping
            bodies[index].vx = min(maxVelocity, max(-maxVelocity, bodies[index].vx))
            bodies[index].vy = min(maxVelocity, max(-maxVelocity, bodies[index].vy))
            bodies[index].x += bodies[index].vx
            bodies[index].y += bodies[index].vy
        }
    }

    private func applyConstructGroupConstraint(to bodies: inout [Body], alpha: CGFloat) {
        let pairs = constructMemberPairs(in: bodies)
        guard !pairs.isEmpty else {
            return
        }

        let strength: CGFloat = displayMode == .artistic ? 0.34 * alpha : 0.24 * alpha
        for pair in pairs {
            let construct = bodies[pair.constructIndex]
            let child = bodies[pair.childIndex]
            let desiredPosition = groupPosition(
                construct: construct,
                child: child,
                offset: pair.offset
            )
            let dx = desiredPosition.x - child.x
            let dy = desiredPosition.y - child.y

            bodies[pair.childIndex].vx += dx * strength
            bodies[pair.childIndex].vy += dy * strength
            bodies[pair.constructIndex].vx -= dx * strength * 0.04
            bodies[pair.constructIndex].vy -= dy * strength * 0.04
        }
    }

    private func applyFileHierarchyConstraint(to bodies: inout [Body], alpha: CGFloat) {
        guard displayMode == .diagram else {
            return
        }

        let pairs = fileDeclarationPairs(in: bodies)
        guard !pairs.isEmpty else {
            return
        }

        let strength: CGFloat = 0.42 * alpha
        let pairsByFileIndex = Dictionary(grouping: pairs, by: \.fileIndex)
        for (fileIndex, filePairs) in pairsByFileIndex {
            let sortedPairs = filePairs.sorted { $0.offset < $1.offset }
            let childSizes = sortedPairs.map { bodies[$0.declarationIndex].size }
            bodies[fileIndex].size = DiagramFileContainerLayout.size(
                for: bodies[fileIndex].node,
                childSizes: childSizes
            )

            for (offset, pair) in sortedPairs.enumerated() {
                let declaration = bodies[pair.declarationIndex]
                let target = DiagramFileContainerLayout.childCenter(
                    in: bodies[fileIndex],
                    offset: offset,
                    childSizes: childSizes
                )
                let dx = target.x - declaration.x
                let dy = target.y - declaration.y

                bodies[pair.declarationIndex].vx += dx * strength
                bodies[pair.declarationIndex].vy += dy * strength
            }
        }
    }

    private func arrangeDiagramFileContainers(_ bodies: inout [Body]) {
        guard displayMode == .diagram else {
            return
        }

        let pairs = fileDeclarationPairs(in: bodies)
        guard !pairs.isEmpty else {
            return
        }

        let pairsByFileIndex = Dictionary(grouping: pairs, by: \.fileIndex)
        for (fileIndex, filePairs) in pairsByFileIndex {
            let sortedPairs = filePairs.sorted { $0.offset < $1.offset }
            let childSizes = sortedPairs.map { bodies[$0.declarationIndex].size }
            bodies[fileIndex].size = DiagramFileContainerLayout.size(
                for: bodies[fileIndex].node,
                childSizes: childSizes
            )

            for (offset, pair) in sortedPairs.enumerated() {
                let target = DiagramFileContainerLayout.childCenter(
                    in: bodies[fileIndex],
                    offset: offset,
                    childSizes: childSizes
                )
                bodies[pair.declarationIndex].x = target.x
                bodies[pair.declarationIndex].y = target.y
                bodies[pair.declarationIndex].vx = 0
                bodies[pair.declarationIndex].vy = 0
            }
        }
    }

    private func constructTailPairs(in bodies: [Body]) -> [TailPair] {
        constructMemberPairs(in: bodies)
    }

    private func fileDeclarationPairs(in bodies: [Body]) -> [FileDeclarationPair] {
        let indexByID = Dictionary(uniqueKeysWithValues: bodies.enumerated().map { ($0.element.node.id, $0.offset) })
        let declarationKinds = Self.fileCardRowKinds
        let fileEdges = edges.filter { edge in
            guard edge.kind == .contains,
                let sourceIndex = indexByID[edge.sourceID],
                let targetIndex = indexByID[edge.targetID]
            else {
                return false
            }
            return bodies[sourceIndex].node.kind == .file
                && declarationKinds.contains(bodies[targetIndex].node.kind)
        }
        let childrenByFileIndex = Dictionary(grouping: fileEdges) { edge in
            indexByID[edge.sourceID] ?? 0
        }

        var pairs: [FileDeclarationPair] = []
        for (fileIndex, childEdges) in childrenByFileIndex {
            let sortedChildren = childEdges.compactMap { indexByID[$0.targetID] }.sorted {
                bodies[$0].node.label < bodies[$1].node.label
            }
            for (offset, childIndex) in sortedChildren.enumerated() {
                pairs.append(FileDeclarationPair(fileIndex: fileIndex, declarationIndex: childIndex, offset: offset))
            }
        }
        return pairs
    }

    private func constructMemberPairs(in bodies: [Body]) -> [TailPair] {
        let indexByID = Dictionary(uniqueKeysWithValues: bodies.enumerated().map { ($0.element.node.id, $0.offset) })

        let tailEdges = edges.filter { edge in
            guard edge.kind == .contains,
                let sourceIndex = indexByID[edge.sourceID],
                let targetIndex = indexByID[edge.targetID]
            else {
                return false
            }
            return bodies[sourceIndex].node.kind == .construct
                && Self.constructGroupedMemberKinds.contains(bodies[targetIndex].node.kind)
        }
        let childrenByConstructIndex = Dictionary(grouping: tailEdges) { edge in
            indexByID[edge.sourceID] ?? 0
        }

        var pairs: [TailPair] = []
        for (constructIndex, childEdges) in childrenByConstructIndex {
            let sortedChildren = childEdges.compactMap { indexByID[$0.targetID] }.sorted {
                bodies[$0].node.label < bodies[$1].node.label
            }
            for (childOffset, childIndex) in sortedChildren.enumerated() {
                pairs.append(
                    TailPair(
                        constructIndex: constructIndex,
                        childIndex: childIndex,
                        offset: childOffset
                    )
                )
            }
        }
        return pairs
    }

    private func relaxArtisticBodies(_ bodies: inout [Body]) {
        let tailPairs = constructTailPairs(in: bodies)
        for _ in 0..<48 {
            for pair in tailPairs {
                let construct = bodies[pair.constructIndex]
                let child = bodies[pair.childIndex]
                let target = tailPosition(construct: construct, child: child, offset: pair.offset)
                bodies[pair.childIndex].x += (target.x - child.x) * 0.42
                bodies[pair.childIndex].y += (target.y - child.y) * 0.42
            }
            separateArtisticBodies(&bodies, strength: 0.72)
        }
    }

    private func separateArtisticBodies(_ bodies: inout [Body], strength: CGFloat) {
        guard bodies.count > 1 else {
            return
        }

        for leftIndex in 0..<(bodies.count - 1) {
            for rightIndex in (leftIndex + 1)..<bodies.count {
                var dx = bodies[rightIndex].x - bodies[leftIndex].x
                var dy = bodies[rightIndex].y - bodies[leftIndex].y
                var distance = hypot(dx, dy)
                if distance < 0.01 {
                    let jitter = deterministicJitter(
                        left: bodies[leftIndex].node.id,
                        right: bodies[rightIndex].node.id
                    )
                    dx = jitter.x
                    dy = jitter.y
                    distance = hypot(dx, dy)
                }

                let minimumDistance = bodies[leftIndex].radius + bodies[rightIndex].radius + 10
                let overlap = minimumDistance - distance
                guard overlap > 0 else {
                    continue
                }

                let nx = dx / distance
                let ny = dy / distance
                let push = overlap * 0.5 * strength
                bodies[leftIndex].x -= nx * push
                bodies[leftIndex].y -= ny * push
                bodies[rightIndex].x += nx * push
                bodies[rightIndex].y += ny * push
            }
        }
    }

    private func tailPosition(construct: Body, child: Body, offset: Int) -> CGPoint {
        groupPosition(construct: construct, child: child, offset: offset)
    }

    private func groupPosition(construct: Body, child: Body, offset: Int) -> CGPoint {
        if displayMode == .diagram {
            let lane = CGFloat(offset % 4)
            let row = CGFloat(offset / 4)
            let x = construct.x + construct.size.width / 2 + child.size.width / 2 + 64 + row * 26
            let y = construct.y + (lane - 1.5) * (child.size.height + 22)
            return CGPoint(x: x, y: y)
        }

        let side: CGFloat = offset.isMultiple(of: 2) ? 1 : -1
        let segment = CGFloat(offset / 2 + 1)
        let baseAngle = atan2(construct.y - viewportSize.height / 2, construct.x - viewportSize.width / 2)
        let angle = baseAngle + side * (0.52 + segment * 0.24)
        let tailDistance = construct.radius + child.radius + 14 + segment * 16

        return CGPoint(
            x: construct.x + cos(angle) * tailDistance,
            y: construct.y + sin(angle) * tailDistance
        )
    }

    private func fileChildPosition(file: Body, child: Body, offset: Int) -> CGPoint {
        let column = CGFloat(offset % 3) - 1
        let row = CGFloat(offset / 3)
        let horizontalSpacing = max(file.size.width, child.size.width) * 0.62
        let verticalSpacing = child.size.height + 94

        return CGPoint(
            x: file.x + column * horizontalSpacing,
            y: file.y + file.size.height / 2 + child.size.height / 2 + verticalSpacing + row * verticalSpacing
        )
    }

    private func normalize(_ bodies: inout [Body]) {
        guard let first = bodies.first else {
            return
        }

        var minX = first.x - first.size.width / 2
        var maxX = first.x + first.size.width / 2
        var minY = first.y - first.size.height / 2
        var maxY = first.y + first.size.height / 2

        for body in bodies {
            minX = min(minX, body.x - body.size.width / 2)
            maxX = max(maxX, body.x + body.size.width / 2)
            minY = min(minY, body.y - body.size.height / 2)
            maxY = max(maxY, body.y + body.size.height / 2)
        }

        let padding: CGFloat = 100
        let currentCenter = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        let targetCenter = CGPoint(
            x: max(viewportSize.width, maxX - minX + padding * 2) / 2,
            y: max(viewportSize.height, maxY - minY + padding * 2) / 2
        )
        let dx = targetCenter.x - currentCenter.x
        let dy = targetCenter.y - currentCenter.y

        for index in bodies.indices {
            bodies[index].x += dx
            bodies[index].y += dy
        }
    }

    private func linkDistance(
        for kind: SemanticGraphRelationKind,
        sourceSize: CGSize,
        targetSize: CGSize
    ) -> CGFloat {
        let sizeAllowance = (hypot(sourceSize.width, sourceSize.height) + hypot(targetSize.width, targetSize.height)) / 4
        if displayMode == .artistic {
            switch kind {
            case .contains:
                return sizeAllowance + 30
            case .conformsTo, .extends:
                return sizeAllowance + 92
            case .referencesType, .referencesIdentity, .resolvesTo:
                return sizeAllowance + 122
            case .appliesMacro, .targetsMacro:
                return sizeAllowance + 74
            case .dependsOn, .mutates, .aliases, .calls:
                return sizeAllowance + 82
            }
        }

        switch kind {
        case .contains:
            return sizeAllowance + 52
        case .conformsTo, .extends:
            return sizeAllowance + 104
        case .referencesType, .referencesIdentity, .resolvesTo:
            return sizeAllowance + 84
        case .appliesMacro, .targetsMacro:
            return sizeAllowance + 72
        case .dependsOn, .mutates, .aliases, .calls:
            return sizeAllowance + 66
        }
    }

    private func linkStrength(for kind: SemanticGraphRelationKind) -> CGFloat {
        if displayMode == .artistic {
            switch kind {
            case .contains:
                return 0.55
            case .conformsTo, .extends:
                return 0.16
            case .referencesType, .referencesIdentity, .resolvesTo:
                return 0.04
            case .appliesMacro, .targetsMacro:
                return 0.10
            case .dependsOn, .mutates, .aliases, .calls:
                return 0.08
            }
        }

        switch kind {
        case .contains:
            return 0.42
        case .conformsTo, .extends:
            return 0.22
        case .referencesType, .referencesIdentity, .resolvesTo:
            return 0.16
        case .appliesMacro, .targetsMacro:
            return 0.25
        case .dependsOn, .mutates, .aliases, .calls:
            return 0.20
        }
    }

    private func deterministicJitter(left: String, right: String) -> CGPoint {
        let hash = stableHash(left + right)
        let angle = CGFloat(hash % 6283) / 1000
        return CGPoint(x: cos(angle) * 0.5, y: sin(angle) * 0.5)
    }

    private func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }
}

private struct ForceLink {
    let sourceIndex: Int
    let targetIndex: Int
    let distance: CGFloat
    let strength: CGFloat
}

private struct TailPair {
    let constructIndex: Int
    let childIndex: Int
    let offset: Int
}

private struct FileDeclarationPair {
    let fileIndex: Int
    let declarationIndex: Int
    let offset: Int
}
