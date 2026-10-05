import { createServerFn } from "@tanstack/react-start";
import { getCookie, setCookie } from "@tanstack/react-start/server";

import { callWorkerPublic } from "./admin-api";
import { COOKIE_FLAGS, REFRESH_COOKIE, SESSION_COOKIE } from "./admin-session";

/**
 * Vendor session (BFF for /vendor/*). Same HttpOnly cookie names/flags/TTLs
 * as the admin session (30m access + 7d refresh) — one session per browser
 * by construction. The access token never reaches browser code.
 *
 * Role truth lives in the worker: POST /v1/auth/vendor/login asserts
 * users.role == "vendor", and every /v1/vendor/* route re-checks
 * require_role("vendor") per request. The `role === "vendor"` assert below
 * is a second gate, never the only one.
 */

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
        // Generic copy — the worker must not oracle valid phones vs codes.
        message: body.error?.message ?? "Invalid phone or code.",
      };
    }
    if (body.role !== "vendor") {
      return { ok: false, status: 403, code: "FORBIDDEN", message: "This number is not a vendor." };
    }
    setCookie(SESSION_COOKIE, body.access_token ?? "", { ...COOKIE_FLAGS, maxAge: 60 * 30 });
    setCookie(REFRESH_COOKIE, body.refresh_token ?? "", { ...COOKIE_FLAGS, maxAge: 60 * 60 * 24 * 7 });
    return { ok: true, role: body.role };
  });

export const hasVendorSessionServer = createServerFn({ method: "GET" }).handler((): { authed: boolean } => ({
  // Cookie presence only — the worker enforces require_role("vendor") on
  // every call, and vendorGet/PostServer bounce 401/403 to /vendor/login.
  authed: Boolean(getCookie(SESSION_COOKIE)),
}));

/** Vendor silent renewal: same contract as refreshSessionServer but pinned
 * to the vendor device id (the worker rejects cross-device refresh). */
export const refreshVendorSessionServer = createServerFn({ method: "POST" }).handler(
  async (): Promise<{ access: string; refresh: string } | null> => {
    const refresh_token = getCookie(REFRESH_COOKIE);
    if (!refresh_token) return null;
    const res = await callWorkerPublic("/v1/auth/refresh", {
      refresh_token,
      device: { id: VENDOR_WEB_DEVICE },
    });
    if (!res.ok) return null;
    const data = (await res.json().catch(() => null)) as { access_token?: string; refresh_token?: string } | null;
    if (!data?.access_token || !data?.refresh_token) return null;
    return { access: data.access_token, refresh: data.refresh_token };
  },
);

export const logoutVendorServer = createServerFn({ method: "POST" }).handler(async () => {
  const access = getCookie(SESSION_COOKIE);
  if (access) {
    // Best-effort worker-side revocation; cookie clearing always wins.
    await callWorkerPublic("/v1/auth/logout", {}, { authorization: `Bearer ${access}` }).catch(() => undefined);
  }
  setCookie(SESSION_COOKIE, "", { ...COOKIE_FLAGS, maxAge: 0 });
  setCookie(REFRESH_COOKIE, "", { ...COOKIE_FLAGS, maxAge: 0 });
});
