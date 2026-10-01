"use client";

import { useState } from "react";
import Link from "next/link";
import { ChevronLeft, ChevronRight, Search, PackageSearch } from "lucide-react";
import { Card, EmptyState, ErrorState, PageHeader, PaymentBadge, SkeletonRows, StateBadge } from "@/shared/ui/primitives";
import { DataTable, columnHelper } from "@/shared/ui/data-table";
import { useOrders } from "@/features/dashboard/api";
import { dateTime, num, paise } from "@/lib/format";
import type { OrderRow } from "@/lib/types";

const STATES = ["", "placed", "accepted", "packed", "assigned", "dispatched", "delivered", "failed", "cancelled"];
const PAY_STATUSES = ["", "unpaid", "link_sent", "paid_upi", "paid_cash", "partial_dues"];

const helper = columnHelper<OrderRow>();
const cols = helper.columns([
  helper.accessor("id", {
    id: "id",
    header: "Order",
    cell: (c) => (
      <Link href={`/admin/orders/${c.row.original.id}`} className="tnum font-medium text-accent hover:underline">
        {c.row.original.id.slice(0, 14)}
      </Link>
    ),
  }),
  helper.accessor("user_id", {
    id: "customer",
    header: "Customer",
    cell: (c) => <span className="tnum text-steel">{c.row.original.user_id.slice(0, 10)}</span>,
  }),
  helper.accessor("n", {
    id: "jars",
    header: "Jars",
    cell: (c) => (
      <span className="tnum text-steel">
        {c.row.original.n} full · {c.row.original.e} empty
      </span>
    ),
  }),
  helper.accessor("total", {
    id: "total",
    header: "Total",
    cell: (c) => <span className="tnum font-medium text-ink">{paise(c.row.original.total)}</span>,
  }),
  helper.accessor("payment_status", {
    id: "payment",
    header: "Payment",
    enableSorting: false,
    cell: (c) => <PaymentBadge status={c.row.original.payment_status} />,
  }),
  helper.accessor("state", {
    id: "state",
    header: "State",
    cell: (c) => <StateBadge state={c.row.original.state} />,
  }),
  helper.accessor("created_at", {
    id: "created",
    header: "Created",
    cell: (c) => <span className="text-xs text-steel">{dateTime(c.row.original.created_at)}</span>,
  }),
]);

const CSV = [
  { label: "Order", value: (o: OrderRow) => o.id },
  { label: "Customer", value: (o: OrderRow) => o.user_id },
  { label: "Jars", value: (o: OrderRow) => `${o.n} full / ${o.e} empty` },
  { label: "Total (paise)", value: (o: OrderRow) => o.total },
  { label: "Payment", value: (o: OrderRow) => o.payment_status },
  { label: "State", value: (o: OrderRow) => o.state },
  { label: "Created", value: (o: OrderRow) => o.created_at },
];

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
        {isFetching ? <span className="text-xs text-steel">syncing…</span> : null}
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
          <DataTable
            columns={cols}
            data={rows}
            csv={CSV}
            csvFilename={`shodasha-orders-${new Date().toISOString().slice(0, 10)}.csv`}
          />
        )}
        {data?.next_cursor ? (
          <div className="flex items-center justify-between border-t border-line-soft px-5 py-3">
            <span className="text-xs text-steel">{num(rows.length)} shown</span>
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
