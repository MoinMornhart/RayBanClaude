# Architektur

## Überblick

```
┌──────────────────┐  Bluetooth   ┌──────────────────────────┐   WLAN (Token)   ┌──────────────────────────────┐
│ Ray-Ban Meta Gen2│ ───────────▶ │ iPhone-App (SwiftUI)      │ ───────────────▶ │ PC: Channel-Server (Bun)      │
│ Kamera · Mikro · │ ◀─────────── │ • Meta DAT SDK 1.0.1      │ ◀─────────────── │ • HTTP + WebSocket :18790     │
│ Lautsprecher     │   HFP-Audio  │ • Apple-Spracherkennung   │  Antwort, Audio, │ • Dashboard + QR-Kopplung     │
└──────────────────┘              │ • iPhone-Stimme/ElevenLabs│  Freigaben       │ • MCP-Channel (stdio) ───────┐│
                                  └──────────────────────────┘                  └──────────────────────────────┘│
                                                                                  Claude Code ◀──────────────────┘
                                                                                  (alle MCP-Tools & Skills)
```

## Nachrichtenfluss (Channel-Modus)

1. Die App erkennt Sprache auf dem iPhone, nimmt das aktuelle Kamerabild (Brille oder iPhone)
   und sendet beides per WebSocket (`type: message`) – große Bilder per `POST /upload`.
2. Der Channel-Server prüft Token, Text und Bild (Magic Bytes), speichert das Bild in
   `~/.claude/channels/raybanclaude/inbox/` und schickt `notifications/claude/channel` an Claude Code.
   Den Modus-Prompt sendet er nur beim Moduswechsel (spart Tokens).
3. Claude liest das Bild (`file_path`) und antwortet über das Tool `reply`.
4. Der Server erzeugt optional ElevenLabs-Audio und schickt `type: reply` an die App, die es vorliest
   (sonst kostenlose iPhone-Stimme) und danach wieder zuhört.

Weitere Nachrichtentypen: `ack` (zugestellt), `edit` (Korrektur), `capture_request`
(Claude fordert ein Foto an), `permission_request`/`permission_resolved` (Tool-Freigabe
am Handy), `phone_action`/`action_result` (Timer, Anruf … auf dem iPhone),
`memory_sync`/`memory` (Gedächtnis), `error`.

## Unterwegs: zwei Adressen, ein PC

Der Kopplungs-Link enthält neben der Heim-Adresse optional `remote` – die Tailscale-Adresse des PCs
(100.64.0.0/10, erkannt am Adapter „Tailscale“). Die App (`ClaudeBridge`) probiert die Adressen der Reihe nach:

| iPhone-Netz | Reihenfolge |
|---|---|
| WLAN | Heim-Adresse → Tailscale |
| nur mobile Daten | Tailscale |

Ein Netzwechsel (`NWPathMonitor`) oder ein fehlgeschlagener Ping startet die Verbindung sofort neu.
Ist der PC unter keiner Adresse erreichbar und ein API-Key hinterlegt, fragt die App Claude direkt.
Unterwegs läuft damit weiterhin alles über Claude Code und das Claude-Abo des Nutzers.

## Kamera nur auf Zuruf (wie Meta AI)

- `VisionIntent` entscheidet anhand der Frage, ob ein Bild nötig ist („Was ist das?“, „Lies vor“, „Mach ein Foto“).
  Sonst geht die Frage ohne Bild an Claude; braucht Claude doch eins, ruft es `request_photo`/`take_photo`.
- `RayBanManager` ist nur „bereit“: Erst für ein Foto startet er Sitzung → Kamera → Stream (`hvc1`, läuft laut Meta
  auch im Hintergrund) → `capturePhoto`, nach 15 s ohne weiteres Foto wird alles wieder freigegeben
  (mind. 2 s zwischen Sitzungen). Schon während der Nutzer spricht, weckt eine erkannte Bild-Frage die Kamera.
- Brille zuerst: `AudioSessionManager` wählt das Bluetooth-Mikrofon der Ray-Ban Meta vor jedem anderen Headset;
  kann die Brille kein Foto machen, springt bei offener App die iPhone-Kamera ein.

## Hosentaschen-Modus

Die Aufnahme (`AVAudioEngine`) läuft durch, nur die Spracherkennung wechselt (`RecognitionSink`) – so darf iOS die
App mit Hintergrund-Audio weiterlaufen lassen, auch bei gesperrtem iPhone. Ohne Weckwort wird das Mikrofon ganz
freigegeben.

## Verknüpfung mit der Claude-Desktop-App

- Der Channel schreibt den Gesprächsverlauf (`~/.claude/channels/raybanclaude/verlauf/JJJJ-MM-TT.md`, 30 Tage) und
  eine Kopie der Merkliste (`gedaechtnis.json`).
