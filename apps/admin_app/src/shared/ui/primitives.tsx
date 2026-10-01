import { clsx } from "clsx";
import type { ReactNode } from "react";

/** Card — pure surface, whisper border + shadow. Used only where elevation communicates hierarchy. */
export function Card({
  children,
  className,
  stagger,
}: {
  children: ReactNode;
  className?: string;
  stagger?: number;
}) {
  return (
    <section
      style={stagger !== undefined ? { ["--stagger" as string]: stagger } : undefined}
      className={clsx(
        "rise rounded-2xl border border-line bg-surface shadow-card",
        className,
      )}
    >
      {children}
    </section>
  );
}

export function CardHeader({ title, hint, action }: { title: string; hint?: string; action?: ReactNode }) {
  return (
    <div className="flex items-center justify-between gap-3 border-b border-line-soft px-5 py-4">
      <div>
        <h2 className="text-sm font-semibold tracking-tight text-ink">{title}</h2>
        {hint ? <p className="mt-0.5 text-xs text-steel">{hint}</p> : null}
      </div>
      {action}
    </div>
  );
}

/** KPI stat — the number is the hero: mono, tabular, big. Delta is optional context. */
export function Stat({
  label,
  value,
  sub,
  tone = "default",
  wide,
  stagger,
}: {
  label: string;
  value: ReactNode;
  sub?: ReactNode;
  tone?: "default" | "good" | "warn" | "bad";
  wide?: boolean;
  stagger?: number;
}) {
  const toneClass = {
    default: "text-ink",
    good: "text-good",
    warn: "text-warn",
    bad: "text-bad",
  }[tone];
  return (
    <Card className={clsx("px-5 py-4", wide && "sm:col-span-2")} stagger={stagger}>
      <p className="text-xs font-medium uppercase tracking-wide text-steel">{label}</p>
      <p className={clsx("tnum mt-1.5 text-2xl font-semibold tracking-tight", toneClass)}>{value}</p>
      {sub ? <div className="mt-1 text-xs text-steel">{sub}</div> : null}
    </Card>
  );
}

type BadgeTone = "neutral" | "accent" | "good" | "warn" | "bad";

const BADGE_STYLES: Record<BadgeTone, string> = {
  neutral: "bg-line-soft text-steel",
  accent: "bg-accent-soft text-accent",
  good: "bg-good-soft text-good",
  warn: "bg-warn-soft text-warn",
  bad: "bg-bad-soft text-bad",
};

export function Badge({ tone = "neutral", children }: { tone?: BadgeTone; children: ReactNode }) {
  return (
    <span
      className={clsx(
        "inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-medium leading-4",
        BADGE_STYLES[tone],
      )}
    >
      {children}
    </span>
  );
}

/** Order-state → badge tone (single source used by every table). */
export function StateBadge({ state }: { state: string }) {
  const tone: BadgeTone =
    state === "delivered" ? "good"
    : state === "cancelled" || state === "rejected" || state === "failed" ? "bad"
    : state === "dispatched" || state === "assigned" ? "accent"
    : state === "placed" ? "warn"
    : "neutral";
  return <Badge tone={tone}>{state}</Badge>;
}

export function PaymentBadge({ status }: { status: string }) {
  const tone: BadgeTone =
    status === "paid_upi" || status === "paid_cash" || status === "paid" ? "good"
    : status === "partial_dues" || status === "partial" ? "warn"
    : status === "failed" ? "bad"
    : "neutral";
  return <Badge tone={tone}>{status.replace(/_/g, " ")}</Badge>;
}

export function PageHeader({
  title,
  description,
  actions,
}: {
  title: string;
  description?: string;
  actions?: ReactNode;
}) {
  return (
    <div className="flex flex-wrap items-end justify-between gap-3">
      <div>
        <h1 className="text-xl font-semibold tracking-tight text-ink">{title}</h1>
        {description ? <p className="mt-1 max-w-2xl text-sm text-steel">{description}</p> : null}
      </div>
      {actions ? <div className="flex items-center gap-2">{actions}</div> : null}
    </div>
  );
}

/** Skeleton shimmer matching the layout (no spinners). */
export function SkeletonRows({ rows = 6, cols = 5 }: { rows?: number; cols?: number }) {
  return (
    <div className="divide-y divide-line-soft">
      {Array.from({ length: rows }).map((_, r) => (
        <div key={r} className="flex gap-4 px-5 py-3.5">
          {Array.from({ length: cols }).map((_, c) => (
            <div key={c} className="skeleton h-4 flex-1" />
          ))}
        </div>
      ))}
    </div>
  );
}

export function SkeletonBlock({ className }: { className?: string }) {
  return <div className={clsx("skeleton", className)} />;
}

/** Composed empty state — never a bare "no data". */
export function EmptyState({
  icon,
  title,
  hint,
  action,
}: {
  icon: ReactNode;
  title: string;
  hint: string;
  action?: ReactNode;
}) {
  return (
    <div className="flex flex-col items-center gap-2 px-6 py-14 text-center">
      <div className="flex size-11 items-center justify-center rounded-full bg-line-soft text-steel">
        {icon}
      </div>
      <p className="text-sm font-medium text-ink">{title}</p>
      <p className="max-w-sm text-xs leading-relaxed text-steel">{hint}</p>
      {action}
    </div>
  );
}

export function ErrorState({ message, hint }: { message: string; hint?: string }) {
  return (
    <div className="rounded-xl border border-bad/30 bg-bad-soft/50 px-4 py-3 text-sm text-bad">
      <p className="font-medium">{message}</p>
      {hint ? <p className="mt-0.5 text-xs opacity-80">{hint}</p> : null}
    </div>
  );
}
