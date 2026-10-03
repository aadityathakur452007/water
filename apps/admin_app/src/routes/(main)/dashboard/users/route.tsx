import { createFileRoute, Outlet } from "@tanstack/react-router";

/** Users layout — renders the directory (index) or the detail child. */
export const Route = createFileRoute("/(main)/dashboard/users")({
  component: () => <Outlet />,
});
