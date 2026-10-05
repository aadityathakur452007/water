import * as React from "react";

import { Minus, Plus } from "lucide-react";

import { Badge } from "@/components/ui/badge";
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
import { toast, useInvalidateVendor, vendorErrorMessage } from "@/hooks/use-vendor-api";
import type { VendorStop } from "@/lib/vendor-types";
import { num, rupees } from "@/lib/money";
import { vendorPostServer } from "@/server/vendor-api";

function Stepper({
  id,
  label,
  value,
  onChange,
}: {
  id: string;
  label: string;
  value: number;
  onChange: (v: number) => void;
}) {
  return (
    <div className="flex flex-col gap-1.5">
      <Label htmlFor={id}>{label}</Label>
      <div className="flex items-center gap-2">
        <Button
          type="button"
          variant="outline"
          size="sm"
          aria-label={`${label} kam karein`}
          disabled={value <= 0}
          onClick={() => onChange(value - 1)}
        >
          <Minus aria-hidden />
        </Button>
        <Input
          id={id}
          className="w-20 text-center tabular-nums"
          inputMode="numeric"
          value={String(value)}
          onChange={(e) => {
            const v = Number(e.target.value.replace(/\D/g, ""));
            if (Number.isFinite(v)) onChange(v);
          }}
        />
        <Button
          type="button"
          variant="outline"
          size="sm"
          aria-label={`${label} badhayein`}
          onClick={() => onChange(value + 1)}
        >
          <Plus aria-hidden />
        </Button>
      </div>
    </div>
  );
}

function parsedTriple(raw: string | null): Record<string, number> {
  if (!raw) return {};
  try {
    const t = JSON.parse(raw) as Record<string, unknown>;
    const pick = (k: string): number => (typeof t[k] === "number" ? (t[k] as number) : 0);
    return { fulls: pick("fulls_given"), empties: pick("empties_back"), cash: pick("cash"), upi: pick("upi") };
  } catch {
    return {};
  }
}

/**
 * Stop execution — triple steppers (idempotent via client key), COD cash
 * post (unpaid only; same-amount retry replays, never double-posts), and
 * the OTP-gated PoD dialog. No delete affordance anywhere.
 */
