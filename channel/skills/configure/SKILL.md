---
name: raybanclaude-configure
description: RayBan Claude Channel einrichten – Kopplung mit dem iPhone, optionale ElevenLabs-Stimme und Port
---

# RayBan Claude Channel einrichten

Der Channel speichert seine Einstellungen in `~/.claude/channels/raybanclaude/`
(Windows: `%USERPROFILE%\.claude\channels\raybanclaude\`).

## Koppeln (empfohlen)

1. Claude Code mit dem Channel starten:
   `claude --dangerously-load-development-channels server:raybanclaude`
2. Dashboard öffnen: <http://localhost:18790>
3. Den QR-Code mit der iPhone-Kamera scannen → „In RayBan Claude öffnen“ → bestätigen.

Handy und PC müssen im selben WLAN sein. Unter Windows beim ersten Start die
Firewall-Abfrage für **private Netzwerke** erlauben.

## Optionale Einstellungen (`.env` im Ordner oben)

```
# Natürlichere Stimme (kostenpflichtig, ohne Key spricht das iPhone kostenlos)
ELEVENLABS_API_KEY=<dein-elevenlabs-key>

# Stimme (Standard: Charlotte)
ELEVENLABS_VOICE_ID=XB0fDUnXU5powFXDhCwa

# Anderer Port (Standard 18790)
RAYBANCLAUDE_PORT=18790

# Dashboard bei jedem Start öffnen (1) bzw. nie öffnen (RAYBANCLAUDE_NO_BROWSER=1)
RAYBANCLAUDE_OPEN_DASHBOARD=0
```

ElevenLabs-Key und Stimme lassen sich auch direkt im Dashboard setzen.

## Token zurücksetzen

Datei `.channel-token` im Ordner oben löschen und Claude neu starten – danach
den QR-Code neu scannen.
