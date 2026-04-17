import { Queue } from "bullmq";
import { getRedisConnection } from "./connection";

// BullMQ key prefix. Paired with the Valkey DB number in REDIS_URL as a
// two-layer isolation strategy when sharing a Valkey cluster with another env
// (typically prod): the URL path sets the DB (SELECT n on connect), and this
// prefix namespaces BullMQ keys within that DB. Staging sets
// BULLMQ_PREFIX=bull:staging; prod uses the default "bull". Worker MUST use
// the same prefix — see lib/jobs/worker.ts. Keep both layers: the prefix is
// the backstop if REDIS_URL ever lands without the /N path (or if the cluster
// is ever upgraded to Cluster mode, where SELECT is unavailable).
const bullmqPrefix = process.env.BULLMQ_PREFIX || "bull";

// ── Queue factory ──
// Creates a queue connected to DO Managed Redis/Valkey.
// Call from Next.js Service code (API routes, Server Actions) to enqueue work.

function createQueue(name: string) {
  return new Queue(name, {
    connection: getRedisConnection(),
    prefix: bullmqPrefix,
    defaultJobOptions: {
      attempts: 3,
      backoff: {
        type: "exponential",
        delay: 1000,
      },
      removeOnComplete: { age: 24 * 3600, count: 1000 },
      removeOnFail: { age: 7 * 24 * 3600, count: 5000 },
    },
  });
}

// ── Project queues ──
// Add queues as needed. Each queue processes a different type of work.
// The Worker component (Dockerfile.worker) runs processors for all queues.

export const emailQueue = createQueue("email");
// export const aiAgentQueue = createQueue("ai-agent");
// export const exportQueue = createQueue("export");
// export const webhookQueue = createQueue("webhook");
