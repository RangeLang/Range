@propertyWrapper
public final class State<Value> {
    private var storage: Value
    private var slot: Int?
    private weak var owner: RuntimeNode?
    public var wrappedValue: Value {
        get { value }
        set { value = newValue }
    }
    public init(wrappedValue: Value) {
        self.storage = wrappedValue
    }

    public var projectedValue: Binding<Value> {
        Binding(
            get: { self.wrappedValue },
            set: { self.wrappedValue = $0 }
        )
    }

    public var value: Value {
        get {
            if let owner, let slot {
                let value = owner.state(slot: slot, default: storage)
                #if os(WASI)
                neatLastStateReadCount &+= 1
                if let doubleValue = value as? Double {
                    neatLastStateReadDouble = doubleValue
                }
                if neatRenderPhase == 1 {
                    neatLastRenderStateReadCount &+= 1
                    if let doubleValue = value as? Double {
                        neatLastRenderStateReadDouble = doubleValue
                    }
                }
                #endif
                return value
            }
            if let key = resolveSlot() {
                let value = key.owner.state(slot: key.slot, default: storage)
                #if os(WASI)
                neatLastStateReadCount &+= 1
                if let doubleValue = value as? Double {
                    neatLastStateReadDouble = doubleValue
                }
                if neatRenderPhase == 1 {
                    neatLastRenderStateReadCount &+= 1
                    if let doubleValue = value as? Double {
                        neatLastRenderStateReadDouble = doubleValue
                    }
                }
                #endif
                return value
            }
            return storage
        }
        set {
            storage = newValue
            if let owner, let slot {
                owner.setState(slot: slot, value: newValue)
                #if os(WASI)
                neatLastStateSetCount &+= 1
                neatLastStateOwnerID = owner.id
                neatLastStateSlot = Int32(slot)
                if let doubleValue = newValue as? Double {
                    neatLastStateSetDouble = doubleValue
                }
                #endif
            } else if let key = resolveSlot() {
                key.owner.setState(slot: key.slot, value: newValue)
                #if os(WASI)
                neatLastStateSetCount &+= 1
                neatLastStateOwnerID = key.owner.id
                neatLastStateSlot = Int32(key.slot)
                if let doubleValue = newValue as? Double {
                    neatLastStateSetDouble = doubleValue
                }
                #endif
            }
            #if os(WASI)
            if owner == nil, slot == nil {
                print("[neat-wasm] state set without owner/slot")
            } else {
                let ownerID = owner?.id ?? -1
                print("[neat-wasm] state set", ownerID, slot ?? -1)
            }
            #endif
            Renderer.shared.scheduleUpdate()
        }
    }

    private func resolveSlot() -> (owner: RuntimeNode, slot: Int)? {
        if let owner, let slot {
            return (owner, slot)
        }
        guard let context = RenderContext.current,
              let node = context.currentRuntimeNode
        else {
            #if os(WASI)
            print("[neat-wasm] state resolve failed (no runtime node)")
            #endif
            return nil
        }
        owner = node
        let resolvedSlot = slot ?? context.nextStateSlot()
        slot = resolvedSlot
        #if os(WASI)
        print("[neat-wasm] state resolve", node.id, resolvedSlot)
        #endif
        return (node, resolvedSlot)
    }
}

protocol StateSlotAssignable {
    func assign(owner: RuntimeNode, slot: Int)
}

extension State: StateSlotAssignable {
    func assign(owner: RuntimeNode, slot: Int) {
        self.owner = owner
        self.slot = slot
    }
}
