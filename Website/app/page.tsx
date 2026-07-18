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
          const grayMix = Math.min(100, Math.max(0, ((ratioToFastest - 1) / 0.25) * 100));
          const redMix = ratioToFastest <= 1.25
            ? 0
            : Math.min(
                100,
                Math.max(
                  0,
                  ((Math.log10(ratioToFastest) - Math.log10(1.25)) /
                    (Math.log10(8) - Math.log10(1.25))) *
                    100,
                ),
              );
          const barColor = ratioToFastest <= 1.25
            ? `color-mix(in oklch, var(--fastest-bar), var(--comparison-bar) ${grayMix.toFixed(1)}%)`
            : `color-mix(in oklch, var(--comparison-bar), var(--slow-bar) ${redMix.toFixed(1)}%)`;
          const barFill = `linear-gradient(90deg, color-mix(in oklch, ${barColor}, var(--paper) 28%), ${barColor})`;

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
                {isFastest && <small>fastest</small>}
                {isRange && !isFastest && <small>{ratioToFastest.toFixed(2)}× fastest</small>}
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
          <h2 id="range-improvement-chart-title">Strings</h2>
          <span>100k appends · Range</span>
        </div>
        <div className="improvementCallout" aria-hidden="true">
          <div className="improvementSummary">
            <p>144× faster</p>
            <p>~2,800× less peak memory</p>
          </div>
          <div className="changeLabels">
            <span>491.2 → 3.4 ms</span>
            <span>5.3 GB → 1.9 MB</span>
          </div>
        </div>
      </header>

      <div className="improvementPlot">
        <svg
          className="bezierChart"
          viewBox="0 0 960 350"
          role="img"
          aria-labelledby="range-improvement-svg-title range-improvement-svg-description"
        >
          <title id="range-improvement-svg-title">Range String performance before and after lowering</title>
          <desc id="range-improvement-svg-description">
            Median wall time falls from 491.2 milliseconds to 3.4 milliseconds, while peak memory
            falls from 5.3 gigabytes to 1.9 megabytes.
          </desc>

          <g className="bezierGrid">
            <line x1="55" y1="24" x2="930" y2="24" />
            <line x1="55" y1="154" x2="930" y2="154" />
            <line x1="55" y1="284" x2="930" y2="284" />
          </g>
          <g className="bezierAxis">
            <text x="43" y="29" textAnchor="end">500</text>
            <text x="43" y="159" textAnchor="end">250</text>
            <text x="43" y="289" textAnchor="end">0</text>
            <text x="14" y="154" textAnchor="middle" transform="rotate(-90 14 154)">milliseconds</text>
          </g>

          <path className="bezierLine" d="M 90 29 C 285 29, 430 284, 900 284" />
          <circle className="bezierPoint" cx="90" cy="29" r="6" />
          <circle className="bezierPoint" cx="900" cy="284" r="6" />

          <g className="bezierLabels">
            <text x="90" y="327" textAnchor="middle">Before</text>
            <text x="900" y="327" textAnchor="middle">Self-hosted</text>
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
              src="/string-lowering-context.png"
              alt="Range String lowering discussion showing owned length, capacity, and data storage"
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
