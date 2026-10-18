import { Router } from "express";
import type { Request, Response } from "express";
import type { SkillLoader } from "../skill-loader.js";

// GET  /skills        – geladene Skills (nur mit Token)
// POST /skills/reload – Skills neu einlesen und Systemprompt aktualisieren

export function createSkillsRouter(skillLoader: SkillLoader, onReload: () => void): Router {
  const router = Router();

  router.get("/", (_req: Request, res: Response): void => {
    res.json({ skills: skillLoader.getSkillList(), count: skillLoader.count });
  });

  router.post("/reload", (_req: Request, res: Response): void => {
    skillLoader.reload();
    onReload();
    res.json({
      message: "Skills neu geladen",
      skills: skillLoader.getSkillList(),
      count: skillLoader.count,
    });
  });

  return router;
}
