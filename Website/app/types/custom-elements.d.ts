import type { DetailedHTMLProps, HTMLAttributes } from "react";

declare module "react" {
  namespace JSX {
    interface IntrinsicElements {
      "range-scale": DetailedHTMLProps<HTMLAttributes<HTMLElement>, HTMLElement> & {
        "endpoint-gap"?: string;
        "division-base"?: string;
        "division-levels"?: string;
        pinch?: string;
        "pinch-core"?: string;
        "pinch-falloff"?: string;
        "pinch-inner-edge"?: string;
        "pinch-strength"?: string;
        "marker-capture-division-weight"?: string;
        "marker-capture-falloff"?: string;
        "marker-capture-strength"?: string;
        "measure-minimum"?: string;
        "invisible-collapse-power"?: string;
        "invisible-measure-minimum"?: string;
        "invisible-stroke-minimum"?: string;
        "stroke-minimum"?: string;
        "tone-falloff"?: string;
        "tone-intensity"?: string;
      };
      "range-optical-guide": DetailedHTMLProps<HTMLAttributes<HTMLElement>, HTMLElement>;
      "range-typed-text": DetailedHTMLProps<HTMLAttributes<HTMLElement>, HTMLElement> & {
        delay?: string;
        interval?: string;
        text?: string;
      };
    }
  }
}

export {};
