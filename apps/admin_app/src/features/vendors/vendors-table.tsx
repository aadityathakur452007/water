"use client";

import Link from "next/link";
import { Truck } from "lucide-react";
import { Badge, Card, EmptyState, ErrorState, PageHeader, SkeletonRows } from "@/shared/ui/primitives";
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
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-line text-left text-[11px] uppercase tracking-wide text-faint">
                  <th className="px-5 py-2.5 font-medium">Vendor</th>
                  <th className="px-3 py-2.5 font-medium">Phone</th>
                  <th className="px-3 py-2.5 font-medium">KYC</th>
                  <th className="px-5 py-2.5 font-medium">Status</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-line-soft">
                {rows.map((v) => (
                  <tr key={v.id} className="transition-colors hover:bg-canvas">
                    <td className="px-5 py-3">
                      <Link href={`/admin/vendors/${v.id}`} className="font-medium text-accent hover:underline">
                        {v.name ?? v.id.slice(0, 10)}
                      </Link>
                    </td>
                    <td className="tnum px-3 py-3 text-steel">{phoneMasked(v.phone)}</td>
                    <td className="px-3 py-3">
                      <Badge tone={v.kyc_status === "verified" ? "good" : "warn"}>{v.kyc_status}</Badge>
                    </td>
                    <td className="px-5 py-3">
                      {v.suspended ? <Badge tone="bad">blocked</Badge> : <Badge tone="good">active</Badge>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>
      <p className="text-[11px] text-faint">
        Capacities and per-stop fees are tuned on each vendor&apos;s profile page; custody flags surface automatically.
      </p>
    </div>
  );
}
