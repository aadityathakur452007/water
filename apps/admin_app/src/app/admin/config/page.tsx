"use client";

import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Settings2 } from "lucide-react";
import { Card, CardHeader, EmptyState, ErrorState, PageHeader, SkeletonRows } from "@/shared/ui/primitives";
import { ConfirmAction } from "@/shared/ui/actions";
import { proxyGet } from "@/features/dashboard/api";
import { dateTime } from "@/lib/format";
import type { ConfigRow } from "@/lib/types";

const KEY_HINTS: Record<string, string> = {
  rate_refill_paise: "20L refill price in paise (2800 = ₹28)",
  rate_container_paise: "Jar + container price in paise (3000 = ₹30)",
  deposit_per_jar_paise: "Refundable deposit per jar (15000 = ₹150)",
  cap_charge_paise: "Cap-missing charge per jar (300 = ₹3)",
  cod_cap_paise: "COD order cap in paise",
  hold_limit_jars: "Jars held before delivery blocks (default 3)",
};

export default function ConfigPage() {
  const qc = useQueryClient();
  const { data, isLoading, isError, error } = useQuery({
    queryKey: ["config"],
    queryFn: () => proxyGet<{ data: ConfigRow[] }>("/v1/admin/config"),
  });

  async function setKey(key: string, value: string): Promise<string | null> {
    const res = await fetch(`/api/admin-actions?url=${encodeURIComponent("/v1/admin/config")}`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ key, value }),
    });
    if (!res.ok) {
      const err = (await res.json().catch(() => ({}))) as { error?: { message?: string } };
      return err.error?.message ?? "Save failed";
    }
    await qc.invalidateQueries({ queryKey: ["config"] });
    return null;
  }

  const rows = data?.data ?? [];

  return (
    <div className="space-y-5">
      <PageHeader
        title="Config"
        description="Rates, deposit and caps. Changes carry effective_from — mid-day edits apply to new quotes only; every write is audit-logged."
      />
      <Card>
        <CardHeader title="Keys" hint="Server-computed money — clients never set totals" />
        {isError ? (
          <div className="p-4">
            <ErrorState message={(error as Error).message} />
          </div>
        ) : isLoading ? (
          <SkeletonRows rows={5} cols={3} />
        ) : rows.length === 0 ? (
          <EmptyState
            icon={<Settings2 className="size-5" />}
            title="No config keys yet"
            hint="Defaults live in the worker settings; keys appear here once set or overridden."
          />
        ) : (
          <ul className="divide-y divide-line-soft">
            {rows.map((row) => (
              <li key={row.key} className="flex flex-wrap items-center gap-3 px-5 py-3.5">
                <div className="min-w-0 flex-1">
                  <p className="tnum text-sm font-medium text-ink">{row.key}</p>
                  <p className="text-xs text-steel">
                    {KEY_HINTS[row.key] ?? "custom key"} · updated {dateTime(row.updated_at)}
                  </p>
                </div>
                <span className="tnum rounded-md bg-canvas px-2 py-1 text-sm text-ink">{row.value}</span>
                <ConfirmAction
                  label="Edit value"
                  tone="accent"
                  title={`Set ${row.key}`}
                  description="Applies to new quotes from now on — existing frozen orders are untouched."
                  confirmLabel="Save value"
                  onConfirm={async (reason) => setKey(row.key, reason)}
                />
              </li>
            ))}
          </ul>
        )}
      </Card>
      <p className="text-[11px] text-faint">
        The edit action reuses the reason field as the new value — type the raw value (e.g. 2800) when confirming.
        Money keys are integer paise.
      </p>
    </div>
  );
}
