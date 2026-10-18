import Anthropic from "@anthropic-ai/sdk";
import { c } from "./console-theme.js";
import type { MCPManager } from "./mcp-manager.js";
import { QueueFullError } from "./middleware.js";
import type { SkillLoader } from "./skill-loader.js";
import {
  HTTP_INTERNAL_ERROR,
  HTTP_SERVICE_UNAVAILABLE,
} from "./http.js";
import type {
  ContentBlock,
  ContentBlockParam,
  MessageParam,
  ServerConfig,
  Tool,
  ToolCallResult,
  ToolResultBlockParam,
  ToolUseBlock,
} from "./types.js";
import type { ValidatedImage } from "./validation.js";

// ── Claude-Client ───────────────────────────────────────────────────
// - Nutzt die Beta-Messages-API, um server-seitige Fallbacks bei
//   Ablehnungen durch Sicherheitsklassifikatoren zu aktivieren
//   (fallbacks: "default" – Modelle ohne Fallback-Unterstützung laufen
//   dann einfach ohne).
// - Thinking wird nicht gesetzt: aktuelle Modelle denken adaptiv; die
//   Denktiefe (und damit die Sprach-Latenz) steuert output_config.effort.
// - Systemprompt und Werkzeuge bleiben innerhalb einer Runde unverändert,
//   Nachrichten werden nur angehängt (Prompt-Cache, gültige Thinking-Blöcke).

const MAX_TOOL_ITERATIONS = 10;
const API_TIMEOUT_MS = 120_000;
const MAX_TOOL_RESULT_CHARS = 50_000;
const FALLBACK_BETA = "server-side-fallback-2026-07-01";
export const SKILL_TOOL_NAME = "skill_laden";

const REFUSAL_TEXT = "Dabei kann ich leider nicht helfen.";
const EMPTY_RESPONSE_TEXT = "Ich konnte darauf gerade keine Antwort formulieren.";
const MAX_ITERATIONS_TEXT =
  "Ich habe mehrere Werkzeuge benutzt, bin aber zu keinem Ergebnis gekommen. Bitte versuche es mit einer einfacheren Anfrage.";
const TRUNCATION_NOTE = "\n[… Ausgabe gekürzt]";

/** Was die App bei einem fehlgeschlagenen Werkzeug sieht (ohne interne Details). */
const TOOL_ERROR_FOR_CLIENT = { error: "Werkzeug-Aufruf fehlgeschlagen." } as const;

export interface ChatTurnResult {
  readonly responseText: string;
  readonly toolCalls: readonly ToolCallResult[];
  /** true, wenn die Anfrage abgelehnt wurde – solche Runden nicht speichern */
  readonly refused: boolean;
}

