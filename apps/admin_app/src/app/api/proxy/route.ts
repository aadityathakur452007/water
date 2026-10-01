import { NextResponse, type NextRequest } from "next/server";
import { ApiError, apiGet, refreshSession, sessionCookieHeader, SESSION_COOKIE_OPTS } from "@/lib/api";

/**
 * BFF GET proxy: the browser calls /api/proxy?url=/v1/… with its session
 * cookie; the worker cookie is attached server-side and never exposed.
 * GET-only — mutations go through dedicated routes so CSRF/idempotency stays explicit.
 *
 * Silent renewal: on worker 401 the refresh cookie is exchanged once for a new
 * pair; the request is retried with the new access token and fresh cookies are
 * set on the response. The admin is only bounced to /login when the refresh
 * family itself is dead.
 */
export async function GET(req: NextRequest) {
  const target = req.nextUrl.searchParams.get("url");
  if (!target || !target.startsWith("/v1/admin/") && !target.startsWith("/v1/catalog")) {
    return NextResponse.json(
      { error: { code: "VALIDATION", message: "url must be an admin /v1 path" } },
      { status: 400 },
    );
  }
  const cookie = req.headers.get("cookie") ?? "";
  try {
    const data = await apiGet<unknown>(target, cookie);
    return NextResponse.json(data);
  } catch (err) {
    if (err instanceof ApiError && err.status === 401) {
      const pair = await refreshSession(cookie);
      if (pair) {
        try {
          const data = await apiGet<unknown>(
            target,
            sessionCookieHeader(pair.access, pair.refresh),
          );
          const out = NextResponse.json(data);
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
