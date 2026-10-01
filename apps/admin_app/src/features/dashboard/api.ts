"use client";

import { useQuery } from "@tanstack/react-query";
import type { Overview, Page, OrderRow, AuditRow, Reconciliation, CustodyRow, DunningRow } from "@/lib/types";

async function proxyGet<T>(path: string): Promise<T> {
  const res = await fetch(`/api/proxy?url=${encodeURIComponent(path)}`);
  if (!res.ok) {
    const body = (await res.json().catch(() => ({}))) as { error?: { message?: string } };
    throw new Error(body.error?.message ?? `Request failed (${res.status})`);
  }
  return (await res.json()) as T;
}

export function useOverview(days = 14) {
  return useQuery({
    queryKey: ["overview", days],
    queryFn: () => proxyGet<Overview>(`/v1/admin/metrics/overview?days=${days}`),
    refetchInterval: 60_000,
  });
}

export function useOrders(params: { state?: string; payment_status?: string; query?: string; cursor?: string; limit?: number }) {
  const search = new URLSearchParams();
  if (params.state) search.set("state", params.state);
  if (params.payment_status) search.set("payment_status", params.payment_status);
  if (params.query) search.set("query", params.query);
  if (params.cursor) search.set("cursor", params.cursor);
  search.set("limit", String(params.limit ?? 50));
  return useQuery({
    queryKey: ["orders", params],
    queryFn: () => proxyGet<Page<OrderRow>>(`/v1/admin/orders?${search.toString()}`),
  });
}

export function useAudit(params: { entity?: string; actor_id?: string; action?: string; limit?: number }) {
  const search = new URLSearchParams();
  if (params.entity) search.set("entity", params.entity);
  if (params.actor_id) search.set("actor_id", params.actor_id);
  if (params.action) search.set("action", params.action);
  search.set("limit", String(params.limit ?? 100));
  return useQuery({
    queryKey: ["audit", params],
    queryFn: () => proxyGet<Page<AuditRow>>(`/v1/admin/audit?${search.toString()}`),
  });
}

export function useReconciliation(route?: string, date?: string) {
  const search = new URLSearchParams();
  if (route) search.set("route", route);
  if (date) search.set("date", date);
  return useQuery({
    queryKey: ["reconciliation", route, date],
    queryFn: () => proxyGet<Reconciliation>(`/v1/admin/reconciliation?${search.toString()}`),
  });
}

export function useCustody() {
  return useQuery({
    queryKey: ["custody"],
    queryFn: () => proxyGet<Page<CustodyRow>>("/v1/admin/custody"),
  });
}

export function useDunning() {
  return useQuery({
    queryKey: ["dunning"],
    queryFn: () => proxyGet<Page<DunningRow>>("/v1/admin/dunning"),
  });
}

export { proxyGet };
