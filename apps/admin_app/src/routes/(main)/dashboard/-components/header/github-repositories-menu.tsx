import { MessageCircle } from "lucide-react";

import { Button } from "@/components/ui/button";

export function WhatsAppAdminButton() {
  return (
    <Button
      variant="outline"
      size="sm"
      className="hidden sm:inline-flex items-center gap-1.5 h-8 text-xs border-emerald-500/40 text-emerald-600 dark:text-emerald-400 bg-emerald-50/50 dark:bg-emerald-950/20 hover:bg-emerald-100/50"
      render={
        <a
          href="https://wa.me/917828442476"
          target="_blank"
          rel="noreferrer"
          aria-label="Contact Admin on WhatsApp"
        />
      }
    >
      <MessageCircle className="size-3.5" />
      <span>WhatsApp Help</span>
    </Button>
  );
}

export const GitHubRepositoriesMenu = WhatsAppAdminButton;
