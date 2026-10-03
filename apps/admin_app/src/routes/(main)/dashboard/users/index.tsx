import { createFileRoute } from "@tanstack/react-router";

import { Users } from "./-components/users";

export const Route = createFileRoute("/(main)/dashboard/users/")({
  component: Page,
});

function Page() {
  return <Users />;
}
