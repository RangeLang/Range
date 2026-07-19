import { MarkGithubIcon, XIcon } from "@primer/octicons-react";
import benchmarkDataJson from "../public/benchmarks.json";

type Result = {
  language: string;
  milliseconds: number;
};

type Benchmark = {
  name: string;
  scale: string;
  axisMax: number;
  results: Result[];
  note?: string;
  leaf?: string;
  description?: string;
};

type BenchmarkMeasurement = {
  language: string;
  status: "passed";
  wallMilliseconds: number;
  cpuMilliseconds: number;
  peakRssKilobytes: number;
  relativeToFastest: number;
  relativeToC: number;
  output: string;
};

type BenchmarkLeaf = {
  id: string;
  name: string;
  description: string;
  workload: { count: number; unit: string };
  runStatus: "passed" | "notRun";
  rangeStatus: "passed" | "notEmitted" | "notRun";
  axisMaxMilliseconds: number;
  results: BenchmarkMeasurement[];
};

type BenchmarkArtifact = {
  schemaVersion: number;
  generatedAt: string;
  configuration: { baseIterations: number; runs: number; caseFilter: string[] };
  summary: {
    leafCount: number;
    runLeafCount: number;
    rangePassed: number;
    rangeNotEmitted: number;
    rangeFailed: number;
  };
  categories: Array<{
    id: string;
    name: string;
    subcategories: Array<{
      id: string;
      name: string;
      leaves: BenchmarkLeaf[];
    }>;
  }>;
};

const benchmarkData = benchmarkDataJson as BenchmarkArtifact;

const baselineBenchmarks: Benchmark[] = [
  {
    name: "Loops",
    scale: "20m iterations",
    axisMax: 80,
    results: [
      { language: "C++", milliseconds: 61.3 },
      { language: "C", milliseconds: 61.4 },
      { language: "Rust", milliseconds: 61.9 },
      { language: "Swift", milliseconds: 62.5 },
      { language: "Range", milliseconds: 66.3 },
      { language: "Go", milliseconds: 79.6 },
    ],
  },
  {
    name: "Noise",
    scale: "50m samples",
    axisMax: 90,
    results: [
      { language: "C", milliseconds: 70.5 },
      { language: "C++", milliseconds: 70.9 },
      { language: "Go", milliseconds: 78.9 },
      { language: "Range", milliseconds: 82.4 },
      { language: "Rust", milliseconds: 82.9 },
      { language: "Swift", milliseconds: 82.9 },
    ],
  },
  {
    name: "Function Calls",
    scale: "20m iterations",
    axisMax: 80,
    results: [
      { language: "Go", milliseconds: 64.2 },
      { language: "C++", milliseconds: 67.4 },
      { language: "C", milliseconds: 67.5 },
      { language: "Rust", milliseconds: 67.9 },
      { language: "Swift", milliseconds: 68.5 },
      { language: "Range", milliseconds: 72.3 },
    ],
  },
  {
    name: "Strings",
    scale: "100k appends",
    axisMax: 500,
    results: [
      { language: "C++", milliseconds: 3.6 },
      { language: "Rust", milliseconds: 3.6 },
      { language: "Go", milliseconds: 4.3 },
      { language: "C", milliseconds: 4.4 },
      { language: "Swift", milliseconds: 4.8 },
      { language: "Range", milliseconds: 491.2 },
    ],
    note: "Range peak memory: 5.3 GB · peers: 1.8–4.2 MB",
  },
];

const improvedStringsBenchmark: Benchmark = {
  name: "Strings",
  scale: "100k appends",
  axisMax: 6,
  results: [
    { language: "C", milliseconds: 3.9 },
    { language: "C++", milliseconds: 3.9 },
    { language: "Range", milliseconds: 4.1 },
    { language: "Rust", milliseconds: 4.2 },
    { language: "Go", milliseconds: 4.8 },
    { language: "Swift", milliseconds: 5.6 },
  ],
  note: "Range peak memory: 1.9 MB",
};

