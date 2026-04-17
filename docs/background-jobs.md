# Background jobs

## Architecture

Two tiers of background processing, both within DigitalOcean:

1. **BullMQ + DO Worker** — Event-driven. For work triggered by user actions, webhooks, or application events. Retries, concurrency control, delayed jobs.
2. **DO Job component** — Cron-scheduled. For nightly cleanup, report generation, cache warming. Billed per-run.

## Adding a new queue

### 1. Declare the queue in `lib/jobs/queues.ts`

```typescript
export const aiAgentQueue = createQueue("ai-agent");
```

### 2. Create a processor

```typescript
// lib/jobs/processors/ai-agent.ts
import type { Job } from "bullmq";

export async function processAiAgent(job: Job) {
  const { userId, prompt, conversationId } = job.data;

  await job.updateProgress(10);
  const response = await generateAgentResponse(prompt);

  await job.updateProgress(80);
  await saveConversation(conversationId, response);

  await job.updateProgress(100);
  return { responseId: response.id };
}
```

### 3. Register in the worker

```typescript
// lib/jobs/worker.ts
import { processAiAgent } from "./processors/ai-agent";
registerWorker("ai-agent", processAiAgent, 3); // concurrency: 3
```

### 4. Enqueue from your app code

```typescript
// In a Server Action or API route
import { aiAgentQueue } from "@/lib/jobs/queues";

await aiAgentQueue.add("process-prompt", {
  userId: session.user.id,
  prompt: userMessage,
  conversationId: conv.id,
});
```

## Job options

```typescript
await emailQueue.add("welcome", { to, template }, {
  attempts: 5,                           // Retry up to 5 times
  backoff: { type: "exponential", delay: 2000 }, // 2s, 4s, 8s, 16s, 32s
  delay: 1000 * 60 * 60,                // Delay: run in 1 hour
  priority: 1,                           // Lower number = higher priority
  removeOnComplete: { age: 3600 },       // Clean up after 1 hour
});
```

## Repeatable jobs (cron-like)

```typescript
await emailQueue.add("daily-digest", { type: "digest" }, {
  repeat: { pattern: "0 9 * * *" },      // Every day at 9am
});
```

## Job flows (multi-step)

```typescript
import { FlowProducer } from "bullmq";
const flow = new FlowProducer({ connection: getRedisConnection() });

await flow.add({
  name: "generate-report",
  queueName: "export",
  data: { reportId },
  children: [
    { name: "fetch-data", queueName: "export", data: { reportId, step: "fetch" } },
    { name: "render-pdf", queueName: "export", data: { reportId, step: "render" } },
  ],
});
```

Children complete first, then parent runs. Use this for multi-step workflows.

## When to use BullMQ vs DO Job

| Scenario | Use |
|----------|-----|
| User uploads a file → process it | BullMQ (event-driven, needs retries) |
| Send email after signup | BullMQ (event-driven, needs retries) |
| Nightly database cleanup | DO Job (cron, billed per-run) |
| Pre-deploy database migration | DO Job (pre-deploy hook) |
| AI agent execution (long-running) | BullMQ (needs progress tracking, no timeout) |
| Send follow-up email in 24 hours | BullMQ (delayed job) |
| Generate weekly report | Either (DO Job if simple script, BullMQ if complex with retries) |

## Local development

Run the worker in a separate terminal:
```bash
pnpm worker:dev  # tsx watch mode — auto-restarts on changes
```

Make sure Redis is running via Docker Compose:
```bash
docker compose -f docker/docker-compose.dev.yml up redis -d
```
