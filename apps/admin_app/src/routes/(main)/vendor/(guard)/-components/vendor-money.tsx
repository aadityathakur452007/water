import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { useVendorQuery } from "@/hooks/use-vendor-api";
import type { Earnings, VendorCustomer } from "@/lib/vendor-types";
import { rupees } from "@/lib/money";

import { VendorError, VendorLoading } from "../../-components/vendor-states";

/** Money row — jama (collected), baaki (dues), hold (GPS-flagged, admin clears). */
export function VendorMoney() {
  const {
    data: earnings,
    isError,
    error,
    refetch,
  } = useVendorQuery<Earnings>("/v1/vendor/earnings");
  const { data: customers } = useVendorQuery<{ customers: VendorCustomer[] }>("/v1/vendor/customers");

  if (isError) return <VendorError error={error} onRetry={() => void refetch()} />;
  if (!earnings) return <VendorLoading lines={2} />;

  const jama = (earnings.cash_total ?? 0) + (earnings.upi_total ?? 0);
  const baaki = (customers?.customers ?? []).reduce((a, c) => a + (c.dues ?? 0), 0);

  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-lg">Aaj ka hisaab</CardTitle>
        <CardDescription>{`Cash ${rupees(earnings.cash_total)} · UPI ${rupees(earnings.upi_total)}`}</CardDescription>
      </CardHeader>
      <CardContent>
        <div className="grid grid-cols-3 gap-4">
          <div>
            <p className="text-muted-foreground text-xs">Jama</p>
            <p className="font-medium text-xl tabular-nums">{rupees(jama)}</p>
          </div>
          <div>
            <p className="text-muted-foreground text-xs">Baaki (dues)</p>
            <p className="font-medium text-xl tabular-nums">{rupees(baaki)}</p>
          </div>
          <div>
            <p className="text-muted-foreground text-xs">Hold</p>
            <p className="font-medium text-xl tabular-nums">{rupees(earnings.flagged_hold)}</p>
          </div>
        </div>
        {(earnings.flagged_stops ?? 0) > 0 ? (
          <p className="mt-2 text-muted-foreground text-xs">
            {`${earnings.flagged_stops} stops hold par — admin clear karega.`}
          </p>
        ) : null}
      </CardContent>
    </Card>
  );
}
