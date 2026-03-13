#if os(WASI)
@_expose(wasm, "neatHandleEvent")
@_cdecl("neatHandleEvent")
public func neatHandleEvent(_ id: Int32, _ kind: Int32) -> Int32 {
    _ = kind
    let handled = WasmEventRegistry.shared.handle(id: id)
    return handled ? 1 : -1
}

private struct NoopInstructionSink: WasmInstructionSink {
    func emit(_ instruction: WasmInstruction) {}
}

@_expose(wasm, "neatWasmInit")
@_cdecl("neatWasmInit")
public func neatWasmInit() {
    // Initialization logic will be driven by the Renderer
    // The user app's @main will call Renderer.shared.mount(...)
}

public nonisolated(unsafe) var neatWasmRouteIndex: Int32 = 0

@_expose(wasm, "neatWasmSetRouteIndex")
@_cdecl("neatWasmSetRouteIndex")
public func neatWasmSetRouteIndex(_ index: Int32) {
    neatWasmRouteIndex = index
}

// MARK: - Binary Protocol
// Opcodes must match JS runtime
private enum Opcode: UInt8 {
    case createText = 0
    case createElement = 1
    case appendChild = 2
    case removeChild = 3
    case replaceChild = 4
    case setAttribute = 5
    case removeAttribute = 6
    case setStyle = 7
    case removeStyle = 8
    case setText = 9
    case addEventListener = 10
    case removeEventListener = 11
}

private let updateCapacity = 1024 * 1024 // 1MB buffer
private nonisolated(unsafe) var updatePtr: UnsafeMutablePointer<UInt8> = .allocate(capacity: updateCapacity)
private nonisolated(unsafe) var updateLen: Int32 = 0

public func emitInstruction(_ instruction: WasmInstruction) {
    switch instruction {
    case .createText(let id, let text):
        write(op: .createText, id: id, payload: text)
    case .createElement(let id, let tag):
        write(op: .createElement, id: id, payload: tag)
    case .appendChild(let parentId, let childId):
        write(op: .appendChild, id: parentId, intParam: childId)
    case .removeChild(let parentId, let childId):
        write(op: .removeChild, id: parentId, intParam: childId)
    case .replaceChild(let parentId, let newId, let oldId):
        write(op: .replaceChild, id: parentId, intParam: newId, intParam2: oldId)
    case .setAttribute(let id, let key, let value):
        write(op: .setAttribute, id: id, payload: key + "=" + value)
    case .removeAttribute(let id, let key):
        write(op: .removeAttribute, id: id, payload: key)
    case .setStyle(let id, let key, let value):
        write(op: .setStyle, id: id, payload: key + "=" + value)
    case .removeStyle(let id, let key):
        write(op: .removeStyle, id: id, payload: key)
    case .setText(let id, let text):
        write(op: .setText, id: id, payload: text)
    case .addEventListener(let id, let event):
        write(op: .addEventListener, id: id, payload: event)
    case .removeEventListener(let id, let event):
        write(op: .removeEventListener, id: id, payload: event)
    }
}

private func write(op: Opcode, id: Int32, intParam: Int32 = 0, intParam2: Int32 = 0, payload: String? = nil) {
    let bytes = payload?.utf8.map { $0 } ?? []
    let payloadLen = bytes.count
    // Header: Op(1) + ID(4) + Int1(4) + Int2(4) + PayloadLen(4) = 17 bytes
    let entrySize = 17 + payloadLen
    let offset = Int(updateLen)

    if offset + entrySize > updateCapacity {
        // Buffer overflow protection - in real app might want to flush or crash
        return
    }

    let base = updatePtr.advanced(by: offset)
    base[0] = op.rawValue
    storeInt32(id, at: base.advanced(by: 1))
    storeInt32(intParam, at: base.advanced(by: 5))
    storeInt32(intParam2, at: base.advanced(by: 9))
    storeInt32(Int32(payloadLen), at: base.advanced(by: 13))

    for i in 0..<payloadLen {
        base[17 + i] = bytes[i]
    }

    updateLen = Int32(offset + entrySize)
}

private func storeInt32(_ value: Int32, at ptr: UnsafeMutablePointer<UInt8>) {
    ptr[0] = UInt8(truncatingIfNeeded: value)
    ptr[1] = UInt8(truncatingIfNeeded: value >> 8)
    ptr[2] = UInt8(truncatingIfNeeded: value >> 16)
    ptr[3] = UInt8(truncatingIfNeeded: value >> 24)
}

@_expose(wasm, "neatUpdatePtr")
@_cdecl("neatUpdatePtr")
public func neatUpdatePtr() -> UnsafePointer<UInt8> {
    UnsafePointer(updatePtr)
}

@_expose(wasm, "neatUpdateLen")
@_cdecl("neatUpdateLen")
public func neatUpdateLen() -> Int32 {
    updateLen
}

