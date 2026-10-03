import * as React from "react";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardAction, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { toast } from "@/components/ui/toast";
import { errorMessage, useAdminQuery } from "@/hooks/use-admin-api";
import type { CustodyRow, DunningRow, Page, Reconciliation } from "@/lib/admin-types";
import { num, rupees } from "@/lib/money";
import { adminPostServer } from "@/server/admin-api";

export function Operations() {
  const { data: reco } = useAdminQuery<Page<Reconciliation>>("/v1/admin/reconciliation");
  const { data: custody } = useAdminQuery<Page<CustodyRow>>("/v1/admin/custody");
  const { data: dunning } = useAdminQuery<Page<DunningRow>>("/v1/admin/dunning");

  const [generating, setGenerating] = React.useState(false);

  async function generateRoutes() {
    setGenerating(true);
    try {
      const res = (await adminPostServer({ data: { path: "/v1/admin/routes/generate", body: {} } })) as {
        routes?: number;
      };
      toast.add({ title: "Routes generated", description: `${res.routes ?? "2"} route sheets created.` });
    } catch (err) {
      toast.add({ title: "Generate failed", description: errorMessage(err), type: "error" });
    } finally {
      setGenerating(false);
    }
  }

  return (
    <Card>
      <CardHeader className="border-b">
        <CardTitle className="text-xl leading-none">Operations</CardTitle>
        <CardDescription>Day-close reconciliation, vendor custody, dues follow-up and routing.</CardDescription>
        <CardAction>
          <Button size="sm" onClick={generateRoutes} disabled={generating}>
            {generating ? "Generating…" : "Generate routes"}
          </Button>
        </CardAction>
      </CardHeader>
      <CardContent className="px-0">
        <Tabs defaultValue="reconciliation">
          <div className="px-4">
            <TabsList>
              <TabsTrigger value="reconciliation">Reconciliation</TabsTrigger>
              <TabsTrigger value="custody">Custody</TabsTrigger>
              <TabsTrigger value="dues">Dues</TabsTrigger>
            </TabsList>
          </div>
          <TabsContent value="reconciliation">
            <Table className="**:data-[slot='table-cell']:px-4 **:data-[slot='table-head']:px-4">
              <TableHeader className="[&_tr]:border-t">
                <TableRow>
                  <TableHead className="py-3">Route</TableHead>
                  <TableHead className="py-3">Stops</TableHead>
                  <TableHead className="py-3">Delivered</TableHead>
                  <TableHead className="py-3">Cash</TableHead>
                  <TableHead className="py-3">UPI</TableHead>
                  <TableHead className="py-3">Jars out</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {(reco?.data ?? []).map((r) => (
                  <TableRow
                    key={`${String(r.route ?? "route")}-${String(r.date ?? "today")}`}
                    className="border-border/60"
                  >
                    <TableCell className="px-3 py-3 font-medium text-sm">{String(r.route ?? "—")}</TableCell>
                    <TableCell className="px-3 py-3 text-sm tabular-nums">{num(Number(r.stopped ?? 0))}</TableCell>
                    <TableCell className="px-3 py-3 text-sm tabular-nums">{num(Number(r.delivered ?? 0))}</TableCell>
                    <TableCell className="px-3 py-3 text-sm tabular-nums">
                      {rupees(Number(r.cash_collected ?? 0))}
                    </TableCell>
                    <TableCell className="px-3 py-3 text-sm tabular-nums">
                      {rupees(Number(r.upi_collected ?? 0))}
                    </TableCell>
                    <TableCell className="px-3 py-3 text-sm tabular-nums">
                      {`${num(Number(r.jars_out ?? 0))} out / ${num(Number(r.empty_returned ?? 0))} back`}
                    </TableCell>
                  </TableRow>
                ))}
                {(reco?.data ?? []).length === 0 ? (
                  <TableRow>
                    <TableCell colSpan={6} className="h-24 text-center text-muted-foreground">
                      No reconciliation rows for today.
                    </TableCell>
                  </TableRow>
                ) : null}
              </TableBody>
            </Table>
          </TabsContent>
          <TabsContent value="custody">
            <Table className="**:data-[slot='table-cell']:px-4 **:data-[slot='table-head']:px-4">
              <TableHeader className="[&_tr]:border-t">
                <TableRow>
                  <TableHead className="py-3">Vendor</TableHead>
                  <TableHead className="py-3">On duty</TableHead>
                  <TableHead className="py-3">Jars in hand</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {(custody?.data ?? []).map((c) => (
                  <TableRow key={c.vendor_id} className="border-border/60">
                    <TableCell className="px-3 py-3 font-medium text-sm">{c.name ?? c.vendor_id}</TableCell>
                    <TableCell className="px-3 py-3 text-sm tabular-nums">{num(c.on_duty)}</TableCell>
                    <TableCell className="px-3 py-3 text-sm tabular-nums">
                      {num(c.in_hand)}
                      {c.in_hand > 30 ? (
                        <Badge variant="outline" className="ml-2 border-amber-500/20 bg-amber-500/10 text-amber-600">
                          high custody
                        </Badge>
                      ) : null}
                    </TableCell>
                  </TableRow>
                ))}
                {(custody?.data ?? []).length === 0 ? (
                  <TableRow>
                    <TableCell colSpan={3} className="h-24 text-center text-muted-foreground">
                      No vendors on duty.
                    </TableCell>
                  </TableRow>
                ) : null}
              </TableBody>
            </Table>
          </TabsContent>
          <TabsContent value="dues">
            <Table className="**:data-[slot='table-cell']:px-4 **:data-[slot='table-head']:px-4">
              <TableHeader className="[&_tr]:border-t">
                <TableRow>
                  <TableHead className="py-3">Customer</TableHead>
                  <TableHead className="py-3">Dues</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {(dunning?.data ?? []).map((d) => (
                  <TableRow key={d.customer_id} className="border-border/60">
                    <TableCell className="px-3 py-3 font-medium text-sm">{d.name ?? d.customer_id}</TableCell>
                    <TableCell className="px-3 py-3 font-medium text-sm tabular-nums">{rupees(d.dues)}</TableCell>
                  </TableRow>
                ))}
                {(dunning?.data ?? []).length === 0 ? (
                  <TableRow>
                    <TableCell colSpan={2} className="h-24 text-center text-muted-foreground">
                      No outstanding dues.
                    </TableCell>
                  </TableRow>
                ) : null}
              </TableBody>
            </Table>
          </TabsContent>
        </Tabs>
      </CardContent>
    </Card>
  );
}
