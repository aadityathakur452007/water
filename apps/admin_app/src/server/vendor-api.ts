import { createServerFn } from "@tanstack/react-start";
import { getCookie } from "@tanstack/react-start/server";

import { bindingFetch } from "./admin-api";
import { apiUrl, storeRotatedSessionServer } from "./admin-session";
import { refreshVendorSessionServer } from "./vendor-session";

/**
 * Vendor read/write proxy (BFF adapter for the /vendor/* subtree). Mirrors
 * admin-api.ts 1:1 — cookie forwarded server-side, 401 → one silent refresh
 * → retry once, then the caller decides (guard bounces to /vendor/login).
 *
 * Authz truth lives in the worker: every /v1/vendor/* route is
 * require_role("vendor"), so a non-vendor cookie gets 401/403 from the
 * worker itself. The path allowlists below are defense-in-depth only —
 * the UI can never reach what the worker would refuse.
 */

export class VendorApiError extends Error {
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

type JsonObject = string | number | boolean | null | JsonObject[] | { [key: string]: JsonObject };

export type VendorEnvelope = {
  data?: JsonObject[];
  next_cursor?: string;
  [key: string]: JsonObject | string | undefined;
};

async function vendorWorkerFetch(
  path: string,
  method: "GET" | "POST" | "PATCH" | "PUT",
  body?: unknown,
  extraHeaders?: Record<string, string>,
): Promise<Response> {
  const access = getCookie("sh_vendor_session") || getCookie("sh_session") || "";
  const init: RequestInit = {
    method,
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${access}`,
      ...extraHeaders,
    },
    cache: "no-store",
    signal: AbortSignal.timeout(15_000),
  };
  if (method !== "GET") init.body = JSON.stringify(body ?? {});
  const viaBinding = await bindingFetch(path, init);
  if (viaBinding) {
    console.log(`[vendor-api] ${method} ${path} via WATER_API binding`);
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

async function throwIfError(res: Response, method: string, path: string): Promise<string> {
  const text = await res.text().catch(() => "");
  if (!res.ok) {
    const err = parseEnvelope<WorkerErrorShape>(text, {}) as WorkerErrorShape;
    console.error(`[vendor-api] ${method} ${path} → ${res.status} ${err.error?.code ?? "SERVER"}`);
    throw new VendorApiError(
      res.status,
      err.error?.code ?? "SERVER",
      err.error?.message ?? `${method} ${path} failed`,
      err.error?.trace_id ?? "",
    );
  }
  return text;
}

/**
 * GET /v1/vendor/* (reads). Closed prefix — anything else is a 400 without
 * touching the network. Same silent-refresh-once contract as adminGetServer.
 */
export const vendorGetServer = createServerFn({ method: "GET" })
  .validator((input: { path: string }) => input)
  .handler(async ({ data }): Promise<VendorEnvelope> => {
    const { path } = data;
    if (!path.startsWith("/v1/vendor/")) {
      throw new VendorApiError(400, "VALIDATION", "path must be a vendor /v1 path");
    }
    if (process.env.API_MODE === "mock") {
      const { resolveFixture } = await import("#/data/admin/mock-resolver");
      return resolveFixture(path, "GET") as unknown as VendorEnvelope;
    }
    let res = await vendorWorkerFetch(path, "GET");
    if (res.status === 401) {
      const pair = await refreshVendorSessionServer();
      if (pair) {
        await storeRotatedSessionServer({ data: pair });
        res = await vendorWorkerFetch(path, "GET");
      }
    }
    return parseEnvelope(await throwIfError(res, "GET", path), {}) as unknown as VendorEnvelope;
  });

/**
 * Closed write allowlist — the only vendor mutations that exist server-side
 * (triple/pod/cash per owned stop, placed accept, offline sync, duty,
 * complaint verify, quality vendor-check, profile PATCH, slots PUT).
 * Everything else → 400. No /v1/admin/* or /v1/refunds/* path can ever
 * pass this gate.
 */
function vendorWriteAllowed(path: string): boolean {
  if (
    path.startsWith("/v1/vendor/stops/") &&
    (path.endsWith("/triple") || path.endsWith("/pod") || path.endsWith("/cash"))
  ) {
    return true;
  }
  // Phase 5 S5.5: single-touch self-accept of a zone-scoped placed order.
  if (path.startsWith("/v1/vendor/placed/") && path.endsWith("/accept")) {
    return true;
  }
  if (path === "/v1/vendor/sync" || path === "/v1/vendor/duty") return true;
  if (path.startsWith("/complaints/") && path.endsWith("/verify")) return true;
  if (path.startsWith("/quality/") && path.endsWith("/vendor-check")) return true;
  if (path === "/v1/vendor/profile" || path === "/v1/vendor/slots") return true;
  return false;
}

/**
 * Vendor writes (POST default; PATCH for profile, PUT for slots via the
 * method param — mirrors adminPatchServer folded in). Forwards the client's
 * Idempotency-Key on triple commits; cash dedupes deterministically
 * server-side on (stop, amount) so no key is needed there.
 */
export const vendorPostServer = createServerFn({ method: "POST" })
  .validator(
    (input: { path: string; body?: unknown; method?: "POST" | "PATCH" | "PUT"; idempotencyKey?: string }) => input,
  )
  .handler(async ({ data }): Promise<VendorEnvelope> => {
    const { path, body, method = "POST", idempotencyKey } = data;
    if (!vendorWriteAllowed(path)) {
      throw new VendorApiError(400, "VALIDATION", "path is not a vendor-writable /v1 path");
    }
    if (process.env.API_MODE === "mock") {
      const { resolveFixture } = await import("#/data/admin/mock-resolver");
      return resolveFixture(path, method === "PUT" ? "POST" : method, body) as unknown as VendorEnvelope;
    }
    const headers = idempotencyKey ? { "Idempotency-Key": idempotencyKey } : undefined;
    let res = await vendorWorkerFetch(path, method, body, headers);
    if (res.status === 401) {
      const pair = await refreshVendorSessionServer();
      if (pair) {
        await storeRotatedSessionServer({ data: pair });
        res = await vendorWorkerFetch(path, method, body, headers);
      }
    }
    return parseEnvelope(await throwIfError(res, method, path), {}) as unknown as VendorEnvelope;
  });
