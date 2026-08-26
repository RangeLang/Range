import { defineConfig } from "vite";
import { sveltekit } from "@sveltejs/kit/vite";
import { fileURLToPath } from "node:url";

const sveltelyRoot = fileURLToPath(
  new URL("./src/lib/frameworks/sveltely/", import.meta.url),
);
const sveltelyEntry = fileURLToPath(
  new URL("./src/lib/frameworks/sveltely/index.js", import.meta.url),
);
const sveltelyStyles = fileURLToPath(
  new URL("./src/lib/frameworks/sveltely/style.css", import.meta.url),
);

// macOS Seatbelt blocks FSEvents, so Codex previews need polling for HMR.
const isCodexSeatbeltSandbox = process.env.CODEX_SANDBOX === "seatbelt";

export default defineConfig({
  resolve: {
    preserveSymlinks: true,
    alias: [
      { find: "sveltely/style.css", replacement: sveltelyStyles },
      { find: /^sveltely$/, replacement: sveltelyEntry },
    ],
    dedupe: ["svelte"],
  },
  optimizeDeps: {
    exclude: ["sveltely"],
  },
  ssr: {
    noExternal: ["sveltely"],
  },
  server: {
    ...(isCodexSeatbeltSandbox
      ? { watch: { useFsEvents: false, usePolling: true } }
      : {}),
    fs: {
      allow: ["..", sveltelyRoot],
    },
  },
  plugins: [sveltekit()],
});
