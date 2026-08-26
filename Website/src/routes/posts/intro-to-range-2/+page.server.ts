import { requireDraftPreview } from "$lib/server/draft-preview";

export const load = ({ url }) => {
  requireDraftPreview(url);
};
