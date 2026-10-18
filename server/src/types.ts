import type Anthropic from "@anthropic-ai/sdk";

// ── Chat-API (Vertrag mit der iOS-App – nicht ändern) ──

export interface ChatRequest {
  text: string;
  images?: string[]; // Base64-kodierte JPEG-/PNG-Bilder
  conversation_id?: string;
}

export interface ToolCallResult {
  name: string;
  result: unknown;
}

export interface ChatResponse {
  text: string;
  tool_calls: ToolCallResult[];
  conversation_id: string;
}

// ── Config-API ──

export interface ConfigUpdate {
  system_prompt?: string;
  model?: string;
  max_tokens?: number;
}

/** Erlaubte Effort-Stufen der Claude API (output_config.effort). */
export const EFFORT_LEVELS = ["low", "medium", "high", "xhigh", "max"] as const;
export type Effort = (typeof EFFORT_LEVELS)[number];

export interface ServerConfig {
  systemPrompt: string;
  model: string;
  maxTokens: number;
  /** null = Parameter nicht senden (z. B. für ältere Modelle ohne Effort-Unterstützung) */
  effort: Effort | null;
}

// ── MCP ──

export interface MCPServerConfig {
  // Lokaler stdio-Server
  command?: string;
  args?: string[];
  env?: Record<string, string>;
  // Entfernter HTTP/SSE-Server
  url?: string;
  headers?: Record<string, string>;
}

export interface DiscoveredTool {
  serverName: string;
  name: string;
  description?: string;
  inputSchema: Record<string, unknown>;
}

// ── Konversation ──
// Es wird die Beta-Schnittstelle des SDK genutzt (wegen server-seitiger
// Fallbacks bei Ablehnungen), daher die Beta-Typen.

export type MessageParam = Anthropic.Beta.BetaMessageParam;
export type ContentBlockParam = Anthropic.Beta.BetaContentBlockParam;
export type ContentBlock = Anthropic.Beta.BetaContentBlock;
export type ToolUseBlock = Anthropic.Beta.BetaToolUseBlock;
export type ToolResultBlockParam = Anthropic.Beta.BetaToolResultBlockParam;
export type Tool = Anthropic.Beta.BetaTool;
