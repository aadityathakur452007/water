import * as React from "react";
import { Check, Copy, ExternalLink, KeyRound, Loader2, Plus, ShieldCheck, UserPlus } from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { NativeSelect, NativeSelectOption } from "@/components/ui/native-select";
import { toast } from "@/components/ui/toast";
import { errorMessage, useAdminQuery, useInvalidateAdmin } from "@/hooks/use-admin-api";
import type { Page, ZoneRow } from "@/lib/admin-types";
import { adminPostServer } from "@/server/admin-api";

type CreatedResult = {
  vendorId: string;
  name: string;
  phone: string;
  code: string;
  expiresAt: string;
};

export function AddVendorDialog() {
  const [open, setOpen] = React.useState(false);
  const [submitting, setSubmitting] = React.useState(false);
  const [createdResult, setCreatedResult] = React.useState<CreatedResult | null>(null);
  const [copied, setCopied] = React.useState(false);

  // Form states
  const [name, setName] = React.useState("");
  const [phone, setPhone] = React.useState("");
  const [zoneId, setZoneId] = React.useState("");
  const [maxStops, setMaxStops] = React.useState("50");
  const [kycNote, setKycNote] = React.useState("Verified by Admin");

  const invalidate = useInvalidateAdmin();

  // Load active zones
  const { data: zonesData } = useAdminQuery<Page<ZoneRow>>("/v1/admin/zones");
  const zones = React.useMemo(() => zonesData?.data ?? [], [zonesData]);

  // Set default zone if available
  React.useEffect(() => {
    if (zones.length > 0 && !zoneId) {
      setZoneId(zones[0].id);
    }
  }, [zones, zoneId]);

  function resetForm() {
    setName("");
    setPhone("");
    if (zones.length > 0) setZoneId(zones[0].id);
    setMaxStops("50");
    setKycNote("Verified by Admin");
    setCreatedResult(null);
    setCopied(false);
    setSubmitting(false);
  }

  function handleOpenChange(nextOpen: boolean) {
    if (!nextOpen) {
      resetForm();
    }
    setOpen(nextOpen);
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    const cleanPhone = phone.trim().replace(/\D/g, "");
    const cleanName = name.trim();

    if (!cleanName || cleanName.length < 2) {
      toast.add({ title: "Name required", description: "Please enter the partner's full name.", type: "error" });
      return;
    }

    if (!/^[6-9]\d{9}$/.test(cleanPhone)) {
      toast.add({
        title: "Invalid phone number",
        description: "Please enter a valid 10-digit Indian mobile number (e.g. 9826123456).",
        type: "error",
      });
      return;
    }

    if (!zoneId) {
      toast.add({ title: "Zone required", description: "Please select an operating zone.", type: "error" });
      return;
    }

    setSubmitting(true);
    try {
      // 1. Create vendor user & profile
      const createRes = (await adminPostServer({
        data: {
          path: "/v1/admin/vendors",
          body: {
            name: cleanName,
            phone: cleanPhone,
            zone_id: zoneId,
            kyc_note: kycNote.trim() || "Verified by Admin",
          },
        },
      })) as { id?: string };

      const vendorId = createRes?.id;
      if (!vendorId) {
        throw new Error("Vendor registration did not return an identifier.");
      }

      // 2. Verify vendor role & KYC
      await adminPostServer({
        data: {
          path: `/v1/admin/vendors/${vendorId}/verify`,
          body: {},
        },
      });

      // 3. Set shift capacity
      const stopsNum = Number.parseInt(maxStops, 10);
      if (!Number.isNaN(stopsNum) && stopsNum > 0) {
        await adminPostServer({
          data: {
            path: `/v1/admin/vendors/${vendorId}/capacity`,
            body: { max_stops: stopsNum },
          },
        });
      }

      // 4. Generate initial 90-day access code
      const accessRes = (await adminPostServer({
        data: {
          path: `/v1/admin/vendors/${vendorId}/access-codes`,
          body: {},
        },
      })) as { code?: string; expires_at?: string };

      const code = accessRes?.code ?? "";
      const expiresAt = accessRes?.expires_at ?? "";

      setCreatedResult({
        vendorId,
        name: cleanName,
        phone: cleanPhone,
        code,
        expiresAt,
      });

      invalidate("/v1/admin");
      toast.add({ title: "Vendor Onboarded", description: `${cleanName} registered and access code generated.` });
    } catch (err) {
      toast.add({ title: "Onboarding failed", description: errorMessage(err), type: "error" });
    } finally {
      setSubmitting(false);
    }
  }

  function handleCopy() {
    if (!createdResult?.code) return;
    navigator.clipboard.writeText(createdResult.code);
    setCopied(true);
    toast.add({ title: "Code Copied", description: "Access code copied to clipboard." });
    setTimeout(() => setCopied(false), 2500);
  }

  function getWhatsAppUrl(): string {
    if (!createdResult) return "#";
    const text = [
      `Hello ${createdResult.name},`,
      "Your Shodasha Water Vendor Partner account is now active.",
      `Access Code: ${createdResult.code}`,
      "Vendor Portal: https://shodasha-admin.adityathakur452007.workers.dev/auth/v1/login",
      "Please enter your registered phone number and the access code to sign in.",
    ].join("\n");
    return `https://wa.me/91${createdResult.phone}?text=${encodeURIComponent(text)}`;
  }

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogTrigger render={<Button size="sm" className="gap-2" />}>
        <UserPlus className="size-4" />
        Add Vendor
      </DialogTrigger>

      <DialogContent className="sm:max-w-md">
        {!createdResult ? (
          <form onSubmit={handleSubmit} className="flex flex-col gap-4">
            <DialogHeader>
              <DialogTitle className="flex items-center gap-2">
                <UserPlus className="size-5 text-primary" />
                Onboard Delivery Partner
              </DialogTitle>
              <DialogDescription>
                Register a new vendor agency partner, assign their operating zone, verify KYC, and generate a login code.
              </DialogDescription>
            </DialogHeader>

            <div className="grid gap-3 py-2">
              <div className="grid gap-1.5">
                <Label htmlFor="vendor-name">Agency / Partner Name</Label>
                <Input
                  id="vendor-name"
                  placeholder="e.g. Ramesh Water Hub"
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  disabled={submitting}
                  required
                />
              </div>

              <div className="grid gap-1.5">
                <Label htmlFor="vendor-phone">Mobile Phone (10 digits)</Label>
                <Input
                  id="vendor-phone"
                  type="tel"
                  placeholder="e.g. 9826123456"
                  maxLength={10}
                  value={phone}
                  onChange={(e) => setPhone(e.target.value.replace(/\D/g, ""))}
                  disabled={submitting}
                  required
                />
              </div>

              <div className="grid gap-1.5">
                <Label htmlFor="vendor-zone">Operating Zone</Label>
                <NativeSelect
                  id="vendor-zone"
                  value={zoneId}
                  onChange={(e) => setZoneId(e.target.value)}
                  disabled={submitting}
                  className="w-full"
                >
                  {zones.map((z) => (
                    <NativeSelectOption key={z.id} value={z.id}>
                      {z.name} ({z.pincodes || "All Area"})
                    </NativeSelectOption>
                  ))}
                </NativeSelect>
              </div>

              <div className="grid gap-1.5">
                <Label htmlFor="vendor-capacity">Daily Shift Capacity (Stops)</Label>
                <Input
                  id="vendor-capacity"
                  type="number"
                  min={1}
                  max={500}
                  value={maxStops}
                  onChange={(e) => setMaxStops(e.target.value)}
                  disabled={submitting}
                />
              </div>

              <div className="grid gap-1.5">
                <Label htmlFor="vendor-kyc">KYC & Verification Notes</Label>
                <Input
                  id="vendor-kyc"
                  placeholder="e.g. Aadhaar & Commercial Auto verified"
                  value={kycNote}
                  onChange={(e) => setKycNote(e.target.value)}
                  disabled={submitting}
                />
              </div>
            </div>

            <DialogFooter className="gap-2 sm:gap-0">
              <Button type="button" variant="outline" onClick={() => setOpen(false)} disabled={submitting}>
                Cancel
              </Button>
              <Button type="submit" disabled={submitting} className="gap-2">
                {submitting ? (
                  <>
                    <Loader2 className="size-4 animate-spin" />
                    Registering...
                  </>
                ) : (
                  <>
                    <Plus className="size-4" />
                    Create & Generate Code
                  </>
                )}
              </Button>
            </DialogFooter>
          </form>
        ) : (
          <div className="flex flex-col gap-4 py-2">
            <DialogHeader>
              <DialogTitle className="flex items-center gap-2 text-emerald-600 dark:text-emerald-400">
                <ShieldCheck className="size-5" />
                Vendor Successfully Registered
              </DialogTitle>
              <DialogDescription>
                {createdResult.name} (+91 {createdResult.phone}) is verified and ready to sign in.
              </DialogDescription>
            </DialogHeader>

            <div className="rounded-xl border bg-muted/30 p-4">
              <div className="flex items-center justify-between">
                <div className="text-muted-foreground text-xs uppercase tracking-wider font-semibold">
                  One-Time Access Code
                </div>
                <Badge variant="outline" className="border-emerald-500/30 text-emerald-600 dark:text-emerald-400">
                  Valid 90 Days
                </Badge>
              </div>

              <div className="mt-3 flex items-center justify-between gap-3 rounded-lg border bg-background p-3 font-mono text-xl tracking-widest font-bold">
                <span className="flex items-center gap-2 select-all">
                  <KeyRound className="size-5 text-muted-foreground" />
                  {createdResult.code}
                </span>
                <Button size="sm" variant="ghost" onClick={handleCopy} className="size-8 p-0">
                  {copied ? <Check className="size-4 text-emerald-500" /> : <Copy className="size-4" />}
                </Button>
              </div>
              <p className="mt-2 text-muted-foreground text-xs">
                This plaintext code is only displayed once. Please share it with the partner immediately.
              </p>
            </div>

            <div className="flex flex-col gap-2">
              <a
                href={getWhatsAppUrl()}
                target="_blank"
                rel="noreferrer"
                className="inline-flex w-full items-center justify-center gap-2 rounded-lg bg-emerald-600 py-2.5 font-medium text-sm text-white transition hover:bg-emerald-700"
              >
                <ExternalLink className="size-4" />
                Send Credentials via WhatsApp
              </a>

              <Button variant="outline" onClick={() => setOpen(false)} className="w-full">
                Done
              </Button>
            </div>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}
