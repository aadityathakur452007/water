import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { rupees } from "@/lib/money";

import type { RecentOrder } from "./columns";
import { recentOrdersColumns } from "./columns";

export function RecentOrdersTable({ rows }: { rows: RecentOrder[] }) {
  return (
    <Table>
      <TableHeader className="[&_tr]:border-t">
        {recentOrdersColumns.map((col) => (
          <TableHead
            key={col.id ?? String("accessorKey" in col ? col.accessorKey : col.id)}
            className="py-3 font-normal"
          >
            {"header" in col && typeof col.header === "string" ? col.header : null}
          </TableHead>
        ))}
      </TableHeader>
      <TableBody>
        {rows.length ? (
          rows.map((row) => (
            <TableRow key={row.id} className="border-border/60 hover:bg-white/2.5">
              {recentOrdersColumns.map((col) => {
                const key = "accessorKey" in col ? (col.accessorKey as string) : (col.id as string);
                const value = (row as unknown as Record<string, unknown>)[key];
                return (
                  <TableCell key={key} className="px-3 py-3 align-middle text-sm">
                    {typeof value === "string" || typeof value === "number" ? renderCell(key, value, row) : null}
                  </TableCell>
                );
              })}
            </TableRow>
          ))
        ) : (
          <TableRow>
            <TableCell colSpan={recentOrdersColumns.length} className="h-24 text-center text-muted-foreground">
              No orders yet today.
            </TableCell>
          </TableRow>
        )}
      </TableBody>
    </Table>
  );
}

function renderCell(key: string, value: string | number, row: RecentOrder) {
  switch (key) {
    case "total":
      return <span className="font-medium tabular-nums">{rupees(row.total)}</span>;
    case "payment_status":
      return <Badge variant="outline">{value}</Badge>;
    case "created":
      return <span className="text-muted-foreground">{value}</span>;
    default:
      return <span>{value}</span>;
  }
}
