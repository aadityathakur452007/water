import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { useVendorQuery } from "@/hooks/use-vendor-api";
import type { VendorCustomer } from "@/lib/vendor-types";
import { num, phoneMasked, rupees } from "@/lib/money";

import { VendorEmpty, VendorError, VendorLoading } from "../../-components/vendor-states";

/** Ledger summary — only assigned customers with held jars or dues. No totals row. */
export function VendorLedger() {
  const { data, isError, error, refetch } = useVendorQuery<{ customers: VendorCustomer[] }>("/v1/vendor/customers");

  if (isError) return <VendorError error={error} onRetry={() => void refetch()} />;
  if (!data) return <VendorLoading />;
  const rows = (data.customers ?? []).filter((c) => (c.held ?? 0) > 0 || (c.dues ?? 0) > 0);
  if (!rows.length) {
    return <VendorEmpty title="Sab clear hai" hint="Na held jars, na baaki dues." />;
  }

  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-lg">Customers</CardTitle>
        <CardDescription>Held jars + baaki — sirf aapke assigned customers</CardDescription>
      </CardHeader>
      <CardContent className="px-0 pb-2">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Customer</TableHead>
              <TableHead>Held</TableHead>
              <TableHead>Dues</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.map((c) => (
              <TableRow key={c.customer_id || c.customer_name}>
                <TableCell>
                  <div className="flex flex-col">
                    <span className="font-medium text-sm">{c.customer_name}</span>
                    <span className="text-muted-foreground text-xs">{phoneMasked(c.customer_phone)}</span>
                  </div>
                </TableCell>
                <TableCell className="text-sm tabular-nums">{`${num(c.held)} jars`}</TableCell>
                <TableCell className="font-medium text-sm tabular-nums">{rupees(c.dues)}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  );
}
