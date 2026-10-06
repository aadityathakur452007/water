import { type UseQueryOptions, useQuery, useQueryClient } from "@tanstack/react-query";

import { toast } from "@/components/ui/toast";
import { AdminApiError, adminGetServer } from "@/server/admin-api";

export type ApiQueryKey = readonly ["admin", string];

/**
 * Client-side read hook: browser → adminGetServer (server function) → Workers.
 * Mock/live differ only inside the server function — the hook is identical.
 */
export function useAdminQuery<T>(path: string, options?: Partial<UseQueryOptions<T, AdminApiError, T, ApiQueryKey>>) {
  return useQuery<T, AdminApiError, T, ApiQueryKey>({
    queryKey: ["admin", path],
    queryFn: async () => {
      try {
        return (await adminGetServer({ data: { path } })) as T;
      } catch (err) {
        if (err instanceof AdminApiError) throw err;
        throw new AdminApiError(0, "NETWORK", "Workers API unreachable");
      }
    },
    staleTime: 15_000,
    retry: 1,
    ...options,
  });
}

/** Invalidates every admin query under a path prefix (e.g. after a mutation). */
export function useInvalidateAdmin() {
  const qc = useQueryClient();
  return (pathPrefix: string) => {
    for (const q of qc.getQueryCache().getAll()) {
      const key = q.queryKey as ApiQueryKey;
      if (key[0] === "admin" && key[1].startsWith(pathPrefix)) {
        void qc.invalidateQueries({ queryKey: key });
      }
    }
  };
}

export function errorMessage(err: unknown): string {
  // Phase 6 S6.4: rate-limit and offline get their own lines (server text
  // covers the rest — never raw status numbers in copy).
  if (err instanceof AdminApiError) {
    if (err.code === "NETWORK" || err.status === 0) return "Network unavailable — check connection and retry.";
    if (err.status === 429) return "Too many tries — wait a moment and retry.";
    return err.message;
  }
  if (err instanceof Error) return err.message;
  return "Something went wrong.";
}

export { toast };
