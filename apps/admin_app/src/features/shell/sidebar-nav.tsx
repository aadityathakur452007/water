"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { clsx } from "clsx";
import {
  BadgeIndianRupee,
  ChartBarBig,
  ClipboardList,
  Layers,
  ReceiptText,
  ScrollText,
  Settings2,
  ShieldHalf,
  Truck,
  Users,
  Wallet,
  X,
} from "lucide-react";
import { useQuery } from "@tanstack/react-query";

type NavItem = { href: string; label: string; icon: typeof ChartBarBig; badgeKey?: "trust" };

const NAV: Array<{ section: string; items: NavItem[] }> = [
  {
    section: "Monitor",
    items: [
      { href: "/admin", label: "Overview", icon: ChartBarBig },
      { href: "/admin/orders", label: "Orders", icon: ClipboardList },
      { href: "/admin/payments", label: "Payments", icon: Wallet },
      { href: "/admin/ledger", label: "Jar ledger", icon: Layers },
    ],
  },
  {
    section: "People",
    items: [
      { href: "/admin/users", label: "Users", icon: Users },
      { href: "/admin/vendors", label: "Vendors", icon: Truck },
      { href: "/admin/trust", label: "Trust", icon: ShieldHalf, badgeKey: "trust" },
    ],
  },
  {
    section: "Operate",
    items: [
      { href: "/admin/operations", label: "Operations", icon: BadgeIndianRupee },
      { href: "/admin/audit", label: "Audit log", icon: ScrollText },
      { href: "/admin/config", label: "Config", icon: Settings2 },
    ],
  },
];

async function fetchTrustCount(): Promise<number> {
  const res = await fetch("/api/proxy?url=" + encodeURIComponent("/v1/admin/metrics"));
  if (!res.ok) return 0;
  const body = (await res.json()) as { quality_open?: number };
  return body.quality_open ?? 0;
}

export function SidebarNav({ onNavigate }: { onNavigate?: () => void }) {
  const pathname = usePathname();
  const { data: trustCount } = useQuery({
    queryKey: ["trust-count"],
    queryFn: fetchTrustCount,
    staleTime: 30_000,
    refetchInterval: 60_000,
  });

  const isActive = (href: string) =>
    href === "/admin" ? pathname === "/admin" : pathname.startsWith(href);

  return (
    <nav className="flex h-full flex-col gap-6 overflow-y-auto px-3 pb-6" aria-label="Admin">
      {NAV.map((group) => (
        <div key={group.section}>
          <p className="px-3 pb-1.5 text-[10px] font-semibold uppercase tracking-widest text-faint">
            {group.section}
          </p>
          <ul className="space-y-0.5">
            {group.items.map((item) => {
              const active = isActive(item.href);
              const Icon = item.icon;
              const badge =
                item.badgeKey === "trust" && trustCount ? (
                  <span className="tnum ml-auto rounded-full bg-bad-soft px-1.5 text-[10px] font-semibold text-bad">
                    {trustCount}
                  </span>
                ) : null;
              return (
                <li key={item.href}>
                  <Link
                    href={item.href}
                    onClick={onNavigate}
                    aria-current={active ? "page" : undefined}
                    className={clsx(
                      "group flex h-9 items-center gap-2.5 rounded-lg px-3 text-sm transition-colors",
                      active
                        ? "bg-accent-soft font-medium text-accent"
                        : "text-steel hover:bg-canvas hover:text-ink",
                    )}
                  >
                    <Icon
                      className={clsx("size-4", active ? "text-accent" : "text-faint group-hover:text-steel")}
                      aria-hidden
                    />
                    {item.label}
                    {badge}
                  </Link>
                </li>
              );
            })}
          </ul>
        </div>
      ))}
      <div className="mt-auto px-3 pt-2">
        <p className="flex items-center gap-1.5 text-[10px] text-faint">
          <ReceiptText className="size-3" aria-hidden />
          Shodasha Mineral Waters
        </p>
      </div>
    </nav>
  );
}

export function MobileNavToggle({ open, onClose }: { open: boolean; onClose: () => void }) {
  if (!open) return null;
  return (
    <div className="fixed inset-0 z-40 lg:hidden" role="dialog" aria-modal="true" aria-label="Navigation">
      <button
        type="button"
        aria-label="Close navigation"
        onClick={onClose}
        className="absolute inset-0 bg-ink/20"
      />
      <div className="absolute inset-y-0 left-0 w-64 border-r border-line bg-surface p-4 shadow-card">
        <div className="mb-4 flex items-center justify-between px-2">
          <span className="text-sm font-semibold text-ink">Menu</span>
          <button
            type="button"
            onClick={onClose}
            className="flex size-8 items-center justify-center rounded-lg text-steel hover:bg-canvas"
            aria-label="Close"
          >
            <X className="size-4" aria-hidden />
          </button>
        </div>
        <SidebarNav onNavigate={onClose} />
      </div>
    </div>
  );
}
