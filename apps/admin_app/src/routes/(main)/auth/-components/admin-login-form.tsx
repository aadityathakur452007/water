import * as React from "react";

import { useNavigate, useSearch } from "@tanstack/react-router";

import { ArrowRight, Loader2, ShieldCheck } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Field, FieldDescription, FieldGroup, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { InputOTP, InputOTPGroup, InputOTPSeparator, InputOTPSlot } from "@/components/ui/input-otp";
import { toast } from "@/components/ui/toast";
import { loginStartServer, loginVerifyServer } from "@/server/admin-session";

/**
 * Admin phone-OTP login — same two-step flow as the old admin's login page
 * (worker /v1/auth/otp/start|verify with role=admin gate; dev shortcut sends
 * the worker's dev|<phone>| token when Firebase env is absent). All visuals
 * are template primitives: Field/Input/InputOTP/Button inside the template's
 * auth layout. The access token never touches browser code (HttpOnly cookies
 * are set by the server function).
 */

declare global {
  interface Window {
    firebase?: {
      initializeApp: (cfg: Record<string, string>) => unknown;
      auth: () => {
        signInWithPhoneNumber: (
          phone: string,
          verifier: unknown,
        ) => Promise<{ confirm: (code: string) => Promise<{ user?: { getIdToken: () => Promise<string> } | null }> }>;
        RecaptchaVerifier: new (el: string | HTMLElement, opts: Record<string, unknown>) => unknown;
      };
    };
  }
}

type FirebaseAuthNamespace = () => {
  signInWithPhoneNumber: (
    phone: string,
    verifier: unknown,
  ) => Promise<{ confirm: (code: string) => Promise<{ user?: { getIdToken: () => Promise<string> } | null }> }>;
  RecaptchaVerifier: new (el: string | HTMLElement, opts: Record<string, unknown>) => unknown;
};

const FIREBASE_API_KEY = import.meta.env.VITE_FIREBASE_API_KEY as string | undefined;
const DEV_ADMIN_PHONE = (import.meta.env.VITE_ADMIN_PHONE as string | undefined) ?? "";

let sharedVerifier: { clear?: () => void } | null = null;

