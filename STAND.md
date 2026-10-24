# Stand: RayBan Claude (Übergabe 2026-10-24)

## Was es ist
Macht Philips Ray-Ban Meta (Gen 2) bzw. das iPhone zu Augen und Ohren von Claude – „wie Meta AI, nur mit Claude“. iPhone-App (Weckwort „Hey Claude“/„Claudi“) spricht über WLAN oder Tailscale mit Claude Code (Claude-Abo) auf dem Windows-PC; ohne PC notfalls direkt über die Claude-API. Kopie von `mrdulasolutions/visionclaude`, umbenannt in RayBan Claude und auf Ray-Ban Meta Gen 2 ausgerichtet.

## Ziel
- Die Brille soll sich anfühlen wie Meta AI, nur mit Claude.
- Kamera nur auf Zuruf – kein Dauerfilmen; ein Foto nur, wenn die Frage eins braucht.
- Brille hat Vorrang für Kamera, Mikrofon und Lautsprecher; das iPhone springt nur ein.

## Aktueller Stand
Auf `main` (Version **2.1.0**, 24.10.; v2.0.0 vom 19.10. ist das letzte veröffentlichte Release):
- **iOS-App** (SwiftUI, Meta DAT SDK 1.0.1, Deutsch): Weckwort freihändig auch bei gesperrtem iPhone, Kamera nur auf Zuruf, Brille hat Vorrang vor iPhone/anderen Headsets, Handy-Aktionen (Timer, Wecker, Erinnerungen, Fotos, Standort; Anruf/Nachricht/Navigation immer mit Bestätigung), Gedächtnis, 11 Experten-Modi, QR-Kopplung, Direkt-Modus mit API-Key nur als Notlösung. Baut in GitHub Actions; `.ipa` ohne Mac per Sideloadly (`docs/IPHONE-OHNE-MAC.md`).
- **Unterwegs übers Claude-Abo:** App erreicht den PC per Tailscale auch über mobile Daten.
- **Channel-Server** (`channel/`, Bun, MCP-Channel für Claude Code) mit Dashboard unter `http://localhost:18790` (nur lokal), Gesprächsverlauf und Gedächtnis-Kopie auf dem PC, Brücke zur Claude-Desktop-App (Werkzeug „Brille“).
- **Gateway-Server** (`server/`, Node/TS) für Betrieb ohne Rückfragen; standardmäßig nur lesende MCP-Werkzeuge.
- **Windows-Installer** `RayBanClaude-Setup.exe` (Inno Setup, Release mit Prüfsumme): installiert Bun + Claude Code, Firewall nur für Heim-WLAN und Tailscale, Verknüpfung mit der Claude-App; dazu `setup.cmd`/`start.cmd`.
- **Projektseite** (GitHub Pages, `docs/index.html`, strikte CSP) und Dashboard im Jarvis-Look; 39 behobene Bugs in `docs/BUGFIXES.md`.

Neu in 2.1.0 (aus den Zweigen vom 20.10., am 24.10. nach `main` übernommen):
- **iPhone-App im Jarvis-Look** (aus `claude/zealous-pascal-dfcf80`): HUD-Farben (Nachtblau, Cyan, Gold) zentral in `HUDStyle.swift`, Reaktor-Ringe um den Mikrofon-Knopf (still bei „Bewegung reduzieren“). Nur Optik, Bedienlogik unverändert.
- **Gesten der Brille** (aus `claude/reverent-moore-d93bfa`, Metas experimentelles Modul `MWDATInputs`): Doppeltipp aufs Touchpad = Claude hört sofort zu, Capture-Taste kurz = Foto + „Was siehst du?“, Zurück = Abbruch. Mit Gesten bleibt die Brillen-Sitzung offen, die Kamera kommt pro Foto dazu und geht 15 s danach wieder aus. Schalter *Einstellungen → Ray-Ban Meta → Gesten (experimentell)*, **standardmäßig aus** – dann wie vorher: Sitzung nur fürs Foto.
- Beide Zweige zusammengeführt (Konflikt in `SettingsView.swift` gelöst), iOS-Build grün ohne Warnungen, Simulator-Rauchtest grün.

