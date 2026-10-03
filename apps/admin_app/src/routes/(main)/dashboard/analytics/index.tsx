import { createFileRoute } from "@tanstack/react-router";

import { OrdersChart } from "../default/-components/orders-chart";
import { OnTimeTrend } from "../default/-components/state-mix";
import { KpiMatrix } from "./-components/kpi-matrix";
import { Leaderboards } from "./-components/leaderboards";
import { PaymentMixTrend } from "./-components/payment-mix-trend";

export const Route = createFileRoute("/(main)/dashboard/analytics/")({
  component: Page,
});

function Page() {
  return (
    <div className="@container/main flex flex-col gap-4 md:gap-6">
      <KpiMatrix />
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <OrdersChart />
        <PaymentMixTrend />
      </div>
      <OnTimeTrend />
      <Leaderboards />
    </div>
  );
}
