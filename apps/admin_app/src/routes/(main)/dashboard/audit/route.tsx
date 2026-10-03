import { createFileRoute } from "@tanstack/react-router";

import { Audit } from "./-components/audit";

export const Route = createFileRoute("/(main)/dashboard/audit")({
  component: Page,
});

function Page() {
  return <Audit />;
}
