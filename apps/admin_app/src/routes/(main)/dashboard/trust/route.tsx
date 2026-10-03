import { createFileRoute } from "@tanstack/react-router";

import { Trust } from "./-components/trust";

export const Route = createFileRoute("/(main)/dashboard/trust")({
  component: Page,
});

function Page() {
  return <Trust />;
}
