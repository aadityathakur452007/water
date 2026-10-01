import { NextResponse, type NextRequest } from "next/server";
import { ApiError, apiMutate } from "@/lib/api";

/**
 * BFF POST proxy for admin mutations. The worker remains the only authority:
 * this route forwards cookie + CSRF + idempotency headers verbatim and maps
 * the worker error envelope 1:1 (never widens a contract, §0).
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
