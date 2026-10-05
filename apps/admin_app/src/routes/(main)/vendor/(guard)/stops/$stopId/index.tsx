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

  const phone = data.customer_phone ?? "";
  const items = (data.items ?? []).map((e) => `${e.qty} ${e.sku}`).join(" • ");

  return (
    <div className="flex flex-col gap-4">
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="flex flex-wrap items-center gap-2 text-lg">
            {`Stop ${num(data.seq)} — ${data.customer_name ?? data.customer_id ?? data.order_id ?? data.id}`}
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
          {phone ? (
            <div className="flex gap-2 pt-1">
              <a className="text-sm underline" href={`tel:${phone}`}>
                Call customer
              </a>
              <a
                className="text-sm underline"
                href={`https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(
                  [data.address_text, data.address_label].filter(Boolean).join(", "),
                )}`}
                target="_blank"
                rel="noreferrer"
              >
                Navigate
              </a>
            </div>
          ) : null}
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
            {data.window_start ? (
              <div>
                <p className="text-muted-foreground text-xs">Window</p>
                <p className="font-medium text-sm">{data.window_start}</p>
              </div>
            ) : null}
            {items ? (
              <div>
                <p className="text-muted-foreground text-xs">Items</p>
                <p className="font-medium text-sm">{items}</p>
              </div>
            ) : null}
            {data.instructions ? (
              <div>
                <p className="text-muted-foreground text-xs">Note</p>
                <p className="font-medium text-sm">{data.instructions}</p>
              </div>
            ) : null}
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
