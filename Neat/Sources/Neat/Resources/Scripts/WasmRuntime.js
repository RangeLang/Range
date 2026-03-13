(() => {
  const log = (...args) => {
    console.log("[neat-wasm]", ...args);
    window.NeatWasmLog.push({ level: "log", args, time: Date.now() });
  };
  const error = (...args) => {
    console.error("[neat-wasm]", ...args);
    window.NeatWasmLog.push({ level: "error", args, time: Date.now() });
  };
  const decoder = new TextDecoder("utf-8");
  let wasmMemory = null;
  let wasmInstance = null;

  window.NeatWasmLog = window.NeatWasmLog || [];
  const getView = () => {
    if (!wasmMemory) {
      throw new Error("WASM memory not ready");
    }
    return new DataView(wasmMemory.buffer);
  };

  const fdWrite = (fd, iovs, iovsLen, nwritten) => {
    const view = getView();
    let written = 0;
    for (let i = 0; i < iovsLen; i += 1) {
      const ptr = view.getUint32(iovs + i * 8, true);
      const len = view.getUint32(iovs + i * 8 + 4, true);
      const chunk = new Uint8Array(wasmMemory.buffer, ptr, len);
      const text = decoder.decode(chunk);
      if (fd === 1) {
        log(text);
      } else if (fd === 2) {
        error(text);
      }
      written += len;
    }
    view.setUint32(nwritten, written, true);
    return 0;
  };

  const writeSizes = (firstPtr, secondPtr) => {
    const view = getView();
    view.setUint32(firstPtr, 0, true);
    view.setUint32(secondPtr, 0, true);
    return 0;
  };

  const wasi = new Proxy(
    {
      fd_write: fdWrite,
      args_sizes_get: writeSizes,
      args_get: () => 0,
      environ_sizes_get: writeSizes,
      environ_get: () => 0,
      proc_exit: (code) => {
        log(`exit ${code}`);
        const err = new Error(`wasi exit ${code}`);
        err.__wasiExit = true;
        err.code = code;
        throw err;
      },
      clock_time_get: () => 0,
      random_get: (bufPtr, bufLen) => {
        if (!wasmMemory) return 0;
        const view = new Uint8Array(wasmMemory.buffer, bufPtr, bufLen);
        crypto.getRandomValues(view);
        return 0;
      },
    },
    {
      get(target, prop) {
        if (prop in target) {
          return target[prop];
        }
        return () => 0;
      },
    },
  );

  const Opcode = {
    createText: 0,
    createElement: 1,
    appendChild: 2,
    removeChild: 3,
    replaceChild: 4,
    setAttribute: 5,
    removeAttribute: 6,
    setStyle: 7,
    removeStyle: 8,
    setText: 9,
    addEventListener: 10,
    removeEventListener: 11,
  };

  class NeatRuntime {
    constructor() {
      this.nodes = new Map();
      this.wasmExports = null;
      this.lastOpCounts = null;
      this.lastCreateTag = null;
      this.lastAppendParent = null;
      this.lastAppendChild = null;
    }

    initialize(wasmExports) {
      this.wasmExports = wasmExports;

      document.querySelectorAll("[data-neat-idx]").forEach((el) => {
        const id = parseInt(el.getAttribute("data-neat-idx"));
        if (!isNaN(id)) {
          this.nodes.set(id, el);
        }
      });

      if (wasmExports.neatWasmInit) {
        wasmExports.neatWasmInit();
      }

      this.flushUpdates();
      this.hydrate();
    }

    flushUpdates() {
      if (!this.wasmExports) return;

      const len = this.wasmExports.neatUpdateLen();
      if (len === 0) return;

      const opCounts = {
        createText: 0,
        createElement: 0,
        appendChild: 0,
        removeChild: 0,
        replaceChild: 0,
        setAttribute: 0,
        removeAttribute: 0,
        setStyle: 0,
        removeStyle: 0,
        setText: 0,
        addEventListener: 0,
        removeEventListener: 0,
      };
      this.lastCreateTag = null;
      this.lastAppendParent = null;
      this.lastAppendChild = null;

      const ptr = this.wasmExports.neatUpdatePtr();
      const memory = new Uint8Array(this.wasmExports.memory.buffer);

      let offset = 0;
      while (offset < len) {
        const op = memory[ptr + offset];
        const id = this.readInt32(memory, ptr + offset + 1);
        const int1 = this.readInt32(memory, ptr + offset + 5);
        const int2 = this.readInt32(memory, ptr + offset + 9);
        const payloadLen = this.readInt32(memory, ptr + offset + 13);

        const payloadBytes = memory.subarray(
          ptr + offset + 17,
          ptr + offset + 17 + payloadLen,
        );
        const payload = decoder.decode(payloadBytes);

        this.execute(op, id, int1, int2, payload, opCounts);

        offset += 17 + payloadLen;
      }

      this.wasmExports.neatClearUpdate();
      this.lastOpCounts = opCounts;
      this.hydrate();
    }

    hydrate(root = document) {
      if (!window.Neat || !window.Neat.components) {
        return;
      }
      const hosts = root.querySelectorAll("[data-neat-component]");
      hosts.forEach((host) => {
        const name = host.getAttribute("data-neat-component");
        if (!name) return;
        const hydrate = window.Neat.components[name];
        if (hydrate) {
          hydrate(host);
        }
      });
    }

    execute(op, id, int1, int2, payload, opCounts) {
      switch (op) {
        case Opcode.createText:
          opCounts.createText += 1;
          const textNode = document.createTextNode(payload);
          this.nodes.set(id, textNode);
          break;

        case Opcode.createElement:
          opCounts.createElement += 1;
          this.lastCreateTag = payload;
          const el = document.createElement(payload);
          el.setAttribute("data-neat-idx", id);
          this.nodes.set(id, el);
          break;

        case Opcode.appendChild:
          opCounts.appendChild += 1;
          this.lastAppendParent = id;
          this.lastAppendChild = int1;
          const parentId = id;
          const childId = int1;
          const parent =
            this.nodes.get(parentId) ||
            document.querySelector(`[data-neat-idx="${parentId}"]`);
          const child = this.nodes.get(childId);
          if (parent && child) {
            parent.appendChild(child);
          }
          break;

        case Opcode.removeChild:
          opCounts.removeChild += 1;
          const pId = id;
          const cId = int1;
          const p =
            this.nodes.get(pId) ||
            document.querySelector(`[data-neat-idx="${pId}"]`);
          let c = this.nodes.get(cId);
          if (!c && p) {
            c = p.querySelector(`[data-neat-idx="${cId}"]`);
          }
          if (p && c) {
            p.removeChild(c);
            this.nodes.delete(cId);
          }
          break;

        case Opcode.replaceChild:
          opCounts.replaceChild += 1;
          const rp =
            this.nodes.get(id) ||
            document.querySelector(`[data-neat-idx="${id}"]`);
          const newChild = this.nodes.get(int1);
          let oldChild = this.nodes.get(int2);
          if (!oldChild && rp) {
            oldChild = rp.querySelector(`[data-neat-idx="${int2}"]`);
          }
          if (rp && newChild && oldChild) {
            rp.replaceChild(newChild, oldChild);
            this.nodes.delete(int2);
          }
          break;

        case Opcode.setAttribute:
          opCounts.setAttribute += 1;
          const nodeAttr =
            this.nodes.get(id) ||
            document.querySelector(`[data-neat-idx="${id}"]`);
          if (nodeAttr) {
            const parts = payload.split("=", 2);
            if (parts.length === 2) {
              nodeAttr.setAttribute(parts[0], parts[1]);
            }
          }
          break;

        case Opcode.removeAttribute:
          opCounts.removeAttribute += 1;
          const nodeRem =
            this.nodes.get(id) ||
            document.querySelector(`[data-neat-idx="${id}"]`);
          if (nodeRem) {
            nodeRem.removeAttribute(payload);
          }
          break;

        case Opcode.setStyle:
          opCounts.setStyle += 1;
          const nodeStyle =
            this.nodes.get(id) ||
            document.querySelector(`[data-neat-idx="${id}"]`);
          if (nodeStyle) {
            const parts = payload.split("=", 2);
            if (parts.length === 2) {
              nodeStyle.style.setProperty(parts[0], parts[1]);
            }
          }
          break;

        case Opcode.removeStyle:
          opCounts.removeStyle += 1;
          const nodeRS =
            this.nodes.get(id) ||
            document.querySelector(`[data-neat-idx="${id}"]`);
          if (nodeRS) {
            nodeRS.style.removeProperty(payload);
          }
          break;

        case Opcode.setText:
          opCounts.setText += 1;
          const nodeText =
            this.nodes.get(id) ||
            document.querySelector(`[data-neat-idx="${id}"]`);
          if (nodeText) {
            nodeText.textContent = payload;
          }
          break;

        case Opcode.addEventListener:
          opCounts.addEventListener += 1;
          break;

        case Opcode.removeEventListener:
          opCounts.removeEventListener += 1;
          break;
      }
    }

    readInt32(memory, ptr) {
      return (
        memory[ptr] |
        (memory[ptr + 1] << 8) |
        (memory[ptr + 2] << 16) |
        (memory[ptr + 3] << 24)
      );
    }

    dispatch(id) {
      if (this.wasmExports && this.wasmExports.neatHandleEvent) {
        const handled = this.wasmExports.neatHandleEvent(id, 0);
        log("dispatch", id, "handled", handled);
        const before = this.wasmExports.neatUpdateLen();
        this.flushUpdates();
        const after = this.wasmExports.neatUpdateLen();
        const patchCount = this.wasmExports.neatLastPatchCount
          ? this.wasmExports.neatLastPatchCount()
          : null;
        const renderCount = this.wasmExports.neatLastRenderCount
          ? this.wasmExports.neatLastRenderCount()
          : null;
        const stateSetCount = this.wasmExports.neatLastStateSetCount
          ? this.wasmExports.neatLastStateSetCount()
          : null;
        const stateOwnerID = this.wasmExports.neatLastStateOwnerID
          ? this.wasmExports.neatLastStateOwnerID()
          : null;
        const stateSlot = this.wasmExports.neatLastStateSlot
          ? this.wasmExports.neatLastStateSlot()
          : null;
        const stateReadCount = this.wasmExports.neatLastStateReadCount
          ? this.wasmExports.neatLastStateReadCount()
          : null;
        const stateReadDouble = this.wasmExports.neatLastStateReadDouble
          ? this.wasmExports.neatLastStateReadDouble()
          : null;
        const stateSetDouble = this.wasmExports.neatLastStateSetDouble
          ? this.wasmExports.neatLastStateSetDouble()
          : null;
        const textDiffCount = this.wasmExports.neatLastTextDiffCount
          ? this.wasmExports.neatLastTextDiffCount()
          : null;
        const renderStateReadCount = this.wasmExports
          .neatLastRenderStateReadCount
          ? this.wasmExports.neatLastRenderStateReadCount()
          : null;
        const renderStateReadDouble = this.wasmExports
          .neatLastRenderStateReadDouble
          ? this.wasmExports.neatLastRenderStateReadDouble()
          : null;
        const textCompareCount = this.wasmExports.neatLastTextCompareCount
          ? this.wasmExports.neatLastTextCompareCount()
          : null;
        const textCompareParentID = this.wasmExports.neatLastTextCompareParentID
          ? this.wasmExports.neatLastTextCompareParentID()
          : null;
        const textCompareWasEqual = this.wasmExports.neatLastTextCompareWasEqual
          ? this.wasmExports.neatLastTextCompareWasEqual()
          : null;
        let lastText = null;
        let lastTextID = null;
        if (this.wasmExports.neatLastRenderedTextPtr) {
          const textLen = this.wasmExports.neatLastRenderedTextLen();
          const textPtr = this.wasmExports.neatLastRenderedTextPtr();
          const textBytes = new Uint8Array(
            this.wasmExports.memory.buffer,
            textPtr,
            textLen,
          );
          lastText = decoder.decode(textBytes);
          lastTextID = this.wasmExports.neatLastRenderedTextID();
        }
        let lastDiffOldText = null;
        let lastDiffNewText = null;
        if (this.wasmExports.neatLastDiffOldTextPtr) {
          const oldLen = this.wasmExports.neatLastDiffOldTextLen();
          const oldPtr = this.wasmExports.neatLastDiffOldTextPtr();
          if (oldLen > 0) {
            const oldBytes = new Uint8Array(
              this.wasmExports.memory.buffer,
              oldPtr,
              oldLen,
            );
            lastDiffOldText = decoder.decode(oldBytes);
          }
          const newLen = this.wasmExports.neatLastDiffNewTextLen();
          const newPtr = this.wasmExports.neatLastDiffNewTextPtr();
          if (newLen > 0) {
            const newBytes = new Uint8Array(
              this.wasmExports.memory.buffer,
              newPtr,
              newLen,
            );
            lastDiffNewText = decoder.decode(newBytes);
          }
        }
        log("updates", {
          before,
          after,
          patchCount,
          renderCount,
          stateSetCount,
          stateOwnerID,
          stateSlot,
          stateReadCount,
          stateReadDouble,
          stateSetDouble,
          textDiffCount,
          renderStateReadCount,
          renderStateReadDouble,
          lastTextID,
          lastText,
          lastDiffOldText,
          lastDiffNewText,
          textCompareCount,
          textCompareParentID,
          textCompareWasEqual,
          opCounts: this.lastOpCounts,
          lastCreateTag: this.lastCreateTag,
          lastAppendParent: this.lastAppendParent,
          lastAppendChild: this.lastAppendChild,
        });
      }
    }
  }

  const runtime = new NeatRuntime();

  document.addEventListener("click", (event) => {
    let target = event.target;
    while (target && target !== document.body) {
      if (target.getAttribute && target.hasAttribute("data-neat-idx")) {
        const id = parseInt(target.getAttribute("data-neat-idx"));
        if (!isNaN(id)) {
          log("click", id);
          runtime.dispatch(id);
        }
      }
      target = target.parentElement;
    }
  });

  const start = async () => {
    const response = await fetch("/wasm/NeatExample.wasm");
    const bytes = await response.arrayBuffer();
    const { instance } = await WebAssembly.instantiate(bytes, {
      wasi_snapshot_preview1: wasi,
    });
    wasmInstance = instance;
    if (instance.exports.memory instanceof WebAssembly.Memory) {
      wasmMemory = instance.exports.memory;
    }

    const routeAttr = document.body?.getAttribute("data-neat-route");
    const routeIndex = routeAttr ? parseInt(routeAttr, 10) : 0;
    if (instance.exports.neatWasmSetRouteIndex) {
      instance.exports.neatWasmSetRouteIndex(
        Number.isFinite(routeIndex) ? routeIndex : 0,
      );
    }

    if (typeof instance.exports._start === "function") {
      try {
        instance.exports._start();
      } catch (err) {
        if (!err || !err.__wasiExit) {
          throw err;
        }
      }
    } else if (typeof instance.exports._initialize === "function") {
      instance.exports._initialize();
    }

    runtime.initialize(instance.exports);

    log("ready");
  };

  start().catch((err) => {
    error("error", err);
  });
})();
