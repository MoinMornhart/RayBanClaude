import { Router } from "express";
import type { Request, Response } from "express";
import type { MCPManager } from "../mcp-manager.js";

// GET /tools        – Liste der MCP-Werkzeuge (nur mit Token)
// GET /tools/health – Erreichbarkeit der MCP-Server (nur mit Token)

export function createToolsRouter(mcpManager: MCPManager): Router {
  const router = Router();

  router.get("/", (_req: Request, res: Response): void => {
    const tools = mcpManager.getAllDiscoveredTools();
    res.json({
      count: tools.length,
      tools: tools.map((tool) => ({
        server: tool.serverName,
        name: tool.name,
        description: tool.description,
        inputSchema: tool.inputSchema,
      })),
    });
  });

  router.get("/health", async (_req: Request, res: Response): Promise<void> => {
    res.json(await mcpManager.healthCheck());
  });

  return router;
}
