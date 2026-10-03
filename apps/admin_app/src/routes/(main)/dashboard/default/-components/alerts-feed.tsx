import { useNavigate } from "@tanstack/react-router";

import { AlertTriangle, ArrowRight, ShieldHalf } from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardAction, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { useAdminQuery } from "@/hooks/use-admin-api";
import type { Page, QualityRow } from "@/lib/admin-types";
import { rupees } from "@/lib/money";

import { useOverview } from "./overview-data";

/** Alerts feed — trust + dues flags deep-linking to their surfaces (flow C). */
export function AlertsFeed() {
  const navigate = useNavigate();
  const { data: overview } = useOverview();
  const { data: quality } = useAdminQuery<Page<QualityRow>>("/v1/admin/quality");

  const openQuality = quality?.data.filter((q) => q.status === "open") ?? [];
  const dues = overview?.money.dues_paise ?? 0;

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <AlertTriangle className="size-4" aria-hidden />
          Alerts
        </CardTitle>
        <CardDescription>Trust queue and money flags needing review</CardDescription>
        <CardAction>
          <Button variant="outline" size="sm" onClick={() => navigate({ to: "/dashboard/trust" })}>
            <ShieldHalf /> Open Trust
            <ArrowRight />
          </Button>
        </CardAction>
      </CardHeader>
      <CardContent className="flex flex-col gap-2">
        {openQuality.length === 0 && dues === 0 ? (
          <p className="text-muted-foreground text-sm">No open alerts. All clear.</p>
        ) : (
          <>
            {openQuality.slice(0, 3).map((q) => (
              <button
                key={q.id}
                type="button"
                onClick={() => navigate({ to: "/dashboard/trust" })}
                className="flex items-center justify-between rounded-lg border px-3 py-2 text-left text-sm hover:bg-muted/40"
              >
                <span>
                  <Badge variant="outline" className="mr-2">
                    quality
                  </Badge>
                  {`${q.order_id} — ${q.reason_code}`}
                </span>
                <ArrowRight className="size-4 text-muted-foreground" aria-hidden />
              </button>
            ))}
            {dues > 0 ? (
              <button
                type="button"
                onClick={() => navigate({ to: "/dashboard/ledger" })}
                className="flex items-center justify-between rounded-lg border px-3 py-2 text-left text-sm hover:bg-muted/40"
              >
                <span>
                  <Badge variant="outline" className="mr-2">
                    dues
                  </Badge>
                  {`${rupees(dues)} outstanding credit`}
                </span>
                <ArrowRight className="size-4 text-muted-foreground" aria-hidden />
              </button>
            ) : null}
          </>
        )}
      </CardContent>
    </Card>
  );
}
