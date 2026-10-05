import { RefreshCw } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { useVendorQuery } from "@/hooks/use-vendor-api";
import type { PlacedOrder } from "@/lib/vendor-types";
import { num, rupees } from "@/lib/money";

import { VendorEmpty, VendorError, VendorLoading } from "../../../-components/vendor-states";

/**
 * Zone-scoped placed pool — read-only refresh (same as the vendor_app Pull:
 * no pull endpoint exists, assignment stays with dispatch). New orders show
 * here after dispatch assigns them to your route.
 */
export function PlacedPool() {
  const { data, isError, error, refetch, isFetching } = useVendorQuery<{ data: PlacedOrder[] }>(
    "/v1/vendor/placed?limit=20",
  );

  if (isError) return <VendorError error={error} onRetry={() => void refetch()} />;
  if (!data) return <VendorLoading lines={2} />;
  const rows = data.data ?? [];
  if (!rows.length) {
    return <VendorEmpty title="Koi naya placed order nahi" hint="Dispatch se assign hote hi yahan dikhega." />;
  }

  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="flex items-center gap-2 text-lg">
          {`Placed pool (${rows.length})`}
          <Button
            variant="ghost"
            size="sm"
            disabled={isFetching}
            onClick={() => void refetch()}
            aria-label="Refresh placed pool"
          >
            <RefreshCw className={isFetching ? "animate-spin" : ""} aria-hidden />
          </Button>
        </CardTitle>
        <CardDescription>Aapke zones ke naye orders — dispatch se assign karvayein</CardDescription>
      </CardHeader>
      <CardContent className="px-0 pb-2">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Order</TableHead>
              <TableHead>Jars</TableHead>
              <TableHead>Total</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.map((o) => (
              <TableRow key={o.order_id}>
                <TableCell>
                  <div className="flex flex-col">
                    <span className="font-medium text-sm">{o.address_label ?? o.order_id}</span>
                    <span className="max-w-56 truncate text-muted-foreground text-xs">{o.address_text ?? ""}</span>
                  </div>
                </TableCell>
                <TableCell className="text-sm tabular-nums">{num(o.n)}</TableCell>
                <TableCell className="font-medium text-sm tabular-nums">{rupees(o.total)}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  );
}
