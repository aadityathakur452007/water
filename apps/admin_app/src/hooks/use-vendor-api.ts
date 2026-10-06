import { type UseQueryOptions, useQuery, useQueryClient } from "@tanstack/react-query";

import { toast } from "@/components/ui/toast";
import { VendorApiError, vendorGetServer } from "@/server/vendor-api";

export type VendorQueryKey = readonly ["vendor", string];

/**
 * Client-side vendor read hook: browser → vendorGetServer → Workers.
 * Mirrors useAdminQuery (15s stale, single retry) under its own cache key
 * so vendor and admin data never share entries.
 */
export function useVendorQuery<T>(
  path: string,
  options?: Partial<UseQueryOptions<T, VendorApiError, T, VendorQueryKey>>,
) {
  return useQuery<T, VendorApiError, T, VendorQueryKey>({
    queryKey: ["vendor", path],
    queryFn: async () => {
      try {
        return (await vendorGetServer({ data: { path } })) as T;
      } catch (err) {
        if (err instanceof VendorApiError) throw err;
        throw new VendorApiError(0, "NETWORK", "Workers API unreachable");
      }
    },
    staleTime: 15_000,
    retry: 1,
    ...options,
  });
}

/** Invalidates every vendor query under a path prefix (e.g. after a mutation). */
export function useInvalidateVendor() {
  const qc = useQueryClient();
  return (pathPrefix: string) => {
    for (const q of qc.getQueryCache().getAll()) {
      const key = q.queryKey as VendorQueryKey;
      if (key[0] === "vendor" && key[1].startsWith(pathPrefix)) {
        void qc.invalidateQueries({ queryKey: key });
      }
    }
  };
}

export function vendorErrorMessage(err: unknown): string {
  // Phase 6 S6.4: same rate-limit/offline lines as the admin hook.
  if (err instanceof VendorApiError) {
    if (err.code === "NETWORK" || err.status === 0) return "Network unavailable — check connection and retry.";
    if (err.status === 429) return "Too many tries — wait a moment and retry.";
    return err.message;
  }
  if (err instanceof Error) return err.message;
  return "Something went wrong.";
}

export { toast };
