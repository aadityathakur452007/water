import { createFileRoute } from "@tanstack/react-router";

import { Ledger } from "./-components/ledger";

export const Route = createFileRoute("/(main)/dashboard/ledger")({
  component: Page,
});

function Page() {
  return <Ledger />;
}
