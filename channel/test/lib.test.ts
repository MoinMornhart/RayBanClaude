/**
 * Unit-Tests der reinen Hilfsfunktionen (Netzwerk, Gedächtnis). Läuft mit `bun test`.
 */

import { describe, expect, test } from 'bun:test'
import { MAX_MEMORY_ITEM_CHARS, MAX_MEMORY_ITEMS } from '../lib/constants.ts'
import { addFact, cleanMemoryItems, forgetFact, memoryBlock } from '../lib/memory.ts'
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
