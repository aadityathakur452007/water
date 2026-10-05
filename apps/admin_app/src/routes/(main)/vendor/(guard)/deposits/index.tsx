import { createFileRoute } from "@tanstack/react-router";

import { Deposits } from "./-components/deposits";

export const Route = createFileRoute("/(main)/vendor/(guard)/deposits/")({
  component: Page,
});

function Page() {
  return <Deposits />;
}
