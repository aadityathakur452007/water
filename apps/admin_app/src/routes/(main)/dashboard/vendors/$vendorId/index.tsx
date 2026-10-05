import { createFileRoute } from "@tanstack/react-router";

import { VendorDetail } from "./-components/vendor-detail";

export const Route = createFileRoute("/(main)/dashboard/vendors/$vendorId/")({
  component: Page,
});

function Page() {
  return <VendorDetail />;
}
