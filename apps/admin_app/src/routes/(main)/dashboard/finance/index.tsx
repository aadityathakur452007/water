import { createFileRoute } from "@tanstack/react-router";
import * as React from "react";

import { Button } from "@/components/ui/button";
import { Card, CardAction, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { toast } from "@/components/ui/toast";
import { errorMessage, useAdminQuery, useInvalidateAdmin } from "@/hooks/use-admin-api";
import type { ReconResponse } from "@/lib/admin-types";
import { num, rupees } from "@/lib/money";
import { adminPostServer } from "@/server/admin-api";

import { Dunning } from "./-components/dunning";
import { MoneyCards } from "./-components/money-cards";

function CloseCell({ leak, cash }: { leak: number; cash: number }) {
  if (cash === 0) return <span className="text-muted-foreground">—</span>;
  if (leak > 0) return <span className="font-medium text-amber-600">{`${leak} jars with vendor`}</span>;
  return <span className="font-medium text-emerald-600">balanced</span>;
}

/** FR-30/31/33 — money command center: cards, day-close board, dues follow-up. */
export const Route = createFileRoute("/(main)/dashboard/finance/")({
  component: FinancePage,
});

function FinancePage() {
  const { data: reco } = useAdminQuery<ReconResponse>("/v1/admin/reconciliation");
  const rows = reco?.routes ?? [];
  const invalidate = useInvalidateAdmin();
  const [day, setDay] = React.useState(() => new Date().toISOString().slice(0, 10));
  const [busy, setBusy] = React.useState(false);
  const [closed, setClosed] = React.useState<Record<string, number | string | boolean> | null>(null);

  async function closeDay() {
    setBusy(true);
    try {
      const res = (await adminPostServer({
        data: { path: "/v1/admin/reconciliation/close", body: { date: day } },
      })) as unknown as Record<string, number | string | boolean>;
      setClosed(res);
      toast.add({ title: "Day closed", description: `${String(res.date)} snapshot in audit` });
      invalidate("/v1/admin");
    } catch (err) {
      toast.add({ title: "Close failed", description: errorMessage(err), type: "error" });
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="@container/main flex flex-col gap-4 md:gap-6">
      <MoneyCards />

      <Card>
        <CardHeader>
          <CardTitle>Close the day</CardTitle>
          <CardDescription>Snapshot books + collected cash/UPI + custody into the audit trail</CardDescription>
          <CardAction>
            <div className="flex items-center gap-2">
              <Input
                aria-label="Close date"
                className="h-8 w-36"
                value={day}
                onChange={(e) => setDay(e.target.value)}
                placeholder="YYYY-MM-DD"
              />
              <Button size="sm" disabled={busy || !/^\d{4}-\d{2}-\d{2}$/.test(day)} onClick={() => void closeDay()}>
                {busy ? "Closing…" : "Close day"}
              </Button>
            </div>
          </CardAction>
        </CardHeader>
        {closed ? (
          <CardContent>
            <p className="text-sm tabular-nums">{`Jama cash ${rupees(Number(closed.collected_cash ?? 0))} · UPI ${rupees(Number(closed.collected_upi ?? 0))} · custody ${rupees(Number(closed.custody_in_hand ?? 0))} · dues ${rupees(Number(closed.dues_receivable ?? 0))}`}</p>
            {closed.cash_mismatch === true || closed.upi_mismatch === true ? (
              <p className="mt-1 text-amber-600 text-xs">
                Declared vs posted money differs — see the route table cross-check before trusting this close.
              </p>
            ) : null}
          </CardContent>
        ) : null}
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Day-close reconciliation</CardTitle>
          <CardDescription>
            Cash + UPI vs pending and jars out-vs-back per route — close every evening, never a month-end surprise
            (FR-31)
          </CardDescription>
        </CardHeader>
        <CardContent className="px-0 pb-2">
          <Table className="**:data-[slot='table-cell']:px-4 **:data-[slot='table-head']:px-4">
            <TableHeader className="[&_tr]:border-t">
              <TableRow>
                <TableHead className="py-3">Route</TableHead>
                <TableHead className="py-3">Stops</TableHead>
                <TableHead className="py-3">Delivered</TableHead>
                <TableHead className="py-3">Cash</TableHead>
                <TableHead className="py-3">UPI</TableHead>
                <TableHead className="py-3">Jars out / empties (exp)</TableHead>
                <TableHead className="py-3">Close</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {rows.length ? (
                rows.map((r) => {
                  const leak = r.jars_out - r.empties_expected;
                  return (
                    <TableRow key={r.route_id} className="border-border/60">
                      <TableCell className="px-3 py-3 font-medium text-sm">
                        {r.route_id}
                        <span className="block font-normal text-muted-foreground text-xs">
                          {r.vendor_name || r.vendor_id}
                        </span>
                      </TableCell>
                      <TableCell className="px-3 py-3 text-sm tabular-nums">{num(r.stops)}</TableCell>
                      <TableCell className="px-3 py-3 text-sm tabular-nums">{num(r.delivered)}</TableCell>
                      <TableCell className="px-3 py-3 text-sm tabular-nums">{rupees(r.cash)}</TableCell>
                      <TableCell className="px-3 py-3 text-sm tabular-nums">{rupees(r.upi)}</TableCell>
                      <TableCell className="px-3 py-3 text-sm tabular-nums">{`${num(r.jars_out)} / ${num(r.empties_expected)}`}</TableCell>
                      <TableCell className="px-3 py-3 text-sm">
                        <CloseCell leak={leak} cash={r.cash} />
                      </TableCell>
                    </TableRow>
                  );
                })
              ) : (
                <TableRow>
                  <TableCell colSpan={7} className="h-20 text-center text-muted-foreground">
                    No reconciliation rows for today.
                  </TableCell>
                </TableRow>
              )}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      <Dunning />
    </div>
  );
}