interface ToolOutcome {
  readonly clientCall: ToolCallResult;
  readonly resultBlock: ToolResultBlockParam;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function truncate(text: string): string {
  return text.length > MAX_TOOL_RESULT_CHARS
    ? `${text.slice(0, MAX_TOOL_RESULT_CHARS)}${TRUNCATION_NOTE}`
    : text;
}

/** Wandelt ein MCP-CallToolResult in Text für den tool_result-Block um. */
function toolResultText(result: unknown): string {
  if (isRecord(result) && Array.isArray(result.content)) {
    const parts = result.content.map((item: unknown) => {
      if (isRecord(item) && item.type === "text" && typeof item.text === "string") {
        return item.text;
      }
      const type = isRecord(item) && typeof item.type === "string" ? item.type : "unbekannt";
      return `[Inhalt vom Typ ${type} – nicht als Text darstellbar]`;
    });
    return truncate(parts.join("\n"));
  }
  return truncate(JSON.stringify(result) ?? "");
}

function extractText(content: readonly ContentBlock[]): string {
  return content
    .flatMap((block) => (block.type === "text" ? [block.text] : []))
    .join("\n")
    .trim();
}

/** Baut die Nutzernachricht: zuerst Bilder, dann Text. */
export function buildUserMessage(text: string, images: readonly ValidatedImage[]): MessageParam {
  const imageBlocks: ContentBlockParam[] = images.map((image) => ({
    type: "image",
    source: { type: "base64", media_type: image.mediaType, data: image.data },
  }));
  const textBlocks: ContentBlockParam[] = text ? [{ type: "text", text }] : [];
  return { role: "user", content: [...imageBlocks, ...textBlocks] };
}

// ── Fehlerzuordnung für den App-Client ──

export interface ClientFacingError {
  readonly status: number;
  readonly message: string;
}

const BUSY_ERROR: ClientFacingError = {
  status: HTTP_SERVICE_UNAVAILABLE,
  message: "Der Dienst ist gerade ausgelastet – bitte gleich noch einmal versuchen.",
};
const UNREACHABLE_ERROR: ClientFacingError = {
  status: HTTP_SERVICE_UNAVAILABLE,
  message: "Die KI ist gerade nicht erreichbar – bitte später erneut versuchen.",
};
const GENERIC_ERROR: ClientFacingError = {
  status: HTTP_INTERNAL_ERROR,
  message: "Die Anfrage konnte nicht verarbeitet werden.",
};

/** Reihenfolge: speziellste Klasse zuerst (APIConnectionError erbt von APIError). */
const ERROR_RULES: readonly (readonly [(err: unknown) => boolean, ClientFacingError])[] = [
  [(err) => err instanceof QueueFullError, BUSY_ERROR],
  [(err) => err instanceof Anthropic.APIConnectionError, UNREACHABLE_ERROR],
  [(err) => err instanceof Anthropic.RateLimitError, BUSY_ERROR],
  [(err) => err instanceof Anthropic.InternalServerError, UNREACHABLE_ERROR],
];

/** Neutrale Meldung + Status für den Client; Details nur ins Log. */
export function describeChatError(err: unknown): ClientFacingError {
  if (err instanceof Anthropic.AuthenticationError || err instanceof Anthropic.PermissionDeniedError) {
    console.error(
      c.label("[Claude]") +
        c.error(" Die Claude API lehnt den API-Schlüssel ab – ANTHROPIC_API_KEY in der .env prüfen.")
    );
  }
  return ERROR_RULES.find(([test]) => test(err))?.[1] ?? GENERIC_ERROR;
}

// ── Client ──

export class ClaudeClient {
  private readonly anthropic: Anthropic;
  private config: ServerConfig;

  constructor(
    private readonly mcpManager: MCPManager,
    private readonly skillLoader: SkillLoader,
    config: ServerConfig
  ) {
    // Schlüssel kommt aus ANTHROPIC_API_KEY (Umgebung/.env), nie aus dem Code
    this.anthropic = new Anthropic({ timeout: API_TIMEOUT_MS });
    this.config = { ...config };
  }

  updateConfig(updates: Partial<ServerConfig>): void {
    this.config = { ...this.config, ...updates };
  }

  getConfig(): ServerConfig {
    return { ...this.config };
  }

  /** Führt eine Chat-Runde aus (inkl. Werkzeugschleife). */
  async chat(
    history: readonly MessageParam[],
    text: string,
    images: readonly ValidatedImage[]
  ): Promise<ChatTurnResult> {
    // Momentaufnahme: Änderungen über /config gelten ab der nächsten Runde
    const config = this.getConfig();
    const tools = this.collectTools();
    const messages = [...history, buildUserMessage(text, images)];
    return this.runLoop(messages, config, tools, [], 0);
  }

  private collectTools(): Tool[] {
    const skillTool: Tool[] = this.skillLoader.count
      ? [
          {
            name: SKILL_TOOL_NAME,
            description:
              "Lädt die vollständige Anleitung eines verfügbaren Skills (siehe Liste im Systemprompt). Vor der Anwendung eines Skills aufrufen.",
            input_schema: {
              type: "object",
              properties: {
                name: { type: "string", description: "Name des Skills, exakt wie in der Liste" },
              },
              required: ["name"],
              additionalProperties: false,
            },
          },
        ]
      : [];
    return [...skillTool, ...this.mcpManager.getToolsForClaude()];
  }

