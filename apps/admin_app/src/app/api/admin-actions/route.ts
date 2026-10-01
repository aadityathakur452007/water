import { NextResponse, type NextRequest } from "next/server";
import { ApiError, apiMutate, refreshSession, sessionCookieHeader, SESSION_COOKIE_OPTS } from "@/lib/api";

/**
 * BFF POST proxy for admin mutations. The worker remains the only authority:
 * this route forwards cookie + CSRF + idempotency headers verbatim and maps
 * the worker error envelope 1:1 (never widens a contract, §0).
 *
 * Silent renewal on 401 mirrors the GET proxy, with one subtlety: a retried
 * mutation re-sends the ORIGINAL request's idempotency key, so a write that
 * succeeded server-side before the token expired cannot be applied twice —
 * the worker returns the first result (contract §3 idempotency scope).
 */
export async function POST(req: NextRequest) {
  const target = req.nextUrl.searchParams.get("url");
  if (!target || !target.startsWith("/v1/admin/")) {
    return NextResponse.json(
      { error: { code: "VALIDATION", message: "url must be an admin /v1 path" } },
      { status: 400 },
    );
  }
  const body = await req.json().catch(() => ({}));
  try {
    const data = await apiMutate("POST", target, body, req);
    return NextResponse.json(data ?? { ok: true });
  } catch (err) {
    if (err instanceof ApiError && err.status === 401) {
      const cookie = req.headers.get("cookie") ?? "";
      const pair = await refreshSession(cookie);
      if (pair) {
        try {
          const data = await apiMutate("POST", target, body, req, sessionCookieHeader(pair.access, pair.refresh));
          const out = NextResponse.json(data ?? { ok: true });
          out.cookies.set("sh_session", pair.access, { ...SESSION_COOKIE_OPTS, maxAge: 60 * 30 });
          out.cookies.set("sh_refresh", pair.refresh, {
            ...SESSION_COOKIE_OPTS,
            maxAge: 60 * 60 * 24 * 7,
          });
          return out;
        } catch {
          // Refreshed token also failed — fall through to the login bounce.
        }
      }
      return NextResponse.json(
        { error: { code: "UNAUTH", message: "Session expired — sign in again." } },
        { status: 401 },
      );
    }
    if (err instanceof ApiError) {
      return NextResponse.json(
        { error: { code: err.code, message: err.message, trace_id: err.traceId } },
        { status: err.status || 502 },
      );
    }
    return NextResponse.json(
      { error: { code: "SERVER", message: "proxy failure" } },
      { status: 500 },
    );
  }
}
