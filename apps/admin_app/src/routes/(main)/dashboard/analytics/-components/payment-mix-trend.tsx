import { format, parseISO } from "date-fns";
import { Area, AreaChart, CartesianGrid, XAxis } from "recharts";

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import {
  type ChartConfig,
  ChartContainer,
  ChartLegend,
  ChartLegendContent,
  ChartTooltip,
  ChartTooltipContent,
} from "@/components/ui/chart";

import { useOverview } from "../../default/-components/overview-data";

const chartConfig = {
  upi: { label: "UPI orders", color: "var(--chart-1)" },
  cod: { label: "COD orders", color: "var(--chart-2)" },
} satisfies ChartConfig;

/** FR-33: UPI-vs-COD split, tracked daily — the payment-mix drift signal. */
export function PaymentMixTrend() {
  const { data } = useOverview();
  const chartData =
    data?.series.map((p) => ({
      date: p.day,
      upi: p.upi_orders,
      cod: p.cod_orders,
    })) ?? [];

  return (
    <Card>
      <CardHeader>
        <CardTitle>UPI vs COD — daily mix</CardTitle>
        <CardDescription>Collection-method drift signals cash-handling load (F7)</CardDescription>
      </CardHeader>
      <CardContent>
        <ChartContainer config={chartConfig} className="aspect-auto h-56 w-full">
          <AreaChart data={chartData} margin={{ left: 8, right: 8 }} stackOffset="expand">
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
            <ChartLegend content={<ChartLegendContent />} />
            <Area
              dataKey="upi"
              type="monotone"
              stackId="mix"
              fill="var(--color-upi)"
              stroke="var(--color-upi)"
              fillOpacity={0.7}
            />
            <Area
              dataKey="cod"
              type="monotone"
              stackId="mix"
              fill="var(--color-cod)"
              stroke="var(--color-cod)"
              fillOpacity={0.7}
            />
          </AreaChart>
        </ChartContainer>
      </CardContent>
    </Card>
  );
}
