import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardAction, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import type { VendorDetail } from "@/lib/admin-types";
import { dateTime, num, rupees } from "@/lib/money";

type VendorDetailPanelsProps = {
  vendorId: string;
  payouts: VendorDetail["payouts"];
  strikes: VendorDetail["strikes"];
  period: string;
  busy: boolean;
  onPeriodChange: (v: string) => void;
  onMutate: (path: string, body: Record<string, unknown>, label: string) => void;
};

export function VendorDetailPanels({
  vendorId,
  payouts,
  strikes,
  period,
  busy,
  onPeriodChange,
  onMutate,
}: VendorDetailPanelsProps) {
  return (
    <div className="grid gap-4 lg:grid-cols-2">
      <Card>
        <CardHeader>
          <CardTitle>Payouts</CardTitle>
          <CardDescription>Weekly settlements (net of deductions)</CardDescription>
          <CardAction>
            <div className="flex items-center gap-2">
              <Input
                aria-label="Payout period YYYY-MM"
                className="h-8 w-28"
                value={period}
                onChange={(e) => onPeriodChange(e.target.value)}
                placeholder="YYYY-MM"
              />
              <Button
                variant="outline"
                size="sm"
                disabled={busy || !/^\d{4}-\d{2}$/.test(period)}
                onClick={() =>
                  onMutate("/v1/admin/payouts/generate", { vendor_id: vendorId, period }, "Payout generated")
                }
              >
                Generate
              </Button>
            </div>
          </CardAction>
        </CardHeader>
        <CardContent className="px-0 pb-2">
          <Table className="**:data-[slot='table-cell']:px-4 **:data-[slot='table-head']:px-4">
            <TableHeader className="[&_tr]:border-t">
              <TableRow>
                <TableHead className="py-3">Period</TableHead>
                <TableHead className="py-3">Stops</TableHead>
                <TableHead className="py-3">Gross</TableHead>
                <TableHead className="py-3">Net</TableHead>
                <TableHead className="py-3">Status</TableHead>
                <TableHead className="py-3">Action</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {payouts.length ? (
                payouts.map((o) => (
                  <TableRow key={o.id} className="border-border/60">
                    <TableCell className="px-3 py-3 font-medium text-sm">{o.period}</TableCell>
                    <TableCell className="px-3 py-3 text-sm tabular-nums">{num(o.stops_done)}</TableCell>
                    <TableCell className="px-3 py-3 text-sm tabular-nums">{rupees(o.gross_fee)}</TableCell>
                    <TableCell className="px-3 py-3 font-medium text-sm tabular-nums">{rupees(o.net)}</TableCell>
                    <TableCell className="px-3 py-3 text-sm">
                      <Badge variant="outline">{o.status}</Badge>
                    </TableCell>
                    <TableCell className="px-3 py-3 text-sm">
                      {o.status === "pending" ? (
                        <Button
                          variant="outline"
                          size="sm"
                          className="h-7"
                          disabled={busy}
                          onClick={() => onMutate(`/v1/admin/payouts/${o.id}/approve`, {}, "Payout approved")}
                        >
                          Approve
                        </Button>
                      ) : null}
                    </TableCell>
                  </TableRow>
                ))
              ) : (
                <TableRow>
                  <TableCell colSpan={6} className="h-20 text-center text-muted-foreground">
                    No payouts yet.
                  </TableCell>
                </TableRow>
              )}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Strikes</CardTitle>
          <CardDescription>Service-severity record for this vendor</CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-2 pb-2">
          {strikes.length ? (
            strikes.map((s) => (
              <div key={s.id} className="flex items-center gap-3 rounded-lg border px-3 py-2 text-sm">
                <Badge variant="outline">{`sev ${s.severity}`}</Badge>
                <span className="font-medium">{s.kind}</span>
                <span className="min-w-0 flex-1 truncate text-muted-foreground">{s.note}</span>
                <span className="text-muted-foreground text-xs">{dateTime(s.created_at)}</span>
              </div>
            ))
          ) : (
            <p className="text-muted-foreground text-sm">Clean record — no strikes.</p>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
