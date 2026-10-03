import * as React from "react";

import { Search } from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { InputGroup, InputGroupAddon, InputGroupInput } from "@/components/ui/input-group";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { errorMessage, useAdminQuery } from "@/hooks/use-admin-api";
import type { Page, PaymentRow, RefundRow } from "@/lib/admin-types";
import { dateTime, phoneMasked, rupees } from "@/lib/money";

import { PaymentsTable } from "./payments-table";

const STATUS = ["All", "captured", "pending", "failed"];
const METHOD = ["All", "upi", "cod"];

export function Payments() {
  const [status, setStatus] = React.useState("All");
  const [method, setMethod] = React.useState("All");
  const [search, setSearch] = React.useState("");

  const params = new URLSearchParams();
  if (status !== "All") params.set("status", status);
  if (method !== "All") params.set("method", method);
  const qs = params.toString();

  const { data, isError, error } = useAdminQuery<Page<PaymentRow>>(`/v1/admin/payments${qs ? `?${qs}` : ""}`);
  const { data: refunds } = useAdminQuery<Page<RefundRow>>("/v1/admin/refunds");

  const rows = React.useMemo(() => {
    let list = data?.data ?? [];
    if (search.trim()) {
      const q = search.trim().toLowerCase();
      list = list.filter(
        (r) =>
          r.id.toLowerCase().includes(q) ||
          r.order_id.toLowerCase().includes(q) ||
          (r.user_name ?? "").toLowerCase().includes(q) ||
          (r.user_phone ?? "").includes(q),
      );
    }
    return list;
  }, [data, search]);

  return (
    <Card>
      <CardHeader className="border-b">
        <CardTitle className="text-xl leading-none">Payments</CardTitle>
        <CardDescription>Every paisa in and out — status/method filters with rider attribution.</CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-4 px-0">
        <div className="flex flex-wrap items-center justify-between gap-3 px-4">
          <div className="flex flex-wrap items-center gap-3">
            <Select value={status} onValueChange={(v) => setStatus(v ?? "All")}>
              <SelectTrigger size="sm" className="w-36">
                <span className="text-muted-foreground">Status:</span>
                <SelectValue />
              </SelectTrigger>
              <SelectContent align="start">
                {STATUS.map((s) => (
                  <SelectItem key={s} value={s}>
                    {s}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <Select value={method} onValueChange={(v) => setMethod(v ?? "All")}>
              <SelectTrigger size="sm" className="w-32">
                <span className="text-muted-foreground">Method:</span>
                <SelectValue />
              </SelectTrigger>
              <SelectContent align="start">
                {METHOD.map((m) => (
                  <SelectItem key={m} value={m}>
                    {m}
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
              placeholder="Search id/order/phone..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
            />
          </InputGroup>
        </div>

        <Tabs defaultValue="payments">
          <div className="px-4">
            <TabsList>
              <TabsTrigger value="payments">Payments</TabsTrigger>
              <TabsTrigger value="refunds">Refunds</TabsTrigger>
            </TabsList>
          </div>
          <TabsContent value="payments">
            {isError ? (
              <p className="px-4 text-destructive text-sm">{errorMessage(error)}</p>
            ) : (
              <PaymentsTable rows={rows} />
            )}
          </TabsContent>
          <TabsContent value="refunds">
            <RefundStream rows={refunds?.data ?? []} />
          </TabsContent>
        </Tabs>
      </CardContent>
    </Card>
  );
}

function RefundStream({ rows }: { rows: RefundRow[] }) {
  return (
    <Table className="**:data-[slot='table-cell']:px-4 **:data-[slot='table-head']:px-4">
      <TableHeader className="[&_tr]:border-t">
        <TableRow>
          <TableHead className="py-3">Refund</TableHead>
          <TableHead className="py-3">Order</TableHead>
          <TableHead className="py-3">Customer</TableHead>
          <TableHead className="py-3">Amount</TableHead>
          <TableHead className="py-3">Status</TableHead>
          <TableHead className="py-3">Done at</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {rows.length ? (
          rows.map((r) => (
            <TableRow key={r.id} className="border-border/60">
              <TableCell className="px-3 py-3 font-medium text-sm">{r.id}</TableCell>
              <TableCell className="px-3 py-3 text-sm">{r.order_id}</TableCell>
              <TableCell className="px-3 py-3 text-sm">
                <div className="flex flex-col">
                  <span>{r.user_name ?? "—"}</span>
                  <span className="text-muted-foreground text-xs">{phoneMasked(r.user_phone)}</span>
                </div>
              </TableCell>
              <TableCell className="px-3 py-3 font-medium text-sm tabular-nums">{rupees(r.amount)}</TableCell>
              <TableCell className="px-3 py-3 text-sm">
                <Badge variant="outline">{r.status}</Badge>
              </TableCell>
              <TableCell className="px-3 py-3 text-muted-foreground text-sm">{dateTime(r.done_at)}</TableCell>
            </TableRow>
          ))
        ) : (
          <TableRow>
            <TableCell colSpan={6} className="h-24 text-center text-muted-foreground">
              No refunds claimed.
            </TableCell>
          </TableRow>
        )}
      </TableBody>
    </Table>
  );
}
