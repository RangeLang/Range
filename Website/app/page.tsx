/* eslint-disable @next/next/no-html-link-for-pages -- benchmark links use document navigation for the shared Range transition */
import { MarkGithubIcon } from "@primer/octicons-react";
import Link from "next/link";
import type { CSSProperties } from "react";
import benchmarkDataJson from "../public/benchmarks.json";

type BenchmarkSummary = {
  summary: {
    runLeafCount: number;
  };
};

const benchmarkData = benchmarkDataJson as BenchmarkSummary;

const logarithmicDashPositions = Array.from({ length: 18 }, (_, index) => {
  const step = index / 17;
  const logarithmicPosition = Math.log1p(9 * step) / Math.log(10);
  const position = 4 + logarithmicPosition * 92;
  const offset = Math.pow(logarithmicPosition, 3) * 100;
  const rotation = 90 - 23 * Math.pow(logarithmicPosition, 2);

  return { index, position, offset, rotation };
});

export default function Home() {
  return (
    <main className="landingPage">
      <div className="landingSequence">
        <header className="landingNav">
          <Link className="landingWordmark" href="/">
            <span className="landingIndex">0</span>
            <span>Range</span>
          </Link>
          <nav aria-label="Primary navigation">
            <a href="/benchmarks">Benchmarks</a>
            <Link href="/updates/string-lowering">Updates</Link>
            <a
              href="https://github.com/georgetchelidze/Range/tree/development"
              target="_blank"
              rel="noreferrer"
            >
              GitHub
            </a>
          </nav>
        </header>

        <div className="landingLogLine" aria-hidden="true">
          {logarithmicDashPositions.map(({ index, position, offset, rotation }) => (
            <span
              className="landingLogDash"
              key={index}
              style={{
                "--dash-position": `${position}%`,
                "--dash-offset": `${offset}%`,
                "--dash-rotation": `${rotation}deg`,
              } as CSSProperties}
            />
          ))}
        </div>

        <section className="landingHero" aria-labelledby="range-title">
          <h1 id="range-title">
            <span className="landingIndex">1</span>
            <span>Range</span>
          </h1>
          <p>The active compiler is Range-authored and emits native LLVM.</p>
          <div className="landingActions">
            <a className="primaryAction" href="/benchmarks">Benchmarks</a>
            <a
              className="secondaryAction"
              href="https://github.com/georgetchelidze/Range/tree/development"
              target="_blank"
              rel="noreferrer"
            >
              <MarkGithubIcon size={18} aria-hidden="true" />
              GitHub
            </a>
          </div>
        </section>
      </div>

      <section className="landingLinks" aria-label="Range links">
        <a href="/benchmarks">
          <span>
            <strong>Benchmarks</strong>
            <small>{benchmarkData.summary.runLeafCount} generated comparisons</small>
          </span>
          <span>View</span>
        </a>
        <Link href="/updates/string-lowering">
          <span>
            <strong>String lowering</strong>
            <small>100k appends · 491.2 ms → 4.1 ms</small>
          </span>
          <span>View</span>
        </Link>
      </section>
    </main>
  );
}
