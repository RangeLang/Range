import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import {
  cpSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  renameSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { homedir, tmpdir } from "node:os";
import { basename, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import {
  createPackageWithOptions,
  extractAll,
  getRawHeader,
} from "@electron/asar";
import { format } from "prettier";

const projectDir = dirname(fileURLToPath(import.meta.url));
const directDir = join(projectDir, "direct-renderer");
const editableAppDir = join(directDir, "app");
const manifestPath = join(directDir, "manifest.json");
const command = process.argv[2];

function fail(message) {
  throw new Error(message);
}

function unpackedRoots(node, currentPath = "", parentUnpacked = false) {
  const isUnpacked = node.unpacked === true;
  const roots = [];
  if (isUnpacked && !parentUnpacked) {
    roots.push({ path: currentPath, directory: node.files != null });
  }
  if (node.files != null) {
    for (const [name, child] of Object.entries(node.files)) {
      roots.push(
        ...unpackedRoots(
          child,
          currentPath === "" ? name : `${currentPath}/${name}`,
          isUnpacked,
        ),
      );
    }
  }
  return roots;
}

function unpackedFiles(node, currentPath = "") {
  if (node.files == null) return node.unpacked === true ? [currentPath] : [];
  return Object.entries(node.files).flatMap(([name, child]) =>
    unpackedFiles(child, currentPath === "" ? name : `${currentPath}/${name}`),
  );
}

function globAlternatives(paths) {
  return paths.length === 1 ? paths[0] : `{${paths.join(",")}}`;
}

function sha256(path) {
  return createHash("sha256").update(readFileSync(path)).digest("hex");
}

function readManifest() {
  if (!existsSync(manifestPath)) {
    fail("No direct renderer exists. Run `npm run direct:extract` first.");
  }
  return JSON.parse(readFileSync(manifestPath, "utf8"));
}

function findEditableFiles() {
  const assetsDir = join(editableAppDir, "webview", "assets");
  const matchers = [
    /^app-initial-.*\.(?:js|css)$/,
    /^local-conversation-page-.*\.js$/,
    /^thread-app-shell-chrome-.*\.js$/,
    /^review-file-tree-pane-.*\.js$/,
    /^home-composer-mode-toggle-.*\.js$/,
    /^composer-action-bar-run-location-dropdown-.*\.js$/,
    /^composer-utility-bar-.*\.js$/,
    /^text-file-editor-tab-content\.electron-.*\.js$/,
    /^shiki-highlight-provider-.*\.js$/,
  ];
  return readdirSync(assetsDir)
    .filter((name) => matchers.some((matcher) => matcher.test(name)))
    .sort()
    .map((name) => join("webview", "assets", name));
}

async function formatEditableFiles(files) {
  for (const relativePath of files) {
    const path = join(editableAppDir, relativePath);
    const parser = relativePath.endsWith(".css") ? "css" : "babel";
    const source = readFileSync(path, "utf8");
    const formatted = await format(source, {
      parser,
      printWidth: 100,
      semi: true,
      singleQuote: false,
    });
    writeFileSync(path, formatted);
    console.log(`Formatted ${relativePath}`);
  }
}

async function extract() {
  const sourceApp = process.argv[3] ?? "/Applications/ChatGPT Range.app";
  const asarPath = join(sourceApp, "Contents", "Resources", "app.asar");
  if (!existsSync(asarPath)) fail(`Source app ASAR does not exist: ${asarPath}`);
  if (existsSync(editableAppDir) || existsSync(manifestPath)) {
    fail(
      `Direct renderer already exists at ${directDir}. ` +
        "Move it aside before extracting a different baseline.",
    );
  }

  mkdirSync(directDir, { recursive: true });
  console.log(`Extracting ${asarPath}...`);
  extractAll(asarPath, editableAppDir);

  const header = getRawHeader(asarPath).header;
  const editableFiles = findEditableFiles();
  await formatEditableFiles(editableFiles);
  const manifest = {
    schemaVersion: 1,
    sourceApp,
    sourceAsarSha256: sha256(asarPath),
    extractedAt: new Date().toISOString(),
    originalUnpackedFiles: unpackedFiles(header).sort(),
    originalUnpackedRoots: unpackedRoots(header),
    editableFiles,
  };
  writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
  console.log(`Editable renderer: ${editableAppDir}`);
  console.log(`Manifest: ${manifestPath}`);
}

function checkJavaScript(manifest) {
  for (const relativePath of manifest.editableFiles) {
    if (!relativePath.endsWith(".js")) continue;
    execFileSync(process.execPath, ["--check", join(editableAppDir, relativePath)], {
      stdio: "inherit",
    });
  }
}

function stopInstalledApp(targetApp) {
  const escaped = targetApp.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const mainExecutablePrefix = `^${escaped}/Contents/MacOS/`;
  const appName = basename(targetApp, ".app");
  const bundleId = execFileSync("/usr/libexec/PlistBuddy", [
    "-c",
    "Print :CFBundleIdentifier",
    join(targetApp, "Contents", "Info.plist"),
  ], { encoding: "utf8" }).trim();
  const isRunning = () => {
    try {
      execFileSync("pgrep", ["-f", mainExecutablePrefix], { stdio: "ignore" });
      return true;
    } catch (error) {
      if (error.status === 1) return false;
      throw error;
    }
  };

  if (!isRunning()) return;

  console.log(`Requesting a graceful quit from ${appName}...`);
  try {
    execFileSync("osascript", ["-e", `tell application id "${bundleId}" to quit`]);
  } catch (error) {
    fail(`Could not request a graceful quit from ${appName}: ${error.message}`);
  }

  const deadline = Date.now() + 30_000;
  while (isRunning() && Date.now() < deadline) {
    Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 100);
  }
  if (isRunning()) {
    fail(
      `${appName} did not finish quitting after 30 seconds. ` +
        "The existing app was left untouched to protect its local databases.",
    );
  }
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 500);
  console.log(`${appName} quit cleanly.`);
}

