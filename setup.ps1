<#
  RayBan Claude – Einrichtung unter Windows
  Ausführen: Rechtsklick → "Mit PowerShell ausführen"
  oder:      powershell -ExecutionPolicy Bypass -File .\setup.ps1
#>
$ErrorActionPreference = 'Stop'
Set-Location -Path $PSScriptRoot
$Port = 18790

function Write-Step($text) { Write-Host "`n▸ $text" -ForegroundColor DarkYellow }
function Write-Ok($text)   { Write-Host "  ✓ $text" -ForegroundColor Green }
function Write-Warn($text) { Write-Host "  ! $text" -ForegroundColor Yellow }
function Ask($question)    { (Read-Host "  $question (j/n)") -match '^(j|ja|y|yes)$' }
function Test-Command($name) { [bool](Get-Command $name -ErrorAction SilentlyContinue) }

Write-Host ""
Write-Host "  ◉ RayBan Claude – Einrichtung" -ForegroundColor DarkYellow
Write-Host "    Claude sieht, was du siehst (Ray-Ban Meta Gen 2 & iPhone)" -ForegroundColor Gray
Write-Host "    Inoffizielles Open-Source-Projekt – nicht verbunden mit Meta, Ray-Ban oder Anthropic." -ForegroundColor DarkGray

# ── 1. Bun (führt den Channel-Server aus) ────────────────────────────────────
Write-Step "Bun prüfen"
if (-not (Test-Command 'bun')) {
    Write-Warn "Bun ist nicht installiert (kostenlos, https://bun.sh)."
    if (Ask "Bun jetzt mit dem offiziellen Installer installieren?") {
        powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://bun.sh/install.ps1 | iex"
        $env:Path = "$env:USERPROFILE\.bun\bin;$env:Path"
    } else {
        Write-Warn "Ohne Bun läuft der Channel nicht. Später: irm https://bun.sh/install.ps1 | iex"
        exit 1
    }
}
Write-Ok "Bun $(bun --version)"

# ── 2. Claude Code ───────────────────────────────────────────────────────────
Write-Step "Claude Code prüfen"
if (-not (Test-Command 'claude')) {
    Write-Warn "Claude Code ist nicht installiert."
    if (Ask "Claude Code jetzt mit dem offiziellen Installer installieren?") {
        powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://claude.ai/install.ps1 | iex"
        $env:Path = "$env:USERPROFILE\.local\bin;$env:Path"
    } else {
        Write-Warn "Später installieren: https://claude.com/claude-code"
    }
}
if (Test-Command 'claude') { Write-Ok "Claude Code $(claude --version)" }

# ── 3. Abhängigkeiten des Channels ───────────────────────────────────────────
Write-Step "Channel-Abhängigkeiten installieren"
Push-Location channel
bun install --frozen-lockfile
bun audit
Pop-Location
Write-Ok "Channel bereit"

# ── 4. Optional: Gateway-Modus (eigener Anthropic-API-Key, kostet pro Anfrage) ──
Write-Step "Gateway-Modus (optional)"
Write-Host "  Nur nötig, wenn du OHNE Claude Code mit eigenem API-Key arbeiten willst." -ForegroundColor Gray
if ((Test-Command 'npm') -and (Ask "Gateway-Server einrichten?")) {
    Push-Location server
    npm ci
    npm run build
    npm audit --audit-level=high
    if (-not (Test-Path .env)) {
        Copy-Item .env.example .env
        Write-Warn "server\.env angelegt – trage dort deinen ANTHROPIC_API_KEY ein."
    }
    Pop-Location
    Write-Ok "Gateway gebaut (Start: cd server; npm start)"
}

# ── 5. Windows-Firewall: iPhone muss den PC im WLAN erreichen ────────────────
Write-Step "Windows-Firewall"
$rule = Get-NetFirewallRule -DisplayName 'RayBan Claude' -ErrorAction SilentlyContinue
if ($rule) {
    Write-Ok "Firewall-Regel vorhanden"
} else {
    Write-Host "  Damit das iPhone den PC erreicht, muss Port $Port im PRIVATEN Netzwerk offen sein." -ForegroundColor Gray
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $cmd = "New-NetFirewallRule -DisplayName 'RayBan Claude' -Direction Inbound -Protocol TCP -LocalPort $Port -Profile Private -Action Allow"
    if ($isAdmin -and (Ask "Regel jetzt anlegen (nur private Netzwerke, Port $Port)?")) {
        Invoke-Expression $cmd | Out-Null
        Write-Ok "Firewall-Regel angelegt"
    } else {
        Write-Warn "Alternativ beim ersten Start die Windows-Abfrage für 'Private Netzwerke' mit 'Zulassen' beantworten."
        Write-Host "  Oder in einer Administrator-PowerShell:" -ForegroundColor Gray
        Write-Host "    $cmd" -ForegroundColor Cyan
    }
}
$profiles = Get-NetConnectionProfile -ErrorAction SilentlyContinue | Where-Object { $_.NetworkCategory -eq 'Public' }
if ($profiles) {
    Write-Warn "Dein WLAN ist als 'Öffentlich' eingestuft – dann blockt Windows das iPhone."
    Write-Host "    Einstellungen → Netzwerk & Internet → WLAN → Netzwerkprofil: Privat" -ForegroundColor Cyan
}

# ── Fertig ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ✅ Fertig! So geht's weiter:" -ForegroundColor Green
Write-Host "   1. start.cmd doppelklicken – startet Claude Code mit RayBan Claude"
Write-Host "      (beim ersten Mal 'Use this MCP server' und 'I am using this for local development' bestätigen)"
Write-Host "   2. Das Dashboard öffnet sich: http://localhost:$Port"
Write-Host "   3. iPhone-App installieren: siehe docs\IPHONE-OHNE-MAC.md (kostenlos, mit Sideloadly)"
Write-Host "   4. QR-Code im Dashboard mit der iPhone-Kamera scannen – fertig."
Write-Host ""
