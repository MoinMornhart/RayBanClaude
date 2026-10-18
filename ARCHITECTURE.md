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
am Handy), `error`.

## Komponenten

| Komponente | Datei(en) | Aufgabe |
|---|---|---|
| Channel-Server | `channel/server.ts` | MCP-Channel, Routen-Tabelle mit Zugriffsstufen (public/local/token/admin), WebSocket |
| Hilfsmodule | `channel/lib/*.ts` | Konstanten, Regex mit Beispielen, Validierung, LAN-IP-Erkennung |
| Dashboard | `channel/dashboard.*` | QR-Kopplung, Aktivität, Stimme; nur `localhost`, strikte CSP |
| Gateway | `server/src/*.ts` | Alternative ohne Claude Code: Claude-API + MCP-Client + Skills |
| `RayBanManager` | `ios/…/Services/RayBanManager.swift` | DAT 1.0.1: Registrierung, Session, Kamera, Stream, Foto, Gerätezustand |
| `CameraManager` | `ios/…/Services/CameraManager.swift` | iPhone-Kamera, JPEG-Drosselung, QR-/Barcodes |
| `SpeechManager` | `ios/…/Services/SpeechManager.swift` | Spracherkennung (on-device), Sprachausgabe |
| `ClaudeBridge` | `ios/…/Services/ClaudeBridge.swift` | WebSocket/REST, Reconnect mit Backoff, Token-Header |
| `SessionViewModel` | `ios/…/ViewModels/SessionViewModel.swift` | Ablaufsteuerung, Timeouts, Kopplung, Freigaben |

## Zugriffsstufen im Channel-Server

| Stufe | Bedingung | Routen |
|---|---|---|
| public | keine | `GET /health` (nur „ok“) |
| local | Loopback-IP + Host/Origin = localhost | Dashboard, `/api/local` (Token, IPs), `/api/pair.svg` |
| token | gültiges Bearer-Token | `/ws`, `/upload`, `/message`, `/files/*`, `/api/status`, `/api/activity` |
| admin | local **und** token | `/api/tts`, `/api/test-message`, `/api/send-imessage` |

## Ray-Ban Meta Gen 2 – Besonderheiten

- Stream mit 720p bei 15 fps (sauberere Einzelbilder über Bluetooth als 30 fps).
- Audio-Session wird **einmal** auf `.playAndRecord` + HFP gestellt und vor `stream.start()`
  ca. 2 s „gesetzt“ – häufiges Umschalten führt laut Meta bei Gen 2 zu „Device unavailable“.
- Geschlossene Bügel beenden die Session; beim Aufklappen baut die App sie neu auf.
- Fotos per `stream.capturePhoto(format: .jpeg)` – Video pausiert kurz.
