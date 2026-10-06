import * as React from "react";

import { useParams } from "@tanstack/react-router";

import { ArrowRight, Dot } from "lucide-react";

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
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Separator } from "@/components/ui/separator";
import { toast } from "@/components/ui/toast";
import { errorMessage, useAdminQuery, useInvalidateAdmin } from "@/hooks/use-admin-api";
import type { AuditRow, OrderRow, Page, VendorOption } from "@/lib/admin-types";
import { dateTime, rupees } from "@/lib/money";
import { adminPostServer } from "@/server/admin-api";

import { STATE_BADGE } from "../../-components/orders-columns";

const TRACK_STEPS = ["placed", "assigned", "dispatched", "delivered"] as const;

export function OrderDetail() {
  const { orderId } = useParams({ strict: false }) as { orderId: string };
  const invalidate = useInvalidateAdmin();

  // Detail = list pick (worker keeps single-row reads out of the contract).
  const { data: orders } = useAdminQuery<Page<OrderRow>>("/v1/admin/orders");
  const { data: vendors } = useAdminQuery<Page<VendorOption>>("/v1/admin/vendors?role=vendor");
  const { data: activity } = useAdminQuery<Page<AuditRow>>(`/v1/admin/audit?entity=orders`);

  const order = orders?.data.find((o) => o.id === orderId);
  const events = (activity?.data ?? []).filter((a) => a.entity_id === orderId);

  const [assignOpen, setAssignOpen] = React.useState(false);
  const [cancelOpen, setCancelOpen] = React.useState(false);
  const [vendorId, setVendorId] = React.useState<string | null>(null);
  const [confirmText, setConfirmText] = React.useState("");

  if (!order) {
    return (
      <Card>
        <CardContent className="py-16 text-center text-muted-foreground text-sm">
          Order {orderId} not found in the current page — go back to{" "}
          <a href="/dashboard/orders" className="underline">
            Orders
          </a>{" "}
          and search there.
        </CardContent>
      </Card>
    );
  }

  const stepIndex = TRACK_STEPS.indexOf(order.state as (typeof TRACK_STEPS)[number]);

  async function assign(reassign: boolean) {
    if (!vendorId) return;
    try {
      await adminPostServer({
        data: {
          path: `/v1/admin/orders/${orderId}/${reassign ? "reassign" : "assign"}`,
          body: { vendor_id: vendorId },
        },
      });
      toast.add({ title: reassign ? "Reassigned" : "Assigned", description: `${orderId} → ${vendorId}` });
      setAssignOpen(false);
      invalidate("/v1/admin");
    } catch (err) {
      toast.add({ title: "Assign failed", description: errorMessage(err), type: "error" });
    }
  }

  async function cancelOverride() {
    if (confirmText.toLowerCase() !== "cancel") return;
    try {
      await adminPostServer({ data: { path: `/v1/admin/orders/${orderId}/cancel-override`, body: {} } });
      toast.add({ title: "Order cancelled", description: `${orderId} cancelled by admin override (audited).` });
      setCancelOpen(false);
      invalidate("/v1/admin");
    } catch (err) {
      toast.add({ title: "Cancel failed", description: errorMessage(err), type: "error" });
    }
  }

  return (
    <div className="flex flex-col gap-4">
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-3 text-xl">
            {orderId}
            <Badge variant="outline" className={STATE_BADGE[order.state] ?? ""}>
              {order.state}
            </Badge>
            <Badge variant="outline">{order.payment_status}</Badge>
          </CardTitle>
          <CardDescription>
            {`${order.n} full / ${order.e} empty · window ${order.window_start.slice(11, 16)} · placed ${dateTime(order.created_at)}`}
          </CardDescription>
          <CardAction className="flex gap-2">
            <Button variant="outline" size="sm" onClick={() => setAssignOpen(true)}>
              {order.state === "assigned" ? "Reassign" : "Assign vendor"}
              <ArrowRight />
            </Button>
            <Button variant="destructive" size="sm" onClick={() => setCancelOpen(true)}>
              Cancel override
            </Button>
          </CardAction>
        </CardHeader>
        <CardContent>
          {/* Tracker */}
          <div className="flex items-center gap-2">
            {TRACK_STEPS.map((s, i) => (
              <React.Fragment key={s}>
                <div className="flex items-center gap-1.5">
                  <span
                    className={`size-2 rounded-full ${
                      i <= stepIndex && stepIndex >= 0 ? "bg-primary" : "bg-muted-foreground/30"
                    }`}
                  />
                  <span
                    className={`text-xs ${i <= stepIndex && stepIndex >= 0 ? "font-medium" : "text-muted-foreground"}`}
                  >
                    {s}
                  </span>
                </div>
                {i < TRACK_STEPS.length - 1 ? <span className="h-px w-8 bg-border" /> : null}
              </React.Fragment>
            ))}
          </div>

          <Separator className="my-4" />

          {/* Bill — server-computed breakup, never client math */}
          <div className="grid gap-3 sm:grid-cols-3">
            <div>
              <p className="text-muted-foreground text-xs">Water</p>
              <p className="font-medium text-sm tabular-nums">{rupees(order.water_bill)}</p>
            </div>
            <div>
              <p className="text-muted-foreground text-xs">Deposit due</p>
              <p className="font-medium text-sm tabular-nums">{rupees(order.deposit_due)}</p>
            </div>
            <div>
              <p className="text-muted-foreground text-xs">Cap charge</p>
              <p className="font-medium text-sm tabular-nums">{rupees(order.cap_charge)}</p>
            </div>
            <div>
              <p className="text-muted-foreground text-xs">Jars out</p>
              <p className="font-medium text-sm tabular-nums">{order.n}</p>
            </div>
            <div>
              <p className="text-muted-foreground text-xs">Empties back</p>
              <p className="font-medium text-sm tabular-nums">{order.e}</p>
            </div>
            <div>
              <p className="text-muted-foreground text-xs">Total (server-computed)</p>
              <p className="font-medium text-sm tabular-nums">{rupees(order.total)}</p>
            </div>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Activity</CardTitle>
          <CardDescription>Audit entries for this order (actor · action · when)</CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-2">
          {events.length ? (
            events.map((e) => (
              <div key={e.id} className="flex items-center gap-3 rounded-lg border px-3 py-2 text-sm">
                <Dot className="size-4 text-muted-foreground" aria-hidden />
                <Badge variant="outline">{e.action}</Badge>
                <span className="text-muted-foreground">{e.actor_id}</span>
                <span className="ml-auto text-muted-foreground text-xs">{dateTime(e.created_at)}</span>
              </div>
            ))
          ) : (
            <p className="text-muted-foreground text-sm">No audit entries for this order yet.</p>
          )}
        </CardContent>
      </Card>

      {/* Assign dialog — template primitives only */}
      <Dialog open={assignOpen} onOpenChange={setAssignOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>
              {order.state === "assigned" ? "Reassign" : "Assign"} {orderId}
            </DialogTitle>
            <DialogDescription>Pick a vendor — capacity is checked server-side (version fenced).</DialogDescription>
          </DialogHeader>
          <Select value={vendorId ?? undefined} onValueChange={(v) => setVendorId(v ?? null)}>
            <SelectTrigger className="w-full">
              <SelectValue placeholder="Choose vendor" />
            </SelectTrigger>
            <SelectContent>
              {(vendors?.data ?? []).map((v) => (
                <SelectItem key={v.id} value={v.id}>
                  {`${v.name ?? v.id} · ${v.phone ?? ""}`}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          <DialogFooter>
            <Button variant="outline" onClick={() => setAssignOpen(false)}>
              Cancel
            </Button>
            <Button disabled={!vendorId} onClick={() => void assign(order.state === "assigned")}>
              Confirm
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Destructive confirm — typed */}
      <Dialog open={cancelOpen} onOpenChange={setCancelOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Cancel order override</DialogTitle>
            <DialogDescription>
              This cancels the order regardless of state. Type <b>cancel</b> to confirm — the action is audited.
            </DialogDescription>
          </DialogHeader>
          <input
            className="h-9 w-full rounded-lg border bg-transparent px-3 text-sm"
            value={confirmText}
            onChange={(e) => setConfirmText(e.target.value)}
            placeholder="cancel"
          />
          <DialogFooter>
            <Button variant="outline" onClick={() => setCancelOpen(false)}>
              Keep order
            </Button>
            <Button
              variant="destructive"
              disabled={confirmText.toLowerCase() !== "cancel"}
              onClick={() => void cancelOverride()}
            >
              Cancel order
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
