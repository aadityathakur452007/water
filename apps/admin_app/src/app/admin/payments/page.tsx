"use client";

import { useState } from "react";
import Link from "next/link";
import { ChevronLeft, ChevronRight, Wallet } from "lucide-react";
import { Badge, Card, EmptyState, ErrorState, PageHeader, SkeletonRows } from "@/shared/ui/primitives";
import { proxyGet } from "@/features/dashboard/api";
import { useQuery } from "@tanstack/react-query";
import { dateTime, num, paise, phoneMasked } from "@/lib/format";
import type { Page, PaymentRow, RefundRow } from "@/lib/types";

const PAY_FILTERS = ["", "paid", "link_sent", "partial", "failed"];
const REFUND_FILTERS = ["", "pending", "claimed", "done", "failed"];

export default function PaymentsPage() {
  const [tab, setTab] = useState<"payments" | "refunds">("payments");
  const [status, setStatus] = useState("");
  const [cursor, setCursor] = useState("");

  const search = new URLSearchParams();
  if (status) search.set("status", status);
  if (cursor) search.set("cursor", cursor);
  search.set("limit", "50");

  const paymentsQ = useQuery({
    queryKey: ["payments", status, cursor],
    queryFn: () => proxyGet<Page<PaymentRow>>(`/v1/admin/payments?${search.toString()}`),
    enabled: tab === "payments",
  });
  const refundsQ = useQuery({
    queryKey: ["refunds", status, cursor],
    queryFn: () => proxyGet<Page<RefundRow>>(`/v1/admin/refunds?${search.toString()}`),
    enabled: tab === "refunds",
  });

  const active = tab === "payments" ? paymentsQ : refundsQ;
  const rows = (active.data?.data ?? []) as Array<PaymentRow | RefundRow>;

  return (
    <div className="space-y-5">
      <PageHeader
        title="Payments"
        description="Every paisa in (collections) and out (refunds) — with rider and customer attribution."
      />

      <div className="flex flex-wrap items-center gap-2">
        <div className="flex rounded-lg border border-line bg-surface p-0.5">
          {(["payments", "refunds"] as const).map((t) => (
            <button
              key={t}
              type="button"
              onClick={() => {
                setTab(t);
                setStatus("");
                setCursor("");
              }}
              className={`h-8 rounded-md px-3.5 text-xs font-medium capitalize transition-colors ${
                tab === t ? "bg-accent-soft text-accent" : "text-steel hover:text-ink"
              }`}
            >
              {t}
            </button>
          ))}
        </div>
        <select
          value={status}
          onChange={(e) => {
            setStatus(e.target.value);
            setCursor("");
          }}
          aria-label="Filter by status"
          className="h-9 rounded-lg border border-line bg-surface px-2.5 text-sm text-ink"
        >
          {(tab === "payments" ? PAY_FILTERS : REFUND_FILTERS).map((s) => (
            <option key={s} value={s}>{s || "All statuses"}</option>
          ))}
        </select>
        {active.isFetching ? <span className="text-xs text-faint">syncing…</span> : null}
      </div>

      <Card>
        {active.isError ? (
          <div className="p-4">
            <ErrorState message={(active.error as Error).message} />
          </div>
        ) : active.isLoading ? (
          <SkeletonRows rows={8} cols={6} />
        ) : rows.length === 0 ? (
          <EmptyState
            icon={<Wallet className="size-5" />}
            title="Nothing here yet"
            hint={
              tab === "payments"
                ? "Collections appear the moment a UPI intent is created or a COD stop is logged."
                : "Refund rows are created by cancellations after money has moved — never by hand."
            }
          />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-line text-left text-[11px] uppercase tracking-wide text-faint">
                  <th className="px-5 py-2.5 font-medium">Id</th>
                  <th className="px-3 py-2.5 font-medium">Customer</th>
                  <th className="px-3 py-2.5 font-medium">Order</th>
                  {tab === "payments" ? <th className="px-3 py-2.5 font-medium">Method</th> : null}
                  <th className="px-3 py-2.5 font-medium">Amount</th>
                  <th className="px-3 py-2.5 font-medium">Status</th>
                  <th className="px-5 py-2.5 font-medium">When</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-line-soft">
                {tab === "payments"
                  ? (rows as PaymentRow[]).map((p) => (
                      <tr key={p.id} className="transition-colors hover:bg-canvas">
                        <td className="tnum px-5 py-3 text-steel">{p.id.slice(0, 10)}</td>
                        <td className="px-3 py-3 text-ink">
                          {p.user_name ?? "—"}
                          <span className="tnum block text-xs text-faint">{phoneMasked(p.user_phone)}</span>
                        </td>
                        <td className="tnum px-3 py-3">
                          <Link href={`/admin/orders/${p.order_id}`} className="text-accent hover:underline">
                            {p.order_id.slice(0, 10)}
                          </Link>
                        </td>
                        <td className="px-3 py-3">
                          <Badge tone={p.method === "upi" ? "accent" : "neutral"}>{p.method}</Badge>
                        </td>
                        <td className="tnum px-3 py-3 font-medium text-ink">{paise(p.amount)}</td>
                        <td className="px-3 py-3">
                          <Badge tone={p.status === "paid" ? "good" : p.status === "failed" ? "bad" : "warn"}>
                            {p.status}
                          </Badge>
                        </td>
                        <td className="px-5 py-3 text-xs text-steel">{dateTime(p.verified_at ?? p.created_at)}</td>
                      </tr>
                    ))
                  : (rows as RefundRow[]).map((r) => (
                      <tr key={r.id} className="transition-colors hover:bg-canvas">
                        <td className="tnum px-5 py-3 text-steel">{r.id.slice(0, 10)}</td>
                        <td className="px-3 py-3 text-ink">
                          {r.user_name ?? "—"}
                          <span className="tnum block text-xs text-faint">{phoneMasked(r.user_phone)}</span>
                        </td>
                        <td className="tnum px-3 py-3">
                          <Link href={`/admin/orders/${r.order_id}`} className="text-accent hover:underline">
                            {r.order_id.slice(0, 10)}
                          </Link>
                        </td>
                        <td className="tnum px-3 py-3 font-medium text-ink">{paise(r.amount)}</td>
                        <td className="px-3 py-3">
                          <Badge tone={r.status === "done" ? "good" : r.status === "failed" ? "bad" : "warn"}>
                            {r.status}
                          </Badge>
                        </td>
                        <td className="px-5 py-3 text-xs text-steel">{dateTime(r.done_at ?? r.created_at)}</td>
                      </tr>
                    ))}
              </tbody>
            </table>
          </div>
        )}
        {(active.data?.next_cursor || cursor) && rows.length > 0 ? (
          <div className="flex items-center justify-between border-t border-line-soft px-5 py-3">
            <span className="text-xs text-faint">{num(rows.length)} shown</span>
            <div className="flex gap-2">
              {cursor ? (
                <button
                  type="button"
                  onClick={() => setCursor("")}
                  className="inline-flex h-8 items-center gap-1 rounded-lg border border-line px-2.5 text-xs font-medium text-steel hover:bg-canvas"
                >
                  <ChevronLeft className="size-3.5" aria-hidden /> First
                </button>
              ) : null}
              {active.data?.next_cursor ? (
                <button
                  type="button"
                  onClick={() => setCursor(active.data?.next_cursor ?? "")}
                  className="inline-flex h-8 items-center gap-1 rounded-lg border border-line px-2.5 text-xs font-medium text-steel hover:bg-canvas"
                >
                  Next <ChevronRight className="size-3.5" aria-hidden />
                </button>
              ) : null}
            </div>
          </div>
        ) : null}
      </Card>
    </div>
  );
}
