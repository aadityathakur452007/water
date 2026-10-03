import * as React from "react";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { errorMessage, useAdminQuery } from "@/hooks/use-admin-api";
import type { LedgerRow, Page } from "@/lib/admin-types";
import { num, phoneMasked, rupees } from "@/lib/money";

import { AdjustSheet } from "./adjust-sheet";

export function Ledger() {
  const { data, isError, error } = useAdminQuery<Page<LedgerRow>>("/v1/admin/ledger");
  const rows = data?.data ?? [];
  const [adjustTarget, setAdjustTarget] = React.useState<LedgerRow | null>(null);

  return (
    <Card>
      <CardHeader className="border-b">
        <CardTitle className="text-xl leading-none">Jar ledger</CardTitle>
        <CardDescription>Every customer's jar position — held at home, deposit paid, dues outstanding.</CardDescription>
      </CardHeader>
      <CardContent className="px-0">
        {isError ? (
          <p className="px-4 text-destructive text-sm">{errorMessage(error)}</p>
        ) : (
          <Table className="**:data-[slot='table-cell']:px-4 **:data-[slot='table-head']:px-4">
            <TableHeader className="[&_tr]:border-t">
              <TableRow>
                <TableHead className="py-3">Customer</TableHead>
                <TableHead className="py-3">Jars held</TableHead>
                <TableHead className="py-3">Deposit paid</TableHead>
                <TableHead className="py-3">Refunded</TableHead>
                <TableHead className="py-3">Dues</TableHead>
                <TableHead className="py-3 text-right">Adjust</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {rows.length ? (
                rows.map((r) => (
                  <TableRow key={r.customer_id} className="border-border/60 hover:bg-white/2.5">
                    <TableCell className="px-3 py-3 text-sm">
                      <div className="flex flex-col">
                        <span className="font-medium">{r.customer_name ?? r.customer_id}</span>
                        <span className="text-muted-foreground text-xs">{phoneMasked(r.customer_phone)}</span>
                      </div>
                    </TableCell>
                    <TableCell className="px-3 py-3 text-sm tabular-nums">
                      {num(r.held)}
                      {r.held > 10 ? (
                        <Badge variant="outline" className="ml-2 border-amber-500/20 bg-amber-500/10 text-amber-600">
                          hold limit
                        </Badge>
                      ) : null}
                    </TableCell>
                    <TableCell className="px-3 py-3 text-sm tabular-nums">{rupees(r.deposit_paid)}</TableCell>
                    <TableCell className="px-3 py-3 text-sm tabular-nums">{rupees(r.deposit_refunded)}</TableCell>
                    <TableCell className="px-3 py-3 font-medium text-sm tabular-nums">
                      {r.dues > 0 ? rupees(r.dues) : "—"}
                    </TableCell>
                    <TableCell className="px-3 py-3 text-right">
                      <Button size="sm" variant="outline" onClick={() => setAdjustTarget(r)}>
                        Adjust
                      </Button>
                    </TableCell>
                  </TableRow>
                ))
              ) : (
                <TableRow>
                  <TableCell colSpan={6} className="h-24 text-center text-muted-foreground">
                    No ledger rows.
                  </TableCell>
                </TableRow>
              )}
            </TableBody>
          </Table>
        )}
      </CardContent>
      <AdjustSheet row={adjustTarget} onClose={() => setAdjustTarget(null)} />
    </Card>
  );
}
