import { Label, Pie, PieChart } from "recharts";

import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "@/components/ui/card";
import {
  type ChartConfig,
  ChartContainer,
  ChartLegend,
  ChartLegendContent,
  ChartTooltip,
  ChartTooltipContent,
} from "@/components/ui/chart";
import { pct, rupees } from "@/lib/money";

import { useOverview } from "./overview-data";

const chartConfig = {
  upi: { label: "UPI", color: "var(--chart-1)" },
  cod: { label: "COD", color: "var(--chart-2)" },
} satisfies ChartConfig;

export function PaymentSplit() {
  const { data } = useOverview();
  const upi = data?.series.reduce((a, p) => a + p.upi_orders, 0) ?? 0;
  const cod = data?.series.reduce((a, p) => a + p.cod_orders, 0) ?? 0;
  const chartData = [
    { name: "upi", orders: upi, fill: "var(--color-upi)" },
    { name: "cod", orders: cod, fill: "var(--color-cod)" },
  ];
  const total = upi + cod;

  return (
    <Card>
      <CardHeader>
        <CardTitle>UPI vs COD — 14 days</CardTitle>
        <CardDescription>Collection method split</CardDescription>
      </CardHeader>
      <CardContent className="flex-1 pb-0">
        <ChartContainer config={chartConfig} className="mx-auto aspect-square max-h-[220px]">
          <PieChart>
            <ChartTooltip cursor={false} content={<ChartTooltipContent hideLabel />} />
            <Pie data={chartData} dataKey="orders" nameKey="name" innerRadius={54} strokeWidth={5}>
              <Label
                content={({ viewBox }) => {
                  if (viewBox && "cx" in viewBox && "cy" in viewBox) {
                    return (
                      <text
                        x={viewBox.cx}
                        y={viewBox.cy}
                        textAnchor="middle"
                        dominantBaseline="middle"
                        fill="var(--foreground)"
                        className="fill-foreground font-semibold text-lg tabular-nums"
                      >
                        {total.toLocaleString("en-IN")}
                      </text>
                    );
                  }
                  return null;
                }}
              />
            </Pie>
            <ChartLegend content={<ChartLegendContent nameKey="name" />} className="-translate-y-2 flex-wrap gap-2" />
          </PieChart>
        </ChartContainer>
      </CardContent>
      <CardFooter className="flex-col items-start gap-1 text-sm">
        <span className="text-muted-foreground">
          {`UPI ${pct((upi / Math.max(total, 1)) * 100)} · COD ${pct((cod / Math.max(total, 1)) * 100)}`}
        </span>
        <span className="text-muted-foreground">
          {`Collected — UPI ${rupees(data?.money.collected_upi_paise)} · COD ${rupees(data?.money.collected_cod_paise)}`}
        </span>
      </CardFooter>
    </Card>
  );
}
