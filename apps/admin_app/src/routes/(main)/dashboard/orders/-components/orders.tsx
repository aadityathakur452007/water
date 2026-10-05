import * as React from "react";

import { useNavigate, useSearch } from "@tanstack/react-router";

import { Download, Search } from "lucide-react";

import { StatusLegend } from "@/components/status-legend";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { InputGroup, InputGroupAddon, InputGroupInput } from "@/components/ui/input-group";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { errorMessage } from "@/hooks/use-admin-api";
import { useCursorPages } from "@/hooks/use-cursor-pages";
import type { OrderRow } from "@/lib/admin-types";
import { dateTime, rupees } from "@/lib/money";

import { STATE_BADGE } from "./orders-columns";

const STATES = ["All", "placed", "assigned", "dispatched", "delivered", "cancelled", "failed"];
const PAYMENT = ["All", "paid", "unpaid", "refunded"];

/** Client-side CSV export of the currently loaded (filtered) rows. */
function exportOrdersCsv(rows: OrderRow[]) {
  const csvEscape = (v: string | number) => {
    const s = String(v);
    return /[",\n]/.test(s) ? `"${s.replaceAll('"', '""')}"` : s;
  };
  const lines = [
    "order_id,user_id,jars_full,jars_empty,amount_inr,payment_status,state,window_start,created_at",
    ...rows.map((r) =>
      [r.id, r.user_id, r.n, r.e, (r.total / 100).toFixed(2), r.payment_status, r.state, r.window_start, r.created_at]
        .map(csvEscape)
        .join(","),
    ),
  ];
  const blob = new Blob([lines.join("\n")], { type: "text/csv;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = `shodasha-orders-${new Date().toISOString().slice(0, 10)}.csv`;
  a.click();
  URL.revokeObjectURL(url);
}

export function Orders() {
  const navigate = useNavigate();
  const search = useSearch({ strict: false }) as { state?: string; payment_status?: string };
  const [state, setState] = React.useState(search.state ?? "All");
  const [payment, setPayment] = React.useState(search.payment_status ?? "All");
  const [query, setQuery] = React.useState("");

  const params = new URLSearchParams();
  if (state !== "All") params.set("state", state);
  if (payment !== "All") params.set("payment_status", payment);
  if (query.trim()) params.set("query", query.trim());
  const qs = params.toString();

  // Cursor-follow: page 1 loads, Load more appends. Row counts below are
  // loaded rows, never server totals.
  const { rows, nextCursor, isError, error, isFetching, loadMore } = useCursorPages<OrderRow>(
    `/v1/admin/orders${qs ? `?${qs}` : ""}`,
  );

  return (
    <Card>
      <CardHeader className="border-b">
        <CardTitle className="text-xl leading-none">Orders</CardTitle>
        <CardDescription>All users' orders — filter by state/payment, open a row to act.</CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-4 px-0">
        <div className="flex flex-wrap items-center justify-between gap-3 px-4">
          <div className="flex flex-wrap items-center gap-3">
            <Select value={state} onValueChange={(v) => setState(v ?? "All")}>
              <SelectTrigger size="sm" className="w-40">
                <span className="text-muted-foreground">State:</span>
                <SelectValue />
              </SelectTrigger>
              <SelectContent align="start">
                {STATES.map((s) => (
                  <SelectItem key={s} value={s}>
                    {s}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <Select value={payment} onValueChange={(v) => setPayment(v ?? "All")}>
              <SelectTrigger size="sm" className="w-40">
                <span className="text-muted-foreground">Payment:</span>
                <SelectValue />
              </SelectTrigger>
              <SelectContent align="start">
                {PAYMENT.map((s) => (
                  <SelectItem key={s} value={s}>
                    {s}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="flex items-center gap-2">
            <InputGroup className="h-7 w-full md:w-64">
              <InputGroupAddon align="inline-start">
                <Search className="size-3.5" />
              </InputGroupAddon>
              <InputGroupInput
                className="h-7"
                placeholder="Search order/user id..."
                value={query}
                onChange={(e) => setQuery(e.target.value)}
              />
            </InputGroup>
            <Button variant="outline" size="sm" disabled={rows.length === 0} onClick={() => exportOrdersCsv(rows)}>
              <Download className="size-3.5" />
              CSV ({rows.length} loaded)
            </Button>
          </div>
        </div>

        {isError ? (
          <p className="px-4 text-destructive text-sm">{errorMessage(error)}</p>
        ) : (
          <Table className="**:data-[slot='table-cell']:px-4 **:data-[slot='table-head']:px-4">
            <TableHeader className="[&_tr]:border-t">
              <TableRow>
                <TableHead className="py-3">Order</TableHead>
                <TableHead className="py-3">User</TableHead>
                <TableHead className="py-3">Jars (full/empty)</TableHead>
                <TableHead className="py-3">Amount</TableHead>
                <TableHead className="py-3">Payment</TableHead>
                <TableHead className="py-3">State</TableHead>
                <TableHead className="py-3">Window</TableHead>
                <TableHead className="py-3">Placed</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {rows.map((r) => (
                <TableRow
                  key={r.id}
                  className="cursor-pointer border-border/60 hover:bg-white/2.5"
                  onClick={() => navigate({ to: "/dashboard/orders/$orderId", params: { orderId: r.id } })}
                >
                  <TableCell className="px-3 py-3 font-medium text-sm">{r.id}</TableCell>
                  <TableCell className="px-3 py-3 text-sm">{r.user_id}</TableCell>
                  <TableCell className="px-3 py-3 text-sm tabular-nums">{`${r.n} / ${r.e}`}</TableCell>
                  <TableCell className="px-3 py-3 font-medium text-sm tabular-nums">{rupees(r.total)}</TableCell>
                  <TableCell className="px-3 py-3 text-sm">{r.payment_status}</TableCell>
                  <TableCell className="px-3 py-3 text-sm">
                    <span
                      className={`inline-flex rounded-full border px-2 py-0.5 text-xs ${STATE_BADGE[r.state] ?? ""}`}
                    >
                      {r.state}
                    </span>
                  </TableCell>
                  <TableCell className="px-3 py-3 text-muted-foreground text-sm">
                    {r.window_start.slice(11, 16)}
                  </TableCell>
                  <TableCell className="px-3 py-3 text-muted-foreground text-sm">{dateTime(r.created_at)}</TableCell>
                </TableRow>
              ))}
              {rows.length === 0 && !isFetching ? (
                <TableRow>
                  <TableCell colSpan={8} className="h-24 text-center text-muted-foreground">
                    No orders match the filters.
                  </TableCell>
                </TableRow>
              ) : null}
            </TableBody>
          </Table>
        )}

        <div className="flex items-center justify-between px-4">
          <p className="text-muted-foreground text-xs">
            {`${rows.length} loaded${nextCursor ? " · more on server" : ""}`}
          </p>
          {nextCursor ? (
            <Button variant="outline" size="sm" onClick={loadMore}>
              Load more
            </Button>
          ) : null}
        </div>
        <StatusLegend />
      </CardContent>
    </Card>
  );
}
