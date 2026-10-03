import { createFileRoute } from "@tanstack/react-router";

import { Payments } from "./-components/payments";

export const Route = createFileRoute("/(main)/dashboard/payments")({
  component: Page,
});

function Page() {
  return <Payments />;
}
