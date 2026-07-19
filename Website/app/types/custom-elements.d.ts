import type { DetailedHTMLProps, HTMLAttributes } from "react";

declare module "react" {
  namespace JSX {
    interface IntrinsicElements {
      "range-log-scale": DetailedHTMLProps<HTMLAttributes<HTMLElement>, HTMLElement> & {
        base?: string;
        "endpoint-gap"?: string;
        marks?: string;
        pinch?: string;
        "pinch-distance"?: string;
        "pinch-growth"?: string;
        "pinch-marks"?: string;
      };
    }
  }
}

export {};
