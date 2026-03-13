public enum WasmInstruction {
    case createText(id: Int32, text: String)
    case createElement(id: Int32, tag: String)
    case appendChild(parentId: Int32, childId: Int32)
    case removeChild(parentId: Int32, childId: Int32)
    case replaceChild(parentId: Int32, newId: Int32, oldId: Int32)
    case setAttribute(id: Int32, key: String, value: String)
    case removeAttribute(id: Int32, key: String)
    case setStyle(id: Int32, key: String, value: String)
    case removeStyle(id: Int32, key: String)
    case setText(id: Int32, text: String)
    case addEventListener(id: Int32, event: String)
    case removeEventListener(id: Int32, event: String)
}

public protocol WasmInstructionSink {
    func emit(_ instruction: WasmInstruction)
}
