"use client";

import { Suspense, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import Link from "next/link";
import { ArrowRight, Droplets, Loader2, ShieldCheck } from "lucide-react";
import { clsx } from "clsx";

type Step = "phone" | "otp";

// Firebase phone auth is loaded from the CDN here so the panel stays a thin BFF
// (no firebase-js-sdk dependency; the worker verifies the ID token server-side).
declare global {
  interface Window {
    firebase?: {
      initializeApp: (cfg: Record<string, string>) => unknown;
      auth: () => {
        signInWithPhoneNumber: (
          phone: string,
          verifier: unknown,
        ) => Promise<{ confirm: (code: string) => Promise<{ getIdToken: () => Promise<string> }> }>;
      };
      RecaptchaVerifier: new (
        el: string | HTMLElement,
        opts: Record<string, unknown>,
      ) => unknown;
    };
  }
}

const FIREBASE_CONFIG = {
  apiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY ?? "",
  authDomain: process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN ?? "",
  projectId: process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID ?? "",
};

export default function LoginPage() {
  return (
    <Suspense>
      <LoginForm />
    </Suspense>
  );
}

function LoginForm() {
  const router = useRouter();
  const params = useSearchParams();
  const next = params.get("next") ?? "/admin";

  const [step, setStep] = useState<Step>("phone");
  const [phone, setPhone] = useState("+91 ");
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [info, setInfo] = useState<string | null>(null);

  async function startOtp() {
    const normalized = normalizePhone(phone);
    if (!normalized) {
      setError("Enter a valid Indian mobile number.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const res = await fetch("/api/auth/otp", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ action: "start", phone: normalized }),
      });
      const body = (await res.json()) as { error?: { message: string }; sent_to_masked?: string };
      if (!res.ok) throw new Error(body.error?.message ?? "Could not send the code.");
      setInfo(body.sent_to_masked ? `Code sent to ${body.sent_to_masked}` : "Code sent");
      setPhone(normalized);
      setStep("otp");
    } catch (e) {
      setError(e instanceof Error ? e.message : "Could not send the code.");
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
      // Local/dev mode: when Firebase web SDK is not configured, the worker's
      // dev verifier accepts the raw code as the token (StubPhoneVerifier path).
      let idToken = code.trim();
      if (FIREBASE_CONFIG.apiKey && typeof window !== "undefined" && window.firebase) {
        if (!document.getElementById("recaptcha-container")) {
          const el = document.createElement("div");
          el.id = "recaptcha-container";
          document.body.appendChild(el);
        }
        const app = window.firebase.initializeApp(FIREBASE_CONFIG);
        void app;
        const auth = window.firebase.auth();
        const verifier = new window.firebase.RecaptchaVerifier("recaptcha-container", { size: "invisible" });
        const normalized = normalizePhone(phone);
        if (!normalized) throw new Error("Enter a valid Indian mobile number.");
        const confirmation = await auth.signInWithPhoneNumber(normalized, verifier);
        const cred = await confirmation.confirm(code.trim());
        idToken = await cred.getIdToken();
      }
      const res = await fetch("/api/auth/otp", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ action: "verify", firebase_id_token: idToken, device_id: "admin-web" }),
      });
      const body = (await res.json()) as { error?: { code: string; message: string } };
      if (!res.ok) throw new Error(body.error?.message ?? "Sign-in failed.");
      router.replace(next);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Sign-in failed.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="flex min-h-[100dvh] items-center justify-center bg-canvas px-4">
      <div className="w-full max-w-sm">
        <div className="rise mb-6 flex flex-col items-center gap-2 text-center">
          <span className="flex size-11 items-center justify-center rounded-xl bg-accent text-white">
            <Droplets className="size-5" aria-hidden />
          </span>
          <h1 className="text-lg font-semibold tracking-tight text-ink">Shodasha Super Admin</h1>
          <p className="text-sm text-steel">Sign in with the admin phone number</p>
        </div>

        <div className="rise rounded-2xl border border-line bg-surface p-6 shadow-card" style={{ ["--stagger" as string]: 1 }}>
          {step === "phone" ? (
            <>
              <label htmlFor="phone" className="text-xs font-medium text-steel">
                Phone number
              </label>
              <input
                id="phone"
                value={phone}
                onChange={(e) => setPhone(e.target.value)}
                onKeyDown={(e) => e.key === "Enter" && startOtp()}
                inputMode="tel"
                autoComplete="tel"
                className="tnum mt-1.5 h-11 w-full rounded-lg border border-line bg-canvas px-3 text-sm text-ink focus:border-accent"
                placeholder="+91 98765 43210"
              />
              <button
                type="button"
                onClick={startOtp}
                disabled={busy}
                className="mt-4 inline-flex h-11 w-full items-center justify-center gap-2 rounded-lg bg-accent text-sm font-medium text-white transition-colors hover:bg-accent/90 disabled:opacity-60"
              >
                {busy ? <Loader2 className="size-4 animate-spin" aria-hidden /> : null}
                Send code
                <ArrowRight className="size-4" aria-hidden />
              </button>
            </>
          ) : (
            <>
              <label htmlFor="otp" className="text-xs font-medium text-steel">
                6-digit code
              </label>
              <input
                id="otp"
                value={code}
                onChange={(e) => setCode(e.target.value.replace(/\D/g, "").slice(0, 6))}
                onKeyDown={(e) => e.key === "Enter" && verifyOtp()}
                inputMode="numeric"
                autoComplete="one-time-code"
                className="tnum mt-1.5 h-11 w-full rounded-lg border border-line bg-canvas px-3 text-lg tracking-[0.4em] text-ink focus:border-accent"
                placeholder="••••••"
              />
              {info ? <p className="mt-1.5 text-xs text-steel">{info}</p> : null}
              <button
                type="button"
                onClick={verifyOtp}
                disabled={busy}
                className="mt-4 inline-flex h-11 w-full items-center justify-center gap-2 rounded-lg bg-accent text-sm font-medium text-white transition-colors hover:bg-accent/90 disabled:opacity-60"
              >
                {busy ? <Loader2 className="size-4 animate-spin" aria-hidden /> : null}
                Sign in
              </button>
              <button
                type="button"
                onClick={() => {
                  setStep("phone");
                  setCode("");
                }}
                className="mt-2 h-9 w-full rounded-lg text-xs font-medium text-steel hover:text-ink"
              >
                Use a different number
              </button>
            </>
          )}
          {error ? (
            <p role="alert" className="mt-3 rounded-lg bg-bad-soft px-3 py-2 text-xs font-medium text-bad">
              {error}
            </p>
          ) : null}
          <div id="recaptcha-container" className={clsx("mt-2", "hidden")} />
        </div>

        <p className="mt-5 flex items-center justify-center gap-1.5 text-[11px] text-faint">
          <ShieldCheck className="size-3.5" aria-hidden />
          Sessions are HttpOnly · role enforced on every request
        </p>
        <p className="mt-2 text-center text-[11px] text-faint">
          <Link href="/admin" className="underline decoration-line hover:text-steel">
            Go to panel
          </Link>
        </p>
      </div>
    </main>
  );
}

function normalizePhone(input: string): string | null {
  const digits = input.replace(/\D/g, "");
  const last10 = digits.slice(-10);
  if (last10.length !== 10 || !/^[6-9]/.test(last10)) return null;
  return `+91${last10}`;
}
