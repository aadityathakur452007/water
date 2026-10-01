"use client";

import Link from "next/link";
import {
  ArrowDownRight,
  ArrowUpRight,
  CircleDollarSign,
  ClipboardList,
  HandCoins,
  Inbox,
  Package,
  ShieldAlert,
} from "lucide-react";
import { Card, CardHeader, ErrorState, SkeletonBlock, SkeletonRows, Stat } from "@/shared/ui/primitives";
import { useCustody, useDunning, useOrders, useOverview } from "@/features/dashboard/api";
import { GmvOrdersChart, OnTimeChart, PaymentSplitChart, StatesChart } from "@/features/dashboard/charts";
import { num, paise, pct } from "@/lib/format";

export default function OverviewPage() {
  const { data, isLoading, isError, error } = useOverview(14);
  const custody = useCustody();
  const dunning = useDunning();
  const recentOrders = useOrders({ limit: 200 });

  if (isError) {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold tracking-tight text-ink">Overview</h1>
        <ErrorState
          message="Could not reach the Workers API."
          hint={`${(error as Error).message} — start it with uvicorn and set API_URL.`}
        />
      </div>
    );
  }

  const series = data?.series ?? [];
  const today = data?.today;
  const yesterday = series.length >= 2 ? series[series.length - 2] : undefined;
  const ordersDelta =
    today && yesterday && yesterday.orders > 0
      ? Math.round(((today.orders - yesterday.orders) / yesterday.orders) * 100)
      : null;
  const money = data?.money;

  const alerts: Array<{ href: string; icon: typeof ShieldAlert; label: string; value: string; tone: string }> = [];
  if ((custody.data?.data.length ?? 0) > 0) {
    alerts.push({
      href: "/admin/vendors",
      icon: HandCoins,
      label: `${custody.data?.data.length} vendor hands holding cash`,
      value: paise(custody.data?.data.reduce((s, r) => s + (r.in_hand ?? 0), 0) ?? 0),
      tone: "text-warn",
    });
  }
  if ((dunning.data?.data.length ?? 0) > 0) {
    alerts.push({
      href: "/admin/trust",
      icon: CircleDollarSign,
      label: `${dunning.data?.data.length} customers with dues`,
      value: paise(dunning.data?.data.reduce((s, r) => s + (r.dues ?? 0), 0) ?? 0),
      tone: "text-bad",
    });
  }

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold tracking-tight text-ink">Overview</h1>
          <p className="mt-1 text-sm text-steel">Everything moving through Shodasha, right now.</p>
        </div>
        <Link
          href="/admin/orders"
          className="inline-flex h-9 items-center gap-1.5 rounded-lg bg-accent px-3.5 text-sm font-medium text-white transition-colors hover:bg-accent/90"
        >
          <ClipboardList className="size-4" aria-hidden />
          Open order queue
        </Link>
      </div>

      {/* KPI row — asymmetric 2fr 1fr 1fr 1fr (bento, not a 3-card cliché) */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-5">
        <Stat
          label="Order value · today"
          value={isLoading ? <SkeletonBlock className="h-8 w-32" /> : paise(today?.gmv_paise)}
          sub={
            ordersDelta === null ? (
              "vs yesterday"
            ) : (
              <span className={ordersDelta >= 0 ? "text-good" : "text-bad"}>
                {ordersDelta >= 0 ? <ArrowUpRight className="mr-0.5 inline size-3" /> : <ArrowDownRight className="mr-0.5 inline size-3" />}
                {Math.abs(ordersDelta)}% vs yesterday
              </span>
            )
          }
          wide
          stagger={0}
        />
        <Stat
          label="Orders today"
          value={isLoading ? <SkeletonBlock className="h-8 w-16" /> : num(today?.orders)}
          sub={`${num(today?.delivered)} delivered`}
          stagger={1}
        />
        <Stat
          label="Jars with customers"
          value={isLoading ? <SkeletonBlock className="h-8 w-16" /> : num(money?.jars_held)}
          sub={`${paise(money?.deposit_liability_paise)} deposit held`}
          stagger={2}
        />
        <Stat
          label="Dues receivable"
          value={isLoading ? <SkeletonBlock className="h-8 w-20" /> : paise(money?.dues_paise)}
          sub={
            <span className={(money?.dues_paise ?? 0) > 0 ? "text-warn" : undefined}>
              collect on next delivery
            </span>
          }
          tone={(money?.dues_paise ?? 0) > 0 ? "warn" : "default"}
          stagger={3}
        />
        <Stat
          label="Vendor payouts"
          value={isLoading ? <SkeletonBlock className="h-8 w-24" /> : paise(money?.payouts_pending_paise)}
          sub={`${paise(money?.payouts_paid_paise)} paid all-time`}
          stagger={4}
        />
      </div>

      {/* Row 2 — 8/4 asymmetric */}
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-12">
        <Card className="lg:col-span-8" stagger={1}>
          <CardHeader
            title="Order value · last 14 days"
            hint="Frozen order totals in ₹ (server-computed, paise-accurate)"
          />
          {isLoading ? <SkeletonBlock className="m-4 h-56" /> : <GmvOrdersChart series={series} />}
        </Card>
        <Card className="lg:col-span-4" stagger={2}>
          <CardHeader title="Payment mix" hint="UPI vs cash orders per day" />
          {isLoading ? <SkeletonBlock className="m-4 h-56" /> : <PaymentSplitChart series={series} />}
        </Card>
      </div>

      {/* Row 3 — 7/5 */}
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-12">
        <Card className="lg:col-span-7" stagger={2}>
          <CardHeader title="On-time window adherence" hint="Delivered within the promised 30-min window" />
          {isLoading ? <SkeletonBlock className="m-4 h-48" /> : <OnTimeChart series={series} />}
        </Card>
        <Card className="lg:col-span-5" stagger={3}>
          <CardHeader title="Needs attention" hint="Live operational queues" />
          {isLoading ? (
            <SkeletonRows rows={3} cols={2} />
          ) : alerts.length === 0 ? (
            <div className="flex items-center gap-3 px-5 py-6 text-sm text-steel">
              <Inbox className="size-4 text-faint" aria-hidden />
              All clear — no custody, dues, or quality flags open.
            </div>
          ) : (
            <ul className="divide-y divide-line-soft">
              {alerts.map((a) => {
                const Icon = a.icon;
                return (
                  <li key={a.href + a.label}>
                    <Link
                      href={a.href}
                      className="flex items-center gap-3 px-5 py-3.5 transition-colors hover:bg-canvas"
                    >
                      <Icon className={`size-4 ${a.tone}`} aria-hidden />
                      <span className="flex-1 text-sm text-ink">{a.label}</span>
                      <span className="tnum text-sm font-medium text-ink">{a.value}</span>
                    </Link>
                  </li>
                );
              })}
            </ul>
          )}
        </Card>
      </div>

      {/* Row 4 — state mix + collection split */}
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-12">
        <Card className="lg:col-span-5" stagger={3}>
          <CardHeader title="Where orders stand" hint="Current page of the queue — live pipeline health" />
          {recentOrders.isLoading ? (
            <SkeletonBlock className="m-4 h-40" />
          ) : (
            <StatesChart
              data={Object.entries(
                (recentOrders.data?.data ?? []).reduce<Record<string, number>>((acc, o) => {
                  acc[o.state] = (acc[o.state] ?? 0) + 1;
                  return acc;
                }, {}),
              )
                .map(([state, count]) => ({ state, count }))
                .sort((a, b) => b.count - a.count)}
            />
          )}
        </Card>
        <Card className="lg:col-span-7" stagger={4}>
          <CardHeader title="Money collected" hint="Payments verified by the server (paise totals)" />
          <div className="grid grid-cols-2 gap-px bg-line-soft">
            <div className="bg-surface px-5 py-4">
              <p className="text-xs text-steel">UPI collected</p>
              <p className="tnum mt-1 text-lg font-semibold text-ink">{paise(money?.collected_upi_paise)}</p>
            </div>
            <div className="bg-surface px-5 py-4">
              <p className="text-xs text-steel">Cash collected</p>
              <p className="tnum mt-1 text-lg font-semibold text-ink">{paise(money?.collected_cod_paise)}</p>
            </div>
            <div className="bg-surface px-5 py-4">
              <p className="text-xs text-steel">Deposits held (liability)</p>
              <p className="tnum mt-1 text-lg font-semibold text-ink">{paise(money?.deposit_liability_paise)}</p>
            </div>
            <div className="bg-surface px-5 py-4">
              <p className="text-xs text-steel">Jars with customers</p>
              <p className="tnum mt-1 text-lg font-semibold text-ink">{num(money?.jars_held)}</p>
            </div>
          </div>
        </Card>
      </div>

      {/* Row 5 — reliability */}
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Card stagger={4}>
          <CardHeader title="Reliability today" hint="The two numbers customers actually feel" />
          <div className="grid grid-cols-2 gap-px bg-line-soft">
            <div className="bg-surface px-5 py-4">
              <p className="text-xs text-steel">On-time delivery</p>
              <p className="tnum mt-1 text-lg font-semibold text-good">{pct(today?.on_time_pct)}</p>
            </div>
            <div className="bg-surface px-5 py-4">
              <p className="text-xs text-steel">Failed / cancelled</p>
              <p className="tnum mt-1 text-lg font-semibold text-bad">
                {num((today?.failed ?? 0) + (today?.cancelled ?? 0))}
              </p>
            </div>
          </div>
        </Card>
      </div>

      <p className="flex items-center gap-1.5 pt-1 text-[11px] text-faint">
        <Package className="size-3" aria-hidden />
        Money is computed by the Workers API in integer paise — the panel only formats it.
      </p>
    </div>
  );
}
