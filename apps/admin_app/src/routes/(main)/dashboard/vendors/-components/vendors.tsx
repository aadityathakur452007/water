import * as React from "react";

import { useNavigate } from "@tanstack/react-router";
import { type ColumnFiltersState, type PaginationState, type SortingState, useTable } from "@tanstack/react-table";

import { cn } from "cn";
import { format } from "date-fns";
import { Search } from "lucide-react";

import { Avatar, AvatarBadge, AvatarFallback } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { InputGroup, InputGroupAddon, InputGroupInput } from "@/components/ui/input-group";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { toast } from "@/components/ui/toast";
import { errorMessage, useAdminQuery, useInvalidateAdmin } from "@/hooks/use-admin-api";
import type { UserRow as ApiUserRow, Page, VendorDetail } from "@/lib/admin-types";
import { dataTableFeatures } from "@/lib/data-table-features";
import { num, phoneMasked } from "@/lib/money";
import { getInitials } from "@/lib/utils";
import { adminPostServer } from "@/server/admin-api";

type VendorView = {
  id: string;
  name: string;
  phone: string | null;
  kyc: string;
  status: string;
  joinedDate: string;
  onDuty: number;
  inHand: number;
  reviewHold: number;
};

const VENDOR_COUNT = 50;

/** Crash-proof date: one bad created_at must never take down the page. */
function joinedLabel(value: unknown): string {
  try {
    const d = value instanceof Date ? value : new Date(value as string);
    if (Number.isNaN(d.getTime())) return "—";
    return format(d, "dd MMM yyyy");
  } catch {
    return "—";
  }
}

function holdLabel(busy: boolean, held: boolean): string {
  if (busy) return "…";
  return held ? "Release hold" : "Review hold";
}

