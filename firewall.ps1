<#
  RayBan Claude – Windows-Firewall freigeben (braucht Administrator-Rechte)

  Öffnet Port 18790 NUR im privaten Netzwerk (Heim-WLAN) und – falls Tailscale installiert ist –
  NUR auf dem Tailscale-Adapter für Geräte aus deinem eigenen Tailnet (100.64.0.0/10).
  Mit -Remove werden beide Regeln wieder entfernt (Deinstallation).
#>
param(
    [switch]$Remove,
    [int]$Port = 18790
)
$ErrorActionPreference = 'Stop'
$Lan = 'RayBan Claude'
$Tailnet = 'RayBan Claude (Tailscale)'

function Test-Rule($name) { [bool](Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue) }

try {
    if ($Remove) {
        foreach ($name in @($Lan, $Tailnet)) {
            if (Test-Rule $name) { Remove-NetFirewallRule -DisplayName $name }
        }
        Write-Host "  ✓ Firewall-Regeln von RayBan Claude entfernt" -ForegroundColor Green
        exit 0
    }
    if (-not (Test-Rule $Lan)) {
        New-NetFirewallRule -DisplayName $Lan -Direction Inbound -Protocol TCP -LocalPort $Port -Profile Private -Action Allow | Out-Null
    }
    Write-Host "  ✓ Heim-WLAN: Port $Port im privaten Netzwerk offen" -ForegroundColor Green
    if (Get-NetAdapter -Name 'Tailscale' -ErrorAction SilentlyContinue) {
        if (-not (Test-Rule $Tailnet)) {
            New-NetFirewallRule -DisplayName $Tailnet -Direction Inbound -Protocol TCP -LocalPort $Port `
                -InterfaceAlias 'Tailscale' -RemoteAddress 100.64.0.0/10 -Action Allow | Out-Null
        }
        Write-Host "  ✓ Unterwegs: Port $Port für deine Tailscale-Geräte offen" -ForegroundColor Green
    }
} catch {
    Write-Host "  ! Firewall konnte nicht eingerichtet werden: $($_.Exception.Message)" -ForegroundColor Yellow
    Start-Sleep -Seconds 6
    exit 1
}
