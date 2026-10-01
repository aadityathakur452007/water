import Link from "next/link";
import { Compass } from "lucide-react";

export default function NotFound() {
  return (
    <main className="flex min-h-[100dvh] flex-col items-center justify-center gap-3 bg-canvas px-4 text-center">
      <span className="flex size-12 items-center justify-center rounded-full bg-line-soft text-steel">
        <Compass className="size-5" aria-hidden />
      </span>
      <h1 className="text-lg font-semibold tracking-tight text-ink">This page does not exist</h1>
      <p className="max-w-sm text-sm text-steel">
        The panel only has the routes in the sidebar — the audit log shows every change ever made, if you were
        looking for history.
      </p>
      <Link
        href="/admin"
        className="mt-2 inline-flex h-10 items-center rounded-lg bg-accent px-4 text-sm font-medium text-white hover:bg-accent/90"
      >
        Back to Overview
      </Link>
    </main>
  );
}
