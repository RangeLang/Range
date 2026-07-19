import type { DetailedHTMLProps, HTMLAttributes } from "react";

declare module "react" {
  namespace JSX {
    interface IntrinsicElements {
      "range-scale": DetailedHTMLProps<HTMLAttributes<HTMLElement>, HTMLElement> & {
        "endpoint-gap"?: string;
        marks?: string;
        pinch?: string;
        "pinch-falloff"?: string;
        "pinch-strength"?: string;
        "measure-peak"?: string;
      };
      "range-typed-text": DetailedHTMLProps<HTMLAttributes<HTMLElement>, HTMLElement> & {
        delay?: string;
        interval?: string;
        text?: string;
      };
    }
  }
}

export {};
