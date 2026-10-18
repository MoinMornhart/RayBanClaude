# RayBan Claude – Hinweise für Claude Code

- Sprache: Antworten, Code-Kommentare, UI-Texte und Doku auf **Deutsch**.
- Git-Texte: Commit-Messages enden mit der Zeile `Verfasst mit Claude 🤖` (vor dem Co-Authored-By);
  README hat die Zeile als Fußzeile. Keine Update-Funktion vorgesehen.
- Repo: öffentlich, https://github.com/MoinMornhart/RayBanClaude
- TypeScript (`channel/`, `server/`): Regeln des Plugins *typescript-patterns-enforcer* einhalten
  (keine Magic Numbers, keine Schleifen/`switch`, jede Regex mit Beispiel + regex101-Link).
  Regexe des Channels stehen in `channel/lib/patterns.ts`.
- Tests: `cd channel && bun test` · `cd server && npm run build` · iOS baut in GitHub Actions (`ios-build.yml`).
- MCP-SDK im Channel bleibt auf `~1.32` – neuere Versionen könnten Protokoll 2026-07-28 aushandeln,
  das Claude Code nicht als Channel registriert.
- Sicherheit: keine Secrets im Code (`.env`, `ios/Secrets.xcconfig`), Eingaben per Whitelist prüfen,
  keine internen Fehlerdetails an Clients.
