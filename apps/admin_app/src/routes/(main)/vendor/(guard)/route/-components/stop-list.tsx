import { useNavigate } from "@tanstack/react-router";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { useVendorQuery } from "@/hooks/use-vendor-api";
import type { TodayRoute, VendorStop } from "@/lib/vendor-types";
import { vendorOrderStateLabel } from "@/lib/vendor-types";
import { num } from "@/lib/money";

import { VendorEmpty, VendorError, VendorLoading } from "../../../-components/vendor-states";

function StopCta({ stop }: { stop: VendorStop }) {
  const navigate = useNavigate();
  if (stop.status === "done") return <Badge variant="outline">Ho gaya</Badge>;
  if (stop.hold_blocked) {
    return (
      <Badge variant="outline" className="border-amber-500/20 bg-amber-500/10 text-amber-600" title={stop.hold_reason}>
        Hold — deposit baaki
      </Badge>
    );
  }
  return (
    <Button
      size="sm"
      variant="outline"
      onClick={() => navigate({ to: "/vendor/stops/$stopId", params: { stopId: stop.id } })}
    >
      Kholo
    </Button>
  );
}

function StopRows({ stops }: { stops: VendorStop[] }) {
  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>#</TableHead>
          <TableHead>Stop</TableHead>
          <TableHead>Jars</TableHead>
          <TableHead className="text-right">Action</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {stops.map((s) => (
          <TableRow key={s.id}>
            <TableCell className="text-sm tabular-nums">{num(s.seq)}</TableCell>
            <TableCell>
              <div className="flex flex-col">
                <span className="font-medium text-sm">{s.address_label ?? s.customer_id ?? s.id}</span>
                <span className="max-w-56 truncate text-muted-foreground text-xs">
                  {s.address_text ?? vendorOrderStateLabel(s.order_state)}
                </span>
              </div>
            </TableCell>
            <TableCell className="text-sm tabular-nums">{`${num(s.fulls_exp)}F/${num(s.empties_exp)}E`}</TableCell>
            <TableCell className="text-right">
              <StopCta stop={s} />
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}

/** Assigned stops — one CTA per state; skipped stops sit in their own section. */
export function StopList() {
  // Phase 5 S5.4: same 60s discovery poll as the vendor_app (on-duty screen).
  const { data, isError, error, refetch } = useVendorQuery<TodayRoute>("/v1/vendor/routes/today", {
    refetchInterval: 60_000,
  });

  if (isError) return <VendorError error={error} onRetry={() => void refetch()} />;
  if (!data) return <VendorLoading />;
  const active = (data.stops ?? []).filter((s) => s.status !== "skipped");
  const skipped = data.skip?.length ? data.skip : (data.stops ?? []).filter((s) => s.status === "skipped");
  if (!data.route) {
    return <VendorEmpty title="Aaj koi stop nahi" hint="Route assign hote hi stops yahan dikhenge." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-lg">{`Stops · ${data.route.zone}`}</CardTitle>
          <CardDescription>
            {`${active.filter((s) => s.status === "done").length} / ${active.length} ho gaye`}
          </CardDescription>
        </CardHeader>
        <CardContent className="px-0 pb-2">
          {active.length ? (
            <StopRows stops={active} />
          ) : (
            <p className="px-4 py-6 text-center text-muted-foreground text-sm">Koi active stop nahi.</p>
          )}
        </CardContent>
      </Card>
      {skipped.length ? (
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-lg">SKIP — aaj nahi</CardTitle>
            <CardDescription>Paused ya late-skip stops, kuch karna nahi hai</CardDescription>
          </CardHeader>
          <CardContent className="px-0 pb-2">
            <StopRows stops={skipped} />
          </CardContent>
        </Card>
      ) : null}
    </div>
  );
}
