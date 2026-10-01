"use client";

import { useState } from "react";
import { ChevronLeft, ChevronRight, ScrollText, Search } from "lucide-react";
import { Badge, Card, EmptyState, ErrorState, PageHeader, SkeletonRows } from "@/shared/ui/primitives";
import { useAudit } from "@/features/dashboard/api";
import { dateTime, shortId } from "@/lib/format";

const ENTITIES = ["", "users", "orders", "ledger", "payments", "config", "routes", "strikes"];

function toneFor(action: string): "bad" | "warn" | "accent" | "neutral" {
  if (action.includes("suspend") || action.includes("cancel")) return "bad";
  if (action.includes("adjust") || action.includes("write") || action.includes("refund")) return "warn";
  if (action.includes("assign") || action.includes("config")) return "accent";
  return "neutral";
}

export default function AuditPage() {
  const [entity, setEntity] = useState("");
  const [actor, setActor] = useState("");
  const [action, setAction] = useState("");
  const [limit, setLimit] = useState(100);

  const { data, isLoading, isError, error, isFetching } = useAudit({
    entity: entity || undefined,
    actor_id: actor || undefined,
    action: action || undefined,
    limit,
  });
  const rows = data?.data ?? [];

  return (
    <div className="space-y-5">
      <PageHeader
        title="Audit log"
        description="The system journal: every money edit, block, assignment and config change — with actor, before/after and trace id."
      />

      <div className="flex flex-wrap items-center gap-2">
        <div className="relative">
          <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-faint" aria-hidden />
          <input
            value={actor}
            onChange={(e) => setActor(e.target.value)}
            placeholder="Actor id"
            className="tnum h-9 w-52 rounded-lg border border-line bg-surface pl-9 pr-3 text-sm text-ink placeholder:text-faint"
          />
        </div>
        <input
          value={action}
          onChange={(e) => setAction(e.target.value)}
          placeholder="Action (e.g. user.suspend)"
          className="tnum h-9 w-56 rounded-lg border border-line bg-surface px-3 text-sm text-ink placeholder:text-faint"
        />
        <select
          value={entity}
          onChange={(e) => setEntity(e.target.value)}
          aria-label="Filter by entity"
          className="h-9 rounded-lg border border-line bg-surface px-2.5 text-sm capitalize text-ink"
        >
          {ENTITIES.map((e) => (
            <option key={e} value={e}>{e || "All entities"}</option>
          ))}
        </select>
        <select
          value={limit}
          onChange={(e) => setLimit(Number(e.target.value))}
          aria-label="Row count"
          className="h-9 rounded-lg border border-line bg-surface px-2.5 text-sm text-ink"
        >
          {[50, 100, 200].map((n) => (
            <option key={n} value={n}>{n} rows</option>
          ))}
        </select>
        {isFetching ? <span className="text-xs text-faint">syncing…</span> : null}
      </div>

      <Card>
        {isError ? (
          <div className="p-4">
            <ErrorState message={(error as Error).message} />
          </div>
        ) : isLoading ? (
          <SkeletonRows rows={10} cols={5} />
        ) : rows.length === 0 ? (
          <EmptyState
            icon={<ScrollText className="size-5" />}
            title="No audit rows match"
            hint="Every write in the system lands here. Clear the filters to see the latest activity."
          />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-line text-left text-[11px] uppercase tracking-wide text-faint">
                  <th className="px-5 py-2.5 font-medium">When</th>
                  <th className="px-3 py-2.5 font-medium">Action</th>
                  <th className="px-3 py-2.5 font-medium">Actor</th>
                  <th className="px-3 py-2.5 font-medium">Entity</th>
                  <th className="px-5 py-2.5 font-medium">Trace</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-line-soft">
                {rows.map((a) => (
                  <tr key={a.id} className="align-top transition-colors hover:bg-canvas">
                    <td className="whitespace-nowrap px-5 py-3 text-xs text-steel">{dateTime(a.created_at)}</td>
                    <td className="px-3 py-3">
                      <Badge tone={toneFor(a.action)}>{a.action}</Badge>
                    </td>
                    <td className="tnum px-3 py-3 text-xs text-steel">
                      {shortId(a.actor_id)}
                      <span className="block text-faint">{a.actor_role}</span>
                    </td>
                    <td className="px-3 py-3 text-xs text-steel">
                      <span className="capitalize">{a.entity}</span>
                      <span className="tnum block text-faint">{shortId(a.entity_id)}</span>
                    </td>
                    <td className="tnum px-5 py-3 text-xs text-faint">{a.trace_id || "—"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        {rows.length >= limit ? (
          <div className="flex items-center justify-between border-t border-line-soft px-5 py-3">
            <span className="text-xs text-faint">{rows.length} rows</span>
            <button
              type="button"
              onClick={() => setLimit(Math.min(limit * 2, 200))}
              className="inline-flex h-8 items-center gap-1 rounded-lg border border-line px-2.5 text-xs font-medium text-steel hover:bg-canvas"
            >
              Load more <ChevronRight className="size-3.5" aria-hidden />
            </button>
          </div>
        ) : (
          <div className="border-t border-line-soft px-5 py-3 text-xs text-faint">
            <ChevronLeft className="mr-1 inline size-3" />
            Oldest entries stay in D1 per the retention policy (money/role events 1 year).
          </div>
        )}
      </Card>
    </div>
  );
}
