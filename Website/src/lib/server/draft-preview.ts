import { dev } from "$app/environment";
import { error } from "@sveltejs/kit";

export function requireDraftPreview(url: URL) {
  const isLocalPreview =
    dev && url.searchParams.get("preview") === "range-draft";
  if (!isLocalPreview) error(404, "Not found");
}
