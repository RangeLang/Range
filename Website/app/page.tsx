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

function Chart({ benchmark, id }: { benchmark: Benchmark; id: string }) {
  const midpoint = benchmark.axisMax / 2;
  const fastestTime = Math.min(...benchmark.results.map((result) => result.milliseconds));

  return (
    <section className="chart" aria-labelledby={`${id}-title`}>
      <header className="chartHeader">
        <h2 id={`${id}-title`}>{benchmark.name}</h2>
        <span>{benchmark.scale}</span>
      </header>

      <div className="rows">
        {benchmark.results.map((result) => {
          const isRange = result.language === "Range";
          const ratioToFastest = result.milliseconds / fastestTime;
          const isFastest = Math.abs(result.milliseconds - fastestTime) < 0.0001;
          const width = `${(result.milliseconds / benchmark.axisMax) * 100}%`;
          const scaleDeviation = (result.milliseconds - fastestTime) / benchmark.axisMax;
          const redThreshold = 0.3;
          const relativeOrange = Math.min(
            100,
            Math.max(
              0,
              (Math.log1p(scaleDeviation * 8) / Math.log1p(redThreshold * 8)) * 100,
            ),
          );
          const orangeMix = isFastest ? 0 : Math.min(100, 28 + relativeOrange * 0.72);
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
          const barColor = scaleDeviation <= redThreshold
            ? `color-mix(in oklch, var(--fastest-bar), var(--warning-bar) ${orangeMix.toFixed(1)}%)`
            : `color-mix(in oklch, var(--warning-bar), var(--slow-bar) ${redMix.toFixed(1)}%)`;
          const barFill = `linear-gradient(90deg, color-mix(in oklch, ${barColor}, var(--paper) 8%), ${barColor})`;

          return (
            <div
              className={`row${isRange ? " range" : ""}${isFastest ? " fastest" : ""}`}
              key={result.language}
            >
              <span className="language">{result.language}</span>
              <span className="track" aria-hidden="true">
                <span className="bar" style={{ width, background: barFill }} />
              </span>
              <span className="value">
                <span>{result.milliseconds.toFixed(1)} ms</span>
                {isFastest && <small>absolute best</small>}
                {isRange && !isFastest && <small>{ratioToFastest.toFixed(2)}× best</small>}
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

function RangeImprovementChart() {
  return (
    <section className="improvementChart" aria-labelledby="range-improvement-chart-title">
      <header className="improvementHeader">
        <div className="improvementTitle">
          <h2 id="range-improvement-chart-title">100k appends · Range</h2>
          <div className="improvementSummary">
            <span>144× faster</span>
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
            Median wall time falls from 491.2 milliseconds to 3.4 milliseconds, while peak memory
            falls from 5.3 gigabytes to 1.9 megabytes.
          </desc>

          <g className="bezierGrid">
            <line x1="55" y1="70" x2="930" y2="70" />
            <line x1="55" y1="180" x2="930" y2="180" />
            <line x1="55" y1="290" x2="930" y2="290" />
          </g>
          <g className="bezierAxis">
            <text x="43" y="75" textAnchor="end">500</text>
            <text x="43" y="185" textAnchor="end">250</text>
            <text x="43" y="295" textAnchor="end">0</text>
            <text x="14" y="180" textAnchor="middle" transform="rotate(-90 14 180)">milliseconds</text>
          </g>

          <path className="bezierLine" d="M 90 72 C 285 72, 430 290, 900 290" />
          <circle className="bezierPoint" cx="90" cy="72" r="6" />
          <circle className="bezierPoint" cx="900" cy="290" r="6" />

          <g className="pointMetrics">
            <text className="pointTime" x="90" y="48" textAnchor="middle">491.2 ms</text>
            <text className="pointMemory" x="90" y="102" textAnchor="middle">5.3 GB</text>
            <text className="pointTime" x="900" y="266" textAnchor="middle">3.4 ms</text>
            <text className="pointMemory" x="900" y="320" textAnchor="middle">1.9 MB</text>
          </g>

          <g className="bezierLabels">
            <text x="90" y="364" textAnchor="middle">Before</text>
            <text x="900" y="364" textAnchor="middle">Self-hosted</text>
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
          <div className="contextImageCrop">
            <img
              src="/string-lowering-response.png"
              alt="Complete Codex response explaining Range String lowering with owned length, capacity, and data storage"
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
      </section>

      <footer>
        <span>Range · native LLVM · O3</span>
        <span>July 2026</span>
      </footer>
    </main>
  );
}
