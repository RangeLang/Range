import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { basename, resolve } from "node:path";

const websiteRoot = resolve(import.meta.dir, "..");
const repositoryRoot = resolve(websiteRoot, "..");
const snapshotRoot = resolve(
  websiteRoot,
  "src/lib/content/source-snapshots",
);
const manifestPath = resolve(snapshotRoot, "manifest.json");

const sources = [
  "Projects/RangeCompilerB/Sources/CompilerB/Core/Macros/Many.range",
  "RangeCompiler/Sources/Compiler/Driver/Main.range",
  "RangeCompiler/Sources/Core/Macro/Codable.range",
  "RangeCompiler/Sources/Core/Macro/CommandGroup.range",
  "Testing/CommandLine/Pass/Routes.range",
] as const;

const sourceCommit = Bun.spawnSync({
  cmd: ["git", "rev-parse", "HEAD"],
  cwd: repositoryRoot,
});

if (sourceCommit.exitCode !== 0) {
  throw new Error(sourceCommit.stderr.toString().trim());
}

await mkdir(snapshotRoot, { recursive: true });

const files = [];
for (const source of sources) {
  const content = await readFile(resolve(repositoryRoot, source));
  const snapshot = basename(source);
  await writeFile(resolve(snapshotRoot, snapshot), content);
  files.push({
    source,
    snapshot,
    sha256: createHash("sha256").update(content).digest("hex"),
  });
}

await writeFile(
  manifestPath,
  `${JSON.stringify(
    {
      sourceCommit: sourceCommit.stdout.toString().trim(),
      files,
    },
    null,
    2,
  )}\n`,
);

console.log(`Wrote ${files.length} source snapshots from ${sourceCommit.stdout.toString().trim()}.`);
