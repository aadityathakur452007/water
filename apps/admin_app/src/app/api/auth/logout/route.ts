import { NextResponse } from "next/server";
import { workerFetch } from "@/lib/api";

export async function POST(req: Request) {
  const cookie = req.headers.get("cookie") ?? "";
  try {
    await workerFetch("/v1/auth/logout", {
      method: "POST",
      cookie,
      body: JSON.stringify({}),
    });
  } catch {
    // Clear the cookie regardless — the panel must never strand a session.
  }
  const res = NextResponse.json({ ok: true });
  res.cookies.set("sh_session", "", { httpOnly: true, path: "/", maxAge: 0 });
  res.cookies.set("sh_csrf", "", { path: "/", maxAge: 0 });
  return res;
}
