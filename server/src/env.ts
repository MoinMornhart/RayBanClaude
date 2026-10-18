// ── Umgebung laden ──────────────────────────────────────────────────
// Dieses Modul MUSS als erstes in index.ts importiert werden, damit die
// Variablen aus der .env gesetzt sind, bevor andere Module sie lesen.

import path from "node:path";
import { fileURLToPath } from "node:url";
import dotenv from "dotenv";

/** Wurzelverzeichnis des Servers (eine Ebene über src/ bzw. dist/). */
export const SERVER_ROOT = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  ".."
);

// .env aus dem server-Ordner laden – unabhängig vom Arbeitsverzeichnis.
// Bereits gesetzte Umgebungsvariablen haben Vorrang (kein override).
// Fehlt die Datei, passiert nichts (Variablen können auch direkt gesetzt sein).
dotenv.config({ path: path.join(SERVER_ROOT, ".env"), quiet: true });
