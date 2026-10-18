import { randomBytes } from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { c } from "./console-theme.js";

// ── Gateway-Token ───────────────────────────────────────────────────
// Das Token ist IMMER Pflicht, weil der Server im ganzen WLAN erreichbar ist.
// Quelle 1: GATEWAY_API_KEY aus der .env.
// Quelle 2: automatisch erzeugtes Token in ~/.raybanclaude/gateway-token
//           (32 Zufallsbytes, hex), wird beim ersten Start angelegt und
//           danach wiederverwendet.

const TOKEN_BYTES = 32;
const TOKEN_DIR_NAME = ".raybanclaude";
const TOKEN_FILE_NAME = "gateway-token";
const TOKEN_DIR_MODE = 0o700;
const TOKEN_FILE_MODE = 0o600;
const ERROR_CODE_NOT_FOUND = "ENOENT";

// Selbst gesetztes Token: 16–256 Zeichen aus A–Z, a–z, 0–9 und ._~+/=-
// Akzeptiert "testtoken1234567890", lehnt "kurz" und Tokens mit Leerzeichen ab.
// https://regex101.com/?flavor=javascript&regex=%5E%5BA-Za-z0-9._~%2B%2F%3D-%5D%7B16%2C256%7D%24&flags=gm&testString=testtoken1234567890%0Akurz
const ENV_TOKEN_PATTERN = /^[A-Za-z0-9._~+/=-]{16,256}$/;

// Automatisch erzeugtes Token: genau 64 Kleinbuchstaben-Hex-Zeichen.
// Akzeptiert "aaaa…" (64× a), lehnt "XYZ" ab.
// https://regex101.com/?flavor=javascript&regex=%5E%5Ba-f0-9%5D%7B64%7D%24&flags=gm&testString=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa%0AXYZ
const FILE_TOKEN_PATTERN = /^[a-f0-9]{64}$/;

export type TokenSource = "env" | "file";

export interface GatewayToken {
  readonly value: string;
  readonly source: TokenSource;
  readonly filePath?: string;
}

/** Fehler in der Token-Konfiguration (führt zum Abbruch des Starts). */
export class TokenConfigError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "TokenConfigError";
  }
}

function isErrnoException(err: unknown): err is NodeJS.ErrnoException {
  return err instanceof Error && "code" in err;
}

/** Liest ein gespeichertes Token; null, wenn keins (gültiges) vorhanden ist. */
function readStoredToken(filePath: string): string | null {
  try {
    const content = fs.readFileSync(filePath, "utf8").trim();
    if (FILE_TOKEN_PATTERN.test(content)) {
      return content;
    }
    console.warn(
      c.label("[Auth]") +
        c.warn(" Gespeichertes Gateway-Token hat ein ungültiges Format – es wird ein neues erzeugt.")
    );
    return null;
  } catch (err) {
    if (isErrnoException(err) && err.code === ERROR_CODE_NOT_FOUND) {
      return null;
    }
    throw err;
  }
}

/** Setzt die Dateirechte auf 0600 (unter Windows schützt die ACL des Benutzerprofils). */
function restrictPermissions(filePath: string): void {
  try {
    fs.chmodSync(filePath, TOKEN_FILE_MODE);
  } catch (err) {
    console.warn(
      c.label("[Auth]") + c.warn(" Dateirechte des Token-Files konnten nicht gesetzt werden:"),
      err
    );
  }
}

/** Erzeugt ein neues Zufallstoken und speichert es mit Rechten 0600. */
function createStoredToken(dir: string, filePath: string): string {
  const token = randomBytes(TOKEN_BYTES).toString("hex");
  fs.mkdirSync(dir, { recursive: true, mode: TOKEN_DIR_MODE });
  fs.writeFileSync(filePath, `${token}\n`, { encoding: "utf8", mode: TOKEN_FILE_MODE });
  // mode wirkt nur beim Neuanlegen – bei überschriebener Datei explizit setzen
  restrictPermissions(filePath);
  console.log(c.label("[Auth]") + c.success(" Neues Gateway-Token erzeugt und gespeichert."));
  return token;
}

/** Ermittelt das Gateway-Token (aus .env oder Token-Datei, sonst neu erzeugt). */
export function resolveGatewayToken(): GatewayToken {
  const fromEnv = process.env.GATEWAY_API_KEY?.trim();
  if (fromEnv) {
    if (!ENV_TOKEN_PATTERN.test(fromEnv)) {
      throw new TokenConfigError(
        "GATEWAY_API_KEY ist ungültig: 16–256 Zeichen, erlaubt sind A–Z, a–z, 0–9 und ._~+/=-"
      );
    }
    return { value: fromEnv, source: "env" };
  }

  const dir = path.join(os.homedir(), TOKEN_DIR_NAME);
  const filePath = path.join(dir, TOKEN_FILE_NAME);
  const stored = readStoredToken(filePath);
  if (stored) {
    restrictPermissions(filePath);
    return { value: stored, source: "file", filePath };
  }
  return { value: createStoredToken(dir, filePath), source: "file", filePath };
}
