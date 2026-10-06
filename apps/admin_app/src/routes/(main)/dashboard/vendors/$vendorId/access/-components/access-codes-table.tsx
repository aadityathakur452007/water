import * as React from "react";

import { useParams } from "@tanstack/react-router";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { toast } from "@/components/ui/toast";
import { errorMessage, useAdminQuery, useInvalidateAdmin } from "@/hooks/use-admin-api";
import type { Page } from "@/lib/admin-types";
import { dateTime } from "@/lib/money";
import type { AccessCodeRow } from "@/lib/vendor-types";
import { adminPostServer } from "@/server/admin-api";

/** Masked access-code list — plaintext never stored, never re-shown. Revoke is a timestamp, not a delete. */
export function AccessCodesTable() {
  const { vendorId } = useParams({ strict: false }) as { vendorId: string };
  const invalidate = useInvalidateAdmin();
  const { data, isError, error } = useAdminQuery<Page<AccessCodeRow> | { codes: AccessCodeRow[] }>(
    `/v1/admin/vendors/${vendorId}/access-codes`,
  );
  const [confirmId, setConfirmId] = React.useState<string | null>(null);
  const [busy, setBusy] = React.useState(false);

  if (isError) {
    return (
      <Card>
        <CardContent className="py-16 text-center text-destructive text-sm">{errorMessage(error)}</CardContent>
      </Card>
    );
  }
  if (!data) {
    // Phase 6 S6.4: skeleton while loading — never a blank card.
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
  const rows = Array.isArray((data as Page<AccessCodeRow>).data)
    ? (data as Page<AccessCodeRow>).data
    : ((data as { codes: AccessCodeRow[] }).codes ?? []);

  async function revoke(id: string) {
    setBusy(true);
    try {
      await adminPostServer({ data: { path: `/v1/admin/vendors/${vendorId}/access-codes/${id}/revoke`, body: {} } });
      toast.add({ title: "Code revoked", description: id });
      setConfirmId(null);
      invalidate("/v1/admin");
    } catch (err) {
      toast.add({ title: "Revoke failed", description: errorMessage(err), type: "error" });
    } finally {
      setBusy(false);
    }
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Access codes</CardTitle>
        <CardDescription>
          Masked list — issuance, revocation and last use. Plaintext shows once at issue.
        </CardDescription>
      </CardHeader>
      <CardContent className="px-0 pb-2">
        <Table className="**:data-[slot='table-cell']:px-4 **:data-[slot='table-head']:px-4">
          <TableHeader className="[&_tr]:border-t">
            <TableRow>
              <TableHead className="py-3">Code</TableHead>
              <TableHead className="py-3">Expires</TableHead>
              <TableHead className="py-3">Revoked</TableHead>
              <TableHead className="py-3">Last used</TableHead>
              <TableHead className="py-3 text-right">Action</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.length ? (
              rows.map((c) => (
                <TableRow key={c.id} className="border-border/60">
                  <TableCell className="px-3 py-3 font-medium font-mono text-sm">{c.masked_hint}</TableCell>
                  <TableCell className="px-3 py-3 text-sm">{c.expires_at ? dateTime(c.expires_at) : "never"}</TableCell>
                  <TableCell className="px-3 py-3 text-sm">
                    {c.revoked_at ? (
                      <Badge variant="outline">revoked</Badge>
                    ) : (
                      <span className="text-muted-foreground">—</span>
                    )}
                  </TableCell>
                  <TableCell className="px-3 py-3 text-muted-foreground text-sm">
                    {c.last_used_at ? dateTime(c.last_used_at) : "never"}
                  </TableCell>
                  <TableCell className="px-3 py-3 text-right text-sm">
                    {c.revoked_at ? null : confirmId === c.id ? (
                      <span className="flex justify-end gap-2">
                        <Button variant="ghost" size="sm" className="h-7" onClick={() => setConfirmId(null)}>
                          Keep
                        </Button>
                        <Button
                          variant="destructive"
                          size="sm"
                          className="h-7"
                          disabled={busy}
                          onClick={() => void revoke(c.id)}
                        >
                          {busy ? "Working…" : "Confirm revoke"}
                        </Button>
                      </span>
                    ) : (
                      <Button variant="outline" size="sm" className="h-7" onClick={() => setConfirmId(c.id)}>
                        Revoke
                      </Button>
                    )}
                  </TableCell>
                </TableRow>
              ))
            ) : (
              <TableRow>
                <TableCell colSpan={5} className="h-20 text-center text-muted-foreground">
                  No codes issued for this vendor.
                </TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  );
}
