"use client";

import { useLayoutEffect, useRef } from "react";
import type { CSSProperties } from "react";

const logarithmicDashPositions = Array.from({ length: 18 }, (_, index) => {
  const step = index / 17;
  const logarithmicPosition = Math.log1p(9 * step) / Math.log(10);

  return {
    index,
    isRadix: index === 0 || index === 17 || index % 4 === 0,
    position: logarithmicPosition * 100,
  };
});

export function LogarithmicConnector() {
  const connectorRef = useRef<HTMLDivElement>(null);

  useLayoutEffect(() => {
    const connector = connectorRef.current;
    const sequence = connector?.parentElement;
    const zero = sequence?.querySelector<HTMLElement>("[data-log-zero]");
    const one = sequence?.querySelector<HTMLElement>("[data-log-one]");
    if (!connector || !sequence || !zero || !one) return;

    let active = true;
    const alignConnector = () => {
      if (!active) return;
      const sequenceRect = sequence.getBoundingClientRect();
      const zeroRect = zero.getBoundingClientRect();
      const oneRect = one.getBoundingClientRect();
      const startX = zeroRect.left + zeroRect.width / 2 - sequenceRect.left;
      const startY = zeroRect.bottom - sequenceRect.top;
      const endY = oneRect.top - sequenceRect.top;

      connector.style.left = `${startX}px`;
      connector.style.top = `${startY}px`;
      connector.style.width = "1px";
      connector.style.height = `${Math.max(1, endY - startY)}px`;
    };

    const resizeObserver = new ResizeObserver(alignConnector);
    resizeObserver.observe(sequence);
    resizeObserver.observe(zero);
    resizeObserver.observe(one);
    window.addEventListener("resize", alignConnector);
    void document.fonts.ready.then(alignConnector);
    alignConnector();

    return () => {
      active = false;
      resizeObserver.disconnect();
      window.removeEventListener("resize", alignConnector);
    };
  }, []);

  return (
    <div className="landingLogLine" aria-hidden="true" ref={connectorRef}>
      {logarithmicDashPositions.map(({ index, isRadix, position }) => (
        <span
          className={`landingLogDash${isRadix ? " landingLogDashRadix" : ""}`}
          key={index}
          style={{
            "--dash-position": `${position}%`,
          } as CSSProperties}
        />
      ))}
    </div>
  );
}
