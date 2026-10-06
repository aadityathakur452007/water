import * as React from "react";

import { RefreshCw } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { toast, useInvalidateVendor, useVendorQuery, vendorErrorMessage } from "@/hooks/use-vendor-api";
import type { PlacedOrder } from "@/lib/vendor-types";
import { num, rupees } from "@/lib/money";
import { vendorPostServer } from "@/server/vendor-api";

import { VendorEmpty, VendorError, VendorLoading } from "../../../-components/vendor-states";

/**
 * Zone-scoped placed pool — per-order single-touch accept (accept to
 * assign, route + stop created, replay returns the existing stop).
 * Polls on the same 60s discovery rhythm as the vendor_app.
 */
export function PlacedPool() {
  const { data, isError, error, refetch, isFetching } = useVendorQuery<{ data: PlacedOrder[] }>(
    "/v1/vendor/placed?limit=20",
    { refetchInterval: 60_000 },
  );
  const invalidate = useInvalidateVendor();
  const [busyId, setBusyId] = React.useState<string | null>(null);

  async function accept(orderId: string) {
    if (busyId) return;
    setBusyId(orderId);
    try {
      const out = (await vendorPostServer({
        data: { path: `/v1/vendor/placed/${orderId}/accept`, body: {} },
      })) as unknown as { replay?: boolean };
      toast.add({
        title: out?.replay ? "Ye order pehle se route me hai" : "Stop jud gaya — route me dekhein",
      });
      invalidate("/v1/vendor");
    } catch (err) {
      toast.add({ title: "Accept failed", description: vendorErrorMessage(err), type: "error" });
    } finally {
      setBusyId(null);
    }
  }

  if (isError) return <VendorError error={error} onRetry={() => void refetch()} />;
  if (!data) return <VendorLoading lines={2} />;
  const rows = data.data ?? [];
  if (!rows.length) {
    return <VendorEmpty title="Koi naya placed order nahi" hint="Naye orders yahan dikhenge — accept karte hi stop route me jud jayega." />;
  }

  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="flex items-center gap-2 text-lg">
          {`Naye orders (${rows.length}) — accept karein`}
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
        <CardDescription>Aapke zones ke naye orders — accept karte hi stop route me jud jayega</CardDescription>
      </CardHeader>
      <CardContent className="px-0 pb-2">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Order</TableHead>
              <TableHead>Jars</TableHead>
              <TableHead>Total</TableHead>
              <TableHead className="text-right">Action</TableHead>
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
                <TableCell className="text-right">
                  <Button
                    size="sm"
                    variant="outline"
                    disabled={busyId !== null}
                    onClick={() => void accept(o.order_id)}
                  >
                    {busyId === o.order_id ? "…" : "Accept"}
                  </Button>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  );
}
