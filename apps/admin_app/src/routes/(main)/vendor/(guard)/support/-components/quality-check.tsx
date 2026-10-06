import * as React from "react";

import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { toast, useInvalidateVendor, useVendorQuery, vendorErrorMessage } from "@/hooks/use-vendor-api";
import type { VendorQualityIncident } from "@/lib/vendor-types";
import { vendorPostServer } from "@/server/vendor-api";

/**
 * Quality vendor-check — open incidents on this vendor's route list up for
 * one-tap selection (manual id stays as fallback); the vendor confirms or
 * disputes what they saw at the door.
 */
export function QualityCheck() {
  const invalidate = useInvalidateVendor();
  // Phase 6 S6.4: query errors surface inline (never silent undefined).
  const {
    data: incidents,
    isError: listError,
    refetch: refetchList,
  } = useVendorQuery<{ data: VendorQualityIncident[] }>("/v1/vendor/quality");
  const open = (incidents?.data ?? []).filter((q) => q.status === "open");
  const [incidentId, setIncidentId] = React.useState("");
  const [check, setCheck] = React.useState("");
  const [note, setNote] = React.useState("");
  const [busy, setBusy] = React.useState(false);
  const [doneId, setDoneId] = React.useState<string | null>(null);

  async function submit(agree: boolean) {
    if (!incidentId.trim()) return;
    setBusy(true);
    try {
      await vendorPostServer({
        data: {
          path: `/quality/${incidentId.trim()}/vendor-check`,
          body: { agree, check: check.trim(), note: note.trim() },
        },
      });
      toast.add({
        title: agree ? "Quality confirmed" : "Quality disputed — admin dekhega",
        description: incidentId.trim(),
      });
      setDoneId(incidentId.trim());
      setIncidentId("");
      setCheck("");
      setNote("");
      invalidate("/v1/vendor");
    } catch (err) {
      toast.add({ title: "Check failed", description: vendorErrorMessage(err), type: "error" });
    } finally {
      setBusy(false);
    }
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-lg">Quality check</CardTitle>
        <CardDescription>Apne route ke incidents — door par jo dekha, wahi likhein</CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        {doneId ? (
          <p role="status" className="text-muted-foreground text-xs">{`Last check: ${doneId} bhej diya.`}</p>
        ) : null}
        {listError ? (
          <p role="alert" className="text-destructive text-xs">
            List nahi aayi —{" "}
            <button type="button" className="underline" onClick={() => void refetchList()}>
              retry karein
            </button>{" "}
            ya id haath se likhein.
          </p>
        ) : null}
        {open.length ? (
          <div className="flex flex-wrap gap-2">
            {open.map((q) => (
              <Button
                key={q.id}
                variant={incidentId === q.id ? "default" : "outline"}
                size="sm"
                onClick={() => setIncidentId(q.id)}
              >
                {`${q.id} · ${q.reason_code}`}
              </Button>
            ))}
          </div>
        ) : null}
        <div className="flex flex-col gap-1.5">
          <Label htmlFor="qc-id">Incident id</Label>
          <Input id="qc-id" value={incidentId} onChange={(e) => setIncidentId(e.target.value)} placeholder="e.g. q_7" />
        </div>
        <div className="flex flex-col gap-1.5">
          <Label htmlFor="qc-check">Check (kya dekha)</Label>
          <Input
            id="qc-check"
            value={check}
            onChange={(e) => setCheck(e.target.value)}
            placeholder="e.g. seal tooti thi / paani saaf tha"
          />
        </div>
        <div className="flex flex-col gap-1.5">
          <Label htmlFor="qc-note">Note (optional)</Label>
          <Input id="qc-note" value={note} onChange={(e) => setNote(e.target.value)} placeholder="Aur kuch?" />
        </div>
        <div className="flex gap-2">
          <Button variant="destructive" disabled={busy || !incidentId.trim()} onClick={() => void submit(false)}>
            {busy ? "Working…" : "Galat hai"}
          </Button>
          <Button disabled={busy || !incidentId.trim()} onClick={() => void submit(true)}>
            {busy ? "Working…" : "Sahi hai"}
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
