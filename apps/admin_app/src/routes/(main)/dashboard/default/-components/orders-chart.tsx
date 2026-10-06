import { format, parseISO } from "date-fns";
import { TrendingUp } from "lucide-react";
import { Area, AreaChart, CartesianGrid, XAxis } from "recharts";

import {
  Card,
  CardAction,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { type ChartConfig, ChartContainer, ChartTooltip, ChartTooltipContent } from "@/components/ui/chart";
import { num, rupees } from "@/lib/money";

import { useOverview } from "./overview-data";

const chartConfig = {
  orders: { label: "Orders", color: "var(--chart-1)" },
  gmv: { label: "GMV (₹'00)", color: "var(--chart-2)" },
} satisfies ChartConfig;

export function OrdersChart() {
  const { data } = useOverview();
  const chartData =
    data?.series.map((p) => ({
      date: p.day,
      orders: p.orders,
      gmv: Math.round(p.gmv_paise / 10000),
    })) ?? [];

  const first = data?.series[0]?.orders ?? 0;
  const last = data?.today.orders ?? 0;
  const up = last >= first;

  return (
    <Card>
      <CardHeader>
        <CardTitle>Orders & GMV — last 14 days</CardTitle>
        <CardDescription>
          Daily order count with revenue plotted in ₹ hundreds (axis) — totals below and KPI cards show full ₹
        </CardDescription>
        <CardAction>
          <span className="text-muted-foreground text-sm tabular-nums">{`Latest ${num(last)} orders`}</span>
        </CardAction>
      </CardHeader>
      <CardContent>
        <ChartContainer config={chartConfig} className="aspect-auto h-64 w-full">
          <AreaChart data={chartData} margin={{ left: 8, right: 8 }}>
            <defs>
              <linearGradient id="fillOrders" x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%" stopColor="var(--color-orders)" stopOpacity={0.8} />
                <stop offset="95%" stopColor="var(--color-orders)" stopOpacity={0.1} />
              </linearGradient>
              <linearGradient id="fillGmv" x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%" stopColor="var(--color-gmv)" stopOpacity={0.8} />
                <stop offset="95%" stopColor="var(--color-gmv)" stopOpacity={0.1} />
              </linearGradient>
            </defs>
            <CartesianGrid vertical={false} />
            <XAxis
              dataKey="date"
              tickLine={false}
              axisLine={false}
              tickMargin={8}
              tickFormatter={(value: string) => format(parseISO(value), "d MMM")}
              minTickGap={24}
            />
            <ChartTooltip cursor={false} content={<ChartTooltipContent indicator="dot" />} />
            <Area dataKey="gmv" type="monotone" fill="url(#fillGmv)" stroke="var(--color-gmv)" />
            <Area dataKey="orders" type="monotone" fill="url(#fillOrders)" stroke="var(--color-orders)" />
          </AreaChart>
        </ChartContainer>
      </CardContent>
      <CardFooter>
        <span className="flex items-center gap-2 text-muted-foreground text-sm">
          {up ? <TrendingUp className="size-4" /> : null}
          {`14-day GMV ${rupees((data?.series ?? []).reduce((a, p) => a + p.gmv_paise, 0))}`}
        </span>
      </CardFooter>
    </Card>
  );
}
