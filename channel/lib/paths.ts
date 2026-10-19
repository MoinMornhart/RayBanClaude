/**
 * Ablageorte im Benutzerordner des PCs (gemeinsam für Channel und Claude-App-Brücke).
 */

import { homedir } from 'os'
import { join } from 'path'
import { SERVER_NAME } from './constants.ts'

export const STATE_DIR = join(homedir(), '.claude', 'channels', SERVER_NAME)
/** Gesprächsverlauf der Brille – eine Markdown-Datei pro Tag */
export const HISTORY_DIR = join(STATE_DIR, 'verlauf')
/** Kopie der Merkliste (Quelle der Wahrheit bleibt die iPhone-App) */
export const MEMORY_FILE = join(STATE_DIR, 'gedaechtnis.json')
/** Von der Claude-App vorgemerkte Fakten – die Brille übernimmt sie beim nächsten Verbinden */
export const PENDING_MEMORY_FILE = join(STATE_DIR, 'gedaechtnis-neu.json')
