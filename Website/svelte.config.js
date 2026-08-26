import adapter from "@sveltejs/adapter-node";

/** @type {import('@sveltejs/kit').Config} */
const config = {
  kit: {
    adapter: adapter(),
    files: {
      assets: "public",
    },
    alias: {
      sveltely: "src/lib/frameworks/sveltely",
      "sveltely/*": "src/lib/frameworks/sveltely/*",
    },
    version: {
      pollInterval: 10_000,
    },
  },
};

export default config;
