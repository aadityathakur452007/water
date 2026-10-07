import * as React from "react";

import { useNavigate, useSearch } from "@tanstack/react-router";

import { ArrowRight, Loader2, ShieldCheck } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Field, FieldDescription, FieldGroup, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { toast } from "@/components/ui/toast";
import { loginCodeServer } from "@/server/admin-session";

/**
 * Admin phone + access-code login — accounts are owner-created, so there is
 * no OTP step and no signup link. Error copy stays generic (no oracle for
 * valid phones vs codes); 429 names the wait. Mirrors VendorLoginForm.
 */
export function AdminLoginForm() {
  const navigate = useNavigate();
  const { next } = useSearch({ strict: false }) as { next?: string };
  const [phone, setPhone] = React.useState("+91 ");
  const [code, setCode] = React.useState("");
  const [busy, setBusy] = React.useState(false);
  const [error, setError] = React.useState<string | null>(null);
  const [copied, setCopied] = React.useState(false);

  async function copyError() {
    if (!error) return;
    // Pasteable triage bundle: visible error + when + auth mode.
    // Never includes secrets — keys stay out of the bundle by construction.
    const bundle = [
      `admin-login error @ ${new Date().toISOString()}`,
      error,
      "auth: access-code",
      `page: ${typeof window !== "undefined" ? window.location.href : ""}`,
    ].join("\n");
    try {
      await navigator.clipboard.writeText(bundle);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      setCopied(false);
    }
  }

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    const normalized = normalizePhone(phone);
    if (!normalized) {
      setError("Enter a valid Indian mobile number.");
      return;
    }
    if (code.trim().length < 4) {
      setError("Enter the access code issued by the owner.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const result = await loginCodeServer({ data: { phone: normalized, code: code.trim() } });
      if (!result.ok) {
        if (result.status === 429) {
          setError("Too many attempts — wait a bit and try again.");
        } else if (result.status === 409) {
          setError("Too many devices on this number — contact the owner.");
        } else if (result.status === 0) {
          setError(result.message);
        } else {
          setError("Invalid phone or code.");
        }
        return;
      }
      toast.add({ title: "Signed in", description: "Welcome back." });
      await navigate({ href: next?.startsWith("/") ? next : "/dashboard", replace: true });
    } catch (e) {
      setError(e instanceof Error ? e.message : "Sign-in failed. Is the API running?");
    } finally {
      setBusy(false);
    }
  }

  return (
    <form
      noValidate
      onSubmit={(e) => void onSubmit(e)}
      className="flex flex-col gap-4"
    >
      <FieldGroup className="gap-4">
        <Field className="gap-1.5">
          <FieldLabel htmlFor="admin-phone">Phone number</FieldLabel>
          <Input
            id="admin-phone"
            value={phone}
            onChange={(e) => {
              const digits = e.target.value.replace(/\D/g, "");
              const clean = digits.startsWith("91") && digits.length > 2 ? digits.slice(2) : digits;
              const limited = clean.slice(0, 10);
              setPhone(limited ? `+91 ${limited}` : "+91 ");
            }}
            inputMode="numeric"
            autoComplete="tel"
            placeholder="+91 93021 90067"
            className="tabular-nums"
          />
          <FieldDescription>Your 10-digit Indian admin number, then access code.</FieldDescription>
        </Field>
        <Field className="gap-1.5">
          <FieldLabel htmlFor="admin-access-code">Access code</FieldLabel>
          <Input
            id="admin-access-code"
            value={code}
            onChange={(e) => setCode(e.target.value)}
            autoComplete="one-time-code"
            placeholder="Issued by the owner"
            className="tabular-nums"
          />
          <FieldDescription>Lost it? Ask the owner for a new code.</FieldDescription>
        </Field>
        {error ? (
          <div role="alert" className="flex items-start justify-between gap-2 rounded-md bg-destructive/10 px-3 py-2">
            <p className="font-medium text-destructive text-xs">{error}</p>
            <button
              type="button"
              onClick={() => void copyError()}
              className="shrink-0 text-destructive text-xs underline"
              aria-label="Copy error details"
            >
              {copied ? "Copied" : "Copy"}
            </button>
          </div>
        ) : null}
      </FieldGroup>
      <Button className="w-full" type="submit" disabled={busy}>
        {busy ? <Loader2 className="animate-spin" aria-hidden /> : null}
        {busy ? "Checking…" : "Sign in"}
        <ArrowRight aria-hidden />
      </Button>
      <p className="flex items-center justify-center gap-1.5 text-muted-foreground text-xs">
        <ShieldCheck className="size-3.5" aria-hidden />
        Sessions are HttpOnly · role enforced on every request
      </p>
    </form>
  );
}

function normalizePhone(input: string): string | null {
  const digits = input.replace(/\D/g, "");
  const last10 = digits.slice(-10);
  if (last10.length !== 10 || !/^[6-9]/.test(last10)) return null;
  return `+91${last10}`;
}
