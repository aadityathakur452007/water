"use client";

import { useState } from "react";
import { clsx } from "clsx";
import { Loader2 } from "lucide-react";

/**
 * Danger-confirm button used for every destructive action (block, cancel-override,
 * write-off): opens an inline confirm panel requiring a typed reason (min 3 chars).
 * Mirrors the backend rule: human-confirmed, never automatic (ADR-016).
 */
export function ConfirmAction({
  label,
  title,
  description,
  confirmLabel,
  tone = "danger",
  requireReason = true,
  onConfirm,
}: {
  label: string;
  title: string;
  description: string;
  confirmLabel: string;
  tone?: "danger" | "accent";
  requireReason?: boolean;
  onConfirm: (reason: string) => Promise<string | null>;
}) {
  const [open, setOpen] = useState<number | null>(null); // reopen counter: reset-on-close without effects
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  function toggle() {
    if (open === null) {
      setOpen(1);
      return;
    }
    // Closing: reset fields for the next open (no effect needed).
    setOpen(null);
    setReason("");
    setError(null);
    setResult(null);
  }

  async function submit() {
    if (requireReason && reason.trim().length < 3) {
      setError("Give a reason (at least 3 characters) — it is written to the audit log.");
      return;
    }
    setBusy(true);
    setError(null);
    const message = await onConfirm(reason.trim());
    setBusy(false);
    if (message) {
      setError(message);
      return;
    }
    setResult("Done");
    setTimeout(toggle, 700);
  }

  const toneBtn =
    tone === "danger"
      ? "bg-bad text-white hover:bg-bad/90"
      : "bg-accent text-white hover:bg-accent/90";

  return (
    <div className="relative inline-block text-left">
      <button
        type="button"
        onClick={toggle}
        className={clsx(
          "inline-flex h-8 items-center rounded-lg px-3 text-xs font-medium transition-colors",
          tone === "danger"
            ? "border border-bad/30 bg-bad-soft/60 text-bad hover:bg-bad-soft"
            : "border border-accent/30 bg-accent-soft text-accent hover:bg-accent-soft/70",
        )}
      >
        {label}
      </button>
      {open !== null ? (
        <div className="absolute right-0 z-30 mt-2 w-80 rounded-xl border border-line bg-surface p-4 shadow-card">
          <p className="text-sm font-semibold text-ink">{title}</p>
          <p className="mt-1 text-xs leading-relaxed text-steel">{description}</p>
          {requireReason ? (
            <textarea
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              rows={3}
              maxLength={500}
              placeholder="Reason (audit-logged)"
              className="mt-3 w-full resize-none rounded-lg border border-line bg-canvas px-3 py-2 text-sm text-ink placeholder:text-faint"
            />
          ) : null}
          {error ? <p className="mt-2 text-xs font-medium text-bad">{error}</p> : null}
          {result ? <p className="mt-2 text-xs font-medium text-good">{result}</p> : null}
          <div className="mt-3 flex justify-end gap-2">
            <button
              type="button"
              onClick={toggle}
              className="h-8 rounded-lg border border-line px-3 text-xs font-medium text-steel hover:bg-canvas"
            >
              Cancel
            </button>
            <button
              type="button"
              onClick={submit}
              disabled={busy}
              className={clsx(
                "inline-flex h-8 items-center gap-1.5 rounded-lg px-3 text-xs font-medium text-white disabled:opacity-60",
                toneBtn,
              )}
            >
              {busy ? <Loader2 className="size-3.5 animate-spin" aria-hidden /> : null}
              {confirmLabel}
            </button>
          </div>
        </div>
      ) : null}
    </div>
  );
}
