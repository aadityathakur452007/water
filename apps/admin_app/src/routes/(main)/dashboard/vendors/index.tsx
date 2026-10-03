import { createFileRoute } from "@tanstack/react-router";

import { Vendors } from "./-components/vendors";

export const Route = createFileRoute("/(main)/dashboard/vendors/")({
  component: Page,
});

function Page() {
  return <Vendors />;
}
