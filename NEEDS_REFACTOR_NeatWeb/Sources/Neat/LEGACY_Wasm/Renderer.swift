import Foundation

#if os(WASI)
public nonisolated(unsafe) var neatLastPatchCount: Int32 = 0
public nonisolated(unsafe) var neatLastRenderCount: Int32 = 0
public nonisolated(unsafe) var neatLastStateSetCount: Int32 = 0
public nonisolated(unsafe) var neatLastStateOwnerID: Int32 = -1
public nonisolated(unsafe) var neatLastStateSlot: Int32 = -1
public nonisolated(unsafe) var neatLastStateReadCount: Int32 = 0
public nonisolated(unsafe) var neatLastStateReadDouble: Double = 0
public nonisolated(unsafe) var neatLastStateSetDouble: Double = 0
public nonisolated(unsafe) var neatLastTextDiffCount: Int32 = 0
public nonisolated(unsafe) var neatLastTextCompareCount: Int32 = 0
public nonisolated(unsafe) var neatLastTextCompareParentID: Int32 = -1
public nonisolated(unsafe) var neatLastTextCompareWasEqual: Int32 = 0
public nonisolated(unsafe) var neatRenderPhase: Int32 = 0
public nonisolated(unsafe) var neatLastRenderStateReadCount: Int32 = 0
public nonisolated(unsafe) var neatLastRenderStateReadDouble: Double = 0
public nonisolated(unsafe) var neatLastRenderedTextID: Int32 = -1
public nonisolated(unsafe) var neatLastRenderedTextLen: Int32 = 0
public nonisolated(unsafe) var neatLastRenderedTextStorage: [UInt8] = []
public nonisolated(unsafe) var neatLastDiffOldTextLen: Int32 = 0
public nonisolated(unsafe) var neatLastDiffNewTextLen: Int32 = 0
public nonisolated(unsafe) var neatLastDiffOldTextStorage: [UInt8] = []
public nonisolated(unsafe) var neatLastDiffNewTextStorage: [UInt8] = []
#endif
public final class Renderer: @unchecked Sendable {
    public static let shared = Renderer()

    private var rootNode: RuntimeNode?
    private var rootComponent: (any Component)?

    private init() {}

    public func mount(_ component: any Component) {
        let node = RuntimeNode(componentType: type(of: component), key: nil)
        rootNode = node
        rootComponent = component

        // Initial build to establish the tree
        _ = renderRoot()

        // In Hydration mode, we DON'T emit instructions for the first tree
        // as the server already provided the HTML.
        // We just need to make sure subsequent state changes trigger diffs.
    }

    public func scheduleUpdate() {
        _ = renderRoot()
    }

    private func renderRoot() -> ElementNode? {
        guard let rootNode, let rootComponent else { return nil }
        let context = RenderContext()
        #if os(WASI)
        neatRenderPhase = 1
        neatLastRenderStateReadCount = 0
        neatLastTextDiffCount = 0
        neatLastTextCompareCount = 0
        neatLastTextCompareParentID = -1
        neatLastTextCompareWasEqual = 0
        neatLastDiffOldTextLen = 0
        neatLastDiffNewTextLen = 0
        neatLastDiffOldTextStorage = []
        neatLastDiffNewTextStorage = []
        #endif
        let newTree = context.withCurrent {
            context.withRootRuntimeNode(rootNode) {
                context.withRuntimeNode(rootNode) {
                    context.withTracking {
                        rootComponent.build(in: context)
                    }
                }
            }
        }
        #if os(WASI)
        neatRenderPhase = 0
        #endif
        let bucketed = newTree.withStyleBuckets(context: nil).normalizedForDiff()

        if let oldTree = rootNode.elementTree {
            let patches = DiffEngine.diff(old: oldTree.normalizedForDiff(), new: bucketed)
            #if os(WASI)
            neatLastPatchCount = Int32(patches.count)
            neatLastRenderCount &+= 1
            #endif
            for patch in patches {
                #if os(WASI)
                emitInstruction(patch)
                #else
                print("VDOM Patch: \(patch)")
                #endif
            }
        }

        rootNode.elementTree = bucketed
        return bucketed
    }
}

struct DiffEngine {
    static func diff(old: ElementNode, new: ElementNode) -> [WasmInstruction] {
        // We need the ID of the node to target instructions.
        // For this implementation, we assume the 'old' node has a valid data-neat-idx in its attributes.
        // The 'new' node might not have one yet if it's fresh from build(), but it should logically map to the same ID if we are diffing.

        return diffNodes(old: old, new: new, parentId: -1, index: 0)
    }

    private static func getId(_ node: ElementNode) -> Int32? {
        if case .element(_, let attrs, _, _, _) = node,
           let idStr = attrs["data-neat-idx"],
           let id = Int32(idStr) {
            return id
        }
        return nil
    }

