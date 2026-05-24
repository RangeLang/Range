import AppKit
import MetalKit
import simd

final class MetalSunGraphView: MTKView, MTKViewDelegate {
    var graph = DeclarationGraphSnapshot(nodes: [], edges: []) {
        didSet {
            cachedLayout = nil
            rebuildSources()
        }
    }
    var selectedNodeID: String? {
        didSet {
            rebuildSources()
        }
    }
    var onSelectNode: ((String?) -> Void)?

    private struct SunSource {
        var position: SIMD2<Float>
        var radius: Float
        var z: Float
        var moment: SIMD2<Float>
        var polarity: Float
        var perspective: Float
    }

    private struct Uniforms {
        var viewportSize: SIMD2<Float>
        var time: Float
        var sourceCount: UInt32
        var selectedIndex: Int32
        var padding: Float = 0
    }

    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?
    private var sourceBuffer: MTLBuffer?
    private var sources: [SunSource] = []
    private var sourceIDs: [String] = []
    private var startTime = CFAbsoluteTimeGetCurrent()
    private var cachedLayout: [PositionedDeclarationNode]?
    private var cachedLayoutSize: CGSize?

    override init(frame frameRect: CGRect, device: MTLDevice?) {
        let metalDevice = device ?? MTLCreateSystemDefaultDevice()
        super.init(frame: frameRect, device: metalDevice)
        commonInit()
    }

    convenience init() {
        self.init(frame: .zero, device: MTLCreateSystemDefaultDevice())
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        if device == nil {
            device = MTLCreateSystemDefaultDevice()
        }
        commonInit()
    }

    private func commonInit() {
        guard let device else {
            return
        }

        framebufferOnly = true
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        preferredFramesPerSecond = 30
        enableSetNeedsDisplay = false
        isPaused = false
        delegate = self
        commandQueue = device.makeCommandQueue()
        buildPipeline(device: device)
    }

