import * as React from "react";

import { useParams } from "@tanstack/react-router";
import { Check, Copy, KeyRound, Loader2 } from "lucide-react";

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
import { NativeSelect, NativeSelectOption } from "@/components/ui/native-select";
import { toast } from "@/components/ui/toast";
import { errorMessage, useInvalidateAdmin } from "@/hooks/use-admin-api";
import type { AccessCodeIssue } from "@/lib/vendor-types";
import { adminPostServer } from "@/server/admin-api";

/** Issue a code — the worker returns plaintext ONCE; after this dialog closes it is gone. */
export function IssueCodeDialog() {
  const { vendorId } = useParams({ strict: false }) as { vendorId: string };
  const invalidate = useInvalidateAdmin();
  const [open, setOpen] = React.useState(false);
  const [durationPreset, setDurationPreset] = React.useState("90");
  const [customDate, setCustomDate] = React.useState("");
  const [busy, setBusy] = React.useState(false);
  const [issued, setIssued] = React.useState<AccessCodeIssue | null>(null);
  const [copied, setCopied] = React.useState(false);

  function getComputedExpiresAt(): string | undefined {
    if (durationPreset === "custom") {
      if (!customDate) return undefined;
      const d = new Date(customDate);
      d.setUTCHours(23, 59, 59, 999);
      return d.toISOString();
    }
    const days = Number.parseInt(durationPreset, 10);
    if (!Number.isNaN(days) && days > 0) {
      const d = new Date();
      d.setDate(d.getDate() + days);
      return d.toISOString();
    }
    return undefined;
  }

  async function issue() {
    setBusy(true);
    try {
      const computedExpiry = getComputedExpiresAt();
      const res = (await adminPostServer({
        data: {
          path: `/v1/admin/vendors/${vendorId}/access-codes`,
          body: computedExpiry ? { expires_at: computedExpiry } : {},
        },
      })) as unknown as AccessCodeIssue;
      setIssued(res);
      setCopied(false);
      invalidate("/v1/admin");
      toast.add({ title: "Code issued", description: "Access code successfully generated." });
    } catch (err) {
      toast.add({ title: "Issue failed", description: errorMessage(err), type: "error" });
    } finally {
      setBusy(false);
    }
  }

  function close() {
    setOpen(false);
    setIssued(null);
    setDurationPreset("90");
    setCustomDate("");
  }

  async function copy() {
    if (!issued) return;
    try {
      await navigator.clipboard.writeText(issued.code);
      setCopied(true);
      setTimeout(() => setCopied(false), 2500);
    } catch {
      setCopied(false);
    }
  }

  const todayStr = new Date().toISOString().slice(0, 10);

  return (
    <>
      <Button size="sm" onClick={() => setOpen(true)} className="gap-2">
        <KeyRound className="size-4" /> Issue code
      </Button>
      <Dialog open={open} onOpenChange={(isOpen) => !isOpen && close()}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <KeyRound className="size-5 text-primary" />
              Issue Partner Access Code
            </DialogTitle>
            <DialogDescription>
              Generate a secure login code for this vendor partner. The plaintext code is only shown once.
            </DialogDescription>
          </DialogHeader>
          {issued ? (
            <div className="flex flex-col gap-3 py-2">
              <div className="flex flex-col gap-1.5">
                <Label htmlFor="ac-code">One-Time Plaintext Access Code</Label>
                <div className="flex items-center gap-2">
                  <Input id="ac-code" readOnly value={issued.code} className="font-mono text-base font-bold tabular-nums select-all" />
                  <Button variant="outline" size="sm" onClick={() => void copy()} className="gap-1.5 shrink-0">
                    {copied ? <Check className="size-4 text-emerald-500" /> : <Copy className="size-4" />}
                    {copied ? "Copied" : "Copy"}
                  </Button>
                </div>
              </div>
              <p className="rounded-lg border border-amber-500/20 bg-amber-500/10 px-3 py-2.5 text-amber-700 dark:text-amber-400 text-xs">
                Share this code with the partner directly. Once you close this window, the plaintext cannot be recovered.
              </p>
            </div>
          ) : (
            <div className="flex flex-col gap-3 py-2">
              <div className="flex flex-col gap-1.5">
                <Label htmlFor="ac-duration">Validity Period</Label>
                <NativeSelect
                  id="ac-duration"
                  value={durationPreset}
                  onChange={(e) => setDurationPreset(e.target.value)}
                  disabled={busy}
                  className="w-full"
                >
                  <NativeSelectOption value="90">90 Days (Recommended)</NativeSelectOption>
                  <NativeSelectOption value="30">30 Days</NativeSelectOption>
                  <NativeSelectOption value="60">60 Days</NativeSelectOption>
                  <NativeSelectOption value="180">180 Days (Max)</NativeSelectOption>
                  <NativeSelectOption value="custom">Custom Date</NativeSelectOption>
                </NativeSelect>
              </div>

              {durationPreset === "custom" && (
                <div className="flex flex-col gap-1.5">
                  <Label htmlFor="ac-custom-date">Expiration Date (up to 180 days)</Label>
                  <Input
                    id="ac-custom-date"
                    type="date"
                    min={todayStr}
                    max={new Date(Date.now() + 180 * 86400000).toISOString().slice(0, 10)}
                    value={customDate}
                    onChange={(e) => setCustomDate(e.target.value)}
                    disabled={busy}
                    required
                  />
                </div>
              )}
            </div>
          )}
          <DialogFooter className="gap-2 sm:gap-0">
            <Button variant="outline" onClick={close} disabled={busy}>
              {issued ? "Done" : "Cancel"}
            </Button>
            {issued ? null : (
              <Button disabled={busy || (durationPreset === "custom" && !customDate)} onClick={() => void issue()} className="gap-2">
                {busy ? (
                  <>
                    <Loader2 className="size-4 animate-spin" />
                    Issuing...
                  </>
                ) : (
                  "Generate Code"
                )}
              </Button>
            )}
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
