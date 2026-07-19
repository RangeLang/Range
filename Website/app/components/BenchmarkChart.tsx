import { codeToHtml } from "shiki";

export type BenchmarkImplementation = {
  language: string;
  syntax: string;
  filename: string;
  source: string;
};

export type Benchmark = {
  name: string;
  scale: string;
  axisMax: number;
  results: Array<{ language: string; milliseconds: number }>;
  note?: string;
  leaf?: string;
  description?: string;
  implementations?: BenchmarkImplementation[];
};

export async function CodeBlock({
  source,
  syntax,
  label,
}: {
  source: string;
  syntax: string;
  label: string;
}) {
  const language = syntax === "range" ? "swift" : syntax;
  const highlighted = await codeToHtml(source, {
    lang: language,
    theme: "github-light",
  });

  return (
    <section className="codeBlock" aria-label={label}>
      <header>{label}</header>
      <div className="codeBlockBody" dangerouslySetInnerHTML={{ __html: highlighted }} />
    </section>
  );
}

export function Chart({ benchmark, id }: { benchmark: Benchmark; id: string }) {
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
                  (Math.log(scaleDeviation / redThreshold) / Math.log(1 / redThreshold)) * 100,
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

      {benchmark.implementations && (
        <details className="testCode">
          <summary>Test code</summary>
          <div className="testCodeGrid">
            {benchmark.implementations.map((implementation) => (
              <CodeBlock
                source={implementation.source}
                syntax={implementation.syntax}
                label={`${implementation.language} · ${implementation.filename}`}
                key={implementation.language}
              />
            ))}
          </div>
        </details>
      )}
    </section>
  );
}
