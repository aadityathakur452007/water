import { createServerFn } from "@tanstack/react-start";
import { getCookie, setCookie } from "@tanstack/react-start/server";

import { callWorkerPublic } from "./admin-api";

/**
 * Admin session against the Python Workers API (BFF — same HttpOnly cookie
 * names/flags, same admin-role gate). Login is phone + access code via
 * POST /v1/auth/admin/login. The access token never reaches browser code.
 */

export const ADMIN_SESSION_COOKIE = "sh_admin_session";
export const ADMIN_REFRESH_COOKIE = "sh_admin_refresh";

// Backward-compatibility aliases
export const SESSION_COOKIE = ADMIN_SESSION_COOKIE;
export const REFRESH_COOKIE = ADMIN_REFRESH_COOKIE;

function getAdminSessionToken(): string | undefined {
  return getCookie(ADMIN_SESSION_COOKIE) || getCookie("sh_session");
}

function getAdminRefreshToken(): string | undefined {
  return getCookie(ADMIN_REFRESH_COOKIE) || getCookie("sh_refresh");
}

// Device ids minted at login and pinned at refresh: the worker rejects
// refresh when device_id != device_fp, so each surface must refresh with
// the id it logged in with (vendor uses VENDOR_WEB_DEVICE).
export const ADMIN_WEB_DEVICE = "admin-web";

let loggedApiHost = false;

export function apiUrl(): string {
  const raw = (process.env.API_URL ?? "http://127.0.0.1:8000").trim();
  const url = raw.replace(/\/+$/, "").replace(/\/v1$/, "");
  if (!loggedApiHost) {
    loggedApiHost = true;
    if (url !== raw) console.error(`[admin-auth] normalized API_URL ${raw} → ${url}`);
    else console.log(`[admin-auth] API_URL ${url}`);
  }
  return url;
}

const isDevHttp = process.env.NODE_ENV === "development" && !process.env.COOKIE_SECURE;

export const COOKIE_FLAGS = {
  path: "/",
  sameSite: "lax" as const,
  secure: !isDevHttp,
  httpOnly: true,
};

// 24 hours for access token cookie, 30 days for refresh token cookie
export const ACCESS_COOKIE_MAX_AGE = 60 * 60 * 24;
export const REFRESH_COOKIE_MAX_AGE = 60 * 60 * 24 * 30;

export type LoginVerifyResult =
  | { ok: true; role: string }
  | { ok: false; status: number; code: string; message: string };

/**
 * Admin phone + access-code login. Calls the worker's generalized
 * access-code door, asserts role=admin, and sets namespaced HttpOnly cookies.
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
      console.error(`[admin-auth] admin/login failed: POST /v1/auth/admin/login → ${res.status} ${code}`);
      return {
        ok: false,
        status: res.status,
        code,
        message: body.error?.message ?? "Invalid phone or code.",
      };
    }
    if (body.role !== "admin") {
      return { ok: false, status: 403, code: "FORBIDDEN", message: "This number is not an admin." };
    }

    setCookie(ADMIN_SESSION_COOKIE, body.access_token ?? "", { ...COOKIE_FLAGS, maxAge: ACCESS_COOKIE_MAX_AGE });
    setCookie(ADMIN_REFRESH_COOKIE, body.refresh_token ?? "", { ...COOKIE_FLAGS, maxAge: REFRESH_COOKIE_MAX_AGE });
    return { ok: true, role: body.role };
  });

// In-flight refresh promise cache to deduplicate parallel refresh calls and prevent burned-token reuse revocation
let activeRefreshPromise: Promise<{ access: string; refresh: string } | null> | null = null;

/** Silent renewal: sh_admin_refresh → /v1/auth/refresh → rotated pair. Returns null when unusable. */
export const refreshSessionServer = createServerFn({ method: "POST" }).handler(
  async (): Promise<{ access: string; refresh: string } | null> => {
    if (activeRefreshPromise) {
      return activeRefreshPromise;
    }

    const refresh_token = getAdminRefreshToken();
    if (!refresh_token) return null;

    activeRefreshPromise = (async () => {
      try {
        const res = await callWorkerPublic("/v1/auth/refresh", {
          refresh_token,
          device: { id: ADMIN_WEB_DEVICE },
        });
        if (!res.ok) return null;
        const data = (await res.json().catch(() => null)) as { access_token?: string; refresh_token?: string } | null;
        if (!data?.access_token || !data?.refresh_token) return null;

        // Auto-persist new cookies directly
        setCookie(ADMIN_SESSION_COOKIE, data.access_token, { ...COOKIE_FLAGS, maxAge: ACCESS_COOKIE_MAX_AGE });
        setCookie(ADMIN_REFRESH_COOKIE, data.refresh_token, { ...COOKIE_FLAGS, maxAge: REFRESH_COOKIE_MAX_AGE });

        return { access: data.access_token, refresh: data.refresh_token };
      } catch (err) {
        console.error("[admin-auth] silent refresh failed:", err);
        return null;
      } finally {
        activeRefreshPromise = null;
      }
    })();

    return activeRefreshPromise;
  },
);

/** Stores a freshly rotated pair as cookies. */
export const storeRotatedSessionServer = createServerFn({ method: "POST" })
  .validator((input: { access: string; refresh: string }) => input)
  .handler(({ data }) => {
    setCookie(ADMIN_SESSION_COOKIE, data.access, { ...COOKIE_FLAGS, maxAge: ACCESS_COOKIE_MAX_AGE });
    setCookie(ADMIN_REFRESH_COOKIE, data.refresh, { ...COOKIE_FLAGS, maxAge: REFRESH_COOKIE_MAX_AGE });
  });

export const logoutServer = createServerFn({ method: "POST" }).handler(async () => {
  const access = getAdminSessionToken();
  if (access) {
    await callWorkerPublic(
      "/v1/auth/logout",
      {},
      { authorization: `Bearer ${access}` },
    ).catch(() => undefined);
  }
  // Clear namespaced and legacy cookies
  setCookie(ADMIN_SESSION_COOKIE, "", { ...COOKIE_FLAGS, maxAge: 0 });
  setCookie(ADMIN_REFRESH_COOKIE, "", { ...COOKIE_FLAGS, maxAge: 0 });
  setCookie("sh_session", "", { ...COOKIE_FLAGS, maxAge: 0 });
  setCookie("sh_refresh", "", { ...COOKIE_FLAGS, maxAge: 0 });
});

export const hasSessionServer = createServerFn({ method: "GET" }).handler((): { authed: boolean } => ({
  authed: Boolean(getAdminSessionToken()),
}));
