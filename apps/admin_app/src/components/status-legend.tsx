import { Badge } from "@/components/ui/badge";

/**
 * Single status legend for the three status vocabularies (orders, payments,
 * vendor payouts). Mounted on the Orders and Payments screens so chip colors
 * mean the same thing everywhere.
 */
const GROUPS: Array<{ title: string; items: string[] }> = [
  {
    title: "Orders",
    items: ["placed", "accepted", "picked", "packed", "assigned", "dispatched", "delivered", "failed", "cancelled", "rejected"],
  },
  {
    title: "Payments",
    items: ["unpaid", "link_sent", "paid_upi", "paid_cash", "partial_dues"],
  },
  {
    title: "Payouts & refunds",
    items: ["pending", "claimed", "approved", "done", "failed"],
  },
];

export function StatusLegend() {
  return (
    <div className="flex flex-wrap items-center gap-x-4 gap-y-1 px-4 pb-2" aria-label="Status legend">
      {GROUPS.map((g) => (
        <span key={g.title} className="flex flex-wrap items-center gap-1.5">
          <span className="text-muted-foreground text-xs">{`${g.title}:`}</span>
          {g.items.map((s) => (
            <Badge key={s} variant="outline" className="px-1.5 py-0 font-normal text-xs">
              {s}
            </Badge>
          ))}
        </span>
      ))}
    </div>
  );
}
