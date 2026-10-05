import { createFileRoute } from "@tanstack/react-router";

import { Card, CardAction, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

import { AccessCodesTable } from "./-components/access-codes-table";
import { IssueCodeDialog } from "./-components/issue-code-dialog";

export const Route = createFileRoute("/(main)/dashboard/vendors/$vendorId/access/")({
  component: Page,
});

function Page() {
  return (
    <div className="flex flex-col gap-4">
      <Card>
        <CardHeader>
          <CardTitle className="text-xl leading-none">Vendor access</CardTitle>
          <CardDescription>Login codes for this vendor — issue once, revoke anytime.</CardDescription>
          <CardAction>
            <IssueCodeDialog />
          </CardAction>
        </CardHeader>
      </Card>
      <AccessCodesTable />
    </div>
  );
}
