import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import type { PaymentRow } from "@/lib/admin-types";

import { paymentsColumns } from "./payments-columns";

export function PaymentsTable({ rows }: { rows: PaymentRow[] }) {
  const cols = paymentsColumns;
  return (
    <Table className="**:data-[slot='table-cell']:px-4 **:data-[slot='table-head']:px-4">
      <TableHeader className="[&_tr]:border-t">
        <TableRow>
          {cols.map((c) => {
            const key = "accessorKey" in c ? (c.accessorKey as string) : (c.id as string);
            const header = "header" in c ? c.header : key;
            return (
              <TableHead key={key} className="py-3">
                {typeof header === "string" ? header : null}
              </TableHead>
            );
          })}
        </TableRow>
      </TableHeader>
      <TableBody>
        {rows.length ? (
          rows.map((row) => (
            <TableRow key={row.id} className="border-border/60 hover:bg-white/2.5">
              {cols.map((c) => {
                const key = "accessorKey" in c ? (c.accessorKey as string) : (c.id as string);
                return (
                  <TableCell key={key} className="px-3 py-3 align-middle text-sm">
                    {render(c, row)}
                  </TableCell>
                );
              })}
            </TableRow>
          ))
        ) : (
          <TableRow>
            <TableCell colSpan={cols.length} className="h-24 text-center text-muted-foreground">
              No payments match the filters.
            </TableCell>
          </TableRow>
        )}
      </TableBody>
    </Table>
  );
}

function render(c: (typeof paymentsColumns)[number], row: PaymentRow) {
  const cellFn = "cell" in c ? (c.cell as (ctx: { row: { original: PaymentRow } }) => React.ReactNode) : undefined;
  if (cellFn) return cellFn({ row: { original: row } });
  const key = "accessorKey" in c ? (c.accessorKey as string) : (c.id as string);
  const value = (row as unknown as Record<string, unknown>)[key];
  return <span>{String(value ?? "—")}</span>;
}
