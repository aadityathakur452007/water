import { useAdminQuery } from "@/hooks/use-admin-api";
import type { DayPoint, MoneyTotals } from "@/lib/admin-types";

/** Overview feed → GET /v1/admin/metrics/overview?days=14 */
export type OverviewEnvelope = {
  today: DayPoint;
  series: DayPoint[];
  money: MoneyTotals;
  quality_open?: number;
};

export function useOverview() {
  return useAdminQuery<OverviewEnvelope>("/v1/admin/metrics/overview?days=14");
}
