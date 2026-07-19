type BenchmarkData = any;

const githubUrl = "https://github.com/georgetchelidze/Range/tree/development";

const baselineBenchmarks = [
  { name: "Loops", scale: "20m iterations", axisMax: 80, results: [["C++", 61.3], ["C", 61.4], ["Rust", 61.9], ["Swift", 62.5], ["Range", 66.3], ["Go", 79.6]] },
  { name: "Noise", scale: "50m samples", axisMax: 90, results: [["C", 70.5], ["C++", 70.9], ["Go", 78.9], ["Range", 82.4], ["Rust", 82.9], ["Swift", 82.9]] },
  { name: "Function Calls", scale: "20m iterations", axisMax: 80, results: [["Go", 64.2], ["C++", 67.4], ["C", 67.5], ["Rust", 67.9], ["Swift", 68.5], ["Range", 72.3]] },
  { name: "Strings", scale: "100k appends", axisMax: 500, results: [["C++", 3.6], ["Rust", 3.6], ["Go", 4.3], ["C", 4.4], ["Swift", 4.8], ["Range", 491.2]], note: "Range peak memory: 5.3 GB · peers: 1.8–4.2 MB" },
];

const improvedStringsBenchmark = {
  name: "Strings", scale: "100k appends", axisMax: 6,
  results: [["C", 3.9], ["C++", 3.9], ["Range", 4.1], ["Rust", 4.2], ["Go", 4.8], ["Swift", 5.6]],
  note: "Range peak memory: 1.9 MB",
};

const stringScalingBenchmarks = [
  { name: "100k appends", scale: "30 runs", axisMax: 7, results: [["C", 4.2], ["C++", 4.3], ["Range", 4.3], ["Rust", 4.4], ["Go", 5.3], ["Swift", 6.2]] },
  { name: "1m appends", scale: "30 runs", axisMax: 24, results: [["C++", 8.2], ["C", 8.7], ["Rust", 8.9], ["Go", 9.5], ["Range", 10.1], ["Swift", 20.7]] },
  { name: "5m appends", scale: "30 runs", axisMax: 70, results: [["C", 20.0], ["C++", 20.2], ["Rust", 20.3], ["Go", 21.3], ["Range", 27.2], ["Swift", 62.1]] },
  { name: "10m appends", scale: "30 runs", axisMax: 130, results: [["C", 36.1], ["Rust", 36.2], ["C++", 36.3], ["Go", 37.0], ["Range", 50.1], ["Swift", 118.4]] },
];

function escapeHtml(value: unknown): string {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function slug(value: string): string {
  return value.toLowerCase().replaceAll(" ", "-");
}

function formatWorkload(count: number): string {
  if (count >= 1_000_000) return `${Number.isInteger(count / 1_000_000) ? count / 1_000_000 : (count / 1_000_000).toFixed(1)}m`;
  if (count >= 1_000) return `${Number.isInteger(count / 1_000) ? count / 1_000 : (count / 1_000).toFixed(1)}k`;
  return String(count);
}

function formatMemory(kilobytes: number): string {
  return kilobytes >= 1024 ? `${(kilobytes / 1024).toFixed(1)} MB` : `${kilobytes} KB`;
}

const rangeKeywords = new Set([
  "binding", "break", "case", "closed", "construct", "continue", "default", "derived", "else", "enum", "extension", "for", "function", "get", "if", "in", "infix", "init", "let", "macro", "open", "operator", "postfix", "precedencegroup", "prefix", "protocol", "return", "set", "state", "switch", "while",
]);

function highlightRange(source: string): string {
  const pattern = /(@[A-Za-z_]\w*|\/\/.*$|"(?:\\.|[^"\\])*"|\b[A-Za-z_]\w*\b|\b\d(?:_?\d)*(?:\.\d(?:_?\d)*)?\b|[{}[\]();,.])/gm;
  let output = "";
  let cursor = 0;
  for (const match of source.matchAll(pattern)) {
    const token = match[0];
    const index = match.index ?? 0;
    output += escapeHtml(source.slice(cursor, index));
    let type = "";
    if (token.startsWith("//")) type = "comment";
    else if (token.startsWith('"')) type = "string";
    else if (token.startsWith("@")) type = "atrule";
    else if (rangeKeywords.has(token)) type = "keyword";
    else if (/^[A-Z]/.test(token)) type = "class-name";
    else if (/^\d/.test(token)) type = "number";
    else if (/^[{}[\]();,.]$/.test(token)) type = "punctuation";
    output += type ? `<span class="token ${type}">${escapeHtml(token)}</span>` : escapeHtml(token);
    cursor = index + token.length;
  }
  return output + escapeHtml(source.slice(cursor));
}