const stringScalingBenchmarks: Benchmark[] = [
  {
    name: "100k appends",
    scale: "30 runs",
    axisMax: 7,
    results: [
      { language: "C", milliseconds: 4.2 },
      { language: "C++", milliseconds: 4.3 },
      { language: "Range", milliseconds: 4.3 },
      { language: "Rust", milliseconds: 4.4 },
      { language: "Go", milliseconds: 5.3 },
      { language: "Swift", milliseconds: 6.2 },
    ],
  },
  {
    name: "1m appends",
    scale: "30 runs",
    axisMax: 24,
    results: [
      { language: "C++", milliseconds: 8.2 },
      { language: "C", milliseconds: 8.7 },
      { language: "Rust", milliseconds: 8.9 },
      { language: "Go", milliseconds: 9.5 },
      { language: "Range", milliseconds: 10.1 },
      { language: "Swift", milliseconds: 20.7 },
    ],
  },
  {
    name: "5m appends",
    scale: "30 runs",
    axisMax: 70,
    results: [
      { language: "C", milliseconds: 20.0 },
      { language: "C++", milliseconds: 20.2 },
      { language: "Rust", milliseconds: 20.3 },
      { language: "Go", milliseconds: 21.3 },
      { language: "Range", milliseconds: 27.2 },
      { language: "Swift", milliseconds: 62.1 },
    ],
  },
  {
    name: "10m appends",
    scale: "30 runs",
    axisMax: 130,
    results: [
      { language: "C", milliseconds: 36.1 },
      { language: "Rust", milliseconds: 36.2 },
      { language: "C++", milliseconds: 36.3 },
      { language: "Go", milliseconds: 37.0 },
      { language: "Range", milliseconds: 50.1 },
      { language: "Swift", milliseconds: 118.4 },
    ],
  },
];

function Chart({ benchmark, id }: { benchmark: Benchmark; id: string }) {
  const midpoint = benchmark.axisMax / 2;
  const fastestTime = Math.min(...benchmark.results.map((result) => result.milliseconds));

  return (
    <section className="chart" aria-labelledby={`${id}-title`}>
      <header className="chartHeader">
        <div>
          <h2 id={`${id}-title`}>{benchmark.name}</h2>
          {benchmark.leaf && <p className="chartLeaf">{benchmark.leaf}</p>}
        </div>
        <span>{benchmark.scale}</span>
      </header>

      {benchmark.description && <p className="chartDescription">{benchmark.description}</p>}

      <div className="rows">
        {benchmark.results.map((result) => {
          const isRange = result.language === "Range";
          const isFastest = Math.abs(result.milliseconds - fastestTime) < 0.0001;
          const width = `${(result.milliseconds / benchmark.axisMax) * 100}%`;
          const scaleDeviation = (result.milliseconds - fastestTime) / benchmark.axisMax;
          const greenThreshold = 0.02;
          const redThreshold = 0.3;
          const orangeProgress = Math.min(
            1,
            Math.max(0, (scaleDeviation - greenThreshold) / (redThreshold - greenThreshold)),
          );
          const softenedOrangeProgress = Math.log1p(2 * orangeProgress ** 1.7) / Math.log(3);
          const yellowStop = 0.58;
          const yellowMix = Math.min(100, (softenedOrangeProgress / yellowStop) * 100);
          const orangeMix = Math.max(
            0,
            ((softenedOrangeProgress - yellowStop) / (1 - yellowStop)) * 100,
          );
          const redMix = scaleDeviation <= redThreshold
            ? 0
            : Math.min(
                100,
                Math.max(
                  0,
                  (Math.log(scaleDeviation / redThreshold) / Math.log(1 / redThreshold)) *
                    100,
                ),
              );
          const preRedColor = softenedOrangeProgress <= yellowStop
            ? `color-mix(in oklch, var(--fastest-bar), var(--yellow-bar) ${yellowMix.toFixed(1)}%)`
            : `color-mix(in oklch, var(--yellow-bar), var(--warning-bar) ${orangeMix.toFixed(1)}%)`;
          const barColor = scaleDeviation <= redThreshold
            ? preRedColor
            : `color-mix(in oklch, var(--warning-bar), var(--slow-bar) ${redMix.toFixed(1)}%)`;

          return (
            <div
              className={`row${isRange ? " range" : ""}${isFastest ? " fastest" : ""}`}
              key={result.language}
            >
              <span className="language">{result.language}</span>
              <span className="track" aria-hidden="true">
                <span className="bar" style={{ width, background: barColor }} />
              </span>
              <span className="value">
                <span>{result.milliseconds.toFixed(1)} ms</span>
                {isFastest && !isRange && <small>absolute best</small>}
              </span>
            </div>
          );
        })}
      </div>

      <div className="axis" aria-hidden="true">
        <span />
        <span className="ticks">
          <span>0</span>
          <span>{midpoint}</span>
          <span>{benchmark.axisMax}</span>
        </span>
        <span />
      </div>

      {benchmark.note && <p className="chartNote">{benchmark.note}</p>}
    </section>
  );
}

