import fs from "node:fs";
import { readFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { SSEClientTransport } from "@modelcontextprotocol/sdk/client/sse.js";
import {
  getDefaultEnvironment,
  StdioClientTransport,
} from "@modelcontextprotocol/sdk/client/stdio.js";
import { StreamableHTTPClientTransport } from "@modelcontextprotocol/sdk/client/streamableHttp.js";
import { c } from "./console-theme.js";
import type { DiscoveredTool, MCPServerConfig, Tool } from "./types.js";

// ── MCP-Manager ─────────────────────────────────────────────────────
// Verbindet sich mit MCP-Servern (lokal per stdio oder entfernt per
// StreamableHTTP/SSE) und stellt deren Werkzeuge Claude zur Verfügung.
//
// Konfigurationsquelle:
//   - MCP_CONFIG_PATH gesetzt → ausschließlich diese Datei
//   - sonst die Claude-Desktop-Konfiguration des Betriebssystems

const CLIENT_INFO = { name: "raybanclaude-gateway", version: "1.1.0" } as const;
const DESKTOP_CONFIG_FILE = "claude_desktop_config.json";
const ALLOWED_URL_PROTOCOLS: ReadonlySet<string> = new Set(["http:", "https:"]);
const MSIX_PACKAGE_PREFIX = "Claude_";

// Gültige Werkzeugnamen der Claude API: 1–64 Zeichen aus a–z, A–Z, 0–9, "_" und "-".
// Akzeptiert "read_file", lehnt "server.read file" ab.
// https://regex101.com/?flavor=javascript&regex=%5E%5Ba-zA-Z0-9_-%5D%7B1%2C64%7D%24&flags=gm&testString=read_file%0Aserver.read%20file
const TOOL_NAME_PATTERN = /^[a-zA-Z0-9_-]{1,64}$/;

type ServerType = "stdio" | "remote";

interface ConnectedServer {
  readonly name: string;
  readonly client: Client;
  readonly tools: readonly DiscoveredTool[];
  readonly type: ServerType;
}

export interface ServerStatus {
  readonly name: string;
  readonly toolCount: number;
  readonly type: ServerType;
}

// ── Konfiguration ──

/** Mögliche Pfade der Claude-Desktop-Konfiguration je nach Betriebssystem. */
function desktopConfigCandidates(): string[] {
  const home = os.homedir();
  const byPlatform: Partial<Record<NodeJS.Platform, () => string[]>> = {
    darwin: () => [path.join(home, "Library", "Application Support", "Claude", DESKTOP_CONFIG_FILE)],
    win32: () => {
      const appData = process.env.APPDATA ?? path.join(home, "AppData", "Roaming");
      const localAppData = process.env.LOCALAPPDATA ?? path.join(home, "AppData", "Local");
      const packagesDir = path.join(localAppData, "Packages");
      // Claude aus dem Microsoft Store (MSIX) legt seine Daten virtualisiert ab
      const msixConfigs = safeReadDir(packagesDir)
        .filter((entry) => entry.startsWith(MSIX_PACKAGE_PREFIX))
        .map((entry) =>
          path.join(packagesDir, entry, "LocalCache", "Roaming", "Claude", DESKTOP_CONFIG_FILE)
        );
      return [path.join(appData, "Claude", DESKTOP_CONFIG_FILE), ...msixConfigs];
    },
  };
  const linux = (): string[] => [
    path.join(process.env.XDG_CONFIG_HOME ?? path.join(home, ".config"), "Claude", DESKTOP_CONFIG_FILE),
  ];
  return (byPlatform[process.platform] ?? linux)();
}

function safeReadDir(dir: string): string[] {
  try {
    return fs.readdirSync(dir);
  } catch {
    // Ordner existiert nicht (z. B. keine Store-Installation) – kein Fehler
    return [];
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isStringRecord(value: unknown): value is Record<string, string> {
  return isRecord(value) && Object.values(value).every((v) => typeof v === "string");
}

function isStringArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.every((v) => typeof v === "string");
}

/** Gibt eine URL ohne Query/Fragment fürs Log aus (dort stehen oft Tokens). */
function loggableUrl(url: URL): string {
  return `${url.origin}${url.pathname}`;
}

/** Prüft einen Servereintrag aus der Konfigurationsdatei (Whitelist der Felder). */
function parseServerConfig(name: string, raw: unknown): MCPServerConfig | null {
  const reject = (reason: string): null => {
    console.warn(c.label("[MCP]") + c.warn(` Server „${name}“ übersprungen: ${reason}`));
    return null;
  };
  if (!isRecord(raw)) return reject("Eintrag ist kein Objekt");
  if (raw.env !== undefined && !isStringRecord(raw.env)) return reject("„env“ muss Strings enthalten");
  if (raw.headers !== undefined && !isStringRecord(raw.headers)) return reject("„headers“ muss Strings enthalten");
  if (raw.args !== undefined && !isStringArray(raw.args)) return reject("„args“ muss ein String-Array sein");

  if (typeof raw.url === "string" && raw.url) {
    const parsed = URL.canParse(raw.url) ? new URL(raw.url) : null;
    if (!parsed || !ALLOWED_URL_PROTOCOLS.has(parsed.protocol)) {
      return reject("„url“ muss eine http(s)-URL sein");
    }
    return { url: raw.url, headers: raw.headers };
  }
  if (typeof raw.command === "string" && raw.command.trim()) {
    return { command: raw.command, args: raw.args, env: raw.env };
  }
  return reject("weder „command“ noch „url“ angegeben");
}

async function readConfigFile(filePath: string): Promise<Record<string, MCPServerConfig>> {
  const parsed: unknown = JSON.parse(await readFile(filePath, "utf-8"));
  const servers = isRecord(parsed) && isRecord(parsed.mcpServers) ? parsed.mcpServers : {};
  return Object.fromEntries(
    Object.entries(servers).flatMap(([name, raw]) => {
      const config = parseServerConfig(name, raw);
      return config ? [[name, config] as const] : [];
    })
  );
}

// ── Werkzeug-Ergebnisse ──

export class MCPToolError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "MCPToolError";
  }
}

