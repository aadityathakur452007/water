import { createFileRoute, Outlet } from "@tanstack/react-router";

export const Route = createFileRoute("/(main)/dashboard/zones")({
  component: () => <Outlet />,
});
