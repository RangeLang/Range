const componentNames = [
  "range-site-shell",
  "range-home-page",
  "range-benchmarks-page",
  "range-benchmark-page",
  "range-update-page",
  "range-benchmark-chart",
  "range-code-block",
  "range-status-list",
  "range-site-footer",
];

for (const name of componentNames) {
  if (!customElements.get(name)) {
    customElements.define(name, class extends HTMLElement {});
  }
}
