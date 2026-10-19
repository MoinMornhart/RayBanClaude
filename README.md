<p align="center">
  <img src="ios/RayBanClaude/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="112" alt="">
</p>

<h1 align="center">RayBan Claude</h1>

<p align="center">
  <b>Claude sieht, was du siehst.</b><br>
  Deine Ray-Ban Meta (Gen 2) oder dein iPhone werden zu Augen und Ohren von Claude –<br>
  zu Hause über deinen Windows-PC, unterwegs auch ohne.
</p>

<p align="center">
  <a href="https://github.com/MoinMornhart/RayBanClaude/actions/workflows/ios-build.yml"><img src="https://github.com/MoinMornhart/RayBanClaude/actions/workflows/ios-build.yml/badge.svg" alt="iOS-App bauen"></a>
  <a href="https://github.com/MoinMornhart/RayBanClaude/actions/workflows/server-tests.yml"><img src="https://github.com/MoinMornhart/RayBanClaude/actions/workflows/server-tests.yml/badge.svg" alt="Server testen"></a>
  <img src="https://img.shields.io/badge/Windows-läuft-0078D4" alt="Windows">
  <img src="https://img.shields.io/badge/Lizenz-MIT-6b7280" alt="MIT">
</p>

<p align="center">
  <a href="#-schnellstart-windows">Schnellstart</a> ·
  <a href="docs/IPHONE-OHNE-MAC.md">iPhone-App ohne Mac</a> ·
  <a href="#-häufige-fragen">FAQ</a> ·
  <a href="docs/BUGFIXES.md">39 behobene Bugs</a>
</p>

<p align="center">
  <img src="docs/images/app-gespraech.png" width="250" alt="Gespräch: Claude liest das Typenschild einer Therme, ein Timer läuft">
  &nbsp;
  <img src="docs/images/app-anruf.png" width="250" alt="Rückfrage vor einem Anruf: Mama (Mobil) anrufen?">
  &nbsp;
  <img src="docs/images/app-einstellungen.png" width="250" alt="Einstellungen mit Verbindung und Modus ohne PC">
</p>

---

## 🗣 Sag einfach „Hey Claude“

Die App hört freihändig zu – über das Mikrofon der Brille. Sag **„Hey Claude“** oder **„Claudi“**, ein kurzer Gong bestätigt, dann deine Frage:

| Du sagst | Was passiert |
|---|---|
| „Hey Claude, was siehst du?“ | Claude beschreibt das Kamerabild der Brille |
| „Claudi, was steht auf dem Schild?“ | Text wird gelesen – auf Wunsch übersetzt |
| „Hey Claude, stell einen Timer auf zehn Minuten für die Nudeln“ | Timer läuft auf dem iPhone, mit Ansage und Mitteilung |
| „Claudi, weck mich um halb sieben“ | Wecker um 06:30 |
| „Hey Claude, ruf Mama an“ | Kontakt wird **auf dem iPhone** gesucht, du bestätigst – Anruf |
| „Claudi, schreib Tom, dass ich zehn Minuten später komme“ | Nachricht wird vorbereitet, du tippst auf Senden |
| „Hey Claude, bring mich zum nächsten Bahnhof“ | Route in Apple Karten nach Rückfrage |
| „Hey Claude, mach ein scharfes Foto und lies die Seriennummer“ | Claude löst selbst ein Foto mit der Brille aus |
| „Hey Claude, schick das Foto per Mail an mein Team“ *(mit PC)* | Claude nutzt deine MCP-Werkzeuge in Claude Code |

Nach einer Antwort hört die App ein paar Sekunden weiter zu – Rückfragen gehen also ohne Weckwort.

## ✨ Was RayBan Claude kann

| | |
|---|---|
| 👓 **Ray-Ban Meta Gen 2** | Offizielles Meta-SDK 1.0.1 – Video, Fotos, Akku und Bügel-Status |
| 🗣 **Freihändig** | Weckwort, Spracherkennung auf dem iPhone, Antwort per Stimme |
| 📱 **Handy-Aktionen** | Timer, Wecker, Anrufe, Nachrichten, Navigation – immer mit Bestätigung |
| 🧰 **Alle deine Tools** | Mit PC nutzt Claude deine komplette Claude-Code-Sitzung inkl. MCP-Servern |
| 🌍 **Unterwegs ohne PC** | Direkt-Modus mit eigenem API-Key, schaltet automatisch um |
| 🔐 **Freigaben am Handy** | Will Claude ein Werkzeug nutzen, fragt die App – „Ja“ genügt |
| 🎯 **11 Experten-Modi** | Übersetzer, Umgebung (Sehbehinderung), Kfz, Heizung, Sanitär, Elektriker (VDE), Arbeitsschutz (DGUV) … |
| 🔳 **QR-Kopplung** | QR-Code im Dashboard scannen – fertig |
| 🇩🇪 **Deutsch** | Oberfläche, Spracherkennung und Stimme |

