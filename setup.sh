#!/usr/bin/env bash
# RayBan Claude – Einrichtung unter macOS und Linux (Windows: setup.cmd)
set -euo pipefail
cd "$(dirname "$0")"
PORT="${RAYBANCLAUDE_PORT:-18790}"

orange=$'\033[38;5;208m'; green=$'\033[32m'; yellow=$'\033[33m'; gray=$'\033[90m'; reset=$'\033[0m'
step() { printf '\n%s▸ %s%s\n' "$orange" "$1" "$reset"; }
ok()   { printf '  %s✓ %s%s\n' "$green" "$1" "$reset"; }
warn() { printf '  %s! %s%s\n' "$yellow" "$1" "$reset"; }
ask()  { read -r -p "  $1 (j/n) " a; [[ "$a" =~ ^(j|ja|y|yes)$ ]]; }
has()  { command -v "$1" >/dev/null 2>&1; }

printf '\n  %s◉ RayBan Claude – Einrichtung%s\n' "$orange" "$reset"
printf '  %sInoffizielles Open-Source-Projekt – nicht verbunden mit Meta, Ray-Ban oder Anthropic.%s\n' "$gray" "$reset"

step "Bun prüfen"
if ! has bun; then
  warn "Bun ist nicht installiert (kostenlos, https://bun.sh)."
  if ask "Bun mit dem offiziellen Installer installieren?"; then
    curl -fsSL https://bun.sh/install | bash
    export PATH="$HOME/.bun/bin:$PATH"
  else
    warn "Ohne Bun läuft der Channel nicht."; exit 1
  fi
fi
ok "Bun $(bun --version)"

step "Claude Code prüfen"
if ! has claude; then
  warn "Claude Code ist nicht installiert."
  if ask "Claude Code mit dem offiziellen Installer installieren?"; then
    curl -fsSL https://claude.ai/install.sh | bash
    export PATH="$HOME/.local/bin:$PATH"
  fi
fi
has claude && ok "Claude Code $(claude --version)"

step "Channel-Abhängigkeiten installieren"
(cd channel && bun install --frozen-lockfile && bun audit)
ok "Channel bereit"

step "Gateway-Modus (optional, eigener Anthropic-API-Key)"
if has npm && ask "Gateway-Server einrichten?"; then
  (cd server && npm ci && npm run build && npm audit --audit-level=high)
  [[ -f server/.env ]] || { cp server/.env.example server/.env; warn "server/.env angelegt – ANTHROPIC_API_KEY eintragen."; }
  ok "Gateway gebaut (Start: cd server && npm start)"
fi

if [[ "$(uname)" == "Darwin" ]]; then
  step "iOS-App (nur mit Mac und Xcode)"
  if has xcodegen || { has brew && ask "XcodeGen per Homebrew installieren?" && brew install xcodegen; }; then
    (cd ios && xcodegen generate)
    ok "Xcode-Projekt erzeugt: ios/RayBanClaude.xcodeproj (Team unter Signing & Capabilities wählen)"
  else
    warn "Ohne Mac/Xcode: fertige IPA aus GitHub Actions nutzen – siehe docs/IPHONE-OHNE-MAC.md"
  fi
fi

printf '\n  %s✅ Fertig!%s\n' "$green" "$reset"
echo "   1. ./start.sh  – startet Claude Code mit RayBan Claude"
echo "   2. Dashboard: http://localhost:$PORT – QR-Code mit der iPhone-Kamera scannen"
echo "   3. Unterwegs (optional): Tailscale auf PC und iPhone – die Adresse steckt dann automatisch im QR-Code"
echo
