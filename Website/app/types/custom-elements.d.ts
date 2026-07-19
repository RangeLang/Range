import type { DetailedHTMLProps, HTMLAttributes } from "react";

declare module "react" {
  namespace JSX {
    interface IntrinsicElements {
      "range-scale": DetailedHTMLProps<HTMLAttributes<HTMLElement>, HTMLElement> & {
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