## 🔀 Mit PC oder ohne

| | **Mit PC** (zu Hause) | **Ohne PC** (unterwegs) |
|---|---|---|
| Wie | iPhone → WLAN → Claude Code auf deinem Windows-PC | iPhone → Internet → Claude-API |
| Kosten | **im Claude-Abo** (Pro/Max) – keine API-Kosten | eigener API-Key, ca. **1–3 Cent pro Frage** |
| Werkzeuge | alle MCP-Server und Skills deiner Claude-Sitzung | Timer, Anrufe, Navigation, Fotos, Websuche |
| Umschalten | automatisch: ist der PC nicht erreichbar, fragt die App direkt (wenn ein API-Key hinterlegt ist) |

```
 Ray-Ban Meta Gen 2 ──Bluetooth──▶ iPhone-App ──WLAN──▶ Windows-PC: Channel-Server ──▶ Claude Code
   Kamera · Mikrofon ·              Weckwort ·    ╲                   Dashboard + QR         alle MCP-Tools
   Lautsprecher                     Sprache       ╲──Internet──▶ Claude-API (ohne PC)
```

## 🚀 Schnellstart (Windows)

1. **Herunterladen:** [ZIP laden](https://github.com/MoinMornhart/RayBanClaude/archive/refs/heads/main.zip) und entpacken – oder `git clone https://github.com/MoinMornhart/RayBanClaude.git`
2. **`setup.cmd` doppelklicken** – installiert bei Bedarf Bun und Claude Code, richtet alles ein, hilft bei der Firewall.
3. **`start.cmd` doppelklicken** – startet Claude Code mit RayBan Claude, das Dashboard öffnet sich.
   Beim ersten Mal *„Use this MCP server“* und *„I am using this for local development“* bestätigen ([warum?](#-häufige-fragen)).
4. **App aufs iPhone** – ohne Mac, kostenlos: [Anleitung](docs/IPHONE-OHNE-MAC.md)
5. **QR-Code scannen** und loslegen: *„Hey Claude, was siehst du?“*

macOS/Linux: `./setup.sh` und `./start.sh`.

<p align="center">
  <img src="docs/images/dashboard.png" width="640" alt="Dashboard am PC mit QR-Code zum Koppeln">
  <br><sub>Das Dashboard unter <code>http://localhost:18790</code> – nur am PC selbst erreichbar.</sub>
</p>

## 💶 Was kostet das?

| Teil | Kosten |
|---|---|
| Mit PC: Claude Code mit Claude-Abo (Pro/Max) | im Abo enthalten |
| Ohne PC: Claude-API mit eigenem Key | Opus 5.5 ca. 1–3 ct/Frage · Sonnet 5.5 etwa die Hälfte · Haiku 5.5 ein Bruchteil · Websuche ca. 1 ct |
| Sprachausgabe | **kostenlose iPhone-Stimme** (ElevenLabs optional) |
| iPhone-App bauen | **kostenlos** per GitHub Actions |
| App aufs iPhone | **kostenlos** mit Sideloadly + normaler Apple-ID (alle 7 Tage auffrischen) |

## 👓 Ray-Ban Meta Gen 2 einrichten

1. Meta-AI-App (ab Version 290) → Einstellungen → Brille → **Entwicklermodus an** → Brille neu starten
2. RayBan Claude → Einstellungen → **Brille über Meta AI verbinden** → in der Meta-AI-App erlauben
3. Unten rechts auf **Brille** tippen und die Kamera-Freigabe bestätigen

Im Entwicklermodus ist **keine** eigene Meta-App-ID nötig. Bügel zu = Stream aus; beim Aufklappen verbindet die App neu.

## 🔐 Sicherheit & Datenschutz

- **Token** (48 Zeichen) für jede Verbindung, nur im Header; nach 10 Fehlversuchen 15 Minuten Sperre.
- **Dashboard nur am PC** selbst erreichbar (Schutz gegen DNS-Rebinding), strikte Content-Security-Policy.
- **Spracherkennung auf dem iPhone**, Kontakte werden nur lokal gesucht – Telefonnummern gehen nie an Claude.
- **Keys im Schlüsselbund** des iPhones (Channel-Token, Anthropic- und ElevenLabs-Key).
- **Freigaben bleiben an:** vorab erlaubt sind nur die Antwort-Tools. Anrufe, Nachrichten und Navigation bestätigst du immer selbst.
  Bitte **nicht** mit `--dangerously-skip-permissions` starten – Text in Kamerabildern kann Anweisungen enthalten (Prompt-Injection).
- Gateway-Modus ohne Rückfragen: standardmäßig nur lesende MCP-Werkzeuge (`MCP_TOOL_ALLOWLIST`).

## ❓ Häufige Fragen

<details>
<summary><b>Warum braucht der Start <code>--dangerously-load-development-channels</code>?</b></summary>

Channels sind in Claude Code eine Forschungsvorschau. Ohne diesen Schalter lädt Claude Code nur Channel-Plugins,
die Anthropic geprüft und freigegeben hat (`--channels plugin:…`). RayBan Claude ist (noch) nicht auf dieser Liste –
für eigene, lokal liegende Channels ist der Schalter der offizielle Weg.

Was der Schalter **nicht** tut: Er schaltet keine Rückfragen oder Berechtigungen ab, sondern überspringt nur die
Freigabeliste für diese eine Sitzung. Lade damit nur Code, dem du vertraust – RayBan Claude ist Open Source und läuft
komplett auf deinem PC. Jeder Absender muss sich per Token ausweisen, und Werkzeug-Freigaben bleiben aktiv.
</details>

<details>
<summary><b>Geht das auch, wenn das iPhone nicht mit dem PC verbunden ist?</b></summary>

Ja, auf zwei Arten:

- **Ohne PC (Direkt-Modus):** In der App unter *Einstellungen → Ohne PC* einen Anthropic-API-Key eintragen
  ([hier erstellen](https://console.anthropic.com/settings/keys)). Ist der PC nicht erreichbar, fragt die App automatisch
  direkt bei Claude – auch über mobile Daten. Kostet ein paar Cent pro Frage; PC-Werkzeuge gibt es dann nicht.
- **PC von unterwegs (kostenlos):** [Tailscale](https://tailscale.com) (privat kostenlos) auf PC und iPhone installieren,
  im Dashboard die Tailscale-Adresse (`100.…`) wählen und den QR-Code scannen. Der PC muss dafür eingeschaltet sein;
  die Firewall-Regel ggf. auch für das Tailscale-Netz erlauben. Bitte keine Portfreigabe im Router.
</details>

<details>
<summary><b>Kann ich im Direkt-Modus mein Claude-Abo nutzen?</b></summary>

Nein. Das Abo gilt für Claude-Apps und Claude Code, nicht für fremde Apps. Mit PC läuft RayBan Claude über Claude Code
und damit über dein Abo – ohne PC braucht es einen API-Key.
</details>

<details>
<summary><b>Funktioniert „Hey Claude“ auch bei gesperrtem iPhone?</b></summary>

Die App muss geöffnet sein. Solange sie im Vordergrund läuft, verhindert sie das automatische Sperren – das iPhone kann
also in der Tasche bleiben, während du über die Brille sprichst. Hintergrundbetrieb ist noch nicht getestet.
</details>

<details>
<summary><b>Brauche ich einen Mac oder ein Apple-Entwicklerkonto?</b></summary>

Nein. Die App wird kostenlos in der Cloud gebaut und unter Windows mit Sideloadly und deiner normalen Apple-ID
installiert: [Anleitung](docs/IPHONE-OHNE-MAC.md).
</details>

<details>
<summary><b>Gibt es eine Android-Version?</b></summary>

Noch nicht. Meta bietet das Brillen-SDK auch für Android an – Mitarbeit ist willkommen.
</details>

## 🛠 Für Entwickler

```bash
cd channel && bun install && bun test      # 15 End-to-End-Tests
cd server && npm ci && npm run build       # Gateway
cd ios && xcodegen generate                # Xcode-Projekt (nur macOS)
```

| Ordner | Inhalt |
|---|---|
| `channel/` | Channel-Server (Bun): MCP-Channel, WebSocket für die App, Dashboard, Tools `reply`, `request_photo`, `phone_action` |
| `server/` | Gateway (Node, optional): eigener Server mit API-Key und MCP-Client |
| `ios/` | iPhone-App (SwiftUI, Meta DAT SDK 1.0.1); Projekt per XcodeGen, Cloud-Build per GitHub Actions |
| `docs/` | Anleitungen, [Bug-Liste](docs/BUGFIXES.md), Projektseite |

Mehr: [ARCHITECTURE.md](ARCHITECTURE.md) · [CONTRIBUTING.md](CONTRIBUTING.md)

## 📄 Lizenz

MIT – siehe [LICENSE](LICENSE). Fork von [mrdulasolutions/visionclaude](https://github.com/mrdulasolutions/visionclaude),
ursprünglicher Code © 2026 MR Dula Solutions. Die Nutzung des Meta Wearables Device Access Toolkit unterliegt den
[Meta Wearables Developer Terms](https://wearables.developer.meta.com/terms).

<sub>Inoffizielles Projekt – nicht verbunden mit Meta Platforms, Ray-Ban/EssilorLuxottica oder Anthropic.
Ray-Ban und Meta sind Marken ihrer Inhaber, Claude ist eine Marke von Anthropic.</sub>

---

<p align="center">Verfasst mit Claude 🤖</p>
