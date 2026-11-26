import { Check, Copy, ExternalLink, KeyRound, ShieldCheck } from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";

type AddVendorSuccessProps = {
  name: string;
  phone: string;
  code: string;
  copied: boolean;
  whatsAppUrl: string;
  onCopy: () => void;
  onDone: () => void;
};

export function AddVendorSuccess({ name, phone, code, copied, whatsAppUrl, onCopy, onDone }: AddVendorSuccessProps) {
  return (
    <div className="flex flex-col gap-4 py-2">
      <DialogHeader>
        <DialogTitle className="flex items-center gap-2 text-emerald-600 dark:text-emerald-400">
          <ShieldCheck className="size-5" />
          Vendor Successfully Registered
        </DialogTitle>
        <DialogDescription>
          {name} (+91 {phone}) is verified and ready to sign in.
        </DialogDescription>
      </DialogHeader>

      <div className="rounded-xl border bg-muted/30 p-4">
        <div className="flex items-center justify-between">
          <div className="font-semibold text-muted-foreground text-xs uppercase tracking-wider">
            One-Time Access Code
          </div>
          <Badge variant="outline" className="border-emerald-500/30 text-emerald-600 dark:text-emerald-400">
            Valid 90 Days
          </Badge>
        </div>

        <div className="mt-3 flex items-center justify-between gap-3 rounded-lg border bg-background p-3 font-bold font-mono text-xl tracking-widest">
          <span className="flex select-all items-center gap-2">
            <KeyRound className="size-5 text-muted-foreground" />
            {code}
          </span>
          <Button size="sm" variant="ghost" onClick={onCopy} className="size-8 p-0">
            {copied ? <Check className="size-4 text-emerald-500" /> : <Copy className="size-4" />}
          </Button>
        </div>
        <p className="mt-2 text-muted-foreground text-xs">
          This plaintext code is only displayed once. Please share it with the partner immediately.
        </p>
      </div>

      <div className="flex flex-col gap-2">
        <a
          href={whatsAppUrl}
          target="_blank"
          rel="noreferrer"
          className="inline-flex w-full items-center justify-center gap-2 rounded-lg bg-emerald-600 py-2.5 font-medium text-sm text-white transition hover:bg-emerald-700"
        >
          <ExternalLink className="size-4" />
          Send Credentials via WhatsApp
        </a>

        <Button variant="outline" onClick={onDone} className="w-full">
          Done
        </Button>
      </div>
    </div>
  );
}
