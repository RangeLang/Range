import { notFound } from "next/navigation";
import Link from "next/link";
import { Benchmark, Chart } from "../../components/BenchmarkChart";

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

export function generateStaticParams() {
  return [{ id: "string-lowering" }];
}

export default async function UpdatePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (id !== "string-lowering") notFound();

  return (
    <main>
      <header className="updatePageHeader">
        <Link href="/">Range</Link>
        <div>
          <h1>String lowering</h1>
          <p className="dateLabel">July 18, 2026</p>
        </div>
      </header>

      <section className="contextSection" aria-labelledby="lowering-sequence-title">
        <div className="sectionHeader">
          <h2 id="lowering-sequence-title">Sequence</h2>
          <p className="dateLabel">7:29 PM</p>
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
          <h2 id="improved-title">Improvement</h2>
          <p className="dateLabel">July 18, 2026</p>
        </div>
        <RangeImprovementChart />
        <div className="improvedStringComparison">
          <Chart benchmark={improvedStringsBenchmark} id="improved-strings" />
        </div>
      </section>

      <section className="scalingSection" aria-labelledby="scaling-title">
        <div className="sectionHeader">
          <h2 id="scaling-title">Scaling</h2>
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
    </main>
  );
}
