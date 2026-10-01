/**
 * Server-side worker fetch: browser → Next.js route/proxy → Workers API.
 * Cookie-forwarded (BFF), never exposed to the client. Mock mode returns null
 * so pages can fall back to fixtures for offline UI work.
 */
const API_URL = process.env.API_URL ?? "http://127.0.0.1:8000";
const MOCK = process.env.NEXT_PUBLIC_API_MODE === "mock";

export class ApiError extends Error {
  code: string;
  status: number;
  traceId: string;

  constructor(status: number, code: string, message: string, traceId = "") {
    super(message);
    this.status = status;
    this.code = code;
    this.traceId = traceId;
  }
}

type WorkerErrorShape = {
  error?: { code?: string; message?: string; details?: Record<string, unknown>; trace_id?: string };
};

/** Server-only GET/POST/PATCH against the Workers API with the admin cookie. */
export async function workerFetch(
  path: string,
  init: RequestInit & { cookie?: string } = {},
): Promise<Response> {
  if (MOCK) {
    // Sentinel error the callers translate into "use fixtures".
    throw new ApiError(0, "MOCK_MODE", "mock mode — use fixtures");
  }
  const { cookie, ...rest } = init;
  const headers = new Headers(rest.headers);
  if (cookie) headers.set("cookie", cookie);
  if (rest.body && !headers.has("content-type")) headers.set("content-type", "application/json");
  let res: Response;
  try {
    res = await fetch(`${API_URL}${path}`, {
      ...rest,
      headers,
      cache: "no-store",
      signal: AbortSignal.timeout(15_000),
    });
  } catch {
    throw new ApiError(0, "NETWORK", "Workers API unreachable");
  }
  return res;
}

/** GET JSON or throw ApiError with the worker's envelope. */
export async function apiGet<T>(path: string, cookie?: string): Promise<T> {
  const res = await workerFetch(path, { cookie });
  if (!res.ok) {
    const body = (await res.json().catch(() => ({}))) as WorkerErrorShape;
    throw new ApiError(
      res.status,
      body.error?.code ?? "SERVER",
      body.error?.message ?? `GET ${path} failed`,
      body.error?.trace_id ?? "",
    );
  }
  return (await res.json()) as T;
}

/** Mutating call from a browser request: forwards cookie + CSRF headers. */
export async function apiMutate(
  method: "POST" | "PATCH" | "DELETE",
  path: string,
  body: unknown,
  req: Request,
  cookieOverride?: string,
): Promise<unknown> {
  const cookie = cookieOverride ?? req.headers.get("cookie") ?? "";
  const res = await workerFetch(path, {
    method,
    cookie,
    body: JSON.stringify(body ?? {}),
    headers: {
      "x-csrf-token": req.headers.get("x-csrf-token") ?? "",
      "idempotency-key": req.headers.get("idempotency-key") ?? crypto.randomUUID(),
    },
  });
  const text = await res.text().catch(() => "");
  let json: WorkerErrorShape & Record<string, unknown> = {};
  try {
    json = (text ? JSON.parse(text) : {}) as WorkerErrorShape & Record<string, unknown>;
  } catch {
    json = {};
  }
  if (!res.ok) {
    // Include the upstream status + body snippet so a failing hop is
    // self-describing in the UI (e.g. non-envelope 403s from the edge).
    const snippet = text.slice(0, 200);
    throw new ApiError(
      res.status,
      (json.error?.code as string | undefined) ?? "SERVER",
      (json.error?.message as string | undefined) ??
        `${method} ${path} failed (upstream ${res.status}${snippet ? `: ${snippet}` : ""})`,
      (json.error?.trace_id as string | undefined) ?? "",
    );
  }
  return json;
}

/** Flags shared by every Set-Cookie of the admin session (mirrors the login route). */
export const SESSION_COOKIE_OPTS = {
  httpOnly: true,
  sameSite: "lax" as const,
  secure: process.env.NODE_ENV === "production",
  path: "/",
};

/**
 * Silent session renewal: exchanges the `sh_refresh` cookie for a fresh pair.
 * Returns null when there is no refresh cookie or the worker rejects it — the
 * caller then lets the original 401 propagate (the UI bounces to /login).
 */
export async function refreshSession(
  cookie: string,
): Promise<{ access: string; refresh: string } | null> {
  const m = /(?:^|;\s*)sh_refresh=([^;]+)/.exec(cookie);
  if (!m) return null;
  const refresh_token = decodeURIComponent(m[1]);
  try {
    const res = await fetch(`${API_URL}/v1/auth/refresh`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ refresh_token, device: { id: "admin-web" } }),
      cache: "no-store",
      signal: AbortSignal.timeout(15_000),
    });
    if (!res.ok) return null;
    const data = (await res.json().catch(() => null)) as
      | { access_token?: string; refresh_token?: string }
      | null;
    if (!data?.access_token || !data?.refresh_token) return null;
    return { access: data.access_token, refresh: data.refresh_token };
  } catch {
    return null;
  }
}

/** Cookie header for a rotated pair (retry calls only; flags ride on Set-Cookie). */
export function sessionCookieHeader(access: string, refresh: string): string {
  return `sh_session=${encodeURIComponent(access)}; sh_refresh=${encodeURIComponent(refresh)}`;
}