function formatWorkload(count: number): string {
  if (count >= 1_000_000) {
    const millions = count / 1_000_000;
    return `${Number.isInteger(millions) ? millions.toFixed(0) : millions.toFixed(1)}m`;
  }
  if (count >= 1_000) {
    const thousands = count / 1_000;
    return `${Number.isInteger(thousands) ? thousands.toFixed(0) : thousands.toFixed(1)}k`;
  }
  return count.toString();
}

function benchmarkFromLeaf(subcategory: string, leaf: BenchmarkLeaf): Benchmark {
  return {
    name: subcategory,
    leaf: leaf.name,
    description: leaf.description,
    scale: `${formatWorkload(leaf.workload.count)} ${leaf.workload.unit} · ${benchmarkData.configuration.runs} runs`,
    axisMax: Math.max(leaf.axisMaxMilliseconds, 1),
    results: leaf.results.map((result) => ({
      language: result.language,
      milliseconds: result.wallMilliseconds,
    })),
  };
}

function RangeImprovementChart() {
  return (
    <section className="improvementChart" aria-labelledby="range-improvement-chart-title">
      <header className="improvementHeader">
        <div className="improvementTitle">
          <h2 id="range-improvement-chart-title">100k appends · Range</h2>
          <div className="improvementSummary">
            <span>~120× faster</span>
            <span>~2,800× less peak memory</span>
          </div>
        </div>
      </header>

      <div className="improvementPlot">
        <svg
          className="bezierChart"
          viewBox="0 0 960 380"
          role="img"
          aria-labelledby="range-improvement-svg-title range-improvement-svg-description"
        >
          <title id="range-improvement-svg-title">Range String performance before and after lowering</title>
          <desc id="range-improvement-svg-description">
            Median wall time falls from 491.2 milliseconds to 4.1 milliseconds, while peak memory
            falls from 5.3 gigabytes to 1.9 megabytes.
          </desc>

          <g className="bezierGrid">
            <line x1="55" y1="70" x2="930" y2="70" />
            <line x1="55" y1="180" x2="930" y2="180" />
            <line x1="55" y1="290" x2="930" y2="290" />
          </g>
          <path className="bezierLine" d="M 90 72 C 285 72, 430 290, 900 290" />
          <circle className="bezierPoint" cx="90" cy="72" r="6" />
          <circle className="bezierPoint" cx="900" cy="290" r="6" />

          <g className="pointMetrics">
            <text className="pointTime" x="90" y="48" textAnchor="middle">491.2 ms</text>
            <text className="pointMemory" x="90" y="102" textAnchor="middle">5.3 GB</text>
            <text className="pointTime" x="900" y="266" textAnchor="middle">4.1 ms</text>
            <text className="pointMemory" x="900" y="320" textAnchor="middle">1.9 MB</text>
          </g>

          <g className="bezierLabels">
            <text x="90" y="364" textAnchor="middle">Before</text>
            <text x="900" y="364" textAnchor="middle">After</text>
          </g>
        </svg>
      </div>
    </section>
  );
}

