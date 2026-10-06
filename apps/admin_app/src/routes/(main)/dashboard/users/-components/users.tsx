import * as React from "react";

import { useNavigate } from "@tanstack/react-router";
import {
  type ColumnFiltersState,
  type ColumnVisibilityState,
  type PaginationState,
  type SortingState,
  useTable,
} from "@tanstack/react-table";

import { format } from "date-fns";
import { Search } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Card, CardAction, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { InputGroup, InputGroupAddon, InputGroupInput } from "@/components/ui/input-group";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectGroup, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { toast } from "@/components/ui/toast";
import { errorMessage, useInvalidateAdmin } from "@/hooks/use-admin-api";
import { useCursorPages } from "@/hooks/use-cursor-pages";
import type { UserRow as ApiUserRow } from "@/lib/admin-types";
import { dataTableFeatures } from "@/lib/data-table-features";
import { adminPostServer } from "@/server/admin-api";

import { filters, type UserRow, type UserStatus } from "./data";
import { usersColumns } from "./users-columns";
import { UsersTable } from "./users-table";

const ROLE_LABEL: Record<string, string> = { user: "Customer", vendor: "Delivery Partner", admin: "Admin" };

function confirmLabel(busy: boolean, target: UserRow | null): string {
  if (busy) return "Working…";
  const blocked = target?.status === "Suspended" || target?.status === "Restricted";
  return blocked ? "Unblock" : "Confirm block";
}

function statusFor(u: ApiUserRow): UserStatus {
  if (u.suspended) return u.suspended_reason ? "Suspended" : "Restricted";
  return u.kyc_status === "pending" ? "Pending KYC" : "Active";
}

function adapt(u: ApiUserRow): UserRow {
  const status: UserStatus = statusFor(u);
  const created = new Date(u.created_at);
  return {
    id: u.id,
    name: u.name ?? u.phone ?? u.id,
    email: u.phone ? `+91 ${u.phone.slice(-10)}` : u.id,
    phone: u.phone,
    role: ROLE_LABEL[u.role] ?? u.role,
    status,
    joinedDate: Number.isNaN(created.getTime()) ? u.created_at : format(created, "dd MMM yyyy, h:mm a"),
  };
}

