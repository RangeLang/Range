import benchmarkData from "../../../Benchmarks/Speed/results/latest.json";

export type BenchmarkResult = {
  language: string;
  milliseconds: number;
};

export type Benchmark = {
  name: string;
  leaf?: string;
  description?: string;
  scale: string;
  axisMax: number;
  results: (BenchmarkResult | [string, number])[];
  note?: string;
  href?: string;
  implementations?: { language: string; filename: string; syntax: string; source: string }[];
};

export const data: any = benchmarkData;
export const githubUrl = "https://github.com/georgetchelidze/Range/tree/development";

export const improvedStringsBenchmark: Benchmark = {
  name: "Strings",
  scale: "100k appends",
  axisMax: 6,
  results: [["C", 3.9], ["C++", 3.9], ["Range", 4.1], ["Rust", 4.2], ["Go", 4.8], ["Swift", 5.6]],
  note: "Range peak memory: 1.9 MB",
};

export const stringScalingBenchmarks: Benchmark[] = [
  { name: "100k appends", scale: "30 runs", axisMax: 7, results: [["C", 4.2], ["C++", 4.3], ["Range", 4.3], ["Rust", 4.4], ["Go", 5.3], ["Swift", 6.2]] },
  { name: "1m appends", scale: "30 runs", axisMax: 24, results: [["C++", 8.2], ["C", 8.7], ["Rust", 8.9], ["Go", 9.5], ["Range", 10.1], ["Swift", 20.7]] },
  { name: "5m appends", scale: "30 runs", axisMax: 70, results: [["C", 20.0], ["C++", 20.2], ["Rust", 20.3], ["Go", 21.3], ["Range", 27.2], ["Swift", 62.1]] },
  { name: "10m appends", scale: "30 runs", axisMax: 130, results: [["C", 36.1], ["Rust", 36.2], ["C++", 36.3], ["Go", 37.0], ["Range", 50.1], ["Swift", 118.4]] },
];

export function slug(value: string): string {
  return value.toLowerCase().replaceAll(" ", "-");
}

export function formatWorkload(count: number): string {
  if (count >= 1_000_000) return `${Number.isInteger(count / 1_000_000) ? count / 1_000_000 : (count / 1_000_000).toFixed(1)}m`;
  if (count >= 1_000) return `${Number.isInteger(count / 1_000) ? count / 1_000 : (count / 1_000).toFixed(1)}k`;
  return String(count);
}

export function formatMemory(kilobytes: number): string {
  return kilobytes >= 1024 ? `${(kilobytes / 1024).toFixed(1)} MB` : `${kilobytes} KB`;
}

export function completedCategories(): any[] {
  return data.categories
    .map((category: any) => ({
      ...category,
      subcategories: category.subcategories
        .map((subcategory: any) => ({ ...subcategory, leaves: subcategory.leaves.filter((leaf: any) => leaf.results.length > 0) }))
        .filter((subcategory: any) => subcategory.leaves.length > 0),
    }))
    .filter((category: any) => category.subcategories.length > 0);
}

export function benchmarkRecords(): any[] {
  return data.categories.flatMap((category: any) =>
    category.subcategories.flatMap((subcategory: any) =>
      subcategory.leaves.map((leaf: any) => ({ category, subcategory, leaf })),
    ),
  );
}

export function benchmarkFromLeaf(subcategory: string, leaf: any): Benchmark {
  return {
    name: subcategory,
    leaf: leaf.name,
    description: leaf.description,
    scale: `${formatWorkload(leaf.workload.count)} ${leaf.workload.unit} · ${data.configuration.runs} runs`,
    axisMax: Math.max(leaf.axisMaxMilliseconds, 1),
    implementations: leaf.implementations,
    href: `/benchmarks/${leaf.id}`,
    results: leaf.results.map((result: any) => ({ language: result.language, milliseconds: result.wallMilliseconds })),
  };
}

const rangeKeywords = new Set([
  "background", "binding", "break", "builder", "capture", "case", "closed",
  "construct", "continue", "core", "default", "derived", "else", "enum",
  "extension", "function", "get", "if", "in", "infix", "init", "let",
  "macro", "main", "marker", "namespace", "nil", "on", "open", "operator",
  "package", "postfix", "precedencegroup", "prefix", "protocol", "return",
  "self", "set", "state", "switch", "var", "while",
]);

const rangeTypeDeclarationKeywords = new Set([
  "construct", "enum", "namespace", "protocol",
]);

const rangeBindingKeywords = new Set([
  "binding", "let", "state", "var",
]);

function rangeSemanticTokenType(
  token: string,
  previous: string,
  next: string,
) {
  if (token.startsWith("//")) return "comment";
  if (token.startsWith('"')) return "string";
  if (token === "@stored") return "type";
  if (token.startsWith("@")) return "macro";
  if (token.startsWith("#")) return "splice";
  if (/^\d/.test(token)) return "number";
  if (/^[{}]$/.test(token)) return "brace";
  if (/^[{}[\]();,.:<>]$/.test(token)) return "punctuation";
  if (!/^[A-Za-z_]/.test(token)) return "";

  if (previous === "." && next === "(") return "method";
  if (previous === ".") return "property";
  if (rangeKeywords.has(token)) return "keyword";
  if (previous === "macro" || previous === "marker") {
    return "macro-declaration";
  }
  if (rangeTypeDeclarationKeywords.has(previous)) {
    return "type-declaration";
  }
  if (/^[A-Z]/.test(token)) return "type";
  if (previous === "function") return "function-declaration";
  if (next === "(") return "function";
  if (next === ":") return "parameter";
  if (rangeBindingKeywords.has(previous)) return "variable-declaration";
  return "variable";
}

export function escapeHtml(value: unknown): string {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

export function highlightRange(source: string): string {
  const pattern = /([@#][A-Za-z_]\w*|\/\/.*$|"(?:\\.|[^"\\])*"|\b[A-Za-z_]\w*\b|\b\d(?:_?\d)*(?:\.\d(?:_?\d)*)?\b|[{}[\]();,.:<>])/gm;
  const matches = Array.from(source.matchAll(pattern));
  let output = "";
  let cursor = 0;
  for (const [matchIndex, match] of matches.entries()) {
    const token = match[0];
    const index = match.index ?? 0;
    output += escapeHtml(source.slice(cursor, index));
    const previous = matches[matchIndex - 1]?.[0] ?? "";
    const next = matches[matchIndex + 1]?.[0] ?? "";
    const type = rangeSemanticTokenType(token, previous, next);
    output += type ? `<span class="token ${type}">${escapeHtml(token)}</span>` : escapeHtml(token);
    cursor = index + token.length;
  }
  return output + escapeHtml(source.slice(cursor));
}
