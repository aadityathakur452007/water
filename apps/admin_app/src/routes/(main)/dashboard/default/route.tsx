import { createFileRoute } from "@tanstack/react-router";

import { AlertsFeed } from "./-components/alerts-feed";
import { MetricCards } from "./-components/metric-cards";
import { OrdersChart } from "./-components/orders-chart";
import { PaymentSplit } from "./-components/payment-split";
import { OnTimeTrend } from "./-components/state-mix";

export const Route = createFileRoute("/(main)/dashboard/default")({
  component: Page,
});

function Page() {
  return (
    <div className="@container/main flex flex-col gap-4 md:gap-6">
      <MetricCards />
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
        <div className="lg:col-span-2">
          <OrdersChart />
        </div>
        <PaymentSplit />
      </div>
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
        <div className="lg:col-span-2">
          <OnTimeTrend />
        </div>
        <AlertsFeed />
      </div>
    </div>
  );
}
