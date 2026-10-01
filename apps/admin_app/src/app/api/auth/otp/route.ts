import { NextResponse, type NextRequest } from "next/server";
import { ApiError, apiMutate, workerFetch } from "@/lib/api";

/**
 * Admin login BFF. Step 1 {action:"start"} → worker OTP start (Firebase SMS).
 * Step 2 {action:"verify"} → worker verify with the Firebase ID token;
 * only role=admin gets the HttpOnly `sh_session` cookie (contract §3: admin web
 * HttpOnly cookie; role enforced again server-side on every call).
 */
export async function POST(req: NextRequest) {
  const body = (await req.json().catch(() => ({}))) as {
    action?: "start" | "verify";
    phone?: string;
    firebase_id_token?: string;
    device_id?: string;
  };

  try {
    if (body.action === "start") {
      const data = (await apiMutate("POST", "/v1/auth/otp/start", { phone: body.phone }, req)) as {
        sent_to_masked?: string;
        resend_after_s?: number;
      };
      return NextResponse.json(data ?? { ok: true });
    }

    if (body.action === "verify") {
      const res = await workerFetch("/v1/auth/otp/verify", {
        method: "POST",
        body: JSON.stringify({
          firebase_id_token: body.firebase_id_token,
          device: { id: body.device_id ?? "admin-web" },
        }),
      });
      const data = (await res.json().catch(() => ({}))) as {
        access_token?: string;
        refresh_token?: string;
        role?: string;
        error?: { code: string; message: string };
      };
      if (!res.ok) {
        return NextResponse.json(
          { error: data.error ?? { code: "UNAUTH", message: "Verification failed" } },
          { status: res.status },
        );
      }
      if (data.role !== "admin") {
        return NextResponse.json(
          { error: { code: "FORBIDDEN", message: "This number is not an admin." } },
          { status: 403 },
        );
      }
      const out = NextResponse.json({ ok: true, role: data.role });
      const secure = process.env.NODE_ENV === "production";
      out.cookies.set("sh_session", data.access_token ?? "", {
        httpOnly: true,
        sameSite: "lax",
        secure,
        path: "/",
        maxAge: 60 * 30,
      });
      out.cookies.set("sh_refresh", data.refresh_token ?? "", {
        httpOnly: true,
        sameSite: "lax",
        secure,
        path: "/",
        maxAge: 60 * 60 * 24 * 7,
      });
      return out;
    }

    return NextResponse.json(
      { error: { code: "VALIDATION", message: "action must be start|verify" } },
      { status: 400 },
    );
  } catch (err) {
    if (err instanceof ApiError) {
      return NextResponse.json(
        { error: { code: err.code, message: err.message } },
        { status: err.status || 502 },
      );
    }
    return NextResponse.json(
      { error: { code: "SERVER", message: "login failure" } },
      { status: 500 },
    );
  }
}
