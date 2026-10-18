#!/usr/bin/env bash
# RayBan Claude starten: Claude Code mit dem Channel + Dashboard im Browser (macOS/Linux)
set -euo pipefail
cd "$(dirname "$0")"
PORT="${RAYBANCLAUDE_PORT:-18790}"

command -v claude >/dev/null || { echo "Claude Code fehlt – bitte zuerst ./setup.sh ausführen."; exit 1; }
[[ -d channel/node_modules ]] || { echo "Abhängigkeiten fehlen – bitte zuerst ./setup.sh ausführen."; exit 1; }

# Dashboard öffnen, sobald der Channel läuft
(
  for _ in $(seq 1 90); do
    if curl -fsS "http://localhost:$PORT/health" >/dev/null 2>&1; then
      if command -v open >/dev/null; then open "http://localhost:$PORT"; else xdg-open "http://localhost:$PORT" >/dev/null 2>&1 || true; fi
      exit 0
    fi
    sleep 1
  done
) &

echo "◉ RayBan Claude startet … Dashboard öffnet sich gleich im Browser."
# Nur die eigenen Antwort-Tools vorab erlauben – alles andere fragt weiter nach
exec claude --dangerously-load-development-channels server:raybanclaude \
  --allowedTools "mcp__raybanclaude__reply" "mcp__raybanclaude__edit_message" "mcp__raybanclaude__request_photo"
