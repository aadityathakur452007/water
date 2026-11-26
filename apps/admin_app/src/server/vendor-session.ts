import { createServerFn } from "@tanstack/react-start";

import type { RoleLoginResult } from "./worker-errors";

export const VENDOR_SESSION_COOKIE = "sh_vendor_session";
export const VENDOR_REFRESH_COOKIE = "sh_vendor_refresh";
export const VENDOR_WEB_DEVICE = "vendor-web";

export type VendorLoginResult = RoleLoginResult;

let activeVendorRefresh: Promise<{ access: string; refresh: string } | null> | null = null;

export const loginVendorVerifyServer = createServerFn({ method: "POST" })
  .validator((input: { phone: string; code: string }) => input)
  .handler(async ({ data }): Promise<VendorLoginResult> => {
    const [sc, wc] = await Promise.all([import("./session-core.server"), import("./worker-client.server")]);
    return sc.loginWithAccessCode({
      endpoint: "/v1/auth/vendor/login",
      expectedRole: "vendor",
      deviceId: VENDOR_WEB_DEVICE,
      phone: data.phone,
      code: data.code,
      sessionCookie: VENDOR_SESSION_COOKIE,
      refreshCookie: VENDOR_REFRESH_COOKIE,
      logTag: "vendor-auth",
      callPublic: (p, b) => wc.callPublicEndpoint(p, b, undefined, "OPS_API", wc.opsApiUrl(), "vendor-api"),
    });
  });

export const hasVendorSessionServer = createServerFn({ method: "GET" }).handler(
  async (): Promise<{ authed: boolean }> => {
    const { getCookie } = await import("@tanstack/react-start/server");
    return { authed: Boolean(getCookie(VENDOR_SESSION_COOKIE) ?? getCookie("sh_session")) };
  },
);

export const refreshVendorSessionServer = createServerFn({ method: "POST" }).handler(
  async (): Promise<{ access: string; refresh: string } | null> => {
    if (activeVendorRefresh !== null) return activeVendorRefresh;
    const [sc, wc] = await Promise.all([import("./session-core.server"), import("./worker-client.server")]);
    const run = sc.createDeduplicatedRefresher({
      refreshCookieNames: [VENDOR_REFRESH_COOKIE, "sh_refresh"],
      sessionCookie: VENDOR_SESSION_COOKIE,
      refreshCookie: VENDOR_REFRESH_COOKIE,
      deviceId: VENDOR_WEB_DEVICE,
      logTag: "vendor-auth",
      callPublic: (p, b) => wc.callPublicEndpoint(p, b, undefined, "OPS_API", wc.opsApiUrl(), "vendor-api"),
    });
    activeVendorRefresh = run().finally(() => {
      activeVendorRefresh = null;
    });
    return activeVendorRefresh;
  },
);

export const logoutVendorServer = createServerFn({ method: "POST" }).handler(async () => {
  const [{ getCookie, setCookie }, sc, wc] = await Promise.all([
    import("@tanstack/react-start/server"),
    import("./session-core.server"),
    import("./worker-client.server"),
  ]);
  const access = getCookie(VENDOR_SESSION_COOKIE) ?? getCookie("sh_session");
  if (access) {
    await wc
      .callPublicEndpoint(
        "/v1/auth/logout",
        {},
        { authorization: `Bearer ${access}` },
        "OPS_API",
        wc.opsApiUrl(),
        "vendor-api",
      )
      .catch(() => undefined);
  }
  setCookie(VENDOR_SESSION_COOKIE, "", { ...sc.COOKIE_FLAGS, maxAge: 0 });
  setCookie(VENDOR_REFRESH_COOKIE, "", { ...sc.COOKIE_FLAGS, maxAge: 0 });
  setCookie("sh_session", "", { ...sc.COOKIE_FLAGS, maxAge: 0 });
  setCookie("sh_refresh", "", { ...sc.COOKIE_FLAGS, maxAge: 0 });
});
