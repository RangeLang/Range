import { Prism, type PrismGrammar } from "prism-react-renderer";

const rangeGrammar: PrismGrammar = {
  comment: [
    {
      pattern: /\/\*[\s\S]*?\*\//,
      greedy: true,
    },
    {
      pattern: /\/\/.*$/m,
      greedy: true,
    },
  ],
  string: {
    pattern: /"(?:\\.|[^"\\])*"/,
    greedy: true,
  },
  annotation: {
    pattern: /@[A-Za-z_]\w*/,
    alias: "atrule",
  },
  keyword: /\b(?:binding|break|case|closed|construct|continue|default|derived|else|enum|extension|for|function|get|if|in|infix|init|let|macro|open|operator|postfix|precedencegroup|prefix|protocol|return|set|state|switch|while)\b/,
  boolean: /\b(?:false|true)\b/,
  nil: {
    pattern: /\bnil\b/,
    alias: "constant",
  },
  "enum-case": {
    pattern: /(^|[^\w.])\.[A-Za-z_]\w*/,
    lookbehind: true,
    alias: "constant",
  },
  type: {
    pattern: /\b[A-Z][A-Za-z0-9_]*\b/,
    alias: "class-name",
  },
  function: /\b[A-Za-z_]\w*(?=\s*\()/,
  label: {
    pattern: /\b[A-Za-z_]\w*(?=\s*:)/,
    alias: "property",
  },
  number: /\b(?:0[xX][\dA-Fa-f](?:_?[\dA-Fa-f])*|0[bB][01](?:_?[01])*|\d(?:_?\d)*(?:\.\d(?:_?\d)*)?(?:[eE][+-]?\d(?:_?\d)*)?)\b/,
  operator: /\.\.\.?|===?|!==?|<=?|>=?|&&|\|\||[-+*/%]=?|[?:]=?|!|&|\||\^|~/,
  punctuation: /[{}[\]();,.]/,
};

export function registerRangePrism(): typeof Prism {
  if (!Prism.languages.range) {
    Prism.languages.range = rangeGrammar;
  }
  return Prism;
}
