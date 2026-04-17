import { Worker, type Job } from "bullmq";
import { getRedisConnection, closeRedisConnection } from "./connection";

// ── Job processors ──
// Each processor handles jobs from a specific queue.
// Import your processing logic and register it here.

async function processEmail(job: Job) {
  const { to, subject, template, data } = job.data;
  console.log(`[email] Processing job ${job.id}: ${subject} → ${to}`);

  // TODO: Replace with Resend integration
  // import { Resend } from "resend";
  // const resend = new Resend(process.env.RESEND_API_KEY);
  // await resend.emails.send({ from: "...", to, subject, html: ... });

  await job.updateProgress(100);
  return { sent: true, to };
}

// ── Register workers ──
// One Worker per queue. Each runs in the same process but processes independently.
// Concurrency controls how many jobs run in parallel per worker.

const workers: Worker[] = [];

// Must match the prefix used in lib/jobs/queues.ts — otherwise workers read
// from a different keyspace than producers write to. See queues.ts for the
// full two-layer (DB number + prefix) isolation rationale.
const bullmqPrefix = process.env.BULLMQ_PREFIX || "bull";

function registerWorker(queueName: string, processor: (job: Job) => Promise<unknown>, concurrency = 5) {
  const worker = new Worker(queueName, processor, {
    connection: getRedisConnection(),
    prefix: bullmqPrefix,
    concurrency,
  });

  worker.on("completed", (job) => {
    console.log(`[${queueName}] Job ${job.id} completed`);
  });

  worker.on("failed", (job, err) => {
    console.error(`[${queueName}] Job ${job?.id} failed:`, err.message);
  });

  worker.on("stalled", (jobId) => {
    console.warn(`[${queueName}] Job ${jobId} stalled`);
  });

  workers.push(worker);
  console.log(`[${queueName}] Worker registered (concurrency: ${concurrency})`);
}

// ── Start workers ──
registerWorker("email", processEmail, 10);
// registerWorker("ai-agent", processAiAgent, 3);
// registerWorker("export", processExport, 2);

console.log(`DevHawk Worker started — ${workers.length} queue(s) active`);

// ── Graceful shutdown ──
async function shutdown(signal: string) {
  console.log(`\n[worker] ${signal} received, shutting down gracefully...`);
  await Promise.all(workers.map((w) => w.close()));
  await closeRedisConnection();
  console.log("[worker] All workers closed. Exiting.");
  process.exit(0);
}

process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));
