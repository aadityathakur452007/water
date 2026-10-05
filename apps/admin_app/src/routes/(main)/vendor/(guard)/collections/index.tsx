import { createFileRoute } from "@tanstack/react-router";

import { Collections } from "./-components/collections";

export const Route = createFileRoute("/(main)/vendor/(guard)/collections/")({
  component: Page,
});

function Page() {
  return <Collections />;
}
