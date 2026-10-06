import * as React from "react";

import { MessageCircle, XCircle } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
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
import type { DunningRow, LedgerRow, Page } from "@/lib/admin-types";
import { phoneMasked, rupees } from "@/lib/money";
import { adminPostServer } from "@/server/admin-api";

/**
 * FR-31 + F6: dues carry-forward with friendly Hindi reminders on WhatsApp —
 * the industry's real channel — plus the audited write-off escape hatch.
 */
export function Dunning() {
  const invalidate = useInvalidateAdmin();
  const { data } = useAdminQuery<Page<DunningRow>>("/v1/admin/dunning");
  // /admin/dunning returns bare {customer_id, dues} — enrich with the name/phone
  // directory from the ledger page (which joins users) so reminders address people.
  const { data: ledgerDir } = useAdminQuery<Page<LedgerRow>>("/v1/admin/ledger?limit=200");
  const directory = new Map((ledgerDir?.data ?? []).map((l) => [l.customer_id, l]));
  const rows = (data?.data ?? []).map((r) => ({
    ...r,
    name: directory.get(r.customer_id)?.customer_name ?? null,
    phone: directory.get(r.customer_id)?.customer_phone ?? null,
  }));

  const [writeOffTarget, setWriteOffTarget] = React.useState<DunningRow | null>(null);
  const [reason, setReason] = React.useState("");
  const [busy, setBusy] = React.useState(false);

  const total = rows.reduce((a, r) => a + r.dues, 0);

  function waLink(r: DunningRow): string {
    // FR-31: friendly Hindi reminder — pre-filled, admin sends from their own WhatsApp.
    const msg = encodeURIComponent(
      `Namaste ${r.name ?? "ji"} 🙏\nShodasha Mineral Waters se reminder: aapke paas ₹${(r.dues / 100).toFixed(0)} ka bhugtan baaki hai. Kripya aaj hi UPI kar dein ya delivery par cash de dein.\nDhanyavaad!`,
    );
    const phone = (r.phone ?? "").replace(/\D/g, "").slice(-10);
    return `https://wa.me/91${phone}?text=${msg}`;
  }

  async function submitWriteOff() {
    if (!writeOffTarget || reason.trim().length < 1) return;
    setBusy(true);
    try {
      const res = (await adminPostServer({
        data: {
          path: `/v1/admin/dues/${writeOffTarget.customer_id}/write-off`,
          body: { reason: reason.trim() },
        },
      })) as { written_off?: number };
      toast.add({
        title: "Dues written off",
        description: `${rupees(res.written_off ?? 0)} cleared for ${writeOffTarget.name ?? writeOffTarget.customer_id} (audited)`,
      });
      setWriteOffTarget(null);
      invalidate("/v1/admin");
    } catch (err) {
      toast.add({ title: "Write-off failed", description: errorMessage(err), type: "error" });
    } finally {
      setBusy(false);
    }
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Dues follow-up</CardTitle>
        <CardDescription>
          {rows.length
            ? `${rows.length} customers · ${rupees(total)} outstanding — remind on WhatsApp, write off only with a reason (top 200 by dues)`
            : "No outstanding dues."}
        </CardDescription>
      </CardHeader>
      {rows.length ? (
        <CardContent className="px-0 pb-2">
          <Table className="**:data-[slot='table-cell']:px-4 **:data-[slot='table-head']:px-4">
            <TableHeader className="[&_tr]:border-t">
              <TableRow>
                <TableHead className="py-3">Customer</TableHead>
                <TableHead className="py-3">Dues</TableHead>
                <TableHead className="py-3 text-right">Actions</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {rows.map((r) => (
                <TableRow key={r.customer_id} className="border-border/60">
                  <TableCell className="px-3 py-3 text-sm">
                    <div className="flex flex-col">
                      <span className="font-medium">{r.name ?? r.customer_id}</span>
                      <span className="text-muted-foreground text-xs">{phoneMasked(r.phone)}</span>
                    </div>
                  </TableCell>
                  <TableCell className="px-3 py-3 font-medium text-sm tabular-nums">{rupees(r.dues)}</TableCell>
                  <TableCell className="px-3 py-3">
                    <div className="flex justify-end gap-2">
                      <Button
                        size="sm"
                        variant="outline"
                        render={<a href={waLink(r)} target="_blank" rel="noreferrer" />}
                      >
                        <MessageCircle /> WhatsApp reminder
                      </Button>
                      <Button
                        size="sm"
                        variant="ghost"
                        className="text-destructive"
                        onClick={() => {
                          setReason("");
                          setWriteOffTarget(r);
                        }}
                      >
                        <XCircle /> Write off
                      </Button>
                    </div>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      ) : null}

      <Dialog open={writeOffTarget != null} onOpenChange={(open) => !open && setWriteOffTarget(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Write off {rupees(writeOffTarget?.dues ?? 0)}</DialogTitle>
            <DialogDescription>
              Zeroes the customer's dues in the jar ledger. The reason is stored and the action audited — never do this
              to hide a collection failure.
            </DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="dunning-reason">Reason (required)</Label>
            <Input
              id="dunning-reason"
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              placeholder="e.g. deposit-theft settlement agreed 2026-10-03"
            />
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setWriteOffTarget(null)}>
              Cancel
            </Button>
            <Button
              variant="destructive"
              disabled={busy || reason.trim().length < 1}
              onClick={() => void submitWriteOff()}
            >
              {busy ? "Working…" : "Confirm write-off"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </Card>
  );
}
