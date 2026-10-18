// ── Konsolen-Design „RayBan Claude" ─────────────────────────────────
// Farbige Terminalausgabe. Farben werden abgeschaltet, wenn NO_COLOR gesetzt
// ist oder die Ausgabe nicht in ein Terminal geht (z. B. Log-Datei).

const useColor = !process.env.NO_COLOR && process.stdout.isTTY === true;

function ansi(code: string): string {
  return useColor ? code : "";
}

const ORANGE = ansi("\x1b[38;2;255;149;0m");
const DARK_ORANGE = ansi("\x1b[38;2;204;119;0m");
const LIGHT_ORANGE = ansi("\x1b[38;2;255;183;77m");
const WHITE = ansi("\x1b[1;37m");
const GRAY = ansi("\x1b[90m");
const GREEN = ansi("\x1b[32m");
const RED = ansi("\x1b[31m");
const YELLOW = ansi("\x1b[33m");
const CYAN = ansi("\x1b[36m");
const DIM = ansi("\x1b[2m");
const BOLD = ansi("\x1b[1m");
const RESET = ansi("\x1b[0m");

export const c = {
  orange: (text: string) => `${ORANGE}${text}${RESET}`,
  darkOrange: (text: string) => `${DARK_ORANGE}${text}${RESET}`,
  lightOrange: (text: string) => `${LIGHT_ORANGE}${text}${RESET}`,
  white: (text: string) => `${WHITE}${text}${RESET}`,
  gray: (text: string) => `${GRAY}${text}${RESET}`,
  green: (text: string) => `${GREEN}${text}${RESET}`,
  red: (text: string) => `${RED}${text}${RESET}`,
  yellow: (text: string) => `${YELLOW}${text}${RESET}`,
  cyan: (text: string) => `${CYAN}${text}${RESET}`,
  dim: (text: string) => `${DIM}${text}${RESET}`,
  bold: (text: string) => `${BOLD}${text}${RESET}`,

  // Semantische Helfer
  success: (text: string) => `${GREEN}${text}${RESET}`,
  error: (text: string) => `${RED}${text}${RESET}`,
  warn: (text: string) => `${YELLOW}${text}${RESET}`,
  info: (text: string) => `${CYAN}${text}${RESET}`,
  label: (text: string) => `${ORANGE}${text}${RESET}`,
  value: (text: string) => `${LIGHT_ORANGE}${text}${RESET}`,
  url: (text: string) => `${CYAN}${text}${RESET}`,
};

export function showBanner(): void {
  const lines = [
    "",
    `${ORANGE}   ██████╗  █████╗ ██╗   ██╗██████╗  █████╗ ███╗   ██╗${RESET}`,
    `${ORANGE}   ██╔══██╗██╔══██╗╚██╗ ██╔╝██╔══██╗██╔══██╗████╗  ██║${RESET}`,
    `${DARK_ORANGE}   ██████╔╝███████║ ╚████╔╝ ██████╔╝███████║██╔██╗ ██║${RESET}`,
    `${DARK_ORANGE}   ██╔══██╗██╔══██║  ╚██╔╝  ██╔══██╗██╔══██║██║╚██╗██║${RESET}`,
    `${LIGHT_ORANGE}   ██║  ██║██║  ██║   ██║   ██████╔╝██║  ██║██║ ╚████║${RESET}`,
    `${LIGHT_ORANGE}   ╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝   ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝${RESET}`,
    "",
    `${ORANGE}    ██████╗██╗      █████╗ ██╗   ██╗██████╗ ███████╗${RESET}`,
    `${ORANGE}   ██╔════╝██║     ██╔══██╗██║   ██║██╔══██╗██╔════╝${RESET}`,
    `${DARK_ORANGE}   ██║     ██║     ███████║██║   ██║██║  ██║█████╗  ${RESET}`,
    `${DARK_ORANGE}   ██║     ██║     ██╔══██║██║   ██║██║  ██║██╔══╝  ${RESET}`,
    `${LIGHT_ORANGE}   ╚██████╗███████╗██║  ██║╚██████╔╝██████╔╝███████╗${RESET}`,
    `${LIGHT_ORANGE}    ╚═════╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚══════╝${RESET}`,
    "",
    `${GRAY}   ──────────────────────────────────────────────────────${RESET}`,
    `${WHITE}    Claude sieht die Welt durch deine Brille${RESET}`,
    `${GRAY}   ──────────────────────────────────────────────────────${RESET}`,
    `${DIM}    Inoffizielles Projekt – nicht mit Meta, Ray-Ban oder${RESET}`,
    `${DIM}    Anthropic verbunden. Fork von visionclaude.${RESET}`,
    "",
  ];

  lines.forEach((line) => console.log(line));
}

