import { error } from "@sveltejs/kit";
import { postForSlug } from "$lib/posts";

export function load({ params }) {
  const post = postForSlug(params.slug);
  if (!post) error(404, "Post not found");
  return { post };
}
