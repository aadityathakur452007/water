import { createFileRoute } from "@tanstack/react-router";

import { UserDetail } from "./-components/user-detail";

export const Route = createFileRoute("/(main)/dashboard/users/$userId")({
  component: Page,
});

function Page() {
  return <UserDetail />;
}