@_expose(wasm, "neatClearUpdate")
@_cdecl("neatClearUpdate")
public func neatClearUpdate() {
    updateLen = 0
}

@_expose(wasm, "neatLastPatchCount")
@_cdecl("neatLastPatchCount")
public func neatLastPatchCountExport() -> Int32 {
    neatLastPatchCount
}

@_expose(wasm, "neatLastRenderCount")
@_cdecl("neatLastRenderCount")
public func neatLastRenderCountExport() -> Int32 {
    neatLastRenderCount
}

@_expose(wasm, "neatLastStateSetCount")
@_cdecl("neatLastStateSetCount")
public func neatLastStateSetCountExport() -> Int32 {
    neatLastStateSetCount
}

@_expose(wasm, "neatLastStateOwnerID")
@_cdecl("neatLastStateOwnerID")
public func neatLastStateOwnerIDExport() -> Int32 {
    neatLastStateOwnerID
}

@_expose(wasm, "neatLastStateSlot")
@_cdecl("neatLastStateSlot")
public func neatLastStateSlotExport() -> Int32 {
    neatLastStateSlot
}

@_expose(wasm, "neatLastStateReadCount")
@_cdecl("neatLastStateReadCount")
public func neatLastStateReadCountExport() -> Int32 {
    neatLastStateReadCount
}

@_expose(wasm, "neatLastStateReadDouble")
@_cdecl("neatLastStateReadDouble")
public func neatLastStateReadDoubleExport() -> Double {
    neatLastStateReadDouble
}

@_expose(wasm, "neatLastStateSetDouble")
@_cdecl("neatLastStateSetDouble")
public func neatLastStateSetDoubleExport() -> Double {
    neatLastStateSetDouble
}

@_expose(wasm, "neatLastTextDiffCount")
@_cdecl("neatLastTextDiffCount")
public func neatLastTextDiffCountExport() -> Int32 {
    neatLastTextDiffCount
}

@_expose(wasm, "neatLastTextCompareCount")
@_cdecl("neatLastTextCompareCount")
public func neatLastTextCompareCountExport() -> Int32 {
    neatLastTextCompareCount
}

@_expose(wasm, "neatLastTextCompareParentID")
@_cdecl("neatLastTextCompareParentID")
public func neatLastTextCompareParentIDExport() -> Int32 {
    neatLastTextCompareParentID
}

@_expose(wasm, "neatLastTextCompareWasEqual")
@_cdecl("neatLastTextCompareWasEqual")
public func neatLastTextCompareWasEqualExport() -> Int32 {
    neatLastTextCompareWasEqual
}

@_expose(wasm, "neatLastRenderStateReadCount")
@_cdecl("neatLastRenderStateReadCount")
public func neatLastRenderStateReadCountExport() -> Int32 {
    neatLastRenderStateReadCount
}

@_expose(wasm, "neatLastRenderStateReadDouble")
@_cdecl("neatLastRenderStateReadDouble")
public func neatLastRenderStateReadDoubleExport() -> Double {
    neatLastRenderStateReadDouble
}

@_expose(wasm, "neatLastRenderedTextID")
@_cdecl("neatLastRenderedTextID")
public func neatLastRenderedTextIDExport() -> Int32 {
    neatLastRenderedTextID
}

@_expose(wasm, "neatLastRenderedTextLen")
@_cdecl("neatLastRenderedTextLen")
public func neatLastRenderedTextLenExport() -> Int32 {
    neatLastRenderedTextLen
}

@_expose(wasm, "neatLastRenderedTextPtr")
@_cdecl("neatLastRenderedTextPtr")
public func neatLastRenderedTextPtrExport() -> UnsafePointer<UInt8> {
    neatLastRenderedTextStorage.withUnsafeBufferPointer { $0.baseAddress! }
}

@_expose(wasm, "neatLastDiffOldTextLen")
@_cdecl("neatLastDiffOldTextLen")
public func neatLastDiffOldTextLenExport() -> Int32 {
    neatLastDiffOldTextLen
}

@_expose(wasm, "neatLastDiffNewTextLen")
@_cdecl("neatLastDiffNewTextLen")
public func neatLastDiffNewTextLenExport() -> Int32 {
    neatLastDiffNewTextLen
}

@_expose(wasm, "neatLastDiffOldTextPtr")
@_cdecl("neatLastDiffOldTextPtr")
public func neatLastDiffOldTextPtrExport() -> UnsafePointer<UInt8> {
    neatLastDiffOldTextStorage.withUnsafeBufferPointer { $0.baseAddress! }
}

@_expose(wasm, "neatLastDiffNewTextPtr")
@_cdecl("neatLastDiffNewTextPtr")
public func neatLastDiffNewTextPtrExport() -> UnsafePointer<UInt8> {
    neatLastDiffNewTextStorage.withUnsafeBufferPointer { $0.baseAddress! }
}
#endif
