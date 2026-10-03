import { createFileRoute } from "@tanstack/react-router";

import { Operations } from "./-components/operations";

export const Route = createFileRoute("/(main)/dashboard/operations")({
  component: Page,
});

function Page() {
  return <Operations />;
}
