import type { ServerConfig } from "./types.js";

// ── Eingabevalidierung ──────────────────────────────────────────────
// Whitelist-Prüfung aller Felder (Typ, Länge, Format). Fehlermeldungen sind
// neutral und deutsch; sie verraten nichts über interne Abläufe.

export type ValidationResult<TValue> =
  | { readonly ok: true; readonly value: TValue }
  | { readonly ok: false; readonly error: string };

function valid<TValue>(value: TValue): ValidationResult<TValue> {
  return { ok: true, value };
}

function invalid<TValue>(error: string): ValidationResult<TValue> {
  return { ok: false, error };
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** undefined und null gelten als „Feld nicht angegeben". */
function isAbsent(value: unknown): value is undefined | null {
  return value === undefined || value === null;
}

const NOT_AN_OBJECT = "Ungültiger Anfrage-Body – ein JSON-Objekt wird erwartet.";

// ── POST /chat ──

export const MAX_TEXT_LENGTH = 4000;
export const MAX_IMAGES = 4;
/** Base64-Länge eines 5-MB-Bildes (Bildlimit der Claude-API: 5 × 1024 × 1024 Byte × 4/3) */
export const MAX_IMAGE_BASE64_LENGTH = 6_990_508;
const BASE64_BLOCK_SIZE = 4;
const MAX_CONVERSATION_ID_LENGTH = 64;

// Reines Base64 (Standardalphabet, optional 1–2 "=" am Ende, ohne Zeilenumbrüche).
// Akzeptiert "/9j/4AAQSkZJRg==", lehnt "abc$def" ab.
// https://regex101.com/?flavor=javascript&regex=%5E%5BA-Za-z0-9%2B%2F%5D%2B%3D%7B0%2C2%7D%24&flags=gm&testString=%2F9j%2F4AAQSkZJRg%3D%3D%0Aabc%24def
const BASE64_PATTERN = /^[A-Za-z0-9+/]+={0,2}$/;

// Konversations-ID: 1–64 Zeichen aus A–Z, a–z, 0–9, "_" und "-".
// Akzeptiert "a1b2-c3_d4", lehnt "abc/def" ab.
// https://regex101.com/?flavor=javascript&regex=%5E%5BA-Za-z0-9_-%5D%7B1%2C64%7D%24&flags=gm&testString=a1b2-c3_d4%0Aabc%2Fdef
const CONVERSATION_ID_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;

export type ImageMediaType = "image/jpeg" | "image/png";

/** Bildformate anhand der Base64-kodierten Magic Bytes (JPEG: FF D8 FF, PNG: 89 50 4E 47). */
const IMAGE_SIGNATURES: readonly { readonly prefix: string; readonly mediaType: ImageMediaType }[] = [
  { prefix: "/9j/", mediaType: "image/jpeg" },
  { prefix: "iVBOR", mediaType: "image/png" },
];

export interface ValidatedImage {
  readonly mediaType: ImageMediaType;
  readonly data: string;
}

export interface ValidatedChatRequest {
  readonly text: string;
  readonly images: readonly ValidatedImage[];
  readonly conversationId?: string;
}

function validateImage(raw: unknown, index: number): ValidationResult<ValidatedImage> {
  const label = `Bild ${index + 1}`;
  if (typeof raw !== "string" || !raw) {
    return invalid(`${label}: Base64-String erwartet.`);
  }
  if (raw.length > MAX_IMAGE_BASE64_LENGTH) {
    return invalid(`${label} ist zu groß (max. ca. 8 MB).`);
  }
  if (raw.length % BASE64_BLOCK_SIZE || !BASE64_PATTERN.test(raw)) {
    return invalid(`${label}: ungültige Base64-Kodierung.`);
  }
  const signature = IMAGE_SIGNATURES.find((sig) => raw.startsWith(sig.prefix));
  if (!signature) {
    return invalid(`${label}: nur JPEG- oder PNG-Bilder werden unterstützt.`);
  }
  return valid({ mediaType: signature.mediaType, data: raw });
}

function validateImages(raw: unknown): ValidationResult<readonly ValidatedImage[]> {
  if (isAbsent(raw)) {
    return valid([]);
  }
  if (!Array.isArray(raw)) {
    return invalid("Feld „images“ muss ein Array sein.");
  }
  if (raw.length > MAX_IMAGES) {
    return invalid(`Zu viele Bilder (max. ${MAX_IMAGES}).`);
  }
  const results = raw.map((item: unknown, index) => validateImage(item, index));
  const failure = results.find((result) => !result.ok);
  if (failure && !failure.ok) {
    return invalid(failure.error);
  }
  return valid(results.flatMap((result) => (result.ok ? [result.value] : [])));
}

function validateConversationId(raw: unknown): ValidationResult<string | undefined> {
  if (isAbsent(raw)) {
    return valid(undefined);
  }
  if (typeof raw !== "string" || !CONVERSATION_ID_PATTERN.test(raw)) {
    return invalid(
      `Feld „conversation_id“ ist ungültig (max. ${MAX_CONVERSATION_ID_LENGTH} Zeichen, nur A–Z, a–z, 0–9, _ und -).`
    );
  }
  return valid(raw);
}

function validateText(raw: unknown): ValidationResult<string> {
  if (isAbsent(raw)) {
    return valid("");
  }
  if (typeof raw !== "string") {
    return invalid("Feld „text“ muss ein String sein.");
  }
  if (raw.length > MAX_TEXT_LENGTH) {
    return invalid(`Feld „text“ ist zu lang (max. ${MAX_TEXT_LENGTH} Zeichen).`);
  }
  return valid(raw.trim());
}

/** Prüft den Body von POST /chat. Unbekannte Felder werden ignoriert. */
export function validateChatRequest(body: unknown): ValidationResult<ValidatedChatRequest> {
  if (!isPlainObject(body)) {
    return invalid(NOT_AN_OBJECT);
  }
  const text = validateText(body.text);
  if (!text.ok) return invalid(text.error);

  const images = validateImages(body.images);
  if (!images.ok) return invalid(images.error);

  const conversationId = validateConversationId(body.conversation_id);
  if (!conversationId.ok) return invalid(conversationId.error);

  if (!text.value && !images.value.length) {
    return invalid("Text oder Bild erforderlich.");
  }

  return valid({
    text: text.value,
    images: images.value,
    ...(conversationId.value ? { conversationId: conversationId.value } : {}),
  });
}

// ── POST /config ──

export const MAX_SYSTEM_PROMPT_LENGTH = 20_000;
export const MAX_TOKENS_LIMIT = 32_000;

// Modell-ID: "claude-" gefolgt von 1–60 Zeichen aus a–z, 0–9, "." und "-".
// Akzeptiert "claude-opus-5-5", lehnt "gpt-4o" und "claude-Opus" ab.
// https://regex101.com/?flavor=javascript&regex=%5Eclaude-%5Ba-z0-9.-%5D%7B1%2C60%7D%24&flags=gm&testString=claude-opus-5-5%0Agpt-4o
export const MODEL_PATTERN = /^claude-[a-z0-9.-]{1,60}$/;

export type ConfigChanges = Partial<Pick<ServerConfig, "systemPrompt" | "model" | "maxTokens">>;

function validateSystemPrompt(raw: unknown): ValidationResult<string | undefined> {
  if (raw === undefined) return valid(undefined);
  if (typeof raw !== "string" || !raw.trim() || raw.length > MAX_SYSTEM_PROMPT_LENGTH) {
    return invalid(
      `Feld „system_prompt“ muss ein nicht-leerer String mit max. ${MAX_SYSTEM_PROMPT_LENGTH} Zeichen sein.`
    );
  }
  return valid(raw);
}

function validateModel(raw: unknown): ValidationResult<string | undefined> {
  if (raw === undefined) return valid(undefined);
  if (typeof raw !== "string" || !MODEL_PATTERN.test(raw)) {
    return invalid("Feld „model“ ist ungültig (Format: claude-…).");
  }
  return valid(raw);
}

function validateMaxTokens(raw: unknown): ValidationResult<number | undefined> {
  if (raw === undefined) return valid(undefined);
  if (typeof raw !== "number" || !Number.isInteger(raw) || raw < 1 || raw > MAX_TOKENS_LIMIT) {
    return invalid(`Feld „max_tokens“ muss eine ganze Zahl zwischen 1 und ${MAX_TOKENS_LIMIT} sein.`);
  }
  return valid(raw);
}

/** Prüft den Body von POST /config. Unbekannte Felder werden ignoriert. */
export function validateConfigUpdate(body: unknown): ValidationResult<ConfigChanges> {
  if (!isPlainObject(body)) {
    return invalid(NOT_AN_OBJECT);
  }
  const systemPrompt = validateSystemPrompt(body.system_prompt);
  if (!systemPrompt.ok) return invalid(systemPrompt.error);

  const model = validateModel(body.model);
  if (!model.ok) return invalid(model.error);

  const maxTokens = validateMaxTokens(body.max_tokens);
  if (!maxTokens.ok) return invalid(maxTokens.error);

  return valid({
    ...(systemPrompt.value !== undefined ? { systemPrompt: systemPrompt.value } : {}),
    ...(model.value !== undefined ? { model: model.value } : {}),
    ...(maxTokens.value !== undefined ? { maxTokens: maxTokens.value } : {}),
  });
}
