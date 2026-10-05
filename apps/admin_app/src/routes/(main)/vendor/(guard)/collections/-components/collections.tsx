import { MessageCircle } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { useVendorQuery } from "@/hooks/use-vendor-api";
import type { Earnings, VendorCustomer } from "@/lib/vendor-types";
import { phoneMasked, rupees } from "@/lib/money";

import { VendorEmpty, VendorError, VendorLoading } from "../../../-components/vendor-states";

function waLink(name: string | null, phone: string | null, dues: number): string {
  // Friendly Hindi reminder — pre-filled, vendor sends from their own WhatsApp.
  const msg = encodeURIComponent(
    `Namaste ${name ?? "ji"} 🙏\nShodasha se reminder: aapke paas ₹${(dues / 100).toFixed(0)} ka bhugtan baaki hai. Kripya aaj hi UPI kar dein ya delivery par cash de dein.\nDhanyavaad!`,
  );
  const digits = (phone ?? "").replace(/\D/g, "").slice(-10);
  return `https://wa.me/91${digits}?text=${msg}`;
}

/**
 * Own collections + dues follow-up. Links are wa.me deep-links only (no
 * WhatsApp provider). No write-off affordance — that stays admin-only.
 */
export function Collections() {
  const { data: earnings } = useVendorQuery<Earnings>("/v1/vendor/earnings");
  const { data, isError, error, refetch } = useVendorQuery<{ customers: VendorCustomer[] }>("/v1/vendor/customers");

  if (isError) return <VendorError error={error} onRetry={() => void refetch()} />;
  if (!data) return <VendorLoading />;
  const rows = (data.customers ?? []).filter((c) => (c.dues ?? 0) > 0);
  const total = rows.reduce((a, r) => a + (r.dues ?? 0), 0);
  if (!rows.length) {
    return <VendorEmpty title="Koi baaki nahi" hint="Sab customers ka bhugtan poora hai. 🎉" />;
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-lg">Collections</CardTitle>
        <CardDescription>
          {`${rows.length} customers · ${rupees(total)} baaki`}
          {earnings ? ` · aaj jama cash ${rupees(earnings.cash_total)} + UPI ${rupees(earnings.upi_total)}` : ""}
        </CardDescription>
      </CardHeader>
      <CardContent className="px-0 pb-2">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Customer</TableHead>
              <TableHead>Dues</TableHead>
              <TableHead className="text-right">Remind</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.map((r) => (
              <TableRow key={r.customer_id || r.customer_name}>
                <TableCell>
                  <div className="flex flex-col">
                    <span className="font-medium text-sm">{r.customer_name}</span>
                    <span className="text-muted-foreground text-xs">{phoneMasked(r.customer_phone)}</span>
                  </div>
                </TableCell>
                <TableCell className="font-medium text-sm tabular-nums">{rupees(r.dues)}</TableCell>
                <TableCell className="text-right">
                  <Button
                    size="sm"
                    variant="outline"
                    render={
                      <a
                        href={waLink(r.customer_name, r.customer_phone, r.dues)}
                        target="_blank"
                        rel="noreferrer"
                      />
                    }
                  >
                    <MessageCircle aria-hidden /> WhatsApp
                  </Button>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  );
}
