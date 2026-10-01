"use client";

import { useQuery, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { ArrowLeft, Ban, Boxes, HandCoins, PackageCheck, Wallet } from "lucide-react";
import { Badge, Card, CardHeader, ErrorState, SkeletonBlock } from "@/shared/ui/primitives";
import { ConfirmAction } from "@/shared/ui/actions";
import { proxyGet } from "@/features/dashboard/api";
import { toastActionSuccess } from "@/lib/feedback";
import { dateTime, num, paise, phoneMasked } from "@/lib/format";
import type { VendorDetail } from "@/lib/types";

export function VendorDetailPanel({ vendorId }: { vendorId: string }) {
  const qc = useQueryClient();
  const { data, isLoading, isError, error } = useQuery({
    queryKey: ["vendor", vendorId],
    queryFn: () => proxyGet<VendorDetail>(`/v1/admin/vendors/${vendorId}/detail`),
    retry: false,
  });

  async function action(path: string, body?: unknown): Promise<string | null> {
    const res = await fetch(`/api/admin-actions?url=${encodeURIComponent(path)}`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body ?? {}),
    });
    const json = (await res.json().catch(() => ({}))) as {
      error?: { message?: string };
      revoked_sessions?: number;
    };
    if (!res.ok) {
      return json.error?.message ?? `Action failed (${res.status})`;
    }
    const label = path.endsWith("/unsuspend")
      ? "Vendor unblocked"
      : path.endsWith("/suspend")
        ? "Vendor blocked"
        : path.endsWith("/review-hold")
          ? "Review hold placed"
          : "Review hold released";
    toastActionSuccess(label, json);
    await qc.invalidateQueries({ queryKey: ["vendor", vendorId] });
    await qc.invalidateQueries({ queryKey: ["vendors"] });
    return null;
  }

  if (isLoading) return <SkeletonBlock className="h-64" />;
  if (isError || !data) {
    return <ErrorState message={(error as Error)?.message ?? "Vendor not found."} />;
  }

  const v = data.vendor;
  const p = data.profile;
  const blocked = Boolean(v.suspended);

  return (
    <div className="space-y-5">
      <div className="flex items-start gap-3">
        <Link
          href="/admin/vendors"
          className="inline-flex size-8 items-center justify-center rounded-lg border border-line text-steel hover:bg-canvas"
          aria-label="Back to vendors"
        >
          <ArrowLeft className="size-4" aria-hidden />
        </Link>
        <div>
          <div className="flex flex-wrap items-center gap-2">
            <h1 className="text-lg font-semibold tracking-tight text-ink">{v.name ?? v.id.slice(0, 10)}</h1>
            <Badge tone={v.kyc_status === "verified" ? "good" : "warn"}>kyc {v.kyc_status}</Badge>
            {blocked ? <Badge tone="bad">blocked</Badge> : null}
            {p?.on_duty ? <Badge tone="accent">on duty</Badge> : null}
            {p?.review_hold ? <Badge tone="warn">review hold</Badge> : null}
          </div>
          <p className="tnum mt-0.5 text-sm text-steel">{phoneMasked(v.phone)}</p>
        </div>
        <div className="ml-auto flex flex-wrap items-center gap-2">
          {!blocked ? (
            <>
              <ConfirmAction
                label="Review hold"
                tone="accent"
                title="Pause new assigns?"
                description="Vendor keeps in-flight stops but receives no new assignments until released."
                confirmLabel="Hold"
                onConfirm={(reason) => action(`/v1/admin/vendors/${vendorId}/review-hold`, { reason })}
              />
              <ConfirmAction
                label="Block vendor"
                title="Block this vendor?"
                description="Suspends the account and revokes every live session — no routes, no app access. In-flight custody must still be handed over."
                confirmLabel="Block now"
                onConfirm={(reason) =>
                  action(`/v1/admin/users/${vendorId}/suspend`, { reason, level: "suspend" })
                }
              />
            </>
          ) : (
            <>
              <ConfirmAction
                label="Release hold"
                tone="accent"
                requireReason={false}
                title="Release review hold?"
                description="Vendor becomes assignable again."
                confirmLabel="Release"
                onConfirm={() => action(`/v1/admin/vendors/${vendorId}/release`, {})}
              />
              <ConfirmAction
                label="Unblock"
                tone="accent"
                requireReason={false}
                title="Unblock this vendor?"
                description="Routes and app access resume. Block history stays in the audit log."
                confirmLabel="Unblock"
                onConfirm={() => action(`/v1/admin/users/${vendorId}/unsuspend`)}
              />
            </>
          )}
        </div>
      </div>

      {blocked && v.suspended_reason ? (
        <div className="rounded-xl border border-bad/30 bg-bad-soft/50 px-4 py-3 text-sm text-bad">
          <p className="flex items-center gap-1.5 font-medium">
            <Ban className="size-4" aria-hidden /> Blocked {dateTime(v.suspended_at)} — {v.suspended_reason}
          </p>
        </div>
      ) : null}

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <Card className="px-5 py-4" stagger={0}>
          <p className="flex items-center gap-1.5 text-xs font-medium uppercase tracking-wide text-steel">
            <PackageCheck className="size-3.5" aria-hidden /> Stops done
          </p>
          <p className="tnum mt-1.5 text-2xl font-semibold text-ink">{num(data.stops_done)}</p>
          <p className="mt-1 text-xs text-steel">{num(data.jars_delivered)} jars delivered all-time</p>
        </Card>
        <Card className="px-5 py-4" stagger={1}>
          <p className="flex items-center gap-1.5 text-xs font-medium uppercase tracking-wide text-steel">
            <HandCoins className="size-3.5" aria-hidden /> Cash in hand
          </p>
          <p className={`tnum mt-1.5 text-2xl font-semibold ${(p?.in_hand ?? 0) > 0 ? "text-warn" : "text-ink"}`}>
            {paise(p?.in_hand)}
          </p>
          <p className="mt-1 text-xs text-steel">custody — must zero at handover</p>
        </Card>
        <Card className="px-5 py-4" stagger={2}>
          <p className="flex items-center gap-1.5 text-xs font-medium uppercase tracking-wide text-steel">
            <Boxes className="size-3.5" aria-hidden /> Capacity
          </p>
          <p className="tnum mt-1.5 text-2xl font-semibold text-ink">
            {num(p?.max_stops_per_shift)}<span className="text-base text-steel"> stops</span>
          </p>
          <p className="mt-1 text-xs text-steel">{num(p?.max_jars_per_shift)} jars/shift cap</p>
        </Card>
        <Card className="px-5 py-4" stagger={3}>
          <p className="flex items-center gap-1.5 text-xs font-medium uppercase tracking-wide text-steel">
            <Wallet className="size-3.5" aria-hidden /> Per-stop fee
          </p>
          <p className="tnum mt-1.5 text-2xl font-semibold text-ink">{paise(p?.per_stop_fee)}</p>
          <p className="mt-1 text-xs text-steel">{p?.per_stop_fee ? "per-stop model" : "salary model"}</p>
        </Card>
      </div>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader title="Zones" hint="Attached geographies with priority" />
          <ul className="divide-y divide-line-soft">
            {data.zones.length === 0 ? (
              <li className="px-5 py-4 text-sm text-steel">No zones attached.</li>
            ) : (
              data.zones.map((z) => (
                <li key={z.id} className="flex items-center justify-between px-5 py-3 text-sm">
                  <span className="text-ink">{z.name}</span>
                  <span className="text-xs text-steel">priority {z.priority}</span>
                </li>
              ))
            )}
          </ul>
        </Card>
        <Card>
          <CardHeader title="Strikes" hint="Trust history — severity drives the ladder" />
          {data.strikes.length === 0 ? (
            <p className="px-5 py-4 text-sm text-steel">Clean record.</p>
          ) : (
            <ul className="divide-y divide-line-soft">
              {data.strikes.map((s) => (
                <li key={s.id} className="flex items-start gap-3 px-5 py-3 text-sm">
                  <Badge tone={s.severity >= 3 ? "bad" : "warn"}>{s.kind}</Badge>
                  <span className="min-w-0 flex-1 truncate text-steel">{s.note || "—"}</span>
                  <span className="text-xs text-steel">{dateTime(s.created_at)}</span>
                </li>
              ))}
            </ul>
          )}
        </Card>
      </div>

      <Card>
        <CardHeader title="Payouts" hint="Per-period earnings — deductions come from custody recovery" />
        {data.payouts.length === 0 ? (
          <p className="px-5 py-4 text-sm text-steel">No payout periods yet.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-line text-left text-[11px] uppercase tracking-wide text-steel">
                  <th className="px-5 py-2.5 font-medium">Period</th>
                  <th className="px-3 py-2.5 font-medium">Stops</th>
                  <th className="px-3 py-2.5 font-medium">Gross</th>
                  <th className="px-3 py-2.5 font-medium">Deductions</th>
                  <th className="px-3 py-2.5 font-medium">Net</th>
                  <th className="px-5 py-2.5 font-medium">Status</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-line-soft">
                {data.payouts.map((row) => (
                  <tr key={row.id}>
                    <td className="px-5 py-3 text-steel">{row.period || dateTime(row.created_at)}</td>
                    <td className="tnum px-3 py-3 text-steel">{num(row.stops_done)}</td>
                    <td className="tnum px-3 py-3 text-steel">{paise(row.gross_fee)}</td>
                    <td className="tnum px-3 py-3 text-warn">{paise(row.deductions)}</td>
                    <td className="tnum px-3 py-3 font-medium text-ink">{paise(row.net)}</td>
                    <td className="px-5 py-3">
                      <Badge tone={row.status === "paid" ? "good" : "warn"}>{row.status}</Badge>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>
    </div>
  );
}
