<p align="center">
  <img src="ios/RayBanClaude/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="112" alt="">
</p>

<h1 align="center">RayBan Claude</h1>

<p align="center">
  <b>Claude sieht, was du siehst.</b><br>
  Deine Ray-Ban Meta (Gen 2) oder dein iPhone werden zu Augen und Ohren von Claude –<br>
  über dein Claude-Abo auf deinem Windows-PC – zu Hause und unterwegs.
</p>

<p align="center">
  <a href="https://github.com/MoinMornhart/RayBanClaude/actions/workflows/ios-build.yml"><img src="https://github.com/MoinMornhart/RayBanClaude/actions/workflows/ios-build.yml/badge.svg" alt="iOS-App bauen"></a>
  <a href="https://github.com/MoinMornhart/RayBanClaude/actions/workflows/server-tests.yml"><img src="https://github.com/MoinMornhart/RayBanClaude/actions/workflows/server-tests.yml/badge.svg" alt="Server testen"></a>
  <img src="https://img.shields.io/badge/Windows-läuft-0078D4" alt="Windows">
  <img src="https://img.shields.io/badge/Lizenz-MIT-6b7280" alt="MIT">
</p>

<p align="center">
  <a href="https://moinmornhart.github.io/RayBanClaude/"><b>🌐 Projektseite</b></a> ·
  <a href="https://github.com/MoinMornhart/RayBanClaude/releases/latest"><b>⬇️ App herunterladen</b></a> ·
  <a href="#-schnellstart-windows">Schnellstart</a> ·
  <a href="#-unterwegs-über-dein-claude-abo">Unterwegs</a> ·
  <a href="docs/IPHONE-OHNE-MAC.md">iPhone-App ohne Mac</a> ·
  <a href="#-häufige-fragen">FAQ</a> ·
  <a href="docs/BUGFIXES.md">39 behobene Bugs</a>
</p>

<p align="center">
  <img src="docs/images/app-gespraech.png" width="250" alt="Gespräch: Claude liest das Typenschild einer Therme, ein Timer läuft">
  &nbsp;
  <img src="docs/images/app-anruf.png" width="250" alt="Rückfrage vor einem Anruf: Mama (Mobil) anrufen?">
  &nbsp;
  <img src="docs/images/app-einstellungen.png" width="250" alt="Einstellungen: Heim-Adresse, Unterwegs-Adresse (Tailscale) und Token">
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
| „Hey Claude, merk dir, dass meine Tochter Mia heißt“ | Claude behält es – auch morgen, mit und ohne PC |
| „Claudi, was weißt du über mich?“ / „Vergiss das mit dem Espresso“ | Antwort aus dem Gedächtnis bzw. Eintrag gelöscht |
| „Hey Claude, schick das Foto per Mail an mein Team“ *(mit PC)* | Claude nutzt deine MCP-Werkzeuge in Claude Code |

Nach einer Antwort hört die App ein paar Sekunden weiter zu – Rückfragen gehen also ohne Weckwort.

## ✨ Was RayBan Claude kann

| | |
|---|---|
| 👓 **Ray-Ban Meta Gen 2** | Offizielles Meta-SDK 1.0.1 – Video, Fotos, Akku und Bügel-Status |
| 🗣 **Freihändig** | Weckwort, Spracherkennung auf dem iPhone, Antwort per Stimme |
| 📱 **Handy-Aktionen** | Timer, Wecker, Anrufe, Nachrichten, Navigation – immer mit Bestätigung |
| 🧰 **Alle deine Tools** | Mit PC nutzt Claude deine komplette Claude-Code-Sitzung inkl. MCP-Servern |
| 🌍 **Unterwegs übers Abo** | Mit Tailscale (kostenlos) erreicht die App deinen PC auch über mobile Daten |
| 🧠 **Gedächtnis** | „Merk dir …“ – Claude kennt dich beim nächsten Mal; Übernahme aus der Claude-App |
| 📶 **Notfalls ohne PC** | Direkt-Modus mit eigenem API-Key, schaltet automatisch um |
| 🔐 **Freigaben am Handy** | Will Claude ein Werkzeug nutzen, fragt die App – „Ja“ genügt |
| 🎯 **11 Experten-Modi** | Übersetzer, Umgebung (Sehbehinderung), Kfz, Heizung, Sanitär, Elektriker (VDE), Arbeitsschutz (DGUV) … |
| 🔳 **QR-Kopplung** | QR-Code im Dashboard scannen – fertig |
| 🇩🇪 **Deutsch** | Oberfläche, Spracherkennung und Stimme |

