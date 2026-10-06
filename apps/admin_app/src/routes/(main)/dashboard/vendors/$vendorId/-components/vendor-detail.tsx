import * as React from "react";

import { useNavigate, useParams } from "@tanstack/react-router";

import { Ban, CirclePause, CirclePlay, Undo2 } from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardAction, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
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
import { Separator } from "@/components/ui/separator";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { toast } from "@/components/ui/toast";
import { errorMessage, useAdminQuery, useInvalidateAdmin } from "@/hooks/use-admin-api";
import type { Page, VendorDetail as ApiVendorDetail, ZoneRow } from "@/lib/admin-types";
import { dateTime, num, phoneMasked, rupees } from "@/lib/money";
import { adminPatchServer, adminPostServer } from "@/server/admin-api";

function dialogDescription(dialog: "block" | "hold" | "capacity" | null, blocked: boolean, hold: number): string {
  if (dialog === "capacity") return "Per-vendor zone load caps + per-stop fee (paise). Audited.";
  if (dialog === "block")
    return blocked ? "Restores vendor access. Audited." : "Blocking revokes the vendor's sessions. Reason required.";
  return hold ? "Vendor resumes accepting dispatches." : "Hold stops new dispatch assignments until released.";
}

function dialogTitle(
  dialog: "block" | "hold" | "capacity" | null,
  blocked: boolean,
  hold: number,
): string {
  if (dialog === "capacity") return "Edit capacity";
  if (dialog === "block") return blocked ? "Unblock vendor" : "Block vendor";
  return hold ? "Release review hold" : "Set review hold";
}

function blockLabel(busy: boolean, blocked: boolean): string {
  if (busy) return "Working…";
  return blocked ? "Unblock" : "Block";
}

