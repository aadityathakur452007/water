import { useParams } from "@tanstack/react-router";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { errorMessage, useAdminQuery } from "@/hooks/use-admin-api";
import type { AuditRow, Page } from "@/lib/admin-types";
import { dateTime, num, phoneMasked, rupees } from "@/lib/money";
import type { VendorPreview } from "@/lib/vendor-types";

/**
 * Read-only "view as vendor" — composes the vendor's own reads through the
 * admin-gated preview endpoint plus their audit trail. Never imports
 * adminPost/adminPatch: no mutation affordance exists on this screen.
 */
export function VendorPreview() {
  const { vendorId } = useParams({ strict: false }) as { vendorId: string };
  const { data, isError, error, refetch } = useAdminQuery<VendorPreview>(`/v1/admin/vendors/${vendorId}/preview`);
  // Secondary query: errors surface inline (never silent undefined).
  const { data: audit, isError: auditError } = useAdminQuery<Page<AuditRow>>(
    `/v1/admin/audit?actor_id=${vendorId}`,
  );

  if (isError) {
    return (
      <Card>
        <CardContent className="flex flex-col items-center gap-3 py-16 text-center">
          <p className="text-destructive text-sm">{errorMessage(error)}</p>
          <Button variant="outline" size="sm" onClick={() => void refetch()}>
            Retry
          </Button>
        </CardContent>
      </Card>
    );
  }
  // Phase 6 S6.4: skeleton while loading — never a blank page.
  if (!data) {
    return (
      <Card>
        <CardContent className="flex flex-col gap-3 py-6">
          {[0, 1, 2].map((i) => (
            <Skeleton key={i} className="h-10 w-full" />
          ))}
        </CardContent>
      </Card>
    );
  }

  const v = data.vendor;
  const today = data.route;
  const stops = today?.stops ?? [];
  const done = stops.filter((s) => s.status === "done").length;
  const customers = data.customers.customers;
  const complaints = data.complaints.data;
  const trail = audit?.data ?? [];

  return (
    <div className="flex flex-col gap-4">
      <Card>
        <CardHeader>
          <CardTitle className="flex flex-wrap items-center gap-3 text-xl">
            {`${v.name ?? vendorId} — as vendor`}
            <Badge variant="outline">read-only</Badge>
            {v.suspended ? <Badge variant="outline">Blocked</Badge> : <Badge variant="outline">Active</Badge>}
          </CardTitle>
          <CardDescription>
            {`${phoneMasked(v.phone)} · KYC ${v.kyc_status} · joined ${dateTime(v.created_at)}`}
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="grid gap-4 sm:grid-cols-4">
            <div>
              <p className="text-muted-foreground text-xs">Today route</p>
              <p className="font-medium text-sm">
                {today?.route ? `${today.route.zone} · ${today.route.status}` : "No route today"}
              </p>
            </div>
            <div>
              <p className="text-muted-foreground text-xs">Stops done</p>
              <p className="font-medium text-xl tabular-nums">{`${num(done)} / ${num(stops.length)}`}</p>
            </div>
            <div>
              <p className="text-muted-foreground text-xs">Jama today</p>
              <p className="font-medium text-sm tabular-nums">
                {rupees((data.earnings?.cash_total ?? 0) + (data.earnings?.upi_total ?? 0))}
              </p>
            </div>
            <div>
              <p className="text-muted-foreground text-xs">Hold</p>
              <p className="font-medium text-sm tabular-nums">{rupees(data.earnings?.flagged_hold ?? 0)}</p>
            </div>
          </div>
        </CardContent>
      </Card>

      <div className="grid gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>Customers (held / dues)</CardTitle>
            <CardDescription>What the vendor sees on deposits</CardDescription>
          </CardHeader>
          <CardContent className="px-0 pb-2">
            <Table>
              <TableHeader className="[&_tr]:border-t">
                <TableRow>
                  <TableHead className="py-3">Customer</TableHead>
                  <TableHead className="py-3">Held</TableHead>
                  <TableHead className="py-3">Dues</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {customers.length ? (
                  customers.map((c) => (
                    <TableRow key={c.customer_id || c.customer_name} className="border-border/60">
                      <TableCell className="px-3 py-3 text-sm">{c.customer_name}</TableCell>
                      <TableCell className="px-3 py-3 text-sm tabular-nums">{num(c.held)}</TableCell>
                      <TableCell className="px-3 py-3 text-sm tabular-nums">{rupees(c.dues)}</TableCell>
                    </TableRow>
                  ))
                ) : (
                  <TableRow>
                    <TableCell colSpan={3} className="h-16 text-center text-muted-foreground">
                      No assigned customers today.
                    </TableCell>
                  </TableRow>
                )}
              </TableBody>
            </Table>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Complaints (assigned)</CardTitle>
            <CardDescription>What the vendor sees on support</CardDescription>
          </CardHeader>
          <CardContent className="flex flex-col gap-2 pb-2">
            {complaints.length ? (
              complaints.map((c) => (
                <div key={c.id} className="flex items-center gap-3 rounded-lg border px-3 py-2 text-sm">
                  <Badge variant="outline">{c.status}</Badge>
                  <span className="font-medium">{c.reason_code}</span>
                  <span className="min-w-0 flex-1 truncate text-muted-foreground">{c.text}</span>
                </div>
              ))
            ) : (
              <p className="text-muted-foreground text-sm">No assigned complaints.</p>
            )}
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Vendor action trail</CardTitle>
          <CardDescription>Audit rows for this actor — money, verify, access use</CardDescription>
        </CardHeader>
        <CardContent className="px-0 pb-2">
          <Table>
            <TableHeader className="[&_tr]:border-t">
              <TableRow>
                <TableHead className="py-3">Action</TableHead>
                <TableHead className="py-3">Entity</TableHead>
                <TableHead className="py-3">When</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {auditError ? (
                <TableRow>
                  <TableCell colSpan={3} className="h-16 text-center text-destructive text-sm">
                    Trail failed to load — main preview above is unaffected.
                  </TableCell>
                </TableRow>
              ) : trail.length ? (
                trail.map((r) => (
                  <TableRow key={r.id} className="border-border/60">
                    <TableCell className="px-3 py-3 font-medium text-sm">{r.action}</TableCell>
                    <TableCell className="px-3 py-3 text-muted-foreground text-sm">
                      {`${r.entity} · ${r.entity_id}`}
                    </TableCell>
                    <TableCell className="px-3 py-3 text-muted-foreground text-sm">{dateTime(r.created_at)}</TableCell>
                  </TableRow>
                ))
              ) : (
                <TableRow>
                  <TableCell colSpan={3} className="h-16 text-center text-muted-foreground">
                    No audit rows for this vendor yet.
                  </TableCell>
                </TableRow>
              )}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
    </div>
  );
}
