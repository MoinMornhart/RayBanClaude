<#
  RayBan Claude starten: Claude Code mit dem Channel + Dashboard im Browser.
  Normalerweise einfach start.cmd doppelklicken.

  Claude macht da weiter, wo ihr beim letzten Mal aufgehört habt (claude --continue) –
  so weiß es noch, worüber ihr über die Brille gesprochen habt. -Neu startet frisch.
#>
param([switch]$Neu)
Set-Location -Path $PSScriptRoot
# Frisch installierte Werkzeuge finden, auch wenn Windows den PATH noch nicht neu geladen hat
$env:Path = "$env:USERPROFILE\.bun\bin;$env:USERPROFILE\.local\bin;$env:Path"
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
Write-Host "  Antworten, Fotos, Handy-Aktionen und Gedächtnis sind vorab erlaubt; andere Tools fragst du auf dem Handy frei." -ForegroundColor Gray

# Frühere Brillen-Sitzung in diesem Ordner? Dann dort weitermachen (Claude Code speichert sie unter ~/.claude/projects)
$sessionDir = Join-Path $env:USERPROFILE (".claude\projects\" + ($PSScriptRoot -replace '[^A-Za-z0-9]', '-'))
$resume = @()
if (-not $Neu -and (Test-Path (Join-Path $sessionDir '*.jsonl'))) {
    $resume = @('--continue')
    Write-Host "  Setzt das letzte Gespräch fort (neues Gespräch: Startmenü → RayBan Claude → Neues Gespräch oder start.cmd -Neu)." -ForegroundColor Gray
}

# Vorab erlaubt sind nur die eigenen Werkzeuge von RayBan Claude – alles andere fragt weiter nach
# (auf Wunsch direkt auf dem Handy per Permission-Relay). Anrufe, Nachrichten und Navigation
# bestätigt der Nutzer ohnehin immer selbst auf dem iPhone.
claude @resume --dangerously-load-development-channels server:raybanclaude `
    --allowedTools "mcp__raybanclaude__reply" "mcp__raybanclaude__edit_message" "mcp__raybanclaude__request_photo" `
    "mcp__raybanclaude__phone_action" "mcp__raybanclaude__remember" "mcp__raybanclaude__forget"
