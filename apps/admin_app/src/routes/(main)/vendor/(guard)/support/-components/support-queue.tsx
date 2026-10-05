import * as React from "react";

import { Badge } from "@/components/ui/badge";
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
import { toast, useInvalidateVendor, useVendorQuery, vendorErrorMessage } from "@/hooks/use-vendor-api";
import type { VendorComplaint } from "@/lib/vendor-types";
import { dateTime } from "@/lib/money";
import { vendorPostServer } from "@/server/vendor-api";

import { VendorEmpty, VendorError, VendorLoading } from "../../../-components/vendor-states";

/** Assigned complaints queue — agree resolves, disagree freezes for admin triage. */
export function SupportQueue() {
  const invalidate = useInvalidateVendor();
  const { data, isError, error, refetch } = useVendorQuery<{ data: VendorComplaint[] }>("/v1/vendor/complaints");
  const [target, setTarget] = React.useState<VendorComplaint | null>(null);
  const [note, setNote] = React.useState("");
  const [busy, setBusy] = React.useState(false);

  if (isError) return <VendorError error={error} onRetry={() => void refetch()} />;
  if (!data) return <VendorLoading />;
  const rows = data.data ?? [];
  if (!rows.length) {
    return <VendorEmpty title="Koi complaint nahi" hint="Assigned complaints yahan dikhengi." />;
  }

  async function verify(agree: boolean) {
    if (!target) return;
    setBusy(true);
    try {
      await vendorPostServer({
        data: { path: `/complaints/${target.id}/verify`, body: { agree, note: note.trim() } },
      });
      toast.add({
        title: agree ? "Sahi maana — resolved" : "Disagree — admin dekhega",
        description: target.id,
      });
      setTarget(null);
      setNote("");
      invalidate("/v1/vendor");
    } catch (err) {
      toast.add({ title: "Verify failed", description: vendorErrorMessage(err), type: "error" });
    } finally {
      setBusy(false);
    }
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-lg">Complaints</CardTitle>
        <CardDescription>Sahi hai to agree karein, galat hai to disagree — admin triage karega</CardDescription>
      </CardHeader>
      <CardContent className="px-0 pb-2">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Complaint</TableHead>
              <TableHead>Status</TableHead>
              <TableHead className="text-right">Verify</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.map((c) => (
              <TableRow key={c.id}>
                <TableCell>
                  <div className="flex flex-col">
                    <span className="font-medium text-sm">{c.reason_code}</span>
                    <span className="max-w-56 truncate text-muted-foreground text-xs">{c.text}</span>
                    <span className="text-muted-foreground text-xs">{dateTime(c.created_at)}</span>
                  </div>
                </TableCell>
                <TableCell>
                  <Badge variant="outline">
                    {c.vendor_agree == null ? c.status : c.vendor_agree ? "agreed" : "disputed"}
                  </Badge>
                </TableCell>
                <TableCell className="text-right">
                  {c.vendor_agree == null ? (
                    <Button
                      size="sm"
                      variant="outline"
                      onClick={() => {
                        setNote("");
                        setTarget(c);
                      }}
                    >
                      Verify
                    </Button>
                  ) : null}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </CardContent>

      <Dialog open={target != null} onOpenChange={(open) => !open && setTarget(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{`Verify ${target?.reason_code ?? ""}`}</DialogTitle>
            <DialogDescription>
              Agree = complaint sahi, resolved. Disagree = 48h admin triage ke liye freeze.
            </DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="sp-note">Note (optional)</Label>
            <Input id="sp-note" value={note} onChange={(e) => setNote(e.target.value)} placeholder="Kya hua tha?" />
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setTarget(null)}>
              Cancel
            </Button>
            <Button variant="destructive" disabled={busy} onClick={() => void verify(false)}>
              {busy ? "Working…" : "Galat hai"}
            </Button>
            <Button disabled={busy} onClick={() => void verify(true)}>
              {busy ? "Working…" : "Sahi hai"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </Card>
  );
}
