"use client";

import { useQueryClient } from "@tanstack/react-query";
import { CalendarClock, HandCoins, Route, Wallet } from "lucide-react";
import { Badge, Card, CardHeader, ErrorState, PageHeader, SkeletonBlock } from "@/shared/ui/primitives";
import { ConfirmAction } from "@/shared/ui/actions";
import { useCustody, useDunning, useReconciliation } from "@/features/dashboard/api";
import { num, paise, phoneMasked } from "@/lib/format";

export default function OperationsPage() {
  const qc = useQueryClient();
  const recon = useReconciliation();
  const custody = useCustody();
  const dunning = useDunning();

  async function generateRoutes(): Promise<string | null> {
    const today = new Date().toISOString().slice(0, 10);
    const res = await fetch(`/api/admin-actions?url=${encodeURIComponent("/v1/admin/routes/generate")}`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ date: today }),
    });
    if (!res.ok) {
      const err = (await res.json().catch(() => ({}))) as { error?: { message?: string } };
      return err.error?.message ?? "Route generation failed";
    }
    await qc.invalidateQueries({ queryKey: ["reconciliation"] });
    return null;
  }

  const r = recon.data ?? {};

  return (
    <div className="space-y-5">
      <PageHeader
        title="Operations"
        description="The owner's daily loop: build routes in the morning, close the day at night."
        actions={
          <ConfirmAction
            label="Generate today's routes"
            tone="accent"
            requireReason={false}
            title="Generate routes for today?"
            description="Auto-builds zone routes + loading sheets from schedules and returns, consuming depot stock."
            confirmLabel="Generate"
            onConfirm={generateRoutes}
          />
        }
      />

      <Card>
        <CardHeader
          title="Day-close reconciliation"
          hint="Cash + UPI vs pending vs jars-out vs deposit liability — every day, never month-end"
          action={
            <span className="flex items-center gap-1.5 text-xs text-steel">
              <CalendarClock className="size-3.5" aria-hidden />
              live
            </span>
          }
        />
        {recon.isLoading ? (
          <SkeletonBlock className="m-4 h-40" />
        ) : recon.isError ? (
          <div className="p-4">
            <ErrorState message={(recon.error as Error).message} hint="Pass ?route=&date= to drill into a route." />
          </div>
        ) : (
          <div className="grid grid-cols-2 gap-px bg-line-soft lg:grid-cols-4">
            {[
              { label: "Cash expected", value: paise(Number(r.cash_expected_paise ?? r.cash_collected ?? 0)) },
              { label: "Cash collected", value: paise(Number(r.cash_collected_paise ?? 0)) },
              { label: "Jars out", value: num(Number(r.jars_out ?? 0)) },
              { label: "Deposit liability", value: paise(Number(r.deposit_liability_paise ?? 0)) },
            ].map((cell) => (
              <div key={cell.label} className="bg-surface px-5 py-4">
                <p className="text-xs text-steel">{cell.label}</p>
                <p className="tnum mt-1 text-lg font-semibold text-ink">{cell.value}</p>
              </div>
            ))}
          </div>
        )}
        <p className="border-t border-line-soft px-5 py-3 text-xs text-steel">
          Full field list follows the worker&apos;s reconciliation payload — totals shown when present; route-level
          drill-down via the API contract §4.11.
        </p>
      </Card>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader
            title="Custody queue"
            hint="Vendor hands holding cash — must zero by handover"
            action={<Badge tone={(custody.data?.data.length ?? 0) > 0 ? "warn" : "good"}>
              {custody.data?.data.length ?? 0} open
            </Badge>}
          />
          {custody.isLoading ? (
            <SkeletonBlock className="m-4 h-24" />
          ) : (custody.data?.data.length ?? 0) === 0 ? (
            <p className="flex items-center gap-2 px-5 py-5 text-sm text-steel">
              <HandCoins className="size-4 text-faint" aria-hidden /> No open custody — clean hands everywhere.
            </p>
          ) : (
            <ul className="divide-y divide-line-soft">
              {custody.data?.data.map((c) => (
                <li key={c.vendor_id} className="flex items-center gap-3 px-5 py-3 text-sm">
                  <span className="min-w-0 flex-1">
                    <span className="text-ink">{c.name ?? c.vendor_id.slice(0, 10)}</span>
                    <span className="tnum block text-xs text-faint">{phoneMasked(c.phone)}</span>
                  </span>
                  <span className="tnum font-medium text-warn">{paise(c.in_hand)}</span>
                </li>
              ))}
            </ul>
          )}
        </Card>

        <Card>
          <CardHeader
            title="Dues ladder"
            hint="Dunning: reminder → COD block → suspend ordering → audited write-off"
            action={<Badge tone={(dunning.data?.data.length ?? 0) > 0 ? "bad" : "good"}>
              {dunning.data?.data.length ?? 0}
            </Badge>}
          />
          {dunning.isLoading ? (
            <SkeletonBlock className="m-4 h-24" />
          ) : (dunning.data?.data.length ?? 0) === 0 ? (
            <p className="flex items-center gap-2 px-5 py-5 text-sm text-steel">
              <Wallet className="size-4 text-faint" aria-hidden /> No outstanding dues.
            </p>
          ) : (
            <ul className="divide-y divide-line-soft">
              {dunning.data?.data.map((d) => (
                <li key={d.customer_id} className="flex items-center gap-3 px-5 py-3 text-sm">
                  <span className="min-w-0 flex-1">
                    <span className="text-ink">{d.name ?? d.customer_id.slice(0, 10)}</span>
                    <span className="tnum block text-xs text-faint">{phoneMasked(d.phone)}</span>
                  </span>
                  <span className="tnum font-medium text-bad">{paise(d.dues)}</span>
                </li>
              ))}
            </ul>
          )}
        </Card>
      </div>

      <p className="flex items-center gap-1.5 text-[11px] text-faint">
        <Route className="size-3" aria-hidden />
        Route sequencing and vendor load balancing run server-side (deterministic least-loaded, ADR-015) — the panel only triggers and displays.
      </p>
    </div>
  );
}
