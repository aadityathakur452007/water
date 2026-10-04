import { createServerFn } from "@tanstack/react-start";
import { getCookie, setCookie } from "@tanstack/react-start/server";

import { callWorkerPublic } from "./admin-api";

/**
 * Admin session against the Python Workers API (BFF — mirrors
 * apps/admin_app's /api/auth/otp routes 1:1: same endpoint calls, same
 * HttpOnly cookie names/flags, same admin-role gate). The access token
 * never reaches browser code.
 */

export const SESSION_COOKIE = "sh_session";
export const REFRESH_COOKIE = "sh_refresh";

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
    let res: Response;
    try {
      res = await callWorkerPublic("/v1/auth/otp/start", { phone: data.phone });
    } catch (e) {
      // Worker unreachable from the admin isolate (DNS/edge/timeout) —
      // previously invisible: no log line and the form showed a bare string.
      console.error(`[admin-auth] otp/start fetch failed: ${e instanceof Error ? e.message : e}`);
      throw new Error("API worker unreachable. Check API_URL and worker status.");
    }
    const body = (await res.json().catch(() => ({}))) as {
      sent_to_masked?: string;
      resend_after_s?: number;
      error?: { code: string; message: string };
    };
    if (!res.ok) {
      const code = body.error?.code ?? "SERVER";
      // No phone number in logs — path + status + worker code triages it.
      // The worker's own message (e.g. rate-limit) is passed through so the
      // UI can show — and copy — the real reason.
      console.error(`[admin-auth] otp/start failed: POST /v1/auth/otp/start → ${res.status} ${code}`);
      throw new Error(body.error?.message ?? `Could not send the code (${res.status} ${code}).`);
    }
    return { sent_to_masked: body.sent_to_masked, resend_after_s: body.resend_after_s };
  });

export const loginVerifyServer = createServerFn({ method: "POST" })
  .validator((input: { id_token: string }) => input)
  .handler(async ({ data }): Promise<LoginVerifyResult> => {
    let res: Response;
    try {
      res = await callWorkerPublic("/v1/auth/otp/verify", {
        firebase_id_token: data.id_token,
        device: { id: "admin-web" },
      });
    } catch (e) {
      console.error(`[admin-auth] otp/verify fetch failed: ${e instanceof Error ? e.message : e}`);
      return { ok: false, status: 0, code: "NETWORK", message: "API worker unreachable. Check API_URL and worker status." };
    }
    const body = (await res.json().catch(() => ({}))) as {
      access_token?: string;
      refresh_token?: string;
      role?: string;
      error?: { code: string; message: string };
    };
    if (!res.ok) {
      const code = body.error?.code ?? "UNAUTH";
      // Never log tokens — status + worker code is the triage signal.
      // A non-envelope error (wrong API_URL path, proxy HTML) lands here
      // with the HTTP status appended instead of a bare "failed".
      console.error(`[admin-auth] otp/verify failed: POST /v1/auth/otp/verify → ${res.status} ${code}`);
      return {
        ok: false,
        status: res.status,
        code,
        message: body.error?.message ?? `Verification failed (${res.status} ${code}). Check API_URL in Cloudflare.`,
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

/**
 * Temporary access-code login (doorstep unblock while phone OTP is down).
 * Calls the worker's config-gated demo door (demo_codes hash + flag), mints
 * a normal role-checked session, and sets the same cookies. Revoke by
 * deleting the demo_codes row or flipping the flag — see runbook in chat.
 */
export const loginDemoServer = createServerFn({ method: "POST" })
  .validator((input: { phone: string; code: string }) => input)
  .handler(async ({ data }): Promise<LoginVerifyResult> => {
    let res: Response;
    try {
      res = await callWorkerPublic("/v1/auth/demo", {
        phone: data.phone,
        demo_code: data.code,
        device: { id: "admin-web" },
      });
    } catch (e) {
      console.error(`[admin-auth] demo fetch failed: ${e instanceof Error ? e.message : e}`);
      return { ok: false, status: 0, code: "NETWORK", message: "API worker unreachable. Check API_URL and worker status." };
    }
    const rawText = await res.text().catch(() => "");
    let body: {
      access_token?: string;
      refresh_token?: string;
      role?: string;
      error?: { code: string; message: string };
    } = {};
    try {
      body = JSON.parse(rawText) as typeof body;
    } catch {
      // Non-JSON error page (edge HTML, proxy text) — snippet it for the tail.
      console.error(`[admin-auth] demo non-JSON error body: ${rawText.slice(0, 200)}`);
    }
    if (!res.ok) {
      const code = body.error?.code ?? "UNAUTH";
      console.error(`[admin-auth] demo failed: POST /v1/auth/demo → ${res.status} ${code}`);
      return {
        ok: false,
        status: res.status,
        code,
        message: body.error?.message ?? `Access code not accepted (${res.status}).`,
      };
    }
    if (body.role !== "admin") {
      return { ok: false, status: 403, code: "FORBIDDEN", message: "This number is not an admin." };
    }
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
      device: { id: "admin-web" },
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