    private static func createInstructions(from node: ElementNode, parentId: Int32) -> [WasmInstruction] {
        var instructions: [WasmInstruction] = []

        // Try to get ID from the node (injected by build), otherwise generate temporary one
        let idFromNode = getId(node)
        let newId = idFromNode ?? Int32.random(in: 10000..<Int32.max)

        switch node {
        case .element(let tag, let attrs, let classes, let styles, let children):
            instructions.append(.createElement(id: newId, tag: tag))

            for (key, val) in attrs {
                instructions.append(.setAttribute(id: newId, key: key, value: val))
            }
            if !classes.isEmpty {
                instructions.append(.setAttribute(id: newId, key: "class", value: classes.joined(separator: " ")))
            }

            for (key, val) in styles {
                instructions.append(.setStyle(id: newId, key: key, value: val.value))
            }

            instructions.append(.appendChild(parentId: parentId, childId: newId))

            for child in children {
                instructions.append(contentsOf: createInstructions(from: child, parentId: newId))
            }

        case .text(let text):
            instructions.append(.createText(id: newId, text: text))
            instructions.append(.appendChild(parentId: parentId, childId: newId))

        case .fragment(let nodes):
            for child in nodes {
                instructions.append(contentsOf: createInstructions(from: child, parentId: parentId))
            }
        }

        return instructions
    }

    private static func diffNodes(old: ElementNode, new: ElementNode, parentId: Int32, index: Int) -> [WasmInstruction] {
        var instructions: [WasmInstruction] = []

        let oldId = getId(old) ?? -1

        switch (old, new) {
        case (.text(let oldText), .text(let newText)):
            // Text nodes don't have IDs themselves in this model, so we target the parent element.
            #if os(WASI)
            neatLastTextCompareCount &+= 1
            neatLastTextCompareParentID = parentId
            let oldBytes = Array(oldText.utf8)
            neatLastDiffOldTextStorage = oldBytes
            neatLastDiffOldTextLen = Int32(oldBytes.count)
            let newBytes = Array(newText.utf8)
            neatLastDiffNewTextStorage = newBytes
            neatLastDiffNewTextLen = Int32(newBytes.count)
            #endif
            if oldText != newText {
                #if os(WASI)
                neatLastTextDiffCount &+= 1
                neatLastTextCompareWasEqual = 0
                #endif
                // We target the parent ID (the wrapper span or div) to set its text content.
                // This assumes the parent only contains this text node (which is true for Text component).
                instructions.append(.setText(id: parentId, text: newText))
            } else {
                #if os(WASI)
                neatLastTextCompareWasEqual = 1
                #endif
            }

        case (.fragment(let oldNodes), .fragment(let newNodes)):
            let commonCount = min(oldNodes.count, newNodes.count)
            for i in 0..<commonCount {
                instructions.append(contentsOf: diffNodes(old: oldNodes[i], new: newNodes[i], parentId: parentId, index: i))
            }
            if newNodes.count > oldNodes.count {
                for i in commonCount..<newNodes.count {
                    instructions.append(contentsOf: createInstructions(from: newNodes[i], parentId: parentId))
                }
            }
            if oldNodes.count > newNodes.count {
                for i in commonCount..<oldNodes.count {
                    if let childId = getId(oldNodes[i]) {
                        instructions.append(.removeChild(parentId: parentId, childId: childId))
                    }
                }
            }

        case (.element(let oldTag, let oldAttrs, let oldClasses, let oldStyles, let oldChildren),
              .element(let newTag, let newAttrs, let newClasses, let newStyles, let newChildren)):

            // 1. Check Identity (Tag)
            if oldTag != newTag {
                 // Tag changed: Replace whole tree
                 let creation = createInstructions(from: new, parentId: parentId)
                 instructions.append(contentsOf: creation)
                 instructions.append(.removeChild(parentId: parentId, childId: oldId))
                 return instructions
            }

            // 2. Diff Attributes
            for (key, newVal) in newAttrs {
                if oldAttrs[key] != newVal {
                    instructions.append(.setAttribute(id: oldId, key: key, value: newVal))
                }
            }
            for key in oldAttrs.keys {
                if newAttrs[key] == nil {
                    instructions.append(.removeAttribute(id: oldId, key: key))
                }
            }

            let oldClassValue = oldClasses.joined(separator: " ")
            let newClassValue = newClasses.joined(separator: " ")
            if oldClassValue != newClassValue {
                if newClassValue.isEmpty {
                    instructions.append(.removeAttribute(id: oldId, key: "class"))
                } else {
                    instructions.append(.setAttribute(id: oldId, key: "class", value: newClassValue))
                }
            }

            // 3. Diff Styles
            for (key, newVal) in newStyles {
                if let oldVal = oldStyles[key], oldVal.value == newVal.value {
                    continue
                }
                instructions.append(.setStyle(id: oldId, key: key, value: newVal.value))
            }
            for key in oldStyles.keys {
                if newStyles[key] == nil {
                    instructions.append(.removeStyle(id: oldId, key: key))
                }
            }

            // 4. Diff Children (Simple Index-based)
            let commonCount = min(oldChildren.count, newChildren.count)
            for i in 0..<commonCount {
                instructions.append(contentsOf: diffNodes(old: oldChildren[i], new: newChildren[i], parentId: oldId, index: i))
            }

            // Handle Additions
            if newChildren.count > oldChildren.count {
                for i in commonCount..<newChildren.count {
                    instructions.append(contentsOf: createInstructions(from: newChildren[i], parentId: oldId))
                }
            }

            // Handle Removals
            if oldChildren.count > newChildren.count {
                for i in commonCount..<oldChildren.count {
                    if let childId = getId(oldChildren[i]) {
                        instructions.append(.removeChild(parentId: oldId, childId: childId))
                    }
                }
            }

        default:
            break
        }

        return instructions
    }
}
