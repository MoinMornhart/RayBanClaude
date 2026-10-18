# Mitmachen

Danke fürs Mithelfen! Fehler und Ideen gern als [Issue](https://github.com/MoinMornhart/RayBanClaude/issues).

## Entwicklungsumgebung

| Teil | Werkzeuge | Befehle |
|---|---|---|
| Channel (`channel/`) | Bun ≥ 1.1 | `bun install` · `bun run typecheck` · `bun test` · `bun audit` |
| Gateway (`server/`) | Node ≥ 20 | `npm ci` · `npm run build` · `npm audit` |
| iPhone-App (`ios/`) | macOS, Xcode ≥ 26.4, XcodeGen | `xcodegen generate` · in Xcode bauen – oder einfach pushen, GitHub Actions baut die IPA |

Eigene Signier-Werte gehören in `ios/Secrets.xcconfig` (nicht committen).

## Regeln

- Texte, Kommentare und Oberfläche auf Deutsch.
- TypeScript: keine Magic Numbers, keine `for`/`while`-Schleifen und kein `switch` (Daten statt Logik),
  jede Regex mit Beschreibung, Beispiel und regex101-Link (siehe `channel/lib/patterns.ts`).
- Sicherheit: keine Secrets im Code, Eingaben an der Grenze validieren (Whitelist),
  keine internen Fehlerdetails an Clients, neue Routen mit passender Zugriffsstufe.
- Vor einem Pull Request: Tests grün, `bun audit`/`npm audit` ohne Funde, kurzer OWASP-Check in der PR-Beschreibung.

## Fehler melden

Bitte angeben: Windows-/macOS-Version, iPhone- und iOS-Version, Brillenmodell und Firmware,
Ausgabe des Channel-Servers (im Claude-Code-Terminal bzw. `claude --debug`) und Schritte zum Nachstellen.
**Keine Tokens oder API-Keys** in Issues posten.
