import { getCookie, setCookie } from "@tanstack/react-start/server";

const isDevHttp = process.env.NODE_ENV === "development" && !process.env.COOKIE_SECURE;

export const COOKIE_FLAGS = {
  path: "/",
  sameSite: "lax" as const,
  secure: !isDevHttp,
  httpOnly: true,
};

export const ACCESS_COOKIE_MAX_AGE = 60 * 60 * 24;
export const REFRESH_COOKIE_MAX_AGE = 60 * 60 * 24 * 30;

export type RoleLoginResult = { ok: true; role: string } | { ok: false; status: number; code: string; message: string };

export function normalizeOrigin(rawValue: string): string {
  return rawValue.trim().replace(/\/+$/, "").replace(/\/v1$/, "");
}

export function setSessionCookies(sessionCookie: string, refreshCookie: string, access: string, refresh: string): void {
  setCookie(sessionCookie, access, { ...COOKIE_FLAGS, maxAge: ACCESS_COOKIE_MAX_AGE });
  setCookie(refreshCookie, refresh, { ...COOKIE_FLAGS, maxAge: REFRESH_COOKIE_MAX_AGE });
}

export async function loginWithAccessCode(opts: {
  endpoint: string;
  expectedRole: "admin" | "vendor";
  deviceId: string;
  phone: string;
  code: string;
  sessionCookie: string;
  refreshCookie: string;
  logTag: string;
  callPublic: (path: string, body: unknown) => Promise<Response>;
}): Promise<RoleLoginResult> {
  let res: Response;
  try {
    res = await opts.callPublic(opts.endpoint, {
      phone: opts.phone,
      code: opts.code,
      device: { id: opts.deviceId },
    });
  } catch (e) {
    console.error(`[${opts.logTag}] login fetch failed: ${e instanceof Error ? e.message : e}`);
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
    error?: { code?: string; message?: string };
  };
  if (!res.ok) {
    const code = body.error?.code ?? "UNAUTH";
    console.error(`[${opts.logTag}] login failed: POST ${opts.endpoint} → ${res.status} ${code}`);
    return {
      ok: false,
      status: res.status,
      code,
      message: body.error?.message ?? "Invalid phone or code.",
    };
  }
  if (body.role !== opts.expectedRole) {
    return {
      ok: false,
      status: 403,
      code: "FORBIDDEN",
      message: `This number is not a ${opts.expectedRole}.`,
    };
  }
  setSessionCookies(opts.sessionCookie, opts.refreshCookie, body.access_token ?? "", body.refresh_token ?? "");
  return { ok: true, role: body.role };
}

export function createDeduplicatedRefresher(opts: {
  refreshCookieNames: string[];
  sessionCookie: string;
  refreshCookie: string;
  deviceId: string;
  logTag: string;
  callPublic: (path: string, body: unknown) => Promise<Response>;
}): () => Promise<{ access: string; refresh: string } | null> {
  let inflight: Promise<{ access: string; refresh: string } | null> | null = null;

  return () => {
    if (inflight !== null) return inflight;
    const refresh_token = opts.refreshCookieNames.map((n) => getCookie(n)).find(Boolean);
    if (!refresh_token) return Promise.resolve(null);

    inflight = (async () => {
      try {
        const res = await opts.callPublic("/v1/auth/refresh", {
          refresh_token,
          device: { id: opts.deviceId },
        });
        if (!res.ok) return null;
        const data = (await res.json().catch(() => null)) as {
          access_token?: string;
          refresh_token?: string;
        } | null;
        if (!data?.access_token || !data?.refresh_token) return null;

        setSessionCookies(opts.sessionCookie, opts.refreshCookie, data.access_token, data.refresh_token);
        return { access: data.access_token, refresh: data.refresh_token };
      } catch (err) {
        console.error(`[${opts.logTag}] silent refresh failed:`, err);
        return null;
      } finally {
        inflight = null;
      }
    })();

    return inflight;
  };
}
