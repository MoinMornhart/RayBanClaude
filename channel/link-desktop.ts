#!/usr/bin/env bun
/**
 * Verknüpft RayBan Claude mit der Claude-Desktop-App auf diesem PC (oder hebt das auf).
 *
 *   bun link-desktop.ts           → trägt die Brücke (bridge.ts) in claude_desktop_config.json ein
 *   bun link-desktop.ts --remove  → trägt sie wieder aus
 *
 * Danach die Claude-App einmal neu starten. Unterstützt die normale Windows-Installation,
 * die Microsoft-Store-Version sowie macOS und Linux. Vor der ersten Änderung wird eine
 * Sicherungskopie der Konfiguration angelegt.
 */

import { copyFileSync, existsSync, readdirSync, readFileSync, writeFileSync } from 'fs'
import { homedir, platform } from 'os'
import { join } from 'path'
import { JSON_INDENT } from './lib/constants.ts'

const SERVER_KEY = 'raybanclaude-brille'
const CONFIG_NAME = 'claude_desktop_config.json'
const BACKUP_SUFFIX = '.vor-raybanclaude'
const STORE_PREFIX = 'Claude_'
const remove = process.argv.includes('--remove')

type Config = Record<string, unknown> & { mcpServers?: Record<string, unknown> }

/** Ordner der Claude-Desktop-App je Betriebssystem (nur die, die es wirklich gibt) */
function configDirs(): string[] {
  const home = homedir()
  const appData = process.env.APPDATA ?? join(home, 'AppData', 'Roaming')
  const localAppData = process.env.LOCALAPPDATA ?? join(home, 'AppData', 'Local')
  const packages = join(localAppData, 'Packages')
  const storeDirs = platform() === 'win32' && existsSync(packages)
    ? readdirSync(packages).filter(name => name.startsWith(STORE_PREFIX))
      .map(name => join(packages, name, 'LocalCache', 'Roaming', 'Claude'))
    : []
  const byPlatform: Readonly<Partial<Record<NodeJS.Platform, string[]>>> = {
    win32: [join(appData, 'Claude'), ...storeDirs],
    darwin: [join(home, 'Library', 'Application Support', 'Claude')],
    linux: [join(home, '.config', 'Claude')],
  }
  return (byPlatform[platform()] ?? []).filter(dir => existsSync(dir))
}

function readConfig(file: string): Config {
  if (!existsSync(file)) return {}
  const parsed: unknown = JSON.parse(readFileSync(file, 'utf8'))
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) throw new Error(`${file} ist kein JSON-Objekt`)
  return parsed as Config // geprüft: einfaches Objekt
}

function update(dir: string): string {
  const file = join(dir, CONFIG_NAME)
  const config = readConfig(file)
  const servers: Record<string, unknown> = { ...(config.mcpServers ?? {}) }
  if (remove) {
    delete servers[SERVER_KEY]
  } else {
    // Bun mit vollem Pfad – die Claude-App kennt den PATH der Kommandozeile nicht
    servers[SERVER_KEY] = { command: process.execPath, args: [join(import.meta.dir, 'bridge.ts')] }
  }
  if (existsSync(file) && !existsSync(file + BACKUP_SUFFIX)) copyFileSync(file, file + BACKUP_SUFFIX)
  writeFileSync(file, JSON.stringify({ ...config, mcpServers: servers }, null, JSON_INDENT) + '\n')
  return file
}

const dirs = configDirs()
if (!dirs.length) {
  console.log('Claude-Desktop-App nicht gefunden – überspringe die Verknüpfung (später: claude.ai/download, dann setup.cmd erneut).')
  process.exit(0)
}
try {
  const files = dirs.map(update)
  console.log(remove
    ? `Verknüpfung mit der Claude-App entfernt (${files.length} Konfiguration/en).`
    : `Mit der Claude-App verknüpft (${files.length} Konfiguration/en). Claude-App einmal neu starten – dann kennt sie das Werkzeug „Brille“.`)
} catch (e) {
  console.error(`Verknüpfung fehlgeschlagen: ${e instanceof Error ? e.message : String(e)}`)
  process.exit(1)
}
