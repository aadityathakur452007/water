import * as React from "react";

import { useNavigate } from "@tanstack/react-router";
import { LogOut } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { toast, useInvalidateVendor, useVendorQuery, vendorErrorMessage } from "@/hooks/use-vendor-api";
import type { VendorProfile, VendorSlots } from "@/lib/vendor-types";
import { vendorPostServer } from "@/server/vendor-api";
import { logoutVendorServer } from "@/server/vendor-session";

import { VendorError, VendorLoading } from "../../../-components/vendor-states";

/** Own profile + slots + logout. Text fields cap at 500 chars server-side too. */
export function Profile() {
  const navigate = useNavigate();
  const invalidate = useInvalidateVendor();
  const {
    data: profile,
    isError,
    error,
    refetch,
  } = useVendorQuery<VendorProfile>("/v1/vendor/profile");
  const { data: slots } = useVendorQuery<VendorSlots>("/v1/vendor/slots");

  const [name, setName] = React.useState("");
  const [phone, setPhone] = React.useState("");
  const [address, setAddress] = React.useState("");
  const [hours, setHours] = React.useState("");
  const [dirty, setDirty] = React.useState(false);
  const [busy, setBusy] = React.useState(false);
  const [newSlot, setNewSlot] = React.useState("");

  React.useEffect(() => {
    if (profile && !dirty) {
      setName(profile.name ?? "");
      setPhone(profile.phone ?? "");
      setAddress(profile.address ?? "");
      setHours(profile.hours ?? "");
    }
  }, [profile, dirty]);

  if (isError) return <VendorError error={error} onRetry={() => void refetch()} />;
  if (!profile) return <VendorLoading />;

  async function saveProfile() {
    setBusy(true);
    try {
      await vendorPostServer({
        data: {
          path: "/v1/vendor/profile",
          method: "PATCH",
          body: {
            name: name.slice(0, 500),
            phone: phone.slice(0, 500),
            address: address.slice(0, 500),
            hours: hours.slice(0, 500),
          },
        },
      });
      toast.add({ title: "Profile saved", description: "Updated." });
      setDirty(false);
      invalidate("/v1/vendor");
      await refetch();
    } catch (err) {
      toast.add({ title: "Save failed", description: vendorErrorMessage(err), type: "error" });
    } finally {
      setBusy(false);
    }
  }

  async function setSlot(key: string, enabled: boolean) {
    setBusy(true);
    try {
      await vendorPostServer({
        data: { path: "/v1/vendor/slots", method: "PUT", body: { slots: { [key]: enabled } } },
      });
      toast.add({ title: enabled ? "Slot on" : "Slot off", description: key });
      invalidate("/v1/vendor");
    } catch (err) {
      toast.add({ title: "Slot failed", description: vendorErrorMessage(err), type: "error" });
    } finally {
      setBusy(false);
    }
  }

  async function logout() {
    await logoutVendorServer();
    await navigate({ to: "/vendor/login", replace: true });
  }

  const slotEntries = Object.entries(slots?.slots ?? {});

  return (
    <div className="flex flex-col gap-4">
      <Card>
        <CardHeader>
          <CardTitle className="text-lg">Profile</CardTitle>
          <CardDescription>Naam, phone, pata, hours — max 500 chars</CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-3">
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="pf-name">Naam</Label>
            <Input
              id="pf-name"
              maxLength={500}
              value={name}
              onChange={(e) => {
                setName(e.target.value);
                setDirty(true);
              }}
            />
          </div>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="pf-phone">Phone</Label>
            <Input
              id="pf-phone"
              maxLength={500}
              inputMode="tel"
              value={phone}
              onChange={(e) => { setPhone(e.target.value); setDirty(true); }}
            />
          </div>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="pf-address">Pata</Label>
            <Input
              id="pf-address"
              maxLength={500}
              value={address}
              onChange={(e) => { setAddress(e.target.value); setDirty(true); }}
            />
          </div>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="pf-hours">Hours</Label>
            <Input
              id="pf-hours"
              maxLength={500}
              value={hours}
              onChange={(e) => { setHours(e.target.value); setDirty(true); }}
              placeholder="e.g. 8am–8pm, Sun closed"
            />
          </div>
          <Button className="self-start" disabled={busy || !dirty} onClick={() => void saveProfile()}>
            {busy ? "Saving…" : "Save profile"}
          </Button>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-lg">Slots</CardTitle>
          <CardDescription>Kaun se time-slots on hain (max 50)</CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-2">
          {slotEntries.length ? (
            slotEntries.map(([key, on]) => (
              <div key={key} className="flex items-center justify-between gap-2 rounded-lg border px-3 py-2">
                <span className="font-medium text-sm">{key}</span>
                <Button
                  size="sm"
                  variant={on ? "default" : "outline"}
                  aria-pressed={on}
                  disabled={busy}
                  onClick={() => void setSlot(key, !on)}
                >
                  {on ? "On" : "Off"}
                </Button>
              </div>
            ))
          ) : (
            <p className="text-muted-foreground text-sm">Koi slot set nahi hai.</p>
          )}
          <div className="flex items-center gap-2">
            <Input
              aria-label="New slot key"
              value={newSlot}
              onChange={(e) => setNewSlot(e.target.value)}
              placeholder="e.g. mon-am"
              className="h-8"
            />
            <Button
              size="sm"
              variant="outline"
              disabled={busy || !newSlot.trim() || slotEntries.length >= 50}
              onClick={() => {
                const key = newSlot.trim().slice(0, 80);
                setNewSlot("");
                void setSlot(key, true);
              }}
            >
              Add
            </Button>
          </div>
        </CardContent>
      </Card>

      <Button variant="outline" className="self-start" onClick={() => void logout()}>
        <LogOut aria-hidden /> Log out
      </Button>
    </div>
  );
}
