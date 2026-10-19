# Gefundene und behobene Bugs

Bestandsaufnahme des Original-Codes (mrdulasolutions/visionclaude, Stand `a6e9cc3`) und
was in RayBan Claude daraus wurde. Schweregrad: 🔴 kritisch · 🟠 hoch · 🟡 mittel · ⚪ gering.

## Kritisch – Projekt unbrauchbar oder offen

| # | Bereich | Problem | Lösung |
|---|---|---|---|
| 1 | 🔴 iOS | **App ließ sich nicht mehr bauen.** `from: "0.5.0"` löst auf Meta DAT 0.9.0 auf – dort gibt es `StreamSession` nicht mehr. | Portierung auf DAT **1.0.1** (DeviceSession → Camera → Stream), offiziell für Ray-Ban Meta **Gen 1 und Gen 2**. Cloud-Build per GitHub Actions grün. |
| 2 | 🔴 Repo | **Echter API-Key des Original-Autors** in `.claude/settings.local.json` im Repo. | Datei nicht übernommen, in `.gitignore`. (Der Original-Autor sollte den Key widerrufen.) |
| 3 | 🔴 Channel | **Token aus dem ganzen WLAN auslesbar**: `/token` prüfte nur den Host-Header – `curl -H "Host: localhost" http://PC-IP:18790/token` genügte. | Nur noch echte Loopback-Verbindungen + Host-/Origin-Prüfung (auch gegen DNS-Rebinding). |
| 4 | 🔴 Gateway | **Ohne `GATEWAY_API_KEY` komplett offen** auf `0.0.0.0`: jeder im WLAN konnte chatten, Tools ausführen, Systemprompt/Modell ändern. | Token immer Pflicht (wird automatisch erzeugt). |
| 5 | 🔴 iOS | Fremde **Meta-App-ID, Client-Token und Apple-Team-ID** des Original-Autors fest eingebaut. | Über `Config.xcconfig`/`Secrets.xcconfig`; im Entwicklermodus nicht nötig. |

## Sicherheit

| # | Bereich | Problem | Lösung |
|---|---|---|---|
| 6 | 🟠 Channel | **AppleScript-Injection** über die Apple-ID in `/send-sms` (Anführungszeichen → Code-Ausführung). | Werte als `argv`, Formatprüfung; nur noch macOS + lokal. |
| 7 | 🟠 Channel | **Pfad-Traversal** beim Speichern: Feld `source` landete ungeprüft im Dateinamen. | Whitelist `iphone`/`rayban`. |
| 8 | 🟠 Channel | `/files/*` (Sprachausgabe, Anhänge) **ohne Token** abrufbar – Auth-Prüfung stand hinter der Auslieferung. | Token nötig, Dateinamen-Whitelist. |
| 9 | 🟠 Channel | Beliebige Dateien als „Bild“ akzeptiert (Endung aus dem Dateinamen). | Prüfung der Magic Bytes (JPEG/PNG/HEIC), Größenlimit. |
| 10 | 🟠 Channel | **`.env`-Injection** über den ElevenLabs-Key (Zeilenumbruch → weitere Variablen). | Formatprüfung, Datei mit Rechten 0600. |
| 11 | 🟠 beide | Kein Schutz gegen **Token-Raten**, Vergleich nicht zeitkonstant. | `timingSafeEqual`, Sperre nach 10 Fehlversuchen für 15 Minuten. |
| 12 | 🟠 Gateway | `/health` verriet MCP-Server, Tools und Skills; **CORS `*`** erlaubte jeder Webseite den Zugriff. | Öffentlich nur „ok“, CORS entfernt, Security-Header (CSP, nosniff, …). |
| 13 | 🟠 Gateway | stdio-MCP-Server erbten **`ANTHROPIC_API_KEY`** und Gateway-Token. | Nur Standard-Umgebung + konfiguriertes `env`. |
| 14 | 🟠 iOS | Token und ElevenLabs-Key **im Klartext in UserDefaults**. | iOS-Schlüsselbund. |
| 15 | 🟡 beide | Interne Fehlertexte (SDK, Stacktraces) gingen an die App. | Neutrale Meldungen, Details nur im Log. |
| 16 | 🟡 Channel | Anhänge: Claude konnte jede Datei des PCs an die App schicken. | Nur Bilder, PDF, Text, Audio; max. 25 MB. |
| 17 | 🟡 Doku | `claude ... -p bypassPermissions` als „freihändig“ empfohlen – `-p` ist der Print-Modus, und Bypass schützt nicht vor Prompt-Injection über Kamerabilder. | Nur die eigenen Antwort-Tools vorab erlauben; andere Freigaben direkt am Handy. |

