import { createServerFn } from "@tanstack/react-start";
import { getCookie, setCookie } from "@tanstack/react-start/server";

import { callWorkerPublic } from "./admin-api";

/**
 * Admin session against the Python Workers API (BFF — same HttpOnly cookie
 * names/flags, same admin-role gate). Login is phone + access code via
 * POST /v1/auth/admin/login. The access token never reaches browser code.
 */

export const SESSION_COOKIE = "sh_session";
export const REFRESH_COOKIE = "sh_refresh";

// Device ids minted at login and pinned at refresh: the worker rejects
// refresh when device_id != device_fp, so each surface must refresh with
// the id it logged in with (vendor uses VENDOR_WEB_DEVICE).
export const ADMIN_WEB_DEVICE = "admin-web";

let loggedApiHost = false;

export function apiUrl(): string {
  // Bare worker origin (wrangler.jsonc documents the value). A trailing
  // slash — or a pasted "/v1" suffix — used to silently build //v1 or
  // /v1/v1 paths: the worker answers those with a non-envelope 404 and the
  // UI could only say "Verification failed." Normalize + log the host once
  // per isolate so `wrangler tail` shows what prod actually dials.
  const raw = (process.env.API_URL ?? "http://127.0.0.1:8000").trim();
  const url = raw.replace(/\/+$/, "").replace(/\/v1$/, "");
  if (!loggedApiHost) {
    loggedApiHost = true;
    if (url !== raw) console.error(`[admin-auth] normalized API_URL ${raw} → ${url}`);
    else console.log(`[admin-auth] API_URL ${url}`);
  }
  return url;
}

export const COOKIE_FLAGS = {
  path: "/",
  sameSite: "lax" as const,
  secure: process.env.NODE_ENV === "production",
  httpOnly: true,
};

export type LoginVerifyResult =
  | { ok: true; role: string }
  | { ok: false; status: number; code: string; message: string };

/**
 * Admin phone + access-code login (028). Calls the worker's generalized
 * access-code door (014 `access_codes` table, `access_code_login_enabled`
 * flag — backend owns the final flag name), asserts role=admin, and sets
 * the same HttpOnly cookies as before. Generic 401, no oracle.
 */
export const loginCodeServer = createServerFn({ method: "POST" })
  .validator((input: { phone: string; code: string }) => input)
  .handler(async ({ data }): Promise<LoginVerifyResult> => {
    let res: Response;
    try {
      res = await callWorkerPublic("/v1/auth/admin/login", {
        phone: data.phone,
        code: data.code,
        device: { id: ADMIN_WEB_DEVICE },
      });
    } catch (e) {
      console.error(`[admin-auth] admin/login fetch failed: ${e instanceof Error ? e.message : e}`);
      return { ok: false, status: 0, code: "NETWORK", message: "API worker unreachable. Check API_URL and worker status." };
    }
    const body = (await res.json().catch(() => ({}))) as {
      access_token?: string;
      refresh_token?: string;
      role?: string;
      error?: { code?: string; message?: string };
    };
    if (!res.ok) {
      const code = body.error?.code ?? "UNAUTH";
      // Never log tokens — status + worker code is the triage signal.
      console.error(`[admin-auth] admin/login failed: POST /v1/auth/admin/login → ${res.status} ${code}`);
      return {
        ok: false,
        status: res.status,
        code,
        // Generic copy — the worker must not oracle valid phones vs codes.
        message: body.error?.message ?? "Invalid phone or code.",
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
    const res = await callWorkerPublic("/v1/auth/refresh", {
      refresh_token,
      device: { id: ADMIN_WEB_DEVICE },
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
    await callWorkerPublic(
      "/v1/auth/logout",
      {},
      { authorization: `Bearer ${access}` },
    ).catch(() => undefined);
  }
  setCookie(SESSION_COOKIE, "", { ...COOKIE_FLAGS, maxAge: 0 });
  setCookie(REFRESH_COOKIE, "", { ...COOKIE_FLAGS, maxAge: 0 });
});

export const hasSessionServer = createServerFn({ method: "GET" }).handler((): { authed: boolean } => ({
  authed: Boolean(getCookie(SESSION_COOKIE)),
}));
