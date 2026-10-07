import * as React from "react";
import { Building2, CheckCircle2, Hash, MapPin, Search } from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { InputGroup, InputGroupAddon, InputGroupInput } from "@/components/ui/input-group";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { toast } from "@/components/ui/toast";
import { errorMessage, useAdminQuery, useInvalidateAdmin } from "@/hooks/use-admin-api";
import type { Page, ZoneRow } from "@/lib/admin-types";
import { adminPostServer } from "@/server/admin-api";
import { AddZoneDialog } from "./add-zone-dialog";

export function Zones() {
  const [search, setSearch] = React.useState("");
  const [busyId, setBusyId] = React.useState<string | null>(null);

  const invalidate = useInvalidateAdmin();
  const { data, isError, error, isLoading } = useAdminQuery<Page<ZoneRow>>("/v1/admin/zones");
  const zones = React.useMemo(() => data?.data ?? [], [data]);

  // Filtered rows
  const filtered = React.useMemo(() => {
    const q = search.trim().toLowerCase();
    if (!q) return zones;
    return zones.filter(
      (z) => z.name.toLowerCase().includes(q) || (z.pincodes && z.pincodes.toLowerCase().includes(q)),
    );
  }, [zones, search]);

  // Metrics
  const activeCount = React.useMemo(() => zones.filter((z) => z.active).length, [zones]);
  const totalPins = React.useMemo(() => {
    const set = new Set<string>();
    for (const z of zones) {
      if (z.pincodes) {
        for (const p of z.pincodes.split(",")) {
          const clean = p.trim();
          if (clean) set.add(clean);
        }
      }
    }
    return set.size;
  }, [zones]);
  const totalVendors = React.useMemo(
    () => zones.reduce((acc, z) => acc + (z.vendor_count ?? 0), 0),
    [zones],
  );

  async function toggleZoneActive(zone: ZoneRow) {
    setBusyId(zone.id);
    const nextActive = zone.active ? 0 : 1;
    try {
      await adminPostServer({
        data: {
          path: `/v1/admin/zones/${zone.id}`,
          body: { active: nextActive },
        },
      });
      invalidate("/v1/admin");
      toast.add({
        title: nextActive ? "Zone Activated" : "Zone Deactivated",
        description: `${zone.name} is now ${nextActive ? "active" : "inactive"}.`,
      });
    } catch (err) {
      toast.add({ title: "Update failed", description: errorMessage(err), type: "error" });
    } finally {
      setBusyId(null);
    }
  }

  return (
    <div className="flex flex-col gap-6">
      {/* Metric summary cards */}
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between pb-2">
            <CardTitle className="text-muted-foreground text-sm font-medium">Total Operating Zones</CardTitle>
            <MapPin className="size-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="font-bold text-2xl">{zones.length}</div>
            <p className="text-muted-foreground text-xs">{activeCount} active zones</p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between pb-2">
            <CardTitle className="text-muted-foreground text-sm font-medium">Active Coverage</CardTitle>
            <CheckCircle2 className="size-4 text-emerald-500" />
          </CardHeader>
          <CardContent>
            <div className="font-bold text-2xl text-emerald-600 dark:text-emerald-400">{activeCount}</div>
            <p className="text-muted-foreground text-xs">Ready for order dispatch</p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between pb-2">
            <CardTitle className="text-muted-foreground text-sm font-medium">Serviced Pincodes</CardTitle>
            <Hash className="size-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="font-bold text-2xl">{totalPins}</div>
            <p className="text-muted-foreground text-xs">Covered postal clusters</p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between pb-2">
            <CardTitle className="text-muted-foreground text-sm font-medium">Assigned Agency Hubs</CardTitle>
            <Building2 className="size-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="font-bold text-2xl">{totalVendors}</div>
            <p className="text-muted-foreground text-xs">Active vendor links</p>
          </CardContent>
        </Card>
      </div>

      {/* Main Zones Table Card */}
      <Card>
        <CardHeader className="flex flex-row items-center justify-between border-b">
          <div>
            <CardTitle className="text-xl leading-none">Operating Zones</CardTitle>
            <CardDescription className="mt-1">
              Distribution areas and delivery postal clusters. Orders automatically route to matching zones.
            </CardDescription>
          </div>
          <AddZoneDialog />
        </CardHeader>

        <CardContent className="flex flex-col gap-4 px-0">
          {isError ? <p className="px-4 text-destructive text-sm">{errorMessage(error)}</p> : null}

          <div className="px-4">
            <InputGroup className="h-7 w-full md:w-72">
              <InputGroupAddon align="inline-start">
                <Search className="size-3.5" />
              </InputGroupAddon>
              <InputGroupInput
                className="h-7"
                placeholder="Search by zone name or pincode..."
                value={search}
                onChange={(e) => setSearch(e.target.value)}
              />
            </InputGroup>
          </div>

          <Table className="**:data-[slot='table-cell']:px-4 **:data-[slot='table-head']:px-4">
            <TableHeader className="[&_tr]:border-t">
              <TableRow>
                <TableHead className="py-4 font-normal">Zone Name</TableHead>
                <TableHead className="py-4 font-normal">Pincodes Covered</TableHead>
                <TableHead className="py-4 font-normal">Attached Vendors</TableHead>
                <TableHead className="py-4 font-normal">Status</TableHead>
                <TableHead className="py-4 text-right font-normal">Actions</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {isLoading ? (
                <TableRow>
                  <TableCell colSpan={5} className="h-24 text-center text-muted-foreground">
                    Loading operating zones...
                  </TableCell>
                </TableRow>
              ) : filtered.length > 0 ? (
                filtered.map((z) => {
                  const pinsList = z.pincodes ? z.pincodes.split(",").map((p) => p.trim()).filter(Boolean) : [];
                  return (
                    <TableRow key={z.id} className="border-border/60 hover:bg-white/2.5">
                      <TableCell className="px-4 py-3 font-medium">
                        <div className="flex items-center gap-2">
                          <MapPin className="size-4 text-muted-foreground" />
                          <span>{z.name}</span>
                        </div>
                      </TableCell>

                      <TableCell className="px-4 py-3">
                        <div className="flex flex-wrap gap-1">
                          {pinsList.length > 0 ? (
                            pinsList.map((p) => (
                              <Badge key={p} variant="secondary" className="font-mono text-xs">
                                {p}
                              </Badge>
                            ))
                          ) : (
                            <span className="text-muted-foreground text-xs">No pincodes assigned</span>
                          )}
                        </div>
                      </TableCell>

                      <TableCell className="px-4 py-3 text-sm">
                        <span className="tabular-nums font-semibold">{z.vendor_count ?? 0}</span>
                        <span className="text-muted-foreground ml-1 text-xs">hubs</span>
                      </TableCell>

                      <TableCell className="px-4 py-3">
                        <Badge
                          variant="outline"
                          className={
                            z.active
                              ? "border-emerald-500/20 bg-emerald-500/10 text-emerald-600 dark:text-emerald-400"
                              : "border-muted-foreground/30 text-muted-foreground"
                          }
                        >
                          {z.active ? "Active" : "Inactive"}
                        </Badge>
                      </TableCell>

                      <TableCell className="px-4 py-3 text-right">
                        <Button
                          variant="outline"
                          size="sm"
                          disabled={busyId === z.id}
                          onClick={() => void toggleZoneActive(z)}
                        >
                          {z.active ? "Deactivate" : "Activate"}
                        </Button>
                      </TableCell>
                    </TableRow>
                  );
                })
              ) : (
                <TableRow>
                  <TableCell colSpan={5} className="h-24 text-center text-muted-foreground">
                    {search ? "No operating zones match your search." : "No operating zones created yet. Click 'Add Zone' above to get started."}
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
