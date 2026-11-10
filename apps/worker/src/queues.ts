/**
 * Queue message contracts and the consumer loop. Off until a queue is bound (infra/cloud/README.md,
 * Queues): the jobs Worker then produces and consumes it, and each queue has a dead-letter queue.
 * Queues deliver at least once, so every handler must be safe to run twice with the same message.
 */

/** Queue keys to their base names; the hosted name is <project>-<key>-<env>, the binding <KEY>_QUEUE. */
export const QUEUES = { jobs: "jobs" } as const;
export type QueueKey = keyof typeof QUEUES;

export interface ExampleQueueMessage {
  kind: "example";
  id: string;
}
export type QueueMessage = ExampleQueueMessage;

const kindToQueue: Record<QueueMessage["kind"], QueueKey> = { example: "jobs" };

export function decodeQueueMessage(value: unknown): QueueMessage | null {
  if (!value || typeof value !== "object") return null;
  const message = value as Record<string, unknown>;
  if (message.kind === "example" && typeof message.id === "string" && message.id.length > 0)
    return { kind: "example", id: message.id };
  return null;
}

/** Seconds before a failed message is retried; after max_retries it goes to the dead-letter queue. */
export function retryDelaySeconds(message: QueueMessage, attempts: number): number {
  void message;
  return Math.min(30 * 2 ** Math.max(0, attempts - 1), 900);
}

type Producer = { send(body: unknown, options?: { delaySeconds?: number }): Promise<unknown> };

/**
 * Sends to the message's queue. A missing binding throws instead of skipping: a source repo once
 * shipped hosted configs with 1 of 5 producers and silently dropped the rest.
 */
export async function sendToQueue(env: object, message: QueueMessage, delaySeconds?: number) {
  const binding = `${kindToQueue[message.kind].toUpperCase()}_QUEUE`;
  const producer = (env as Record<string, Producer | undefined>)[binding];
  if (!producer) throw new Error(`No ${binding} binding: add it to every block of wrangler.jsonc.`);
  await producer.send(message, delaySeconds ? { delaySeconds } : undefined);
}

interface Message {
  id: string;
  body: unknown;
  attempts: number;
  ack(): void;
  retry(options?: { delaySeconds?: number }): void;
}

/** Acks invalid messages (retrying cannot fix them), acks successes, retries failures with backoff. */
export async function consumeBatch(
  batch: { queue: string; messages: readonly Message[] },
  handle: (message: QueueMessage, attempts: number) => Promise<void>,
): Promise<void> {
  for (const message of batch.messages) {
    const decoded = decodeQueueMessage(message.body);
    if (!decoded) {
      console.error(JSON.stringify({ event: "queue.invalid", queue: batch.queue, id: message.id }));
      message.ack();
      continue;
    }
    try {
      await handle(decoded, message.attempts);
      message.ack();
    } catch (error) {
      console.error(
        JSON.stringify({
          event: "queue.failed",
          queue: batch.queue,
          kind: decoded.kind,
          attempts: message.attempts,
          error: String(error),
        }),
      );
      message.retry({ delaySeconds: retryDelaySeconds(decoded, message.attempts) });
    }
  }
}
