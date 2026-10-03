import { createFileRoute } from "@tanstack/react-router";

import { Orders } from "./-components/orders";

export const Route = createFileRoute("/(main)/dashboard/orders/")({
  component: Page,
});

function Page() {
  return <Orders />;
}
