import { createFileRoute, Outlet } from "@tanstack/react-router";

/** Vendors layout — renders the directory (index) or the detail child. */
export const Route = createFileRoute("/(main)/dashboard/vendors")({
  component: () => <Outlet />,
});
