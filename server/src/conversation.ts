import { randomUUID } from "node:crypto";
import type { ContentBlockParam, MessageParam } from "./types.js";

// ── Konversationsspeicher (In-Memory) ───────────────────────────────
// - Kamerabilder werden NICHT in der History gespeichert, sondern durch den
//   Textblock "[Kamerabild]" ersetzt. Sonst würde jede Runde alle alten
//   Bilder erneut an die API schicken (Token-Explosion).
// - History ist auf die letzten MAX_HISTORY_MESSAGES Nachrichten begrenzt und
//   beginnt immer mit einer Nutzernachricht (gültige API-Reihenfolge).
// - Höchstens MAX_CONVERSATIONS Konversationen; die am längsten unbenutzte
//   wird bei Bedarf verworfen.

const MS_PER_MINUTE = 60_000;
const CONVERSATION_TTL_MINUTES = 30;
const CLEANUP_INTERVAL_MINUTES = 5;
const DEFAULT_MAX_CONVERSATIONS = 200;
const DEFAULT_MAX_HISTORY_MESSAGES = 40;

export const IMAGE_PLACEHOLDER = "[Kamerabild]";

interface ConversationEntry {
  readonly messages: readonly MessageParam[];
  readonly lastAccess: number;
}

/** Ersetzt Bild-Blöcke durch einen kurzen Platzhalter-Text. */
export function withoutImages(message: MessageParam): MessageParam {
  if (typeof message.content === "string") {
    return message;
  }
  const content = message.content.map(
    (block): ContentBlockParam =>
      block.type === "image" ? { type: "text", text: IMAGE_PLACEHOLDER } : block
  );
  return { ...message, content };
}

/** true für echte Nutzereingaben (nicht für tool_result-Nachrichten). */
function isUserTurnStart(message: MessageParam): boolean {
  if (message.role !== "user") return false;
  return (
    typeof message.content === "string" ||
    !message.content.some((block) => block.type === "tool_result")
  );
}

/** Kürzt auf die letzten maxMessages Nachrichten, beginnend bei einer Nutzernachricht. */
export function trimHistory(
  messages: readonly MessageParam[],
  maxMessages: number
): MessageParam[] {
  const tail = messages.slice(-maxMessages);
  const start = tail.findIndex(isUserTurnStart);
  return start === -1 ? [] : tail.slice(start);
}

export class ConversationStore {
  private readonly store = new Map<string, ConversationEntry>();
  private readonly cleanupTimer: NodeJS.Timeout;
  private readonly ttlMs = CONVERSATION_TTL_MINUTES * MS_PER_MINUTE;

  constructor(
    private readonly maxConversations: number = DEFAULT_MAX_CONVERSATIONS,
    private readonly maxHistoryMessages: number = DEFAULT_MAX_HISTORY_MESSAGES
  ) {
    this.cleanupTimer = setInterval(
      () => this.cleanup(),
      CLEANUP_INTERVAL_MINUTES * MS_PER_MINUTE
    );
    // Timer soll das Beenden des Prozesses nicht verhindern
    this.cleanupTimer.unref();
  }

  /** Liefert die ID einer bestehenden Konversation oder legt eine neue an. */
  resolveId(conversationId?: string): string {
    const id = conversationId ?? randomUUID();
    const existing = this.store.get(id);
    this.put(id, existing?.messages ?? []);
    return id;
  }

  /** Kopie der History (für den nächsten API-Aufruf). */
  getHistory(id: string): MessageParam[] {
    return [...(this.store.get(id)?.messages ?? [])];
  }

  /** Hängt eine vollständige Runde (Nutzer + Assistent) an. */
  appendTurn(id: string, user: MessageParam, assistant: MessageParam): void {
    const previous = this.store.get(id)?.messages ?? [];
    const next = trimHistory(
      [...previous, withoutImages(user), assistant],
      this.maxHistoryMessages
    );
    this.put(id, next);
  }

  get size(): number {
    return this.store.size;
  }

  destroy(): void {
    clearInterval(this.cleanupTimer);
    this.store.clear();
  }

  /** Speichert und markiert als zuletzt benutzt (Map-Reihenfolge = LRU). */
  private put(id: string, messages: readonly MessageParam[]): void {
    this.store.delete(id);
    if (this.store.size >= this.maxConversations) {
      const oldest = this.store.keys().next().value;
      if (oldest !== undefined) {
        this.store.delete(oldest);
      }
    }
    this.store.set(id, { messages, lastAccess: Date.now() });
  }

  private cleanup(): void {
    const now = Date.now();
    [...this.store]
      .filter(([, entry]) => now - entry.lastAccess > this.ttlMs)
      .forEach(([id]) => this.store.delete(id));
  }
}