## 🔀 Drei Wege zu Claude – die App wählt selbst

| | **Zu Hause** | **Unterwegs mit Tailscale** | **Ohne PC** (Notlösung) |
|---|---|---|---|
| Wie | iPhone → WLAN → Claude Code auf deinem PC | iPhone → mobile Daten → Tailscale → dein PC zu Hause | iPhone → Internet → Claude-API |
| Kosten | **im Claude-Abo** (Pro/Max) | **im Claude-Abo** – Tailscale privat kostenlos | eigener API-Key, ca. **1–3 Cent pro Frage** |
| Werkzeuge | alle MCP-Server und Skills deiner Sitzung | alle MCP-Server und Skills deiner Sitzung | Timer, Anrufe, Navigation, Fotos, Websuche |
| Voraussetzung | PC an, `start.cmd` läuft | dazu Tailscale auf PC und iPhone | API-Key in der App |

Die App probiert zu Hause erst das WLAN, unterwegs automatisch Tailscale – und nur wenn der PC gar nicht erreichbar
ist (und ein API-Key hinterlegt ist), fragt sie Claude direkt. Oben in der App steht, welcher Weg gerade läuft:
**PC**, **PC · unterwegs** oder **Direkt**.

```
 Ray-Ban Meta Gen 2 ──Bluetooth──▶ iPhone-App ──WLAN / Tailscale──▶ dein PC: Channel-Server ──▶ Claude Code (Abo)
   Kamera · Mikrofon ·              Weckwort ·    ╲                    Dashboard + QR            alle MCP-Tools
   Lautsprecher                     Gedächtnis     ╲──Internet──▶ Claude-API (ohne PC, API-Key)
```

## 🚀 Schnellstart (Windows)

