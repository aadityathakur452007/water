import { createServerFn } from "@tanstack/react-start";

import { refreshSessionServer, storeRotatedSessionServer } from "./admin-session";
import { WorkerApiError, type WorkerEnvelope } from "./worker-errors";

export class AdminApiError extends WorkerApiError {}

export type AdminEnvelope = WorkerEnvelope;

const ADMIN_PREFIX = "/v1/admin";
const ADMIN_COOKIES = ["sh_admin_session", "sh_session"];

export const adminRoleServer = createServerFn({ method: "GET" }).handler(async (): Promise<{ role: string } | null> => {
  const wc = await import("./worker-client.server");
  if (wc.apiMode() === "mock") return { role: "admin" };
  let res = await wc.executeAuthedFetch({
    path: "/v1/auth/me",
    method: "GET",
    bindingName: "WATER_API",
    baseUrl: wc.apiUrl(),
    cookieNames: ADMIN_COOKIES,
    logTag: "admin-api",
    retry5xx: true,
  });
  if (res.status === 401) {
    const pair = await refreshSessionServer();
    if (pair) {
      await storeRotatedSessionServer({ data: pair });
      res = await wc.executeAuthedFetch({
        path: "/v1/auth/me",
        method: "GET",
        bindingName: "WATER_API",
        baseUrl: wc.apiUrl(),
        cookieNames: ADMIN_COOKIES,
        logTag: "admin-api",
        retry5xx: true,
      });
    }
  }
  if (!res.ok) return null;
  const body = (await res.json().catch(() => null)) as { user?: { role?: unknown } } | null;
  const role = body?.user?.role;
  return typeof role === "string" ? { role } : null;
});

export type CurrentAdminUser = {
  id: string;
  phone: string;
  name: string;
  role: string;
  avatar?: string;
};

export const adminMeServer = createServerFn({ method: "GET" }).handler(async (): Promise<CurrentAdminUser | null> => {
  const wc = await import("./worker-client.server");
  if (wc.apiMode() === "mock") {
    return { id: "admin-root", phone: "+917828442476", name: "Admin", role: "admin" };
  }
  let res = await wc.executeAuthedFetch({
    path: "/v1/auth/me",
    method: "GET",
    bindingName: "WATER_API",
    baseUrl: wc.apiUrl(),
    cookieNames: ADMIN_COOKIES,
    logTag: "admin-api",
    retry5xx: true,
  });
  if (res.status === 401) {
    const pair = await refreshSessionServer();
    if (pair) {
      await storeRotatedSessionServer({ data: pair });
      res = await wc.executeAuthedFetch({
        path: "/v1/auth/me",
        method: "GET",
        bindingName: "WATER_API",
        baseUrl: wc.apiUrl(),
        cookieNames: ADMIN_COOKIES,
        logTag: "admin-api",
        retry5xx: true,
      });
    }
  }
  if (!res.ok) return null;
  const body = (await res.json().catch(() => null)) as {
    user?: { id?: string; phone?: string; name?: string; role?: string };
  } | null;
  if (!body?.user?.id) return null;
  return {
    id: body.user.id,
    phone: body.user.phone ?? "",
    name: body.user.name ?? "Admin",
    role: body.user.role ?? "admin",
  };
});

export const adminExportCsvServer = createServerFn({ method: "GET" })
  .validator((input: { query: string }) => input)
  .handler(async ({ data }): Promise<string> => {
    const wc = await import("./worker-client.server");
    if (wc.apiMode() === "mock") {
      const { auditFixture } = await import("#/data/admin/fixtures");
      const rows = auditFixture.data as Array<Record<string, unknown>>;
      const keys = Object.keys(rows[0] ?? { id: "" });
      const esc = (v: unknown) => {
        const s = String(v ?? "");
        return /[",\n]/.test(s) ? `"${s.replaceAll('"', '""')}"` : s;
      };
      return [keys.join(","), ...rows.map((r) => keys.map((k) => esc(r[k])).join(","))].join("\n");
    }
    const res = await wc.executeAuthedFetch({
      path: `/v1/admin/audit/export${data.query}`,
      method: "GET",
      bindingName: "WATER_API",
      baseUrl: wc.apiUrl(),
      cookieNames: ADMIN_COOKIES,
      logTag: "admin-api",
      retry5xx: true,
    });
    if (res.status === 401) {
      const pair = await refreshSessionServer();
      if (pair) {
        await storeRotatedSessionServer({ data: pair });
        const retry = await wc.executeAuthedFetch({
          path: `/v1/admin/audit/export${data.query}`,
          method: "GET",
          bindingName: "WATER_API",
          baseUrl: wc.apiUrl(),
          cookieNames: ADMIN_COOKIES,
          logTag: "admin-api",
          retry5xx: true,
        });
        if (retry.ok) return retry.text().catch(() => "");
      }
      throw new AdminApiError(401, "UNAUTH", "Session expired — sign in again.");
    }
    if (!res.ok) {
      throw new AdminApiError(res.status, "SERVER", `Export failed (${res.status}).`);
    }
    return res.text().catch(() => "");
  });

async function runAdminRequest(path: string, method: "GET" | "POST" | "PATCH", body?: unknown): Promise<AdminEnvelope> {
  const wc = await import("./worker-client.server");
  if (wc.apiMode() === "mock") {
    const { resolveFixture } = await import("#/data/admin/mock-resolver");
    return resolveFixture(path, method, body) as unknown as AdminEnvelope;
  }
  return wc.fetchEnvelopeWithRefresh({
    path,
    method,
    body,
    bindingName: "WATER_API",
    baseUrl: wc.apiUrl(),
    cookieNames: ADMIN_COOKIES,
    logTag: "admin-api",
    retry5xx: true,
    refresh: () => refreshSessionServer(),
    storeRotated: (pair) => storeRotatedSessionServer({ data: pair }),
    makeError: (s, c, m, t) => new AdminApiError(s, c, m, t),
  });
}

export const adminGetServer = createServerFn({ method: "GET" })
  .validator((input: { path: string }) => input)
  .handler(async ({ data }): Promise<AdminEnvelope> => {
    if (!data.path.startsWith(ADMIN_PREFIX)) {
      throw new AdminApiError(400, "VALIDATION", "path must be an admin /v1 path");
    }
    return runAdminRequest(data.path, "GET");
  });

export const adminPostServer = createServerFn({ method: "POST" })
  .validator((input: { path: string; body?: unknown }) => input)
  .handler(async ({ data }): Promise<AdminEnvelope> => {
    if (!data.path.startsWith(ADMIN_PREFIX) && !data.path.startsWith("/v1/refunds/")) {
      throw new AdminApiError(400, "VALIDATION", "path must be an admin /v1 path");
    }
    return runAdminRequest(data.path, "POST", data.body);
  });

export const adminPatchServer = createServerFn({ method: "POST" })
  .validator((input: { path: string; body?: unknown }) => input)
  .handler(async ({ data }): Promise<AdminEnvelope> => {
    if (!data.path.startsWith(ADMIN_PREFIX)) {
      throw new AdminApiError(400, "VALIDATION", "path must be an admin /v1 path");
    }
    return runAdminRequest(data.path, "PATCH", data.body);
  });
