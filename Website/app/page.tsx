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
};

const benchmarks: Benchmark[] = [
  {
    name: "Loops",
    scale: "20m iterations",
    axisMax: 140,
    results: [
      { language: "C", milliseconds: 65.4 },
      { language: "Swift", milliseconds: 72.5 },
      { language: "C++", milliseconds: 83.9 },
      { language: "Range", milliseconds: 106.8 },
      { language: "Rust", milliseconds: 109.4 },
      { language: "Go", milliseconds: 133.0 },
    ],
  },
  {
    name: "Noise",
    scale: "50m samples",
    axisMax: 140,
    results: [
      { language: "C++", milliseconds: 70.8 },
      { language: "Rust", milliseconds: 81.8 },
      { language: "Swift", milliseconds: 82.1 },
      { language: "Range", milliseconds: 82.1 },
      { language: "C", milliseconds: 98.0 },
      { language: "Go", milliseconds: 128.8 },
    ],
  },
  {
    name: "Function Calls",
    scale: "20m iterations",
    axisMax: 80,
    results: [
      { language: "Go", milliseconds: 64.5 },
      { language: "Swift", milliseconds: 66.2 },
      { language: "C", milliseconds: 69.0 },
      { language: "C++", milliseconds: 69.6 },
      { language: "Rust", milliseconds: 71.0 },
      { language: "Range", milliseconds: 71.5 },
    ],
  },
  {
    name: "Strings",
    scale: "100k appends",
    axisMax: 550,
    results: [
      { language: "C", milliseconds: 5.9 },
      { language: "C++", milliseconds: 6.1 },
      { language: "Go", milliseconds: 6.2 },
      { language: "Rust", milliseconds: 6.4 },
      { language: "Swift", milliseconds: 7.1 },
      { language: "Range", milliseconds: 523.1 },
    ],
    note: "Range peak memory: 5.3 GB · peers: 1.8–4.2 MB",
  },
];

function Chart({ benchmark }: { benchmark: Benchmark }) {
  const midpoint = benchmark.axisMax / 2;

  return (
    <section className="chart" aria-labelledby={`${benchmark.name}-title`}>
      <header className="chartHeader">
        <h2 id={`${benchmark.name}-title`}>{benchmark.name}</h2>
        <span>{benchmark.scale}</span>
      </header>

      <div className="rows">
        {benchmark.results.map((result) => {
          const isRange = result.language === "Range";
          const width = `${(result.milliseconds / benchmark.axisMax) * 100}%`;

          return (
            <div className={`row${isRange ? " range" : ""}`} key={result.language}>
              <span className="language">{result.language}</span>
              <span className="track" aria-hidden="true">
                <span className="bar" style={{ width }} />
              </span>
              <span className="value">{result.milliseconds.toFixed(1)} ms</span>
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

export default function Home() {
  return (
    <main>
      <header className="pageHeader">
        <h1>Range Performance</h1>
      </header>

      <div className="chartGrid">
        {benchmarks.map((benchmark) => (
          <Chart benchmark={benchmark} key={benchmark.name} />
        ))}
      </div>

      <section className="status" aria-labelledby="range-status-title">
        <div>
          <p className="statusLabel">Compiler status</p>
          <h2 id="range-status-title">4 of 6 tests emitted and passed</h2>
        </div>
        <dl className="statusList">
          <div>
            <dt>Not emitted</dt>
            <dd>Collections · resolution stage 2</dd>
          </div>
          <div>
            <dt>Not emitted</dt>
            <dd>Constructs · constructor-argument parse reachability</dd>
          </div>
          <div>
            <dt>Emitted but failed</dt>
            <dd>None</dd>
          </div>
        </dl>
      </section>

      <footer>
        <span>Range · native LLVM · O3</span>
        <span>July 2026</span>
      </footer>
    </main>
  );
}
