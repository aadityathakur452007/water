"use client";

import { useQuery, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { ArrowLeft, Ban, CircleCheck, Package, ShieldOff, Wallet } from "lucide-react";
import { Badge, Card, CardHeader, ErrorState, SkeletonBlock, SkeletonRows } from "@/shared/ui/primitives";
import { ConfirmAction } from "@/shared/ui/actions";
import { proxyGet } from "@/features/dashboard/api";
import { dateTime, num, paise, phoneMasked } from "@/lib/format";
import type { UserDetail } from "@/lib/types";

export function UserDetailPanel({ userId }: { userId: string }) {
  const qc = useQueryClient();
  const { data, isLoading, isError, error } = useQuery({
    queryKey: ["user", userId],
    queryFn: () => proxyGet<UserDetail>(`/v1/admin/users/${userId}/detail`),
    retry: false,
  });

  async function action(path: string, body?: unknown): Promise<string | null> {
    const res = await fetch(`/api/admin-actions?url=${encodeURIComponent(path)}`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body ?? {}),
    });
    if (!res.ok) {
      const err = (await res.json().catch(() => ({}))) as { error?: { message?: string } };
      return err.error?.message ?? `Action failed (${res.status})`;
    }
    await qc.invalidateQueries({ queryKey: ["user", userId] });
    await qc.invalidateQueries({ queryKey: ["users"] });
    return null;
  }

  if (isLoading) {
    return (
      <div className="space-y-4">
        <SkeletonBlock className="h-8 w-56" />
        <SkeletonRows rows={4} cols={4} />
      </div>
    );
  }
  if (isError || !data) {
    return <ErrorState message={(error as Error)?.message ?? "User not found."} />;
  }

  const u = data.user;
  const blocked = Boolean(u.suspended);

  return (
    <div className="space-y-5">
      <div className="flex items-start gap-3">
        <Link
          href="/admin/users"
          className="inline-flex size-8 items-center justify-center rounded-lg border border-line text-steel hover:bg-canvas"
          aria-label="Back to users"
        >
          <ArrowLeft className="size-4" aria-hidden />
        </Link>
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <h1 className="text-lg font-semibold tracking-tight text-ink">{u.name ?? u.id.slice(0, 10)}</h1>
            <Badge tone="neutral">{u.role}</Badge>
            {blocked ? <Badge tone="bad">blocked</Badge> : <Badge tone="good">active</Badge>}
          </div>
          <p className="tnum mt-0.5 text-sm text-steel">
            {phoneMasked(u.phone)} · joined {dateTime(u.created_at)}
          </p>
        </div>
        <div className="ml-auto flex items-center gap-2">
          {blocked ? (
            <ConfirmAction
              label="Unblock"
              tone="accent"
              requireReason={false}
              title="Unblock this account?"
              description="Ordering and login resume immediately. The block history stays in the audit log."
              confirmLabel="Unblock"
              onConfirm={() => action(`/v1/admin/users/${userId}/unsuspend`)}
            />
          ) : (
            <ConfirmAction
              label="Block account"
              title="Block this account?"
              description="Suspends ordering instantly and revokes every live session. Restrict blocks COD only; Suspend blocks everything. Never deletes the account."
              confirmLabel="Block now"
              onConfirm={(reason) =>
                action(`/v1/admin/users/${userId}/suspend`, { reason, level: "suspend" })
              }
            />
          )}
        </div>
      </div>

      {blocked && u.suspended_reason ? (
        <div className="rounded-xl border border-bad/30 bg-bad-soft/50 px-4 py-3 text-sm text-bad">
          <p className="flex items-center gap-1.5 font-medium">
            <Ban className="size-4" aria-hidden /> Blocked {dateTime(u.suspended_at)} — {u.suspended_reason}
          </p>
        </div>
      ) : null}

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <Card className="px-5 py-4" stagger={0}>
          <p className="flex items-center gap-1.5 text-xs font-medium uppercase tracking-wide text-steel">
            <Package className="size-3.5" aria-hidden /> Orders
          </p>
          <p className="tnum mt-1.5 text-2xl font-semibold text-ink">{num(data.orders_count)}</p>
          <p className="mt-1 text-xs text-steel">{paise(data.spend_paise)} lifetime · last {dateTime(data.last_order_at)}</p>
        </Card>
        <Card className="px-5 py-4" stagger={1}>
          <p className="flex items-center gap-1.5 text-xs font-medium uppercase tracking-wide text-steel">
            <Wallet className="size-3.5" aria-hidden /> Jars held
          </p>
          <p className="tnum mt-1.5 text-2xl font-semibold text-ink">{num(data.ledger.held)}</p>
          <p className="mt-1 text-xs text-steel">
            deposit {paise(data.ledger.deposit_paid - data.ledger.deposit_refunded)} held
          </p>
        </Card>
        <Card className="px-5 py-4" stagger={2}>
          <p className="text-xs font-medium uppercase tracking-wide text-steel">Dues</p>
          <p className={`tnum mt-1.5 text-2xl font-semibold ${data.ledger.dues > 0 ? "text-bad" : "text-ink"}`}>
            {paise(data.ledger.dues)}
          </p>
          <p className="mt-1 text-xs text-steel">owed by customer</p>
        </Card>
        <Card className="px-5 py-4" stagger={3}>
          <p className="flex items-center gap-1.5 text-xs font-medium uppercase tracking-wide text-steel">
            <ShieldOff className="size-3.5" aria-hidden /> Sessions
          </p>
          <p className="tnum mt-1.5 text-2xl font-semibold text-ink">{num(data.active_sessions)}</p>
          <p className="mt-1 text-xs text-steel">
            {num(data.devices)} devices · {num(data.open_strikes)} open strikes
          </p>
        </Card>
      </div>

      <Card>
        <CardHeader title="Recent orders" hint="Last 10 — full trail in the Orders queue" />
        {data.recent_orders.length === 0 ? (
          <p className="px-5 py-6 text-sm text-steel">
            <CircleCheck className="mr-1.5 inline size-4 text-faint" aria-hidden />
            No orders yet.
          </p>
        ) : (
          <ul className="divide-y divide-line-soft">
            {data.recent_orders.map((o) => (
              <li key={o.id}>
                <Link
                  href={`/admin/orders/${o.id}`}
                  className="flex items-center gap-3 px-5 py-3 transition-colors hover:bg-canvas"
                >
                  <span className="tnum text-sm font-medium text-accent">{o.id.slice(0, 14)}</span>
                  <Badge tone={o.state === "delivered" ? "good" : o.state === "cancelled" ? "bad" : "neutral"}>
                    {o.state}
                  </Badge>
                  <span className="ml-auto text-xs text-steel">{dateTime(o.created_at)}</span>
                  <span className="tnum text-sm font-medium text-ink">{paise(o.total)}</span>
                </Link>
              </li>
            ))}
          </ul>
        )}
      </Card>
    </div>
  );
}
