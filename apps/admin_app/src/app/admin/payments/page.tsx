"use client";

import { useState } from "react";
import Link from "next/link";
import { ChevronLeft, ChevronRight, Wallet } from "lucide-react";
import { Badge, Card, EmptyState, ErrorState, PageHeader, SkeletonRows } from "@/shared/ui/primitives";
import { DataTable, columnHelper } from "@/shared/ui/data-table";
import { proxyGet } from "@/features/dashboard/api";
import { useQuery } from "@tanstack/react-query";
import { dateTime, num, paise, phoneMasked } from "@/lib/format";
import type { Page, PaymentRow, RefundRow } from "@/lib/types";

const PAY_FILTERS = ["", "paid", "link_sent", "partial", "failed"];
const REFUND_FILTERS = ["", "pending", "claimed", "done", "failed"];

const helperP = columnHelper<PaymentRow>();
const helperR = columnHelper<RefundRow>();

const payCols = helperP.columns([
  helperP.accessor("id", {
    id: "id",
    header: "Id",
    cell: (c) => <span className="tnum text-steel">{c.row.original.id.slice(0, 10)}</span>,
  }),
  helperP.accessor((p) => p.user_name ?? p.user_phone ?? "", {
    id: "customer",
    header: "Customer",
    cell: (c) => (
      <span className="text-ink">
        {c.row.original.user_name ?? "—"}
        <span className="tnum block text-xs text-steel">{phoneMasked(c.row.original.user_phone)}</span>
      </span>
    ),
  }),
  helperP.accessor("order_id", {
    id: "order",
    header: "Order",
    cell: (c) => (
      <Link href={`/admin/orders/${c.row.original.order_id}`} className="tnum text-accent hover:underline">
        {c.row.original.order_id.slice(0, 10)}
      </Link>
    ),
  }),
  helperP.accessor("method", {
    id: "method",
    header: "Method",
    cell: (c) => (
      <Badge tone={c.row.original.method === "upi" ? "accent" : "neutral"}>{c.row.original.method}</Badge>
    ),
  }),
  helperP.accessor("amount", {
    id: "amount",
    header: "Amount",
    cell: (c) => <span className="tnum font-medium text-ink">{paise(c.row.original.amount)}</span>,
  }),
  helperP.accessor("status", {
    id: "status",
    header: "Status",
    cell: (c) => (
      <Badge tone={c.row.original.status === "paid" ? "good" : c.row.original.status === "failed" ? "bad" : "warn"}>
        {c.row.original.status}
      </Badge>
    ),
  }),
  helperP.accessor((p) => p.verified_at ?? p.created_at, {
    id: "when",
    header: "When",
    cell: (c) => (
      <span className="text-xs text-steel">{dateTime(c.row.original.verified_at ?? c.row.original.created_at)}</span>
    ),
  }),
]);

const refundCols = helperR.columns([
  helperR.accessor("id", {
    id: "id",
    header: "Id",
    cell: (c) => <span className="tnum text-steel">{c.row.original.id.slice(0, 10)}</span>,
  }),
  helperR.accessor((r) => r.user_name ?? r.user_phone ?? "", {
    id: "customer",
    header: "Customer",
    cell: (c) => (
      <span className="text-ink">
        {c.row.original.user_name ?? "—"}
        <span className="tnum block text-xs text-steel">{phoneMasked(c.row.original.user_phone)}</span>
      </span>
    ),
  }),
  helperR.accessor("order_id", {
    id: "order",
    header: "Order",
    cell: (c) => (
      <Link href={`/admin/orders/${c.row.original.order_id}`} className="tnum text-accent hover:underline">
        {c.row.original.order_id.slice(0, 10)}
      </Link>
    ),
  }),
  helperR.accessor("amount", {
    id: "amount",
    header: "Amount",
    cell: (c) => <span className="tnum font-medium text-ink">{paise(c.row.original.amount)}</span>,
  }),
  helperR.accessor("status", {
    id: "status",
    header: "Status",
    cell: (c) => (
      <Badge tone={c.row.original.status === "done" ? "good" : c.row.original.status === "failed" ? "bad" : "warn"}>
        {c.row.original.status}
      </Badge>
    ),
  }),
  helperR.accessor((r) => r.done_at ?? r.created_at, {
    id: "when",
    header: "When",
    cell: (c) => (
      <span className="text-xs text-steel">{dateTime(c.row.original.done_at ?? c.row.original.created_at)}</span>
    ),
  }),
]);

const PAY_CSV = [
  { label: "Id", value: (p: PaymentRow) => p.id },
  { label: "Customer", value: (p: PaymentRow) => p.user_name ?? p.user_phone ?? "" },
  { label: "Order", value: (p: PaymentRow) => p.order_id },
  { label: "Method", value: (p: PaymentRow) => p.method ?? "" },
  { label: "Amount (paise)", value: (p: PaymentRow) => p.amount },
  { label: "Status", value: (p: PaymentRow) => p.status },
  { label: "When", value: (p: PaymentRow) => p.verified_at ?? p.created_at },
];

const REFUND_CSV = [
  { label: "Id", value: (r: RefundRow) => r.id },
  { label: "Customer", value: (r: RefundRow) => r.user_name ?? r.user_phone ?? "" },
  { label: "Order", value: (r: RefundRow) => r.order_id },
  { label: "Amount (paise)", value: (r: RefundRow) => r.amount },
  { label: "Status", value: (r: RefundRow) => r.status },
  { label: "When", value: (r: RefundRow) => r.done_at ?? r.created_at },
];

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
        {active.isFetching ? <span className="text-xs text-steel">syncing…</span> : null}
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
        ) : tab === "payments" ? (
          <DataTable
            columns={payCols}
            data={rows as PaymentRow[]}
            csv={PAY_CSV}
            csvFilename={`shodasha-payments-${new Date().toISOString().slice(0, 10)}.csv`}
          />
        ) : (
          <DataTable
            columns={refundCols}
            data={rows as RefundRow[]}
            csv={REFUND_CSV}
            csvFilename={`shodasha-refunds-${new Date().toISOString().slice(0, 10)}.csv`}
          />
        )}
        {(active.data?.next_cursor || cursor) && rows.length > 0 ? (
          <div className="flex items-center justify-between border-t border-line-soft px-5 py-3">
            <span className="text-xs text-steel">{num(rows.length)} shown</span>
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
