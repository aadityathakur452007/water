import * as React from "react";

import { useNavigate, useSearch } from "@tanstack/react-router";

import { Search } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { InputGroup, InputGroupAddon, InputGroupInput } from "@/components/ui/input-group";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { errorMessage, useAdminQuery } from "@/hooks/use-admin-api";
import type { OrderRow, Page } from "@/lib/admin-types";
import { dateTime, rupees } from "@/lib/money";

import { STATE_BADGE } from "./orders-columns";

const STATES = ["All", "placed", "assigned", "dispatched", "delivered", "cancelled", "failed"];
const PAYMENT = ["All", "paid", "unpaid", "refunded"];

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

  const { data, isError, error, isFetching } = useAdminQuery<Page<OrderRow>>(`/v1/admin/orders${qs ? `?${qs}` : ""}`);
  const rows = data?.data ?? [];
  const [showAll, setShowAll] = React.useState(false);
  const visible = showAll ? rows : rows.slice(0, 20);

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
              {visible.map((r) => (
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
              {visible.length === 0 && !isFetching ? (
                <TableRow>
                  <TableCell colSpan={8} className="h-24 text-center text-muted-foreground">
                    No orders match the filters.
                  </TableCell>
                </TableRow>
              ) : null}
            </TableBody>
          </Table>
        )}

        {rows.length > 20 ? (
          <div className="px-4">
            {data?.next_cursor ? (
              <Button variant="outline" size="sm" onClick={() => setShowAll(true)}>
                Show all ({rows.length})
              </Button>
            ) : null}
          </div>
        ) : null}
      </CardContent>
    </Card>
  );
}
