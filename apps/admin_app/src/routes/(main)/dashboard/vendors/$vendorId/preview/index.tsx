import { createFileRoute } from "@tanstack/react-router";

import { VendorPreview } from "./-components/vendor-preview";

export const Route = createFileRoute("/(main)/dashboard/vendors/$vendorId/preview/")({
  component: Page,
});

function Page() {
  return <VendorPreview />;
}
