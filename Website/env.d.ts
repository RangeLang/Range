interface Fetcher {
  fetch(request: Request): Promise<Response>;
}

declare module "*.css?raw" {
  const source: string;
  export default source;
}
