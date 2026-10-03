import { createFileRoute } from "@tanstack/react-router";

import { Config } from "./-components/config";

export const Route = createFileRoute("/(main)/dashboard/config")({
  component: Page,
});

function Page() {
  return <Config />;
}
