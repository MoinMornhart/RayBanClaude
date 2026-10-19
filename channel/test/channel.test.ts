/**
 * End-to-End-Test des Channel-Servers: simuliert Claude Code (MCP über stdio)
 * und die iPhone-App (HTTP + WebSocket). Läuft mit `bun test`.
 */

import { afterAll, beforeAll, describe, expect, test } from 'bun:test'
import { mkdtempSync, rmSync } from 'fs'
import { tmpdir } from 'os'
import { join } from 'path'
import type { Subprocess } from 'bun'

const TEST_PORT = 18797
const BASE = `http://127.0.0.1:${TEST_PORT}`
const WAIT_MS = 5000
const POLL_MS = 50
const AUTH_ATTEMPTS = 10
const HTTP_OK = 200
const HTTP_ACCEPTED = 202
const HTTP_BAD_REQUEST = 400
const HTTP_UNAUTHORIZED = 401
const HTTP_FORBIDDEN = 403
const HTTP_UNSUPPORTED_MEDIA = 415
const HTTP_TOO_MANY = 429
const JSONRPC = '2.0'
const PROTOCOL = '2025-06-18'
const PERMISSION_ID = 'tbxkq'
/** Kleinstes Dummy-„JPEG“: Magic Bytes plus Füllbytes (der Server prüft nur den Header). */
const FAKE_JPEG = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, ...new Array(28).fill(0)]) // eslint-disable-line ts-patterns/no-magic-numbers

interface RpcMessage {
  readonly jsonrpc: string
  readonly id?: number
  readonly method?: string
  readonly params?: Record<string, unknown>
  readonly result?: Record<string, unknown>
}

const home = mkdtempSync(join(tmpdir(), 'raybanclaude-test-'))
const received: RpcMessage[] = []
const state = { rpcId: 0, buffer: '', token: '' }
let proc: Subprocess<'pipe', 'pipe', 'pipe'>

async function waitFor<TValue>(probe: () => TValue | undefined, label: string): Promise<TValue> {
  const deadline = Date.now() + WAIT_MS
  while (Date.now() < deadline) { // eslint-disable-line ts-patterns/no-loop-statements
    const value = probe()
    if (value !== undefined) return value
    await Bun.sleep(POLL_MS)
  }
  throw new Error(`Zeitüberschreitung: ${label}`)
}

function send(message: Record<string, unknown>): void {
  proc.stdin.write(JSON.stringify({ jsonrpc: JSONRPC, ...message }) + '\n')
  proc.stdin.flush()
}

async function rpc(method: string, params: Record<string, unknown> = {}): Promise<Record<string, unknown>> {
  state.rpcId++
  const id = state.rpcId
  send({ id, method, params })
  const reply = await waitFor(() => received.find(m => m.id === id), method)
  return reply.result ?? {}
}

async function readStdout(): Promise<void> {
  const decoder = new TextDecoder()
  // Zeilenweise JSON-RPC-Nachrichten einsammeln
  await proc.stdout.pipeTo(new WritableStream({
    write(chunk) {
      state.buffer += decoder.decode(chunk)
      const lines = state.buffer.split('\n')
      state.buffer = lines.pop() ?? ''
      lines.filter(Boolean).forEach(line => received.push(JSON.parse(line)))
    },
  }))
}

function notification(method: string, match: (p: Record<string, unknown>) => boolean): Promise<Record<string, unknown>> {
  return waitFor(() => received.find(m => m.method === method && match(m.params ?? {}))?.params, method)
}

function authed(path: string, init: RequestInit = {}): Promise<Response> {
  return fetch(BASE + path, { ...init, headers: { Authorization: `Bearer ${state.token}`, ...(init.headers ?? {}) } })
}

async function openSocket(): Promise<{ ws: WebSocket; inbox: Record<string, unknown>[] }> {
  const inbox: Record<string, unknown>[] = []
  const ws = new WebSocket(`ws://127.0.0.1:${TEST_PORT}/ws`, { headers: { Authorization: `Bearer ${state.token}` } })
  ws.onmessage = ev => inbox.push(JSON.parse(String(ev.data)))
  await waitFor(() => inbox.find(m => m.type === 'status'), 'WS-Status')
  return { ws, inbox }
}

