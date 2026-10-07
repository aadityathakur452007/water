import { MessageCircle } from "lucide-react";

import { Card, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

export function SupportCard() {
  return (
    <Card size="sm" className="overflow-hidden shadow-none group-data-[collapsible=icon]:hidden border-emerald-500/30 bg-emerald-50/50 dark:bg-emerald-950/20">
      <CardHeader className="min-w-0 px-4 py-3">
        <CardTitle className="truncate text-xs font-semibold flex items-center gap-1.5 text-emerald-800 dark:text-emerald-300">
          <MessageCircle className="size-3.5 text-emerald-600 dark:text-emerald-400" />
          <span>Need Help or Facing Issues?</span>
        </CardTitle>
        <CardDescription className="text-xs text-muted-foreground pt-1">
          Contact admin directly via WhatsApp:{" "}
          <a
            href="https://wa.me/917828442476"
            target="_blank"
            rel="noreferrer"
            className="font-medium text-emerald-600 dark:text-emerald-400 underline underline-offset-2 hover:opacity-80 inline-flex items-center gap-1"
          >
            +91 7828442476
          </a>
        </CardDescription>
      </CardHeader>
    </Card>
  );
}
