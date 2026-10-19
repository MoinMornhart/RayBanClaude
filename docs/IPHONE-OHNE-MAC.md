# iPhone-App installieren – ohne Mac, kostenlos

Apple erlaubt Apps außerhalb des App Stores nur signiert. Du brauchst dafür **keinen Mac
und kein bezahltes Entwicklerkonto**: Die App wird kostenlos in der Cloud gebaut
(GitHub Actions) und unter Windows mit **Sideloadly** und deiner **normalen Apple-ID**
aufs iPhone gebracht.

| Was | Kosten |
|---|---|
| App bauen (GitHub Actions, öffentliches Repo) | kostenlos |
| Sideloadly | kostenlos |
| Apple-ID (kein Developer-Programm nötig) | kostenlos |
| Einschränkung | App muss alle **7 Tage** neu signiert werden (Sideloadly kann das automatisch) |

## 1. IPA herunterladen

- **Einfach:** Auf der [Releases-Seite](https://github.com/MoinMornhart/RayBanClaude/releases/latest)
  die Datei `RayBanClaude.ipa` laden. Zum Prüfen liegt `RayBanClaude.ipa.sha256` daneben –
  unter Windows vergleichen mit: `Get-FileHash RayBanClaude.ipa -Algorithm SHA256`
- **Neuester Stand:** [Actions → „iOS-App bauen“](https://github.com/MoinMornhart/RayBanClaude/actions/workflows/ios-build.yml)
  → letzten grünen Lauf öffnen → unten unter *Artifacts* `RayBanClaude-ipa` laden und entpacken
  (dafür musst du bei GitHub angemeldet sein).

## 2. Sideloadly einrichten (Windows)

1. **iTunes und iCloud** von apple.com installieren – die Versionen *von der Apple-Webseite*,
   nicht aus dem Microsoft Store (Sideloadly braucht deren Treiber).
2. **Sideloadly** von <https://sideloadly.io> laden und installieren.
3. iPhone per **USB-Kabel** anschließen und auf dem iPhone „Diesem Computer vertrauen“ tippen.

## 3. App aufs iPhone

1. Sideloadly öffnen, `RayBanClaude.ipa` ins Fenster ziehen.
2. Deine **Apple-ID** eintragen → **Start**. (Das Passwort geht nur an Apple; nutze am besten
   ein App-spezifisches Passwort bzw. eine Zweit-Apple-ID, wenn du vorsichtig sein willst.)
3. Meldet Sideloadly, die Bundle-ID sei vergeben: unter *Advanced Options* eine eigene
   Bundle-ID wählen, z. B. `com.deinname.raybanclaude` (**ohne Bindestrich**).
4. Auf dem iPhone:
   - *Einstellungen → Allgemein → VPN & Geräteverwaltung →* deine Apple-ID → **Vertrauen**
   - *Einstellungen → Datenschutz & Sicherheit → Entwicklermodus →* **an** (iPhone startet neu)

## 4. Alle 7 Tage auffrischen

Mit einer kostenlosen Apple-ID läuft die Signatur nach 7 Tagen ab. In Sideloadly
„Automatic Refresh“ aktivieren (PC und iPhone im selben WLAN) – dann passiert das von selbst.
Alternativ einfach Schritt 3 wiederholen; Einstellungen und Kopplung bleiben erhalten.

> Mit einem bezahlten Apple-Developer-Konto (99 €/Jahr) hält die Signatur ein Jahr.
> Alternativen zu Sideloadly: AltStore oder SideStore.

## 5. Mit dem PC koppeln

1. Auf dem PC `start.cmd` doppelklicken → das Dashboard öffnet sich.
2. iPhone ins selbe WLAN, die normale **Kamera-App** auf den QR-Code halten.
3. „In RayBan Claude öffnen“ → **Koppeln** bestätigen. Fertig.

Für **unterwegs über dein Claude-Abo**: vorher Tailscale auf PC und iPhone einrichten – dann steckt die
Unterwegs-Adresse automatisch im QR-Code ([Anleitung](../README.md#-unterwegs-über-dein-claude-abo)).

## Ray-Ban Meta Gen 2 verbinden

1. Meta-AI-App → Einstellungen → deine Brille → **Entwicklermodus** an, Brille neu starten.
2. In RayBan Claude: Einstellungen → **Brille über Meta AI verbinden** → in der Meta-AI-App erlauben.
3. Unten rechts auf **Brille** tippen und die Kamera-Freigabe bestätigen.

Im Entwicklermodus brauchst du **keine** eigene Meta-App-ID. Erst wenn du die App über
Meta-Release-Channels an andere verteilen willst, trägst du sie in `ios/Secrets.xcconfig` ein.
