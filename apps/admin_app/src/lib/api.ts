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
): Promise<unknown> {
  const cookie = req.headers.get("cookie") ?? "";
  const res = await workerFetch(path, {
    method,
    cookie,
    body: JSON.stringify(body ?? {}),
    headers: {
      "x-csrf-token": req.headers.get("x-csrf-token") ?? "",
      "idempotency-key": req.headers.get("idempotency-key") ?? crypto.randomUUID(),
    },
  });
  const json = (await res.json().catch(() => ({}))) as WorkerErrorShape & Record<string, unknown>;
  if (!res.ok) {
    throw new ApiError(
      res.status,
      json.error?.code ?? "SERVER",
      json.error?.message ?? `${method} ${path} failed`,
      json.error?.trace_id ?? "",
    );
  }
  return json;
}
