import type { ColumnDef } from "@tanstack/react-table";

import { Badge } from "@/components/ui/badge";
import type { dataTableFeatures } from "@/lib/data-table-features";
import { rupees } from "@/lib/money";

export type RecentOrder = {
  id: string;
  user: string;
  n: number;
  total: number;
  payment_status: string;
  state: string;
  created: string;
};

type DataTableFeatures = typeof dataTableFeatures;

export const recentOrdersColumns: ColumnDef<DataTableFeatures, RecentOrder>[] = [
  {
    accessorKey: "id",
    header: "Order",
    cell: ({ row }) => <div className="font-medium">{row.original.id}</div>,
  },
  {
    accessorKey: "user",
    header: "Customer",
  },
  {
    accessorKey: "n",
    header: "Jars",
    cell: ({ row }) => <div className="tabular-nums">{row.original.n}</div>,
  },
  {
    accessorKey: "total",
    header: "Amount",
    cell: ({ row }) => <div className="font-medium tabular-nums">{rupees(row.original.total)}</div>,
  },
  {
    accessorKey: "payment_status",
    header: "Payment",
    cell: ({ row }) => <Badge variant="outline">{row.original.payment_status}</Badge>,
  },
  {
    accessorKey: "state",
    header: "State",
  },
  {
    accessorKey: "created",
    header: "Placed",
    cell: ({ row }) => <div className="text-muted-foreground text-sm">{row.original.created}</div>,
  },
];
