import { Router } from "express";
import type { Request, Response } from "express";
import { buildUserMessage, describeChatError } from "../claude-client.js";
import type { ClaudeClient } from "../claude-client.js";
import { c } from "../console-theme.js";
import type { ConversationStore } from "../conversation.js";
import { HTTP_BAD_REQUEST, sendError } from "../http.js";
import type { RequestQueue } from "../middleware.js";
import type { ChatResponse } from "../types.js";
import { validateChatRequest } from "../validation.js";

// POST /chat – Vertrag mit der iOS-App:
//   Body:    { text, images?: string[] (Base64), conversation_id? }
//   Antwort: { text, tool_calls: [{ name, result }], conversation_id }

export function createChatRouter(
  claudeClient: ClaudeClient,
  conversations: ConversationStore,
  requestQueue: RequestQueue
): Router {
  const router = Router();

  router.post("/", async (req: Request, res: Response): Promise<void> => {
    const validation = validateChatRequest(req.body);
    if (!validation.ok) {
      sendError(res, HTTP_BAD_REQUEST, validation.error);
      return;
    }

    const { text, images, conversationId } = validation.value;
    const id = conversations.resolveId(conversationId);

    try {
      // History erst bei Ausführung lesen – so sieht eine wartende Anfrage
      // auch die Runde, die direkt vor ihr in derselben Konversation lief.
      const result = await requestQueue.enqueue(() =>
        claudeClient.chat(conversations.getHistory(id), text, images)
      );

      if (!result.refused) {
        conversations.appendTurn(id, buildUserMessage(text, images), {
          role: "assistant",
          content: result.responseText,
        });
      }

      const response: ChatResponse = {
        text: result.responseText,
        tool_calls: [...result.toolCalls],
        conversation_id: id,
      };
      res.json(response);
    } catch (err) {
      // Details (inkl. SDK-Fehlertext) nur ins Log, an den Client nur neutral
      console.error(c.label("[Chat]") + c.error(" Anfrage fehlgeschlagen:"), err);
      const { status, message } = describeChatError(err);
      sendError(res, status, message);
    }
  });

  return router;
}
