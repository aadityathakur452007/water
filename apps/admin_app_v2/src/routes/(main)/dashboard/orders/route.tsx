import { createFileRoute } from "@tanstack/react-router";

import { Orders } from "./-components/orders";

type OrdersSearch = { state?: string; payment_status?: string };

export const Route = createFileRoute("/(main)/dashboard/orders")({
  validateSearch: (search: Record<string, unknown>): OrdersSearch => ({
    state: typeof search.state === "string" ? search.state : undefined,
    payment_status: typeof search.payment_status === "string" ? search.payment_status : undefined,
  }),
  component: Page,
});

function Page() {
  return <Orders />;
}
