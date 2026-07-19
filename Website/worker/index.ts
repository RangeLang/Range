import styles from "../app/globals.css?raw";
import benchmarkData from "../public/benchmarks.json";
import { renderDocument } from "../src/render";

interface Env {
  ASSETS: Fetcher;
}

const worker = {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/globals.css" || url.pathname === "/range-geist.css" || url.pathname === "/range-ui.css" || url.pathname === "/range-ui-v92.css") {
      return new Response(styles, {
        headers: {
          "cache-control": "no-cache",
          "content-type": "text/css; charset=utf-8",
        },
      });
    }

    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Method not allowed", { status: 405 });
    }

    const rendered = renderDocument(url, benchmarkData);
    if (rendered) {
      const html = rendered.html
        .replace('/range-ui.css', '/range-ui-v92.css')
        .replace('/range-typed-text.js', '/range-typed-text.js?version=84')
        .replace('/range-navigation-v2.js', '/range-navigation-v2.js?version=86');
      return new Response(request.method === "HEAD" ? null : html, {
        status: rendered.status,
        headers: {
          "content-type": "text/html; charset=utf-8",
          "x-content-type-options": "nosniff",
        },
      });
    }

    const asset = await env.ASSETS.fetch(request);
    if (url.pathname.endsWith(".woff2") && asset.ok) {
      const headers = new Headers(asset.headers);
      headers.set("content-type", "font/woff2");
      headers.set("cache-control", "public, max-age=31536000, immutable");
      return new Response(asset.body, { status: asset.status, headers });
    }
    return asset;
  },
};

export default worker;