export function AdminLoginForm() {
  const navigate = useNavigate();
  const { next } = useSearch({ strict: false }) as { next?: string };
  const [step, setStep] = React.useState<"phone" | "otp">("phone");
  const [phone, setPhone] = React.useState(DEV_ADMIN_PHONE || "+91 ");
  const [code, setCode] = React.useState("");
  const [busy, setBusy] = React.useState(false);
  const [error, setError] = React.useState<string | null>(null);
  const [info, setInfo] = React.useState<string | null>(null);
  const [copied, setCopied] = React.useState(false);

  async function copyError() {
    if (!error) return;
    // Pasteable triage bundle: visible error + when + firebase-configured?
    // Never includes secrets — keys stay out of the bundle by construction.
    const bundle = [
      `admin-login error @ ${new Date().toISOString()}`,
      error,
      `otp-configured: ${FIREBASE_API_KEY ? "yes" : "no"}`,
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

  async function signIn(idToken: string) {
    setBusy(true);
    setError(null);
    try {
      const result = await loginVerifyServer({ data: { id_token: idToken } });
      if (!result.ok) {
        setError(result.message);
        return;
      }
      toast.add({ title: "Signed in", description: "Welcome back." });
      await navigate({ href: next?.startsWith("/") ? next : "/dashboard", replace: true });
    } catch {
      setError("Sign-in failed. Is the API running?");
    } finally {
      setBusy(false);
    }
  }

  async function startOtp() {
    const normalized = normalizePhone(phone);
    if (!normalized) {
      setError("Enter a valid Indian mobile number.");
      return;
    }
    if (!FIREBASE_API_KEY) {
      if (import.meta.env.PROD) {
        // Production builds without phone-OTP config must say so loudly:
        // the dev shortcut below only works against a DEV_AUTH=1 worker and
        // always fails in prod with "verification failed".
        setError("Phone sign-in is not configured on this deployment (missing Firebase web keys).");
        return;
      }
      // Dev fallback (worker DEV_AUTH=1): one click signs the env admin in.
      await signIn(`dev|${normalized}|local`);
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const data = await loginStartServer({ data: { phone: normalized } });
      setInfo(data.sent_to_masked ? `Code sent to ${data.sent_to_masked}` : "Code sent");
      setPhone(normalized);
      setStep("otp");
    } catch {
      setError("Could not send the code.");
    } finally {
      setBusy(false);
    }
  }

  async function verifyOtp() {
    if (code.trim().length !== 6) {
      setError("Enter the 6-digit code.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      let idToken = code.trim();
      if (!FIREBASE_API_KEY) {
        if (import.meta.env.PROD) {
          throw new Error("Phone sign-in is not configured on this deployment (missing Firebase web keys).");
        }
        const normalized = normalizePhone(phone);
        if (!normalized) throw new Error("Enter a valid Indian mobile number.");
        idToken = `dev|${normalized}|local`;
      } else if (typeof window !== "undefined" && window.firebase) {
        if (!document.getElementById("recaptcha-container")) {
          const el = document.createElement("div");
          el.id = "recaptcha-container";
          document.body.appendChild(el);
        }
        const app = window.firebase.initializeApp({
          apiKey: FIREBASE_API_KEY,
          authDomain: (import.meta.env.VITE_FIREBASE_AUTH_DOMAIN as string | undefined) ?? "",
          projectId: (import.meta.env.VITE_FIREBASE_PROJECT_ID as string | undefined) ?? "",
        });
        void app;
        const authNs = window.firebase.auth as unknown as FirebaseAuthNamespace;
        const auth = authNs();
        if (!sharedVerifier) {
          const authInstance = authNs();
          sharedVerifier = new authInstance.RecaptchaVerifier("recaptcha-container", { size: "invisible" }) as {
            clear?: () => void;
          };
        }
        const verifier = sharedVerifier;
        const normalized = normalizePhone(phone);
        if (!normalized) throw new Error("Enter a valid Indian mobile number.");
        const confirmation = await auth.signInWithPhoneNumber(normalized, verifier);
        const userCred = await confirmation.confirm(code.trim());
        const token = await userCred.user?.getIdToken();
        if (!token) throw new Error("Sign-in failed.");
        idToken = token;
      }
      await signIn(idToken);
    } catch (e) {
      try {
        sharedVerifier?.clear?.();
      } catch {
        /* already cleared */
      }
      sharedVerifier = null;
      setError(e instanceof Error ? e.message : "Sign-in failed.");
    } finally {
      setBusy(false);
    }
  }

  const submitLabel = () => {
    if (!FIREBASE_API_KEY) return "Sign in";
    return step === "phone" ? "Send code" : "Sign in";
  };

  return (
    <form
      noValidate
      onSubmit={(e) => {
        e.preventDefault();
        if (step === "phone") void startOtp();
        else void verifyOtp();
      }}
      className="flex flex-col gap-4"
    >
      <FieldGroup className="gap-4">
        {step === "phone" ? (
          <Field className="gap-1.5">
            <FieldLabel htmlFor="admin-phone">Phone number</FieldLabel>
            <Input
              id="admin-phone"
              value={phone}
              onChange={(e) => setPhone(e.target.value)}
              inputMode="tel"
              autoComplete="tel"
              placeholder="+91 93021 90067"
              className="tabular-nums"
            />
            <FieldDescription>Sign in with the admin phone number.</FieldDescription>
          </Field>
        ) : (
          <Field className="gap-1.5">
            <FieldLabel htmlFor="admin-otp">6-digit code</FieldLabel>
            <InputOTP
              id="admin-otp"
              value={code}
              onChange={(value: string) => setCode(value.replace(/\D/g, "").slice(0, 6))}
              maxLength={6}
            >
              <InputOTPGroup>
                <InputOTPSlot index={0} />
                <InputOTPSeparator />
                <InputOTPSlot index={1} />
                <InputOTPSlot index={2} />
                <InputOTPSeparator />
                <InputOTPSlot index={3} />
                <InputOTPSlot index={4} />
                <InputOTPSlot index={5} />
              </InputOTPGroup>
            </InputOTP>
            {info ? <FieldDescription>{info}</FieldDescription> : null}
          </Field>
        )}
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
      {step === "otp" ? (
        <Button
          type="button"
          variant="ghost"
          size="sm"
          className="self-start"
          onClick={() => {
            setStep("phone");
            setCode("");
          }}
        >
          Use a different number
        </Button>
      ) : null}
      <Button className="w-full" type="submit" disabled={busy}>
        {busy ? <Loader2 className="animate-spin" aria-hidden /> : null}
        {submitLabel()}
        <ArrowRight aria-hidden />
      </Button>
      <p className="flex items-center justify-center gap-1.5 text-muted-foreground text-xs">
        <ShieldCheck className="size-3.5" aria-hidden />
        Sessions are HttpOnly · role enforced on every request
      </p>
      <div id="recaptcha-container" className="hidden" />
    </form>
  );
}

function normalizePhone(input: string): string | null {
  const digits = input.replace(/\D/g, "");
  const last10 = digits.slice(-10);
  if (last10.length !== 10 || !/^[6-9]/.test(last10)) return null;
  return `+91${last10}`;
}
