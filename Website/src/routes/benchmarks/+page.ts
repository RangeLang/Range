import { completedCategories } from "$lib/benchmarks";
import type { PageLoad } from "./$types";

export const load: PageLoad = ({ url }) => {
  const categories = completedCategories();
  const active = categories.find((category) => category.id === url.searchParams.get("category")) ?? categories[0];
  return { categories, active };
};
