import { createFileRoute } from "@tanstack/react-router";

import { TodayStrip } from "./-components/today-strip";
import { VendorLedger } from "./-components/vendor-ledger";
import { VendorMoney } from "./-components/vendor-money";

export const Route = createFileRoute("/(main)/vendor/(guard)/")({
  component: VendorOverview,
});

function VendorOverview() {
  return (
    <div className="flex flex-col gap-4">
      <TodayStrip />
      <VendorMoney />
      <VendorLedger />
    </div>
  );
}
