import { useNavigate } from "@tanstack/react-router";

import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { VendorApiError } from "@/server/vendor-api";

import { vendorErrorMessage } from "@/hooks/use-vendor-api";

/** Loading skeleton — every vendor screen renders this while its query is in flight. */
export function VendorLoading({ lines = 4 }: { lines?: number }) {
  return (
    <Card aria-busy="true" aria-label="Loading">
      <CardContent className="flex flex-col gap-3 py-6">
        {Array.from({ length: lines }, (_, i) => (
          <Skeleton key={i} className="h-10 w-full" />
        ))}
      </CardContent>
    </Card>
  );
}

/** Error + retry — 401/403 also offer the login door (session expired or wrong role). */
export function VendorError({ error, onRetry }: { error: unknown; onRetry: () => void }) {
  const navigate = useNavigate();
  const needsLogin = error instanceof VendorApiError && (error.status === 401 || error.status === 403);
  return (
    <Card>
      <CardContent className="flex flex-col items-center gap-3 py-10 text-center">
        <p role="alert" className="font-medium text-destructive text-sm">
          {vendorErrorMessage(error)}
        </p>
        <div className="flex gap-2">
          <Button variant="outline" size="sm" onClick={onRetry}>
            Retry
          </Button>
          {needsLogin ? (
            <Button size="sm" onClick={() => navigate({ to: "/vendor/login", replace: true })}>
              Sign in again
            </Button>
          ) : null}
        </div>
      </CardContent>
    </Card>
  );
}

/** Honest empty — names what is missing, never a blank card. */
export function VendorEmpty({ title, hint }: { title: string; hint?: string }) {
  return (
    <Card>
      <CardContent className="flex flex-col items-center gap-1 py-10 text-center">
        <p className="font-medium text-sm">{title}</p>
        {hint ? <p className="text-muted-foreground text-xs">{hint}</p> : null}
      </CardContent>
    </Card>
  );
}
