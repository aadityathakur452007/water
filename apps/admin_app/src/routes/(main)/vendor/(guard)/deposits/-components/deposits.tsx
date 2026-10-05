import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { useVendorQuery } from "@/hooks/use-vendor-api";
import type { VendorCustomer } from "@/lib/vendor-types";
import { num, phoneMasked, rupees } from "@/lib/money";

import { VendorEmpty, VendorError, VendorLoading } from "../../../-components/vendor-states";

/**
 * READ-ONLY per-customer deposits for ASSIGNED customers only (held/dues
 * ints from the owner-scoped customers read). No totals, no ledger history,
 * no deposit_paid/refunded columns — those have no vendor route by design.
 */
export function Deposits() {
  const { data, isError, error, refetch } = useVendorQuery<{ customers: VendorCustomer[] }>("/v1/vendor/customers");

  if (isError) return <VendorError error={error} onRetry={() => void refetch()} />;
  if (!data) return <VendorLoading />;
  const rows = data.customers ?? [];
  if (!rows.length) {
    return <VendorEmpty title="Koi assigned customer nahi" hint="Route assign hote hi list yahan dikhegi." />;
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-lg">Deposits</CardTitle>
        <CardDescription>Per-customer held jars + dues — sirf aapke assigned customers</CardDescription>
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
