import * as React from "react";

import { useNavigate } from "@tanstack/react-router";

import { ArrowRight, Loader2, ShieldCheck } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Field, FieldDescription, FieldGroup, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { toast } from "@/components/ui/toast";
import { loginVendorVerifyServer } from "@/server/vendor-session";

/**
 * Vendor phone + access-code login — accounts are admin-created, so there is
 * no OTP step and no signup link. Error copy stays generic (no oracle for
 * valid phones vs codes); 429 names the wait.
 */
export function VendorLoginForm() {
  const navigate = useNavigate();
  const [phone, setPhone] = React.useState("+91 ");
  const [code, setCode] = React.useState("");
  const [busy, setBusy] = React.useState(false);
  const [error, setError] = React.useState<string | null>(null);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    const normalized = normalizePhone(phone);
    if (!normalized) {
      setError("Sahi 10-digit mobile number likhein.");
      return;
    }
    if (code.trim().length < 4) {
      setError("Access code likhein (admin se mila tha).");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const result = await loginVendorVerifyServer({ data: { phone: normalized, code: code.trim() } });
      if (!result.ok) {
        if (result.status === 429) {
          setError("Bahut koshish ho gayi — thodi der baad try karein.");
        } else if (result.status === 409) {
          setError("Is number par bahut devices hain — admin se baat karein.");
        } else if (result.status === 0) {
          setError(result.message);
        } else {
          setError("Invalid phone or code.");
        }
        return;
      }
      toast.add({ title: "Namaste!", description: "Aaj ka route taiyaar hai." });
      await navigate({ to: "/vendor", replace: true });
    } catch (e) {
      setError(e instanceof Error ? e.message : "Sign-in failed.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <form noValidate onSubmit={(e) => void onSubmit(e)} className="flex flex-col gap-4">
      <FieldGroup className="gap-4">
        <Field className="gap-1.5">
          <FieldLabel htmlFor="vendor-phone">Phone number</FieldLabel>
          <Input
            id="vendor-phone"
            value={phone}
            onChange={(e) => {
              const digits = e.target.value.replace(/\D/g, "");
              const clean = digits.startsWith("91") && digits.length > 2 ? digits.slice(2) : digits;
              const limited = clean.slice(0, 10);
              setPhone(limited ? `+91 ${limited}` : "+91 ");
            }}
            inputMode="numeric"
            autoComplete="tel"
            placeholder="+91 98XXX XXXXX"
            className="tabular-nums"
          />
          <FieldDescription>Wohi 10-digit number jo admin ne vendor banate waqt dala tha.</FieldDescription>
        </Field>
        <Field className="gap-1.5">
          <FieldLabel htmlFor="vendor-code">Access code</FieldLabel>
          <Input
            id="vendor-code"
            value={code}
            onChange={(e) => setCode(e.target.value)}
            autoComplete="one-time-code"
            placeholder="Admin se mila code"
            className="tabular-nums"
          />
          <FieldDescription>Code bhool gaye? Admin se naya code lein.</FieldDescription>
        </Field>
        {error ? (
          <div role="alert" className="flex flex-col gap-1.5 rounded-md bg-destructive/10 px-3 py-2">
            <p className="font-medium text-destructive text-xs">{error}</p>
            <a
              href="https://wa.me/917828442476?text=Namaste%20Admin%2C%20vendor%20login%20me%20problem%20aa%20rahi%20hai"
              target="_blank"
              rel="noreferrer"
              className="font-medium text-destructive text-xs underline hover:opacity-80"
            >
              Admin WhatsApp (+91 7828442476) par madad lein
            </a>
          </div>
        ) : null}
      </FieldGroup>
      <Button className="w-full" type="submit" disabled={busy}>
        {busy ? <Loader2 className="animate-spin" aria-hidden /> : null}
        {busy ? "Checking…" : "Sign in"}
        <ArrowRight aria-hidden />
      </Button>
      <div className="flex flex-col items-center justify-center gap-1.5 text-center text-muted-foreground text-xs">
        <a
          href="https://wa.me/917828442476?text=Namaste%20Admin%2C%20mujhe%20vendor%20support%20chahiye"
          target="_blank"
          rel="noreferrer"
          className="text-primary underline hover:opacity-80"
        >
          Pareshani aane par Admin WhatsApp (+91 7828442476) par sampark karein
        </a>
        <p className="flex items-center gap-1">
          <ShieldCheck className="size-3.5" aria-hidden />
          Sessions are HttpOnly · sirf aapka data dikhega
        </p>
      </div>
    </form>
  );
}

function normalizePhone(input: string): string | null {
  const digits = input.replace(/\D/g, "");
  const last10 = digits.slice(-10);
  if (last10.length !== 10 || !/^[6-9]/.test(last10)) return null;
  return `+91${last10}`;
}