## Funktion

| # | Bereich | Problem | Lösung |
|---|---|---|---|
| 18 | 🟠 iOS | **Brille streamte nach „Stop“ weiter** (Task las `streamSession` erst, nachdem es `nil` war). | Sauberer Teardown Kamera → Session. |
| 19 | 🟠 iOS | **Bilder kamen um 90° gedreht** bei Claude an (Sensor-Ausrichtung). | `videoRotationAngle = 90`. |
| 20 | 🟠 iOS | Ohne Antwort hing die App **für immer bei „Denkt nach“** – jede weitere Frage wurde ignoriert. | Zustellbestätigung (10 s) und Antwort-Timeout. |
| 21 | 🟠 iOS | Spracherkennung und Stimme **fest auf Englisch** – Deutsch wurde nicht verstanden. | Sprache wählbar, Standard = Gerätesprache. |
| 22 | 🟠 Channel | **Verwaister Prozess** nach dem Beenden von Claude blockierte den Port („Port belegt“). | Prozess endet mit der MCP-Verbindung. |
| 23 | 🟠 Channel | **Absturz unter Windows/Linux** (macOS-Befehl `open`). | Plattformabhängig, abgesichert. |
| 24 | 🟠 Gateway | Jedes Kamerabild blieb in der History → **Kosten explodieren** pro Runde. | Bilder nur in der aktuellen Nachricht, History begrenzt. |
| 25 | 🟡 Channel | Anhänge aus `reply` wurden kopiert, aber **nie an die App geschickt**. | URLs in der Antwort, Anzeige im Verlauf. |
| 26 | 🟡 Channel | `edit_message` erzeugte eine **neue Nachricht** statt die alte zu ändern. | Eigener Nachrichtentyp `edit`. |
| 27 | 🟡 iOS | Gateway-Modus **nie wählbar**, sendete kein Token; Upload erwartete 204. | Auswahl in den Einstellungen, Token-Header, 2xx. |
| 28 | 🟡 iOS | Reconnect: Zähler nie erhöht, doppelte Reconnects, **URLSession-Leck**, Endlosschleife bei falschem Token. | Backoff, eine Verbindung, Stopp bei 401/429. |
| 29 | 🟡 iOS | Modus-Auswahl und Brillen-Status **aktualisierten sich nicht** (verschachtelte ObservableObjects). | Weiterleitung bzw. `@ObservedObject`. |
| 30 | 🟡 iOS | Zuhören brach still ab, Anzeige blieb auf „Hört zu“; Sätze wurden teils **doppelt** gesendet. | Rückmeldung bei Abbruch, Pause nur einmal verarbeitet. |
| 31 | 🟡 iOS | Audio-Session wurde ständig umgeschaltet – bei **Gen 2** führt das zu „Device unavailable“. | Einmal `.playAndRecord` + HFP, kein Wechsel auf `.playback`. |
| 32 | 🟡 iOS | **Absturz** bei ungültiger Host-Eingabe (`URL(...)!`); Port-Feld sprang beim Löschen auf 18790. | Optionale URLs, eigener Textzustand. |
| 33 | 🟡 Channel | Unter Windows **falsche IP** im Dashboard (WSL/Hyper-V-Adapter zuerst). | Ranking: WLAN/192.168.x zuerst, virtuelle Adapter zuletzt. |
| 34 | 🟡 Channel | `.env` mit Windows-Zeilenenden (CRLF) falsch gelesen. | CRLF-tolerant. |
| 35 | 🟡 Gateway | `HOME` unter Windows undefiniert; **Privatpfade des Original-Autors** hart codiert; Claude-Desktop-Config nur auf macOS. | `os.homedir()`, `SKILL_PATHS`, Pfade für Windows/Linux/Store-App. |
| 36 | 🟡 Gateway | Doppelte Tool-Namen ließen **jede Anfrage mit 400** scheitern; Skill-Inhalte kamen nie bei Claude an. | Kollisionen gefiltert, Tool `skill_laden`. |
| 37 | ⚪ Channel | Inbox/Outbox wuchsen unbegrenzt. | Aufräumen nach 24 h. |
| 38 | ⚪ iOS | Kamera-Stop während laufendem Start übersehen; neuer `CIContext` pro Bild; Display-Link erzeugte pro Frame eine Task; Puls-Animation unsichtbar. | Session-Queue, ein Context, direkte Aktualisierung. |
| 39 | ⚪ Setup | `.mcp.json` mit absoluten Pfaden des Original-Autors; Setup nur für macOS. | Relativer Pfad, `setup.cmd`/`start.cmd` für Windows. |

