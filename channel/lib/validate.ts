/**
 * Eingabevalidierung an der Systemgrenze (App → Server). Whitelist statt Blacklist.
 */

import {
  HEIC_BRAND_END, HEIC_BRAND_START, HTTP_PAYLOAD_TOO_LARGE, HTTP_UNSUPPORTED_MEDIA, JPEG_MAGIC_HEX,
  MAX_IMAGE_BYTES, MAX_IMAGE_MB, MAX_MODE_NAME_CHARS, MAX_PORT, MAX_TEXT_CHARS, MIN_IMAGE_HEADER_BYTES,
  MIN_PORT, PNG_MAGIC_HEX,
} from './constants.ts'
import { CONTROL_CHARS, HEIC_BRAND, MESSAGE_ID, MODE_NAME_DISALLOWED } from './patterns.ts'

/** Fehler mit HTTP-Status, dessen Text gefahrlos an den Client gehen darf. */
export class HttpError extends Error {
  constructor(public readonly status: number, message: string) {
    super(message)
    this.name = 'HttpError'
  }
}

export const SOURCES = ['iphone', 'rayban'] as const
export type Source = (typeof SOURCES)[number]
const DEFAULT_SOURCE: Source = 'iphone'

export type ImageExt = '.jpg' | '.png' | '.heic'

export function isSource(raw: unknown): raw is Source {
  return SOURCES.some(s => s === raw)
}

export function cleanText(raw: unknown, max: number = MAX_TEXT_CHARS): string {
  if (typeof raw !== 'string') return ''
  return raw.replace(CONTROL_CHARS, '').trim().slice(0, max)
}

export function cleanSource(raw: unknown): Source {
  return isSource(raw) ? raw : DEFAULT_SOURCE
}

export function cleanId(raw: unknown, fallback: () => string): string {
  return typeof raw === 'string' && MESSAGE_ID.test(raw) ? raw : fallback()
}

export function isValidId(raw: unknown): raw is string {
  return typeof raw === 'string' && MESSAGE_ID.test(raw)
}

export function cleanModeName(raw: unknown): string {
  return cleanText(raw, MAX_MODE_NAME_CHARS).replace(MODE_NAME_DISALLOWED, '').trim()
}

export function parsePort(raw: string | undefined, fallback: number): number {
  const n = Number(raw)
  return Number.isInteger(n) && n >= MIN_PORT && n <= MAX_PORT ? n : fallback
}

/** Ermittelt das Bildformat anhand der Magic Bytes – dem Dateinamen wird nie vertraut. */
export function imageExt(buf: Uint8Array): ImageExt | null {
  if (buf.length < MIN_IMAGE_HEADER_BYTES) return null
  const head = Buffer.from(buf.subarray(0, HEIC_BRAND_END))
  const hex = head.toString('hex')
  if (hex.startsWith(JPEG_MAGIC_HEX)) return '.jpg'
  if (hex.startsWith(PNG_MAGIC_HEX)) return '.png'
  if (HEIC_BRAND.test(head.subarray(HEIC_BRAND_START).toString('latin1'))) return '.heic'
  return null
}

/** Prüft Größe und Format eines Bildes und liefert die passende Dateiendung. */
export function requireImage(buf: Uint8Array): ImageExt {
  if (buf.length > MAX_IMAGE_BYTES) throw new HttpError(HTTP_PAYLOAD_TOO_LARGE, `Bild ist zu groß (max. ${MAX_IMAGE_MB} MB)`)
  const ext = imageExt(buf)
  if (!ext) throw new HttpError(HTTP_UNSUPPORTED_MEDIA, 'Nur JPEG-, PNG- oder HEIC-Bilder sind erlaubt')
  return ext
}
