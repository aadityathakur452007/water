import * as React from "react";

import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { toast } from "@/components/ui/toast";
import { errorMessage, useAdminQuery, useInvalidateAdmin } from "@/hooks/use-admin-api";
import type { ConfigRow, Page } from "@/lib/admin-types";
import { dateTime } from "@/lib/money";
import { adminPostServer } from "@/server/admin-api";

/** Per-key unit labels (the old "paise unless noted" header hid money-traps). */
function unitFor(key: string): string {
  if (key.endsWith("_paise")) return "paise";
  if (key.endsWith("_enabled") || key.startsWith("access_code_")) return "flag (0/1)";
  if (key.includes("ttl") || key.includes("minutes")) return "minutes";
  return "text";
}

export function Config() {
  const { data } = useAdminQuery<Page<ConfigRow>>("/v1/admin/config");
  const rows = data?.data ?? [];
  const [drafts, setDrafts] = React.useState<Record<string, string>>({});
  const invalidate = useInvalidateAdmin();

  async function save(row: ConfigRow) {
    const value = drafts[row.key];
    if (value == null || value === row.value) return;
    try {
      await adminPostServer({ data: { path: "/v1/admin/config", body: { key: row.key, value } } });
      toast.add({ title: "Config updated", description: `${row.key} → ${value} (audited)` });
      invalidate("/v1/admin");
    } catch (err) {
      toast.add({ title: "Update failed", description: errorMessage(err), type: "error" });
    }
  }

  return (
    <Card>
      <CardHeader className="border-b">
        <CardTitle className="text-xl leading-none">Config</CardTitle>
        <CardDescription>Rates, deposit and caps — every change is audit-logged server-side.</CardDescription>
      </CardHeader>
      <CardContent className="px-0 pb-4">
        <Table className="**:data-[slot='table-cell']:px-4 **:data-[slot='table-head']:px-4">
          <TableHeader className="[&_tr]:border-t">
              <TableRow>
                <TableHead className="py-3">Key</TableHead>
                <TableHead className="py-3">Value</TableHead>
                <TableHead className="py-3">Unit</TableHead>
                <TableHead className="py-3">Effective</TableHead>
                <TableHead className="py-3">Updated</TableHead>
                <TableHead className="py-3 text-right">Save</TableHead>
              </TableRow>
          </TableHeader>
          <TableBody>
            {rows.map((r) => (
              <TableRow key={r.key} className="border-border/60">
                <TableCell className="px-3 py-3 font-medium text-sm">{r.key}</TableCell>
                <TableCell className="px-3 py-3">
                  <Input
                    className="h-8 w-40 tabular-nums"
                    defaultValue={r.value}
                    onChange={(e) => setDrafts((d) => ({ ...d, [r.key]: e.target.value }))}
                  />
                </TableCell>
                <TableCell className="px-3 py-3 text-muted-foreground text-xs">{unitFor(r.key)}</TableCell>
                <TableCell className="px-3 py-3 text-muted-foreground text-sm">{r.effective_from ?? "—"}</TableCell>
                <TableCell className="px-3 py-3 text-muted-foreground text-sm">
                  {r.updated_at ? dateTime(r.updated_at) : "—"}
                </TableCell>
                <TableCell className="px-3 py-3 text-right">
                  <Button size="sm" variant="outline" onClick={() => void save(r)}>
                    Save
                  </Button>
                </TableCell>
              </TableRow>
            ))}
            {rows.length === 0 ? (
              <TableRow>
                <TableCell colSpan={5} className="h-24 text-center text-muted-foreground">
                  No config keys.
                </TableCell>
              </TableRow>
            ) : null}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  );
}