## Zuletzt gemacht
- 2026-10-24: Version 2.1.0 auf `main`: iPhone-App im Jarvis-Look + Gesten der Brille (standardmäßig aus); Übergabe aus den lokalen Chats (18.–20.10.) eingearbeitet.
- 2026-10-24: Cloud-Start-Hook (Philips Skills in Cloud-Sitzungen).
- 2026-10-20: Gesten (Doppeltipp, Capture-Taste) und iPhone-App im Jarvis-Look auf eigenen Zweigen gebaut, Builds grün.
- 2026-10-19: Release v2.0.0. Projektseite + Dashboard im Jarvis-Look; Installer-Fix; „wie Meta AI“ (Kamera auf Zuruf, Hosentaschen-Modus); Brille hat Vorrang; Verknüpfung Claude-App; unterwegs übers Abo (Tailscale) + Gedächtnis; Weckwort, Handy-Aktionen, Direkt-Modus; Sicherheits-Check.
- 2026-10-18: Import als RayBan Claude, Sicherheitslücken behoben, Windows-Support, Meta DAT 1.0.1, Deutsch.

## Offen / Nächste Schritte
- **Nichts davon ist auf echter Hardware (Brille + iPhone) getestet** – wichtigster offener Punkt; Hintergrund-Zuhören ebenfalls ungetestet.
- Gesten auf echter Brille testen (Einstellungen → Ray-Ban Meta → Gesten): Kommt die Capture-Taste bei laufender Kamera an? Macht die Brille zusätzlich ein eigenes Foto? Blockiert die offene Sitzung Meta AI? Danach entscheiden, ob sie standardmäßig an gehen.
- Release v2.1.0 auf GitHub veröffentlichen (aus der Cloud-Sitzung nicht möglich – `gh` hat dort keine Anmeldung); die Workflows hängen Setup.exe und .ipa danach selbst an.
- Neue Screenshots im Jarvis-Look in README (`docs/images/app-*.png`, 600 px breit) und Projektseite (eingebettet, 520 px) einbauen: liegen als Artefakt `ios-screenshots` im Workflow „iOS-Screenshots“; der Download aus der Cloud scheiterte an der Netzwerk-Freigabe (`*.blob.core.windows.net`).
- Alte Zweige `claude/reverent-moore-d93bfa` und `claude/zealous-pascal-dfcf80` löschen (nach Philips OK).
- **iPhone-App kostenlos aufs iPhone:** Sideloadly scheiterte bei Philip mit kostenloser Apple-ID, deshalb zahlt er gerade. Vermutlich Apples Sperre kostenloser Konten seit Sommer 2026 (Fehler 0xe8008024 „provisioning profile is banned“, betrifft auch AltStore/SideStore); gemeldet hilft meist eine neue kostenlose Apple-ID. Einrichtung (z. B. SideStore mit Auffrischen am iPhone oder Sideloadly/AltServer über den PC) erst, wenn Philip Bescheid sagt.
- Issue #1 (VibeWorks): Abhängigkeiten aktualisieren, u. a. `@anthropic-ai/sdk` 0.135 → 1.3 (Major).
- Idee: Token-Schutz in fremden WLANs – gegenseitige Prüfung ohne Klartext-Token (App schickt Token im WLAN nur an die gespeicherte Heim-Adresse).
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
- Sideloadly: Anmeldung mit der Apple-ID (= E-Mail-Adresse); eine Team-ID ist nicht nötig.

## Philips Vorgaben
- Repo **öffentlich** (github.com/MoinMornhart/RayBanClaude), MIT-Lizenz.
- Commit-Messages enden mit `Verfasst mit Claude 🤖` (vor Co-Authored-By); README-Fußzeile ebenso.
- **Keine Update-Funktion** vorgesehen.
- Alles auf Deutsch (Antworten, Kommentare, App-Oberfläche, Doku).

Diese Datei wird beim Arbeiten aktuell gehalten: nach jedem größeren Schritt „Aktueller Stand“ und „Offen“ anpassen.
