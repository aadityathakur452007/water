import { createFileRoute, Outlet } from "@tanstack/react-router";

/** Vendor layout — renders the detail (index) or the preview/access children. */
export const Route = createFileRoute("/(main)/dashboard/vendors/$vendorId")({
  component: () => <Outlet />,
});