1. **Herunterladen:** [ZIP laden](https://github.com/MoinMornhart/RayBanClaude/archive/refs/heads/main.zip) und entpacken – oder `git clone https://github.com/MoinMornhart/RayBanClaude.git`
2. **`setup.cmd` doppelklicken** – installiert bei Bedarf Bun und Claude Code, richtet alles ein, hilft bei der Firewall.
3. **`start.cmd` doppelklicken** – startet Claude Code mit RayBan Claude, das Dashboard öffnet sich.
   Beim ersten Mal *„Use this MCP server“* und *„I am using this for local development“* bestätigen ([warum?](#-häufige-fragen)).
4. **App aufs iPhone** – ohne Mac, kostenlos: [Anleitung](docs/IPHONE-OHNE-MAC.md)
5. **QR-Code scannen** und loslegen: *„Hey Claude, was siehst du?“*
6. *Optional für unterwegs:* [Tailscale einrichten](#-unterwegs-über-dein-claude-abo) – dann klappt es auch über mobile Daten.

macOS/Linux: `./setup.sh` und `./start.sh`.

<p align="center">
  <img src="docs/images/dashboard.png" width="640" alt="Dashboard am PC mit QR-Code zum Koppeln">
  <br><sub>Das Dashboard unter <code>http://localhost:18790</code> – nur am PC selbst erreichbar.</sub>
</p>

## 🌍 Unterwegs über dein Claude-Abo

Damit Claude auch beim Einkaufen oder auf der Baustelle über **dein Abo** läuft, verbindet sich die App über
[Tailscale](https://tailscale.com) mit deinem PC zu Hause – verschlüsselt, ohne Portfreigabe im Router, privat kostenlos.

1. **Tailscale auf dem PC** installieren ([Download](https://tailscale.com/download)) und anmelden.
2. **Tailscale auf dem iPhone** aus dem App Store laden, mit **demselben Konto** anmelden, VPN einschalten.
3. **`setup.cmd` noch einmal starten** – es findet Tailscale und gibt den Port nur für deine Tailscale-Geräte frei.
4. **`start.cmd`** starten. Im Dashboard steht jetzt *„🌍 Unterwegs: über Tailscale (100.…)“* – den
   **QR-Code einmal neu scannen**. Fertig.

Ab jetzt nimmt die App zu Hause das WLAN und unterwegs automatisch Tailscale. Der PC muss dafür eingeschaltet
bleiben und `start.cmd` laufen (Tipp: *Windows-Einstellungen → System → Energie → Ruhezustand: Nie*, solange er am Strom hängt).

## 🧠 Gedächtnis

Sag *„Hey Claude, merk dir …“* – oder Claude notiert sich selbst, was dauerhaft wichtig ist (Namen, Vorlieben,
Termine). Beim nächsten Gespräch weiß Claude es noch, egal ob über den PC oder direkt.

- **Ansehen und löschen:** *Einstellungen → Gedächtnis* (nach links wischen) oder *„Vergiss das mit …“*.
- **Aus der Claude-App übernehmen:** Eine fremde App kann deine Chats in der Claude-App nicht auslesen – dafür gibt
  es unter *Einstellungen → Gedächtnis → Aus der Claude-App übernehmen* eine fertige Frage. Die stellst du Claude in
  der Claude-App, fügst die Antwort ein, fertig.
- **Wo liegt das?** Nur auf deinem iPhone (verschlüsselt). Der PC hält eine Kopie nur im Arbeitsspeicher, solange die
  Sitzung läuft. Abschalten geht mit einem Schalter.

## 💶 Was kostet das?

| Teil | Kosten |
|---|---|
| Mit PC: Claude Code mit Claude-Abo (Pro/Max) | im Abo enthalten |
| Unterwegs übers Abo: Tailscale | **kostenlos** (privater Plan) |
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
- **Unterwegs nur über Tailscale** (verschlüsselt, nur deine eigenen Geräte) – nie per Portfreigabe im Router.
  Die Firewall-Regel gilt nur für den Tailscale-Adapter.
- **Gedächtnis nur auf dem iPhone**, verschlüsselt; Einträge gelten für Claude als Fakten, nicht als Anweisungen.
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
- **PC von unterwegs (über dein Abo):** mit [Tailscale](#-unterwegs-über-dein-claude-abo) – die App wechselt
  automatisch vom WLAN auf Tailscale. Der PC muss dafür eingeschaltet sein.
</details>

<details>
<summary><b>Läuft das unterwegs über mein Claude-Abo?</b></summary>

Ja – mit Tailscale. Dann spricht die App auch über mobile Daten mit Claude Code auf deinem PC zu Hause, und Claude Code
läuft über dein Abo. Nur der Direkt-Modus (ganz ohne PC) braucht einen API-Key: Anthropic erlaubt das Abo für die
Claude-Apps und Claude Code, nicht für fremde Apps, die direkt mit Claude sprechen.
</details>

<details>
<summary><b>Kennt Claude meine Chats aus der Claude-App?</b></summary>

Nicht von selbst – Anthropic bietet keine Schnittstelle, über die fremde Apps deine Chats lesen könnten (zum Glück).
Mit *Einstellungen → Gedächtnis → Aus der Claude-App übernehmen* holst du dir das Wichtigste in einem Schritt: Die
App gibt dir eine Frage für die Claude-App, du fügst Claudes Antwort ein. Danach merkt sich RayBan Claude selbst,
was du ihm erzählst.
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
cd channel && bun install && bun test      # 26 Tests (End-to-End + Hilfsfunktionen)
cd server && npm ci && npm run build       # Gateway
cd ios && xcodegen generate                # Xcode-Projekt (nur macOS)
```

| Ordner | Inhalt |
|---|---|
| `channel/` | Channel-Server (Bun): MCP-Channel, WebSocket für die App, Dashboard, Tools `reply`, `request_photo`, `phone_action`, `remember`, `forget` |
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
