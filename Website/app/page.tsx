import { MarkGithubIcon, XIcon } from "@primer/octicons-react";
import { Benchmark, BenchmarkImplementation, Chart, CodeBlock } from "./components/BenchmarkChart";
import benchmarkDataJson from "../public/benchmarks.json";

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
  implementations: BenchmarkImplementation[];
  results: BenchmarkMeasurement[];
};

type BenchmarkArtifact = {
  schemaVersion: number;
  generatedAt: string;
  configuration: { baseIterations: number; runs: number; caseFilter: string[] };
  procedure: {
    steps: string[];
    commands: { c: string[]; range: string[]; suite: string[] };
    notes: string[];
  };
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
    implementations: leaf.implementations,
    results: leaf.results.map((result) => ({
      language: result.language,
      milliseconds: result.wallMilliseconds,
    })),
  };
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

        <details className="runProcedure">
          <summary>Run procedure</summary>
          <div className="runProcedureBody">
            <ol>
              {benchmarkData.procedure.steps.map((step) => <li key={step}>{step}</li>)}
            </ol>
            <div className="runCommands">
              <CodeBlock
                source={`${benchmarkData.procedure.commands.suite.join("\n")}\n`}
                syntax="shellscript"
                label="Suite"
              />
              <CodeBlock
                source={`${benchmarkData.procedure.commands.c.join("\n")}\n`}
                syntax="shellscript"
                label="C"
              />
              <CodeBlock
                source={`${benchmarkData.procedure.commands.range.join("\n")}\n`}
                syntax="shellscript"
                label="Range"
              />
            </div>
            <ul className="runNotes">
              {benchmarkData.procedure.notes.map((note) => <li key={note}>{note}</li>)}
            </ul>
          </div>
        </details>

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

      <section className="updatesSection" aria-labelledby="updates-title">
        <div className="sectionHeader">
          <h2 id="updates-title">Updates</h2>
        </div>
        <a className="updateLink" href="/updates/string-lowering">
          <span>
            <strong>String lowering</strong>
            <small>100k appends · 491.2 ms → 4.1 ms</small>
          </span>
          <time dateTime="2026-07-18">July 18, 2026</time>
        </a>
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
