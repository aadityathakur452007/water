import { NextResponse, type NextRequest } from "next/server";
import { ApiError, apiGet } from "@/lib/api";

/**
 * BFF GET proxy: the browser calls /api/proxy?url=/v1/… with its session
 * cookie; the worker cookie is attached server-side and never exposed.
 * GET-only — mutations go through dedicated routes so CSRF/idempotency stays explicit.
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
