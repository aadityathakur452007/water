import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { toast } from "@/components/ui/toast";
import { errorMessage, useAdminQuery, useInvalidateAdmin } from "@/hooks/use-admin-api";
import type { ComplaintRow, Page, QualityRow, StrikeRow } from "@/lib/admin-types";
import { dateTime } from "@/lib/money";
import { adminPostServer } from "@/server/admin-api";

/** FR-29 wire shape of GET /v1/admin/returns (10-working-day pickup SLA). */
type ReturnRow = {
  id: string;
  user_id: string;
  qty: number;
  address_id: string | null;
  status: string;
  sla_due: string | null;
  created_at: string;
};

export function Trust() {
  const { data: quality } = useAdminQuery<Page<QualityRow>>("/v1/admin/quality");
  const { data: strikes } = useAdminQuery<Page<StrikeRow>>("/v1/admin/strikes");
  const { data: complaints } = useAdminQuery<Page<ComplaintRow>>("/v1/admin/complaints");
  const { data: returns } = useAdminQuery<Page<ReturnRow>>("/v1/admin/returns");
  const invalidate = useInvalidateAdmin();

  const openQuality = (quality?.data ?? []).filter((q) => q.status === "open").length;
  const openStrikes = (strikes?.data ?? []).filter((s) => !s.cleared_at).length;
  const openComplaints = (complaints?.data ?? []).filter((c) => c.status !== "resolved").length;
  const openReturns = (returns?.data ?? []).filter((r) => r.status !== "refunded").length;

  async function act(path: string, description: string) {
    try {
      await adminPostServer({ data: { path, body: {} } });
      toast.add({ title: "Done", description });
      invalidate("/v1/admin");
    } catch (err) {
      toast.add({ title: "Action failed", description: errorMessage(err), type: "error" });
    }
  }

  return (
    <Card>
      <CardHeader className="border-b">
        <CardTitle className="text-xl leading-none">Trust</CardTitle>
        <CardDescription>
          Quality incidents, strikes and complaints — every resolve is audited server-side.
        </CardDescription>
      </CardHeader>
      <CardContent className="px-0">
        <Tabs defaultValue="quality">
          <div className="flex items-center justify-between px-4">
            <TabsList>
              <TabsTrigger value="quality">{`Quality (${openQuality})`}</TabsTrigger>
              <TabsTrigger value="strikes">{`Strikes (${openStrikes})`}</TabsTrigger>
              <TabsTrigger value="complaints">{`Complaints (${openComplaints})`}</TabsTrigger>
              <TabsTrigger value="returns">{`Returns (${openReturns})`}</TabsTrigger>
            </TabsList>
          </div>
          <TabsContent value="quality">
            <TrustTable
              rows={(quality?.data ?? []).map((q) => ({
                id: q.id,
                line1: `${q.order_id} — ${q.reason_code}`,
                line2: q.description,
                badge: q.status,
                at: dateTime(q.created_at),
                actions:
                  q.status === "open"
                    ? [
                        { label: "Confirm", fn: () => act(`/v1/admin/quality/${q.id}/confirm`, "Incident confirmed") },
                        { label: "Reject", fn: () => act(`/v1/admin/quality/${q.id}/reject`, "Incident rejected") },
                      ]
                    : [],
              }))}
            />
          </TabsContent>
          <TabsContent value="strikes">
            <TrustTable
              rows={(strikes?.data ?? []).map((s) => ({
                id: s.id,
                line1: `${s.subject_id} — ${s.kind} (severity ${s.severity})`,
                line2: s.note,
                badge: s.cleared_at ? "cleared" : "open",
                at: dateTime(s.created_at),
                actions: s.cleared_at
                  ? []
                  : [{ label: "Clear strike", fn: () => act(`/v1/admin/strikes/${s.id}/clear`, "Strike cleared") }],
              }))}
            />
          </TabsContent>
          <TabsContent value="complaints">
            <TrustTable
              rows={(complaints?.data ?? []).map((c) => ({
                id: c.id,
                line1: `${c.order_id} — ${c.reason_code}`,
                line2: c.text,
                badge: c.status,
                at: dateTime(c.created_at),
                actions:
                  c.status !== "resolved"
                    ? [
                        {
                          label: "Resolve",
                          fn: () => act(`/v1/admin/complaints/${c.id}/resolve`, "Complaint resolved"),
                        },
                      ]
                    : [],
              }))}
            />
          </TabsContent>
          <TabsContent value="returns">
            <TrustTable
              rows={(returns?.data ?? []).map((r) => ({
                id: r.id,
                line1: `${r.user_id} — ${r.qty} jar${r.qty === 1 ? "" : "s"} return (FR-29, 10-day SLA)`,
                line2: r.sla_due ? `Pickup due by ${dateTime(r.sla_due)}` : "No SLA date set",
                badge: r.status,
                at: dateTime(r.created_at),
                actions: [],
              }))}
            />
          </TabsContent>
        </Tabs>
      </CardContent>
    </Card>
  );
}

type TrustEntry = {
  id: string;
  line1: string;
  line2: string;
  badge: string;
  at: string;
  actions: Array<{ label: string; fn: () => Promise<void> | void }>;
};

function TrustTable({ rows }: { rows: TrustEntry[] }) {
  return (
    <div className="flex flex-col gap-2 px-4 py-3">
      {rows.length ? (
        rows.map((r) => (
          <div key={r.id} className="flex flex-wrap items-center justify-between gap-3 rounded-lg border px-3 py-2.5">
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2 font-medium text-sm">
                <Badge variant="outline">{r.badge}</Badge>
                {r.line1}
              </div>
              <p className="mt-0.5 truncate text-muted-foreground text-sm">{r.line2}</p>
              <p className="text-muted-foreground text-xs">{r.at}</p>
            </div>
            <div className="flex gap-2">
              {r.actions.map((a) => (
                <Button key={a.label} size="sm" variant="outline" onClick={() => void a.fn()}>
                  {a.label}
                </Button>
              ))}
            </div>
          </div>
        ))
      ) : (
        <p className="py-8 text-center text-muted-foreground text-sm">Nothing in this queue.</p>
      )}
    </div>
  );
}
