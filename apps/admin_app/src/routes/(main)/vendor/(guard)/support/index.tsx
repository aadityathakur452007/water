import { createFileRoute } from "@tanstack/react-router";
import { MessageCircle } from "lucide-react";

import { Card, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

import { QualityCheck } from "./-components/quality-check";
import { SupportQueue } from "./-components/support-queue";

export const Route = createFileRoute("/(main)/vendor/(guard)/support/")({
  component: Page,
});

function Page() {
  return (
    <div className="flex flex-col gap-4">
      <Card className="border-emerald-500/40 bg-emerald-50/60 dark:bg-emerald-950/20">
        <CardHeader className="py-3 px-4">
          <CardTitle className="text-sm font-semibold flex items-center gap-2 text-emerald-800 dark:text-emerald-300">
            <MessageCircle className="size-4 text-emerald-600 dark:text-emerald-400" />
            Admin Sahayata (WhatsApp Support)
          </CardTitle>
          <CardDescription className="text-xs text-muted-foreground pt-0.5">
            Kisi bhi samasya ya sahayata ke liye Admin se WhatsApp par sampark karein:{" "}
            <a
              href="https://wa.me/917828442476"
              target="_blank"
              rel="noreferrer"
              className="font-medium text-emerald-600 dark:text-emerald-400 underline underline-offset-2 hover:opacity-80"
            >
              +91 7828442476
            </a>
          </CardDescription>
        </CardHeader>
      </Card>
      <SupportQueue />
      <QualityCheck />
    </div>
  );
}
