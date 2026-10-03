/**
 * Money formatting: the wire carries integer paise; the server is the only
 * money computer — these helpers only format (ported logic from
 * apps/admin_app/src/lib/format.ts, adapted to rupee display).
 */

export function rupees(paise: number | null | undefined): string {
  const value = (paise ?? 0) / 100;
  return `₹${value.toLocaleString("en-IN", { maximumFractionDigits: 2 })}`;
}

export function num(value: number | null | undefined): string {
  return (value ?? 0).toLocaleString("en-IN");
}

export function pct(value: number | null | undefined): string {
  if (value == null) return "—";
  return `${Math.round(value)}%`;
}

export function dateTime(iso: string | null | undefined): string {
  if (!iso) return "—";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "—";
  return d.toLocaleString("en-IN", {
    day: "2-digit",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
    hour12: true,
  });
}

export function phoneMasked(phone: string | null | undefined): string {
  if (!phone) return "—";
  const digits = phone.replace(/\D/g, "");
  const last10 = digits.slice(-10);
  if (last10.length !== 10) return phone;
  return `+91 ••••• ${last10.slice(-5)}`;
}
