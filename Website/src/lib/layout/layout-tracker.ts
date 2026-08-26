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

export type RangeLayoutQuery = Element | string | (() => Element | null);

export type RangeLayoutTracker = {
  locate: (target: Element) => RangeLayoutSnapshot;
  query: (
    target: RangeLayoutQuery,
    root?: ParentNode,
  ) => RangeLayoutSnapshot | undefined;
  observe: (
    target: RangeLayoutQuery,
    listener: (snapshot: RangeLayoutSnapshot) => void,
    root?: ParentNode,
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
  type Observation = {
    target: RangeLayoutQuery;
    root?: ParentNode;
    element?: Element;
    listener: (snapshot: RangeLayoutSnapshot) => void;
  };

  const observations = new Set<Observation>();
  let frame: number | undefined;
  let listening = false;
  let resizeObserver: ResizeObserver | undefined;
  let mutationObserver: MutationObserver | undefined;

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

  const resolve = (
    target: RangeLayoutQuery,
    root: ParentNode = document,
  ): Element | null => {
    if (typeof target === "string") return root.querySelector(target);
    if (typeof target === "function") return target();
    return target;
  };

  const query: RangeLayoutTracker["query"] = (target, root) => {
    if (typeof document === "undefined") return undefined;
    const element = resolve(target, root);
    return element?.isConnected ? locate(element) : undefined;
  };

  const updateObservedElement = (observation: Observation) => {
    const element = resolve(observation.target, observation.root);
    if (element === observation.element) return element;
    if (observation.element) resizeObserver?.unobserve(observation.element);
    observation.element = element ?? undefined;
    if (element) resizeObserver?.observe(element);
    return element;
  };

  const refreshNow = () => {
    frame = undefined;
    for (const observation of observations) {
      const target = updateObservedElement(observation);
      if (!target?.isConnected) continue;
      observation.listener(locate(target));
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
    mutationObserver = new MutationObserver(refresh);
    mutationObserver.observe(document.documentElement, {
      childList: true,
      subtree: true,
    });
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
    mutationObserver?.disconnect();
    mutationObserver = undefined;
  };

  const observe: RangeLayoutTracker["observe"] = (target, listener, root) => {
    const observation: Observation = { target, listener, root };
    observations.add(observation);
    startListening();
    const element = updateObservedElement(observation);
    if (element?.isConnected) listener(locate(element));
    return () => {
      observations.delete(observation);
      if (observation.element) resizeObserver?.unobserve(observation.element);
      if (observations.size === 0) stopListening();
    };
  };

  const dispose = () => {
    if (frame !== undefined && typeof window !== "undefined") {
      window.cancelAnimationFrame(frame);
    }
    frame = undefined;
    observations.clear();
    stopListening();
  };

  return { locate, query, observe, refresh, dispose };
}
