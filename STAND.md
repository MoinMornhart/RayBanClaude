# Stand: RayBan Claude (Übergabe 2026-10-24)

## Was es ist
Macht Philips Ray-Ban Meta (Gen 2) bzw. das iPhone zu Augen und Ohren von Claude – „wie Meta AI, nur mit Claude“. iPhone-App (Weckwort „Hey Claude“/„Claudi“) spricht über WLAN oder Tailscale mit Claude Code (Claude-Abo) auf dem Windows-PC; ohne PC notfalls direkt über die Claude-API. Fork/Import von `mrdulasolutions/visionclaude`.

## Aktueller Stand
- **iOS-App** (SwiftUI, Meta DAT SDK 1.0.1): Weckwort freihändig auch bei gesperrtem iPhone, Kamera nur auf Zuruf, Brille hat Vorrang vor iPhone/anderen Headsets, Handy-Aktionen (Timer, Wecker, Erinnerungen, Anruf/Nachricht/Navigation mit Bestätigung, Fotos, Standort), Gedächtnis, 11 Experten-Modi, QR-Kopplung, Direkt-Modus mit API-Key. Baut in GitHub Actions; Installation ohne Mac per Sideloadly (`docs/IPHONE-OHNE-MAC.md`).
- **Channel-Server** (`channel/`, Bun, MCP-Channel für Claude Code) mit Dashboard unter `http://localhost:18790` (nur lokal), Verlauf, Verknüpfung mit der Claude-Desktop-App (Werkzeug „Brille“).
- **Gateway-Server** (`server/`, Node/TS) für Betrieb ohne Rückfragen; standardmäßig nur lesende MCP-Werkzeuge.
- **Windows-Installer** `RayBanClaude-Setup.exe` (Inno Setup, Release mit Prüfsumme), `setup.cmd`/`start.cmd`.
- Projektseite (GitHub Pages, `docs/index.html`) im Jarvis-Look; 39 behobene Bugs in `docs/BUGFIXES.md`.

## Zuletzt gemacht
- 2026-10-24: Cloud-Start-Hook (Philips Skills in Cloud-Sitzungen).
- 2026-10-19: Projektseite + Dashboard im Jarvis-Look; Installer-Fix; „wie Meta AI“ (Kamera auf Zuruf, Hosentaschen-Modus); Brille hat Vorrang; Verknüpfung Claude-App; unterwegs übers Abo (Tailscale) + Gedächtnis; Weckwort, Handy-Aktionen, Direkt-Modus; Sicherheits-Check.
- 2026-10-18: Import als RayBan Claude, Sicherheitslücken behoben, Windows-Support, Meta DAT 1.0.1, Deutsch.

## Offen / Nächste Schritte
- **iPhone-App noch nicht auf echter Hardware (Brille + iPhone) getestet** – wichtigster offener Punkt; Hintergrund-Zuhören ebenfalls ungetestet.
- Geplant: gegenseitige Prüfung ohne Klartext-Token (App schickt Token im WLAN an gespeicherte Heim-Adresse, auch in fremden WLANs).
- Bekannte Grenzen: Speicherleck im Meta-DAT-SDK bei Gen 2 (~4 MB/min, Meta-Issue #324) → bei langen Sitzungen App neu starten; WLAN-Verbindung nur HTTP (mit Token); Prompt-Injection über Kamerabilder nicht ganz vermeidbar.
- Nicht möglich/noch nicht: Tippen-und-Halten am Bügel (Meta gibt Geste nicht frei), Live-Übersetzung, Musik, Mitteilungen vorlesen; Android-App fehlt.
- Installer ist nicht kostenpflichtig signiert (SmartScreen-Warnung).

## Wichtige Infos
- Tests/Build: `cd channel && bun test` · `cd server && npm run build` · iOS über `ios-build.yml` (XcodeGen aus `ios/project.yml`).
- Weitere Workflows: `server-tests.yml`, `windows-installer.yml`, `ios-screenshots.yml`, `vibeworks-check.yml`.
- Start: `start.cmd` (Claude Code mit `--dangerously-load-development-channels`, NICHT mit `--dangerously-skip-permissions`).
- Port Channel/Dashboard: 18790. Daten am PC: `%USERPROFILE%\.claude\channels\raybanclaude` (Verlauf 30 Tage, `.env`).
- MCP-SDK im Channel auf `~1.32` lassen (neuere handeln evtl. Protokoll 2026-07-28 aus → kein Channel).
- TypeScript-Regeln vom Plugin *typescript-patterns-enforcer*; Regexe in `channel/lib/patterns.ts`.
- Secrets nur in `.env` / `ios/Secrets.xcconfig` (beide ignoriert).

## Philips Vorgaben
- Repo **öffentlich** (github.com/MoinMornhart/RayBanClaude), MIT-Lizenz.
- Commit-Messages enden mit `Verfasst mit Claude 🤖` (vor Co-Authored-By); README-Fußzeile ebenso.
- **Keine Update-Funktion** vorgesehen.
- Alles auf Deutsch (Antworten, Kommentare, UI, Doku).

Diese Datei wird beim Arbeiten aktuell gehalten: nach jedem größeren Schritt „Aktueller Stand“ und „Offen“ anpassen.
