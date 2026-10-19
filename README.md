# ◉ RayBan Claude

**Claude sieht, was du siehst.** Deine **Ray-Ban Meta (Gen 2)** oder dein iPhone werden zu
Augen und Ohren deiner Claude-Code-Sitzung: Du sprichst, Claude schaut durch die Brille,
antwortet per Stimme – und kann dabei alle deine MCP-Tools und Skills nutzen.

[![iOS-App bauen](https://github.com/MoinMornhart/RayBanClaude/actions/workflows/ios-build.yml/badge.svg)](https://github.com/MoinMornhart/RayBanClaude/actions/workflows/ios-build.yml)
[![Server testen](https://github.com/MoinMornhart/RayBanClaude/actions/workflows/server-tests.yml/badge.svg)](https://github.com/MoinMornhart/RayBanClaude/actions/workflows/server-tests.yml)

- 🪟 **Läuft mit Windows-PCs** (auch macOS/Linux)
- 💸 **Kostenlos**: nutzt dein Claude-Abo, kostenlose iPhone-Stimme, App ohne Mac und ohne Entwicklerkonto
- 📷 **Ray-Ban Meta Gen 2** über das offizielle Meta Wearables SDK 1.0.1
- 🇩🇪 Deutsche Oberfläche, Spracherkennung und Stimme

> Inoffizielles Open-Source-Projekt – nicht verbunden mit Meta, Ray-Ban/EssilorLuxottica oder Anthropic.
> Fork von [mrdulasolutions/visionclaude](https://github.com/mrdulasolutions/visionclaude) –
> überarbeitet, abgesichert und für Windows und die Gen 2 angepasst
> ([39 behobene Bugs](docs/BUGFIXES.md)).

```
 Ray-Ban Meta Gen 2 ──Bluetooth──▶ iPhone-App ──WLAN──▶ Windows-PC
   Kamera, Mikrofon,                 Sprache→Text        Channel-Server (Bun)
   Lautsprecher                      Kamera-Bilder           │  MCP-Channel
                                     ◀── Antwort + Stimme    ▼
                                                         Claude Code – alle MCP-Tools & Skills
```

## Schnellstart (Windows, 10 Minuten)

1. **Projekt laden:** [ZIP herunterladen](https://github.com/MoinMornhart/RayBanClaude/archive/refs/heads/main.zip)
   und entpacken – oder `git clone https://github.com/MoinMornhart/RayBanClaude.git`
2. **`setup.cmd` doppelklicken** – installiert bei Bedarf Bun und Claude Code und richtet alles ein.
3. **`start.cmd` doppelklicken** – startet Claude Code mit RayBan Claude, das Dashboard öffnet sich.
   Beim ersten Mal *„Use this MCP server“* und *„I am using this for local development“* bestätigen.
4. **iPhone-App installieren** – ohne Mac, kostenlos: [Anleitung](docs/IPHONE-OHNE-MAC.md)
5. **QR-Code** im Dashboard mit der iPhone-Kamera scannen → *Koppeln* → lossprechen:
   *„Was siehst du?“*

macOS/Linux: `./setup.sh` und `./start.sh`.

## Was kostet das?

| Teil | Kosten |
|---|---|
| Claude Code mit Claude-Abo (Pro/Max) | im Abo enthalten – **keine API-Kosten** |
| Sprachausgabe | **kostenlose iPhone-Stimme** (ElevenLabs optional) |
| iPhone-App bauen | **kostenlos** per GitHub Actions |
| App aufs iPhone | **kostenlos** mit Sideloadly + normaler Apple-ID (alle 7 Tage auffrischen) |
| Gateway-Modus (optional, ohne Claude Code) | Anthropic-API, Abrechnung pro Nutzung |

## Was die App kann

| Funktion | Beschreibung |
|---|---|
| 👓 Brille oder iPhone | Kamera der Ray-Ban Meta (720p) oder iPhone (1080p), per Knopfdruck wechseln |
| 🗣 Freihändig | Sprechen → Pause → Claude antwortet → hört wieder zu (Mikrofon/Lautsprecher der Brille) |
| 🧰 Alle Tools | Im Channel-Modus nutzt Claude deine komplette Claude-Code-Sitzung inkl. MCP-Servern und Skills |
| 🔐 Freigaben am Handy | Will Claude ein Tool ausführen, fragt die App – Knopf oder einfach „Ja“/„Nein“ sagen |
| 📸 Foto auf Anfrage | Claude kann selbst ein scharfes Foto mit der Brille auslösen (z. B. zum Lesen) |
| 🎯 Experten-Modi | Allgemein, Übersetzer, Umgebung (Sehbehinderung), Kfz, Heizung/Klima, Sanitär, Elektriker (VDE), QR-Scanner, Inventur, Arbeitsschutz (DGUV/ASR), Dokumente – plus eigene |
| 🔳 QR-/Barcodes | Automatisch erkannt, mit einem Tipp an Claude |
| 🔋 Gen-2-Status | Akku, Modell, Bügel-Status; Stream startet beim Aufklappen neu |
| 📱 QR-Kopplung | Kein Abtippen von IP und Token |

## Ray-Ban Meta Gen 2 einrichten

1. Meta-AI-App (ab Version 290) → Einstellungen → Brille → **Entwicklermodus an** → Brille neu starten
2. RayBan Claude → Einstellungen → **Brille über Meta AI verbinden** → in der Meta-AI-App erlauben
3. Unten rechts auf **Brille** tippen, Kamera-Freigabe bestätigen

Im Entwicklermodus ist **keine** Meta-App-ID nötig. Details: [docs/IPHONE-OHNE-MAC.md](docs/IPHONE-OHNE-MAC.md).

## Aufbau

| Ordner | Inhalt |
|---|---|
| `channel/` | **Channel-Server** (Bun, TypeScript): MCP-Channel für Claude Code, WebSocket für die App, Dashboard mit QR-Kopplung |
| `server/` | **Gateway** (Node, optional): eigener Server mit Anthropic-API-Key und MCP-Client |
| `ios/` | **iPhone-App** (SwiftUI, Meta Wearables DAT SDK 1.0.1); Xcode-Projekt per XcodeGen |
| `docs/` | Anleitungen, [Bug-Liste](docs/BUGFIXES.md), Projekt-Webseite (`docs/index.html`) |

Mehr Details: [ARCHITECTURE.md](ARCHITECTURE.md)

## Sicherheit

- Jede Verbindung braucht ein **Token** (48 Hex-Zeichen, automatisch erzeugt); nach 10 Fehlversuchen 15 Minuten Sperre.
- Token und ElevenLabs-Key liegen am iPhone im **Schlüsselbund**.
- Das Dashboard ist **nur am PC selbst** erreichbar (Schutz gegen DNS-Rebinding).
- Claude-Code-Freigaben bleiben aktiv; vorab erlaubt sind nur die Antwort-Tools von RayBan Claude.
  **Nicht** mit `--dangerously-skip-permissions` betreiben: Text in Kamerabildern kann Anweisungen enthalten (Prompt-Injection).
- Gateway-Modus (ohne Rückfragen): Claude bekommt standardmäßig nur Werkzeuge, die sich als „nur lesend“ ausweisen.
  Weitere gezielt per `MCP_TOOL_ALLOWLIST` in `server/.env` freischalten (z. B. `readonly,kalender/*`).
- Das Token wird nur im `Authorization`-Header übertragen, nie in der URL.
- Im WLAN läuft die Verbindung per HTTP (LAN-IPs haben kein Zertifikat). Für unterwegs: VPN wie Tailscale statt Port-Freigabe.

## Für Entwickler

```bash
cd channel && bun install && bun test      # 12 End-to-End-Tests
cd server && npm ci && npm run build       # Gateway
cd ios && xcodegen generate                # Xcode-Projekt (nur macOS)
```

Eigene Werte für Xcode (Team-ID, Bundle-ID, Meta-App-ID) in `ios/Secrets.xcconfig`
(Vorlage: `ios/Secrets.xcconfig.example`). Mehr in [CONTRIBUTING.md](CONTRIBUTING.md).

## Fehlerbehebung

| Problem | Lösung |
|---|---|
| App verbindet nicht | Gleiches WLAN? Windows-Firewall: privates Netzwerk erlauben (`setup.cmd` hilft). WLAN-Profil auf „Privat“. |
| „Token falsch“ | QR-Code im Dashboard neu scannen |
| Keine Antwort von Claude | Läuft `start.cmd`? In Claude `/mcp` prüfen. Wartet Claude auf eine Freigabe? |
| Port belegt | Andere Claude-Sitzung mit RayBan Claude schließen oder `RAYBANCLAUDE_PORT` setzen |
| Brille streamt nicht | Entwicklermodus an? Bügel offen? Akku > 10 %? Brille neu starten |

## Lizenz

MIT – siehe [LICENSE](LICENSE). Ursprünglicher Code © 2026 MR Dula Solutions.
Die Nutzung des Meta Wearables Device Access Toolkit unterliegt den
[Meta Wearables Developer Terms](https://wearables.developer.meta.com/terms).

---

Verfasst mit Claude 🤖