export function Vendors() {
  const navigate = useNavigate();
  const invalidate = useInvalidateAdmin();

  const { data, isError, error } = useAdminQuery<Page<ApiUserRow>>(`/v1/admin/vendors?limit=${VENDOR_COUNT}`);
  const rows = React.useMemo(
    () =>
      (data?.data ?? []).map(
        (v): VendorView => ({
          id: v.id,
          name: v.name ?? v.phone ?? v.id,
          phone: v.phone,
          kyc: v.kyc_status,
          status: v.suspended ? "Blocked" : "Active",
          joinedDate: joinedLabel(v.created_at),
          onDuty: 0,
          inHand: 0,
          reviewHold: 0,
        }),
      ),
    [data],
  );

  const [sorting, setSorting] = React.useState<SortingState>([]);
  const [columnFilters, setColumnFilters] = React.useState<ColumnFiltersState>([]);
  const [pagination, setPagination] = React.useState<PaginationState>({ pageIndex: 0, pageSize: 10 });
  const [busyId, setBusyId] = React.useState<string | null>(null);

  const columns = [
    {
      accessorKey: "name",
      header: "Vendor",
      cell: ({ row }: { row: { original: VendorView } }) => (
        <div className="flex items-center gap-3">
          <Avatar size="lg" className="font-medium">
            <AvatarFallback>{getInitials(row.original.name)}</AvatarFallback>
            <AvatarBadge className={row.original.status === "Active" ? "bg-green-600" : "bg-destructive"} />
          </Avatar>
          <div className="min-w-0">
            <div className="truncate font-medium text-foreground text-sm">{row.original.name}</div>
            <div className="truncate text-muted-foreground text-sm">{phoneMasked(row.original.phone)}</div>
          </div>
        </div>
      ),
    },
    {
      accessorKey: "kyc",
      header: "KYC",
      cell: ({ row }: { row: { original: VendorView } }) => <Badge variant="outline">{row.original.kyc}</Badge>,
    },
    {
      accessorKey: "status",
      header: "Status",
      cell: ({ row }: { row: { original: VendorView } }) => (
        <Badge
          variant="outline"
          className={
            row.original.status === "Active"
              ? "border-emerald-500/20 bg-emerald-500/10 text-emerald-600 dark:text-emerald-400"
              : "border-destructive/20 bg-destructive/10 text-destructive"
          }
        >
          {row.original.status}
        </Badge>
      ),
    },
    {
      accessorKey: "joinedDate",
      header: "Joined",
      cell: ({ row }: { row: { original: VendorView } }) => (
        <span className="text-muted-foreground text-sm">{row.original.joinedDate}</span>
      ),
    },
    {
      id: "actions",
      header: () => <div className="text-right">Actions</div>,
      cell: ({ row }: { row: { original: VendorView } }) => (
        <div className="flex justify-end gap-2">
          <Button
            variant="outline"
            size="sm"
            onClick={() => navigate({ to: "/dashboard/vendors/$vendorId", params: { vendorId: row.original.id } })}
          >
            Open
          </Button>
          <Button
            variant={row.original.reviewHold ? "default" : "outline"}
            size="sm"
            disabled={busyId === row.original.id}
            onClick={() => void toggleHold(row.original)}
          >
            {holdLabel(busyId === row.original.id, row.original.reviewHold > 0)}
          </Button>
        </div>
      ),
    },
  ];

  const table = useTable({
    features: dataTableFeatures,
    data: rows,
    columns: columns as never,
    state: { sorting, columnFilters, pagination },
    getRowId: (row) => row.id,
    onSortingChange: setSorting,
    onColumnFiltersChange: setColumnFilters,
    onPaginationChange: setPagination,
  });

  const searchQuery = (table.getColumn("name")?.getFilterValue() as string | undefined) ?? "";

  async function toggleHold(v: VendorView) {
    setBusyId(v.id);
    try {
      const releasing = v.reviewHold > 0;
      await adminPostServer({
        data: {
          path: `/v1/admin/vendors/${v.id}/${releasing ? "release" : "review-hold"}`,
          body: releasing ? {} : { note: "Review hold from vendors list" },
        },
      });
      toast.add({ title: releasing ? "Hold released" : "Review hold set", description: v.name });
      invalidate("/v1/admin");
    } catch (err) {
      toast.add({ title: "Action failed", description: errorMessage(err), type: "error" });
    } finally {
      setBusyId(null);
    }
  }

  // Custody data enriches rows when the worker serves it (optional join).
  const { data: custody } =
    useAdminQuery<Page<{ vendor_id: string; on_duty: number; in_hand: number }>>("/v1/admin/custody");

  return (
    <Card>
      <CardHeader className="border-b">
        <CardTitle className="text-xl leading-none">Vendors</CardTitle>
        <CardDescription>
          Delivery partners — capacity, custody and review holds. Open a vendor for the full picture.
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-4 px-0">
        {isError ? <p className="px-4 text-destructive text-sm">{errorMessage(error)}</p> : null}
        <div className="px-4">
          <InputGroup className="h-7 w-full md:w-64">
            <InputGroupAddon align="inline-start">
              <Search className="size-3.5" />
            </InputGroupAddon>
            <InputGroupInput
              className="h-7"
              placeholder="Search vendors..."
              value={searchQuery}
              onChange={(event) => {
                table.getColumn("name")?.setFilterValue(event.target.value || undefined);
                table.setPageIndex(0);
              }}
            />
          </InputGroup>
        </div>

        <Table className="**:data-[slot='table-cell']:px-4 **:data-[slot='table-head']:px-4">
          <TableHeader className="[&_tr]:border-t">
            <TableRow>
              <TableHead className="py-4 font-normal">Vendor</TableHead>
              <TableHead className="py-4 font-normal">On duty</TableHead>
              <TableHead className="py-4 font-normal">Jars in hand</TableHead>
              <TableHead className="py-4 font-normal">KYC</TableHead>
              <TableHead className="py-4 font-normal">Status</TableHead>
              <TableHead className="py-4 text-right font-normal">Actions</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {table.getRowModel().rows.length ? (
              table.getRowModel().rows.map((row) => {
                const v = row.original;
                const c = (custody?.data ?? []).find((x) => x.vendor_id === v.id);
                return (
                  <TableRow
                    key={row.id}
                    className="cursor-pointer border-border/60 hover:bg-white/2.5"
                    onClick={() => navigate({ to: "/dashboard/vendors/$vendorId", params: { vendorId: v.id } })}
                  >
                    <TableCell className="px-3 py-3">{columns[0].cell({ row: { original: v } })}</TableCell>
                    <TableCell className="px-3 py-3 text-sm tabular-nums">{num(c?.on_duty ?? 0)}</TableCell>
                    <TableCell className="px-3 py-3 text-sm tabular-nums">{num(c?.in_hand ?? 0)}</TableCell>
                    <TableCell className="px-3 py-3">
                      <Badge variant="outline">{v.kyc}</Badge>
                    </TableCell>
                    <TableCell className="px-3 py-3">{columns[2].cell({ row: { original: v } })}</TableCell>
                    <TableCell className="px-3 py-3 text-right">{columns[4].cell({ row: { original: v } })}</TableCell>
                  </TableRow>
                );
              })
            ) : (
              <TableRow>
                <TableCell colSpan={6} className="h-24 text-center text-muted-foreground">
                  No vendors match.
                </TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  );
}

export type { VendorDetail };
export { cn };
