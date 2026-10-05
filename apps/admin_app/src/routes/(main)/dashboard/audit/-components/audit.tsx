import * as React from "react";

import { Search } from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { InputGroup, InputGroupAddon, InputGroupInput } from "@/components/ui/input-group";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { toast } from "@/components/ui/toast";
import { errorMessage } from "@/hooks/use-admin-api";
import { useCursorPages } from "@/hooks/use-cursor-pages";
import type { AuditRow } from "@/lib/admin-types";
import { dateTime } from "@/lib/money";
import { adminExportCsvServer } from "@/server/admin-api";

export function Audit() {
  const [actor, setActor] = React.useState("");
  const [action, setAction] = React.useState("");

  const params = new URLSearchParams();
  if (actor.trim()) params.set("actor_id", actor.trim());
  if (action.trim()) params.set("action", action.trim());
  const qs = params.toString();

  const { rows, nextCursor, loadMore, isError, error } = useCursorPages<AuditRow>(
    `/v1/admin/audit${qs ? `?${qs}` : ""}`,
  );

  async function exportCsv() {
    try {
      const text = await adminExportCsvServer({ data: { query: qs ? `?${qs}` : "" } });
      const blob = new Blob([text], { type: "text/csv;charset=utf-8" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = "shodasha-audit.csv";
      a.click();
      URL.revokeObjectURL(url);
    } catch (err) {
      toast.add({ title: "Export failed", description: errorMessage(err), type: "error" });
    }
  }

  return (
    <Card>
      <CardHeader className="border-b">
        <CardTitle className="text-xl leading-none">Audit log</CardTitle>
        <CardDescription>Server journal — every money edit, state transition and admin action.</CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-4 px-0 pb-4">
        <div className="flex flex-wrap items-center gap-3 px-4">
          <InputGroup className="h-7 w-56">
            <InputGroupAddon align="inline-start">
              <Search className="size-3.5" />
            </InputGroupAddon>
            <InputGroupInput
              className="h-7"
              placeholder="actor_id…"
              value={actor}
              onChange={(e) => setActor(e.target.value)}
            />
          </InputGroup>
          <InputGroup className="h-7 w-56">
            <InputGroupAddon align="inline-start">
              <Search className="size-3.5" />
            </InputGroupAddon>
            <InputGroupInput
              className="h-7"
              placeholder="action e.g. user.suspend"
              value={action}
              onChange={(e) => setAction(e.target.value)}
            />
          </InputGroup>
          <Button variant="outline" size="sm" onClick={() => void exportCsv()}>
            Export CSV ({rows.length} loaded)
          </Button>
        </div>
        {isError ? (
          <p className="px-4 text-destructive text-sm">{errorMessage(error)}</p>
        ) : (
          <Table className="**:data-[slot='table-cell']:px-4 **:data-[slot='table-head']:px-4">
            <TableHeader className="[&_tr]:border-t">
              <TableRow>
                <TableHead className="py-3">At</TableHead>
                <TableHead className="py-3">Actor</TableHead>
                <TableHead className="py-3">Action</TableHead>
                <TableHead className="py-3">Entity</TableHead>
                <TableHead className="py-3">Change</TableHead>
                <TableHead className="py-3">Trace</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {rows.length ? (
                rows.map((r) => (
                  <TableRow key={r.id} className="border-border/60 hover:bg-white/2.5">
                    <TableCell className="px-3 py-3 text-muted-foreground text-sm">{dateTime(r.created_at)}</TableCell>
                    <TableCell className="px-3 py-3 text-sm">
                      <div className="flex flex-col">
                        <span className="font-medium">{r.actor_id}</span>
                        <span className="text-muted-foreground text-xs">{r.actor_role}</span>
                      </div>
                    </TableCell>
                    <TableCell className="px-3 py-3 text-sm">
                      <Badge variant="outline">{r.action}</Badge>
                    </TableCell>
                    <TableCell className="px-3 py-3 text-sm">{`${r.entity} · ${r.entity_id}`}</TableCell>
                    <TableCell className="max-w-64 truncate px-3 py-3 font-mono text-xs">{`${r.before} → ${r.after}`}</TableCell>
                    <TableCell className="px-3 py-3 font-mono text-muted-foreground text-xs">{r.trace_id}</TableCell>
                  </TableRow>
                ))
              ) : (
                <TableRow>
                  <TableCell colSpan={6} className="h-24 text-center text-muted-foreground">
                    No audit entries match.
                  </TableCell>
                </TableRow>
              )}
            </TableBody>
          </Table>
        )}
        <div className="flex items-center justify-between px-4">
          <p className="text-muted-foreground text-xs">
            {`${rows.length} loaded${nextCursor ? " · more on server" : ""}`}
          </p>
          {nextCursor ? (
            <Button variant="outline" size="sm" onClick={loadMore}>
              Load more
            </Button>
          ) : null}
        </div>
      </CardContent>
    </Card>
  );
}