function codeBlock(source: string, syntax: string, label: string): string {
  const highlighted = syntax === "range" ? highlightRange(source.trimEnd()) : escapeHtml(source.trimEnd());
  return `<range-code-block><section class="codeBlock" aria-label="${escapeHtml(label)}"><header>${escapeHtml(label)}</header><div class="codeBlockBody"><pre class="language-${escapeHtml(syntax)}"><code>${highlighted}</code></pre></div></section></range-code-block>`;
}

function githubIcon(): string {
  return `<svg viewBox="0 0 16 16" width="18" height="18" aria-hidden="true" fill="currentColor"><path d="M6.766 11.328c-2.063-.25-3.516-1.734-3.516-3.656 0-.781.281-1.625.75-2.188-.203-.515-.172-1.609.063-2.062.625-.078 1.468.25 1.968.703.594-.187 1.219-.281 1.985-.281.765 0 1.39.094 1.953.265.484-.437 1.344-.765 1.969-.687.218.422.25 1.515.046 2.047.5.593.766 1.39.766 2.203 0 1.922-1.453 3.375-3.547 3.64.531.344.89 1.094.89 1.954v1.625c0 .468.391.734.86.547C13.781 14.359 16 11.53 16 8.03 16 3.61 12.406 0 7.984 0 3.563 0 0 3.61 0 8.031a7.88 7.88 0 0 0 5.172 7.422c.422.156.828-.125.828-.547v-1.25c-.219.094-.5.156-.75.156-1.031 0-1.64-.562-2.078-1.609-.172-.422-.36-.672-.719-.719-.187-.015-.25-.093-.25-.187 0-.188.313-.328.625-.328.453 0 .844.281 1.25.86.313.452.64.655 1.031.655s.641-.14 1-.5c.266-.265.47-.5.657-.656"/></svg>`;
}

function chart(benchmark: any, id: string): string {
  const results = benchmark.results.map((item: any) => Array.isArray(item) ? { language: item[0], milliseconds: item[1] } : item);
  const fastest = Math.min(...results.map((result: any) => result.milliseconds));
  const rows = results.map((result: any) => {
    const isRange = result.language === "Range";
    const isFastest = Math.abs(result.milliseconds - fastest) < 0.0001;
    const scaleDeviation = (result.milliseconds - fastest) / benchmark.axisMax;
    const greenThreshold = 0.02;
    const redThreshold = 0.3;
    const orangeProgress = Math.min(1, Math.max(0, (scaleDeviation - greenThreshold) / (redThreshold - greenThreshold)));
    const softened = Math.log1p(2 * orangeProgress ** 1.7) / Math.log(3);
    const yellowStop = 0.58;
    const yellowMix = Math.min(100, (softened / yellowStop) * 100);
    const orangeMix = Math.max(0, ((softened - yellowStop) / (1 - yellowStop)) * 100);
    const redMix = scaleDeviation <= redThreshold ? 0 : Math.min(100, Math.max(0, (Math.log(scaleDeviation / redThreshold) / Math.log(1 / redThreshold)) * 100));
    const preRed = softened <= yellowStop
      ? `color-mix(in oklch, var(--fastest-bar), var(--yellow-bar) ${yellowMix.toFixed(1)}%)`
      : `color-mix(in oklch, var(--yellow-bar), var(--warning-bar) ${orangeMix.toFixed(1)}%)`;
    const color = scaleDeviation <= redThreshold ? preRed : `color-mix(in oklch, var(--warning-bar), var(--slow-bar) ${redMix.toFixed(1)}%)`;
    return `<div class="row${isRange ? " range" : ""}${isFastest ? " fastest" : ""}"><span class="language">${escapeHtml(result.language)}</span><span class="track" aria-hidden="true"><span class="bar" style="width:${(result.milliseconds / benchmark.axisMax) * 100}%;background:${color}"></span></span><span class="value"><span>${result.milliseconds.toFixed(1)} ms</span>${isFastest && !isRange ? "<small>absolute best</small>" : ""}</span></div>`;
  }).join("");
  const implementationCode = benchmark.implementations?.length
    ? `<details class="testCode"><summary>Test code</summary><div class="testCodeGrid">${benchmark.implementations.map((item: any) => codeBlock(item.source, item.syntax, `${item.language} · ${item.filename}`)).join("")}</div></details>`
    : "";
  return `<range-benchmark-chart><section class="chart" aria-labelledby="${id}-title"><header class="chartHeader"><div><h2 id="${id}-title">${benchmark.href ? `<a href="${benchmark.href}">${escapeHtml(benchmark.name)}</a>` : escapeHtml(benchmark.name)}</h2>${benchmark.leaf ? `<p class="chartLeaf">${escapeHtml(benchmark.leaf)}</p>` : ""}</div><span>${escapeHtml(benchmark.scale)}</span></header>${benchmark.description ? `<p class="chartDescription">${escapeHtml(benchmark.description)}</p>` : ""}<div class="rows">${rows}</div><div class="axis" aria-hidden="true"><span></span><span class="ticks"><span>0</span><span>${benchmark.axisMax / 2}</span><span>${benchmark.axisMax}</span></span><span></span></div>${benchmark.note ? `<p class="chartNote">${escapeHtml(benchmark.note)}</p>` : ""}${implementationCode}</section></range-benchmark-chart>`;
}

