import { Database } from "bun:sqlite";
import { drizzle } from "drizzle-orm/bun-sqlite";
import * as schema from "./schema";

export function getDb(path = process.env.DATABASE_URL ?? "range.db") {
  return drizzle(new Database(path), { schema });
}
