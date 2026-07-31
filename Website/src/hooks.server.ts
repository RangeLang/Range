import type { Handle } from "@sveltejs/kit";

export const handle: Handle = async ({ event, resolve }) => {
  const response = await resolve(event);
  const acceptsHtml = event.request.headers
    .get("accept")
    ?.includes("text/html");
  const isPageRequest =
    event.request.method === "GET" || event.request.method === "HEAD";

  if (response.status === 404 && acceptsHtml && isPageRequest) {
    return new Response(null, {
      status: 302,
      headers: { location: "/" },
    });
  }

  return response;
};
