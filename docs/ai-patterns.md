# AI patterns

## Setup

AI SDK 6 is provider-agnostic. Configure providers in your code, API keys in env vars.

```typescript
import { anthropic } from "@ai-sdk/anthropic";
import { openai } from "@ai-sdk/openai";

// Use either — switch by changing the model reference
const model = anthropic("claude-sonnet-4-20250514");
// const model = openai("gpt-4o");
```

## Streaming chat (Server Action + useChat)

```typescript
// app/api/chat/route.ts
import { anthropic } from "@ai-sdk/anthropic";
import { streamText } from "ai";

export async function POST(req: Request) {
  const { messages } = await req.json();

  const result = streamText({
    model: anthropic("claude-sonnet-4-20250514"),
    system: "You are a helpful assistant.",
    messages,
  });

  return result.toDataStreamResponse();
}
```

```typescript
// Client component
"use client";
import { useChat } from "ai/react";

export function ChatWidget() {
  const { messages, input, handleInputChange, handleSubmit } = useChat();
  // ... render messages and input form
}
```

## Structured outputs

Generate typed JSON from LLMs using Zod schemas:

```typescript
import { generateObject } from "ai";
import { z } from "zod";

const { object } = await generateObject({
  model: anthropic("claude-sonnet-4-20250514"),
  schema: z.object({
    title: z.string(),
    summary: z.string(),
    tags: z.array(z.string()),
    sentiment: z.enum(["positive", "negative", "neutral"]),
  }),
  prompt: `Analyze this customer review: "${review}"`,
});
// object is fully typed: { title: string, summary: string, tags: string[], ... }
```

## Tool calling

Define tools with Zod parameter schemas:

```typescript
import { generateText, tool } from "ai";
import { z } from "zod";

const result = await generateText({
  model: anthropic("claude-sonnet-4-20250514"),
  tools: {
    getWeather: tool({
      description: "Get current weather for a location",
      parameters: z.object({
        city: z.string().describe("City name"),
      }),
      execute: async ({ city }) => {
        const data = await fetchWeather(city);
        return { temperature: data.temp, conditions: data.conditions };
      },
    }),
    searchProducts: tool({
      description: "Search the product catalog",
      parameters: z.object({
        query: z.string(),
        maxResults: z.number().default(5),
      }),
      execute: async ({ query, maxResults }) => {
        return await db.select().from(product)
          .where(ilike(product.name, `%${query}%`))
          .limit(maxResults);
      },
    }),
  },
  prompt: userMessage,
});
```

## Agent loops

For multi-step agents that iterate until done:

```typescript
import { generateText } from "ai";

const { text, toolResults } = await generateText({
  model: anthropic("claude-sonnet-4-20250514"),
  tools: { /* ... */ },
  maxSteps: 10, // Max tool call iterations
  prompt: taskDescription,
});
```

## Background AI processing

For long-running AI tasks, enqueue via BullMQ:

```typescript
// Server Action: enqueue the work
await aiAgentQueue.add("analyze", {
  documentId: doc.id,
  userId: session.user.id,
});

// Worker processor: run the AI task
async function processAiAgent(job: Job) {
  const doc = await db.query.document.findFirst({
    where: eq(document.id, job.data.documentId),
  });

  const { object } = await generateObject({
    model: anthropic("claude-sonnet-4-20250514"),
    schema: analysisSchema,
    prompt: `Analyze this document: ${doc.content}`,
  });

  await db.update(document)
    .set({ analysis: object, analyzedAt: new Date() })
    .where(eq(document.id, doc.id));
}
```
