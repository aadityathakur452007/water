import * as React from "react";

import { useNavigate } from "@tanstack/react-router";

import { ClipboardList, PackageOpen, Route as RouteIcon, Truck } from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardAction, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { toast } from "@/components/ui/toast";
import { errorMessage, useAdminQuery, useInvalidateAdmin } from "@/hooks/use-admin-api";
import type { CustodyRow, OrderRow, Page, Reconciliation } from "@/lib/admin-types";
import { num, rupees } from "@/lib/money";
import { adminPostServer } from "@/server/admin-api";

const FUNNEL: Array<{ state: string; label: string }> = [
  { state: "placed", label: "Placed (unassigned)" },
  { state: "assigned", label: "Assigned" },
  { state: "dispatched", label: "Dispatched" },
  { state: "delivered", label: "Delivered" },
  { state: "failed", label: "Failed" },
  { state: "cancelled", label: "Cancelled" },
];

/** FR-26 dispatch board — funnel, unassigned pool, route board, custody (F2). */
export function Dispatch() {
  const navigate = useNavigate();
  const { data: orders } = useAdminQuery<Page<OrderRow>>("/v1/admin/orders");
  const { data: reco } = useAdminQuery<Page<Reconciliation>>("/v1/admin/reconciliation");
  const { data: custody } = useAdminQuery<Page<CustodyRow>>("/v1/admin/custody");
  const [generating, setGenerating] = React.useState(false);
  const invalidate = useInvalidateAdmin();
  const [confirmVendor, setConfirmVendor] = React.useState<string | null>(null);
  const [handoverRs, setHandoverRs] = React.useState("");
  const [confirming, setConfirming] = React.useState(false);

  async function confirmHandover() {
    if (!confirmVendor) return;
    const paise = Math.round(Number(handoverRs) * 100);
    if (!Number.isFinite(paise) || paise <= 0) return;
    setConfirming(true);
    try {
      const res = (await adminPostServer({
        data: { path: "/v1/admin/custody/confirm", body: { vendor_id: confirmVendor, amount: paise } },
      })) as unknown as { in_hand?: number };
      toast.add({ title: "Handover confirmed", description: `In hand now ${rupees(Number(res.in_hand ?? 0))}` });
      setConfirmVendor(null);
      setHandoverRs("");
      invalidate("/v1/admin");
    } catch (err) {
      toast.add({ title: "Confirm failed", description: errorMessage(err), type: "error" });
    } finally {
      setConfirming(false);
    }
  }

  const rows = orders?.data ?? [];
  const counts = Object.fromEntries(
    FUNNEL.map(({ state }) => [state, rows.filter((o) => o.state === state).length]),
  ) as Record<string, number>;
  const unassigned = rows.filter((o) => o.state === "placed");
  const poolGmv = unassigned.reduce((a, o) => a + o.total, 0);

  async function generateRoutes() {
    setGenerating(true);
    try {
      const res = (await adminPostServer({ data: { path: "/v1/admin/routes/generate", body: {} } })) as {
        routes?: number;
      };
      toast.add({ title: "Routes generated", description: `${res.routes ?? 2} route sheets created (FR-27).` });
    } catch (err) {
      toast.add({ title: "Generate failed", description: errorMessage(err), type: "error" });
    } finally {
      setGenerating(false);
    }
  }

  return (
    <div className="flex flex-col gap-4">
      {/* Funnel strip */}
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 xl:grid-cols-6">
        {FUNNEL.map(({ state, label }) => (
          <button
            key={state}
            type="button"
            onClick={() => navigate({ to: "/dashboard/orders", search: { state } })}
            className="rounded-xl border bg-card p-4 text-left shadow-xs transition-colors hover:bg-muted/40"
          >
            <p className="text-muted-foreground text-xs">{label}</p>
            <p className="mt-1 font-medium text-2xl tabular-nums">{num(counts[state])}</p>
          </button>
        ))}
      </div>

      <div className="grid gap-4 lg:grid-cols-3">
        {/* Unassigned pool */}
        <Card className="lg:col-span-2">
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <PackageOpen className="size-4" aria-hidden />
              Unassigned pool
            </CardTitle>
            <CardDescription>{`${unassigned.length} placed orders waiting · ${rupees(poolGmv)} in pool (FR-26)`}</CardDescription>
          </CardHeader>
          <CardContent className="px-0 pb-2">
            <Table className="**:data-[slot='table-cell']:px-4 **:data-[slot='table-head']:px-4">
              <TableHeader className="[&_tr]:border-t">
                <TableRow>
                  <TableHead className="py-3">Order</TableHead>
                  <TableHead className="py-3">User</TableHead>
                  <TableHead className="py-3">Jars</TableHead>
                  <TableHead className="py-3">Amount</TableHead>
                  <TableHead className="py-3" />
                </TableRow>
              </TableHeader>
              <TableBody>
                {unassigned.length ? (
                  unassigned.slice(0, 8).map((o) => (
                    <TableRow key={o.id} className="border-border/60">
                      <TableCell className="px-3 py-3 font-medium text-sm">{o.id}</TableCell>
                      <TableCell className="px-3 py-3 text-sm">{o.user_id}</TableCell>
                      <TableCell className="px-3 py-3 text-sm tabular-nums">{`${o.n} / ${o.e}`}</TableCell>
                      <TableCell className="px-3 py-3 text-sm tabular-nums">{rupees(o.total)}</TableCell>
                      <TableCell className="px-3 py-3 text-right">
                        <Button
                          size="sm"
                          variant="outline"
                          onClick={() => navigate({ to: "/dashboard/orders/$orderId", params: { orderId: o.id } })}
                        >
                          Assign
                        </Button>
                      </TableCell>
                    </TableRow>
                  ))
                ) : (
                  <TableRow>
                    <TableCell colSpan={5} className="h-16 text-center text-muted-foreground">
                      Nothing pending — every order is dispatched.
                    </TableCell>
                  </TableRow>
                )}
              </TableBody>
            </Table>
          </CardContent>
        </Card>

        {/* Custody */}
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Truck className="size-4" aria-hidden />
              Vendor custody
            </CardTitle>
            <CardDescription>Jars on the street right now (F2 integrity)</CardDescription>
          </CardHeader>
          <CardContent className="flex flex-col gap-2">
            {(custody?.data ?? []).map((c) => (
              <div key={c.vendor_id} className="flex items-center justify-between rounded-lg border px-3 py-2">
                <div className="min-w-0">
                  <p className="truncate font-medium text-sm">{c.name ?? c.vendor_id}</p>
                  <p className="text-muted-foreground text-xs">{`on duty ${num(c.on_duty)}`}</p>
                </div>
                <div className="flex items-center gap-2">
                  <Badge
                    variant="outline"
                    className={
                      c.in_hand > 30
                        ? "border-amber-500/20 bg-amber-500/10 text-amber-600"
                        : "border-emerald-500/20 bg-emerald-500/10 text-emerald-600"
                    }
                  >
                    {`${num(c.in_hand)} jars`}
                  </Badge>
                  <Button
                    variant="outline"
                    size="sm"
                    className="h-7"
                    onClick={() => {
                      setConfirmVendor(c.vendor_id);
                      setHandoverRs("");
                    }}
                  >
                    Confirm handover
                  </Button>
                </div>
              </div>
            ))}
            {(custody?.data ?? []).length === 0 ? (
              <p className="py-6 text-center text-muted-foreground text-sm">No vendors on duty.</p>
            ) : null}
          </CardContent>
        </Card>
      </div>

      {/* Route board */}
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <RouteIcon className="size-4" aria-hidden />
            Today's route board
          </CardTitle>
          <CardDescription>Stops, deliveries and jar movement per route (loading sheet, FR-25/27)</CardDescription>
          <CardAction>
            <Button size="sm" onClick={generateRoutes} disabled={generating}>
              <ClipboardList /> {generating ? "Generating…" : "Generate routes"}
            </Button>
          </CardAction>
        </CardHeader>
        <CardContent className="px-0 pb-2">
          <Table className="**:data-[slot='table-cell']:px-4 **:data-[slot='table-head']:px-4">
            <TableHeader className="[&_tr]:border-t">
              <TableRow>
                <TableHead className="py-3">Route</TableHead>
                <TableHead className="py-3">Stops</TableHead>
                <TableHead className="py-3">Delivered</TableHead>
                <TableHead className="py-3">Failed</TableHead>
                <TableHead className="py-3">Collections</TableHead>
                <TableHead className="py-3">Jars out / back</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {(reco?.data ?? []).length ? (
                (reco?.data ?? []).map((r) => (
                  <TableRow key={`${String(r.route)}-${String(r.date)}`} className="border-border/60">
                    <TableCell className="px-3 py-3 font-medium text-sm">{String(r.route ?? "—")}</TableCell>
                    <TableCell className="px-3 py-3 text-sm tabular-nums">{num(Number(r.stopped ?? 0))}</TableCell>
                    <TableCell className="px-3 py-3 text-sm tabular-nums">{num(Number(r.delivered ?? 0))}</TableCell>
                    <TableCell className="px-3 py-3 text-sm tabular-nums">{num(Number(r.failed ?? 0))}</TableCell>
                    <TableCell className="px-3 py-3 text-sm tabular-nums">
                      {`${rupees(Number(r.cash_collected ?? 0))} + ${rupees(Number(r.upi_collected ?? 0))}`}
                    </TableCell>
                    <TableCell className="px-3 py-3 text-sm tabular-nums">
                      {`${num(Number(r.jars_out ?? 0))} / ${num(Number(r.empty_returned ?? 0))}`}
                    </TableCell>
                  </TableRow>
                ))
              ) : (
                <TableRow>
                  <TableCell colSpan={6} className="h-16 text-center text-muted-foreground">
                    No routes yet — generate to build today's loading sheets.
                  </TableCell>
                </TableRow>
              )}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      <Dialog open={confirmVendor != null} onOpenChange={(open) => !open && setConfirmVendor(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Confirm cash handover</DialogTitle>
            <DialogDescription>Cash received from the vendor decrements agency money in hand. Audited.</DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="dispatch-handover">Amount (Rs)</Label>
            <Input
              id="dispatch-handover"
              inputMode="decimal"
              value={handoverRs}
              onChange={(e) => setHandoverRs(e.target.value)}
              placeholder="0"
            />
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setConfirmVendor(null)}>
              Cancel
            </Button>
            <Button disabled={confirming || !(Number(handoverRs) > 0)} onClick={() => void confirmHandover()}>
              {confirming ? "Confirming…" : "Confirm"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
