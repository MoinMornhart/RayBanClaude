import { Router } from "express";
import type { Request, Response } from "express";
import type { ConversationStore } from "../conversation.js";
import type { MCPManager } from "../mcp-manager.js";
import type { SkillLoader } from "../skill-loader.js";

// GET /health         – öffentlich, nur minimaler Status (keine Interna)
// GET /health/details – nur mit gültigem Token (Auth-Middleware greift,
//                       weil nur exakt /health öffentlich ist)

export function createHealthRouter(
  mcpManager: MCPManager,
  conversations: ConversationStore,
  skillLoader: SkillLoader
): Router {
  const router = Router();

  router.get("/", (_req: Request, res: Response): void => {
    res.json({ status: "ok", mode: "gateway", auth: "required" });
  });

  router.get("/details", (_req: Request, res: Response): void => {
    res.json({
      status: "ok",
      mode: "gateway",
      uptime: process.uptime(),
      mcp: {
        servers: mcpManager.getServerStatus(),
        totalTools: mcpManager.getAllDiscoveredTools().length,
      },
      skills: {
        count: skillLoader.count,
        loaded: skillLoader.getSkillList(),
      },
      conversations: conversations.size,
    });
  });

  return router;
}
