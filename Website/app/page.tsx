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

const improvedStringBenchmark: Benchmark = {
  name: "Strings",
  scale: "100k appends",
  axisMax: 6,
  results: [
    { language: "C++", milliseconds: 3.2 },
    { language: "C", milliseconds: 3.4 },
    { language: "Range", milliseconds: 3.4 },
    { language: "Rust", milliseconds: 4.1 },
    { language: "Go", milliseconds: 4.1 },
    { language: "Swift", milliseconds: 5.2 },
  ],
  note: "Range peak memory: 1.9 MB · peers: 1.8–4.1 MB",
};

function Chart({ benchmark, id }: { benchmark: Benchmark; id: string }) {
  const midpoint = benchmark.axisMax / 2;

  return (
    <section className="chart" aria-labelledby={`${id}-title`}>
      <header className="chartHeader">
        <h2 id={`${id}-title`}>{benchmark.name}</h2>
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
        <a href="https://github.com/georgetchelidze/Range">GitHub</a>
      </header>

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

      <section className="contextSection" aria-labelledby="lowering-title">
        <div className="sectionHeader">
          <h2 id="lowering-title">String lowering</h2>
          <p className="dateLabel">July 18, 2026 · 7:29 PM</p>
        </div>
        <figure className="contextFigure">
          <img
            src="/string-lowering-context.png"
            alt="Range String lowering discussion showing owned length, capacity, and data storage"
          />
          <figcaption>
            Owned String storage carries length, capacity, and data forward so unique growth can
            extend the same allocation.
          </figcaption>
        </figure>
      </section>

      <section className="improvementSection" aria-labelledby="improved-title">
        <div className="sectionHeader">
          <h2 id="improved-title">Improved self-hosted result</h2>
          <p className="dateLabel">July 18, 2026</p>
        </div>
        <div className="improvedChart">
          <Chart benchmark={improvedStringBenchmark} id="improved-strings" />
        </div>
      </section>

      <footer>
        <span>Range · native LLVM · O3</span>
        <span>July 2026</span>
      </footer>
    </main>
  );
}
