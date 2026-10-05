import { createFileRoute } from "@tanstack/react-router";

import { PlacedPool } from "./-components/placed-pool";
import { StopList } from "./-components/stop-list";

export const Route = createFileRoute("/(main)/vendor/(guard)/route/")({
  component: VendorRouteScreen,
});

function VendorRouteScreen() {
  return (
    <div className="flex flex-col gap-4">
      <StopList />
      <PlacedPool />
    </div>
  );
}
