import type { Response } from "express";

// ── HTTP-Statuscodes und neutrale Fehlerantworten ───────────────────
// Clients bekommen nur neutrale deutsche Meldungen – keine Stacktraces,
// SDK-Fehlertexte, Pfade oder Versionen. Details gehören ins Log.

export const HTTP_BAD_REQUEST = 400;
export const HTTP_UNAUTHORIZED = 401;
export const HTTP_NOT_FOUND = 404;
export const HTTP_PAYLOAD_TOO_LARGE = 413;
export const HTTP_UNSUPPORTED_MEDIA_TYPE = 415;
export const HTTP_TOO_MANY_REQUESTS = 429;
export const HTTP_INTERNAL_ERROR = 500;
export const HTTP_SERVICE_UNAVAILABLE = 503;

/** Sendet eine JSON-Fehlerantwort mit neutraler Meldung. */
export function sendError(res: Response, status: number, message: string): void {
  res.status(status).json({ error: message });
}
