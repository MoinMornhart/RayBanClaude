// RayBan Claude – Dashboard (läuft nur auf http://localhost, siehe server.ts)
'use strict'

const REFRESH_MS = 3000
const COPY_FEEDBACK_MS = 1800
const state = { token: '', port: 0, host: '', tailscale: '' }

const $ = id => document.getElementById(id)

function setStatus(el, text, kind) {
  el.textContent = text
  el.className = 'hint' + (kind ? ' ' + kind : '')
}

async function api(path, options = {}) {
  const res = await fetch(path, {
    ...options,
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + state.token, ...(options.headers || {}) },
  })
  const data = await res.json().catch(() => ({}))
  if (!res.ok) throw new Error(data.error || 'Fehler ' + res.status)
  return data
}

async function copyText(text, button) {
  await navigator.clipboard.writeText(text)
  const original = button.textContent
  button.textContent = 'Kopiert ✓'
  setTimeout(() => { button.textContent = original }, COPY_FEEDBACK_MS)
}

function renderPairing() {
  $('host').textContent = state.host
  $('port').textContent = String(state.port)
  $('token').textContent = state.token
  const img = $('qr')
  img.src = '/api/pair.svg?host=' + encodeURIComponent(state.host)
  img.onload = () => setStatus($('qr-hint'), 'Mit der iPhone-Kamera scannen')
  img.onerror = () => setStatus($('qr-hint'), 'QR-Code konnte nicht erzeugt werden', 'bad')
  renderRemote()
}

/** Zeigt, ob das iPhone den PC auch unterwegs (über Tailscale) erreicht. */
function renderRemote() {
  const hint = $('remote-hint')
  if (!state.tailscale) {
    setStatus(hint, '🌍 Unterwegs: Tailscale nicht gefunden. Installiere Tailscale (kostenlos) auf PC und iPhone und lade diese Seite neu – siehe README „Unterwegs“.')
    return
  }
  if (state.tailscale === state.host) {
    setStatus(hint, '🌍 Du koppelst direkt über Tailscale (' + state.tailscale + ') – klappt zu Hause und unterwegs.', 'ok')
    return
  }
  setStatus(hint, '🌍 Unterwegs: über Tailscale (' + state.tailscale + ') – steckt schon im QR-Code. Zu Hause nimmt die App das WLAN, unterwegs automatisch Tailscale.', 'ok')
}

function renderBadges(status) {
  const clients = status.clients || 0
  $('badge-clients').innerHTML = ''
  const dot = document.createElement('span')
  dot.className = 'dot ' + (clients ? 'ok' : 'warn')
  $('badge-clients').append(dot, document.createTextNode(clients === 1 ? '1 App verbunden' : clients + ' Apps verbunden'))

  $('badge-voice').innerHTML = ''
  const vdot = document.createElement('span')
  vdot.className = 'dot ok'
  $('badge-voice').append(vdot, document.createTextNode(status.tts ? 'Stimme: ElevenLabs' : 'Stimme: iPhone (kostenlos)'))
  if (status.voice) $('eleven-voice').value = status.voice
}

function renderActivity(entries) {
  const list = $('activity')
  list.replaceChildren()
  if (!entries.length) {
    const li = document.createElement('li')
    li.className = 'hint'
    li.textContent = 'Noch keine Nachrichten.'
    list.append(li)
    return
  }
  entries.forEach(e => {
    const li = document.createElement('li')
    const t = document.createElement('span')
    t.className = 't'
    t.textContent = new Date(e.ts).toLocaleTimeString('de-DE')
    const who = document.createElement('span')
    who.className = e.direction === 'in' ? 'in' : 'out'
    who.textContent = (e.direction === 'in' ? '← ' : '→ ') + e.source + (e.hasImage ? ' 📷' : '')
    const text = document.createElement('span')
    text.textContent = e.text // textContent: kein HTML aus Nachrichten (XSS-Schutz)
    li.append(t, who, text)
    list.append(li)
  })
}

async function refresh() {
  try {
    renderBadges(await api('/api/status'))
    renderActivity((await api('/api/activity')).activity || [])
  } catch (e) {
    console.warn('Aktualisierung fehlgeschlagen', e)
  }
}

async function init() {
  const res = await fetch('/api/local')
  if (!res.ok) {
    document.body.textContent = 'Das Dashboard ist nur direkt auf dem PC unter http://localhost erreichbar.'
    return
  }
  const local = await res.json()
  state.token = local.token
  state.port = local.port
  state.tailscale = local.tailscale || ''
  $('version').textContent = 'v' + local.version

  const select = $('ip-select')
  const ips = local.ips.length ? local.ips : [{ address: 'localhost', iface: 'kein Netzwerk gefunden' }]
  ips.forEach(ip => {
    const opt = document.createElement('option')
    opt.value = ip.address
    opt.textContent = ip.address + ' – ' + ip.iface
    select.append(opt)
  })
  state.host = ips[0].address
  select.addEventListener('change', () => { state.host = select.value; renderPairing() })
  renderPairing()

  $('card-imessage').hidden = !local.imessage

  $('btn-reveal').addEventListener('click', ev => {
    const shown = $('token').classList.toggle('shown')
    ev.target.textContent = shown ? 'Token verbergen' : 'Token zeigen'
  })
  $('btn-copy').addEventListener('click', ev =>
    copyText('Host: ' + state.host + '\nPort: ' + state.port + '\nToken: ' + state.token
      + (state.tailscale && state.tailscale !== state.host ? '\nUnterwegs (Tailscale): ' + state.tailscale : ''), ev.target))
  document.querySelectorAll('[data-copy]').forEach(btn =>
    btn.addEventListener('click', () => copyText($(btn.dataset.copy).textContent, btn)))

  $('btn-test').addEventListener('click', async () => {
    const status = $('test-status')
    try {
      const r = await api('/api/test-message', { method: 'POST', body: JSON.stringify({ text: $('test-text').value }) })
      setStatus(status, r.delivered_to ? 'Zugestellt an ' + r.delivered_to + ' App(s) ✓' : 'Keine App verbunden – erst koppeln', r.delivered_to ? 'ok' : 'bad')
    } catch (e) { setStatus(status, e.message, 'bad') }
  })

  const saveTts = async body => {
    const status = $('tts-status')
    try {
      const r = await api('/api/tts', { method: 'POST', body: JSON.stringify(body) })
      $('eleven-key').value = ''
      setStatus(status, r.tts ? 'ElevenLabs aktiv ✓' : 'iPhone-Stimme aktiv (kostenlos) ✓', 'ok')
      refresh()
    } catch (e) { setStatus(status, e.message, 'bad') }
  }
  $('btn-tts').addEventListener('click', () => {
    const key = $('eleven-key').value.trim()
    saveTts(key ? { key, voice_id: $('eleven-voice').value } : { voice_id: $('eleven-voice').value })
  })
  $('btn-tts-off').addEventListener('click', () => saveTts({ key: '' }))

  $('btn-im').addEventListener('click', async () => {
    const status = $('im-status')
    try {
      const { link } = await api('/api/pair-link?host=' + encodeURIComponent(state.host))
      const message = 'RayBan Claude koppeln:\n' + link
      await api('/api/send-imessage', { method: 'POST', body: JSON.stringify({ recipient: $('im-recipient').value, message }) })
      setStatus(status, 'Gesendet ✓ – Link auf dem iPhone antippen', 'ok')
    } catch (e) { setStatus(status, e.message, 'bad') }
  })

  refresh()
  setInterval(refresh, REFRESH_MS)
}

init()
