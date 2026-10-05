import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { useVendorQuery } from "@/hooks/use-vendor-api";
import type { TodayRoute } from "@/lib/vendor-types";
import { num } from "@/lib/money";

import { VendorEmpty, VendorError, VendorLoading } from "../../-components/vendor-states";

/** TODAY strip — folds the route sheet client-side: stops, jars, customers. */
export function TodayStrip() {
  const { data, isError, error, refetch } = useVendorQuery<TodayRoute>("/v1/vendor/routes/today");

  if (isError) return <VendorError error={error} onRetry={() => void refetch()} />;
  if (!data) return <VendorLoading lines={3} />;
  if (!data.route) {
    return <VendorEmpty title="Aaj koi route nahi" hint="Dispatch se route assign hote hi yahan dikhega." />;
  }

  const stops = data.stops ?? [];
  const done = stops.filter((s) => s.status === "done").length;
  const customers = new Set(stops.map((s) => s.customer_id).filter(Boolean)).size;

  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="flex flex-wrap items-center gap-2 text-lg">
          {`Aaj ka route · ${data.route.zone}`}
          <Badge variant="outline">{data.route.status}</Badge>
        </CardTitle>
        <CardDescription>{`${done} / ${stops.length} stops ho gaye · ${customers} customers`}</CardDescription>
      </CardHeader>
      <CardContent>
        <div className="grid grid-cols-3 gap-4">
          <div>
            <p className="text-muted-foreground text-xs">Stops</p>
            <p className="font-medium text-xl tabular-nums">{`${done}/${stops.length}`}</p>
          </div>
          <div>
            <p className="text-muted-foreground text-xs">Full jars (le jao)</p>
            <p className="font-medium text-xl tabular-nums">{num(data.loading?.take_fulls ?? 0)}</p>
          </div>
          <div>
            <p className="text-muted-foreground text-xs">Khaali (wapas lao)</p>
            <p className="font-medium text-xl tabular-nums">{num(data.loading?.expect_empties ?? 0)}</p>
          </div>
        </div>
      </CardContent>
    </Card>
  );
}
