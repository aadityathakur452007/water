import { createServerFn } from "@tanstack/react-start";
import { getCookie } from "@tanstack/react-start/server";

import { apiUrl, refreshSessionServer, SESSION_COOKIE, storeRotatedSessionServer } from "./admin-session";

/**
 * Admin read/write proxy (the TanStack-Start equivalent of the old admin's
 * /api/proxy + /api/admin-actions routes). The worker stays the only
 * authority: cookie forwarded server-side, 401 → one silent refresh → retry
 * once, then the caller decides (guard redirects to sign-in). Errors map 1:1
 * to the worker envelope; mock mode serves fixtures with identical shapes.
 */

export class AdminApiError extends Error {
  status: number;
  code: string;
  traceId: string;

  constructor(status: number, code: string, message: string, traceId = "") {
    super(message);
    this.status = status;
    this.code = code;
    this.traceId = traceId;
  }
}

type WorkerErrorShape = {
  error?: { code?: string; message?: string; trace_id?: string };
};

/**
 * JSON-safe envelope — everything crossing the server-function boundary must
 * be serializable, so the row arrays are typed as JsonObject (realistically
 * API row shapes; the casting happens once here, consumers re-narrow).
 */
type JsonObject = string | number | boolean | null | JsonObject[] | { [key: string]: JsonObject };

export type AdminEnvelope = {
  data?: JsonObject[];
  next_cursor?: string;
  [key: string]: JsonObject | string | undefined;
};

export function apiMode(): "live" | "mock" {
  const mode = process.env.API_MODE;
  if (mode === "mock") return "mock";
  // live is the safe default: a forgotten API_MODE in production must never
  // silently render fixture data. Set API_MODE=mock explicitly for offline dev.
  return "live";
}

const ADMIN_PREFIX = "/v1/admin";

/**
 * Direct Worker-to-Worker call via the WATER_API service binding (same
 * account). Public HTTPS fetch between workers.dev hosts can be stopped at
 * the edge (error 1003 historically, opaque 403 now) — the binding never
 * leaves Cloudflare's network: no DNS, no edge, no 403. Returns null when
 * unavailable (local `vite dev`) so callers fall back to API_URL.
 */
export async function bindingFetch(path: string, init: RequestInit): Promise<Response | null> {
  try {
    // @vite-ignore keeps this runtime-only: the client bundle must not try
    // to resolve the workers runtime import (build failure otherwise). This
    // only ever executes inside server functions on the worker / wrangler dev.
    const { env } = await import(/* @vite-ignore */ "cloudflare:workers");
    const binding = (env as Record<string, unknown>).WATER_API as
      | { fetch: typeof fetch }
      | undefined;
    if (!binding) return null;
    return await binding.fetch(`https://water.internal${path}`, init);
  } catch {
    return null;
  }
}

