import { createFileRoute } from "@tanstack/react-router";

import { Zones } from "./-components/zones";

export const Route = createFileRoute("/(main)/dashboard/zones/")({
  component: Page,
});

function Page() {
  return <Zones />;
}
