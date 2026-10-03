import { createServerFn } from "@tanstack/react-start";
import { getCookie, setCookie } from "@tanstack/react-start/server";

/**
 * Admin session against the Python Workers API (BFF — mirrors
 * apps/admin_app's /api/auth/otp routes 1:1: same endpoint calls, same
 * HttpOnly cookie names/flags, same admin-role gate). The access token
 * never reaches browser code.
 */

export const SESSION_COOKIE = "sh_session";
export const REFRESH_COOKIE = "sh_refresh";

export function apiUrl(): string {
  return process.env.API_URL ?? "http://127.0.0.1:8000";
}

const COOKIE_FLAGS = {
  path: "/",
  sameSite: "lax" as const,
  secure: process.env.NODE_ENV === "production",
};

export type LoginStartResult = { sent_to_masked?: string; resend_after_s?: number };

export type LoginVerifyResult =
  | { ok: true; role: string }
  | { ok: false; status: number; code: string; message: string };

export const loginStartServer = createServerFn({ method: "POST" })
  .validator((input: { phone: string }) => input)
  .handler(async ({ data }): Promise<LoginStartResult> => {
    const res = await fetch(`${apiUrl()}/v1/auth/otp/start`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ phone: data.phone }),
      signal: AbortSignal.timeout(15_000),
    });
    if (!res.ok) {
      throw new Error("Could not send the code.");
    }
    return (await res.json().catch(() => ({}))) as LoginStartResult;
  });

export const loginVerifyServer = createServerFn({ method: "POST" })
  .validator((input: { id_token: string }) => input)
  .handler(async ({ data }): Promise<LoginVerifyResult> => {
    const res = await fetch(`${apiUrl()}/v1/auth/otp/verify`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ firebase_id_token: data.id_token, device: { id: "admin-web" } }),
      signal: AbortSignal.timeout(15_000),
    });
    const body = (await res.json().catch(() => ({}))) as {
      access_token?: string;
      refresh_token?: string;
      role?: string;
      error?: { code: string; message: string };
    };
    if (!res.ok) {
      return {
        ok: false,
        status: res.status,
        code: body.error?.code ?? "UNAUTH",
        message: body.error?.message ?? "Verification failed.",
      };
    }
    if (body.role !== "admin") {
      return { ok: false, status: 403, code: "FORBIDDEN", message: "This number is not an admin." };
    }
    // Same cookie names/flags as the old admin's login route.
    setCookie(SESSION_COOKIE, body.access_token ?? "", { ...COOKIE_FLAGS, maxAge: 60 * 30 });
    setCookie(REFRESH_COOKIE, body.refresh_token ?? "", { ...COOKIE_FLAGS, maxAge: 60 * 60 * 24 * 7 });
    return { ok: true, role: body.role };
  });

/** Silent renewal: sh_refresh → /v1/auth/refresh → rotated pair. Returns null when unusable. */
export const refreshSessionServer = createServerFn({ method: "POST" }).handler(
  async (): Promise<{ access: string; refresh: string } | null> => {
    const refresh_token = getCookie(REFRESH_COOKIE);
    if (!refresh_token) return null;
    const res = await fetch(`${apiUrl()}/v1/auth/refresh`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ refresh_token, device: { id: "admin-web" } }),
      signal: AbortSignal.timeout(15_000),
    });
    if (!res.ok) return null;
    const data = (await res.json().catch(() => null)) as { access_token?: string; refresh_token?: string } | null;
    if (!data?.access_token || !data?.refresh_token) return null;
    return { access: data.access_token, refresh: data.refresh_token };
  },
);

/** Stores a freshly rotated pair as cookies (called after a successful refresh-retry). */
export const storeRotatedSessionServer = createServerFn({ method: "POST" })
  .validator((input: { access: string; refresh: string }) => input)
  .handler(({ data }) => {
    setCookie(SESSION_COOKIE, data.access, { ...COOKIE_FLAGS, maxAge: 60 * 30 });
    setCookie(REFRESH_COOKIE, data.refresh, { ...COOKIE_FLAGS, maxAge: 60 * 60 * 24 * 7 });
  });

export const logoutServer = createServerFn({ method: "POST" }).handler(async () => {
  const access = getCookie(SESSION_COOKIE);
  if (access) {
    // Best-effort worker-side revocation; cookie clearing always wins.
    await fetch(`${apiUrl()}/v1/auth/logout`, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: `Bearer ${access}` },
      body: JSON.stringify({}),
      signal: AbortSignal.timeout(5_000),
    }).catch(() => undefined);
  }
  setCookie(SESSION_COOKIE, "", { ...COOKIE_FLAGS, maxAge: 0 });
  setCookie(REFRESH_COOKIE, "", { ...COOKIE_FLAGS, maxAge: 0 });
});

export const hasSessionServer = createServerFn({ method: "GET" }).handler((): { authed: boolean } => ({
  authed: Boolean(getCookie(SESSION_COOKIE)),
}));
