"use client";

import {
  Area,
  AreaChart,
  Bar,
  BarChart,
  CartesianGrid,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import type { DayPoint } from "@/lib/types";
import { dayLabel, num, paise } from "@/lib/format";

/**
 * Single-hue chart language: accent water-blue for the primary series,
 * zinc for the counter-series. No rainbows — the data is the color.
 */

function ChartTooltip({
  active,
  payload,
  label,
  money,
}: {
  active?: boolean;
  payload?: Array<{ name?: string; value?: number | string; color?: string }>;
  label?: string | number;
  money?: boolean;
}) {
  if (!active || !payload?.length) return null;
  return (
    <div className="rounded-lg border border-line bg-surface px-3 py-2 text-xs shadow-card">
      <p className="mb-1 font-medium text-ink">{label ? dayLabel(String(label)) : ""}</p>
      {payload.map((p) => (
        <p key={p.name} className="tnum flex items-center gap-2 text-steel">
          <span className="inline-block size-2 rounded-full" style={{ background: p.color }} />
          {p.name}: {money ? paise(Number(p.value)) : num(Number(p.value))}
        </p>
      ))}
    </div>
  );
}

export function GmvOrdersChart({ series }: { series: DayPoint[] }) {
  return (
    <div className="h-64 w-full px-2 py-3">
      <ResponsiveContainer width="100%" height="100%">
        <AreaChart data={series} margin={{ top: 4, right: 12, left: 4, bottom: 0 }}>
          <defs>
            <linearGradient id="gmvFill" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#0369a1" stopOpacity={0.18} />
              <stop offset="100%" stopColor="#0369a1" stopOpacity={0.02} />
            </linearGradient>
          </defs>
          <CartesianGrid stroke="#f1f1f3" vertical={false} />
          <XAxis
            dataKey="day"
            tickFormatter={(v: string) => dayLabel(v)}
            tick={{ fontSize: 11, fill: "#a1a1aa" }}
            axisLine={{ stroke: "#e4e4e7" }}
            tickLine={false}
          />
          <YAxis
            tickFormatter={(v: number) => `₹${Math.round(v / 100)}`}
            tick={{ fontSize: 11, fill: "#a1a1aa" }}
            axisLine={false}
            tickLine={false}
            width={56}
          />
          <Tooltip content={<ChartTooltip money />} />
          <Area
            type="monotone"
            dataKey="gmv_paise"
            name="Order value"
            stroke="#0369a1"
            strokeWidth={2}
            fill="url(#gmvFill)"
          />
        </AreaChart>
      </ResponsiveContainer>
    </div>
  );
}

export function PaymentSplitChart({ series }: { series: DayPoint[] }) {
  return (
    <div className="h-64 w-full px-2 py-3">
      <ResponsiveContainer width="100%" height="100%">
        <BarChart data={series} margin={{ top: 4, right: 12, left: 4, bottom: 0 }}>
          <CartesianGrid stroke="#f1f1f3" vertical={false} />
          <XAxis
            dataKey="day"
            tickFormatter={(v: string) => dayLabel(v)}
            tick={{ fontSize: 11, fill: "#a1a1aa" }}
            axisLine={{ stroke: "#e4e4e7" }}
            tickLine={false}
          />
          <YAxis
            tick={{ fontSize: 11, fill: "#a1a1aa" }}
            axisLine={false}
            tickLine={false}
            width={32}
          />
          <Tooltip content={<ChartTooltip />} />
          <Bar dataKey="upi_orders" name="UPI" stackId="pay" fill="#0369a1" radius={[0, 0, 0, 0]} />
          <Bar dataKey="cod_orders" name="Cash" stackId="pay" fill="#d4d4d8" radius={[3, 3, 0, 0]} />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}

export function OnTimeChart({ series }: { series: DayPoint[] }) {
  const data = series.map((d) => ({ ...d, on_time_pct: d.on_time_pct ?? null }));
  return (
    <div className="h-56 w-full px-2 py-3">
      <ResponsiveContainer width="100%" height="100%">
        <LineChart data={data} margin={{ top: 4, right: 12, left: 4, bottom: 0 }}>
          <CartesianGrid stroke="#f1f1f3" vertical={false} />
          <XAxis
            dataKey="day"
            tickFormatter={(v: string) => dayLabel(v)}
            tick={{ fontSize: 11, fill: "#a1a1aa" }}
            axisLine={{ stroke: "#e4e4e7" }}
            tickLine={false}
          />
          <YAxis
            domain={[0, 100]}
            tickFormatter={(v: number) => `${v}%`}
            tick={{ fontSize: 11, fill: "#a1a1aa" }}
            axisLine={false}
            tickLine={false}
            width={40}
          />
          <Tooltip content={<ChartTooltip />} />
          <Line
            type="monotone"
            dataKey="on_time_pct"
            name="On-time"
            stroke="#15803d"
            strokeWidth={2}
            dot={{ r: 2.5, fill: "#15803d", strokeWidth: 0 }}
            connectNulls
          />
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
}

const STATE_COLORS: Record<string, string> = {
  delivered: "#15803d",
  dispatched: "#0369a1",
  assigned: "#0284c7",
  placed: "#b45309",
  failed: "#b91c1c",
  cancelled: "#71717a",
};

export function StatesChart({ data }: { data: Array<{ state: string; count: number }> }) {
  return (
    <div className="space-y-2.5 px-5 py-4">
      {data.map((row) => {
        const max = Math.max(...data.map((d) => d.count), 1);
        const color = STATE_COLORS[row.state] ?? "#a1a1aa";
        return (
          <div key={row.state} className="flex items-center gap-3">
            <span className="w-20 shrink-0 text-xs capitalize text-steel">{row.state}</span>
            <div className="h-2.5 flex-1 overflow-hidden rounded-full bg-line-soft">
              <div
                className="h-full rounded-full transition-[width] duration-500"
                style={{ width: `${Math.max((row.count / max) * 100, 2)}%`, background: color }}
              />
            </div>
            <span className="tnum w-10 text-right text-xs text-ink">{num(row.count)}</span>
          </div>
        );
      })}
    </div>
  );
}
