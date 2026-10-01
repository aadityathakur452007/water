import { NextResponse, type NextRequest } from "next/server";

/**
 * Route gate (Next 16 `proxy` convention): /admin/* requires the sh_session
 * cookie (role check happens server-side on every worker call — this is UX
 * routing, never the security boundary, per contract §0 C2).
 */
export default function proxy(req: NextRequest) {
  const { pathname } = req.nextUrl;
  const hasSession = Boolean(req.cookies.get("sh_session")?.value);
  if (pathname.startsWith("/admin") && !hasSession) {
    const url = req.nextUrl.clone();
    url.pathname = "/login";
    url.searchParams.set("next", pathname);
    return NextResponse.redirect(url);
  }
  if (pathname === "/login" && hasSession) {
    const url = req.nextUrl.clone();
    url.pathname = "/admin";
    url.search = "";
    return NextResponse.redirect(url);
  }
  return NextResponse.next();
}

export const config = {
  matcher: ["/admin/:path*", "/login"],
};