export function Users() {
  const navigate = useNavigate();
  const invalidate = useInvalidateAdmin();

  // Cursor-follow: page 1 loads, Load more appends. The table paginates the
  // loaded rows — counts below are loaded rows, never server totals.
  const {
    rows: serverRows,
    nextCursor,
    loadMore,
    isError,
    error,
  } = useCursorPages<ApiUserRow>("/v1/admin/users");
  const rows = React.useMemo(() => serverRows.map(adapt), [serverRows]);

  const [rowSelection, setRowSelection] = React.useState({});
  const [sorting, setSorting] = React.useState<SortingState>([{ id: "joinedDate", desc: true }]);
  const [columnFilters, setColumnFilters] = React.useState<ColumnFiltersState>([]);
  const [columnVisibility, setColumnVisibility] = React.useState<ColumnVisibilityState>({
    search: false,
  });
  const [pagination, setPagination] = React.useState<PaginationState>({ pageIndex: 0, pageSize: 10 });

  // Block / unblock sheet state (typed reason — server audits every action).
  const [target, setTarget] = React.useState<UserRow | null>(null);
  const [reason, setReason] = React.useState("");
  const [level, setLevel] = React.useState<"restrict" | "suspend">("suspend");
  const [busy, setBusy] = React.useState(false);

  const table = useTable({
    features: dataTableFeatures,
    data: rows,
    columns: usersColumns,
    state: { rowSelection, sorting, columnFilters, columnVisibility, pagination },
    getRowId: (row) => row.id,
    autoResetPageIndex: false,
    enableRowSelection: true,
    onRowSelectionChange: setRowSelection,
    onSortingChange: setSorting,
    onColumnFiltersChange: setColumnFilters,
    onColumnVisibilityChange: setColumnVisibility,
    onPaginationChange: setPagination,
    meta: {
      shodasha: {
        openDetail: (user: UserRow) => navigate({ to: "/dashboard/users/$userId", params: { userId: user.id } }),
        toggleSuspend: (user: UserRow) => {
          setTarget(user);
          setReason("");
          setLevel("suspend");
        },
      },
    } as never,
  });

  const searchQuery = (table.getColumn("search")?.getFilterValue() as string | undefined) ?? "";
  const roleFilter = (table.getColumn("role")?.getFilterValue() as string | undefined) ?? filters.role[0];
  const statusFilter = (table.getColumn("status")?.getFilterValue() as string | undefined) ?? filters.status[0];

  function setColumnSelectFilter(columnId: string, value: string | null) {
    table.getColumn(columnId)?.setFilterValue(!value || value === "All" ? undefined : value);
    table.setPageIndex(0);
  }

  async function submitSuspend() {
    if (!target || reason.trim().length < 3) return;
    const suspending = target.status !== "Suspended" && target.status !== "Restricted";
    setBusy(true);
    try {
      const res = (await adminPostServer({
        data: {
          path: `/v1/admin/users/${target.id}/${suspending ? "suspend" : "unsuspend"}`,
          body: suspending ? { reason: reason.trim(), level } : {},
        },
      })) as { revoked_sessions?: number };
      toast.add({
        title: suspending ? "Blocked" : "Unblocked",
        description: suspending
          ? `${target.name} ${level === "suspend" ? "suspended" : "restricted"} · ${res.revoked_sessions ?? 0} sessions revoked`
          : `${target.name} is active again`,
      });
      setTarget(null);
      invalidate("/v1/admin");
    } catch (err) {
      toast.add({ title: "Action failed", description: errorMessage(err), type: "error" });
    } finally {
      setBusy(false);
    }
  }

  return (
    <Card>
      <CardHeader className="border-b has-data-[slot=card-action]:grid-cols-1 md:has-data-[slot=card-action]:grid-cols-[1fr_auto]">
        <CardTitle className="text-xl leading-none">Users</CardTitle>
        <CardDescription className="max-w-sm leading-snug">
          Customers, delivery partners and admins — block with a typed reason; every action is audited.
        </CardDescription>
        <CardAction className="col-start-1 row-start-auto flex w-full flex-wrap justify-start gap-2 justify-self-stretch md:col-start-2 md:row-span-2 md:row-start-1 md:w-auto md:flex-nowrap md:justify-end md:justify-self-end">
          <InputGroup className="h-7 w-full md:w-64">
            <InputGroupAddon align="inline-start">
              <Search className="size-3.5" />
            </InputGroupAddon>
            <InputGroupInput
              className="h-7"
              placeholder="Search users..."
              value={searchQuery}
              onChange={(event) => {
                table.getColumn("search")?.setFilterValue(event.target.value || undefined);
                table.setPageIndex(0);
              }}
            />
          </InputGroup>
        </CardAction>
      </CardHeader>
      <CardContent className="flex flex-col gap-4 px-0">
        {isError ? <p className="px-4 text-destructive text-sm">{errorMessage(error)}</p> : null}
        <div className="flex flex-wrap items-center justify-between gap-3 px-4">
          <div className="flex flex-wrap items-center gap-3">
            <Select value={roleFilter} onValueChange={(value) => setColumnSelectFilter("role", value)}>
              <SelectTrigger size="sm">
                <span className="text-muted-foreground">Role:</span>
                <SelectValue />
              </SelectTrigger>
              <SelectContent align="start" alignItemWithTrigger={false}>
                <SelectGroup>
                  {filters.role.map((option) => (
                    <SelectItem key={option} value={option}>
                      {option}
                    </SelectItem>
                  ))}
                </SelectGroup>
              </SelectContent>
            </Select>
            <Select value={statusFilter} onValueChange={(value) => setColumnSelectFilter("status", value)}>
              <SelectTrigger size="sm">
                <span className="text-muted-foreground">Status:</span>
                <SelectValue />
              </SelectTrigger>
              <SelectContent align="start" alignItemWithTrigger={false}>
                <SelectGroup>
                  {filters.status.map((option) => (
                    <SelectItem key={option} value={option}>
                      {option}
                    </SelectItem>
                  ))}
                </SelectGroup>
              </SelectContent>
            </Select>
          </div>
        </div>

        <UsersTable table={table} />
        <div className="flex items-center justify-between px-4 pb-2">
          <p className="text-muted-foreground text-xs">
            {`${rows.length} loaded${nextCursor ? " · more on server" : ""}`}
          </p>
          {nextCursor ? (
            <Button variant="outline" size="sm" onClick={loadMore}>
              Load more
            </Button>
          ) : null}
        </div>
      </CardContent>

      {/* Typed block sheet — template dialog, old-admin flow */}
      <Dialog open={target != null} onOpenChange={(open) => !open && setTarget(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>
              {target && target.status !== "Suspended" && target.status !== "Restricted" ? "Block" : "Unblock"}{" "}
              {target?.name}
            </DialogTitle>
            <DialogDescription>
              {target && target.status !== "Suspended" && target.status !== "Restricted"
                ? "Blocking revokes the user's live sessions immediately. The reason is stored and audited."
                : "Unblocking restores access. The action is audited."}
            </DialogDescription>
          </DialogHeader>
          {target && target.status !== "Suspended" && target.status !== "Restricted" ? (
            <div className="flex flex-col gap-3">
              <div className="flex flex-col gap-1.5">
                <Label htmlFor="block-reason">Reason (min 3 chars)</Label>
                <Input
                  id="block-reason"
                  value={reason}
                  onChange={(e) => setReason(e.target.value)}
                  placeholder="e.g. Repeated short delivery"
                />
              </div>
              <div className="flex flex-col gap-1.5">
                <Label>Level</Label>
                <Select value={level} onValueChange={(v) => setLevel((v ?? "suspend") as "restrict" | "suspend")}>
                  <SelectTrigger className="w-full">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="restrict">restrict — login stays, writes blocked</SelectItem>
                    <SelectItem value="suspend">suspend — sessions revoked</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            </div>
          ) : null}
          <DialogFooter>
            <Button variant="outline" onClick={() => setTarget(null)}>
              Cancel
            </Button>
            <Button
              variant={
                target && target.status !== "Suspended" && target.status !== "Restricted" ? "destructive" : "default"
              }
              disabled={
                busy ||
                (target != null &&
                  target.status !== "Suspended" &&
                  target.status !== "Restricted" &&
                  reason.trim().length < 3)
              }
              onClick={() => void submitSuspend()}
            >
              {confirmLabel(busy, target)}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </Card>
  );
}
