"use client";

import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { LogOut, Menu, Droplets } from "lucide-react";
import { MobileNavToggle, SidebarNav } from "./sidebar-nav";

export function AdminChrome({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const [mobileOpen, setMobileOpen] = useState(false);

  async function signOut() {
    await fetch("/api/auth/logout", { method: "POST" });
    router.replace("/login");
  }

  return (
    <div className="flex min-h-[100dvh]">
      {/* Sidebar — desktop only; mobile uses the slide-over */}
      <aside className="fixed inset-y-0 left-0 z-30 hidden w-60 flex-col border-r border-line bg-surface lg:flex">
        <Link href="/admin" className="flex items-center gap-2.5 px-5 py-5">
          <span className="flex size-8 items-center justify-center rounded-lg bg-accent text-white">
            <Droplets className="size-4.5" aria-hidden />
          </span>
          <span>
            <span className="block text-sm font-semibold leading-4 tracking-tight text-ink">Shodasha</span>
            <span className="block text-[10px] font-medium uppercase tracking-widest text-steel">
              Super Admin
            </span>
          </span>
        </Link>
        <SidebarNav />
      </aside>

      <div className="flex min-w-0 flex-1 flex-col lg:pl-60">
        <header className="sticky top-0 z-20 flex h-14 items-center gap-3 border-b border-line bg-surface/90 px-4 backdrop-blur lg:px-8">
          <button
            type="button"
            onClick={() => setMobileOpen(true)}
            className="flex size-9 items-center justify-center rounded-lg border border-line text-steel hover:bg-canvas lg:hidden"
            aria-label="Open navigation"
          >
            <Menu className="size-4" aria-hidden />
          </button>
          <div className="ml-auto flex items-center gap-2">
            <span className="hidden rounded-full border border-line px-2.5 py-1 text-[11px] font-medium text-steel sm:inline">
              Cloudflare Pages · edge
            </span>
            <button
              type="button"
              onClick={signOut}
              className="inline-flex h-8 items-center gap-1.5 rounded-lg border border-line px-3 text-xs font-medium text-steel transition-colors hover:bg-canvas hover:text-ink"
            >
              <LogOut className="size-3.5" aria-hidden />
              Sign out
            </button>
          </div>
        </header>
        <main className="mx-auto w-full max-w-[1400px] flex-1 px-4 py-6 lg:px-8">{children}</main>
      </div>

      <MobileNavToggle open={mobileOpen} onClose={() => setMobileOpen(false)} />
    </div>
  );
}
