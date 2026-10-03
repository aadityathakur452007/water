import { format, parseISO } from "date-fns";
import { CartesianGrid, Line, LineChart, XAxis } from "recharts";

import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "@/components/ui/card";
import { type ChartConfig, ChartContainer, ChartTooltip, ChartTooltipContent } from "@/components/ui/chart";
import { pct } from "@/lib/money";

import { useOverview } from "./overview-data";

const chartConfig = {
  on_time: { label: "On-time %", color: "var(--chart-3)" },
} satisfies ChartConfig;

export function OnTimeTrend() {
  const { data } = useOverview();
  const chartData =
    data?.series
      .filter((p) => p.on_time_pct != null)
      .map((p) => ({
        date: p.day,
        on_time: p.on_time_pct as number,
      })) ?? [];
  const latest = chartData[chartData.length - 1]?.on_time ?? null;

  return (
    <Card>
      <CardHeader>
        <CardTitle>On-time adherence</CardTitle>
        <CardDescription>Deliveries inside the promised 30-min window</CardDescription>
      </CardHeader>
      <CardContent>
        <ChartContainer config={chartConfig} className="aspect-auto h-40 w-full">
          <LineChart data={chartData} margin={{ left: 8, right: 8 }}>
            <CartesianGrid vertical={false} />
            <XAxis
              dataKey="date"
              tickLine={false}
              axisLine={false}
              tickMargin={8}
              tickFormatter={(value: string) => format(parseISO(value), "d MMM")}
              minTickGap={24}
            />
            <ChartTooltip cursor={false} content={<ChartTooltipContent indicator="line" />} />
            <Line dataKey="on_time" type="monotone" stroke="var(--color-on_time)" strokeWidth={2} dot={false} />
          </LineChart>
        </ChartContainer>
      </CardContent>
      <CardFooter>
        <span className="text-muted-foreground text-sm">{`Window adherence latest: ${pct(latest)}`}</span>
      </CardFooter>
    </Card>
  );
}