export default function Home() {
  return (
    <main>
      <header className="pageHeader">
        <h1>Range Performance</h1>
      </header>

      <section className="benchmarkProject" aria-labelledby="benchmark-project-title">
        <div className="sectionHeader">
          <h2 id="benchmark-project-title">Benchmark suite</h2>
          <p className="dateLabel">
            {new Date(benchmarkData.generatedAt).toLocaleDateString("en-US", {
              month: "long",
              day: "numeric",
              year: "numeric",
              timeZone: "UTC",
            })}
          </p>
        </div>

        <nav className="benchmarkIndex" aria-label="Benchmark categories">
          {benchmarkData.categories.map((category) => {
            const comparisonCount = category.subcategories.reduce(
              (count, subcategory) =>
                count + subcategory.leaves.filter((leaf) => leaf.results.length > 0).length,
              0,
            );
            if (comparisonCount === 0) return null;

            return (
              <a href={`#category-${category.id}`} key={category.id}>
                <span>{category.name}</span>
                <small>{comparisonCount}</small>
              </a>
            );
          })}
        </nav>

        {benchmarkData.categories.map((category, categoryIndex) => {
          const completedSubcategories = category.subcategories
            .map((subcategory) => ({
              ...subcategory,
              leaves: subcategory.leaves.filter((leaf) => leaf.results.length > 0),
            }))
            .filter((subcategory) => subcategory.leaves.length > 0);
          if (completedSubcategories.length === 0) return null;

          const comparisonCount = completedSubcategories.reduce(
            (count, subcategory) => count + subcategory.leaves.length,
            0,
          );

          return (
            <details
              className="benchmarkCategory"
              id={`category-${category.id}`}
              key={category.id}
              open={categoryIndex === 0}
            >
              <summary>
                <span className="benchmarkCategoryTitle" role="heading" aria-level={3}>
                  {category.name}
                </span>
                <span>{comparisonCount} {comparisonCount === 1 ? "comparison" : "comparisons"}</span>
              </summary>
              <div className="chartGrid">
                {completedSubcategories.flatMap((subcategory) =>
                  subcategory.leaves.map((leaf) => (
                    <Chart
                      benchmark={benchmarkFromLeaf(subcategory.name, leaf)}
                      id={`current-${category.id}-${subcategory.id}-${leaf.id}`}
                      key={leaf.id}
                    />
                  )),
                )}
              </div>
            </details>
          );
        })}

        <div className="benchmarkRunStatus" aria-label="Current benchmark run status">
          <span>{benchmarkData.summary.runLeafCount} of {benchmarkData.summary.leafCount} leaves run</span>
          <span>Range passed {benchmarkData.summary.rangePassed}</span>
          <span>Not emitted {benchmarkData.summary.rangeNotEmitted}</span>
          <span>Failed {benchmarkData.summary.rangeFailed}</span>
        </div>
      </section>

      <section className="benchmarkSection" aria-labelledby="baseline-title">
        <div className="sectionHeader">
          <h2 id="baseline-title">Initial benchmark</h2>
          <p className="dateLabel">July 18, 2026</p>
        </div>

        <div className="chartGrid">
          {baselineBenchmarks.map((benchmark) => (
            <Chart
              benchmark={benchmark}
              id={`baseline-${benchmark.name.toLowerCase().replaceAll(" ", "-")}`}
              key={benchmark.name}
            />
          ))}
        </div>
      </section>

      <section className="status" aria-labelledby="range-status-title">
        <div className="statusHeader">
          <p className="statusLabel">Compiler status</p>
          <h2 id="range-status-title">4 of 6 tests emitted and passed</h2>
        </div>
        <ul className="statusList" aria-label="Tests not emitted in this pass">
          <li>
            <XIcon className="statusIcon" size={18} aria-hidden="true" />
            <span><strong>Collections</strong> · resolution stage 2</span>
          </li>
          <li>
            <XIcon className="statusIcon" size={18} aria-hidden="true" />
            <span><strong>Constructs</strong> · constructor-argument parse reachability</span>
          </li>
        </ul>
      </section>

      <section className="contextSection" aria-labelledby="lowering-title">
        <div className="sectionHeader">
          <h2 id="lowering-title">String lowering</h2>
          <p className="dateLabel">July 18, 2026 · 7:29 PM</p>
        </div>
        <figure className="contextFigure">
          <div className="contextImageCrop">
            <img
              src="/string-lowering-conversation.png"
              alt="User message about processing strings together followed by the complete Codex response explaining Range String lowering"
            />
          </div>
          <figcaption>
            Owned String storage carries length, capacity, and data forward so unique growth can
            extend the same allocation.
          </figcaption>
        </figure>
      </section>

      <section className="improvementSection" aria-labelledby="improved-title">
        <div className="sectionHeader">
          <h2 id="improved-title">Range Strings improvement</h2>
          <p className="dateLabel">July 18, 2026</p>
        </div>
        <RangeImprovementChart />
        <div className="improvedStringComparison">
          <Chart benchmark={improvedStringsBenchmark} id="improved-strings" />
        </div>
      </section>

      <section className="scalingSection" aria-labelledby="scaling-title">
        <div className="sectionHeader">
          <h2 id="scaling-title">String scaling</h2>
          <p className="dateLabel">July 18, 2026</p>
        </div>
        <div className="chartGrid">
          {stringScalingBenchmarks.map((benchmark) => (
            <Chart
              benchmark={benchmark}
              id={`scaling-${benchmark.name.toLowerCase().replaceAll(" ", "-")}`}
              key={benchmark.name}
            />
          ))}
        </div>
      </section>

      <footer>
        <a
          className="githubButton"
          href="https://github.com/georgetchelidze/Range/tree/development"
          target="_blank"
          rel="noreferrer"
          aria-label="Open the Range development branch on GitHub"
        >
          <MarkGithubIcon size={19} aria-hidden="true" />
          <span>GitHub</span>
        </a>
        <div className="footerMeta">
          <span>Range · native LLVM · O3</span>
          <span>July 2026</span>
        </div>
      </footer>
    </main>
  );
}
