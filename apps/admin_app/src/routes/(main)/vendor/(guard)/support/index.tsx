import { createFileRoute } from "@tanstack/react-router";

import { QualityCheck } from "./-components/quality-check";
import { SupportQueue } from "./-components/support-queue";

export const Route = createFileRoute("/(main)/vendor/(guard)/support/")({
  component: Page,
});

function Page() {
  return (
    <div className="flex flex-col gap-4">
      <SupportQueue />
      <QualityCheck />
    </div>
  );
}
