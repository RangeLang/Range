import {
  stringScalingBenchmarks,
  type Benchmark,
} from "$lib/benchmarks";

export type PerformanceScale = {
  count: number;
  label: string;
};

export type PerformanceSlice = {
  operationCount: number;
  benchmark: Benchmark;
};

export type PerformanceObservation = {
  id: string;
  observedAt: string;
  label: string;
  note: string;
  slices: PerformanceSlice[];
};

function scalingBenchmark(label: string): Benchmark | undefined {
  return stringScalingBenchmarks.find((benchmark) => benchmark.name === label);
}

export const performanceScales: PerformanceScale[] = [
  { count: 100_000, label: "100k" },
  { count: 1_000_000, label: "1m" },
  { count: 5_000_000, label: "5m" },
  { count: 10_000_000, label: "10m" },
];

function requireBenchmark(
  benchmark: Benchmark | undefined,
  label: string,
): Benchmark {
  if (!benchmark) throw new Error(`Missing benchmark history sample: ${label}`);
  return benchmark;
}

export const performanceObservations: PerformanceObservation[] = [
  {
    id: "2026-07-18-string-scaling",
    observedAt: "2026-07-18",
    label: "String append scaling",
    note: "Thirty-run native LLVM O3 scaling snapshot.",
    slices: [
      ["100k", 100_000],
      ["1m", 1_000_000],
      ["5m", 5_000_000],
      ["10m", 10_000_000],
    ].map(([label, operationCount]): PerformanceSlice => ({
      operationCount: Number(operationCount),
      benchmark: requireBenchmark(
        scalingBenchmark(`${label} appends`),
        `observed scaling slice ${label}`,
      ),
    })),
  },
];
