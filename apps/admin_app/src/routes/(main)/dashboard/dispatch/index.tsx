import { createFileRoute } from "@tanstack/react-router";

import { Dispatch } from "./-components/dispatch";

export const Route = createFileRoute("/(main)/dashboard/dispatch/")({
  component: Page,
});

function Page() {
  return <Dispatch />;
}
