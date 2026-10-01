"use client";

import Link from "next/link";
import { Truck } from "lucide-react";
import { Badge, Card, EmptyState, ErrorState, PageHeader, SkeletonRows } from "@/shared/ui/primitives";
import { DataTable, columnHelper } from "@/shared/ui/data-table";
import { proxyGet } from "@/features/dashboard/api";
import { useQuery } from "@tanstack/react-query";
import { phoneMasked } from "@/lib/format";

type VendorListRow = {
  id: string;
  name: string | null;
  phone: string | null;
  kyc_status: string;
  suspended: number;
};

const helper = columnHelper<VendorListRow>();
const cols = helper.columns([
  helper.accessor((v) => v.name ?? v.id, {
    id: "vendor",
    header: "Vendor",
    cell: (c) => (
      <Link href={`/admin/vendors/${c.row.original.id}`} className="font-medium text-accent hover:underline">
        {c.row.original.name ?? c.row.original.id.slice(0, 10)}
      </Link>
    ),
  }),
  helper.accessor((v) => v.phone ?? "", {
    id: "phone",
    header: "Phone",
    cell: (c) => <span className="tnum text-steel">{phoneMasked(c.row.original.phone)}</span>,
  }),
  helper.accessor("kyc_status", {
    id: "kyc",
    header: "KYC",
    cell: (c) => (
      <Badge tone={c.row.original.kyc_status === "verified" ? "good" : "warn"}>
        {c.row.original.kyc_status}
      </Badge>
    ),
  }),
  helper.accessor("suspended", {
    id: "status",
    header: "Status",
    cell: (c) =>
      c.row.original.suspended ? <Badge tone="bad">blocked</Badge> : <Badge tone="good">active</Badge>,
  }),
]);

const CSV = [
  { label: "Vendor", value: (v: VendorListRow) => v.name ?? v.id },
  { label: "Phone", value: (v: VendorListRow) => v.phone ?? "" },
  { label: "KYC", value: (v: VendorListRow) => v.kyc_status },
  { label: "Status", value: (v: VendorListRow) => (v.suspended ? "blocked" : "active") },
];


export function VendorsTable() {
  const listQ = useQuery({
    queryKey: ["vendors"],
    queryFn: () => proxyGet<{ data: VendorListRow[] }>("/v1/admin/vendors"),
  });

  const rows = listQ.data?.data ?? [];

  return (
    <div className="space-y-5">
      <PageHeader
        title="Vendors"
        description="Delivery partners — KYC, duty, custody and blocks."
      />
      <Card>
        {listQ.isError ? (
          <div className="p-4">
            <ErrorState message={(listQ.error as Error).message} />
          </div>
        ) : listQ.isLoading ? (
          <SkeletonRows rows={5} cols={5} />
        ) : rows.length === 0 ? (
          <EmptyState
            icon={<Truck className="size-5" />}
            title="No vendors yet"
            hint="Create the first vendor with POST /v1/admin/vendors (phone, name, zone)."
          />
        ) : (
          <DataTable
            columns={cols}
            data={rows}
            csv={CSV}
            csvFilename={`shodasha-vendors-${new Date().toISOString().slice(0, 10)}.csv`}
          />
        )}
      </Card>
      <p className="text-[11px] text-steel">
        Capacities and per-stop fees are tuned on each vendor&apos;s profile page; custody flags surface automatically.
      </p>
    </div>
  );
}
