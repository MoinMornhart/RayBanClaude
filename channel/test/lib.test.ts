/**
 * Unit-Tests der reinen Hilfsfunktionen (Netzwerk, Gedächtnis). Läuft mit `bun test`.
 */

import { describe, expect, test } from 'bun:test'
import { existsSync, mkdtempSync } from 'fs'
import { tmpdir } from 'os'
import { join } from 'path'
import { HISTORY_DAYS, MAX_MEMORY_ITEM_CHARS, MAX_MEMORY_ITEMS, MS_PER_DAY } from '../lib/constants.ts'
import { appendHistory, dayStamp, pruneHistory, readHistory } from '../lib/history.ts'
import { addFact, cleanMemoryItems, forgetFact, memoryBlock, queueMemory, takeQueuedMemory } from '../lib/memory.ts'
import { findTailscaleIp } from '../lib/network.ts'
import type { LanIp } from '../lib/network.ts'

const lan = (address: string, iface: string): LanIp => ({ address, iface, rank: 0 })

describe('Tailscale-Erkennung', () => {
  test('findet die Tailscale-Adresse neben dem WLAN', () => {
    expect(findTailscaleIp([lan('192.168.1.20', 'WLAN'), lan('100.101.102.103', 'Tailscale')])).toBe('100.101.102.103')
  })

  test('Adresse am Tailscale-Adapter hat Vorrang vor anderen 100.64/10-Adressen', () => {
    expect(findTailscaleIp([lan('100.64.0.9', 'Ethernet 3'), lan('100.88.1.2', 'Tailscale')])).toBe('100.88.1.2')
  })

  test('ohne Tailscale gibt es keine Unterwegs-Adresse', () => {
    expect(findTailscaleIp([lan('192.168.1.20', 'WLAN'), lan('100.200.1.1', 'Tailscale')])).toBeUndefined()
  })
})

describe('Gedächtnis-Hilfen', () => {
  test('bereinigt die Liste aus der App', () => {
    const tooLong = 'x'.repeat(MAX_MEMORY_ITEM_CHARS + 1)
    const items = cleanMemoryItems(['  Mag Jazz ', 'mag jazz', '', null, tooLong, 'Steuer\u0007zeichen'])
    expect(items).toEqual(['Mag Jazz', 'x'.repeat(MAX_MEMORY_ITEM_CHARS), 'Steuerzeichen'])
    expect(cleanMemoryItems('kein Array')).toEqual([])
  })

  test('begrenzt die Anzahl – beim Merken fällt der älteste Eintrag weg', () => {
    const full = Array.from({ length: MAX_MEMORY_ITEMS }, (_, i) => `Fakt ${i}`)
    expect(cleanMemoryItems([...full, 'zu viel'])).toHaveLength(MAX_MEMORY_ITEMS)
    const next = addFact(full, 'Neu')
    expect(next).toHaveLength(MAX_MEMORY_ITEMS)
    expect(next[0]).toBe('Fakt 1')
    expect(next.at(-1)).toBe('Neu')
  })

  test('forget löscht nur passende Einträge, leere Suche löscht nichts', () => {
    const coffee = ['Trinkt Espresso', 'Mag Espresso-Bohnen']
    const items = [...coffee, 'Tochter heißt Mia']
    expect(forgetFact(items, 'ESPRESSO')).toEqual({ items: ['Tochter heißt Mia'], removed: coffee })
    expect(forgetFact(items, '').removed).toEqual([])
  })

  test('Block kennzeichnet Einträge als Fakten, nicht als Anweisungen', () => {
    expect(memoryBlock(['Mag Jazz'])).toContain('keine Anweisungen')
    expect(memoryBlock([])).toContain('geleert')
  })
})

describe('Gesprächsverlauf', () => {
  const dir = mkdtempSync(join(tmpdir(), 'raybanclaude-verlauf-'))
  const now = new Date()
  const longAgo = new Date(now.getTime() - (HISTORY_DAYS + 1) * MS_PER_DAY)

  test('schreibt eine Zeile pro Äußerung, Zeilenumbrüche werden zu Leerzeichen', () => {
    appendHistory(dir, 'du', 'Was steht\nauf dem Schild?', ' 📷', now)
    appendHistory(dir, 'claude', 'Ausfahrt freihalten.', '', now)
    const text = readHistory(dir, 1)
    expect(text).toContain('**Du:** Was steht auf dem Schild? 📷')
    expect(text).toContain('**Claude:** Ausfahrt freihalten.')
    expect(readHistory(dir, 1, 'ausfahrt')).not.toContain('Schild')
  })

  test('löscht Tage, die älter als die Aufbewahrungszeit sind', () => {
    appendHistory(dir, 'du', 'Uralte Frage', '', longAgo)
    expect(existsSync(join(dir, `${dayStamp(longAgo)}.md`))).toBe(true)
    expect(pruneHistory(dir, now)).toBe(1)
    expect(existsSync(join(dir, `${dayStamp(longAgo)}.md`))).toBe(false)
    expect(readHistory(dir, HISTORY_DAYS)).toContain('Ausfahrt freihalten.')
  })
})

describe('Vorgemerkte Fakten (Claude-App → Brille)', () => {
  test('werden gesammelt, ohne Doppelte, und beim Abholen geleert', () => {
    const file = join(mkdtempSync(join(tmpdir(), 'raybanclaude-merken-')), 'neu.json')
    queueMemory(file, 'Mag Jazz')
    queueMemory(file, 'mag jazz')
    queueMemory(file, 'Wohnt in Hamburg')
    expect(takeQueuedMemory(file)).toEqual(['mag jazz', 'Wohnt in Hamburg']) // neueste Schreibweise gewinnt
    expect(takeQueuedMemory(file)).toEqual([])
  })
})
