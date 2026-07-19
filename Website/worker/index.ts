import styles from "../app/globals.css?raw";
import benchmarkData from "../public/benchmarks.json";
import { renderDocument } from "../src/render";

interface Env {
  ASSETS: Fetcher;
}

const worker = {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/globals.css") {
      return new Response(styles, {
        headers: {
          "cache-control": "public, max-age=3600",
          "content-type": "text/css; charset=utf-8",
        },
      });
    }

    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Method not allowed", { status: 405 });
    }

    const rendered = renderDocument(url, benchmarkData);
    if (rendered) {
      return new Response(request.method === "HEAD" ? null : rendered.html, {
        status: rendered.status,
        headers: {
          "content-type": "text/html; charset=utf-8",
          "x-content-type-options": "nosniff",
        },
      });
    }

    return env.ASSETS.fetch(request);
  },
};

export default worker;
