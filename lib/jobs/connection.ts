import IORedis from "ioredis";

// Lazy singleton — created on first access, reused across the process.
// Works in both the Next.js Service (for queue.add) and the Worker (for processing).
let _connection: IORedis | null = null;

export function getRedisConnection(): IORedis {
  if (!_connection) {
    const url = process.env.REDIS_URL;
    if (!url) throw new Error("REDIS_URL is required");

    _connection = new IORedis(url, {
      maxRetriesPerRequest: null, // Required by BullMQ
      enableReadyCheck: false,
      retryStrategy(times) {
        return Math.min(times * 200, 5000);
      },
    });
  }
  return _connection;
}

export async function closeRedisConnection(): Promise<void> {
  if (_connection) {
    await _connection.quit();
    _connection = null;
  }
}
