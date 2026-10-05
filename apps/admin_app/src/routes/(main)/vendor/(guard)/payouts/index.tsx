import { createFileRoute } from "@tanstack/react-router";

import { Payouts } from "./-components/payouts";

export const Route = createFileRoute("/(main)/vendor/(guard)/payouts/")({
  component: Page,
});

function Page() {
  return <Payouts />;
}
