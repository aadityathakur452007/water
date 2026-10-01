import { clsx } from "clsx";
import Link from "next/link";
import { ArrowDownRight, ArrowUpRight } from "lucide-react";
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

/** Inline trend for a KPI card — static SVG (no axes, no animation), reduced-motion safe by nature. */
export function Sparkline({
  points,
  tone = "accent",
}: {
  points: number[];
  tone?: "accent" | "good" | "warn" | "bad";
}) {
  if (points.length < 2) return null;
  const W = 96;
  const H = 28;
  const PAD = 2;
  const min = Math.min(...points);
  const max = Math.max(...points);
  const span = max - min || 1;
  const step = (W - PAD * 2) / (points.length - 1);
  const coords = points.map(
    (p, i) => [PAD + i * step, H - PAD - ((p - min) / span) * (H - PAD * 2)] as const,
  );
  const line = coords.map(([x, y]) => `${x.toFixed(1)},${y.toFixed(1)}`).join(" ");
  const [lastX, lastY] = coords[coords.length - 1];
  const stroke = {
    accent: "var(--color-accent)",
    good: "var(--color-good)",
    warn: "var(--color-warn)",
    bad: "var(--color-bad)",
  }[tone];
  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="h-7 w-24 shrink-0" aria-hidden focusable="false">
      <polyline
        points={line}
        fill="none"
        stroke={stroke}
        strokeWidth="1.5"
        strokeLinejoin="round"
        strokeLinecap="round"
      />
      <circle cx={lastX} cy={lastY} r="1.8" fill={stroke} />
    </svg>
  );
}

/** Delta with honest sentiment: direction (arrow) is decoupled from good/bad (color).
 *  Rising dues must read red-up, falling dues green-down — per metric, not globally. */
export type StatDelta = { pct: number | null; window: string; goodWhen?: "up" | "down" };

/** Non-value states of a live KPI card — a card must never silently lie. */
export type StatState =
  | { kind: "error"; message: string; onRetry: () => void }
  | { kind: "empty"; message: string };

/** KPI stat — the number is the hero: mono, tabular, big. Doctrine (SaaSUI 2026):
 *  value + delta vs an explicit window + sparkline for shape + drill-in link,
 *  with skeleton / genuine-zero / empty / in-card-error states designed on purpose. */
export function Stat({
  label,
  value,
  sub,
  tone = "default",
  wide,
  stagger,
  href,
  delta,
  spark,
  sparkTone = "accent",
  state,
}: {
  label: string;
  value: ReactNode;
  sub?: ReactNode;
  tone?: "default" | "good" | "warn" | "bad";
  wide?: boolean;
  stagger?: number;
  /** Card-as-doorway: when set, the whole card links to the surface behind the number. */
  href?: string;
  delta?: StatDelta;
  spark?: number[];
  sparkTone?: "accent" | "good" | "warn" | "bad";
  state?: StatState;
}) {
  const toneClass = {
    default: "text-ink",
    good: "text-good",
    warn: "text-warn",
    bad: "text-bad",
  }[tone];

  let deltaNode: ReactNode = null;
  if (delta) {
    if (delta.pct === null || Number.isNaN(delta.pct)) {
      deltaNode = <span className="text-steel">{delta.window}</span>;
    } else {
      const good = delta.goodWhen === "down" ? delta.pct <= 0 : delta.pct >= 0;
      deltaNode = (
        <span className={good ? "text-good" : "text-bad"}>
          {delta.pct >= 0 ? (
            <ArrowUpRight className="mr-0.5 inline size-3" aria-hidden />
          ) : (
            <ArrowDownRight className="mr-0.5 inline size-3" aria-hidden />
          )}
          {Math.abs(Math.round(delta.pct))}% {delta.window}
        </span>
      );
    }
  }

  const body = (
    <>
      <div className="flex items-start justify-between gap-2">
        <p className="text-xs font-medium uppercase tracking-wide text-steel">{label}</p>
        {spark && !state ? <Sparkline points={spark} tone={sparkTone} /> : null}
      </div>
      {state?.kind === "error" ? (
        <div className="mt-1.5">
          <p className="text-xs text-bad">{state.message}</p>
          <button
            type="button"
            onClick={state.onRetry}
            className="mt-1.5 inline-flex h-7 items-center rounded-md border border-line px-2.5 text-xs font-medium text-ink transition-colors hover:bg-canvas"
          >
            Retry
          </button>
        </div>
      ) : (
        <>
          <div className={clsx("tnum mt-1.5 text-2xl font-semibold tracking-tight", toneClass)}>
            {state?.kind === "empty" ? "—" : value}
          </div>
          <div className="mt-1 space-y-0.5 text-xs text-steel">
            {deltaNode}
            {state?.kind === "empty" ? <span className="text-steel">{state.message}</span> : sub}
          </div>
        </>
      )}
    </>
  );

  const shell = clsx("px-5 py-4", wide && "sm:col-span-2");
  const style = stagger !== undefined ? { ["--stagger" as string]: stagger } : undefined;

  if (href && state?.kind !== "error") {
    return (
      <Link
        href={href}
        style={style}
        className={clsx(
          "rise block rounded-2xl border border-line bg-surface shadow-card transition-colors hover:border-ink/25",
          shell,
        )}
      >
        {body}
      </Link>
    );
  }
  return (
    <Card className={shell} stagger={stagger}>
      {body}
    </Card>
  );
}

type BadgeTone = "neutral" | "accent" | "good" | "warn" | "bad";

const BADGE_STYLES: Record<BadgeTone, string> = {
  neutral: "bg-line-soft text-ink-soft",
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