async function workerFetch(
  path: string,
  method: "GET" | "POST" | "PATCH",
  body?: unknown,
): Promise<Response> {
  const access = getCookie(SESSION_COOKIE) ?? "";
  const init: RequestInit = {
    method,
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${access}`,
    },
    cache: "no-store",
    signal: AbortSignal.timeout(15_000),
  };
  if (method !== "GET") init.body = JSON.stringify(body ?? {});
  const viaBinding = await bindingFetch(path, init);
  if (viaBinding) {
    console.log(`[admin-api] ${method} ${path} via WATER_API binding`);
    return viaBinding;
  }
  return fetch(`${apiUrl()}${path}`, init);
}

/**
 * Unauthenticated worker POST without the admin cookie (login/logout edge).
 * Binding-first like workerFetch; extra headers (logout Bearer) pass through.
 */
export async function callWorkerPublic(
  path: string,
  body: unknown,
  headers?: Record<string, string>,
): Promise<Response> {
  const init: RequestInit = {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body: JSON.stringify(body ?? {}),
    cache: "no-store",
    signal: AbortSignal.timeout(15_000),
  };
  const viaBinding = await bindingFetch(path, init);
  if (viaBinding) {
    console.log(`[admin-api] POST ${path} via WATER_API binding`);
    return viaBinding;
  }
  return fetch(`${apiUrl()}${path}`, init);
}

function parseEnvelope<T>(raw: string, fallback: T): T | WorkerErrorShape {
  if (!raw) return fallback;
  try {
    return JSON.parse(raw) as T | WorkerErrorShape;
  } catch {
    return fallback;
  }
}

/**
 * Role probe for the dashboard guard: GET /v1/auth/me with the session
 * cookie → the worker's current role (or null when unauthenticated/dead).
 * Cheap, read-only, owner-scoped by construction. Mock mode reports admin
 * so offline dev keeps the shell.
 */
export const adminRoleServer = createServerFn({ method: "GET" }).handler(
  async (): Promise<{ role: string } | null> => {
    if (apiMode() === "mock") return { role: "admin" };
    let res = await workerFetch("/v1/auth/me", "GET");
    if (res.status === 401) {
      const pair = await refreshSessionServer();
      if (pair) {
        await storeRotatedSessionServer({ data: pair });
        res = await workerFetch("/v1/auth/me", "GET");
      }
    }
    if (!res.ok) return null;
    const body = (await res.json().catch(() => null)) as { user?: { role?: unknown } } | null;
    const role = body?.user?.role;
    return typeof role === "string" ? { role } : null;
  },
);

/**
 * GET /v1/admin/* (reads). On 401: one silent refresh + retry, then throws
 * AdminApiError(401) so the client guard bounces to sign-in.
 */
export const adminGetServer = createServerFn({ method: "GET" })
  .validator((input: { path: string }) => input)
  .handler(async ({ data }): Promise<AdminEnvelope> => {
    const { path } = data;
    if (!path.startsWith(ADMIN_PREFIX)) {
      throw new AdminApiError(400, "VALIDATION", "path must be an admin /v1 path");
    }
    if (apiMode() === "mock") {
      const { resolveFixture } = await import("#/data/admin/mock-resolver");
      return resolveFixture(path, "GET") as unknown as AdminEnvelope;
    }
    let res = await workerFetch(path, "GET");
    if (res.status === 401) {
      const pair = await refreshSessionServer();
      if (pair) {
        await storeRotatedSessionServer({ data: pair });
        res = await workerFetch(path, "GET");
      }
    }
    const text = await res.text().catch(() => "");
    if (!res.ok) {
      const err = parseEnvelope<WorkerErrorShape>(text, {}) as WorkerErrorShape;
      console.error(
        `[admin-api] GET ${path} → ${res.status} ${err.error?.code ?? "SERVER"} (tail: wrangler tail shodasha-admin)`,
      );
      throw new AdminApiError(
        res.status,
        err.error?.code ?? "SERVER",
        err.error?.message ?? `GET ${path} failed`,
        err.error?.trace_id ?? "",
      );
    }
    return parseEnvelope(text, {}) as unknown as AdminEnvelope;
  });

/**
 * POST /v1/admin/* (writes). Forward cookie bearer + idempotency key; the
 * same silent-refresh-once contract as GET. Refund writes live under
 * /v1/refunds/* (admin-gated server-side) — allowed alongside /v1/admin/*.
 */
export const adminPostServer = createServerFn({ method: "POST" })
  .validator((input: { path: string; body?: unknown }) => input)
  .handler(async ({ data }): Promise<AdminEnvelope> => {
    const { path, body } = data;
    if (!path.startsWith(ADMIN_PREFIX) && !path.startsWith("/v1/refunds/")) {
      throw new AdminApiError(400, "VALIDATION", "path must be an admin /v1 path");
    }
    if (apiMode() === "mock") {
      const { resolveFixture } = await import("#/data/admin/mock-resolver");
      return resolveFixture(path, "POST", body) as unknown as AdminEnvelope;
    }
    let res = await workerFetch(path, "POST", body);
    if (res.status === 401) {
      const pair = await refreshSessionServer();
      if (pair) {
        await storeRotatedSessionServer({ data: pair });
        res = await workerFetch(path, "POST", body);
      }
    }
    const text = await res.text().catch(() => "");
    if (!res.ok) {
      const err = parseEnvelope<WorkerErrorShape>(text, {}) as WorkerErrorShape;
      console.error(
        `[admin-api] POST ${path} → ${res.status} ${err.error?.code ?? "SERVER"} (tail: wrangler tail shodasha-admin)`,
      );
      throw new AdminApiError(
        res.status,
        err.error?.code ?? "SERVER",
        err.error?.message ?? `POST ${path} failed`,
        err.error?.trace_id ?? "",
      );
    }
    return parseEnvelope(text, {}) as unknown as AdminEnvelope;
  });

/**
 * PATCH /v1/admin/* (partial updates, e.g. vendor capacity). Same guard +
 * refresh-once contract as POST.
 */
export const adminPatchServer = createServerFn({ method: "POST" })
  .validator((input: { path: string; body?: unknown }) => input)
  .handler(async ({ data }): Promise<AdminEnvelope> => {
    const { path, body } = data;
    if (!path.startsWith(ADMIN_PREFIX)) {
      throw new AdminApiError(400, "VALIDATION", "path must be an admin /v1 path");
    }
    if (apiMode() === "mock") {
      const { resolveFixture } = await import("#/data/admin/mock-resolver");
      return resolveFixture(path, "PATCH", body) as unknown as AdminEnvelope;
    }
    let res = await workerFetch(path, "PATCH", body);
    if (res.status === 401) {
      const pair = await refreshSessionServer();
      if (pair) {
        await storeRotatedSessionServer({ data: pair });
        res = await workerFetch(path, "PATCH", body);
      }
    }
    const text = await res.text().catch(() => "");
    if (!res.ok) {
      const err = parseEnvelope<WorkerErrorShape>(text, {}) as WorkerErrorShape;
      console.error(
        `[admin-api] PATCH ${path} → ${res.status} ${err.error?.code ?? "SERVER"} (tail: wrangler tail shodasha-admin)`,
      );
      throw new AdminApiError(
        res.status,
        err.error?.code ?? "SERVER",
        err.error?.message ?? `PATCH ${path} failed`,
        err.error?.trace_id ?? "",
      );
    }
    return parseEnvelope(text, {}) as unknown as AdminEnvelope;
  });