beforeAll(async () => {
  proc = Bun.spawn([process.execPath, join(import.meta.dir, '..', 'server.ts')], {
    stdin: 'pipe',
    stdout: 'pipe',
    stderr: 'pipe',
    env: { ...process.env, HOME: home, USERPROFILE: home, RAYBANCLAUDE_PORT: String(TEST_PORT), RAYBANCLAUDE_NO_BROWSER: '1' },
  })
  void readStdout()
  await rpc('initialize', { protocolVersion: PROTOCOL, capabilities: {}, clientInfo: { name: 'test', version: '1' } })
  send({ method: 'notifications/initialized' })
  await waitForHealth()
})

async function waitForHealth(): Promise<void> {
  const deadline = Date.now() + WAIT_MS
  while (Date.now() < deadline) { // eslint-disable-line ts-patterns/no-loop-statements
    const ok = await fetch(`${BASE}/health`).then(r => r.ok, () => false)
    if (ok) return
    await Bun.sleep(POLL_MS)
  }
  throw new Error('HTTP-Server startet nicht')
}

afterAll(() => {
  proc?.kill()
  rmSync(home, { recursive: true, force: true })
})

describe('MCP-Seite', () => {
  test('meldet Channel- und Permission-Capability sowie drei Tools', async () => {
    const init = received.find(m => m.id === 1)?.result ?? {}
    const caps = (init.capabilities ?? {}) as Record<string, Record<string, unknown>>
    expect(caps.experimental?.['claude/channel']).toEqual({})
    expect(caps.experimental?.['claude/channel/permission']).toEqual({})
    const tools = (await rpc('tools/list')).tools as { name: string }[]
    expect(tools.map(t => t.name).sort()).toEqual(['edit_message', 'reply', 'request_photo'])
  })
})

describe('HTTP-Sicherheit', () => {
  test('/health ist öffentlich, verrät aber nichts', async () => {
    const res = await fetch(`${BASE}/health`)
    expect(res.status).toBe(HTTP_OK)
    expect(await res.json()).toEqual({ status: 'ok', mode: 'channel', auth: 'required' })
    expect(res.headers.get('x-content-type-options')).toBe('nosniff')
    expect(res.headers.get('access-control-allow-origin')).toBeNull()
  })

  test('/api/local liefert das Token nur an localhost mit passendem Host-Header', async () => {
    const ok = await fetch(`${BASE}/api/local`)
    expect(ok.status).toBe(HTTP_OK)
    const local = (await ok.json()) as { token: string } // Antwortform von /api/local
    state.token = local.token
    // 48 Hex-Zeichen (24 Zufallsbytes). Passt: "ab12…" (48 Zeichen); lehnt ab: "kurz".
    // https://regex101.com/?flavor=javascript&regex=%5E%5B0-9a-f%5D%7B48%7D%24&flags=m&testString=0123456789abcdef0123456789abcdef0123456789abcdef%0Akurz
    expect(state.token).toMatch(/^[0-9a-f]{48}$/)
    const rebinding = await fetch(`${BASE}/api/local`, { headers: { Host: 'evil.example' } })
    expect(rebinding.status).toBe(HTTP_FORBIDDEN)
    const foreignOrigin = await fetch(`${BASE}/api/local`, { headers: { Origin: 'http://evil.example' } })
    expect(foreignOrigin.status).toBe(HTTP_FORBIDDEN)
  })

  test('geschützte Routen verlangen das Token', async () => {
    expect((await fetch(`${BASE}/api/status`)).status).toBe(HTTP_UNAUTHORIZED)
    expect((await authed('/api/status')).status).toBe(HTTP_OK)
  })

  test('Token in der URL wird nicht akzeptiert (nur Authorization-Header)', async () => {
    const res = await fetch(`${BASE}/ws?token=${state.token}`)
    expect(res.status).toBe(HTTP_UNAUTHORIZED)
  })

  test('Pfad-Traversal bei /files wird abgewiesen', async () => {
    const res = await authed('/files/..%2F.channel-token')
    expect(res.status).toBe(HTTP_BAD_REQUEST)
  })

  test('Upload ohne echtes Bild wird abgewiesen', async () => {
    const form = new FormData()
    form.set('text', 'Test')
    form.set('image', new Blob(['<?php echo 1; ?> kein bild hier']), 'x.jpg')
    expect((await authed('/upload', { method: 'POST', body: form })).status).toBe(HTTP_UNSUPPORTED_MEDIA)
  })
})

