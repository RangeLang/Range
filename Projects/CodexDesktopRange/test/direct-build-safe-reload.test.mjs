import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const source = await readFile(new URL("../direct-edit.mjs", import.meta.url), "utf8");

test("direct builds wait for a graceful app shutdown before replacing the bundle", () => {
  assert.match(source, /tell application id "\$\{bundleId\}" to quit/);
  assert.match(source, /mainExecutablePrefix = `\^\$\{escaped\}\/Contents\/MacOS\/`/);
  assert.match(source, /while \(isRunning\(\) && Date\.now\(\) < deadline\)/);
  assert.match(source, /left untouched to protect its local databases/);
  assert.doesNotMatch(source, /execFileSync\("pkill"/);
});