## Neu hinzugekommen

- **QR-Kopplung**: Dashboard zeigt QR-Code, iPhone-Kamera scannen, fertig (mit Sicherheitsabfrage).
- **Freigaben aufs Handy** (Permission-Relay): Tool-Freigaben per Knopf oder „Ja“/„Nein“.
- **Foto auf Anfrage**: Claude kann mit `request_photo` ein scharfes Foto mit der Brille auslösen.
- **Gen-2-Details**: Akku, Modell, Bügel-Status, automatischer Neustart beim Aufklappen.
- **Kostenloser Cloud-Build** der iPhone-App + Anleitung für Windows (Sideloadly).
- **Tests**: 12 End-to-End-Tests für den Channel, CI unter Windows/macOS/Linux.
- Deutsche Oberfläche, deutsche Modi (VDE, DGUV/ASR statt NEC/OSHA), neue Modi „Übersetzer“ und „Umgebung“.

## Offen / bekannte Grenzen

- Im WLAN läuft die Verbindung per **HTTP** (kein Zertifikat für LAN-IPs möglich) – geschützt durch Token.
  Für unterwegs: Tailscale o. Ä. statt Port-Freigabe im Router.
- **Prompt-Injection über Kamerabilder** (Text im Bild) lässt sich nicht vollständig verhindern –
  deshalb bleiben Tool-Freigaben aktiv und Claude soll vor Aktionen mit Außenwirkung nachfragen.
  Im Gateway-Modus (ohne Rückfragen) sind standardmäßig nur lesende Werkzeuge freigegeben (`MCP_TOOL_ALLOWLIST`).

## Nachgezogen nach dem Sicherheits-Check (2026-10-19)

- Gateway: Erlaubt-Liste für MCP-Werkzeuge, Standard = nur lesende Werkzeuge (`server/src/tool-policy.ts`).
- Channel: Token nur noch im `Authorization`-Header, nicht mehr als URL-Parameter (+ Test).
- `.gitignore`: `.env.*`, Schlüssel- und Zertifikatsdateien, lokale Datenbanken, Python-Caches.
- gitleaks-Fehlalarm (öffentliche Stimmen-ID) entschärft: Platzhalter + `.gitleaksignore` mit Begründung.
- Meta DAT 1.0.x hat bei Gen 2 ein bekanntes **Speicherleck** im Bluetooth-Puffer (~4 MB/min, Meta-Issue #324) –
  bei sehr langen Sitzungen App gelegentlich neu starten.
- Die iPhone-App ist in der Cloud gebaut, aber **noch nicht auf echter Hardware** (Brille + iPhone) getestet.

## Wie Meta AI: Kamera auf Zuruf, Hosentaschen-Modus (2026-10-19)

- Die Brille hat dauernd gefilmt (Akku, Wärme, Speicherleck im Meta-SDK #324) – jetzt nur noch Fotos auf Zuruf.
- Die Aufnahme wurde nach jedem Satz gestoppt; im Hintergrund darf iOS sie dann nicht neu starten – jetzt läuft sie durch.
- `request_photo` ließ Claude ewig warten, wenn kein Foto möglich war – jetzt kommt „Foto nicht möglich“ zurück.
- Ein anderes Bluetooth-Headset (z. B. im Auto) konnte der Brille das Mikrofon „wegnehmen“ – jetzt hat die Brille Vorrang.

## Nachgezogen mit „Unterwegs übers Abo“ und Gedächtnis (2026-10-19)

- **Eigener Fehler aus der ersten Fassung des Direkt-Modus:** Sprachbefehle prüften noch, ob der PC verbunden ist –
  ohne PC kam deshalb immer „Nicht verbunden“. Auch die Rückfrage nach einer Antwort und der Kamerastart beim
  Wechsel der Bildquelle hingen an der PC-Verbindung. Jetzt zählt, ob *irgendein* Weg zu Claude offen ist.
- Tote Verbindungen (z. B. WLAN weg, Tunnel unterbrochen) blieben bis zu zwei Minuten „verbunden“ – jetzt erkennt die
  App sie am Ping und am Netzwechsel und verbindet sofort neu (unterwegs über Tailscale).
- Offen: Die App schickt ihr Token im WLAN an die gespeicherte Heim-Adresse – auch in fremden WLANs, wie bisher.
  Mit mobilen Daten nimmt sie nur noch die Tailscale-Adresse. Eine gegenseitige Prüfung ohne Klartext-Token ist geplant.
