import * as React from "react";

import { useParams } from "@tanstack/react-router";

import { Ban, Undo2 } from "lucide-react";

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
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Separator } from "@/components/ui/separator";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { toast } from "@/components/ui/toast";
import { errorMessage, useAdminQuery, useInvalidateAdmin } from "@/hooks/use-admin-api";
import type { UserDetail as ApiUserDetail } from "@/lib/admin-types";
import { dateTime, phoneMasked, rupees } from "@/lib/money";
import { adminPostServer } from "@/server/admin-api";

import { statusMeta, type UserStatus } from "../../-components/data";

function confirmLabel(busy: boolean, blocked: boolean): string {
  if (busy) return "Working…";
  return blocked ? "Confirm unblock" : "Confirm block";
}

function toStatus(u: ApiUserDetail["user"]): UserStatus {
  if (u.suspended) return u.suspended_reason ? "Suspended" : "Restricted";
  return u.kyc_status === "pending" ? "Pending KYC" : "Active";
}

export function UserDetail() {
  const { userId } = useParams({ strict: false }) as { userId: string };
  const invalidate = useInvalidateAdmin();
  const { data, isError, error } = useAdminQuery<ApiUserDetail>(`/v1/admin/users/${userId}/detail`);

  const [blockOpen, setBlockOpen] = React.useState(false);
  const [reason, setReason] = React.useState("");
  const [level, setLevel] = React.useState<"restrict" | "suspend">("suspend");
  const [busy, setBusy] = React.useState(false);

  if (isError) {
    return (
      <Card className="border-destructive/20 bg-destructive/5">
        <CardContent className="flex flex-col items-center justify-center gap-4 py-16 text-center">
          <p className="max-w-md font-medium text-destructive text-sm">{errorMessage(error)}</p>
          <div className="flex flex-wrap items-center justify-center gap-3">
            <Button
              variant="outline"
              size="sm"
              onClick={() => invalidate(`/v1/admin/users/${userId}/detail`)}
            >
              Dobara koshish karein (Retry)
            </Button>
            <Button
              variant="default"
              size="sm"
              asChild
            >
              <a
                href="https://wa.me/917828442476?text=Namaste%20Admin%2C%20user%20detail%20load%20karne%20me%20problem%20aa%20rahi%20hai"
                target="_blank"
                rel="noreferrer"
              >
                Admin WhatsApp: +91 7828442476
              </a>
            </Button>
          </div>
        </CardContent>
      </Card>
    );
  }
  if (!data) {
    // Phase 6 S6.4: skeleton while loading — never a blank page.
    return (
      <Card>
        <CardContent className="flex flex-col gap-3 py-6">
          {[0, 1, 2].map((i) => (
            <Skeleton key={i} className="h-10 w-full" />
          ))}
        </CardContent>
      </Card>
    );
  }

  const u = data.user;
  const status = toStatus(u);
  const blocked = u.suspended === 1;

  async function submit() {
    setBusy(true);
    try {
      const res = (await adminPostServer({
        data: {
          path: `/v1/admin/users/${userId}/${blocked ? "unsuspend" : "suspend"}`,
          body: blocked ? {} : { reason: reason.trim(), level },
        },
      })) as { revoked_sessions?: number };
      toast.add({
        title: blocked ? "Unblocked" : "Blocked",
        description: blocked
          ? `${u.name ?? u.id} is active again`
          : `${level === "suspend" ? "Suspended" : "Restricted"} · ${res.revoked_sessions ?? 0} sessions revoked`,
      });
      setBlockOpen(false);
      invalidate("/v1/admin");
    } catch (err) {
      toast.add({ title: "Action failed", description: errorMessage(err), type: "error" });
    } finally {
      setBusy(false);
    }
  }

  const meta = statusMeta[status];

  return (
    <div className="flex flex-col gap-4">
      <Card>
        <CardHeader>
          <CardTitle className="flex flex-wrap items-center gap-3 text-xl">
            {u.name ?? u.id}
            <Badge variant="outline" className={`gap-1.5 ${meta.badgeClass}`}>
              <span className={`size-1.5 rounded-full ${meta.dotClass}`} />
              {status}
            </Badge>
            <Badge variant="outline">{u.role}</Badge>
          </CardTitle>
          <CardDescription>
            {`${phoneMasked(u.phone)} · joined ${dateTime(u.created_at)}${u.suspended_reason ? ` · ${u.suspended_reason}` : ""}`}
          </CardDescription>
          <CardAction>
            <Button
              variant={blocked ? "outline" : "destructive"}
              size="sm"
              onClick={() => {
                setReason("");
                setLevel("suspend");
                setBlockOpen(true);
              }}
            >
              {blocked ? <Undo2 /> : <Ban />}
              {blocked ? "Unblock" : "Block"}
            </Button>
          </CardAction>
        </CardHeader>
        <CardContent>
          <div className="grid gap-4 sm:grid-cols-4">
            <div>
              <p className="text-muted-foreground text-xs">Orders</p>
              <p className="font-medium text-xl tabular-nums">{data.orders_count}</p>
            </div>
            <div>
              <p className="text-muted-foreground text-xs">Lifetime spend</p>
              <p className="font-medium text-xl tabular-nums">{rupees(data.spend_paise)}</p>
            </div>
            <div>
              <p className="text-muted-foreground text-xs">Last order</p>
              <p className="font-medium text-sm">{data.last_order_at ? dateTime(data.last_order_at) : "—"}</p>
            </div>
            <div>
              <p className="text-muted-foreground text-xs">Sessions · devices</p>
              <p className="font-medium text-sm tabular-nums">{`${data.active_sessions} · ${data.devices}`}</p>
            </div>
          </div>
          <Separator className="my-4" />
          <div className="grid gap-4 sm:grid-cols-4">
            <div>
              <p className="text-muted-foreground text-xs">Jars held</p>
              <p className="font-medium text-sm tabular-nums">{data.ledger.held}</p>
            </div>
            <div>
              <p className="text-muted-foreground text-xs">Deposit paid</p>
              <p className="font-medium text-sm tabular-nums">{rupees(data.ledger.deposit_paid)}</p>
            </div>
            <div>
              <p className="text-muted-foreground text-xs">Deposit refunded</p>
              <p className="font-medium text-sm tabular-nums">{rupees(data.ledger.deposit_refunded)}</p>
            </div>
            <div>
              <p className="text-muted-foreground text-xs">Dues</p>
              <p className="font-medium text-sm tabular-nums">
                {data.ledger.dues > 0 ? rupees(data.ledger.dues) : "—"}
              </p>
            </div>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Recent orders</CardTitle>
          <CardDescription>Latest activity for this account</CardDescription>
        </CardHeader>
        <CardContent className="px-0 pb-2">
          <Table className="**:data-[slot='table-cell']:px-4 **:data-[slot='table-head']:px-4">
            <TableHeader className="[&_tr]:border-t">
              <TableRow>
                <TableHead className="py-3">Order</TableHead>
                <TableHead className="py-3">Total</TableHead>
                <TableHead className="py-3">State</TableHead>
                <TableHead className="py-3">Payment</TableHead>
                <TableHead className="py-3">Placed</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {data.recent_orders.length ? (
                data.recent_orders.map((o) => (
                  <TableRow key={o.id} className="border-border/60 hover:bg-white/2.5">
                    <TableCell className="px-3 py-3 font-medium text-sm">{o.id}</TableCell>
                    <TableCell className="px-3 py-3 text-sm tabular-nums">{rupees(o.total)}</TableCell>
                    <TableCell className="px-3 py-3 text-sm">{o.state}</TableCell>
                    <TableCell className="px-3 py-3 text-sm">{o.payment_status}</TableCell>
                    <TableCell className="px-3 py-3 text-muted-foreground text-sm">{dateTime(o.created_at)}</TableCell>
                  </TableRow>
                ))
              ) : (
                <TableRow>
                  <TableCell colSpan={5} className="h-20 text-center text-muted-foreground">
                    No orders yet.
                  </TableCell>
                </TableRow>
              )}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      <Dialog open={blockOpen} onOpenChange={setBlockOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{blocked ? `Unblock ${u.name ?? u.id}` : `Block ${u.name ?? u.id}`}</DialogTitle>
            <DialogDescription>
              {blocked
                ? "Restores access. The action is audited."
                : "Blocking revokes live sessions immediately. The reason is stored and audited."}
            </DialogDescription>
          </DialogHeader>
          {!blocked ? (
            <div className="flex flex-col gap-3">
              <div className="flex flex-col gap-1.5">
                <Label htmlFor="ud-reason">Reason (min 3 chars)</Label>
                <Input
                  id="ud-reason"
                  value={reason}
                  onChange={(e) => setReason(e.target.value)}
                  placeholder="e.g. Cash not handed over at day-close"
                />
              </div>
              <div className="flex flex-col gap-1.5">
                <Label>Level</Label>
                <Select value={level} onValueChange={(v) => setLevel((v ?? "suspend") as "restrict" | "suspend")}>
                  <SelectTrigger className="w-full">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="restrict">restrict — login stays, writes blocked</SelectItem>
                    <SelectItem value="suspend">suspend — sessions revoked</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            </div>
          ) : null}
          <DialogFooter>
            <Button variant="outline" onClick={() => setBlockOpen(false)}>
              Cancel
            </Button>
            <Button
              variant={blocked ? "default" : "destructive"}
              disabled={busy || (!blocked && reason.trim().length < 3)}
              onClick={() => void submit()}
            >
              {confirmLabel(busy, blocked)}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
