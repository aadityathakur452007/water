import * as React from "react";

import { useParams } from "@tanstack/react-router";
import { Copy, KeyRound } from "lucide-react";

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
import type { AccessCodeIssue } from "@/lib/vendor-types";
import { adminPostServer } from "@/server/admin-api";

/** Issue a code — the worker returns plaintext ONCE; after this dialog closes it is gone. */
export function IssueCodeDialog() {
  const { vendorId } = useParams({ strict: false }) as { vendorId: string };
  const invalidate = useInvalidateAdmin();
  const [open, setOpen] = React.useState(false);
  const [expiresAt, setExpiresAt] = React.useState("");
  const [busy, setBusy] = React.useState(false);
  const [issued, setIssued] = React.useState<AccessCodeIssue | null>(null);
  const [copied, setCopied] = React.useState(false);

  async function issue() {
    setBusy(true);
    try {
      const res = (await adminPostServer({
        data: {
          path: `/v1/admin/vendors/${vendorId}/access-codes`,
          body: expiresAt.trim() ? { expires_at: expiresAt.trim() } : {},
        },
      })) as unknown as AccessCodeIssue;
      setIssued(res);
      setCopied(false);
      invalidate("/v1/admin");
    } catch (err) {
      toast.add({ title: "Issue failed", description: errorMessage(err), type: "error" });
    } finally {
      setBusy(false);
    }
  }

  function close() {
    // Plaintext dies with the dialog — the list only ever shows the mask.
    setOpen(false);
    setIssued(null);
    setExpiresAt("");
  }

  async function copy() {
    if (!issued) return;
    try {
      await navigator.clipboard.writeText(issued.code);
      setCopied(true);
    } catch {
      setCopied(false);
    }
  }

  return (
    <>
      <Button size="sm" onClick={() => setOpen(true)}>
        <KeyRound aria-hidden /> Issue code
      </Button>
      <Dialog open={open} onOpenChange={(isOpen) => !isOpen && close()}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Issue access code</DialogTitle>
            <DialogDescription>
              Per-vendor code for phone + code login. The plaintext shows exactly once below.
            </DialogDescription>
          </DialogHeader>
          {issued ? (
            <div className="flex flex-col gap-3">
              <div className="flex flex-col gap-1.5">
                <Label htmlFor="ac-code">Code — copy now, it will never be shown again</Label>
                <div className="flex items-center gap-2">
                  <Input id="ac-code" readOnly value={issued.code} className="font-mono tabular-nums" />
                  <Button variant="outline" size="sm" onClick={() => void copy()} aria-label="Copy code">
                    <Copy aria-hidden /> {copied ? "Copied" : "Copy"}
                  </Button>
                </div>
              </div>
              <p role="alert" className="rounded-md bg-amber-500/10 px-3 py-2 text-amber-600 text-xs">
                Share this with the vendor on a trusted channel. After closing, only the masked hint remains.
              </p>
            </div>
          ) : (
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="ac-expires">Expires at (optional, ISO)</Label>
              <Input
                id="ac-expires"
                value={expiresAt}
                onChange={(e) => setExpiresAt(e.target.value)}
                placeholder="e.g. 2026-11-04T00:00:00Z — blank = 90 days"
              />
            </div>
          )}
          <DialogFooter>
            <Button variant="outline" onClick={close}>
              {issued ? "Done" : "Cancel"}
            </Button>
            {issued ? null : (
              <Button disabled={busy} onClick={() => void issue()}>
                {busy ? "Issuing…" : "Issue"}
              </Button>
            )}
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
