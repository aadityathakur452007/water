import { createFileRoute, useParams } from "@tanstack/react-router";

import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { useVendorQuery } from "@/hooks/use-vendor-api";
import type { VendorStop } from "@/lib/vendor-types";
import { num } from "@/lib/money";

import { VendorEmpty, VendorError, VendorLoading } from "../../../-components/vendor-states";
import { StopActions } from "./-components/stop-actions";

export const Route = createFileRoute("/(main)/vendor/(guard)/stops/$stopId/")({
  component: StopDetail,
});

/** Stop detail — 404 reads same-as-missing (no oracle for cross-vendor ids). */
function StopDetail() {
  const { stopId } = useParams({ strict: false }) as { stopId: string };
  const { data, isError, error, refetch } = useVendorQuery<VendorStop>(`/v1/vendor/stops/${stopId}`);

  if (isError) {
    const status = (error as { status?: number })?.status;
    if (status === 404) return <VendorEmpty title="Stop nahi mila" hint="Ye stop aapke route par nahi hai." />;
    return <VendorError error={error} onRetry={() => void refetch()} />;
  }
  if (!data?.id) return <VendorLoading />;

  return (
    <div className="flex flex-col gap-4">
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="flex flex-wrap items-center gap-2 text-lg">
            {`Stop ${num(data.seq)}`}
            <Badge variant="outline">{data.status}</Badge>
            {data.hold_blocked ? (
              <Badge variant="outline" className="border-amber-500/20 bg-amber-500/10 text-amber-600">
                Hold
              </Badge>
            ) : null}
          </CardTitle>
          <CardDescription>
            {[data.address_label, data.address_text].filter(Boolean).join(" · ") ||
              (data.customer_id ?? data.order_id ?? data.id)}
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-3 gap-4">
            <div>
              <p className="text-muted-foreground text-xs">Expected</p>
              <p className="font-medium text-sm tabular-nums">
                {`${num(data.fulls_exp)}F / ${num(data.empties_exp)}E`}
              </p>
            </div>
            <div>
              <p className="text-muted-foreground text-xs">Payment</p>
              <p className="font-medium text-sm">{`${data.payment_mode ?? "—"} · ${data.payment_status ?? "—"}`}</p>
            </div>
            <div>
              <p className="text-muted-foreground text-xs">Order</p>
              <p className="font-medium text-sm">{data.order_state ?? "—"}</p>
            </div>
          </div>
          {data.hold_blocked ? (
            <p className="mt-2 text-amber-600 text-xs">{data.hold_reason ?? "Hold limit — delivery blocked."}</p>
          ) : null}
        </CardContent>
      </Card>
      <Card>
        <CardContent className="pt-6">
          <StopActions stop={data} onDone={() => void refetch()} />
        </CardContent>
      </Card>
    </div>
  );
}
