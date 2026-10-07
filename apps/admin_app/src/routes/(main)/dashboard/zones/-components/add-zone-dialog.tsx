import * as React from "react";
import { Loader2, MapPin, Plus } from "lucide-react";

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
import { toast } from "@/components/ui/toast";
import { errorMessage, useInvalidateAdmin } from "@/hooks/use-admin-api";
import type { ZoneRow } from "@/lib/admin-types";
import { adminPostServer } from "@/server/admin-api";

type AddZoneDialogProps = {
  trigger?: React.ReactNode;
  onCreated?: (zone: ZoneRow) => void;
};

export function AddZoneDialog({ trigger, onCreated }: AddZoneDialogProps) {
  const [open, setOpen] = React.useState(false);
  const [name, setName] = React.useState("");
  const [pincodes, setPincodes] = React.useState("");
  const [submitting, setSubmitting] = React.useState(false);

  const invalidate = useInvalidateAdmin();

  function resetForm() {
    setName("");
    setPincodes("");
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
    const cleanName = name.trim();
    if (!cleanName || cleanName.length < 2) {
      toast.add({ title: "Name required", description: "Please enter a valid zone name.", type: "error" });
      return;
    }

    setSubmitting(true);
    try {
      const res = (await adminPostServer({
        data: {
          path: "/v1/admin/zones",
          body: {
            name: cleanName,
            pincodes: pincodes.trim(),
          },
        },
      })) as ZoneRow;

      invalidate("/v1/admin");
      toast.add({ title: "Operating Zone Created", description: `${cleanName} is now active.` });
      if (onCreated && res?.id) {
        onCreated(res);
      }
      setOpen(false);
      resetForm();
    } catch (err) {
      toast.add({ title: "Failed to create zone", description: errorMessage(err), type: "error" });
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogTrigger render={trigger ? (trigger as React.ReactElement) : <Button size="sm" className="gap-2" />}>
        {!trigger && (
          <>
            <Plus className="size-4" />
            Add Zone
          </>
        )}
      </DialogTrigger>

      <DialogContent className="sm:max-w-md">
        <form onSubmit={handleSubmit} className="flex flex-col gap-4">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <MapPin className="size-5 text-primary" />
              Add Operating Zone
            </DialogTitle>
            <DialogDescription>
              Define a delivery cluster and assign serviced 6-digit postal codes.
            </DialogDescription>
          </DialogHeader>

          <div className="grid gap-3 py-2">
            <div className="grid gap-1.5">
              <Label htmlFor="zone-name">Zone Name</Label>
              <Input
                id="zone-name"
                placeholder="e.g. Vijay Nagar & Palasia"
                value={name}
                onChange={(e) => setName(e.target.value)}
                disabled={submitting}
                required
              />
            </div>

            <div className="grid gap-1.5">
              <Label htmlFor="zone-pincodes">Serviced Pincodes (comma-separated)</Label>
              <Input
                id="zone-pincodes"
                placeholder="e.g. 452010, 452001, 452011"
                value={pincodes}
                onChange={(e) => setPincodes(e.target.value)}
                disabled={submitting}
              />
              <p className="text-muted-foreground text-xs">
                Addresses with these PIN codes will automatically be mapped to this zone.
              </p>
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
                  Saving...
                </>
              ) : (
                <>
                  <Plus className="size-4" />
                  Create Zone
                </>
              )}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
