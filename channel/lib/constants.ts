/**
 * Zentrale Konstanten des Channel-Servers (Grenzwerte, Zeiten, HTTP-Status).
 */

export const VERSION = '2.0.0'
export const SERVER_NAME = 'raybanclaude'

// ── Einheiten ──────────────────────────────────────────────────────────────
export const BYTES_PER_KB = 1024
export const BYTES_PER_MB = 1_048_576
export const MS_PER_SECOND = 1000
export const MS_PER_MINUTE = 60_000
export const MS_PER_HOUR = 3_600_000

// ── Netzwerk ───────────────────────────────────────────────────────────────
export const DEFAULT_PORT = 18790
export const MIN_PORT = 1024
export const MAX_PORT = 65535
export const HTTP_DEFAULT_PORT = 80
export const LISTEN_HOST = '0.0.0.0' // LAN-Zugriff vom Handy

// ── Grenzwerte ─────────────────────────────────────────────────────────────
export const MAX_TEXT_CHARS = 8000            // Nutzernachricht
export const MAX_REPLY_CHARS = 10_000         // Antwort von Claude
export const MAX_MODE_PROMPT_CHARS = 4000
export const MAX_MODE_NAME_CHARS = 60
export const MAX_REASON_CHARS = 120
export const MAX_TEST_MESSAGE_CHARS = 500
export const MAX_IMESSAGE_CHARS = 2000
export const MAX_TTS_CHARS = 2500
export const MAX_LOG_PREVIEW_CHARS = 80
export const MAX_ACTIVITY_TEXT_CHARS = 160
export const MAX_ACTIVITY_ENTRIES = 100
export const MAX_ATTACHMENTS = 5

export const MAX_IMAGE_MB = 12
export const MAX_IMAGE_BYTES = MAX_IMAGE_MB * BYTES_PER_MB
export const MAX_ATTACHMENT_MB = 25
export const MAX_ATTACHMENT_BYTES = MAX_ATTACHMENT_MB * BYTES_PER_MB
export const MAX_REQUEST_MB = 16
export const MAX_REQUEST_BYTES = MAX_REQUEST_MB * BYTES_PER_MB

/** Base64 bläht um 4/3 auf – Obergrenze für die Länge eines Base64-Bildes. */
const BASE64_GROUP_BYTES = 3
const BASE64_GROUP_CHARS = 4
export const MAX_IMAGE_BASE64_CHARS = Math.ceil(MAX_IMAGE_BYTES / BASE64_GROUP_BYTES) * BASE64_GROUP_CHARS + BASE64_GROUP_CHARS

// ── Zeiten ─────────────────────────────────────────────────────────────────
export const FILE_TTL_HOURS = 24
export const FILE_TTL_MS = FILE_TTL_HOURS * MS_PER_HOUR
export const AUTH_MAX_FAILS = 10
export const AUTH_WINDOW_MINUTES = 15
export const AUTH_WINDOW_MS = AUTH_WINDOW_MINUTES * MS_PER_MINUTE
export const AUTH_LOCK_MS = AUTH_WINDOW_MS
export const CAPTURE_TTL_MINUTES = 5
export const CAPTURE_TTL_MS = CAPTURE_TTL_MINUTES * MS_PER_MINUTE
export const TTS_TIMEOUT_MS = 20_000
export const WS_IDLE_TIMEOUT_SECONDS = 120
export const PHONE_ACTION_TIMEOUT_MS = 25_000
export const MAX_ACTION_RESULT_CHARS = 300

// ── Token ──────────────────────────────────────────────────────────────────
export const TOKEN_BYTES = 24              // → 48 Hex-Zeichen
export const TOKEN_PREVIEW_CHARS = 4
export const TOKEN_PREVIEW_TAIL = -2
export const RANDOM_SUFFIX_BYTES = 4
export const PRIVATE_FILE_MODE = 0o600

// ── ElevenLabs (optional) ──────────────────────────────────────────────────
export const ELEVENLABS_MODEL = 'eleven_flash_v2_5' // mehrsprachig (inkl. Deutsch), geringste Latenz
export const ELEVENLABS_DEFAULT_VOICE = 'XB0fDUnXU5powFXDhCwa' // Charlotte
export const ELEVENLABS_STABILITY = 0.5
export const ELEVENLABS_SIMILARITY = 0.75

// ── Bildformate (Magic Bytes) ──────────────────────────────────────────────
export const JPEG_MAGIC_HEX = 'ffd8ff'
export const PNG_MAGIC_HEX = '89504e47'
export const HEIC_BRAND_START = 4
export const HEIC_BRAND_END = 12
export const MIN_IMAGE_HEADER_BYTES = HEIC_BRAND_END

// ── HTTP-Status ────────────────────────────────────────────────────────────
export const HTTP_OK = 200
export const HTTP_ACCEPTED = 202
export const HTTP_BAD_REQUEST = 400
export const HTTP_UNAUTHORIZED = 401
export const HTTP_FORBIDDEN = 403
export const HTTP_NOT_FOUND = 404
export const HTTP_PAYLOAD_TOO_LARGE = 413
export const HTTP_UNSUPPORTED_MEDIA = 415
export const HTTP_TOO_MANY_REQUESTS = 429
export const HTTP_INTERNAL_ERROR = 500
export const HTTP_NOT_IMPLEMENTED = 501

/** WebSocket-readyState „offen“ (siehe WHATWG-Spezifikation). */
export const WS_OPEN = 1
