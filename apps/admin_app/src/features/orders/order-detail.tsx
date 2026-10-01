"use client";

import { useQuery, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { ArrowLeft, Phone } from "lucide-react";
import { Card, CardHeader, ErrorState, PaymentBadge, SkeletonBlock, StateBadge } from "@/shared/ui/primitives";
import { ConfirmAction } from "@/shared/ui/actions";
import { proxyGet } from "@/features/dashboard/api";
import { toastActionSuccess } from "@/lib/feedback";
import { dateTime, num, paise } from "@/lib/format";

type OrderEvent = {
  id: string;
  from_state: string | null;
  to_state: string;
  actor_id: string;
  actor_role: string;
  reason: string;
  created_at: string;
};

type AdminOrder = {
  id: string;
  user_id: string;
  address_id: string;
  items: string;
  n: number;
  e: number;
  m: number;
  water_bill: number;
  deposit_due: number;
  cap_charge: number;
  total: number;
  payment_mode: string;
  payment_status: string;
  state: string;
  window_start: string;
  window_end: string;
  created_at: string;
};

type VendorOption = { id: string; name: string | null; phone: string | null; role: string };

const TRACKER = ["placed", "accepted", "packed", "assigned", "dispatched", "delivered"];

export function OrderDetail({ orderId }: { orderId: string }) {
  const qc = useQueryClient();
  const orderQ = useQuery({
    queryKey: ["order", orderId],
    queryFn: async () => {
      const page = await proxyGet<{ data: AdminOrder[] }>(`/v1/admin/orders?limit=200`);
      const found = page.data.find((o) => o.id === orderId);
      if (!found) throw new Error("Order not found in the current queue page.");
      return found;
    },
    retry: false,
  });
  const eventsQ = useQuery({
    queryKey: ["order-events", orderId],
    queryFn: () => proxyGet<{ data: OrderEvent[] }>(`/v1/admin/orders?limit=200`).then(() =>
      proxyGet<{ data: OrderEvent[] }>(`/v1/admin/audit?entity=orders&limit=100`),
    ),
    retry: false,
  });
  const vendorsQ = useQuery({
    queryKey: ["vendor-options"],
    queryFn: () => proxyGet<{ data: VendorOption[] }>(`/v1/admin/vendors`),
  });

  async function mutate(path: string, body: unknown): Promise<string | null> {
    const res = await fetch(`/api/admin-actions?url=${encodeURIComponent(path)}`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-csrf-token": document.cookie.includes("sh_csrf") ? "1" : "",
      },
      body: JSON.stringify(body),
    });
    const json = (await res.json().catch(() => ({}))) as { error?: { message?: string } };
    if (!res.ok) {
      return json.error?.message ?? `Action failed (${res.status})`;
    }
    toastActionSuccess(
      path.endsWith("/assign")
        ? "Vendor assigned"
        : path.endsWith("/reassign")
          ? "Vendor reassigned"
          : "Order cancelled",
      json,
    );
    await qc.invalidateQueries({ queryKey: ["order", orderId] });
    await qc.invalidateQueries({ queryKey: ["orders"] });
    return null;
  }

  if (orderQ.isLoading) {
    return (
      <div className="space-y-4">
        <SkeletonBlock className="h-8 w-48" />
        <SkeletonBlock className="h-64" />
      </div>
    );
  }
  if (orderQ.isError || !orderQ.data) {
    return (
      <ErrorState
        message={(orderQ.error as Error)?.message ?? "Order not found."}
        hint="Open it from the Orders queue so the id stays in the fetched page."
      />
    );
  }

  const o = orderQ.data;
  const stepIdx = TRACKER.indexOf(o.state);
  const items: Array<{ sku: string; qty: number }> = safeItems(o.items);
  const vendors = (vendorsQ.data?.data ?? []).filter((v) => v.role === "vendor");

  return (
    <div className="space-y-5">
      <div className="flex items-center gap-3">
        <Link
          href="/admin/orders"
          className="inline-flex size-8 items-center justify-center rounded-lg border border-line text-steel hover:bg-canvas"
          aria-label="Back to orders"
        >
          <ArrowLeft className="size-4" aria-hidden />
        </Link>
        <div>
          <h1 className="tnum text-lg font-semibold tracking-tight text-ink">{o.id}</h1>
          <p className="text-xs text-steel">
            Created {dateTime(o.created_at)} · window {dateTime(o.window_start)}
          </p>
        </div>
        <div className="ml-auto flex items-center gap-2">
          <StateBadge state={o.state} />
          <PaymentBadge status={o.payment_status} />
        </div>
      </div>

      {/* Tracker */}
      <Card>
        <div className="flex flex-wrap items-center gap-0 px-6 py-5">
          {TRACKER.map((step, i) => {
            const done = stepIdx >= i && stepIdx !== -1;
            return (
              <div key={step} className="flex items-center">
                <div className="flex flex-col items-center gap-1">
                  <span
                    className={`flex size-7 items-center justify-center rounded-full text-[11px] font-semibold ${
                      done ? "bg-accent text-white" : "bg-line-soft text-faint"
                    }`}
                  >
                    {i + 1}
                  </span>
                  <span className={`text-[11px] capitalize ${done ? "text-ink" : "text-faint"}`}>{step}</span>
                </div>
                {i < TRACKER.length - 1 ? (
                  <span className={`mx-2 h-px w-8 sm:w-14 ${stepIdx > i ? "bg-accent" : "bg-line"}`} />
                ) : null}
              </div>
            );
          })}
        </div>
      </Card>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-12">
        {/* Bill */}
        <Card className="lg:col-span-5">
          <CardHeader title="Bill" hint="Server-computed, frozen at quote" />
          <dl className="space-y-2 px-5 py-4 text-sm">
            {items.map((it) => (
              <div key={it.sku} className="flex justify-between text-steel">
                <dt className="capitalize">
                  {it.sku === "refill" ? "20L refill" : "Jar + container"} × {it.qty}
                </dt>
                <dd className="tnum">{paise(o.water_bill)}</dd>
              </div>
            ))}
            <div className="flex justify-between text-steel">
              <dt>Deposit ({num(Math.max(o.n - o.e, 0))} jars × ₹150)</dt>
              <dd className="tnum">{paise(o.deposit_due)}</dd>
            </div>
            {o.cap_charge > 0 ? (
              <div className="flex justify-between text-steel">
                <dt>Cap missing ({num(o.m)})</dt>
                <dd className="tnum">{paise(o.cap_charge)}</dd>
              </div>
            ) : null}
            <div className="mt-2 flex justify-between border-t border-line-soft pt-2.5 text-base font-semibold text-ink">
              <dt>Total</dt>
              <dd className="tnum">{paise(o.total)}</dd>
            </div>
            <div className="flex justify-between pt-1 text-xs text-steel">
              <dt>Mode</dt>
              <dd className="uppercase">{o.payment_mode}</dd>
            </div>
          </dl>
        </Card>

        {/* Actions + timeline */}
        <div className="space-y-4 lg:col-span-7">
          <Card>
            <CardHeader title="Dispatch actions" hint="Every action is audit-logged with your admin id" />
            <div className="flex flex-wrap items-center gap-2 px-5 py-4">
              <select
                id="vendor-pick"
                className="h-9 rounded-lg border border-line bg-canvas px-2.5 text-sm text-ink"
                defaultValue=""
              >
                <option value="" disabled>
                  Pick vendor…
                </option>
                {vendors.map((v) => (
                  <option key={v.id} value={v.id}>
                    {v.name ?? v.phone ?? v.id}
                  </option>
                ))}
              </select>
              <ConfirmAction
                label="Assign"
                tone="accent"
                title="Assign this order?"
                description="Deterministic zone assignment already ran; this is your manual override."
                confirmLabel="Assign order"
                requireReason={false}
                onConfirm={() => {
                  const pick = (document.getElementById("vendor-pick") as HTMLSelectElement).value;
                  if (!pick) return Promise.resolve("Pick a vendor first.");
                  return mutate(`/v1/admin/orders/${o.id}/assign`, { vendor_id: pick });
                }}
              />
              <ConfirmAction
                label="Reassign"
                tone="accent"
                title="Reassign to another vendor?"
                description="Price stays frozen; the stop version bumps and the old vendor is notified."
                confirmLabel="Reassign"
                onConfirm={(reason) => {
                  const pick = (document.getElementById("vendor-pick") as HTMLSelectElement).value;
                  if (!pick) return Promise.resolve("Pick a vendor first.");
                  return mutate(`/v1/admin/orders/${o.id}/reassign`, { vendor_id: pick, reason });
                }}
              />
              <ConfirmAction
                label="Cancel override"
                title="Cancel after dispatch?"
                description="Dispatcher override: settlement runs per the cancel matrix; stop pulled from the route."
                confirmLabel="Cancel order"
                onConfirm={(reason) =>
                  mutate(`/v1/admin/orders/${o.id}/cancel-override`, { reason })
                }
              />
            </div>
          </Card>

          <Card>
            <CardHeader title="Activity" hint="Server event trail for this order" />
            {eventsQ.isLoading ? (
              <SkeletonBlock className="m-4 h-32" />
            ) : (
              <ol className="space-y-3 px-5 py-4">
                {(eventsQ.data?.data ?? []).slice(0, 12).map((e) => (
                  <li key={e.id} className="flex gap-3 text-sm">
                    <span className="mt-1.5 size-1.5 shrink-0 rounded-full bg-accent" />
                    <div className="min-w-0">
                      <p className="text-ink">
                        <span className="font-medium capitalize">{e.to_state}</span>
                        {e.from_state ? <span className="text-steel"> from {e.from_state}</span> : null}
                      </p>
                      <p className="text-xs text-steel">
                        {dateTime(e.created_at)} · {e.actor_role} {e.actor_id.slice(0, 8)}
                        {e.reason ? ` · ${e.reason}` : ""}
                      </p>
                    </div>
                  </li>
                ))}
              </ol>
            )}
          </Card>
        </div>
      </div>

      <p className="flex items-center gap-1.5 text-[11px] text-steel">
        <Phone className="size-3" aria-hidden />
        Customer contact stays masked here — call routing happens through the vendor app, never a public directory.
      </p>
    </div>
  );
}

function safeItems(json: string): Array<{ sku: string; qty: number }> {
  try {
    const parsed = JSON.parse(json) as Array<{ sku: string; qty: number }>;
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}
