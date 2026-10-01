"use client";

import { useState } from "react";
import Link from "next/link";
import { ChevronLeft, ChevronRight, Search, PackageSearch } from "lucide-react";
import { Card, EmptyState, ErrorState, PageHeader, PaymentBadge, SkeletonRows, StateBadge } from "@/shared/ui/primitives";
import { useOrders } from "@/features/dashboard/api";
import { dateTime, num, paise } from "@/lib/format";

const STATES = ["", "placed", "accepted", "packed", "assigned", "dispatched", "delivered", "failed", "cancelled"];
const PAY_STATUSES = ["", "unpaid", "link_sent", "paid_upi", "paid_cash", "partial_dues"];

export default function OrdersPage() {
  const [state, setState] = useState("");
  const [pay, setPay] = useState("");
  const [query, setQuery] = useState("");
  const [cursor, setCursor] = useState("");
  const { data, isLoading, isError, error, isFetching } = useOrders({
    state: state || undefined,
    payment_status: pay || undefined,
    query: query || undefined,
    cursor: cursor || undefined,
  });

  const rows = data?.data ?? [];

  return (
    <div className="space-y-5">
      <PageHeader
        title="Orders"
        description="Every order by every user — filter, search, drill in."
      />

      <div className="flex flex-wrap items-center gap-2">
        <div className="relative">
          <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-faint" aria-hidden />
          <input
            value={query}
            onChange={(e) => {
              setQuery(e.target.value);
              setCursor("");
            }}
            placeholder="Search phone, user or order id"
            className="h-9 w-72 rounded-lg border border-line bg-surface pl-9 pr-3 text-sm text-ink placeholder:text-faint"
          />
        </div>
        <select
          value={state}
          onChange={(e) => {
            setState(e.target.value);
            setCursor("");
          }}
          aria-label="Filter by state"
          className="h-9 rounded-lg border border-line bg-surface px-2.5 text-sm capitalize text-ink"
        >
          {STATES.map((s) => (
            <option key={s} value={s}>{s || "All states"}</option>
          ))}
        </select>
        <select
          value={pay}
          onChange={(e) => {
            setPay(e.target.value);
            setCursor("");
          }}
          aria-label="Filter by payment status"
          className="h-9 rounded-lg border border-line bg-surface px-2.5 text-sm text-ink"
        >
          {PAY_STATUSES.map((s) => (
            <option key={s} value={s}>{s ? s.replace(/_/g, " ") : "All payments"}</option>
          ))}
        </select>
        {isFetching ? <span className="text-xs text-faint">syncing…</span> : null}
      </div>

      <Card>
        {isError ? (
          <div className="p-4">
            <ErrorState message={(error as Error).message} hint="Check that the Workers API is running." />
          </div>
        ) : isLoading ? (
          <SkeletonRows rows={8} cols={6} />
        ) : rows.length === 0 ? (
          <EmptyState
            icon={<PackageSearch className="size-5" />}
            title="No orders match"
            hint="Try clearing the state or payment filter, or search a different phone number."
          />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-line text-left text-[11px] uppercase tracking-wide text-faint">
                  <th className="px-5 py-2.5 font-medium">Order</th>
                  <th className="px-3 py-2.5 font-medium">Customer</th>
                  <th className="px-3 py-2.5 font-medium">Jars</th>
                  <th className="px-3 py-2.5 font-medium">Total</th>
                  <th className="px-3 py-2.5 font-medium">Payment</th>
                  <th className="px-3 py-2.5 font-medium">State</th>
                  <th className="px-5 py-2.5 font-medium">Created</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-line-soft">
                {rows.map((o) => (
                  <tr key={o.id} className="group transition-colors hover:bg-canvas">
                    <td className="px-5 py-3">
                      <Link href={`/admin/orders/${o.id}`} className="tnum font-medium text-accent hover:underline">
                        {o.id.slice(0, 14)}
                      </Link>
                    </td>
                    <td className="tnum px-3 py-3 text-steel">{o.user_id.slice(0, 10)}</td>
                    <td className="tnum px-3 py-3 text-steel">
                      {o.n} full · {o.e} empty
                    </td>
                    <td className="tnum px-3 py-3 font-medium text-ink">{paise(o.total)}</td>
                    <td className="px-3 py-3">
                      <PaymentBadge status={o.payment_status} />
                    </td>
                    <td className="px-3 py-3">
                      <StateBadge state={o.state} />
                    </td>
                    <td className="px-5 py-3 text-xs text-steel">{dateTime(o.created_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        {data?.next_cursor ? (
          <div className="flex items-center justify-between border-t border-line-soft px-5 py-3">
            <span className="text-xs text-faint">{num(rows.length)} shown</span>
            <div className="flex gap-2">
              <button
                type="button"
                disabled={!cursor}
                onClick={() => setCursor("")}
                className="inline-flex h-8 items-center gap-1 rounded-lg border border-line px-2.5 text-xs font-medium text-steel disabled:opacity-40 hover:bg-canvas"
              >
                <ChevronLeft className="size-3.5" aria-hidden /> First
              </button>
              <button
                type="button"
                onClick={() => setCursor(data.next_cursor ?? "")}
                className="inline-flex h-8 items-center gap-1 rounded-lg border border-line px-2.5 text-xs font-medium text-steel hover:bg-canvas"
              >
                Next <ChevronRight className="size-3.5" aria-hidden />
              </button>
            </div>
          </div>
        ) : null}
      </Card>
    </div>
  );
}
