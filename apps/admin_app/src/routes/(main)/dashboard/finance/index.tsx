import { createFileRoute } from "@tanstack/react-router";

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { useAdminQuery } from "@/hooks/use-admin-api";
import type { Page, Reconciliation } from "@/lib/admin-types";
import { num, rupees } from "@/lib/money";

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
  const { data: reco } = useAdminQuery<Page<Reconciliation>>("/v1/admin/reconciliation");
  const rows = reco?.data ?? [];

  return (
    <div className="@container/main flex flex-col gap-4 md:gap-6">
      <MoneyCards />

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
                <TableHead className="py-3">Jars out / back</TableHead>
                <TableHead className="py-3">Close</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {rows.length ? (
                rows.map((r) => {
                  const jarsOut = Number(r.jars_out ?? 0);
                  const jarsBack = Number(r.empty_returned ?? 0);
                  const leak = jarsOut - jarsBack;
                  const cash = Number(r.cash_collected ?? 0);
                  return (
                    <TableRow key={`${String(r.route)}-${String(r.date)}`} className="border-border/60">
                      <TableCell className="px-3 py-3 font-medium text-sm">{String(r.route ?? "—")}</TableCell>
                      <TableCell className="px-3 py-3 text-sm tabular-nums">{num(Number(r.stopped ?? 0))}</TableCell>
                      <TableCell className="px-3 py-3 text-sm tabular-nums">{num(Number(r.delivered ?? 0))}</TableCell>
                      <TableCell className="px-3 py-3 text-sm tabular-nums">{rupees(cash)}</TableCell>
                      <TableCell className="px-3 py-3 text-sm tabular-nums">
                        {rupees(Number(r.upi_collected ?? 0))}
                      </TableCell>
                      <TableCell className="px-3 py-3 text-sm tabular-nums">{`${num(jarsOut)} / ${num(jarsBack)}`}</TableCell>
                      <TableCell className="px-3 py-3 text-sm">
                        <CloseCell leak={leak} cash={cash} />
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
