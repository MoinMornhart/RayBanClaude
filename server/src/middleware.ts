import type { Request, Response, NextFunction } from "express";
import { c } from "./console-theme.js";

// ── Gateway Auth Middleware ──────────────────────────────────────────
// Optional API key auth. If GATEWAY_API_KEY is set in .env, all
// non-health endpoints require it via X-Gateway-Key header.
// If not set, all requests are allowed (localhost-only use).

export function gatewayAuth() {
  const gatewayKey = process.env.GATEWAY_API_KEY || "";

  return (req: Request, res: Response, next: NextFunction): void => {
    // Health endpoint is always public
    if (req.path === "/health" || req.path === "/") {
      next();
      return;
    }

    // If no key configured, allow all (localhost mode)
    if (!gatewayKey) {
      next();
      return;
    }

    // Check header
    const provided = req.headers["x-gateway-key"] as string;
    if (provided === gatewayKey) {
      next();
      return;
    }

    console.log(
      c.warn(`[Auth] Rejected request to ${req.path} — invalid or missing X-Gateway-Key`)
    );
    res.status(401).json({ error: "Unauthorized — provide X-Gateway-Key header" });
  };
}

// ── Rate Limiter / Request Queue ─────────────────────────────────────
// Prevents concurrent Claude API calls from racing.
// Queues requests and processes them one at a time.

export class RequestQueue {
  private queue: Array<{
    execute: () => Promise<void>;
    resolve: () => void;
  }> = [];
  private running = false;
  private maxConcurrent: number;
  private activeCount = 0;

  constructor(maxConcurrent: number = 1) {
    this.maxConcurrent = maxConcurrent;
  }

  async enqueue<T>(fn: () => Promise<T>): Promise<T> {
    return new Promise<T>((resolve, reject) => {
      const execute = async () => {
        try {
          const result = await fn();
          resolve(result);
        } catch (err) {
          reject(err);
        }
      };

      this.queue.push({
        execute,
        resolve: () => {},
      });

      this.processQueue();
    });
  }

  private async processQueue(): Promise<void> {
    if (this.activeCount >= this.maxConcurrent) return;
    const item = this.queue.shift();
    if (!item) return;

    this.activeCount++;
    try {
      await item.execute();
    } finally {
      this.activeCount--;
      this.processQueue();
    }
  }

  get pending(): number {
    return this.queue.length;
  }

  get active(): number {
    return this.activeCount;
  }
}

// ── Simple Rate Limiter ──────────────────────────────────────────────
// Limits requests per IP per window. Prevents abuse if gateway is exposed.

interface RateLimitEntry {
  count: number;
  resetAt: number;
}

export function rateLimiter(
  maxRequests: number = 30,
  windowMs: number = 60_000
) {
  const clients = new Map<string, RateLimitEntry>();

  // Cleanup old entries every minute
  setInterval(() => {
    const now = Date.now();
    for (const [key, entry] of clients) {
      if (now > entry.resetAt) clients.delete(key);
    }
  }, windowMs);

  return (req: Request, res: Response, next: NextFunction): void => {
    // Skip rate limiting for health checks
    if (req.path === "/health" || req.path === "/") {
      next();
      return;
    }

    const ip = req.ip || req.socket.remoteAddress || "unknown";
    const now = Date.now();
    let entry = clients.get(ip);

    if (!entry || now > entry.resetAt) {
      entry = { count: 0, resetAt: now + windowMs };
      clients.set(ip, entry);
    }

    entry.count++;

    // Set rate limit headers
    res.setHeader("X-RateLimit-Limit", maxRequests);
    res.setHeader("X-RateLimit-Remaining", Math.max(0, maxRequests - entry.count));
    res.setHeader("X-RateLimit-Reset", Math.ceil(entry.resetAt / 1000));

    if (entry.count > maxRequests) {
      console.log(c.warn(`[RateLimit] ${ip} exceeded ${maxRequests} req/${windowMs / 1000}s`));
      res.status(429).json({
        error: "Too many requests — try again later",
        retryAfter: Math.ceil((entry.resetAt - now) / 1000),
      });
      return;
    }

    next();
  };
}
