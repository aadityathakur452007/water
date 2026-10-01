"use client";

import { useQuery, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { MessageSquareWarning, ShieldAlert, Siren } from "lucide-react";
import { Badge, Card, CardHeader, EmptyState, ErrorState, PageHeader, SkeletonBlock } from "@/shared/ui/primitives";
import { ConfirmAction } from "@/shared/ui/actions";
import { proxyGet } from "@/features/dashboard/api";
import { toastActionSuccess } from "@/lib/feedback";
import { dateTime } from "@/lib/format";
import type { Page, QualityRow, StrikeRow, ComplaintRow } from "@/lib/types";

export default function TrustPage() {
  const qc = useQueryClient();
  const strikesQ = useQuery({
    queryKey: ["strikes"],
    queryFn: () => proxyGet<Page<StrikeRow>>("/v1/admin/strikes"),
  });
  const qualityQ = useQuery({
    queryKey: ["quality"],
    queryFn: () => proxyGet<Page<QualityRow>>("/v1/admin/quality"),
  });
  const complaintsQ = useQuery({
    queryKey: ["complaints"],
    queryFn: () => proxyGet<Page<ComplaintRow>>("/v1/admin/complaints"),
  });

  async function action(path: string, body?: unknown): Promise<string | null> {
    const res = await fetch(`/api/admin-actions?url=${encodeURIComponent(path)}`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body ?? {}),
    });
    const json = (await res.json().catch(() => ({}))) as { error?: { message?: string } };
    if (!res.ok) {
      return json.error?.message ?? `Action failed (${res.status})`;
    }
    const label = path.endsWith("/confirm")
      ? "Quality incident confirmed"
      : path.endsWith("/reject")
        ? "Quality incident rejected"
        : path.includes("/strikes/")
          ? "Strike cleared"
          : "Complaint resolved";
    toastActionSuccess(label, json);
    await qc.invalidateQueries({ queryKey: ["strikes"] });
    await qc.invalidateQueries({ queryKey: ["quality"] });
    await qc.invalidateQueries({ queryKey: ["complaints"] });
    await qc.invalidateQueries({ queryKey: ["trust-count"] });
    return null;
  }

  const qualityOpen = (qualityQ.data?.data ?? []).filter((q) => q.status === "open");

  return (
    <div className="space-y-5">
      <PageHeader
        title="Trust & safety"
        description="Strikes, quality incidents and disputes — the graduated warn → restrict → suspend ladder, human-confirmed."
      />

      <div className="grid grid-cols-1 gap-4 xl:grid-cols-2">
        <Card>
          <CardHeader
            title="Quality incidents"
            hint="24h quality window · vendor verified at the door · 48h admin triage"
            action={<Badge tone={qualityOpen.length ? "bad" : "good"}>{qualityOpen.length} open</Badge>}
          />
          {qualityQ.isLoading ? (
            <SkeletonBlock className="m-4 h-28" />
          ) : qualityQ.isError ? (
            <div className="p-4">
              <ErrorState message={(qualityQ.error as Error).message} />
            </div>
          ) : (qualityQ.data?.data.length ?? 0) === 0 ? (
            <EmptyState
              icon={<Siren className="size-5" />}
              title="No quality incidents"
              hint="Water-quality, damaged-jar and seal claims land here with the vendor's door check attached."
            />
          ) : (
            <ul className="divide-y divide-line-soft">
              {qualityQ.data?.data.map((q) => (
                <li key={q.id} className="px-5 py-4">
                  <div className="flex flex-wrap items-center gap-2">
                    <Badge tone={q.status === "open" ? "warn" : q.status === "confirmed" ? "bad" : "good"}>
                      {q.status}
                    </Badge>
                    <span className="text-xs font-medium capitalize text-ink">{q.reason_code.replace(/_/g, " ")}</span>
                    <Link href={`/admin/orders/${q.order_id}`} className="tnum text-xs text-accent hover:underline">
                      {q.order_id.slice(0, 10)}
                    </Link>
                    <span className="ml-auto text-xs text-steel">{dateTime(q.created_at)}</span>
                  </div>
                  <p className="mt-1.5 text-sm text-steel">{q.description || "—"}</p>
                  {q.vendor_agree !== null ? (
                    <p className="mt-1 text-xs text-steel">
                      Vendor {q.vendor_agree ? "agrees" : "disagrees"} — admin decides within 48h.
                    </p>
                  ) : null}
                  {q.status === "open" ? (
                    <div className="mt-2.5 flex gap-2">
                      <ConfirmAction
                        label="Confirm"
                        tone="danger"
                        title="Confirm this incident?"
                        description="Vendor strike + free redelivery or refund for the customer (never their bad water to pay for)."
                        confirmLabel="Confirm incident"
                        onConfirm={(reason) => action(`/v1/admin/quality/${q.id}/confirm`, { resolution: reason })}
                      />
                      <ConfirmAction
                        label="Reject"
                        title="Reject this claim?"
                        description="Records the rejection — 3 rejected claims in 90 days raise an abuse strike on the user."
                        confirmLabel="Reject claim"
                        onConfirm={(reason) => action(`/v1/admin/quality/${q.id}/reject`, { resolution: reason })}
                      />
                    </div>
                  ) : null}
                </li>
              ))}
            </ul>
          )}
        </Card>

        <div className="space-y-4">
          <Card>
            <CardHeader title="Strikes" hint="quality · fake_delivery · cash · behavior · payment_default · abuse" />
            {strikesQ.isLoading ? (
              <SkeletonBlock className="m-4 h-24" />
            ) : strikesQ.isError ? (
              <div className="p-4">
                <ErrorState message={(strikesQ.error as Error).message} />
              </div>
            ) : (strikesQ.data?.data.length ?? 0) === 0 ? (
              <EmptyState
                icon={<ShieldAlert className="size-5" />}
                title="No strikes on file"
                hint="Strike thresholds auto-flag but removal is always human-confirmed."
              />
            ) : (
              <ul className="divide-y divide-line-soft">
                {strikesQ.data?.data.map((s) => (
                  <li key={s.id} className="flex items-center gap-3 px-5 py-3 text-sm">
                    <Badge tone={s.severity >= 3 ? "bad" : s.cleared_at ? "neutral" : "warn"}>{s.kind}</Badge>
                    <Link href={`/admin/users/${s.subject_id}`} className="tnum text-xs text-accent hover:underline">
                      {s.subject_id.slice(0, 10)}
                    </Link>
                    <span className="min-w-0 flex-1 truncate text-xs text-steel">{s.note || "—"}</span>
                    {s.cleared_at ? (
                      <span className="text-xs text-good">cleared</span>
                    ) : (
                      <ConfirmAction
                        label="Clear"
                        tone="accent"
                        requireReason={false}
                        title="Clear this strike?"
                        description="Marks it cleared; history stays visible."
                        confirmLabel="Clear strike"
                        onConfirm={() => action(`/v1/admin/strikes/${s.id}/clear`, {})}
                      />
                    )}
                  </li>
                ))}
              </ul>
            )}
          </Card>

          <Card>
            <CardHeader
              title="Complaints"
              hint="3-day dispute window · refunds and redeliveries resolve here"
            />
            {complaintsQ.isLoading ? (
              <SkeletonBlock className="m-4 h-24" />
            ) : complaintsQ.isError ? (
              <div className="p-4">
                <ErrorState message={(complaintsQ.error as Error).message} />
              </div>
            ) : (complaintsQ.data?.data.length ?? 0) === 0 ? (
              <EmptyState
                icon={<MessageSquareWarning className="size-5" />}
                title="No complaints"
                hint="Quantity and deposit disputes auto-resolve from ledger records — only real judgment calls surface here."
              />
            ) : (
              <ul className="divide-y divide-line-soft">
                {complaintsQ.data?.data.map((c) => (
                  <li key={c.id} className="px-5 py-3.5">
                    <div className="flex flex-wrap items-center gap-2">
                      <Badge tone={c.status === "resolved" ? "good" : "warn"}>{c.status}</Badge>
                      <span className="text-xs font-medium capitalize text-ink">{c.reason_code.replace(/_/g, " ")}</span>
                      <Link href={`/admin/orders/${c.order_id}`} className="tnum text-xs text-accent hover:underline">
                        {c.order_id.slice(0, 10)}
                      </Link>
                      <span className="ml-auto text-xs text-steel">{dateTime(c.created_at)}</span>
                    </div>
                    <p className="mt-1.5 text-sm text-steel">{c.text}</p>
                    {c.status !== "resolved" ? (
                      <div className="mt-2.5 flex gap-2">
                        {(["refund", "redelivery", "note"] as const).map((act) => (
                          <ConfirmAction
                            key={act}
                            label={act === "note" ? "Note only" : `Resolve: ${act}`}
                            tone={act === "note" ? "accent" : "danger"}
                            title={`Resolve with ${act}?`}
                            description="The decision and your note are shown to the user — never silence."
                            confirmLabel="Resolve"
                            onConfirm={(note) => action(`/v1/admin/complaints/${c.id}/resolve`, { action: act, note })}
                          />
                        ))}
                      </div>
                    ) : null}
                  </li>
                ))}
              </ul>
            )}
          </Card>
        </div>
      </div>
    </div>
  );
}
