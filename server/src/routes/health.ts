import { Router } from "express";
import type { MCPManager } from "../mcp-manager.js";
import type { ConversationStore } from "../conversation.js";
import type { SkillLoader } from "../skill-loader.js";

export function createHealthRouter(
  mcpManager: MCPManager,
  conversations: ConversationStore,
  skillLoader?: SkillLoader
): Router {
  const router = Router();

  router.get("/", async (_req, res) => {
    const servers = mcpManager.getServerStatus();
    const toolCount = mcpManager.getAllDiscoveredTools().length;

    res.json({
      status: "ok",
      uptime: process.uptime(),
      mcp: {
        servers,
        totalTools: toolCount,
      },
      skills: {
        count: skillLoader?.count ?? 0,
        loaded: skillLoader?.getSkillList() ?? [],
      },
      conversations: conversations.size,
    });
  });

  return router;
}