export function StopActions({ stop, onDone }: { stop: VendorStop; onDone: () => void }) {
  const invalidate = useInvalidateVendor();
  const [busy, setBusy] = React.useState(false);
  const [idemKey, setIdemKey] = React.useState<string | null>(null);

  // Browser-only: crypto.randomUUID must never run during SSR.
  React.useEffect(() => {
    try {
      if (typeof crypto !== "undefined" && "randomUUID" in crypto) setIdemKey(crypto.randomUUID());
    } catch {
      setIdemKey(null);
    }
  }, []);

  const prev = React.useMemo(() => parsedTriple(stop.triple), [stop.triple]);
  const [fulls, setFulls] = React.useState(prev.fulls ?? 0);
  const [empties, setEmpties] = React.useState(prev.empties ?? 0);
  // Wire money is integer paise (vendor_app triple_sheet: whole-Rs inputs × 100).
  const [cashRs, setCashRs] = React.useState(Math.round((prev.cash ?? 0) / 100));
  const [upiRs, setUpiRs] = React.useState(Math.round((prev.upi ?? 0) / 100));
  const [caps, setCaps] = React.useState(0);
  const [sealOk, setSealOk] = React.useState(true);
  const [cashAmount, setCashAmount] = React.useState("");
  const [podOpen, setPodOpen] = React.useState(false);
  const [otp, setOtp] = React.useState("");
  const [podEmpties, setPodEmpties] = React.useState(0);

  // Same paid predicate as vendor_app stop_detail: COD-unpaid only.
  const codUnpaid =
    stop.payment_mode !== "upi" &&
    stop.payment_status !== "paid_upi" &&
    stop.payment_status !== "paid_cash" &&
    (stop.total ?? 0) > 0;

  async function submitTriple() {
    if (!idemKey) return;
    setBusy(true);
    try {
      await vendorPostServer({
        data: {
          path: `/v1/vendor/stops/${stop.id}/triple`,
          body: {
            fulls_given: fulls,
            empties_back: empties,
            cash: cashRs * 100,
            upi: upiRs * 100,
            caps_missing: caps,
            seal_ok: sealOk,
            version: stop.version,
          },
          idempotencyKey: idemKey,
        },
      });
      toast.add({ title: "Triple jama", description: `${num(fulls)} full · ${num(empties)} khaali` });
      try {
        // Fresh key for the next triple — same-key resubmits stay replay-safe.
        setIdemKey(crypto.randomUUID());
      } catch {
        /* keep the old key — replay stays safe */
      }
      invalidate("/v1/vendor");
      onDone();
    } catch (err) {
      toast.add({ title: "Triple failed", description: vendorErrorMessage(err), type: "error" });
    } finally {
      setBusy(false);
    }
  }

  async function submitCash() {
    const amountRs = Number(cashAmount);
    if (!Number.isFinite(amountRs) || amountRs <= 0) return;
    const amount = amountRs * 100; // whole-Rs input → paise on the wire
    setBusy(true);
    try {
      await vendorPostServer({ data: { path: `/v1/vendor/stops/${stop.id}/cash`, body: { amount } } });
      toast.add({ title: "Cash jama", description: rupees(amount) });
      setCashAmount("");
      invalidate("/v1/vendor");
      onDone();
    } catch (err) {
      const msg = vendorErrorMessage(err);
      const replay = /already|pehle se/i.test(msg);
      toast.add({ title: replay ? "Pehle se jama hai" : "Cash failed", description: msg, type: "error" });
    } finally {
      setBusy(false);
    }
  }

  async function submitPod() {
    if (!otp.trim()) return;
    setBusy(true);
    try {
      await vendorPostServer({
        data: {
          path: `/v1/vendor/stops/${stop.id}/pod`,
          body: { delivery_otp: otp.trim(), empties_count: podEmpties, cash: 0, seal_ok: sealOk },
        },
      });
      toast.add({ title: "Delivery poori", description: "PoD recorded." });
      setPodOpen(false);
      setOtp("");
      invalidate("/v1/vendor");
      onDone();
    } catch (err) {
      toast.add({ title: "PoD failed", description: vendorErrorMessage(err), type: "error" });
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="grid gap-4 sm:grid-cols-2">
        <Stepper id="sa-fulls" label="Full diye" value={fulls} onChange={setFulls} />
        <Stepper id="sa-empties" label="Khaali wapas" value={empties} onChange={setEmpties} />
        <Stepper id="sa-cash" label="Cash (rupaye)" value={cashRs} onChange={setCashRs} />
        <Stepper id="sa-upi" label="UPI (rupaye)" value={upiRs} onChange={setUpiRs} />
        <Stepper id="sa-caps" label="Caps missing" value={caps} onChange={setCaps} />
        <div className="flex flex-col gap-1.5">
          <Label>Seal</Label>
          <Button
            type="button"
            variant={sealOk ? "outline" : "destructive"}
            aria-pressed={sealOk}
            onClick={() => setSealOk((v) => !v)}
          >
            {sealOk ? "Seal OK" : "Seal kharab"}
          </Button>
        </div>
      </div>
      <div className="flex flex-wrap gap-2">
        <Button disabled={busy || !idemKey} onClick={() => void submitTriple()}>
          {busy ? "Jama ho raha…" : "Triple jama karo"}
        </Button>
        <Button variant="outline" disabled={busy || stop.status === "done"} onClick={() => setPodOpen(true)}>
          PoD (OTP)
        </Button>
      </div>

      {codUnpaid ? (
        <div className="flex flex-col gap-1.5 rounded-lg border p-3">
          <Label htmlFor="sa-cash-amount">{`Cash lo — baaki ${rupees(stop.total)} (COD unpaid)`}</Label>
          <div className="flex items-center gap-2">
            <Input
              id="sa-cash-amount"
              className="w-32 tabular-nums"
              inputMode="numeric"
              placeholder="Rupaye"
              value={cashAmount}
              onChange={(e) => setCashAmount(e.target.value.replace(/\D/g, ""))}
            />
            <Button variant="outline" size="sm" disabled={busy || !cashAmount} onClick={() => void submitCash()}>
              Cash jama
            </Button>
          </div>
          <p className="text-muted-foreground text-xs">
            Same amount dobara = pehle se recorded, double-post nahi hoga.
          </p>
        </div>
      ) : (
        <p className="text-muted-foreground text-xs">
          {stop.payment_mode === "cod" ? "COD already paid hai." : "UPI/prepaid stop — cash lene ki zaroorat nahi."}
        </p>
      )}

      {stop.status === "done" ? (
        <p className="flex items-center gap-2 text-sm">
          <Badge variant="outline">Ho gaya</Badge>
        </p>
      ) : null}

      <Dialog open={podOpen} onOpenChange={(open) => !open && setPodOpen(false)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>PoD — delivery OTP</DialogTitle>
            <DialogDescription>
              Customer ko mila OTP daliye. Galat OTP fail hoga, GPS drift sirf flag hoga.
            </DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-3">
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="sa-otp">Delivery OTP</Label>
              <Input
                id="sa-otp"
                value={otp}
                onChange={(e) => setOtp(e.target.value.replace(/\D/g, "").slice(0, 6))}
                inputMode="numeric"
                autoComplete="one-time-code"
                placeholder="6-digit OTP"
                className="tabular-nums"
              />
            </div>
            <Stepper id="sa-pod-empties" label="Khaali liye" value={podEmpties} onChange={setPodEmpties} />
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setPodOpen(false)}>
              Cancel
            </Button>
            <Button disabled={busy || !otp.trim()} onClick={() => void submitPod()}>
              {busy ? "Working…" : "Confirm PoD"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
