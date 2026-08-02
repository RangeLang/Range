export const RANGE_LAYOUT_TRACKER_CONTEXT = Symbol("range-layout-tracker");

export type RangeLayoutRect = {
  top: number;
  right: number;
  bottom: number;
  left: number;
  width: number;
  height: number;
  x: number;
  y: number;
};

export type RangeLayoutSnapshot = {
  rect: RangeLayoutRect;
  documentX: number;
  documentY: number;
  centerX: number;
  centerY: number;
  distanceFromViewportCenterX: number;
  distanceFromViewportCenterY: number;
  distanceFromViewportCenter: number;
  normalizedViewportX: number;
  normalizedViewportY: number;
  viewportWidth: number;
  viewportHeight: number;
  scrollX: number;
  scrollY: number;
  visible: boolean;
};

export type RangeLayoutTracker = {
  locate: (target: Element) => RangeLayoutSnapshot;
  observe: (
    target: Element,
    listener: (snapshot: RangeLayoutSnapshot) => void,
  ) => () => void;
  refresh: () => void;
  dispose: () => void;
};

declare global {
  interface Window {
    __rangeLayoutTracker?: RangeLayoutTracker;
  }
}

export function createRangeLayoutTracker(): RangeLayoutTracker {
  const targets = new Map<
    Element,
    Set<(snapshot: RangeLayoutSnapshot) => void>
  >();
  let frame: number | undefined;
  let listening = false;
  let resizeObserver: ResizeObserver | undefined;

  const locate = (target: Element): RangeLayoutSnapshot => {
    const bounds = target.getBoundingClientRect();
    const viewportWidth = window.visualViewport?.width ?? window.innerWidth;
    const viewportHeight = window.visualViewport?.height ?? window.innerHeight;
    const scrollX = window.scrollX;
    const scrollY = window.scrollY;
    const centerX = bounds.left + bounds.width / 2;
    const centerY = bounds.top + bounds.height / 2;
    const distanceFromViewportCenterX = centerX - viewportWidth / 2;
    const distanceFromViewportCenterY = centerY - viewportHeight / 2;
    return {
      rect: {
        top: bounds.top,
        right: bounds.right,
        bottom: bounds.bottom,
        left: bounds.left,
        width: bounds.width,
        height: bounds.height,
        x: bounds.x,
        y: bounds.y,
      },
      documentX: bounds.left + scrollX,
      documentY: bounds.top + scrollY,
      centerX,
      centerY,
      distanceFromViewportCenterX,
      distanceFromViewportCenterY,
      distanceFromViewportCenter: Math.hypot(
        distanceFromViewportCenterX,
        distanceFromViewportCenterY,
      ),
      normalizedViewportX: centerX / Math.max(1, viewportWidth),
      normalizedViewportY: centerY / Math.max(1, viewportHeight),
      viewportWidth,
      viewportHeight,
      scrollX,
      scrollY,
      visible:
        bounds.right > 0 &&
        bounds.bottom > 0 &&
        bounds.left < viewportWidth &&
        bounds.top < viewportHeight,
    };
  };

  const refreshNow = () => {
    frame = undefined;
    for (const [target, listeners] of targets) {
      if (!target.isConnected) continue;
      const snapshot = locate(target);
      for (const listener of listeners) listener(snapshot);
    }
  };

  const refresh = () => {
    if (frame !== undefined || typeof window === "undefined") return;
    frame = window.requestAnimationFrame(refreshNow);
  };

  const startListening = () => {
    if (listening || typeof window === "undefined") return;
    listening = true;
    window.addEventListener("scroll", refresh, { passive: true, capture: true });
    window.addEventListener("resize", refresh, { passive: true });
    window.visualViewport?.addEventListener("scroll", refresh, { passive: true });
    window.visualViewport?.addEventListener("resize", refresh, { passive: true });
    resizeObserver = new ResizeObserver(refresh);
  };

  const stopListening = () => {
    if (!listening || typeof window === "undefined") return;
    listening = false;
    window.removeEventListener("scroll", refresh, true);
    window.removeEventListener("resize", refresh);
    window.visualViewport?.removeEventListener("scroll", refresh);
    window.visualViewport?.removeEventListener("resize", refresh);
    resizeObserver?.disconnect();
    resizeObserver = undefined;
  };

  const observe: RangeLayoutTracker["observe"] = (target, listener) => {
    let listeners = targets.get(target);
    if (!listeners) {
      listeners = new Set();
      targets.set(target, listeners);
      startListening();
      resizeObserver?.observe(target);
    }
    listeners.add(listener);
    listener(locate(target));
    return () => {
      listeners?.delete(listener);
      if (listeners?.size) return;
      targets.delete(target);
      resizeObserver?.unobserve(target);
      if (targets.size === 0) stopListening();
    };
  };

  const dispose = () => {
    if (frame !== undefined && typeof window !== "undefined") {
      window.cancelAnimationFrame(frame);
    }
    frame = undefined;
    targets.clear();
    stopListening();
  };

  return { locate, observe, refresh, dispose };
}
