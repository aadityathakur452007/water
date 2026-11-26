import { getCookie } from "@tanstack/react-start/server";

import { WorkerApiError, type WorkerEnvelope } from "./worker-errors";

export type WorkerBindingName = "WATER_API" | "OPS_API";

export type WorkerErrorShape = {
  error?: { code?: string; message?: string; trace_id?: string };
};

export function normalizeOrigin(rawValue: string): string {
  return rawValue.trim().replace(/\/+$/, "").replace(/\/v1$/, "");
}

let loggedApiHost = false;

export function apiUrl(): string {
  const raw = (process.env.API_URL ?? "http://127.0.0.1:8000").trim();
  const url = normalizeOrigin(raw);
  if (!loggedApiHost) {
    loggedApiHost = true;
    if (url !== raw) console.error(`[admin-auth] normalized API_URL ${raw} → ${url}`);
    else console.log(`[admin-auth] API_URL ${url}`);
  }
  return url;
}

export function opsApiUrl(): string {
  return normalizeOrigin(process.env.OPS_API_URL ?? process.env.API_URL ?? "http://127.0.0.1:8000");
}

export function apiMode(): "live" | "mock" {
  return process.env.API_MODE === "mock" ? "mock" : "live";
}

/**
 * Direct Worker-to-Worker call via Cloudflare service binding (same account).
 * Returns null in local `vite dev` so callers fall back to HTTP URLs.
 */
export async function bindingFetch(
  path: string,
  init: RequestInit,
  bindingName: WorkerBindingName = "WATER_API",
): Promise<Response | null> {
  try {
    // @vite-ignore keeps the client bundle from resolving cloudflare:workers.
    const { env } = await import(/* @vite-ignore */ "cloudflare:workers");
    const binding = (env as Record<string, unknown>)[bindingName] as { fetch: typeof fetch } | undefined;
    if (!binding) return null;
    return await binding.fetch(`https://worker.internal${path}`, init);
  } catch {
    return null;
  }
}

export function parseEnvelope<T>(raw: string, fallback: T): T | WorkerErrorShape {
  if (!raw) return fallback;
  try {
    return JSON.parse(raw) as T | WorkerErrorShape;
  } catch {
    return fallback;
  }
}

export async function callPublicEndpoint(
  path: string,
  body: unknown,
  headers: Record<string, string> | undefined,
  bindingName: WorkerBindingName,
  baseUrl: string,
  logTag = "worker-api",
): Promise<Response> {
  const init: RequestInit = {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body: JSON.stringify(body ?? {}),
    cache: "no-store",
    signal: AbortSignal.timeout(15_000),
  };
  const viaBinding = await bindingFetch(path, init, bindingName);
  if (viaBinding) {
    console.log(`[${logTag}] POST ${path} via ${bindingName} binding`);
    return viaBinding;
  }
  return fetch(`${baseUrl}${path}`, init);
}

export async function executeAuthedFetch(opts: {
  path: string;
  method: "GET" | "POST" | "PATCH" | "PUT";
  body?: unknown;
  extraHeaders?: Record<string, string>;
  bindingName: WorkerBindingName;
  baseUrl: string;
  cookieNames: string[];
  logTag: string;
  retry5xx?: boolean;
}): Promise<Response> {
  const token = opts.cookieNames.map((n) => getCookie(n)).find(Boolean) ?? "";
  const buildInit = (): RequestInit => {
    const init: RequestInit = {
      method: opts.method,
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${token}`,
        ...opts.extraHeaders,
      },
      cache: "no-store",
      signal: AbortSignal.timeout(15_000),
    };
    if (opts.method !== "GET") init.body = JSON.stringify(opts.body ?? {});
    return init;
  };

  const maxAttempts = opts.retry5xx && opts.method === "GET" ? 3 : 1;
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      const init = buildInit();
      const viaBinding = await bindingFetch(opts.path, init, opts.bindingName);
      const res = viaBinding ?? (await fetch(`${opts.baseUrl}${opts.path}`, init));
      if (viaBinding) {
        console.log(`[${opts.logTag}] ${opts.method} ${opts.path} via ${opts.bindingName} binding`);
      }
      if (res.status >= 500 && attempt < maxAttempts) {
        await new Promise((r) => setTimeout(r, attempt * 200));
        continue;
      }
      return res;
    } catch (err) {
      if (attempt >= maxAttempts) throw err;
      await new Promise((r) => setTimeout(r, attempt * 200));
    }
  }
  throw new WorkerApiError(502, "SERVER", `${opts.method} ${opts.path} failed`);
}

export async function fetchEnvelopeWithRefresh(opts: {
  path: string;
  method: "GET" | "POST" | "PATCH" | "PUT";
  body?: unknown;
  extraHeaders?: Record<string, string>;
  bindingName: WorkerBindingName;
  baseUrl: string;
  cookieNames: string[];
  logTag: string;
  retry5xx?: boolean;
  refresh: () => Promise<{ access: string; refresh: string } | null>;
  storeRotated?: (pair: { access: string; refresh: string }) => Promise<void>;
  makeError: (status: number, code: string, message: string, traceId: string) => Error;
}): Promise<WorkerEnvelope> {
  let res = await executeAuthedFetch(opts);
  if (res.status === 401) {
    const pair = await opts.refresh();
    if (pair) {
      if (opts.storeRotated) await opts.storeRotated(pair);
      res = await executeAuthedFetch(opts);
    }
  }
  const text = await res.text().catch(() => "");
  if (!res.ok) {
    const err = parseEnvelope<WorkerErrorShape>(text, {}) as WorkerErrorShape;
    console.error(`[${opts.logTag}] ${opts.method} ${opts.path} → ${res.status} ${err.error?.code ?? "SERVER"}`);
    throw opts.makeError(
      res.status,
      err.error?.code ?? "SERVER",
      err.error?.message ?? `${opts.method} ${opts.path} failed`,
      err.error?.trace_id ?? "",
    );
  }
  return parseEnvelope(text, {}) as unknown as WorkerEnvelope;
}
