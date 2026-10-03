import type { ColumnDef } from "@tanstack/react-table";

import { Badge } from "@/components/ui/badge";
import type { PaymentRow } from "@/lib/admin-types";
import type { dataTableFeatures } from "@/lib/data-table-features";
import { dateTime, phoneMasked, rupees } from "@/lib/money";

type DataTableFeatures = typeof dataTableFeatures;

const PAYMENT_STATUS_CLS: Record<string, string> = {
  captured: "border-emerald-500/20 bg-emerald-500/10 text-emerald-600 dark:text-emerald-400",
  failed: "border-destructive/20 bg-destructive/10 text-destructive",
};

function PaymentStatusBadge({ status }: { status: string }) {
  const cls = PAYMENT_STATUS_CLS[status] ?? "border-amber-500/20 bg-amber-500/10 text-amber-600 dark:text-amber-400";
  return (
    <Badge variant="outline" className={`gap-1.5 ${cls}`}>
      {status}
    </Badge>
  );
}

export const paymentsColumns: ColumnDef<DataTableFeatures, PaymentRow>[] = [
  {
    accessorKey: "id",
    header: "Payment",
    cell: ({ row }) => <span className="font-medium">{row.original.id}</span>,
  },
  {
    accessorKey: "order_id",
    header: "Order",
  },
  {
    id: "user",
    accessorFn: (r) => r.user_name ?? r.user_phone ?? r.user_id,
    header: "Customer",
    cell: ({ row }) => (
      <div className="flex flex-col">
        <span>{row.original.user_name ?? "—"}</span>
        <span className="text-muted-foreground text-xs">{phoneMasked(row.original.user_phone)}</span>
      </div>
    ),
  },
  {
    accessorKey: "amount",
    header: "Amount",
    cell: ({ row }) => <span className="font-medium tabular-nums">{rupees(row.original.amount)}</span>,
  },
  {
    accessorKey: "method",
    header: "Method",
    cell: ({ row }) => <Badge variant="outline">{row.original.method.toUpperCase()}</Badge>,
  },
  {
    accessorKey: "status",
    header: "Status",
    cell: ({ row }) => {
      const s = row.original.status;
      return <PaymentStatusBadge status={s} />;
    },
  },
  {
    accessorKey: "created_at",
    header: "At",
    cell: ({ row }) => <span className="text-muted-foreground text-sm">{dateTime(row.original.created_at)}</span>,
  },
];
