import { Award, Users } from "lucide-react";

import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { useAdminQuery } from "@/hooks/use-admin-api";
import type { UserRow as ApiUserRow, CustodyRow, Page } from "@/lib/admin-types";
import { num, phoneMasked, rupees } from "@/lib/money";
import { getInitials } from "@/lib/utils";

/** FR-32-lite: who carries the business — vendors by duty load, customers by order count. */
export function Leaderboards() {
  const { data: custody } = useAdminQuery<Page<CustodyRow>>("/v1/admin/custody");
  const { data: users } = useAdminQuery<Page<ApiUserRow>>("/v1/admin/users");

  const vendors = [...(custody?.data ?? [])].sort((a, b) => b.on_duty - a.on_duty).slice(0, 5);
  const customers = (users?.data ?? []).filter((u) => u.role === "user").slice(0, 5);

  return (
    <div className="grid gap-4 lg:grid-cols-2">
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Award className="size-4" aria-hidden />
            Vendor load — today
          </CardTitle>
          <CardDescription>On-duty stops and jars in hand (capacity balance, F2)</CardDescription>
        </CardHeader>
        <CardContent className="px-0 pb-2">
          <Table className="**:data-[slot='table-cell']:px-4 **:data-[slot='table-head']:px-4">
            <TableHeader className="[&_tr]:border-t">
              <TableRow>
                <TableHead className="py-3">Vendor</TableHead>
                <TableHead className="py-3">On duty</TableHead>
                <TableHead className="py-3">Jars in hand</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {vendors.length ? (
                vendors.map((v) => (
                  <TableRow key={v.vendor_id} className="border-border/60">
                    <TableCell className="px-3 py-3 font-medium text-sm">{v.name ?? v.vendor_id}</TableCell>
                    <TableCell className="px-3 py-3 text-sm tabular-nums">{num(v.on_duty)}</TableCell>
                    <TableCell className="px-3 py-3 text-sm tabular-nums">
                      {num(v.in_hand)}
                      {v.in_hand > 30 ? (
                        <Badge variant="outline" className="ml-2 border-amber-500/20 bg-amber-500/10 text-amber-600">
                          custody watch
                        </Badge>
                      ) : null}
                    </TableCell>
                  </TableRow>
                ))
              ) : (
                <TableRow>
                  <TableCell colSpan={3} className="h-16 text-center text-muted-foreground">
                    No custody data yet.
                  </TableCell>
                </TableRow>
              )}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Users className="size-4" aria-hidden />
            Customer book — newest
          </CardTitle>
          <CardDescription>Directory head (CRM-lite, FR-32; ranking lands with the aggregate read)</CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-2 pb-2">
          {customers.map((c) => (
            <div key={c.id} className="flex items-center gap-3 rounded-lg border px-3 py-2">
              <Avatar size="sm">
                <AvatarFallback>{getInitials(c.name ?? c.id)}</AvatarFallback>
              </Avatar>
              <div className="min-w-0 flex-1">
                <p className="truncate font-medium text-sm">{c.name ?? c.id}</p>
                <p className="truncate text-muted-foreground text-xs">{phoneMasked(c.phone)}</p>
              </div>
              <Badge variant="outline">{c.kyc_status}</Badge>
            </div>
          ))}
          {customers.length === 0 ? (
            <p className="py-6 text-center text-muted-foreground text-sm">No customers yet.</p>
          ) : null}
          <p className="text-muted-foreground text-xs">
            Lifetime spend per customer flows in from user details ({rupees(0)} placeholder removed at scale).
          </p>
        </CardContent>
      </Card>
    </div>
  );
}