// ── Info-Box nach dem Start ──

const BOX_INNER_WIDTH = 50;

/** Sichtbare Länge eines Strings (ohne ANSI-Farbcodes). */
function visibleLength(text: string): number {
  // Entfernt ANSI-Farbcodes: "\x1b[32mOK\x1b[0m" → "OK"; "OK" bleibt unverändert.
  // https://regex101.com/?flavor=javascript&regex=%5Cx1b%5C%5B%5B0-9%3B%5D*m&flags=g&testString=%1B%5B32mOK%1B%5B0m%0AOK
  // eslint-disable-next-line no-control-regex
  return text.replace(/\x1b\[[0-9;]*m/g, "").length;
}

function boxLine(content: string): string {
  const pad = Math.max(0, BOX_INNER_WIDTH - visibleLength(content));
  return `${ORANGE}   │${RESET} ${content}${" ".repeat(pad)}${ORANGE}│${RESET}`;
}

function boxRule(left: string, right: string): string {
  return `${ORANGE}   ${left}${"─".repeat(BOX_INNER_WIDTH + 1)}${right}${RESET}`;
}

export interface ServerInfo {
  port: number;
  model: string;
  mcpCount: number;
  toolCount: number;
  skillCount: number;
  lanAddresses: string[];
}

export function showServerInfo(info: ServerInfo): void {
  console.log("");
  console.log(boxRule("┌", "┐"));
  console.log(boxLine(`${GREEN}●${RESET} ${WHITE}Gateway aktiv${RESET}`));
  console.log(boxRule("├", "┤"));
  console.log(boxLine(`${GRAY}Port${RESET}     ${WHITE}${info.port}${RESET}`));
  console.log(boxLine(`${GRAY}Modell${RESET}   ${WHITE}${info.model}${RESET}`));
  console.log(
    boxLine(
      `${GRAY}MCP${RESET}      ${WHITE}${info.mcpCount} Server${RESET} ${GRAY}→${RESET} ${LIGHT_ORANGE}${info.toolCount} Werkzeug(e)${RESET}`
    )
  );
  console.log(boxLine(`${GRAY}Skills${RESET}   ${WHITE}${info.skillCount} geladen${RESET}`));
  info.lanAddresses.forEach((addr) =>
    console.log(boxLine(`${GRAY}Adresse${RESET}  ${CYAN}http://${addr}:${info.port}${RESET}`))
  );
  console.log(boxRule("├", "┤"));
  console.log(boxLine(`${CYAN}GET  /health${RESET}          ${DIM}Status (öffentlich)${RESET}`));
  console.log(boxLine(`${CYAN}GET  /health/details${RESET}  ${DIM}Details (Token)${RESET}`));
  console.log(boxLine(`${CYAN}GET  /tools${RESET}           ${DIM}MCP-Werkzeuge${RESET}`));
  console.log(boxLine(`${CYAN}GET  /skills${RESET}          ${DIM}Geladene Skills${RESET}`));
  console.log(boxLine(`${CYAN}POST /chat${RESET}            ${DIM}Nachricht + Bild${RESET}`));
  console.log(boxRule("└", "┘"));
  console.log(c.dim("   Alle Endpunkte außer GET /health verlangen das Gateway-Token."));
  console.log("");
}

/** Gibt das Gateway-Token aus, damit es in der App eingetragen werden kann. */
export function showToken(token: string, source: "env" | "file", filePath?: string): void {
  if (source === "env") {
    console.log(
      c.label("[Auth]") + " Gateway-Token stammt aus GATEWAY_API_KEY (Umgebung bzw. .env) – Wert wird nicht angezeigt."
    );
    return;
  }
  console.log(c.label("[Auth]") + " Gateway-Token (in der App unter Einstellungen eintragen):");
  console.log(`         ${BOLD}${LIGHT_ORANGE}${token}${RESET}`);
  if (filePath) {
    console.log(c.dim(`         gespeichert in ${filePath}`));
  }
}