    override func layout() {
        super.layout()
        drawableSize = CGSize(
            width: max(1, bounds.width * windowBackingScale),
            height: max(1, bounds.height * windowBackingScale)
        )
        rebuildSources()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let hit = hitSource(at: point) {
            selectedNodeID = hit
            onSelectNode?(hit)
        } else {
            selectedNodeID = nil
            onSelectNode?(nil)
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        cachedLayout = nil
        cachedLayoutSize = nil
        rebuildSources()
    }

    func draw(in view: MTKView) {
        guard let device,
            let drawable = currentDrawable,
            let descriptor = currentRenderPassDescriptor,
            let pipelineState,
            let commandQueue,
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else {
            return
        }

        if sources.isEmpty {
            rebuildSources()
        }

        let sourceBuffer = currentSourceBuffer(device: device)
        var uniforms = Uniforms(
            viewportSize: SIMD2<Float>(Float(max(1, bounds.width)), Float(max(1, bounds.height))),
            time: Float(CFAbsoluteTimeGetCurrent() - startTime),
            sourceCount: UInt32(min(sources.count, 64)),
            selectedIndex: Int32(sourceIDs.firstIndex(of: selectedNodeID ?? "") ?? -1)
        )

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        if let sourceBuffer {
            encoder.setFragmentBuffer(sourceBuffer, offset: 0, index: 1)
        }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private var windowBackingScale: CGFloat {
        window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    private func buildPipeline(device: MTLDevice) {
        do {
            let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
            guard let vertexFunction = library.makeFunction(name: "sunVertex"),
                let fragmentFunction = library.makeFunction(name: "sunFragment")
            else {
                return
            }

            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFunction
            descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
            pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            Swift.print("Metal shader build failed: \(error)")
        }
    }

    private func rebuildSources() {
        let layout = positionedNodes()
        let center = graphCenter(for: layout)
        var nextSources: [SunSource] = []
        var nextIDs: [String] = []

        for positioned in layout.prefix(64) {
            let radius = min(positioned.size.width, positioned.size.height) / 2
            let depthSeed = CGFloat(stableVisualHash(positioned.id + "|z") % 10_000) / 10_000
            let z = (depthSeed - 0.5) * 560
            let perspective = 860 / (860 + z)
            let radialX = positioned.position.x - center.x
            let radialY = positioned.position.y - center.y
            let projected = CGPoint(
                x: center.x + radialX * perspective,
                y: center.y + radialY * perspective
            )
            let spin = CGFloat(stableVisualHash(positioned.id + "|spin") % 6283) / 1000
            let mx = cos(spin) * 0.48 + radialX * 0.004
            let my = sin(spin) * 0.48 + radialY * 0.004
            let momentLength = max(1, hypot(mx, my))
            let polarity: CGFloat = stableVisualHash(positioned.id).isMultiple(of: 2) ? 1 : -1

            nextSources.append(
                SunSource(
                    position: SIMD2<Float>(Float(projected.x), Float(projected.y)),
                    radius: Float(radius * perspective),
                    z: Float(z),
                    moment: SIMD2<Float>(Float(mx / momentLength), Float(my / momentLength)),
                    polarity: Float(polarity),
                    perspective: Float(perspective)
                )
            )
            nextIDs.append(positioned.id)
        }

        sources = nextSources
        sourceIDs = nextIDs
        sourceBuffer = nil
    }

    private func currentSourceBuffer(device: MTLDevice) -> MTLBuffer? {
        guard !sources.isEmpty else {
            return nil
        }

        let length = MemoryLayout<SunSource>.stride * sources.count
        if let sourceBuffer, sourceBuffer.length >= length {
            let pointer = sourceBuffer.contents().bindMemory(to: SunSource.self, capacity: sources.count)
            pointer.update(from: sources, count: sources.count)
            return sourceBuffer
        }

        sourceBuffer = device.makeBuffer(bytes: sources, length: length, options: [.storageModeShared])
        return sourceBuffer
    }

    private func positionedNodes() -> [PositionedDeclarationNode] {
        let size = bounds.size
        if let cachedLayout, cachedLayoutSize == size {
            return cachedLayout
        }

        let layout = ForceDirectedDeclarationLayout(
            nodes: graph.nodes,
            edges: graph.edges,
            displayMode: .artistic,
            viewportSize: size
        )
        .solve()

        cachedLayout = layout
        cachedLayoutSize = size
        return layout
    }

    private func graphCenter(for layout: [PositionedDeclarationNode]) -> CGPoint {
        guard !layout.isEmpty else {
            return CGPoint(x: bounds.midX, y: bounds.midY)
        }

        let total = layout.reduce(CGPoint.zero) { partial, positioned in
            CGPoint(x: partial.x + positioned.position.x, y: partial.y + positioned.position.y)
        }
        return CGPoint(x: total.x / CGFloat(layout.count), y: total.y / CGFloat(layout.count))
    }

    private func hitSource(at point: CGPoint) -> String? {
        for (index, source) in sources.enumerated().reversed() {
            let dx = CGFloat(source.position.x) - point.x
            let dy = CGFloat(source.position.y) - point.y
            if hypot(dx, dy) <= CGFloat(source.radius) {
                return sourceIDs[index]
            }
        }
        return nil
    }

    private func stableVisualHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float2 viewportSize;
        float time;
        uint sourceCount;
        int selectedIndex;
        float padding;
    };

    struct SunSource {
        float2 position;
        float radius;
        float z;
        float2 moment;
        float polarity;
        float perspective;
    };

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex VertexOut sunVertex(uint vertexID [[vertex_id]], constant Uniforms& uniforms [[buffer(0)]]) {
        float2 positions[3] = {
            float2(-1.0, -1.0),
            float2( 3.0, -1.0),
            float2(-1.0,  3.0)
        };
        VertexOut out;
        out.position = float4(positions[vertexID], 0.0, 1.0);
        out.uv = (positions[vertexID] + 1.0) * 0.5;
        return out;
    }

    float hash21(float2 p) {
        p = fract(p * float2(123.34, 456.21));
        p += dot(p, p + 45.32);
        return fract(p.x * p.y);
    }

    float2 dipoleField(float2 p, SunSource source) {
        float2 r = p - source.position;
        float minDistance = max(6.0, source.radius * 0.32);
        float d2 = max(dot(r, r), minDistance * minDistance);
        float d = sqrt(d2);
        float2 rh = r / d;
        float dotMR = dot(source.moment, rh);
        float depthGain = clamp(source.perspective, 0.46, 1.45);
        float falloff = source.radius * depthGain / d2;
        float2 dipole = (2.0 * dotMR * rh - source.moment) * source.polarity;
        return dipole * falloff;
    }

    float circularRidge(float value, float sharpness) {
        float phase = abs(fract(value) - 0.5) * 2.0;
        return pow(1.0 - phase, sharpness);
    }

    float pairFlux(float2 p, SunSource a, SunSource b, float time) {
        float2 ab = b.position - a.position;
        float d = max(1.0, length(ab));
        float2 axis = ab / d;
        float2 normal = float2(-axis.y, axis.x);
        float t = clamp(dot(p - a.position, axis) / d, 0.0, 1.0);
        float offset = dot(p - (a.position + axis * d * t), normal);

        float2 field = dipoleField(p, a) + dipoleField(p, b);
        float fieldLength = max(0.0001, length(field));
        float2 fieldDirection = field / fieldLength;
        float tangentAlignment = pow(abs(dot(fieldDirection, axis)), 0.65);
        float bendAlignment = 0.45 + 0.55 * pow(abs(dot(fieldDirection, normal)), 0.7);

        float envelopeWidth = max(18.0, min(d * 0.28, a.radius + b.radius + 46.0));
        float envelope = exp(-(offset * offset) / (envelopeWidth * envelopeWidth));
        float endFade = smoothstep(0.0, 0.10, t) * smoothstep(1.0, 0.90, t);
        float strandFrequency = 0.075 + 26.0 / max(d, 80.0);
        float phase = offset * strandFrequency + t * 2.2 + sin(t * 6.283 + time * 0.11) * 0.18;
        float strands = circularRidge(phase, 18.0);
        float glow = circularRidge(phase, 4.2) * 0.34;

        return (strands + glow) * envelope * endFade * (0.36 + tangentAlignment * bendAlignment * 1.2);
    }

    fragment float4 sunFragment(VertexOut in [[stage_in]],
                                constant Uniforms& uniforms [[buffer(0)]],
                                constant SunSource* sources [[buffer(1)]]) {
        float2 p = float2(in.uv.x * uniforms.viewportSize.x, (1.0 - in.uv.y) * uniforms.viewportSize.y);
        uint count = min(uniforms.sourceCount, 64u);
        float energy = 0.0;
        float core = 0.0;

        for (uint i = 0; i < count; i++) {
            SunSource source = sources[i];
            float d = distance(p, source.position);
            float disk = smoothstep(source.radius + 1.2, source.radius - 1.2, d);
            core = max(core, disk);

            float corona = exp(-(d * d) / max(1.0, source.radius * source.radius * 0.55)) * 0.22;
            energy += corona * source.perspective;
        }

        for (uint i = 0; i < count; i++) {
            for (uint j = i + 1; j < count; j++) {
                energy += pairFlux(p, sources[i], sources[j], uniforms.time) * 0.20;
            }
        }

        float selectedRing = 0.0;
        if (uniforms.selectedIndex >= 0 && uint(uniforms.selectedIndex) < count) {
            SunSource selected = sources[uint(uniforms.selectedIndex)];
            float d = distance(p, selected.position);
            selectedRing = exp(-pow((d - selected.radius * 1.18) / 3.0, 2.0)) * 0.72;
        }

        float e = clamp(energy, 0.0, 2.8);
        float3 cyan = float3(0.04, 0.78, 1.0);
        float3 whiteHot = float3(0.78, 0.98, 1.0);
        float3 color = mix(cyan, whiteHot, smoothstep(0.18, 1.25, e));
        color *= 1.0 - exp(-e * 1.65);
        color += whiteHot * selectedRing;
        color = mix(color, float3(0.0), core);
        return float4(color, 1.0);
    }
    """
}