export function VendorDetail() {
  const { vendorId } = useParams({ strict: false }) as { vendorId: string };
  const navigate = useNavigate();
  const invalidate = useInvalidateAdmin();
  const { data, isError, error } = useAdminQuery<ApiVendorDetail>(`/v1/admin/vendors/${vendorId}/detail`);
  const { data: zones } = useAdminQuery<Page<ZoneRow>>("/v1/admin/zones");

  const [dialog, setDialog] = React.useState<"block" | "hold" | "capacity" | null>(null);
  const [text, setText] = React.useState("");
  const [busy, setBusy] = React.useState(false);
  const [maxStops, setMaxStops] = React.useState("");
  const [maxJars, setMaxJars] = React.useState("");
  const [feePaise, setFeePaise] = React.useState("");
  const [attachZone, setAttachZone] = React.useState("");
  const [period, setPeriod] = React.useState(() => new Date().toISOString().slice(0, 7));

  if (isError) {
    return (
      <Card>
        <CardContent className="py-16 text-center text-destructive text-sm">{errorMessage(error)}</CardContent>
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

  const v = data.vendor;
  const blocked = v.suspended === 1;
  const hold = data.profile?.review_hold ?? 0;

  async function act(kind: "block" | "hold") {
    setBusy(true);
    try {
      if (kind === "block") {
        await adminPostServer({
          data: {
            path: `/v1/admin/users/${vendorId}/${blocked ? "unsuspend" : "suspend"}`,
            body: blocked ? {} : { reason: text.trim() || "Vendor blocked from vendor detail", level: "suspend" },
          },
        });
        toast.add({ title: blocked ? "Unblocked" : "Blocked", description: v.name ?? vendorId });
      } else {
        await adminPostServer({
          data: {
            path: `/v1/admin/vendors/${vendorId}/${hold ? "release" : "review-hold"}`,
            body: hold ? {} : { note: text.trim() || "Review hold from vendor detail" },
          },
        });
        toast.add({ title: hold ? "Hold released" : "Review hold set", description: v.name ?? vendorId });
      }
      setDialog(null);
      invalidate("/v1/admin");
    } catch (err) {
      toast.add({ title: "Action failed", description: errorMessage(err), type: "error" });
    } finally {
      setBusy(false);
    }
  }

  async function saveCapacity() {
    const body: Record<string, number> = {};
    if (maxStops.trim()) body.max_stops = Number(maxStops);
    if (maxJars.trim()) body.max_jars = Number(maxJars);
    if (feePaise.trim()) body.per_stop_fee = Number(feePaise);
    if (!Object.keys(body).length) return;
    setBusy(true);
    try {
      await adminPatchServer({ data: { path: `/v1/admin/vendors/${vendorId}/capacity`, body } });
      toast.add({ title: "Capacity updated", description: v.name ?? vendorId });
      setDialog(null);
      invalidate("/v1/admin");
    } catch (err) {
      toast.add({ title: "Action failed", description: errorMessage(err), type: "error" });
    } finally {
      setBusy(false);
    }
  }

  async function mutate(path: string, body: unknown, okTitle: string) {
    setBusy(true);
    try {
      await adminPostServer({ data: { path, body } });
      toast.add({ title: okTitle, description: v.name ?? vendorId });
      invalidate("/v1/admin");
    } catch (err) {
      toast.add({ title: "Action failed", description: errorMessage(err), type: "error" });
    } finally {
      setBusy(false);
    }
  }

  const p = data.profile;

  return (
    <div className="flex flex-col gap-4">
      <Card>
        <CardHeader>
          <CardTitle className="flex flex-wrap items-center gap-3 text-xl">
            {v.name ?? vendorId}
            <Badge variant="outline">{blocked ? "Blocked" : "Active"}</Badge>
            {hold ? (
              <Badge variant="outline" className="border-amber-500/20 bg-amber-500/10 text-amber-600">
                review hold
              </Badge>
            ) : null}
          </CardTitle>
          <CardDescription>
            {`${phoneMasked(v.phone)} · KYC ${v.kyc_status} · joined ${dateTime(v.created_at)}`}
          </CardDescription>
          <CardAction className="flex gap-2">
            <Button
              variant="outline"
              size="sm"
              onClick={() => {
                setDialog("hold");
                setText("");
              }}
            >
              {hold ? <CirclePlay /> : <CirclePause />}
              {hold ? "Release hold" : "Review hold"}
            </Button>
            <Button
              variant={blocked ? "outline" : "destructive"}
              size="sm"
              onClick={() => {
                setDialog("block");
                setText("");
              }}
            >
              {blocked ? <Undo2 /> : <Ban />}
              {blockLabel(busy, blocked)}
            </Button>
          </CardAction>
        </CardHeader>
        <CardContent>
          <div className="mb-4 flex flex-wrap gap-2">
            <Button
              variant="outline"
              size="sm"
              onClick={() => navigate({ to: "/dashboard/vendors/$vendorId/preview", params: { vendorId } })}
            >
              View as vendor
            </Button>
            <Button
              variant="outline"
              size="sm"
              onClick={() => navigate({ to: "/dashboard/vendors/$vendorId/access", params: { vendorId } })}
            >
              Access codes
            </Button>
          </div>
          <div className="grid gap-4 sm:grid-cols-4">
            <div>
              <p className="text-muted-foreground text-xs">Stops done</p>
              <p className="font-medium text-xl tabular-nums">{num(data.stops_done)}</p>
            </div>
            <div>
              <p className="text-muted-foreground text-xs">Jars delivered</p>
              <p className="font-medium text-xl tabular-nums">{num(data.jars_delivered)}</p>
            </div>
            <div>
              <p className="text-muted-foreground text-xs">On duty / in hand</p>
              <p className="font-medium text-sm tabular-nums">{`${num(p?.on_duty ?? 0)} / ${num(p?.in_hand ?? 0)}`}</p>
            </div>
            <div>
              <p className="text-muted-foreground text-xs">Per-stop fee</p>
              <p className="font-medium text-sm tabular-nums">{p ? rupees(p.per_stop_fee) : "—"}</p>
            </div>
          </div>
          <Separator className="my-4" />
          <div className="grid gap-4 sm:grid-cols-3">
            <div>
              <p className="text-muted-foreground text-xs">Capacity (stops / jars per shift)</p>
              <p className="font-medium text-sm tabular-nums">{`${num(p?.max_stops_per_shift ?? 0)} / ${num(p?.max_jars_per_shift ?? 0)}`}</p>
              <Button
                variant="outline"
                size="sm"
                className="mt-1"
                onClick={() => {
                  setMaxStops(String(p?.max_stops_per_shift ?? ""));
                  setMaxJars(String(p?.max_jars_per_shift ?? ""));
                  setFeePaise(String(p?.per_stop_fee ?? ""));
                  setDialog("capacity");
                }}
              >
                Edit capacity
              </Button>
            </div>
            <div>
              <p className="text-muted-foreground text-xs">Zones</p>
              {data.zones.length ? (
                <div className="flex flex-col gap-1">
                  {data.zones.map((z) => (
                    <div key={z.id} className="flex items-center gap-2 text-sm">
                      <span className="font-medium">{z.name}</span>
                      <Button
                        variant="ghost"
                        size="sm"
                        className="h-6 px-2 text-xs"
                        disabled={busy}
                        onClick={() =>
                          void mutate(`/v1/admin/zones/${z.id}/vendors/${vendorId}/detach`, { reason: "detach from vendor detail" }, "Zone detached")
                        }
                      >
                        Detach
                      </Button>
                    </div>
                  ))}
                </div>
              ) : (
                <p className="font-medium text-sm">—</p>
              )}
              <div className="mt-2 flex items-center gap-2">
                <select
                  aria-label="Attach zone"
                  className="h-8 rounded-md border bg-background px-2 text-xs"
                  value={attachZone}
                  onChange={(e) => setAttachZone(e.target.value)}
                >
                  <option value="">Attach zone…</option>
                  {(zones?.data ?? [])
                    .filter((z) => !data.zones.some((mine) => mine.id === z.id))
                    .map((z) => (
                      <option key={z.id} value={z.id}>
                        {z.name}
                      </option>
                    ))}
                </select>
                <Button
                  variant="outline"
                  size="sm"
                  className="h-8"
                  disabled={busy || !attachZone}
                  onClick={() =>
                    void mutate(
                      `/v1/admin/zones/${attachZone}/vendors/attach`,
                      { vendor_id: vendorId, priority: 0 },
                      "Zone attached",
                    )
                  }
                >
                  Attach
                </Button>
              </div>
            </div>
            <div>
              <p className="text-muted-foreground text-xs">KYC note</p>
              <p className="font-medium text-sm">{p?.kyc_note || "—"}</p>
            </div>
          </div>
        </CardContent>
      </Card>

      <div className="grid gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>Payouts</CardTitle>
            <CardDescription>Weekly settlements (net of deductions)</CardDescription>
            <CardAction>
              <div className="flex items-center gap-2">
                <Input
                  aria-label="Payout period YYYY-MM"
                  className="h-8 w-28"
                  value={period}
                  onChange={(e) => setPeriod(e.target.value)}
                  placeholder="YYYY-MM"
                />
                <Button
                  variant="outline"
                  size="sm"
                  disabled={busy || !/^\d{4}-\d{2}$/.test(period)}
                  onClick={() =>
                    void mutate("/v1/admin/payouts/generate", { vendor_id: vendorId, period }, "Payout generated")
                  }
                >
                  Generate
                </Button>
              </div>
            </CardAction>
          </CardHeader>
          <CardContent className="px-0 pb-2">
            <Table className="**:data-[slot='table-cell']:px-4 **:data-[slot='table-head']:px-4">
              <TableHeader className="[&_tr]:border-t">
                <TableRow>
                  <TableHead className="py-3">Period</TableHead>
                  <TableHead className="py-3">Stops</TableHead>
                  <TableHead className="py-3">Gross</TableHead>
                  <TableHead className="py-3">Net</TableHead>
                  <TableHead className="py-3">Status</TableHead>
                  <TableHead className="py-3">Action</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {data.payouts.length ? (
                  data.payouts.map((o) => (
                    <TableRow key={o.id} className="border-border/60">
                      <TableCell className="px-3 py-3 font-medium text-sm">{o.period}</TableCell>
                      <TableCell className="px-3 py-3 text-sm tabular-nums">{num(o.stops_done)}</TableCell>
                      <TableCell className="px-3 py-3 text-sm tabular-nums">{rupees(o.gross_fee)}</TableCell>
                      <TableCell className="px-3 py-3 font-medium text-sm tabular-nums">{rupees(o.net)}</TableCell>
                      <TableCell className="px-3 py-3 text-sm">
                        <Badge variant="outline">{o.status}</Badge>
                      </TableCell>
                      <TableCell className="px-3 py-3 text-sm">
                        {o.status === "pending" ? (
                          <Button
                            variant="outline"
                            size="sm"
                            className="h-7"
                            disabled={busy}
                            onClick={() => void mutate(`/v1/admin/payouts/${o.id}/approve`, {}, "Payout approved")}
                          >
                            Approve
                          </Button>
                        ) : null}
                      </TableCell>
                    </TableRow>
                  ))
                ) : (
                  <TableRow>
                    <TableCell colSpan={6} className="h-20 text-center text-muted-foreground">
                      No payouts yet.
                    </TableCell>
                  </TableRow>
                )}
              </TableBody>
            </Table>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Strikes</CardTitle>
            <CardDescription>Service-severity record for this vendor</CardDescription>
          </CardHeader>
          <CardContent className="flex flex-col gap-2 pb-2">
            {data.strikes.length ? (
              data.strikes.map((s) => (
                <div key={s.id} className="flex items-center gap-3 rounded-lg border px-3 py-2 text-sm">
                  <Badge variant="outline">{`sev ${s.severity}`}</Badge>
                  <span className="font-medium">{s.kind}</span>
                  <span className="min-w-0 flex-1 truncate text-muted-foreground">{s.note}</span>
                  <span className="text-muted-foreground text-xs">{dateTime(s.created_at)}</span>
                </div>
              ))
            ) : (
              <p className="text-muted-foreground text-sm">Clean record — no strikes.</p>
            )}
          </CardContent>
        </Card>
      </div>

      <Dialog open={dialog != null} onOpenChange={(open) => !open && setDialog(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{dialogTitle(dialog, blocked, hold)}</DialogTitle>
            <DialogDescription>{dialogDescription(dialog, blocked, hold)}</DialogDescription>
          </DialogHeader>
          {dialog === "capacity" ? (
            <div className="flex flex-col gap-3">
              <div className="flex flex-col gap-1.5">
                <Label htmlFor="vd-stops">Max stops / shift</Label>
                <Input
                  id="vd-stops"
                  inputMode="numeric"
                  value={maxStops}
                  onChange={(e) => setMaxStops(e.target.value)}
                  placeholder="25"
                />
              </div>
              <div className="flex flex-col gap-1.5">
                <Label htmlFor="vd-jars">Max jars / shift</Label>
                <Input
                  id="vd-jars"
                  inputMode="numeric"
                  value={maxJars}
                  onChange={(e) => setMaxJars(e.target.value)}
                  placeholder="60"
                />
              </div>
              <div className="flex flex-col gap-1.5">
                <Label htmlFor="vd-fee">Per-stop fee (paise)</Label>
                <Input
                  id="vd-fee"
                  inputMode="numeric"
                  value={feePaise}
                  onChange={(e) => setFeePaise(e.target.value)}
                  placeholder="0 = salary model"
                />
              </div>
            </div>
          ) : !(dialog === "block" && blocked) && !(dialog === "hold" && hold) ? (
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="vd-note">Note {dialog === "block" ? "(reason, min 3 chars)" : "(optional)"}</Label>
              <Input id="vd-note" value={text} onChange={(e) => setText(e.target.value)} placeholder="Reason" />
            </div>
          ) : null}
          <DialogFooter>
            <Button variant="outline" onClick={() => setDialog(null)}>
              Cancel
            </Button>
            <Button
              variant={dialog === "block" && !blocked ? "destructive" : "default"}
              disabled={busy || (dialog === "block" && !blocked && text.trim().length < 3)}
              onClick={() => void (dialog === "capacity" ? saveCapacity() : act(dialog === "block" ? "block" : "hold"))}
            >
              {busy ? "Working…" : "Confirm"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
