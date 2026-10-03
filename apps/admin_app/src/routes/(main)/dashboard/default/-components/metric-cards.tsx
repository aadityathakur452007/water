import { useNavigate } from "@tanstack/react-router";

import { AlertTriangle, ClipboardList, Droplets, IndianRupee, TrendingDown, TrendingUp, Wallet } from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { Card, CardAction, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { num, rupees } from "@/lib/money";

import { useOverview } from "./overview-data";

export function MetricCards() {
  const { data, isError } = useOverview();
  const navigate = useNavigate();

  if (isError || !data) {
    return (
      <div className="grid grid-cols-1 gap-4 xl:grid-cols-4">
        <Card className="xl:col-span-4">
          <CardContent className="flex items-center gap-2 text-muted-foreground text-sm">
            <AlertTriangle className="size-4" aria-hidden />
            Overview unavailable — API unreachable or not signed in scope.
          </CardContent>
        </Card>
      </div>
    );
  }

  const { today, money } = data;
  const yesterdayOrders = data.series[data.series.length - 2]?.orders ?? today.orders;
  const delta = yesterdayOrders > 0 ? Math.round(((today.orders - yesterdayOrders) / yesterdayOrders) * 100) : 0;
  const deltaUp = delta >= 0;

  return (
    <div className="grid grid-cols-1 gap-4 *:data-[slot=card]:bg-linear-to-t *:data-[slot=card]:from-primary/5 *:data-[slot=card]:to-card *:data-[slot=card]:shadow-xs xl:grid-cols-4 dark:*:data-[slot=card]:bg-card">
      <Card>
        <CardHeader>
          <CardTitle>
            <div className="flex size-7 items-center justify-center rounded-lg border bg-muted text-muted-foreground">
              <IndianRupee className="size-4" />
            </div>
          </CardTitle>
          <CardDescription>GMV today</CardDescription>
          <CardAction>
            {today.on_time_pct != null ? (
              <Badge variant="outline">{`On-time ${Math.round(today.on_time_pct)}%`}</Badge>
            ) : null}
          </CardAction>
        </CardHeader>
        <CardContent className="flex flex-col gap-1">
          <div className="font-medium text-3xl tabular-nums leading-none tracking-tight">{rupees(today.gmv_paise)}</div>
          <p className="text-muted-foreground text-sm">
            {`${num(today.delivered)} delivered · ${num(today.cancelled)} cancelled · ${num(today.failed)} failed`}
          </p>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>
            <div className="flex size-7 items-center justify-center rounded-lg border bg-muted text-muted-foreground">
              <ClipboardList className="size-4" />
            </div>
          </CardTitle>
          <CardDescription>Orders today</CardDescription>
          <CardAction>
            <Badge variant={deltaUp ? "default" : "destructive"}>
              {deltaUp ? <TrendingUp className="size-3" /> : <TrendingDown className="size-3" />}
              {`${deltaUp ? "+" : ""}${delta}%`}
            </Badge>
          </CardAction>
        </CardHeader>
        <CardContent className="flex flex-col gap-1">
          <div className="font-medium text-3xl tabular-nums leading-none tracking-tight">{num(today.orders)}</div>
          <p className="text-muted-foreground text-sm">
            {`UPI ${num(today.upi_orders)} · COD ${num(today.cod_orders)}`}
          </p>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>
            <div className="flex size-7 items-center justify-center rounded-lg border bg-muted text-muted-foreground">
              <Droplets className="size-4" />
            </div>
          </CardTitle>
          <CardDescription>Deposits held</CardDescription>
          <CardAction>
            <Badge variant="outline">{`${num(money.jars_held)} jars at homes`}</Badge>
          </CardAction>
        </CardHeader>
        <CardContent className="flex flex-col gap-1">
          <div className="font-medium text-3xl tabular-nums leading-none tracking-tight">
            {rupees(money.deposit_liability_paise)}
          </div>
          <p className="text-muted-foreground text-sm">Refundable ₹150 per jar liability</p>
        </CardContent>
      </Card>

      <Card>
        <CardAction>
          <Wallet className="size-4 text-muted-foreground" />
        </CardAction>
        <CardHeader>
          <CardTitle>Dues receivable</CardTitle>
          <CardDescription>Customer credit outstanding</CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-1">
          <div className="font-medium text-3xl tabular-nums leading-none tracking-tight">
            {rupees(money.dues_paise)}
          </div>
          <div className="flex gap-2">
            <button
              type="button"
              onClick={() => navigate({ to: "/dashboard/orders" })}
              className="text-muted-foreground text-xs underline-offset-2 hover:underline"
            >
              View orders
            </button>
            <span aria-hidden>·</span>
            <button
              type="button"
              onClick={() => navigate({ to: "/dashboard/ledger" })}
              className="text-muted-foreground text-xs underline-offset-2 hover:underline"
            >
              Jar ledger
            </button>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
