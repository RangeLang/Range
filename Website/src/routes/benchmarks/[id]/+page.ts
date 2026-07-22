import { error } from "@sveltejs/kit";
import { benchmarkFromLeaf, benchmarkRecords } from "$lib/benchmarks";
import type { PageLoad } from "./$types";

export const load: PageLoad = ({ params }) => {
  const record = benchmarkRecords().find(({ leaf }) => leaf.id === params.id);
  if (!record) error(404, "Benchmark not found");
  const benchmark = benchmarkFromLeaf(record.subcategory.name, record.leaf);
  benchmark.href = undefined;
  return { ...record, benchmark };
};