  private async runLoop(
    messages: readonly MessageParam[],
    config: ServerConfig,
    tools: readonly Tool[],
    toolCalls: readonly ToolCallResult[],
    iteration: number
  ): Promise<ChatTurnResult> {
    if (iteration >= MAX_TOOL_ITERATIONS) {
      console.warn(c.label("[Claude]") + c.warn(" Maximale Anzahl Werkzeug-Runden erreicht."));
      return { responseText: MAX_ITERATIONS_TEXT, toolCalls, refused: false };
    }

    const response = await this.anthropic.beta.messages.create({
      model: config.model,
      max_tokens: config.maxTokens,
      // Stabiler Präfix (Werkzeuge + Systemprompt) wird gecacht
      system: [{ type: "text", text: config.systemPrompt, cache_control: { type: "ephemeral" } }],
      messages: [...messages],
      ...(tools.length ? { tools: [...tools] } : {}),
      ...(config.effort ? { output_config: { effort: config.effort } } : {}),
      fallbacks: "default",
      betas: [FALLBACK_BETA],
    });

    // Ablehnung immer VOR dem Lesen des Inhalts prüfen
    if (response.stop_reason === "refusal") {
      console.warn(
        c.label("[Claude]") +
          c.warn(` Anfrage abgelehnt (Kategorie: ${response.stop_details?.category ?? "unbekannt"})`)
      );
      return { responseText: REFUSAL_TEXT, toolCalls, refused: true };
    }

    const toolUses = response.content.filter(
      (block): block is ToolUseBlock => block.type === "tool_use"
    );

    if (response.stop_reason !== "tool_use" || !toolUses.length) {
      if (response.stop_reason === "max_tokens") {
        console.warn(c.label("[Claude]") + c.warn(" Antwort wegen max_tokens abgeschnitten."));
      }
      const responseText = extractText(response.content) || EMPTY_RESPONSE_TEXT;
      return { responseText, toolCalls, refused: false };
    }

    // Parallele Werkzeugaufrufe gleichzeitig ausführen; alle Ergebnisse in EINER Nachricht
    const outcomes = await Promise.all(toolUses.map((toolUse) => this.executeTool(toolUse)));
    const nextMessages: MessageParam[] = [
      ...messages,
      { role: "assistant", content: response.content },
      { role: "user", content: outcomes.map((outcome) => outcome.resultBlock) },
    ];
    return this.runLoop(
      nextMessages,
      config,
      tools,
      [...toolCalls, ...outcomes.map((outcome) => outcome.clientCall)],
      iteration + 1
    );
  }

  private async executeTool(toolUse: ToolUseBlock): Promise<ToolOutcome> {
    console.log(c.label("[Claude]") + ` Werkzeug-Aufruf: ${toolUse.name}`);
    const input = isRecord(toolUse.input) ? toolUse.input : {};

    if (toolUse.name === SKILL_TOOL_NAME) {
      return this.loadSkill(toolUse, input);
    }

    try {
      const result = await this.mcpManager.invokeTool(toolUse.name, input);
      const isError = isRecord(result) && result.isError === true;
      return {
        clientCall: { name: toolUse.name, result: isError ? TOOL_ERROR_FOR_CLIENT : result },
        resultBlock: {
          type: "tool_result",
          tool_use_id: toolUse.id,
          content: toolResultText(result),
          ...(isError ? { is_error: true } : {}),
        },
      };
    } catch (err) {
      // Claude darf den Fehlertext sehen (zur Selbstkorrektur), die App nicht
      const message = err instanceof Error ? err.message : String(err);
      console.error(c.label("[Claude]") + c.error(` Werkzeugfehler (${toolUse.name}):`), message);
      return {
        clientCall: { name: toolUse.name, result: TOOL_ERROR_FOR_CLIENT },
        resultBlock: {
          type: "tool_result",
          tool_use_id: toolUse.id,
          content: `Fehler beim Werkzeug-Aufruf: ${message}`,
          is_error: true,
        },
      };
    }
  }

  private loadSkill(toolUse: ToolUseBlock, input: Record<string, unknown>): ToolOutcome {
    const name = typeof input.name === "string" ? input.name : "";
    const prompt = this.skillLoader.getSkillPrompt(name);
    return {
      clientCall: { name: toolUse.name, result: { skill: name, gefunden: prompt !== null } },
      resultBlock: {
        type: "tool_result",
        tool_use_id: toolUse.id,
        content: prompt ? truncate(prompt) : `Skill „${name}“ ist nicht vorhanden.`,
        ...(prompt ? {} : { is_error: true }),
      },
    };
  }
}
