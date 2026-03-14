export function startHMR({ versionPath = "./.hmr-version", intervalMS = 1000 } = {}) {
  let currentVersion = null;

  async function poll() {
    try {
      const res = await fetch(`${versionPath}?ts=${Date.now()}`, { cache: "no-store" });
      if (!res.ok) {
        return;
      }

      const next = (await res.text()).trim();
      if (!next) {
        return;
      }

      if (currentVersion === null) {
        currentVersion = next;
        return;
      }

      if (next !== currentVersion) {
        window.location.reload();
      }
    } catch {
      // Ignore transient polling failures while recompiling.
    }
  }

  setInterval(poll, intervalMS);
  void poll();
}