export class MCPManager {
  private readonly servers = new Map<string, ConnectedServer>();
  private readonly toolToServer = new Map<string, string>(); // Werkzeugname → Servername

  /** @param reservedToolNames Namen, die lokal belegt sind (z. B. "skill_laden") */
  constructor(private readonly reservedToolNames: ReadonlySet<string> = new Set()) {}

  async initialize(): Promise<void> {
    const config = await this.loadConfig();
    const entries = Object.entries(config);

    if (!entries.length) {
      console.log(c.label("[MCP]") + c.dim(" Keine MCP-Server konfiguriert"));
      return;
    }

    console.log(c.label("[MCP]") + ` Verbinde mit ${entries.length} Server(n)...`);

    const results = await Promise.allSettled(
      entries.map(([name, cfg]) => this.connectServer(name, cfg))
    );

    // In Konfigurationsreihenfolge registrieren → deterministische Werkzeugliste
    results.forEach((result, index) => {
      const name = entries[index][0];
      if (result.status === "fulfilled") {
        this.register(result.value);
      } else {
        console.error(
          c.label("[MCP]") + c.error(` Verbindung zu „${name}“ fehlgeschlagen: `),
          result.reason
        );
      }
    });

    console.log(
      c.label("[MCP]") +
        c.success(
          ` ${this.servers.size}/${entries.length} Server verbunden, ${this.toolToServer.size} Werkzeug(e) verfügbar`
        )
    );
  }

  private async loadConfig(): Promise<Record<string, MCPServerConfig>> {
    const explicitPath = process.env.MCP_CONFIG_PATH?.trim();
    const candidates = explicitPath ? [path.resolve(explicitPath)] : desktopConfigCandidates();
    const found = candidates.find((candidate) => fs.existsSync(candidate));

    if (!found) {
      const hint = explicitPath
        ? ` MCP_CONFIG_PATH zeigt auf keine vorhandene Datei: ${explicitPath}`
        : " Keine Claude-Desktop-Konfiguration gefunden";
      console.log(c.label("[MCP]") + c.dim(hint));
      return {};
    }

    try {
      const servers = await readConfigFile(found);
      console.log(c.label("[MCP]") + ` Konfiguration geladen: ${found}`);
      return servers;
    } catch (err) {
      console.error(c.label("[MCP]") + c.error(` Konfiguration nicht lesbar: ${found}`), err);
      return {};
    }
  }

  private async connectServer(name: string, config: MCPServerConfig): Promise<ConnectedServer> {
    const isRemote = Boolean(config.url);
    const client = isRemote
      ? await this.connectRemoteServer(name, config)
      : await this.connectStdioServer(config);

    const toolsResponse = await client.listTools();
    const tools: DiscoveredTool[] = (toolsResponse.tools ?? []).map((tool) => ({
      serverName: name,
      name: tool.name,
      description: tool.description,
      inputSchema: tool.inputSchema,
    }));

    const typeLabel = isRemote ? c.cyan("[entfernt]") : c.dim("[lokal]");
    console.log(
      c.label("[MCP]") +
        ` „${name}“ ${typeLabel} verbunden – ${tools.length} Werkzeug(e): ${tools.map((t) => t.name).join(", ")}`
    );
    return { name, client, tools, type: isRemote ? "remote" : "stdio" };
  }

