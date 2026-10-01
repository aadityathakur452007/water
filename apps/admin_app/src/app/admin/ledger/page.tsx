"use client";

import { useState } from "react";
import Link from "next/link";
import { ChevronLeft, ChevronRight, Layers } from "lucide-react";
import { Card, EmptyState, ErrorState, PageHeader, SkeletonRows } from "@/shared/ui/primitives";
import { proxyGet } from "@/features/dashboard/api";
import { useQuery } from "@tanstack/react-query";
import { num, paise, phoneMasked } from "@/lib/format";
import type { LedgerRow, Page } from "@/lib/types";

export default function LedgerPage() {
  const [cursor, setCursor] = useState("");
  const search = new URLSearchParams({ limit: "50" });
  if (cursor) search.set("cursor", cursor);

  const { data, isLoading, isError, error } = useQuery({
    queryKey: ["ledger", cursor],
    queryFn: () => proxyGet<Page<LedgerRow>>(`/v1/admin/ledger?${search.toString()}`),
  });
  const rows = data?.data ?? [];
  const totals = rows.reduce(
    (acc, r) => ({
      held: acc.held + r.held,
      deposit: acc.deposit + (r.deposit_paid - r.deposit_refunded),
      dues: acc.dues + r.dues,
    }),
    { held: 0, deposit: 0, dues: 0 },
  );

  return (
    <div className="space-y-5">
      <PageHeader
        title="Jar ledger"
        description="The asset book: every jar with a customer, every rupee of deposit held, every rupee of dues. The server refuses negative jars — what you see is physically possible."
      />

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
        <Card className="px-5 py-4" stagger={0}>
          <p className="text-xs font-medium uppercase tracking-wide text-steel">Jars on this page</p>
          <p className="tnum mt-1.5 text-2xl font-semibold text-ink">{num(totals.held)}</p>
        </Card>
        <Card className="px-5 py-4" stagger={1}>
          <p className="text-xs font-medium uppercase tracking-wide text-steel">Deposit liability</p>
          <p className="tnum mt-1.5 text-2xl font-semibold text-ink">{paise(totals.deposit)}</p>
        </Card>
        <Card className="px-5 py-4" stagger={2}>
          <p className="text-xs font-medium uppercase tracking-wide text-steel">Dues</p>
          <p className={`tnum mt-1.5 text-2xl font-semibold ${totals.dues > 0 ? "text-bad" : "text-ink"}`}>
            {paise(totals.dues)}
          </p>
        </Card>
      </div>

      <Card>
        {isError ? (
          <div className="p-4">
            <ErrorState message={(error as Error).message} />
          </div>
        ) : isLoading ? (
          <SkeletonRows rows={8} cols={6} />
        ) : rows.length === 0 ? (
          <EmptyState
            icon={<Layers className="size-5" />}
            title="No ledger entries yet"
            hint="Rows appear with the first deposit event — book an order with jars to see it live."
          />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-line text-left text-[11px] uppercase tracking-wide text-faint">
                  <th className="px-5 py-2.5 font-medium">Customer</th>
                  <th className="px-3 py-2.5 font-medium">Jars held</th>
                  <th className="px-3 py-2.5 font-medium">Deposit paid</th>
                  <th className="px-3 py-2.5 font-medium">Deposit refunded</th>
                  <th className="px-5 py-2.5 font-medium">Dues</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-line-soft">
                {rows.map((r) => (
                  <tr key={r.customer_id} className="transition-colors hover:bg-canvas">
                    <td className="px-5 py-3">
                      <Link href={`/admin/users/${r.customer_id}`} className="font-medium text-accent hover:underline">
                        {r.customer_name ?? r.customer_id.slice(0, 10)}
                      </Link>
                      <span className="tnum block text-xs text-faint">{phoneMasked(r.customer_phone)}</span>
                    </td>
                    <td className="tnum px-3 py-3">
                      <span className={r.held > 3 ? "font-medium text-warn" : "text-ink"}>{num(r.held)}</span>
                      {r.held > 3 ? <span className="ml-1.5 text-xs text-warn">hold-limit</span> : null}
                    </td>
                    <td className="tnum px-3 py-3 text-steel">{paise(r.deposit_paid)}</td>
                    <td className="tnum px-3 py-3 text-steel">{paise(r.deposit_refunded)}</td>
                    <td className={`tnum px-5 py-3 ${r.dues > 0 ? "font-medium text-bad" : "text-steel"}`}>
                      {paise(r.dues)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        {data?.next_cursor ? (
          <div className="flex items-center justify-between border-t border-line-soft px-5 py-3">
            <span className="text-xs text-faint">{num(rows.length)} shown</span>
            <div className="flex gap-2">
              {cursor ? (
                <button
                  type="button"
                  onClick={() => setCursor("")}
                  className="inline-flex h-8 items-center gap-1 rounded-lg border border-line px-2.5 text-xs font-medium text-steel hover:bg-canvas"
                >
                  <ChevronLeft className="size-3.5" aria-hidden /> First
                </button>
              ) : null}
              <button
                type="button"
                onClick={() => setCursor(data.next_cursor ?? "")}
                className="inline-flex h-8 items-center gap-1 rounded-lg border border-line px-2.5 text-xs font-medium text-steel hover:bg-canvas"
              >
                Next <ChevronRight className="size-3.5" aria-hidden />
              </button>
            </div>
          </div>
        ) : null}
      </Card>
    </div>
  );
}
