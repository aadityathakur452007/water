"use client";

import { useState } from "react";
import Link from "next/link";
import { ChevronLeft, ChevronRight, Search, UsersRound } from "lucide-react";
import { Badge, Card, EmptyState, ErrorState, PageHeader, SkeletonRows } from "@/shared/ui/primitives";
import { proxyGet } from "@/features/dashboard/api";
import { useQuery } from "@tanstack/react-query";
import { dateTime, phoneMasked } from "@/lib/format";
import type { Page, UserRow } from "@/lib/types";

const ROLES = ["", "user", "vendor", "admin"];

export function UsersTable() {
  const [query, setQuery] = useState("");
  const [role, setRole] = useState("");
  const [susp, setSusp] = useState("");
  const [cursor, setCursor] = useState("");

  const search = new URLSearchParams();
  if (query) search.set("query", query);
  if (role) search.set("role", role);
  if (susp) search.set("suspended", susp === "1" ? "1" : "0");
  if (cursor) search.set("cursor", cursor);
  search.set("limit", "50");

  const { data, isLoading, isError, error, isFetching } = useQuery({
    queryKey: ["users", query, role, susp, cursor],
    queryFn: () => proxyGet<Page<UserRow>>(`/v1/admin/users?${search.toString()}`),
  });
  const rows = data?.data ?? [];

  return (
    <div className="space-y-5">
      <PageHeader
        title="Users"
        description="Every account — customers, vendors, admins. Blocking lives on the profile page."
      />

      <div className="flex flex-wrap items-center gap-2">
        <div className="relative">
          <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-faint" aria-hidden />
          <input
            value={query}
            onChange={(e) => {
              setQuery(e.target.value);
              setCursor("");
            }}
            placeholder="Search name or phone"
            className="h-9 w-64 rounded-lg border border-line bg-surface pl-9 pr-3 text-sm text-ink placeholder:text-faint"
          />
        </div>
        <select
          value={role}
          onChange={(e) => {
            setRole(e.target.value);
            setCursor("");
          }}
          aria-label="Filter by role"
          className="h-9 rounded-lg border border-line bg-surface px-2.5 text-sm capitalize text-ink"
        >
          {ROLES.map((r) => (
            <option key={r} value={r}>{r || "All roles"}</option>
          ))}
        </select>
        <select
          value={susp}
          onChange={(e) => {
            setSusp(e.target.value);
            setCursor("");
          }}
          aria-label="Filter by blocked state"
          className="h-9 rounded-lg border border-line bg-surface px-2.5 text-sm text-ink"
        >
          <option value="">Active + blocked</option>
          <option value="0">Active only</option>
          <option value="1">Blocked only</option>
        </select>
        {isFetching ? <span className="text-xs text-faint">syncing…</span> : null}
      </div>

      <Card>
        {isError ? (
          <div className="p-4">
            <ErrorState message={(error as Error).message} />
          </div>
        ) : isLoading ? (
          <SkeletonRows rows={8} cols={5} />
        ) : rows.length === 0 ? (
          <EmptyState
            icon={<UsersRound className="size-5" />}
            title="No accounts match"
            hint="Try a different phone digits, or clear the role filter."
          />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-line text-left text-[11px] uppercase tracking-wide text-faint">
                  <th className="px-5 py-2.5 font-medium">Name</th>
                  <th className="px-3 py-2.5 font-medium">Phone</th>
                  <th className="px-3 py-2.5 font-medium">Role</th>
                  <th className="px-3 py-2.5 font-medium">Status</th>
                  <th className="px-5 py-2.5 font-medium">Joined</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-line-soft">
                {rows.map((u) => (
                  <tr key={u.id} className="transition-colors hover:bg-canvas">
                    <td className="px-5 py-3">
                      <Link href={`/admin/users/${u.id}`} className="font-medium text-accent hover:underline">
                        {u.name ?? u.id.slice(0, 10)}
                      </Link>
                    </td>
                    <td className="tnum px-3 py-3 text-steel">{phoneMasked(u.phone)}</td>
                    <td className="px-3 py-3 text-steel capitalize">{u.role}</td>
                    <td className="px-3 py-3">
                      {u.suspended ? (
                        <Badge tone="bad">blocked</Badge>
                      ) : u.role === "vendor" && u.kyc_status !== "verified" ? (
                        <Badge tone="warn">kyc {u.kyc_status}</Badge>
                      ) : (
                        <Badge tone="good">active</Badge>
                      )}
                    </td>
                    <td className="px-5 py-3 text-xs text-steel">{dateTime(u.created_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        {data?.next_cursor ? (
          <div className="flex justify-end border-t border-line-soft px-5 py-3">
            <button
              type="button"
              onClick={() => setCursor(data.next_cursor ?? "")}
              className="inline-flex h-8 items-center gap-1 rounded-lg border border-line px-2.5 text-xs font-medium text-steel hover:bg-canvas"
            >
              Next <ChevronRight className="size-3.5" aria-hidden />
            </button>
          </div>
        ) : null}
        {cursor ? (
          <div className="border-t border-line-soft px-5 py-3">
            <button
              type="button"
              onClick={() => setCursor("")}
              className="inline-flex h-8 items-center gap-1 rounded-lg border border-line px-2.5 text-xs font-medium text-steel hover:bg-canvas"
            >
              <ChevronLeft className="size-3.5" aria-hidden /> First page
            </button>
          </div>
        ) : null}
      </Card>
    </div>
  );
}
