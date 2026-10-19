<#
  RayBan Claude – Einrichtung unter Windows
  Ausführen: setup.cmd doppelklicken (oder den Windows-Installer RayBanClaude-Setup.exe nutzen)
  oder:      powershell -ExecutionPolicy Bypass -File .\setup.ps1

  -Unattended: ohne Rückfragen (für den Installer) – installiert Bun und Claude Code bei Bedarf
  mit den offiziellen Installern, überspringt den optionalen Gateway; die Firewall richtet der
  Installer selbst ein.
#>
param([switch]$Unattended)
$ErrorActionPreference = 'Stop'
Set-Location -Path $PSScriptRoot
$Port = 18790

function Write-Step($text) { Write-Host "`n▸ $text" -ForegroundColor DarkYellow }
function Write-Ok($text)   { Write-Host "  ✓ $text" -ForegroundColor Green }
function Write-Warn($text) { Write-Host "  ! $text" -ForegroundColor Yellow }
function Ask($question, [bool]$UnattendedAnswer = $true) {
    if ($Unattended) { return $UnattendedAnswer }
    (Read-Host "  $question (j/n)") -match '^(j|ja|y|yes)$'
}
function Test-Command($name) { [bool](Get-Command $name -ErrorAction SilentlyContinue) }
function Test-Rule($name) { [bool](Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue) }

# Frisch installierte Werkzeuge sofort finden (der Installer erbt noch den alten PATH)
$env:Path = "$env:USERPROFILE\.bun\bin;$env:USERPROFILE\.local\bin;$env:Path"

try {
    Write-Host ""
    Write-Host "  ◉ RayBan Claude – Einrichtung" -ForegroundColor DarkYellow
    Write-Host "    Claude sieht, was du siehst (Ray-Ban Meta Gen 2 & iPhone)" -ForegroundColor Gray
    Write-Host "    Inoffizielles Open-Source-Projekt – nicht verbunden mit Meta, Ray-Ban oder Anthropic." -ForegroundColor DarkGray

    # ── 1. Bun (führt den Channel-Server aus) ────────────────────────────────
    Write-Step "Bun prüfen"
    if (-not (Test-Command 'bun')) {
        Write-Warn "Bun ist nicht installiert (kostenlos, https://bun.sh)."
        if (Ask "Bun jetzt mit dem offiziellen Installer installieren?") {
            powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://bun.sh/install.ps1 | iex"
        } else {
            Write-Warn "Ohne Bun läuft der Channel nicht. Später: irm https://bun.sh/install.ps1 | iex"
            exit 1
        }
    }
    if (-not (Test-Command 'bun')) { throw "Bun wurde nicht gefunden – bitte setup.cmd noch einmal starten." }
    Write-Ok "Bun $(bun --version)"

    # ── 2. Claude Code ───────────────────────────────────────────────────────
    Write-Step "Claude Code prüfen"
    if (-not (Test-Command 'claude')) {
        Write-Warn "Claude Code ist nicht installiert."
        if (Ask "Claude Code jetzt mit dem offiziellen Installer installieren?") {
            powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://claude.ai/install.ps1 | iex"
        } else {
            Write-Warn "Später installieren: https://claude.com/claude-code"
        }
    }
    if (Test-Command 'claude') { Write-Ok "Claude Code $(claude --version)" }

    # ── 3. Abhängigkeiten des Channels ───────────────────────────────────────
    Write-Step "Channel-Abhängigkeiten installieren"
    Push-Location channel
    bun install --frozen-lockfile
    if ($LASTEXITCODE -ne 0) { throw "bun install ist fehlgeschlagen (Internetverbindung?)" }
    bun audit
    Pop-Location
    Write-Ok "Channel bereit"

    # ── 4. Optional: Gateway-Modus (eigener Anthropic-API-Key, kostet pro Anfrage) ──
    if (Test-Path server) {
        Write-Step "Gateway-Modus (optional)"
        Write-Host "  Nur nötig, wenn du OHNE Claude Code mit eigenem API-Key arbeiten willst." -ForegroundColor Gray
        if ((Test-Command 'npm') -and (Ask "Gateway-Server einrichten?" $false)) {
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
    }

    # ── 5. Windows-Firewall: iPhone muss den PC erreichen (WLAN und ggf. Tailscale) ──
    if (-not $Unattended) {
        Write-Step "Windows-Firewall"
        $hasTailscale = [bool](Get-NetAdapter -Name 'Tailscale' -ErrorAction SilentlyContinue)
        $missing = (-not (Test-Rule 'RayBan Claude')) -or ($hasTailscale -and -not (Test-Rule 'RayBan Claude (Tailscale)'))
        if (-not $missing) {
            Write-Ok "Firewall-Regeln vorhanden"
        } else {
            Write-Host "  Damit das iPhone den PC erreicht, muss Port $Port im PRIVATEN Netzwerk offen sein" -ForegroundColor Gray
            Write-Host "  (und – falls installiert – für deine Tailscale-Geräte)." -ForegroundColor Gray
            if (Ask "Jetzt freigeben? Windows fragt dafür nach Administrator-Rechten.") {
                Start-Process powershell -Verb RunAs -Wait -ArgumentList @(
                    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSScriptRoot\firewall.ps1`"", '-Port', $Port)
            } else {
                Write-Warn "Alternativ beim ersten Start die Windows-Abfrage für 'Private Netzwerke' mit 'Zulassen' beantworten."
            }
        }
        if (-not $hasTailscale) {
            Write-Host "  Unterwegs über dein Claude-Abo? Tailscale (kostenlos) auf PC und iPhone installieren" -ForegroundColor Gray
            Write-Host "  (https://tailscale.com/download) und setup.cmd noch einmal starten." -ForegroundColor Gray
        }
    }

    $profiles = Get-NetConnectionProfile -ErrorAction SilentlyContinue | Where-Object { $_.NetworkCategory -eq 'Public' }
    if ($profiles) {
        Write-Warn "Dein WLAN ist als 'Öffentlich' eingestuft – dann blockt Windows das iPhone."
        Write-Host "    Einstellungen → Netzwerk & Internet → WLAN → Netzwerkprofil: Privat" -ForegroundColor Cyan
    }

    # ── Fertig ───────────────────────────────────────────────────────────────
    Write-Host ""
    Write-Host "  ✅ Fertig! So geht's weiter:" -ForegroundColor Green
    Write-Host "   1. 'RayBan Claude' starten (Desktop-Symbol oder start.cmd)"
    Write-Host "      Beim ersten Mal: bei Claude anmelden, 'Use this MCP server' und"
    Write-Host "      'I am using this for local development' bestätigen."
    Write-Host "   2. Das Dashboard öffnet sich: http://localhost:$Port"
    Write-Host "   3. iPhone-App installieren: docs\IPHONE-OHNE-MAC.md (kostenlos, mit Sideloadly)"
    Write-Host "   4. QR-Code im Dashboard mit der iPhone-Kamera scannen – fertig."
    Write-Host "   5. Unterwegs: mit Tailscale steckt die Unterwegs-Adresse automatisch im QR-Code."
    Write-Host ""
    if ($Unattended) { Start-Sleep -Seconds 3 }
} catch {
    Write-Host ""
    Write-Host "  ✗ Einrichtung abgebrochen: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "    Tipp: Internetverbindung prüfen und 'RayBan Claude – Einrichtung' noch einmal starten." -ForegroundColor Gray
    if ($Unattended) { Read-Host "  Enter zum Schließen" | Out-Null }
    exit 1
}