function trashBackupPath(targetApp) {
  const appName = basename(targetApp, ".app");
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  return join(homedir(), ".Trash", `${appName} before direct renderer ${stamp}.app`);
}

async function build() {
  const manifest = readManifest();
  const templateApp = process.argv[3] ?? manifest.sourceApp;
  const targetApp = process.argv[4] ?? "/Applications/ChatGPT Range.app";
  if (!existsSync(editableAppDir)) fail(`Editable renderer is missing: ${editableAppDir}`);
  if (!existsSync(templateApp)) fail(`Template app does not exist: ${templateApp}`);

  checkJavaScript(manifest);
  const tempRoot = mkdtempSync(join(tmpdir(), "codex-range-direct-build-"));
  const stagedApp = join(tempRoot, basename(targetApp));
  const packedAsar = join(tempRoot, "app.asar");

  try {
    console.log(`Copying app shell from ${templateApp}...`);
    execFileSync("/usr/bin/ditto", [templateApp, stagedApp]);

    const unpackDirectories = manifest.originalUnpackedRoots
      .filter((entry) => entry.directory)
      .map((entry) => entry.path);
    const unpackFiles = manifest.originalUnpackedRoots
      .filter((entry) => !entry.directory)
      .map((entry) => `**/${entry.path}`);
    await createPackageWithOptions(editableAppDir, packedAsar, {
      unpack: globAlternatives(unpackFiles),
      unpackDir: globAlternatives(unpackDirectories),
    });

    const repackedUnpackedFiles = unpackedFiles(getRawHeader(packedAsar).header).sort();
    if (
      JSON.stringify(repackedUnpackedFiles) !==
      JSON.stringify(manifest.originalUnpackedFiles)
    ) {
      fail("Direct renderer build changed the original ASAR unpack contract");
    }

    const resourcesDir = join(stagedApp, "Contents", "Resources");
    const stagedAsar = join(resourcesDir, "app.asar");
    cpSync(packedAsar, stagedAsar);
    rmSync(`${stagedAsar}.unpacked`, { recursive: true, force: true });
    cpSync(`${packedAsar}.unpacked`, `${stagedAsar}.unpacked`, { recursive: true });

    const { headerString } = getRawHeader(stagedAsar);
    const headerHash = createHash("sha256").update(headerString).digest("hex");
    const plistPath = join(stagedApp, "Contents", "Info.plist");
    execFileSync("/usr/libexec/PlistBuddy", [
      "-c",
      `Set :ElectronAsarIntegrity:Resources/app.asar:hash ${headerHash}`,
      plistPath,
    ]);
    execFileSync(
      "codesign",
      ["--force", "--deep", "--sign", "-", stagedApp],
      { stdio: "inherit" },
    );
    execFileSync("codesign", ["--verify", "--deep", "--strict", stagedApp]);

    stopInstalledApp(targetApp);
    if (existsSync(targetApp)) {
      const backupPath = trashBackupPath(targetApp);
      renameSync(targetApp, backupPath);
      console.log(`Previous app moved to ${backupPath}`);
    }
    renameSync(stagedApp, targetApp);
    execFileSync("open", ["-n", targetApp]);
    console.log(`Installed ${targetApp}`);
    console.log(`app.asar sha256 ${sha256(join(targetApp, "Contents", "Resources", "app.asar"))}`);
  } finally {
    rmSync(tempRoot, { recursive: true, force: true });
  }
}

function status() {
  const manifest = readManifest();
  console.log(`Editable renderer: ${editableAppDir}`);
  console.log(`Baseline: ${manifest.sourceApp}`);
  for (const path of manifest.editableFiles) console.log(path);
}

switch (command) {
  case "extract":
    await extract();
    break;
  case "build":
    await build();
    break;
  case "status":
    status();
    break;
  default:
    fail("Usage: node direct-edit.mjs <extract|build|status> [source-app] [target-app]");
}
