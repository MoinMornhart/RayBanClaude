; RayBan Claude – Windows-Installer (Inno Setup 6)
;
; Baut RayBanClaude-Setup.exe: kopiert Channel und Skripte nach %LOCALAPPDATA%\Programs\RayBanClaude
; (keine Administrator-Rechte nötig), richtet Bun und Claude Code mit den offiziellen Installern ein,
; öffnet auf Wunsch die Windows-Firewall (fragt dann einmal nach Administrator-Rechten) und legt
; „RayBan Claude“ auf den Desktop und ins Startmenü.
;
; Gebaut wird in GitHub Actions (.github/workflows/windows-installer.yml):
;   ISCC.exe /DAppVersion=2.0.0 installer\RayBanClaude.iss

#define AppName "RayBan Claude"
#ifndef AppVersion
  #define AppVersion "2.0.0"
#endif
#define RepoUrl "https://github.com/MoinMornhart/RayBanClaude"

[Setup]
AppId={{6C1F3B52-8E47-4C0A-9B6D-2F7E91A4C3D8}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=RayBan Claude (Open Source)
AppPublisherURL={#RepoUrl}
AppSupportURL={#RepoUrl}/issues
AppUpdatesURL={#RepoUrl}/releases
DefaultDirName={localappdata}\Programs\RayBanClaude
DisableProgramGroupPage=yes
DisableDirPage=auto
PrivilegesRequired=lowest
OutputDir=Output
OutputBaseFilename=RayBanClaude-Setup
SetupIconFile=RayBanClaude.ico
UninstallDisplayIcon={app}\RayBanClaude.ico
UninstallDisplayName={#AppName}
LicenseFile=..\LICENSE
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ShowLanguageDialog=no
; Bun braucht Windows 10 Version 1809 oder neuer
MinVersion=10.0.17763
CloseApplications=yes

[Languages]
Name: "de"; MessagesFile: "compiler:Languages\German.isl"

[Messages]
de.WelcomeLabel2=Damit sieht Claude, was du siehst – mit deiner Ray-Ban Meta (Gen 2) oder deinem iPhone.%n%nDer Installer richtet alles ein, was dein PC braucht: Bun und Claude Code (offizielle Installer, kostenlos) und den RayBan-Claude-Channel. Für Claude brauchst du ein Claude-Abo (Pro oder Max).%n%nInoffizielles Open-Source-Projekt – nicht verbunden mit Meta, Ray-Ban oder Anthropic.
de.FinishedLabel=RayBan Claude ist eingerichtet.%n%nBeim ersten Start meldest du dich einmal bei Claude an (der Browser öffnet sich) und bestätigst „Use this MCP server“. Danach öffnet sich das Dashboard – dort den QR-Code mit der iPhone-Kamera scannen.%n%nDie iPhone-App installierst du ohne Mac mit Sideloadly (Anleitung im Startmenü).

[Tasks]
Name: "desktopicon"; Description: "Symbol „RayBan Claude“ auf dem Desktop anlegen"
Name: "firewall"; Description: "Windows-Firewall für das iPhone öffnen (nur Heim-WLAN und Tailscale – fragt nach Administrator-Rechten)"

[Files]
Source: "..\channel\*"; DestDir: "{app}\channel"; Excludes: "\node_modules\*,\test\*,*.log"; Flags: recursesubdirs ignoreversion
Source: "..\.mcp.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\setup.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\setup.cmd"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\start.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\start.cmd"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\firewall.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\docs\IPHONE-OHNE-MAC.md"; DestDir: "{app}\docs"; Flags: ignoreversion
Source: "RayBanClaude.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\RayBan Claude\RayBan Claude"; Filename: "{app}\start.cmd"; WorkingDir: "{app}"; IconFilename: "{app}\RayBanClaude.ico"; Comment: "Claude mit Ray-Ban Meta und iPhone starten"
Name: "{autoprograms}\RayBan Claude\Einrichtung wiederholen"; Filename: "{app}\setup.cmd"; WorkingDir: "{app}"; IconFilename: "{app}\RayBanClaude.ico"
Name: "{autoprograms}\RayBan Claude\iPhone-App installieren (Anleitung)"; Filename: "{#RepoUrl}/blob/main/docs/IPHONE-OHNE-MAC.md"
Name: "{autoprograms}\RayBan Claude\RayBan Claude deinstallieren"; Filename: "{uninstallexe}"
Name: "{autodesktop}\RayBan Claude"; Filename: "{app}\start.cmd"; WorkingDir: "{app}"; IconFilename: "{app}\RayBanClaude.ico"; Comment: "Claude mit Ray-Ban Meta und iPhone starten"; Tasks: desktopicon

[Run]
; Bun, Claude Code (offizielle Installer) und die Channel-Abhängigkeiten – im sichtbaren Fenster
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\setup.ps1"" -Unattended"; WorkingDir: "{app}"; StatusMsg: "Richte Bun, Claude Code und den Channel ein …"; Flags: waituntilterminated
; Firewall: nur dieser Schritt braucht Administrator-Rechte
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\firewall.ps1"""; Verb: "runas"; StatusMsg: "Öffne die Windows-Firewall für das iPhone …"; Flags: shellexec waituntilterminated; Tasks: firewall
Filename: "{app}\start.cmd"; WorkingDir: "{app}"; Description: "RayBan Claude jetzt starten"; Flags: postinstall shellexec nowait skipifsilent
Filename: "{#RepoUrl}/blob/main/docs/IPHONE-OHNE-MAC.md"; Description: "Anleitung öffnen: App aufs iPhone (ohne Mac)"; Flags: postinstall shellexec nowait skipifsilent unchecked

[UninstallRun]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\firewall.ps1"" -Remove"; Verb: "runas"; Flags: shellexec waituntilterminated; RunOnceId: "FirewallEntfernen"

[UninstallDelete]
Type: filesandordirs; Name: "{app}\channel\node_modules"
