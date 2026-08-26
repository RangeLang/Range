export type ProcessReading = {
  name: string;
  cpuPercent: number;
  residentBytes: number;
};

export type PerformanceSample = {
  elapsedMilliseconds: number;
  rangeCpuPercent: number;
  rangeResidentBytes: number;
  peers: ProcessReading[];
};

export type CompilerProfileSummary = {
  status: number | null;
  llvmBytes: number | null;
  functionCount: number | null;
  maximumResidentBytes: number | null;
  peakFootprintBytes: number | null;
};

export type MonitorEvent =
  | { type: "started"; startedAt: string; sampleIntervalMilliseconds: number }
  | ({ type: "sample" } & PerformanceSample)
  | ({ type: "finished"; durationMilliseconds: number } & CompilerProfileSummary)
  | { type: "error"; message: string };

export type ProcessRow = ProcessReading & {
  pid: number;
  parentPid: number;
};

export function parseProcessRows(output: string): ProcessRow[] {
  return output
    .split("\n")
    .map((line) => line.trim().match(/^(\d+)\s+(\d+)\s+([\d.]+)\s+(\d+)\s+(.+)$/))
    .filter((match): match is RegExpMatchArray => match !== null)
    .map((match) => ({
      pid: Number(match[1]),
      parentPid: Number(match[2]),
      cpuPercent: Number(match[3]),
      residentBytes: Number(match[4]) * 1024,
      name: match[5]!.split("/").at(-1) ?? match[5]!,
    }));
}

export function processFamily(rows: ProcessRow[], rootPid: number): Set<number> {
  const family = new Set([rootPid]);
  let changed = true;
  while (changed) {
    changed = false;
    for (const row of rows) {
      if (family.has(row.parentPid) && !family.has(row.pid)) {
        family.add(row.pid);
        changed = true;
      }
    }
  }
  return family;
}

export function sampleProcesses(
  rows: ProcessRow[],
  rootPid: number,
  elapsedMilliseconds: number,
): PerformanceSample {
  const family = processFamily(rows, rootPid);
  const rangeRows = rows.filter((row) => family.has(row.pid));
  const peers = rows
    .filter((row) => !family.has(row.pid) && row.pid !== process.pid)
    .sort((left, right) => right.residentBytes - left.residentBytes)
    .slice(0, 3)
    .map(({ name, cpuPercent, residentBytes }) => ({
      name,
      cpuPercent,
      residentBytes,
    }));

  return {
    elapsedMilliseconds,
    rangeCpuPercent: rangeRows.reduce((sum, row) => sum + row.cpuPercent, 0),
    rangeResidentBytes: rangeRows.reduce((sum, row) => sum + row.residentBytes, 0),
    peers,
  };
}

function numericField(line: string, name: string): number | null {
  const match = line.match(new RegExp(`(?:^|\\t)${name}=(\\d+)`));
  return match ? Number(match[1]) : null;
}

export function parseCompilerProfileSummary(output: string): CompilerProfileSummary {
  const profile = output.split("\n").find((line) => line.startsWith("compilerProfile\t")) ?? "";
  const resources = output.split("\n").find((line) => line.startsWith("compilerResources\t")) ?? "";
  return {
    status: numericField(profile, "status"),
    llvmBytes: numericField(profile, "llvmBytes"),
    functionCount: numericField(profile, "functionCount"),
    maximumResidentBytes: numericField(resources, "maximumResidentBytes"),
    peakFootprintBytes: numericField(resources, "peakFootprintBytes"),
  };
}
