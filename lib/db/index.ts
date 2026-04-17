import { drizzle } from "drizzle-orm/postgres-js";
import postgres from "postgres";
import * as schema from "./schema";
import { env } from "@/lib/env";

// Connection pool: max 10 connections in production, 1 in dev
const connection = postgres(env.DATABASE_URL, {
  max: env.NODE_ENV === "production" ? 10 : 1,
  idle_timeout: 20,
  max_lifetime: 60 * 30, // 30 minutes
});

export const db = drizzle(connection, {
  schema,
  logger: env.NODE_ENV === "development",
});

export type Database = typeof db;