describe('Nachrichtenfluss App ↔ Claude', () => {
  test('Text + Bild per WebSocket landen als Channel-Notification bei Claude', async () => {
    const { ws, inbox } = await openSocket()
    ws.send(JSON.stringify({ id: 'ios-1', text: 'Was siehst du?', source: 'rayban', mode: 'Allgemein', mode_prompt: 'Sei hilfreich.', image: Buffer.from(FAKE_JPEG).toString('base64') }))
    const params = await notification('notifications/claude/channel', p => (p.meta as Record<string, string>)?.message_id === 'ios-1')
    const meta = params.meta as Record<string, string>
    expect(meta.device).toBe('rayban')
    expect(meta.mode).toBe('Allgemein')
    expect(meta.file_path).toContain('rayban.jpg')
    expect(String(params.content)).toContain('[Modus „Allgemein“: Sei hilfreich.]')
    await waitFor(() => inbox.find(m => m.type === 'ack' && m.id === 'ios-1'), 'ack')
    ws.close()
  })

  test('reply-Tool erreicht die App', async () => {
    const { ws, inbox } = await openSocket()
    const result = await rpc('tools/call', { name: 'reply', arguments: { text: 'Ein roter Apfel.', reply_to: 'ios-1' } })
    expect(result.isError).toBeFalsy()
    const reply = await waitFor(() => inbox.find(m => m.type === 'reply'), 'reply')
    expect(reply.text).toBe('Ein roter Apfel.')
    expect(reply.reply_to).toBe('ios-1')
    ws.close()
  })

  test('request_photo → App lädt Foto hoch → Claude erhält es mit request_id', async () => {
    const { ws, inbox } = await openSocket()
    await rpc('tools/call', { name: 'request_photo', arguments: { reason: 'Text lesen' } })
    const request = await waitFor(() => inbox.find(m => m.type === 'capture_request'), 'capture_request')
    const form = new FormData()
    form.set('source', 'rayban')
    form.set('in_reply_to', String(request.id))
    form.set('image', new Blob([FAKE_JPEG], { type: 'image/jpeg' }), 'foto.jpg')
    expect((await authed('/upload', { method: 'POST', body: form })).status).toBe(HTTP_ACCEPTED)
    const params = await notification('notifications/claude/channel', p => (p.meta as Record<string, string>)?.request_id === request.id)
    expect(params.content).toBe('(angefordertes Foto)')
    ws.close()
  })

  test('Permission-Relay: Freigabe-Anfrage aufs Handy, Antwort zurück an Claude', async () => {
    const { ws, inbox } = await openSocket()
    send({ method: 'notifications/claude/channel/permission_request', params: { request_id: PERMISSION_ID, tool_name: 'Bash', description: 'Liste Dateien', input_preview: 'ls' } })
    const ask = await waitFor(() => inbox.find(m => m.type === 'permission_request'), 'permission_request')
    expect(ask.tool_name).toBe('Bash')
    ws.send(JSON.stringify({ type: 'permission', request_id: PERMISSION_ID, behavior: 'allow' }))
    const verdict = await notification('notifications/claude/channel/permission', p => p.request_id === PERMISSION_ID)
    expect(verdict.behavior).toBe('allow')
    ws.close()
  })
})

describe('Brute-Force-Schutz', () => {
  test(`nach ${AUTH_ATTEMPTS} falschen Tokens wird gesperrt`, async () => {
    const attempts = Array.from({ length: AUTH_ATTEMPTS }, () =>
      fetch(`${BASE}/api/status`, { headers: { Authorization: 'Bearer falsch' } }))
    await Promise.all(attempts)
    const locked = await fetch(`${BASE}/api/status`, { headers: { Authorization: `Bearer ${state.token}` } })
    expect(locked.status).toBe(HTTP_TOO_MANY)
  })
})

describe('Lebenszyklus', () => {
  test('Prozess endet, wenn Claude Code die Verbindung schließt (kein verwaister Port)', async () => {
    proc.stdin.end()
    const code = await Promise.race([proc.exited, Bun.sleep(WAIT_MS).then(() => 'timeout')])
    expect(code).toBe(0)
  })
})