function procedure(data: BenchmarkData): string {
  const commands = data.procedure.commands;
  return `<ol>${data.procedure.steps.map((step: string) => `<li>${escapeHtml(step)}</li>`).join("")}</ol><div class="runCommands">${codeBlock(`${commands.suite.join("\n")}\n`, "shellscript", "Suite")}${codeBlock(`${commands.c.join("\n")}\n`, "shellscript", "C")}${codeBlock(`${commands.range.join("\n")}\n`, "shellscript", "Range")}</div><ul class="runNotes">${data.procedure.notes.map((note: string) => `<li>${escapeHtml(note)}</li>`).join("")}</ul>`;
}

function benchmarkRecords(data: BenchmarkData): any[] {
  return data.categories.flatMap((category: any) => category.subcategories.flatMap((subcategory: any) => subcategory.leaves.map((leaf: any) => ({ category, subcategory, leaf }))));
}

function benchmarkFromLeaf(data: BenchmarkData, subcategory: string, leaf: any): any {
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

function home(data: BenchmarkData): string {
  return `<range-home-page><main class="landingPage"><div class="landingSequence"><header class="landingNav"><a class="landingWordmark" href="/"><span class="landingIndex" data-scale-zero>0</span><span class="rangeWord">Range</span></a><nav aria-label="Primary navigation"><a href="/benchmarks">Benchmarks</a><a href="/updates/string-lowering">Updates</a><a href="${githubUrl}" target="_blank" rel="noreferrer">GitHub</a></nav></header><range-scale aria-hidden="true" endpoint-gap="8" division-base="3" division-levels="3" pinch="0.27" pinch-core="10" pinch-falloff="0.16" pinch-inner-edge="0.68" pinch-strength="0.9" measure-minimum="0.7" invisible-collapse-power="1.35" invisible-measure-minimum="0.1" invisible-stroke-minimum="0.06" marker-capture-division-weight="0.48" marker-capture-falloff="0.14" marker-capture-strength="0.9" stroke-minimum="0.65" snap-hysteresis="0.08" snap-to-marks="true" tone-falloff="0.12" tone-intensity="0.16"></range-scale><range-optical-guide aria-hidden="true"></range-optical-guide><section class="landingHero" aria-labelledby="range-title"><h1 id="range-title"><span class="landingIndex" data-scale-end><span>1</span></span><span class="rangeTitleWord">Range</span><span class="rangePerformanceAnchor" aria-hidden="true"></span></h1><p>a love letter to electrons, logic and abstraction</p><div class="landingActions"><a class="primaryAction" href="/benchmarks">Benchmarks</a><a class="secondaryAction" href="${githubUrl}" target="_blank" rel="noreferrer">${githubIcon()}GitHub</a></div></section></div><section class="landingLinks" aria-label="Range links"><a href="/benchmarks"><span><strong>Benchmarks</strong><small>${data.summary.runLeafCount} generated comparisons</small></span><span>View</span></a><a href="/updates/string-lowering"><span><strong>String lowering</strong><small>100k appends · 491.2 ms → 4.1 ms</small></span><span>View</span></a></section></main></range-home-page>`;
}

function benchmarksPage(url: URL, data: BenchmarkData): string {
  const completed = data.categories.map((category: any) => ({ ...category, subcategories: category.subcategories.map((subcategory: any) => ({ ...subcategory, leaves: subcategory.leaves.filter((leaf: any) => leaf.results.length > 0) })).filter((subcategory: any) => subcategory.leaves.length > 0) })).filter((category: any) => category.subcategories.length > 0);
  const active = completed.find((category: any) => category.id === url.searchParams.get("category")) ?? completed[0];
  const nav = completed.map((category: any) => {
    const count = category.subcategories.reduce((sum: number, item: any) => sum + item.leaves.length, 0);
    return `<a href="/benchmarks?category=${category.id}"${category.id === active.id ? ' aria-current="page"' : ""}><span>${escapeHtml(category.name)}</span><small>${count}</small></a>`;
  }).join("");
  const count = active.subcategories.reduce((sum: number, item: any) => sum + item.leaves.length, 0);
  const currentCharts = active.subcategories.flatMap((subcategory: any) => subcategory.leaves.map((leaf: any) => chart(benchmarkFromLeaf(data, subcategory.name, leaf), `current-${active.id}-${subcategory.id}-${leaf.id}`))).join("");
  const baseline = baselineBenchmarks.map((item) => chart(item, `baseline-${slug(item.name)}`)).join("");
  return `<range-benchmarks-page><main><header class="pageHeader"><a class="backLink routeWordmark" href="/"><span class="rangeWord">Range</span></a><h1><span>Range</span><range-typed-text text="Performance" delay="300" interval="45">Performance</range-typed-text></h1></header><section class="benchmarkProject" aria-labelledby="benchmark-project-title"><div class="sectionHeader"><h2 id="benchmark-project-title">Benchmark suite</h2><p class="dateLabel">${new Date(data.generatedAt).toLocaleDateString("en-US", { month: "long", day: "numeric", year: "numeric", timeZone: "UTC" })}</p></div><nav class="benchmarkIndex" aria-label="Benchmark categories">${nav}</nav><details class="runProcedure"><summary>Run procedure</summary><div class="runProcedureBody">${procedure(data)}</div></details><details class="benchmarkCategory" open><summary><span class="benchmarkCategoryTitle" role="heading" aria-level="3">${escapeHtml(active.name)}</span><span>${count} ${count === 1 ? "comparison" : "comparisons"}</span></summary><div class="chartGrid">${currentCharts}</div></details><div class="benchmarkRunStatus" aria-label="Current benchmark run status"><span>${data.summary.runLeafCount} of ${data.summary.leafCount} leaves run</span><span>Range passed ${data.summary.rangePassed}</span><span>Not emitted ${data.summary.rangeNotEmitted}</span><span>Failed ${data.summary.rangeFailed}</span></div></section><section class="benchmarkSection" aria-labelledby="baseline-title"><div class="sectionHeader"><h2 id="baseline-title">Initial benchmark</h2><p class="dateLabel">July 18, 2026</p></div><div class="chartGrid">${baseline}</div></section><range-status-list><section class="status" aria-labelledby="range-status-title"><div class="statusHeader"><p class="statusLabel">Compiler status</p><h2 id="range-status-title">4 of 6 tests emitted and passed</h2></div><ul class="statusList" aria-label="Tests not emitted in this pass"><li><span class="statusIcon" aria-hidden="true">×</span><span><strong>Collections</strong> · resolution stage 2</span></li><li><span class="statusIcon" aria-hidden="true">×</span><span><strong>Constructs</strong> · constructor-argument parse reachability</span></li></ul></section></range-status-list><section class="updatesSection" aria-labelledby="updates-title"><div class="sectionHeader"><h2 id="updates-title">Updates</h2></div><a class="updateLink" href="/updates/string-lowering"><span><strong>String lowering</strong><small>100k appends · 491.2 ms → 4.1 ms</small></span><time datetime="2026-07-18">July 18, 2026</time></a></section>${footer()}</main></range-benchmarks-page>`;
}

function footer(): string {
  return `<range-site-footer><footer><a class="githubButton" href="${githubUrl}" target="_blank" rel="noreferrer" aria-label="Open the Range development branch on GitHub">${githubIcon()}<span>GitHub</span></a><div class="footerMeta"><span>Range · native LLVM · O3</span><span>July 2026</span></div></footer></range-site-footer>`;
}

function benchmarkPage(id: string, data: BenchmarkData): string | null {
  const record = benchmarkRecords(data).find(({ leaf }) => leaf.id === id);
  if (!record) return null;
  const { category, subcategory, leaf } = record;
  const benchmark = benchmarkFromLeaf(data, subcategory.name, leaf);
  benchmark.href = undefined;
  const tableRows = leaf.results.map((result: any) => `<tr><th>${escapeHtml(result.language)}</th><td>${result.wallMilliseconds.toFixed(1)} ms</td><td>${result.cpuMilliseconds.toFixed(1)} ms</td><td>${formatMemory(result.peakRssKilobytes)}</td><td>${result.relativeToFastest.toFixed(2)}×</td><td>${escapeHtml(result.output)}</td></tr>`).join("");
  return `<range-benchmark-page><main><header class="benchmarkDetailHeader"><a class="backLink" href="/benchmarks">Benchmarks</a><div><p>${escapeHtml(category.name)}</p><h1>${escapeHtml(subcategory.name)} · ${escapeHtml(leaf.name)}</h1><span>${escapeHtml(leaf.description)}</span></div></header><section class="benchmarkDetailChart" aria-label="Benchmark comparison">${chart(benchmark, `benchmark-${leaf.id}`)}</section><section class="measurementsSection" aria-labelledby="measurements-title"><div class="sectionHeader"><h2 id="measurements-title">Measurements</h2><p class="dateLabel">Range ${escapeHtml(leaf.rangeStatus)}</p></div><div class="measurementTableWrap"><table class="measurementTable"><thead><tr><th>Language</th><th>Wall</th><th>CPU</th><th>Peak memory</th><th>Relative</th><th>Output</th></tr></thead><tbody>${tableRows}</tbody></table></div></section><section class="benchmarkProcedureSection" aria-labelledby="procedure-title"><div class="sectionHeader"><h2 id="procedure-title">Run procedure</h2></div>${procedure(data)}</section></main></range-benchmark-page>`;
}

function improvementChart(): string {
  return `<section class="improvementChart" aria-labelledby="range-improvement-chart-title"><header class="improvementHeader"><div class="improvementTitle"><h2 id="range-improvement-chart-title">100k appends · Range</h2><div class="improvementSummary"><span>~120× faster</span><span>~2,800× less peak memory</span></div></div></header><div class="improvementPlot"><svg class="bezierChart" viewBox="0 0 960 380" role="img" aria-labelledby="range-improvement-svg-title range-improvement-svg-description"><title id="range-improvement-svg-title">Range String performance before and after lowering</title><desc id="range-improvement-svg-description">Median wall time falls from 491.2 milliseconds to 4.1 milliseconds, while peak memory falls from 5.3 gigabytes to 1.9 megabytes.</desc><g class="bezierGrid"><line x1="55" y1="70" x2="930" y2="70"></line><line x1="55" y1="180" x2="930" y2="180"></line><line x1="55" y1="290" x2="930" y2="290"></line></g><path class="bezierLine" d="M 90 72 C 285 72, 430 290, 900 290"></path><circle class="bezierPoint" cx="90" cy="72" r="6"></circle><circle class="bezierPoint" cx="900" cy="290" r="6"></circle><g class="pointMetrics"><text class="pointTime" x="90" y="48" text-anchor="middle">491.2 ms</text><text class="pointMemory" x="90" y="102" text-anchor="middle">5.3 GB</text><text class="pointTime" x="900" y="266" text-anchor="middle">4.1 ms</text><text class="pointMemory" x="900" y="320" text-anchor="middle">1.9 MB</text></g><g class="bezierLabels"><text x="90" y="364" text-anchor="middle">Before</text><text x="900" y="364" text-anchor="middle">After</text></g></svg></div></section>`;
}

function updatePage(): string {
  const scaling = stringScalingBenchmarks.map((item) => chart(item, `scaling-${slug(item.name)}`)).join("");
  return `<range-update-page><main><header class="updatePageHeader"><a href="/">Range</a><div><h1>String lowering</h1><p class="dateLabel">July 18, 2026</p></div></header><section class="contextSection" aria-labelledby="lowering-sequence-title"><div class="sectionHeader"><h2 id="lowering-sequence-title">Sequence</h2><p class="dateLabel">7:29 PM</p></div><figure class="contextFigure"><div class="contextImageCrop"><img src="/string-lowering-conversation.png" alt="User message about processing strings together followed by the complete Codex response explaining Range String lowering"></div><figcaption>Owned String storage carries length, capacity, and data forward so unique growth can extend the same allocation.</figcaption></figure></section><section class="improvementSection" aria-labelledby="improved-title"><div class="sectionHeader"><h2 id="improved-title">Improvement</h2><p class="dateLabel">July 18, 2026</p></div>${improvementChart()}<div class="improvedStringComparison">${chart(improvedStringsBenchmark, "improved-strings")}</div></section><section class="scalingSection" aria-labelledby="scaling-title"><div class="sectionHeader"><h2 id="scaling-title">Scaling</h2><p class="dateLabel">July 18, 2026</p></div><div class="chartGrid">${scaling}</div></section></main></range-update-page>`;
}

function documentShell(content: string): string {
  return `<!doctype html><html lang="en" class="range-layout-pending"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Range</title><meta name="description" content="Native benchmark results for Range, C, C++, Rust, Go, and Swift, with compiler emission status."><meta property="og:title" content="Range"><meta property="og:description" content="Native benchmark results for Range, C, C++, Rust, Go, and Swift, with compiler emission status."><meta property="og:type" content="website"><meta property="og:image" content="/og-v3.png"><meta name="twitter:card" content="summary_large_image"><link rel="icon" href="/favicon.svg"><link rel="preload" href="/fonts/geist/Geist-Variable.woff2" as="font" type="font/woff2" crossorigin><link rel="preload" href="/fonts/geist/GeistMono-Variable.woff2" as="font" type="font/woff2" crossorigin><link rel="stylesheet" href="/range-ui.css"><style>html.range-layout-pending body{visibility:hidden}</style><noscript><style>html.range-layout-pending body{visibility:visible}</style></noscript><script type="module" src="/range-site.js"></script><script type="module" src="/range-scale.js?profile=pinch-dissolve-v4"></script><script type="module" src="/range-optical-guide.js?guide=glyph-ink-box"></script><script type="module" src="/range-typed-text.js"></script><script type="module" src="/range-navigation-v2.js"></script><script type="module" src="/range-layout-ready.js"></script></head><body><range-site-shell>${content}</range-site-shell></body></html>`;
}

export function renderDocument(url: URL, data: BenchmarkData): { html: string; status: number } | null {
  if (url.pathname === "/") return { html: documentShell(home(data)), status: 200 };
  if (url.pathname === "/benchmarks") return { html: documentShell(benchmarksPage(url, data)), status: 200 };
  const benchmarkMatch = url.pathname.match(/^\/benchmarks\/([^/]+)$/);
  if (benchmarkMatch) {
    const content = benchmarkPage(decodeURIComponent(benchmarkMatch[1]), data);
    return content ? { html: documentShell(content), status: 200 } : { html: documentShell("<main><h1>Not found</h1></main>"), status: 404 };
  }
  if (url.pathname === "/updates/string-lowering") return { html: documentShell(updatePage()), status: 200 };
  if (url.pathname.startsWith("/updates/")) return { html: documentShell("<main><h1>Not found</h1></main>"), status: 404 };
  return null;
}
