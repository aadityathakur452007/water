import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { useVendorQuery } from "@/hooks/use-vendor-api";
import type { VendorPayouts } from "@/lib/vendor-types";
import { num, rupees } from "@/lib/money";

import { VendorEmpty, VendorError, VendorLoading } from "../../../-components/vendor-states";

/** READ-ONLY own payouts + custody. No approve affordance exists on this screen. */
export function Payouts() {
  const { data, isError, error, refetch } = useVendorQuery<VendorPayouts>("/v1/vendor/payouts");

  if (isError) return <VendorError error={error} onRetry={() => void refetch()} />;
  if (!data) return <VendorLoading />;
  const rows = data.payouts ?? [];
  if (!rows.length) {
    return <VendorEmpty title="Abhi koi payout nahi" hint="Settlement hote hi yahan dikhega." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-lg">Haath me (in-hand)</CardTitle>
          <CardDescription>Agency ka cash jo abhi aapke paas hai</CardDescription>
        </CardHeader>
        <CardContent>
          <p className="font-medium text-2xl tabular-nums">{rupees(data.in_hand)}</p>
          {data.note ? <p className="mt-1 text-muted-foreground text-xs">{data.note}</p> : null}
        </CardContent>
      </Card>
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-lg">Payouts</CardTitle>
          <CardDescription>Weekly settlements — sirf dekh sakte hain, approve admin karega</CardDescription>
        </CardHeader>
        <CardContent className="px-0 pb-2">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Period</TableHead>
                <TableHead>Stops</TableHead>
                <TableHead>Net</TableHead>
                <TableHead>Status</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {rows.map((o) => (
                <TableRow key={o.id}>
                  <TableCell className="font-medium text-sm">{o.period}</TableCell>
                  <TableCell className="text-sm tabular-nums">{num(o.stops_done)}</TableCell>
                  <TableCell className="text-sm tabular-nums">
                    {`${rupees(o.net)} (−${rupees(o.deductions)})`}
                  </TableCell>
                  <TableCell>
                    <Badge variant="outline">{o.status}</Badge>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
    </div>
  );
}
