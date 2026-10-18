#!/usr/bin/env bash
# Testskript für das RayBan Claude Gateway (läuft auch unter Windows-Git-Bash)
#
# Aufruf:
#   ./test-chat.sh [BASE_URL] [TOKEN]
#   GATEWAY_TOKEN=<token> ./test-chat.sh http://192.168.1.20:18790
#
# Ohne Token-Angabe wird ~/.raybanclaude/gateway-token gelesen (falls vorhanden).

set -u

BASE_URL="${1:-http://localhost:18790}"
TOKEN="${2:-${GATEWAY_TOKEN:-}}"
TOKEN_FILE="$HOME/.raybanclaude/gateway-token"

if [ -z "$TOKEN" ] && [ -f "$TOKEN_FILE" ]; then
  TOKEN="$(tr -d '[:space:]' < "$TOKEN_FILE")"
fi

if [ -z "$TOKEN" ]; then
  echo "Fehler: Kein Gateway-Token. Als 2. Argument oder per GATEWAY_TOKEN übergeben." >&2
  exit 1
fi

# JSON hübsch ausgeben: jq, sonst node, sonst unverändert
pretty() {
  if command -v jq >/dev/null 2>&1; then
    jq .
  elif command -v node >/dev/null 2>&1; then
    node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log(JSON.stringify(JSON.parse(s),null,2))}catch{console.log(s)}})'
  else
    cat
  fi
}

AUTH_HEADER="Authorization: Bearer ${TOKEN}"

echo "=== Health (öffentlich) ==="
curl -s "$BASE_URL/health" | pretty
echo ""

echo "=== Health-Details ==="
curl -s -H "$AUTH_HEADER" "$BASE_URL/health/details" | pretty
echo ""

echo "=== Werkzeuge ==="
curl -s -H "$AUTH_HEADER" "$BASE_URL/tools" | pretty
echo ""

echo "=== Chat (nur Text) ==="
curl -s -X POST "$BASE_URL/chat" \
  -H "$AUTH_HEADER" \
  -H "Content-Type: application/json" \
  -d '{"text": "Hallo! Welche Werkzeuge hast du? Bitte kurz aufzählen."}' | pretty
echo ""

echo "=== Konfiguration ==="
curl -s -H "$AUTH_HEADER" "$BASE_URL/config" | pretty
echo ""

echo "=== MCP-Status ==="
curl -s -H "$AUTH_HEADER" "$BASE_URL/tools/health" | pretty
echo ""
