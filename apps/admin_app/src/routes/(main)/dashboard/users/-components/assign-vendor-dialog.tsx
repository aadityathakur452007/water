import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import type { UserRow } from "@/lib/admin-types";

type AssignVendorDialogProps = {
  open: boolean;
  userLabel: string;
  selectedVendor: string;
  vendors: UserRow[];
  busy: boolean;
  onOpenChange: (open: boolean) => void;
  onSelectVendor: (vendorId: string) => void;
  onSubmit: () => void;
};

export function AssignVendorDialog({
  open,
  userLabel,
  selectedVendor,
  vendors,
  busy,
  onOpenChange,
  onSelectVendor,
  onSubmit,
}: AssignVendorDialogProps) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Assign Delivery Vendor</DialogTitle>
          <DialogDescription>
            Assign <strong>{userLabel}</strong> to a delivery vendor partner. Subsequent orders will auto-route to this
            vendor.
          </DialogDescription>
        </DialogHeader>
        <div className="flex flex-col gap-3 py-2">
          <Label htmlFor="assign-vendor-select">Delivery Partner (Vendor)</Label>
          <Select value={selectedVendor} onValueChange={(val) => onSelectVendor(val ?? "none")}>
            <SelectTrigger id="assign-vendor-select">
              <SelectValue placeholder="Choose vendor partner..." />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="none">None (Unassigned / General Pool)</SelectItem>
              {vendors.map((v) => (
                <SelectItem key={v.id} value={v.id}>
                  {v.name ?? v.phone ?? v.id} ({v.phone ?? "no phone"})
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={busy}>
            Cancel
          </Button>
          <Button onClick={onSubmit} disabled={busy}>
            {busy ? "Saving…" : "Save Assignment"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
