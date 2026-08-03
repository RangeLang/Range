import { dev } from "$app/environment";
import { error } from "@sveltejs/kit";

export const load = ({ url }) => {
  const isLocalPreview =
    dev && url.searchParams.get("preview") === "range-draft";

  if (!isLocalPreview) error(404, "Not found");
};
