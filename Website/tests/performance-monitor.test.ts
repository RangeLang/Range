import { describe, expect, test } from "bun:test";
import {
  parseCompilerProfileSummary,
  parseProcessRows,
  processFamily,
  sampleProcesses,
} from "../src/lib/performance-monitor";

const processListing = `
  100     1   0.0   1024 /bin/bash
  101   100  82.5 204800 /tmp/RangeCompilerProfiled
  102   101  12.5  32768 /usr/bin/clang
  200     1  30.0 512000 /Applications/Browser
  201     1   2.0 128000 /Applications/Editor
`;

describe("performance monitor measurements", () => {
  test("aggregates the complete profiler process family", () => {
    const rows = parseProcessRows(processListing);
    expect([...processFamily(rows, 100)]).toEqual([100, 101, 102]);

    const sample = sampleProcesses(rows, 100, 750);
    expect(sample.rangeCpuPercent).toBe(95);
    expect(sample.rangeResidentBytes).toBe((1024 + 204800 + 32768) * 1024);
    expect(sample.peers[0]).toEqual({
      name: "Browser",
      cpuPercent: 30,
      residentBytes: 512000 * 1024,
    });
  });

  test("parses the profiler's stable summary records", () => {
    expect(parseCompilerProfileSummary([
      "compilerProfile\tstatus=0\tllvmBytes=8536874\tfunctionCount=912",
      "compilerResources\tmaximumResidentBytes=250000000\tpeakFootprintBytes=310000000",
    ].join("\n"))).toEqual({
      status: 0,
      llvmBytes: 8536874,
      functionCount: 912,
      maximumResidentBytes: 250000000,
      peakFootprintBytes: 310000000,
    });
  });
});
