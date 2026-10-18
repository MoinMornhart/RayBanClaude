import { Router } from "express";
import type { Request, Response } from "express";
import type { ClaudeClient } from "../claude-client.js";
import { HTTP_BAD_REQUEST, sendError } from "../http.js";
import { validateConfigUpdate } from "../validation.js";

// GET  /config – aktuelle Konfiguration (nur mit Token)
// POST /config – system_prompt, model, max_tokens ändern (validiert)

export function createConfigRouter(claudeClient: ClaudeClient): Router {
  const router = Router();

  router.get("/", (_req: Request, res: Response): void => {
    res.json(claudeClient.getConfig());
  });

  router.post("/", (req: Request, res: Response): void => {
    const validation = validateConfigUpdate(req.body);
    if (!validation.ok) {
      sendError(res, HTTP_BAD_REQUEST, validation.error);
      return;
    }
    claudeClient.updateConfig(validation.value);
    res.json({ updated: Object.keys(validation.value), config: claudeClient.getConfig() });
  });

  return router;
}
