/**
 * Gesprächsverlauf der Brille: eine Markdown-Datei pro Tag im Benutzerordner des PCs.
 *
 * Damit weiß Claude später noch, worüber ihr über die Brille gesprochen habt – in der
 * Claude-Desktop-App über das Werkzeug `brille_verlauf`. Tage, die älter als
 * HISTORY_DAYS sind, werden automatisch gelöscht. Der Verlauf verlässt den PC nicht.
 */

import { appendFileSync, existsSync, mkdirSync, readdirSync, readFileSync, unlinkSync } from 'fs'
import { join } from 'path'
import {
  HISTORY_DAYS, MAX_HISTORY_ENTRY_CHARS, MAX_HISTORY_READ_CHARS, MS_PER_DAY, PRIVATE_FILE_MODE,
} from './constants.ts'
import { ISO_DATE, LINE_BREAK } from './patterns.ts'
import { cleanText } from './validate.ts'

export type Speaker = 'du' | 'claude'

const SPEAKER_LABEL: Readonly<Record<Speaker, string>> = { du: 'Du', claude: 'Claude' }
const FILE_SUFFIX = '.md'
/** Schwedisches Datumsformat = JJJJ-MM-TT in Ortszeit */
const DAY_LOCALE = 'sv-SE'

export function dayStamp(date: Date): string {
  return date.toLocaleDateString(DAY_LOCALE)
}

function timeStamp(date: Date): string {
  return date.toLocaleTimeString('de-DE', { hour: '2-digit', minute: '2-digit' })
}

/** Eine Zeile an den Verlauf des Tages anhängen (Zeilenumbrüche werden zu Leerzeichen). */
export function appendHistory(dir: string, speaker: Speaker, raw: string, note = '', now: Date = new Date()): void {
  const text = cleanText(raw, MAX_HISTORY_ENTRY_CHARS).split(LINE_BREAK).join(' ')
  if (!text) return
  mkdirSync(dir, { recursive: true })
  const day = dayStamp(now)
  const file = join(dir, `${day}${FILE_SUFFIX}`)
  const header = existsSync(file) ? '' : `# Gespräche über die Brille – ${day}\n\n`
  appendFileSync(file, `${header}- ${timeStamp(now)} **${SPEAKER_LABEL[speaker]}:** ${text}${note}\n`, { mode: PRIVATE_FILE_MODE })
}

/** Tage mit Verlauf, älteste zuerst */
function historyDays(dir: string): string[] {
  if (!existsSync(dir)) return []
  return readdirSync(dir)
    .filter(name => name.endsWith(FILE_SUFFIX) && ISO_DATE.test(name.slice(0, -FILE_SUFFIX.length)))
    .map(name => name.slice(0, -FILE_SUFFIX.length))
    .sort()
}

/** Tage löschen, die älter als HISTORY_DAYS sind. */
export function pruneHistory(dir: string, now: Date = new Date()): number {
  const oldest = dayStamp(new Date(now.getTime() - HISTORY_DAYS * MS_PER_DAY))
  const expired = historyDays(dir).filter(day => day < oldest)
  expired.forEach(day => unlinkSync(join(dir, `${day}${FILE_SUFFIX}`)))
  return expired.length
}

/**
 * Verlauf der letzten `days` Tage, optional nur Zeilen mit dem Suchbegriff.
 * Wird es zu lang, bleiben die neuesten Einträge.
 */
export function readHistory(dir: string, days: number, query = ''): string {
  const needle = query.trim().toLocaleLowerCase('de-DE')
  const text = historyDays(dir)
    .slice(-days)
    .map(day => readFileSync(join(dir, `${day}${FILE_SUFFIX}`), 'utf8'))
    .map(content => needle ? filterLines(content, needle) : content)
    .filter(Boolean)
    .join('\n')
  return text.length > MAX_HISTORY_READ_CHARS ? `…\n${text.slice(-MAX_HISTORY_READ_CHARS)}` : text
}

function filterLines(content: string, needle: string): string {
  const lines = content.split(LINE_BREAK)
  const heading = lines.find(line => line.startsWith('# ')) ?? ''
  const hits = lines.filter(line => line.toLocaleLowerCase('de-DE').includes(needle))
  return hits.length ? [heading, ...hits].join('\n') : ''
}