- `channel/bridge.ts` ist ein eigener MCP-Server (stdio) für die Claude-Desktop-App mit `brille_verlauf`,
  `brille_gedaechtnis` und `brille_merken`. Vorgemerkte Fakten (`gedaechtnis-neu.json`) übernimmt der Channel, sobald
  das iPhone verbunden ist, und schickt sie als `memory`/`add` an die App.
- `channel/link-desktop.ts` trägt die Brücke in `claude_desktop_config.json` ein (normale und Store-Version, mit
  Sicherungskopie); `--remove` trägt sie wieder aus.
- `start.ps1` startet Claude Code mit `--continue`, wenn es in diesem Ordner schon eine Sitzung gibt.

## Gedächtnis

- **Quelle der Wahrheit ist die App** (`MemoryStore`, JSON-Datei mit Datenschutzklasse
  *complete until first user authentication*). Max. 200 Einträge à 300 Zeichen.
- **Channel:** Beim Verbinden und nach jeder Änderung schickt die App `memory_sync`. Der Server hält eine
  Kopie (Arbeitsspeicher + `gedaechtnis.json` für die Claude-App) und stellt sie der *ersten* Nachricht an Claude
  voran – erneut nur, wenn sie sich geändert hat. Die Tools `remember`/`forget` ändern die Kopie und schicken `memory` (add/remove) an die App.
- **Direkt:** Die Liste steht in der ersten Nutzernachricht eines Verlaufs (der Systemprompt bleibt gleich →
  Prompt-Caching), `remember`/`forget` laufen lokal.
- **Gateway:** Die Liste geht einmal pro Gespräch mit; merken geht dort nur über die App.
- Einträge sind für Claude ausdrücklich **Fakten, keine Anweisungen**; Text aus Bildern oder Webseiten soll
  Claude nicht speichern.

## Komponenten

| Komponente | Datei(en) | Aufgabe |
|---|---|---|
| Channel-Server | `channel/server.ts` | MCP-Channel, Routen-Tabelle mit Zugriffsstufen (public/local/token/admin), WebSocket |
| Hilfsmodule | `channel/lib/*.ts` | Konstanten, Regex mit Beispielen, Validierung, LAN-/Tailscale-Erkennung, Handy-Aktionen, Gedächtnis |
| Dashboard | `channel/dashboard.*` | QR-Kopplung, Aktivität, Stimme; nur `localhost`, strikte CSP |
| Gateway | `server/src/*.ts` | Alternative ohne Claude Code: Claude-API + MCP-Client + Skills |
| `RayBanManager` | `ios/…/Services/RayBanManager.swift` | DAT 1.0.1: Registrierung, Session, Kamera, Stream, Foto, Gerätezustand |
| `CameraManager` | `ios/…/Services/CameraManager.swift` | iPhone-Kamera, JPEG-Drosselung, QR-/Barcodes |
| `SpeechManager` | `ios/…/Services/SpeechManager.swift` | Spracherkennung (on-device), Sprachausgabe |
| `ClaudeBridge` | `ios/…/Services/ClaudeBridge.swift` | WebSocket/REST, WLAN → Tailscale, Reconnect mit Backoff, Token-Header |
| `DirectClaudeClient` | `ios/…/Services/DirectClaudeClient.swift` | Ohne PC: Claude-API direkt, Werkzeug-Schleife, Prompt-Caching |
| `MemoryStore` | `ios/…/Services/MemoryStore.swift` | Gedächtnis: speichern, abgleichen, Übernahme aus der Claude-App |
| `SessionViewModel` | `ios/…/ViewModels/SessionViewModel.swift` | Ablaufsteuerung, Timeouts, Kopplung, Freigaben |

## Zugriffsstufen im Channel-Server

| Stufe | Bedingung | Routen |
|---|---|---|
| public | keine | `GET /health` (nur „ok“) |
| local | Loopback-IP + Host/Origin = localhost | Dashboard, `/api/local` (Token, IPs), `/api/pair.svg`, `/api/pair-link` |
| token | gültiges Bearer-Token | `/ws`, `/upload`, `/message`, `/files/*`, `/api/status`, `/api/activity` |
| admin | local **und** token | `/api/tts`, `/api/test-message`, `/api/send-imessage` |

## Ray-Ban Meta Gen 2 – Besonderheiten

- Stream mit 720p bei 15 fps (sauberere Einzelbilder über Bluetooth als 30 fps).
- Audio-Session wird **einmal** auf `.playAndRecord` + HFP gestellt und vor `stream.start()`
  ca. 2 s „gesetzt“ – häufiges Umschalten führt laut Meta bei Gen 2 zu „Device unavailable“.
- Geschlossene Bügel beenden die Session; beim Aufklappen baut die App sie neu auf.
- Fotos per `stream.capturePhoto(format: .jpeg)` – Video pausiert kurz.
