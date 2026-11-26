import { createServerFn } from "@tanstack/react-start";

import type { RoleLoginResult } from "./worker-errors";

export const ADMIN_SESSION_COOKIE = "sh_admin_session";
export const ADMIN_REFRESH_COOKIE = "sh_admin_refresh";
export const SESSION_COOKIE = ADMIN_SESSION_COOKIE;
export const REFRESH_COOKIE = ADMIN_REFRESH_COOKIE;
export const ADMIN_WEB_DEVICE = "admin-web";

export type LoginVerifyResult = RoleLoginResult;

let activeRefresh: Promise<{ access: string; refresh: string } | null> | null = null;

export const loginCodeServer = createServerFn({ method: "POST" })
  .validator((input: { phone: string; code: string }) => input)
  .handler(async ({ data }): Promise<LoginVerifyResult> => {
    const [sc, wc] = await Promise.all([import("./session-core.server"), import("./worker-client.server")]);
    return sc.loginWithAccessCode({
      endpoint: "/v1/auth/admin/login",
      expectedRole: "admin",
      deviceId: ADMIN_WEB_DEVICE,
      phone: data.phone,
      code: data.code,
      sessionCookie: ADMIN_SESSION_COOKIE,
      refreshCookie: ADMIN_REFRESH_COOKIE,
      logTag: "admin-auth",
      callPublic: (p, b) => wc.callPublicEndpoint(p, b, undefined, "WATER_API", wc.apiUrl(), "admin-api"),
    });
  });

export const refreshSessionServer = createServerFn({ method: "POST" }).handler(
  async (): Promise<{ access: string; refresh: string } | null> => {
    if (activeRefresh !== null) return activeRefresh;
    const [sc, wc] = await Promise.all([import("./session-core.server"), import("./worker-client.server")]);
    const run = sc.createDeduplicatedRefresher({
      refreshCookieNames: [ADMIN_REFRESH_COOKIE, "sh_refresh"],
      sessionCookie: ADMIN_SESSION_COOKIE,
      refreshCookie: ADMIN_REFRESH_COOKIE,
      deviceId: ADMIN_WEB_DEVICE,
      logTag: "admin-auth",
      callPublic: (p, b) => wc.callPublicEndpoint(p, b, undefined, "WATER_API", wc.apiUrl(), "admin-api"),
    });
    activeRefresh = run().finally(() => {
      activeRefresh = null;
    });
    return activeRefresh;
  },
);

export const storeRotatedSessionServer = createServerFn({ method: "POST" })
  .validator((input: { access: string; refresh: string }) => input)
  .handler(async ({ data }) => {
    const sc = await import("./session-core.server");
    sc.setSessionCookies(ADMIN_SESSION_COOKIE, ADMIN_REFRESH_COOKIE, data.access, data.refresh);
  });

export const logoutServer = createServerFn({ method: "POST" }).handler(async () => {
  const [{ getCookie, setCookie }, sc, wc] = await Promise.all([
    import("@tanstack/react-start/server"),
    import("./session-core.server"),
    import("./worker-client.server"),
  ]);
  const access = getCookie(ADMIN_SESSION_COOKIE) ?? getCookie("sh_session");
  if (access) {
    await wc
      .callPublicEndpoint(
        "/v1/auth/logout",
        {},
        { authorization: `Bearer ${access}` },
        "WATER_API",
        wc.apiUrl(),
        "admin-api",
      )
      .catch(() => undefined);
  }
  setCookie(ADMIN_SESSION_COOKIE, "", { ...sc.COOKIE_FLAGS, maxAge: 0 });
  setCookie(ADMIN_REFRESH_COOKIE, "", { ...sc.COOKIE_FLAGS, maxAge: 0 });
  setCookie("sh_session", "", { ...sc.COOKIE_FLAGS, maxAge: 0 });
  setCookie("sh_refresh", "", { ...sc.COOKIE_FLAGS, maxAge: 0 });
});

export const hasSessionServer = createServerFn({ method: "GET" }).handler(async (): Promise<{ authed: boolean }> => {
  const { getCookie } = await import("@tanstack/react-start/server");
  return { authed: Boolean(getCookie(ADMIN_SESSION_COOKIE) ?? getCookie("sh_session")) };
});
