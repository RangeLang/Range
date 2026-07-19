/* eslint-disable @next/next/no-html-link-for-pages -- benchmark links use document navigation for the shared Range transition */
import { MarkGithubIcon } from "@primer/octicons-react";
import Link from "next/link";
import benchmarkDataJson from "../public/benchmarks.json";

type BenchmarkSummary = {
  summary: {
    runLeafCount: number;
  };
};

const benchmarkData = benchmarkDataJson as BenchmarkSummary;

export default function Home() {
  return (
    <main className="landingPage">
      <div className="landingSequence">
        <header className="landingNav">
          <Link className="landingWordmark" href="/">
            <span className="landingIndex" data-scale-zero>0</span>
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

        <range-scale
          aria-hidden="true"
          endpoint-gap="8"
          division-base="3"
          division-levels="3"
          pinch="0.27"
          pinch-falloff="0.16"
          pinch-strength="0.9"
          measure-minimum="0.35"
          stroke-minimum="0.25"
          tone-falloff="0.12"
          tone-intensity="0.82"
        />
        {/* ES modules are deferred by the browser; this loads the native custom element without a React client boundary. */}
        {/* eslint-disable-next-line @next/next/no-sync-scripts */}
        <script type="module" src="/range-scale.js" />

        <section className="landingHero" aria-labelledby="range-title">
          <h1 id="range-title">
            <span className="landingIndex" data-scale-end><span>1</span></span>
            <span className="rangeTitleWord">Range</span>
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
