import { ArrowDownLeft, ArrowUpRight, Banknote, Droplets, Landmark, Wallet } from "lucide-react";

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { num, rupees } from "@/lib/money";

import { useOverview } from "../../default/-components/overview-data";

/** Money command strip — collections in, obligations out (F7 / FR-30). */
export function MoneyCards() {
  const { data } = useOverview();
  if (!data) return null;
  const m = data.money;

  const cards = [
    {
      icon: Landmark,
      label: "Collected — UPI",
      value: rupees(m.collected_upi_paise),
      hint: "zero-fee own-bank QR settlements",
      tone: "text-emerald-600",
    },
    {
      icon: Banknote,
      label: "Collected — COD cash",
      value: rupees(m.collected_cod_paise),
      hint: "day-close custody chain (leak watch, F6/F7)",
      tone: "text-amber-600",
    },
    {
      icon: Wallet,
      label: "Dues receivable",
      value: rupees(m.dues_paise),
      hint: "ledger total — follow-up list shows top 200",
      tone: "text-destructive",
    },
    {
      icon: Droplets,
      label: "Deposit liability",
      value: rupees(m.deposit_liability_paise),
      hint: `${num(m.jars_held)} jars at homes — refundable ₹150/jar`,
      tone: "text-sky-600",
    },
    {
      icon: ArrowUpRight,
      label: "Payouts paid",
      value: rupees(m.payouts_paid_paise),
      hint: "vendor settlements done",
      tone: "",
    },
    {
      icon: ArrowDownLeft,
      label: "Payouts pending",
      value: rupees(m.payouts_pending_paise),
      hint: "settle at day-close",
      tone: "text-amber-600",
    },
  ];

  return (
    <div className="grid grid-cols-1 gap-4 *:data-[slot=card]:bg-linear-to-t *:data-[slot=card]:from-primary/5 *:data-[slot=card]:to-card *:data-[slot=card]:shadow-xs sm:grid-cols-2 xl:grid-cols-3 dark:*:data-[slot=card]:bg-card">
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
            <div className={`font-medium text-2xl tabular-nums leading-none tracking-tight ${c.tone}`}>{c.value}</div>
            <p className="text-muted-foreground text-sm">{c.hint}</p>
          </CardContent>
        </Card>
      ))}
    </div>
  );
}
