import {
  Activity,
  BadgeIndianRupee,
  CalendarCheck,
  Droplets,
  ReceiptText,
  TrendingUp,
  Users,
  Wallet,
} from "lucide-react";

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { useAdminQuery } from "@/hooks/use-admin-api";
import type { Page, UserRow } from "@/lib/admin-types";
import { num, pct, rupees } from "@/lib/money";

import { useOverview } from "../../default/-components/overview-data";

/** FR-33 KPI matrix — the four research pillars in one strip (F1/F2/F3/F7). */
export function KpiMatrix() {
  const { data } = useOverview();
  // Phase 6 S6.3: directory totals ride the users list read (limit=1 keeps
  // the payload tiny — counts are full-book aggregates, not page slices).
  const { data: users } = useAdminQuery<Page<UserRow>>("/v1/admin/users?limit=1");
  const customerCount = users?.counts?.user;
  if (!data) return null;

  const series = data.series;
  const gmv14 = series.reduce((a, p) => a + p.gmv_paise, 0);
  const orders14 = series.reduce((a, p) => a + p.orders, 0);
  const delivered14 = series.reduce((a, p) => a + p.delivered, 0);
  const failed14 = series.reduce((a, p) => a + p.failed, 0);
  const cancelled14 = series.reduce((a, p) => a + p.cancelled, 0);
  const aov = orders14 > 0 ? Math.round(gmv14 / orders14) : 0;
  const fulfilRate = orders14 > 0 ? (delivered14 / orders14) * 100 : null;
  const onTime = series.filter((p) => p.on_time_pct != null);
  const onTimeAvg = onTime.length ? onTime.reduce((a, p) => a + (p.on_time_pct ?? 0), 0) / onTime.length : null;

  const cards = [
    {
      icon: BadgeIndianRupee,
      label: "GMV — 14 days",
      value: rupees(gmv14),
      hint: `${num(orders14)} orders · AOV ${rupees(aov)}`,
    },
    {
      icon: TrendingUp,
      label: "Fulfilment rate",
      value: pct(fulfilRate),
      hint: `${num(delivered14)} delivered · ${num(failed14)} failed · ${num(cancelled14)} cancelled`,
    },
    {
      icon: CalendarCheck,
      label: "On-time adherence",
      value: pct(onTimeAvg),
      hint: "avg across windowed days (30-min promise, F4)",
    },
    {
      icon: Wallet,
      label: "Dues receivable",
      value: rupees(data.money.dues_paise),
      hint: "carry-forward credit (F31 day-close discipline)",
    },
    {
      icon: Droplets,
      label: "Deposit liability",
      value: rupees(data.money.deposit_liability_paise),
      hint: `${num(data.money.jars_held)} jars at homes (F2 jar integrity)`,
    },
    {
      icon: ReceiptText,
      label: "Payouts pending",
      value: rupees(data.money.payouts_pending_paise),
      hint: `${rupees(data.money.payouts_paid_paise)} settled`,
    },
    {
      icon: Users,
      label: "Customers",
      value: customerCount == null ? "—" : num(customerCount),
      hint: "user-role directory total (full book)",
    },
    {
      icon: Activity,
      label: "Collections split",
      value: `UPI ${num(series.reduce((a, p) => a + p.upi_orders, 0))} · COD ${num(series.reduce((a, p) => a + p.cod_orders, 0))}`,
      hint: `${rupees(data.money.collected_upi_paise)} upi · ${rupees(data.money.collected_cod_paise)} cod`,
    },
  ];

  return (
    <div className="grid grid-cols-1 gap-4 *:data-[slot=card]:bg-linear-to-t *:data-[slot=card]:from-primary/5 *:data-[slot=card]:to-card *:data-[slot=card]:shadow-xs sm:grid-cols-2 xl:grid-cols-4 dark:*:data-[slot=card]:bg-card">
      {cards.map((c) => (
        <Card key={c.label}>
          <CardHeader>
            <CardTitle>
              <div className="flex size-7 items-center justify-center rounded-lg border bg-muted text-muted-foreground">
                <c.icon className="size-4" />
              </div>
            </CardTitle>
            <CardDescription>{c.label}</CardDescription>
          </CardHeader>
          <CardContent className="flex flex-col gap-1">
            <div className="font-medium text-2xl tabular-nums leading-none tracking-tight">{c.value}</div>
            <p className="text-muted-foreground text-sm">{c.hint}</p>
          </CardContent>
        </Card>
      ))}
    </div>
  );
}
