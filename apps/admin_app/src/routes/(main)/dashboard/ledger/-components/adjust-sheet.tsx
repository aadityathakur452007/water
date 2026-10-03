import * as React from "react";

import { Button } from "@/components/ui/button";
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
import { toast } from "@/components/ui/toast";
import { errorMessage, useInvalidateAdmin } from "@/hooks/use-admin-api";
import type { LedgerRow } from "@/lib/admin-types";
import { adminPostServer } from "@/server/admin-api";

/**
 * FR-28/29: the ONLY manual mutation allowed on the jar ledger — deltas
 * (d_held/d_deposit/d_dues) with a mandatory reason, audited server-side.
 * Used for breakage, deposit-theft settlements and data corrections.
 */
export function AdjustSheet({ row, onClose }: { row: LedgerRow | null; onClose: () => void }) {
  const invalidate = useInvalidateAdmin();
  const [dHeld, setDHeld] = React.useState("");
  const [dDeposit, setDDeposit] = React.useState("");
  const [dDues, setDDues] = React.useState("");
  const [reason, setReason] = React.useState("");
  const [busy, setBusy] = React.useState(false);

  React.useEffect(() => {
    if (row) {
      setDHeld("");
      setDDeposit("");
      setDDues("");
      setReason("");
    }
  }, [row]);

  async function submit() {
    if (!row || reason.trim().length < 1) return;
    setBusy(true);
    try {
      await adminPostServer({
        data: {
          path: `/v1/admin/ledger/${row.customer_id}/adjust`,
          body: {
            d_held: Number(dHeld || 0),
            d_deposit: Math.round(Number(dDeposit || 0) * 100),
            d_dues: Math.round(Number(dDues || 0) * 100),
            reason: reason.trim(),
          },
        },
      });
      toast.add({ title: "Ledger adjusted", description: `${row.customer_id} updated (audited).` });
      invalidate("/v1/admin");
      onClose();
    } catch (err) {
      toast.add({ title: "Adjust failed", description: errorMessage(err), type: "error" });
    } finally {
      setBusy(false);
    }
  }

  const allZero = Number(dHeld || 0) === 0 && Number(dDeposit || 0) === 0 && Number(dDues || 0) === 0;

  return (
    <Dialog open={row != null} onOpenChange={(open) => !open && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Adjust ledger — {row?.customer_name ?? row?.customer_id}</DialogTitle>
          <DialogDescription>
            Deltas apply on top of the current position (held {row?.held ?? 0}, dues{" "}
            {`₹${((row?.dues ?? 0) / 100).toFixed(0)}`}). Every adjustment is audit-logged.
          </DialogDescription>
        </DialogHeader>
        <div className="grid grid-cols-3 gap-3">
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="adj-held">Jars Δ</Label>
            <Input
              id="adj-held"
              className="tabular-nums"
              value={dHeld}
              onChange={(e) => setDHeld(e.target.value)}
              placeholder="e.g. -1"
            />
          </div>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="adj-deposit">Deposit ₹ Δ</Label>
            <Input
              id="adj-deposit"
              className="tabular-nums"
              value={dDeposit}
              onChange={(e) => setDDeposit(e.target.value)}
              placeholder="e.g. 150"
            />
          </div>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="adj-dues">Dues ₹ Δ</Label>
            <Input
              id="adj-dues"
              className="tabular-nums"
              value={dDues}
              onChange={(e) => setDDues(e.target.value)}
              placeholder="e.g. -56"
            />
          </div>
        </div>
        <div className="flex flex-col gap-1.5">
          <Label htmlFor="adj-reason">Reason (required)</Label>
          <Input
            id="adj-reason"
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            placeholder="e.g. jar broken at delivery — evidence in quality incident q_7"
          />
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>
            Cancel
          </Button>
          <Button disabled={busy || allZero || reason.trim().length < 1} onClick={() => void submit()}>
            {busy ? "Working…" : "Confirm adjust"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
