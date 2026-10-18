/**
 * Alle regulären Ausdrücke des Channel-Servers an einer Stelle.
 * Jede Regex trägt Beschreibung, Beispiele und einen vorausgefüllten Tester-Link.
 * Generiert – Beispiele bei Änderungen bitte mit anpassen.
 */

// Eine Zeile KEY=Wert aus der .env. Passt: "ELEVENLABS_API_KEY=abc → ("ELEVENLABS_API_KEY", "abc")"; lehnt ab: "# Kommentar".
// https://regex101.com/?flavor=javascript&regex=%5E%5Cs%2A%28%5BA-Z0-9_%5D%2B%29%5Cs%2A%3D%5Cs%2A%28.%2A%3F%29%5Cs%2A%24&flags=m&testString=ELEVENLABS_API_KEY%3Dabc%0A%23%20Kommentar
export const ENV_LINE = /^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/

// Umschließende Anführungszeichen eines .env-Werts (werden entfernt). Passt: "\"abc\"" → abc; lehnt ab: "abc (bleibt unverändert)".
// https://regex101.com/?flavor=javascript&regex=%5E%5B%22%27%5D%7C%5B%22%27%5D%24&flags=gm&testString=%22abc%22%0Aabc
export const ENV_QUOTES = /^["']|["']$/g

// Zeilenumbruch, Windows (CRLF) oder Unix (LF). Passt: "a\r\nb" → ["a", "b"]; lehnt ab: "ab" (kein Umbruch).
// https://regex101.com/?flavor=javascript&regex=%5Cr%3F%5Cn&flags=m&testString=a%0D%0Ab%0Aab
export const LINE_BREAK = /\r?\n/

// Channel-Token: 16–128 Zeichen aus Buchstaben, Ziffern, _ und -. Passt: "3f9ac01d77e2b4a5c6d7e8f901234567"; lehnt ab: "kurz", "token mit leerzeichen".
// https://regex101.com/?flavor=javascript&regex=%5E%5BA-Za-z0-9_-%5D%7B16%2C128%7D%24&flags=m&testString=3f9ac01d77e2b4a5c6d7e8f901234567%0Akurz%0Atoken%20mit%20leerzeichen
export const TOKEN = /^[A-Za-z0-9_-]{16,128}$/

// Steuerzeichen außer Tab und Zeilenumbruch (werden entfernt). Passt: "a\u0007b" → "ab"; lehnt ab: "a\nb" (Zeilenumbruch bleibt).
// https://regex101.com/?flavor=javascript&regex=%5B%5Cu0000-%5Cu0008%5Cu000B%5Cu000C%5Cu000E-%5Cu001F%5Cu007F%5D&flags=gm&testString=a%07b%0Aa%0Ab
export const CONTROL_CHARS = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g

// Nachrichten-ID: 1–64 Zeichen aus Buchstaben, Ziffern und . _ : -. Passt: "ios-1729273000.5", "rc1a2b-7"; lehnt ab: "../etc/passwd", "id mit leerzeichen".
// https://regex101.com/?flavor=javascript&regex=%5E%5BA-Za-z0-9._%3A-%5D%7B1%2C64%7D%24&flags=m&testString=ios-1729273000.5%0Arc1a2b-7%0A..%2Fetc%2Fpasswd%0Aid%20mit%20leerzeichen
export const MESSAGE_ID = /^[A-Za-z0-9._:-]{1,64}$/

// Alles außer Buchstaben, Ziffern, Leerzeichen und & / + . _ - (wird aus Modusnamen entfernt). Passt: "Elektriker 🔌" → "Elektriker "; lehnt ab: "Kfz-Mechaniker" (bleibt unverändert).
// https://regex101.com/?flavor=javascript&regex=%5B%5E%5Cp%7BL%7D%5Cp%7BN%7D%20%26%2F%2B._-%5D&flags=gum&testString=Elektriker%20%F0%9F%94%8C%0AKfz-Mechaniker
export const MODE_NAME_DISALLOWED = /[^\p{L}\p{N} &\/+._-]/gu

// HEIC/HEIF-Kennung in den Bytes 4–11 einer Bilddatei. Passt: "ftypheic", "ftypmif1"; lehnt ab: "ftypmp42 (MP4-Video)".
// https://regex101.com/?flavor=javascript&regex=%5Eftyp%28heic%7Cheix%7Cmif1%7Cmsf1%29%24&flags=m&testString=ftypheic%0Aftypmif1%0Aftypmp42
export const HEIC_BRAND = /^ftyp(heic|heix|mif1|msf1)$/

// Base64-Text (Standardalphabet, Zeilenumbrüche erlaubt). Passt: "/9j/4AAQSkZJRg=="; lehnt ab: "abc$%".
// https://regex101.com/?flavor=javascript&regex=%5E%5BA-Za-z0-9%2B%2F%3D%5Cr%5Cn%5D%2B%24&flags=m&testString=%2F9j%2F4AAQSkZJRg%3D%3D%0Aabc%24%25
export const BASE64 = /^[A-Za-z0-9+\/=\r\n]+$/

// Einfacher Dateiname ohne Pfadanteile. Passt: "tts-1729273000-ab12cd34.mp3"; lehnt ab: "../geheim.txt (enthält /)", "a b.mp3".
// https://regex101.com/?flavor=javascript&regex=%5E%5BA-Za-z0-9._-%5D%7B1%2C100%7D%24&flags=m&testString=tts-1729273000-ab12cd34.mp3%0A..%2Fgeheim.txt%0Aa%20b.mp3
export const FILE_NAME = /^[A-Za-z0-9._-]{1,100}$/

// ElevenLabs-API-Key: 20–128 Zeichen aus Buchstaben, Ziffern, _ und -. Passt: "sk_0123456789abcdef01234567"; lehnt ab: "mein key", "zu-kurz".
// https://regex101.com/?flavor=javascript&regex=%5E%5BA-Za-z0-9_-%5D%7B20%2C128%7D%24&flags=m&testString=sk_0123456789abcdef01234567%0Amein%20key%0Azu-kurz
export const ELEVENLABS_KEY = /^[A-Za-z0-9_-]{20,128}$/

// ElevenLabs-Stimmen-ID: 10–40 Buchstaben/Ziffern. Passt: "XB0fDUnXU5powFXDhCwa"; lehnt ab: "stimme-1".
// https://regex101.com/?flavor=javascript&regex=%5E%5BA-Za-z0-9%5D%7B10%2C40%7D%24&flags=m&testString=XB0fDUnXU5powFXDhCwa%0Astimme-1
export const VOICE_ID = /^[A-Za-z0-9]{10,40}$/

// Telefonnummer mit optionalem +, Leerzeichen, Klammern, / und -. Passt: "+49 170 1234567", "(0170) 123-456"; lehnt ab: "abc", "123".
// https://regex101.com/?flavor=javascript&regex=%5E%5C%2B%3F%5B0-9%20%28%29%2F-%5D%7B5%2C25%7D%24&flags=m&testString=%2B49%20170%201234567%0A%280170%29%20123-456%0Aabc%0A123
export const PHONE = /^\+?[0-9 ()\/-]{5,25}$/

// E-Mail-Adresse bzw. Apple-ID. Passt: "max.muster@icloud.com"; lehnt ab: "max@", "max@icloud".
// https://regex101.com/?flavor=javascript&regex=%5E%5BA-Za-z0-9._%25%2B-%5D%7B1%2C64%7D%40%5BA-Za-z0-9.-%5D%7B1%2C190%7D%5C.%5BA-Za-z%5D%7B2%2C24%7D%24&flags=m&testString=max.muster%40icloud.com%0Amax%40%0Amax%40icloud
export const EMAIL = /^[A-Za-z0-9._%+-]{1,64}@[A-Za-z0-9.-]{1,190}\.[A-Za-z]{2,24}$/

// Alles außer Ziffern und + (wird aus Telefonnummern entfernt). Passt: "+49 (170) 123" → "+49170123"; lehnt ab: "+49170123" (bleibt unverändert).
// https://regex101.com/?flavor=javascript&regex=%5B%5E0-9%2B%5D&flags=gm&testString=%22%2B49%0A%2B49170123
export const NON_PHONE_CHARS = /[^0-9+]/g

// IPv4-Adresse in Punktschreibweise. Passt: "192.168.1.20"; lehnt ab: "192.168.1", "192.168.1.20/24".
// https://regex101.com/?flavor=javascript&regex=%5E%28%5Cd%7B1%2C3%7D%5C.%29%7B3%7D%5Cd%7B1%2C3%7D%24&flags=m&testString=192.168.1.20%0A192.168.1%0A192.168.1.20%2F24
export const IPV4 = /^(\d{1,3}\.){3}\d{1,3}$/

// Hostname aus Labels mit Buchstaben, Ziffern und -. Passt: "mein-pc.local", "desktop"; lehnt ab: "evil.com/x", "a b".
// https://regex101.com/?flavor=javascript&regex=%5E%5BA-Za-z0-9-%5D%7B1%2C63%7D%28%5C.%5BA-Za-z0-9-%5D%7B1%2C63%7D%29%2A%24&flags=m&testString=mein-pc.local%0Adesktop%0Aevil.com%2Fx%0Aa%20b
export const HOSTNAME = /^[A-Za-z0-9-]{1,63}(\.[A-Za-z0-9-]{1,63})*$/

// Port am Ende eines Host-Headers (wird entfernt). Passt: "localhost:18790" → "localhost"; lehnt ab: "localhost" (bleibt unverändert).
// https://regex101.com/?flavor=javascript&regex=%3A%5Cd%2B%24&flags=m&testString=localhost%3A18790%0Alocalhost
export const PORT_SUFFIX = /:\d+$/

// Heimnetz-Adressbereich 192.168.0.0/16. Passt: "192.168.178.20"; lehnt ab: "192.169.1.1".
// https://regex101.com/?flavor=javascript&regex=%5E192%5C.168%5C.&flags=m&testString=192.168.178.20%0A192.169.1.1
export const LAN_192 = /^192\.168\./

// Privater Adressbereich 10.0.0.0/8. Passt: "10.0.0.7"; lehnt ab: "100.64.0.1".
// https://regex101.com/?flavor=javascript&regex=%5E10%5C.&flags=m&testString=10.0.0.7%0A100.64.0.1
export const LAN_10 = /^10\./

// Privater Adressbereich 172.16.0.0/12. Passt: "172.20.1.5"; lehnt ab: "172.32.0.1".
// https://regex101.com/?flavor=javascript&regex=%5E172%5C.%281%5B6-9%5D%7C2%5Cd%7C3%5B01%5D%29%5C.&flags=m&testString=172.20.1.5%0A172.32.0.1
export const LAN_172 = /^172\.(1[6-9]|2\d|3[01])\./

// CGNAT-Bereich 100.64.0.0/10 (z. B. Tailscale). Passt: "100.101.5.2"; lehnt ab: "100.128.0.1".
// https://regex101.com/?flavor=javascript&regex=%5E100%5C.%286%5B4-9%5D%7C%5B7-9%5D%5Cd%7C1%5B01%5D%5Cd%7C12%5B0-7%5D%29%5C.&flags=m&testString=100.101.5.2%0A100.128.0.1
export const CGNAT_100 = /^100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\./

// Link-Local-Adresse 169.254.0.0/16 (vom Handy nicht erreichbar). Passt: "169.254.10.3"; lehnt ab: "192.168.1.2".
// https://regex101.com/?flavor=javascript&regex=%5E169%5C.254%5C.&flags=m&testString=169.254.10.3%0A192.168.1.2
export const LINK_LOCAL = /^169\.254\./

// Name eines virtuellen Netzwerkadapters (WSL, Hyper-V, VMs, Docker, VPN). Passt: "vEthernet (WSL)", "VirtualBox Host-Only"; lehnt ab: "WLAN", "Ethernet".
// https://regex101.com/?flavor=javascript&regex=vethernet%7Cwsl%7Chyper-v%7Cvirtualbox%7Cvmware%7Cvbox%7Cdocker%7Cbr-%7Cutun%7Cloopback%7Cnpcap%7Czerotier&flags=im&testString=vEthernet%0AVirtualBox%20Host-Only%0AWLAN%0AEthernet
export const VIRTUAL_IFACE = /vethernet|wsl|hyper-v|virtualbox|vmware|vbox|docker|br-|utun|loopback|npcap|zerotier/i

// Tailscale-Adapter (bleibt trotz VPN nutzbar). Passt: "Tailscale"; lehnt ab: "Ethernet".
// https://regex101.com/?flavor=javascript&regex=tailscale&flags=im&testString=Tailscale%0AEthernet
export const TAILSCALE_IFACE = /tailscale/i

// Freigabe-ID von Claude Code: genau 5 Kleinbuchstaben a–z ohne l. Passt: "tbxkq"; lehnt ab: "abcdl (enthält l)", "ABCDE".
// https://regex101.com/?flavor=javascript&regex=%5E%5Ba-km-z%5D%7B5%7D%24&flags=m&testString=tbxkq%0Aabcdl%0AABCDE
export const PERMISSION_ID = /^[a-km-z]{5}$/

// WLAN-Adapter (wird bevorzugt, weil das Handy meist im WLAN hängt). Passt: "WLAN", "Wi-Fi", "en0"; lehnt ab: "Ethernet 2".
// https://regex101.com/?flavor=javascript&regex=wi-%3Ffi%7Cwlan%7Cwireless%7Cen0&flags=im&testString=WLAN%0AWi-Fi%0Aen0%0AEthernet%202
export const WIFI_IFACE = /wi-?fi|wlan|wireless|en0/i
