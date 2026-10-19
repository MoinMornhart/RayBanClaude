import type { DiscoveredTool } from "./types.js";

// ── Erlaubt-Liste für MCP-Werkzeuge ─────────────────────────────────
// Im Gateway-Modus gibt es keine Rückfrage pro Werkzeugaufruf. Text in einem
// Kamerabild könnte Claude zu Aktionen mit Außenwirkung verleiten
// (Prompt-Injection) – deshalb bekommt Claude nur freigegebene Werkzeuge.
//
// MCP_TOOL_ALLOWLIST (kommagetrennt):
//   (leer)            → nur Werkzeuge mit MCP-Annotation readOnlyHint = true
//   *                 → alle Werkzeuge (bewusst freischalten)
//   readonly          → alle als „nur lesend“ markierten Werkzeuge
//   werkzeug          → ein Werkzeug über seinen Namen
//   server/werkzeug   → ein Werkzeug eines bestimmten Servers
//   server/*          → alle Werkzeuge eines Servers

export interface ToolPolicy {
  readonly allows: (tool: DiscoveredTool) => boolean;
  readonly description: string;
}

const ENTRY_SEPARATOR = ",";
const SERVER_SEPARATOR = "/";
const ALL_TOOLS = "*";
const READ_ONLY_KEYWORD = "readonly";

const READ_ONLY_POLICY: ToolPolicy = {
  allows: (tool) => tool.readOnly,
  description: "nur lesende Werkzeuge (Standard; freischalten mit MCP_TOOL_ALLOWLIST)",
};

const ALLOW_ALL_POLICY: ToolPolicy = {
  allows: () => true,
  description: "alle Werkzeuge (MCP_TOOL_ALLOWLIST=*) – Achtung: keine Rückfrage vor Aktionen",
};

export function parseToolPolicy(raw: string | undefined): ToolPolicy {
  const entries = (raw ?? "")
    .split(ENTRY_SEPARATOR)
    .map((entry) => entry.trim())
    .filter(Boolean);

  if (!entries.length) return READ_ONLY_POLICY;
  if (entries.includes(ALL_TOOLS)) return ALLOW_ALL_POLICY;

  const rules: ReadonlySet<string> = new Set(entries);
  const includeReadOnly = rules.has(READ_ONLY_KEYWORD);
  return {
    allows: (tool) =>
      (includeReadOnly && tool.readOnly) ||
      rules.has(tool.name) ||
      rules.has(`${tool.serverName}${SERVER_SEPARATOR}${tool.name}`) ||
      rules.has(`${tool.serverName}${SERVER_SEPARATOR}${ALL_TOOLS}`),
    description: `Erlaubt-Liste: ${entries.join(", ")}`,
  };
}