  /** Übernimmt die Werkzeuge eines Servers; ungültige Namen und Kollisionen werden gemeldet. */
  private register(server: ConnectedServer): void {
    const accepted = server.tools.filter((tool) => {
      if (!TOOL_NAME_PATTERN.test(tool.name)) {
        console.warn(
          c.label("[MCP]") +
            c.warn(` Werkzeug „${tool.name}“ von „${server.name}“ hat einen ungültigen Namen – ignoriert.`)
        );
        return false;
      }
      const owner = this.reservedToolNames.has(tool.name) ? "Gateway (lokal)" : this.toolToServer.get(tool.name);
      if (owner) {
        console.warn(
          c.label("[MCP]") +
            c.warn(
              ` Namenskollision: Werkzeug „${tool.name}“ von „${server.name}“ ist bereits durch „${owner}“ belegt – wird ignoriert.`
            )
        );
        return false;
      }
      this.toolToServer.set(tool.name, server.name);
      return true;
    });
    this.servers.set(server.name, { ...server, tools: accepted });
  }

  private async connectRemoteServer(name: string, config: MCPServerConfig): Promise<Client> {
    const url = new URL(config.url ?? "");
    const requestInit = { headers: { ...(config.headers ?? {}) } };

    // Zuerst StreamableHTTP (neueres Protokoll), dann SSE als Rückfall
    try {
      console.log(c.label("[MCP]") + c.dim(` „${name}“ versucht StreamableHTTP → ${loggableUrl(url)}`));
      const client = new Client(CLIENT_INFO, { capabilities: {} });
      await client.connect(new StreamableHTTPClientTransport(url, { requestInit }));
      console.log(c.label("[MCP]") + c.success(` „${name}“ über StreamableHTTP verbunden`));
      return client;
    } catch (httpErr) {
      console.log(
        c.label("[MCP]") + c.dim(` „${name}“ StreamableHTTP fehlgeschlagen, versuche SSE...`),
        httpErr instanceof Error ? httpErr.message : httpErr
      );
      const client = new Client(CLIENT_INFO, { capabilities: {} });
      await client.connect(new SSEClientTransport(url, { requestInit }));
      console.log(c.label("[MCP]") + c.success(` „${name}“ über SSE verbunden`));
      return client;
    }
  }

  private async connectStdioServer(config: MCPServerConfig): Promise<Client> {
    const client = new Client(CLIENT_INFO, { capabilities: {} });
    const transport = new StdioClientTransport({
      command: config.command ?? "",
      args: config.args,
      // Nur die sichere Standardumgebung + explizit konfigurierte Variablen –
      // ANTHROPIC_API_KEY und GATEWAY_API_KEY dürfen nicht an fremde Prozesse gehen.
      env: { ...getDefaultEnvironment(), ...(config.env ?? {}) },
    });
    await client.connect(transport);
    return client;
  }

  /** Ruft ein MCP-Werkzeug auf. Fehler werden als MCPToolError geworfen. */
  async invokeTool(toolName: string, args: Record<string, unknown>): Promise<unknown> {
    const serverName = this.toolToServer.get(toolName);
    const server = serverName ? this.servers.get(serverName) : undefined;
    if (!serverName || !server) {
      throw new MCPToolError(`Unbekanntes Werkzeug: ${toolName}`);
    }

    console.log(c.label("[MCP]") + ` Rufe ${c.value(toolName)} auf „${serverName}“ auf...`);
    return server.client.callTool({ name: toolName, arguments: args });
  }

  /** Werkzeugdefinitionen im Format der Claude API (ohne Duplikate). */
  getToolsForClaude(): Tool[] {
    return this.getAllDiscoveredTools().map((tool) => ({
      name: tool.name,
      description: tool.description ?? "",
      // MCP garantiert ein JSON-Schema vom Typ "object" – entspricht input_schema
      input_schema: tool.inputSchema as Tool["input_schema"],
    }));
  }

  getAllDiscoveredTools(): DiscoveredTool[] {
    return [...this.servers.values()].flatMap((server) => [...server.tools]);
  }

  getServerNames(): string[] {
    return [...this.servers.keys()];
  }

  getServerStatus(): ServerStatus[] {
    return [...this.servers.values()].map((server) => ({
      name: server.name,
      toolCount: server.tools.length,
      type: server.type,
    }));
  }

  async healthCheck(): Promise<{ healthy: string[]; unhealthy: string[] }> {
    const checks = await Promise.allSettled(
      [...this.servers.values()].map(async (server) => {
        await server.client.listTools();
        return server.name;
      })
    );
    const names = [...this.servers.keys()];
    return {
      healthy: names.filter((_, index) => checks[index].status === "fulfilled"),
      unhealthy: names.filter((_, index) => checks[index].status === "rejected"),
    };
  }

  async shutdown(): Promise<void> {
    console.log(c.label("[MCP]") + " Trenne alle Server...");
    const servers = [...this.servers.values()];
    const results = await Promise.allSettled(servers.map((server) => server.client.close()));
    results.forEach((result, index) => {
      const name = servers[index].name;
      if (result.status === "fulfilled") {
        console.log(c.label("[MCP]") + c.dim(` „${name}“ getrennt`));
      } else {
        console.error(c.label("[MCP]") + c.error(` Fehler beim Trennen von „${name}“:`), result.reason);
      }
    });
    this.servers.clear();
    this.toolToServer.clear();
  }
}
