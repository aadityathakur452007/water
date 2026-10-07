import { createServerFn } from "@tanstack/react-start";
import { getCookie, setCookie } from "@tanstack/react-start/server";

import { callWorkerPublic } from "./admin-api";
import { ACCESS_COOKIE_MAX_AGE, COOKIE_FLAGS, REFRESH_COOKIE_MAX_AGE } from "./admin-session";

/**
 * Vendor session (BFF for /vendor/*). Namespaced HttpOnly cookies
 * (sh_vendor_session + sh_vendor_refresh) to prevent collisions with the admin session.
 */

export const VENDOR_SESSION_COOKIE = "sh_vendor_session";
export const VENDOR_REFRESH_COOKIE = "sh_vendor_refresh";

function getVendorSessionToken(): string | undefined {
  return getCookie(VENDOR_SESSION_COOKIE) || getCookie("sh_session");
}

function getVendorRefreshToken(): string | undefined {
  return getCookie(VENDOR_REFRESH_COOKIE) || getCookie("sh_refresh");
}

export type VendorLoginResult =
  | { ok: true; role: string }
  | { ok: false; status: number; code: string; message: string };

// Device id minted at vendor login — the worker pins refresh to it, so the
// vendor guard/proxy must refresh with this id, never ADMIN_WEB_DEVICE.
export const VENDOR_WEB_DEVICE = "vendor-web";

/** Phone + admin-issued access code → vendor session (no OTP, no signup). */
export const loginVendorVerifyServer = createServerFn({ method: "POST" })
  .validator((input: { phone: string; code: string }) => input)
  .handler(async ({ data }): Promise<VendorLoginResult> => {
    let res: Response;
    try {
      res = await callWorkerPublic("/v1/auth/vendor/login", {
        phone: data.phone,
        code: data.code,
        device: { id: VENDOR_WEB_DEVICE },
      });
    } catch (e) {
      console.error(`[vendor-auth] login fetch failed: ${e instanceof Error ? e.message : e}`);
      return {
        ok: false,
        status: 0,
        code: "NETWORK",
        message: "API worker unreachable. Check API_URL and worker status.",
      };
    }
    const body = (await res.json().catch(() => ({}))) as {
      access_token?: string;
      refresh_token?: string;
      role?: string;
      user_id?: string;
      error?: { code?: string; message?: string };
    };
    if (!res.ok) {
      const code = body.error?.code ?? "UNAUTH";
      console.error(`[vendor-auth] login failed: POST /v1/auth/vendor/login → ${res.status} ${code}`);
      return {
        ok: false,
        status: res.status,
        code,
        message: body.error?.message ?? "Invalid phone or code.",
      };
    }
    if (body.role !== "vendor") {
      return { ok: false, status: 403, code: "FORBIDDEN", message: "This number is not a vendor." };
    }
    setCookie(VENDOR_SESSION_COOKIE, body.access_token ?? "", { ...COOKIE_FLAGS, maxAge: ACCESS_COOKIE_MAX_AGE });
    setCookie(VENDOR_REFRESH_COOKIE, body.refresh_token ?? "", { ...COOKIE_FLAGS, maxAge: REFRESH_COOKIE_MAX_AGE });
    return { ok: true, role: body.role };
  });

export const hasVendorSessionServer = createServerFn({ method: "GET" }).handler((): { authed: boolean } => ({
  authed: Boolean(getVendorSessionToken()),
}));

let activeVendorRefreshPromise: Promise<{ access: string; refresh: string } | null> | null = null;

/** Vendor silent renewal: deduplicated in-flight to prevent burned-token reuse revocation */
export const refreshVendorSessionServer = createServerFn({ method: "POST" }).handler(
  async (): Promise<{ access: string; refresh: string } | null> => {
    if (activeVendorRefreshPromise) {
      return activeVendorRefreshPromise;
    }

    const refresh_token = getVendorRefreshToken();
    if (!refresh_token) return null;

    activeVendorRefreshPromise = (async () => {
      try {
        const res = await callWorkerPublic("/v1/auth/refresh", {
          refresh_token,
          device: { id: VENDOR_WEB_DEVICE },
        });
        if (!res.ok) return null;
        const data = (await res.json().catch(() => null)) as { access_token?: string; refresh_token?: string } | null;
        if (!data?.access_token || !data?.refresh_token) return null;

        setCookie(VENDOR_SESSION_COOKIE, data.access_token, { ...COOKIE_FLAGS, maxAge: ACCESS_COOKIE_MAX_AGE });
        setCookie(VENDOR_REFRESH_COOKIE, data.refresh_token, { ...COOKIE_FLAGS, maxAge: REFRESH_COOKIE_MAX_AGE });

        return { access: data.access_token, refresh: data.refresh_token };
      } catch (err) {
        console.error("[vendor-auth] silent refresh failed:", err);
        return null;
      } finally {
        activeVendorRefreshPromise = null;
      }
    })();

    return activeVendorRefreshPromise;
  },
);

export const logoutVendorServer = createServerFn({ method: "POST" }).handler(async () => {
  const access = getVendorSessionToken();
  if (access) {
    await callWorkerPublic("/v1/auth/logout", {}, { authorization: `Bearer ${access}` }).catch(() => undefined);
  }
  setCookie(VENDOR_SESSION_COOKIE, "", { ...COOKIE_FLAGS, maxAge: 0 });
  setCookie(VENDOR_REFRESH_COOKIE, "", { ...COOKIE_FLAGS, maxAge: 0 });
  setCookie("sh_session", "", { ...COOKIE_FLAGS, maxAge: 0 });
  setCookie("sh_refresh", "", { ...COOKIE_FLAGS, maxAge: 0 });
});
