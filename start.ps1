<#
  RayBan Claude starten: Claude Code mit dem Channel + Dashboard im Browser.
  Normalerweise einfach start.cmd doppelklicken.
#>
Set-Location -Path $PSScriptRoot
$Port = if ($env:RAYBANCLAUDE_PORT) { $env:RAYBANCLAUDE_PORT } else { 18790 }

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Host "Claude Code fehlt – bitte zuerst setup.ps1 ausführen." -ForegroundColor Red
    Read-Host "Enter zum Beenden"
    exit 1
}
if (-not (Test-Path "channel\node_modules")) {
    Write-Host "Abhängigkeiten fehlen – bitte zuerst setup.ps1 ausführen." -ForegroundColor Red
    Read-Host "Enter zum Beenden"
    exit 1
}

# Dashboard öffnen, sobald der Channel läuft (Claude Code startet ihn ein paar Sekunden nach dem Start)
Start-Job -ArgumentList $Port -ScriptBlock {
    param($Port)
    for ($i = 0; $i -lt 90; $i++) {
        try {
            Invoke-WebRequest -Uri "http://localhost:$Port/health" -UseBasicParsing -TimeoutSec 2 | Out-Null
            Start-Process "http://localhost:$Port"
            return
        } catch { Start-Sleep -Seconds 1 }
    }
} | Out-Null

Write-Host "◉ RayBan Claude startet … Dashboard öffnet sich gleich im Browser." -ForegroundColor DarkYellow
Write-Host "  Antworten an das Handy sind vorab erlaubt; andere Tools fragst du auf dem Handy oder hier frei." -ForegroundColor Gray

# Nur die eigenen Antwort-Tools werden vorab erlaubt – alles andere fragt weiter nach
# (auf Wunsch direkt auf dem Handy per Permission-Relay).
claude --dangerously-load-development-channels server:raybanclaude `
    --allowedTools "mcp__raybanclaude__reply" "mcp__raybanclaude__edit_message" "mcp__raybanclaude__request_photo"
