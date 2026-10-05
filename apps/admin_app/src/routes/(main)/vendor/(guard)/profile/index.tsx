import { createFileRoute } from "@tanstack/react-router";

import { Profile } from "./-components/profile";

export const Route = createFileRoute("/(main)/vendor/(guard)/profile/")({
  component: Page,
});

function Page() {
  return <Profile />;
}
