"use client";

import { useState } from "react";
import Link from "next/link";
import { ChevronLeft, ChevronRight, Search, UsersRound } from "lucide-react";
import { Badge, Card, EmptyState, ErrorState, PageHeader, SkeletonRows } from "@/shared/ui/primitives";
import { DataTable, columnHelper } from "@/shared/ui/data-table";
import { proxyGet } from "@/features/dashboard/api";
import { useQuery } from "@tanstack/react-query";
import { dateTime, phoneMasked } from "@/lib/format";
import type { Page, UserRow } from "@/lib/types";

const ROLES = ["", "user", "vendor", "admin"];

const helper = columnHelper<UserRow>();
const cols = helper.columns([
  helper.accessor((u) => u.name ?? u.id, {
    id: "name",
    header: "Name",
    cell: (c) => (
      <Link href={`/admin/users/${c.row.original.id}`} className="font-medium text-accent hover:underline">
        {c.row.original.name ?? c.row.original.id.slice(0, 10)}
      </Link>
    ),
  }),
  helper.accessor((u) => u.phone ?? "", {
    id: "phone",
    header: "Phone",
    cell: (c) => <span className="tnum text-steel">{phoneMasked(c.row.original.phone)}</span>,
  }),
  helper.accessor("role", {
    id: "role",
    header: "Role",
    cell: (c) => <span className="capitalize text-steel">{c.getValue<string>()}</span>,
  }),
  helper.display({
    id: "status",
    header: "Status",
    cell: (c) => {
      const u = c.row.original;
      return u.suspended ? (
        <Badge tone="bad">blocked</Badge>
      ) : u.role === "vendor" && u.kyc_status !== "verified" ? (
        <Badge tone="warn">kyc {u.kyc_status}</Badge>
      ) : (
        <Badge tone="good">active</Badge>
      );
    },
  }),
  helper.accessor((u) => u.created_at ?? "", {
    id: "joined",
    header: "Joined",
    cell: (c) => <span className="text-xs text-steel">{dateTime(c.row.original.created_at)}</span>,
  }),
]);

const CSV = [
  { label: "Name", value: (u: UserRow) => u.name ?? u.id },
  { label: "Phone", value: (u: UserRow) => u.phone ?? "" },
  { label: "Role", value: (u: UserRow) => u.role },
  {
    label: "Status",
    value: (u: UserRow) =>
      u.suspended
        ? "blocked"
        : u.role === "vendor" && u.kyc_status !== "verified"
          ? `kyc ${u.kyc_status}`
          : "active",
  },
  { label: "Joined", value: (u: UserRow) => u.created_at ?? "" },
];

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
        {isFetching ? <span className="text-xs text-steel">syncing…</span> : null}
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
          <DataTable
            columns={cols}
            data={rows}
            csv={CSV}
            csvFilename={`shodasha-users-${new Date().toISOString().slice(0, 10)}.csv`}
          />
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
