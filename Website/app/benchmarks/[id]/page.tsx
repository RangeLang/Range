import { notFound } from "next/navigation";
import Link from "next/link";
import { Benchmark, BenchmarkImplementation, Chart, CodeBlock } from "../../components/BenchmarkChart";
import benchmarkDataJson from "../../../public/benchmarks.json";

type Measurement = {
  language: string;
  wallMilliseconds: number;
  cpuMilliseconds: number;
  peakRssKilobytes: number;
  relativeToFastest: number;
  output: string;
};

type Leaf = {
  id: string;
  name: string;
  description: string;
  workload: { count: number; unit: string };
  rangeStatus: string;
  axisMaxMilliseconds: number;
  implementations: BenchmarkImplementation[];
  results: Measurement[];
};

type BenchmarkArtifact = {
  configuration: { runs: number };
  procedure: {
    steps: string[];
    commands: { c: string[]; range: string[]; suite: string[] };
    notes: string[];
  };
  categories: Array<{
    name: string;
    subcategories: Array<{ name: string; leaves: Leaf[] }>;
  }>;
};

const benchmarkData = benchmarkDataJson as BenchmarkArtifact;

function benchmarkRecords() {
  return benchmarkData.categories.flatMap((category) =>
    category.subcategories.flatMap((subcategory) =>
      subcategory.leaves.map((leaf) => ({ category, subcategory, leaf })),
    ),
  );
}

function formatWorkload(count: number): string {
  if (count >= 1_000_000) return `${count / 1_000_000}m`;
  if (count >= 1_000) return `${count / 1_000}k`;
  return count.toString();
}

function formatMemory(kilobytes: number): string {
  return kilobytes >= 1024
    ? `${(kilobytes / 1024).toFixed(1)} MB`
    : `${kilobytes} KB`;
}

export function generateStaticParams() {
  return benchmarkRecords().map(({ leaf }) => ({ id: leaf.id }));
}

export default async function BenchmarkPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const record = benchmarkRecords().find(({ leaf }) => leaf.id === id);
  if (!record) notFound();

  const { category, subcategory, leaf } = record;
  const benchmark: Benchmark = {
    name: subcategory.name,
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

  return (
    <main>
      <header className="benchmarkDetailHeader">
        <Link className="backLink" href="/benchmarks">Benchmarks</Link>
        <div>
          <p>{category.name}</p>
          <h1>{subcategory.name} · {leaf.name}</h1>
          <span>{leaf.description}</span>
        </div>
      </header>

      <section className="benchmarkDetailChart" aria-label="Benchmark comparison">
        <Chart benchmark={benchmark} id={`benchmark-${leaf.id}`} />
      </section>

      <section className="measurementsSection" aria-labelledby="measurements-title">
        <div className="sectionHeader">
          <h2 id="measurements-title">Measurements</h2>
          <p className="dateLabel">Range {leaf.rangeStatus}</p>
        </div>
        <div className="measurementTableWrap">
          <table className="measurementTable">
            <thead>
              <tr>
                <th>Language</th>
                <th>Wall</th>
                <th>CPU</th>
                <th>Peak memory</th>
                <th>Relative</th>
                <th>Output</th>
              </tr>
            </thead>
            <tbody>
              {leaf.results.map((result) => (
                <tr key={result.language}>
                  <th>{result.language}</th>
                  <td>{result.wallMilliseconds.toFixed(1)} ms</td>
                  <td>{result.cpuMilliseconds.toFixed(1)} ms</td>
                  <td>{formatMemory(result.peakRssKilobytes)}</td>
                  <td>{result.relativeToFastest.toFixed(2)}×</td>
                  <td>{result.output}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <section className="benchmarkProcedureSection" aria-labelledby="procedure-title">
        <div className="sectionHeader">
          <h2 id="procedure-title">Run procedure</h2>
        </div>
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
      </section>
    </main>
  );
}
