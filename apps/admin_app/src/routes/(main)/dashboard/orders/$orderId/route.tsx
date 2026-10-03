import { createFileRoute } from "@tanstack/react-router";

import { OrderDetail } from "./-components/order-detail";

export const Route = createFileRoute("/(main)/dashboard/orders/$orderId")({
  component: Page,
});

function Page() {
  return <OrderDetail />;
}
