import { createServerFn } from "@tanstack/react-start";

import { refreshVendorSessionServer } from "./vendor-session";
import { WorkerApiError, type WorkerEnvelope } from "./worker-errors";

export class VendorApiError extends WorkerApiError {}

export type VendorEnvelope = WorkerEnvelope;

const VENDOR_COOKIES = ["sh_vendor_session", "sh_session"];

export const vendorGetServer = createServerFn({ method: "GET" })
  .validator((input: { path: string }) => input)
  .handler(async ({ data }): Promise<VendorEnvelope> => {
    const { path } = data;
    if (!path.startsWith("/v1/vendor/")) {
      throw new VendorApiError(400, "VALIDATION", "path must be a vendor /v1 path");
    }
    const wc = await import("./worker-client.server");
    if (wc.apiMode() === "mock") {
      const { resolveFixture } = await import("#/data/admin/mock-resolver");
      return resolveFixture(path, "GET") as unknown as VendorEnvelope;
    }
    return wc.fetchEnvelopeWithRefresh({
      path,
      method: "GET",
      bindingName: "OPS_API",
      baseUrl: wc.opsApiUrl(),
      cookieNames: VENDOR_COOKIES,
      logTag: "vendor-api",
      refresh: () => refreshVendorSessionServer(),
      makeError: (s, c, m, t) => new VendorApiError(s, c, m, t),
    });
  });

function vendorWriteAllowed(path: string): boolean {
  if (
    path.startsWith("/v1/vendor/stops/") &&
    (path.endsWith("/triple") || path.endsWith("/pod") || path.endsWith("/cash"))
  ) {
    return true;
  }
  if (path.startsWith("/v1/vendor/placed/") && path.endsWith("/accept")) {
    return true;
  }
  if (path === "/v1/vendor/sync" || path === "/v1/vendor/duty") return true;
  if (path.startsWith("/v1/complaints/") && path.endsWith("/verify")) return true;
  if (path.startsWith("/v1/quality/") && path.endsWith("/vendor-check")) return true;
  if (path === "/v1/vendor/profile" || path === "/v1/vendor/slots") return true;
  return false;
}

export const vendorPostServer = createServerFn({ method: "POST" })
  .validator(
    (input: { path: string; body?: unknown; method?: "POST" | "PATCH" | "PUT"; idempotencyKey?: string }) => input,
  )
  .handler(async ({ data }): Promise<VendorEnvelope> => {
    const { path, body, method = "POST", idempotencyKey } = data;
    if (!vendorWriteAllowed(path)) {
      throw new VendorApiError(400, "VALIDATION", "path is not a vendor-writable /v1 path");
    }
    const wc = await import("./worker-client.server");
    if (wc.apiMode() === "mock") {
      const { resolveFixture } = await import("#/data/admin/mock-resolver");
      return resolveFixture(path, method === "PUT" ? "POST" : method, body) as unknown as VendorEnvelope;
    }
    return wc.fetchEnvelopeWithRefresh({
      path,
      method,
      body,
      extraHeaders: idempotencyKey ? { "Idempotency-Key": idempotencyKey } : undefined,
      bindingName: "OPS_API",
      baseUrl: wc.opsApiUrl(),
      cookieNames: VENDOR_COOKIES,
      logTag: "vendor-api",
      refresh: () => refreshVendorSessionServer(),
      makeError: (s, c, m, t) => new VendorApiError(s, c, m, t),
    });
  });
