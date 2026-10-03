import type { ColumnDef } from "@tanstack/react-table";

import { Badge } from "@/components/ui/badge";
import type { OrderRow } from "@/lib/admin-types";
import type { dataTableFeatures } from "@/lib/data-table-features";
import { dateTime, rupees } from "@/lib/money";

type DataTableFeatures = typeof dataTableFeatures;

export const STATE_BADGE: Record<string, string> = {
  delivered: "border-emerald-500/20 bg-emerald-500/10 text-emerald-600 dark:text-emerald-400",
  dispatched: "border-sky-500/20 bg-sky-500/10 text-sky-600 dark:text-sky-400",
  assigned: "border-sky-500/20 bg-sky-500/10 text-sky-600 dark:text-sky-400",
  placed: "border-amber-500/20 bg-amber-500/10 text-amber-600 dark:text-amber-400",
  cancelled: "border-destructive/20 bg-destructive/10 text-destructive",
  failed: "border-destructive/20 bg-destructive/10 text-destructive",
};

export const ordersColumns: ColumnDef<DataTableFeatures, OrderRow>[] = [
  {
    accessorKey: "id",
    header: "Order",
    cell: ({ row }) => <span className="font-medium">{row.original.id}</span>,
  },
  {
    accessorKey: "user_id",
    header: "User",
  },
  {
    id: "jars",
    accessorFn: (r) => `${r.n} / ${r.e}`,
    header: "Jars (full/empty)",
    cell: ({ row }) => (
      <span className="tabular-nums">
        {row.original.n} / {row.original.e}
      </span>
    ),
  },
  {
    accessorKey: "total",
    header: "Amount",
    cell: ({ row }) => <span className="font-medium tabular-nums">{rupees(row.original.total)}</span>,
  },
  {
    accessorKey: "payment_status",
    header: "Payment",
    cell: ({ row }) => <Badge variant="outline">{row.original.payment_status}</Badge>,
  },
  {
    accessorKey: "state",
    header: "State",
    cell: ({ row }) => (
      <Badge variant="outline" className={STATE_BADGE[row.original.state] ?? ""}>
        {row.original.state}
      </Badge>
    ),
  },
  {
    accessorKey: "window_start",
    header: "Window",
    cell: ({ row }) => <span className="text-muted-foreground text-sm">{row.original.window_start.slice(11, 16)}</span>,
  },
  {
    accessorKey: "created_at",
    header: "Placed",
    cell: ({ row }) => <span className="text-muted-foreground text-sm">{dateTime(row.original.created_at)}</span>,
  },
];
