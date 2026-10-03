import {
  BadgeIndianRupee,
  Banknote,
  ChartBarBig,
  ClipboardList,
  Layers,
  type LucideIcon,
  Route,
  ScrollText,
  Settings2,
  ShieldHalf,
  TrendingUp,
  Truck,
  Users,
  Wallet,
} from "lucide-react";

import type { FileRoutesByTo } from "@/routeTree.gen";

export type NavBadge = "new" | "soon";
export type AppPath = keyof FileRoutesByTo;

export interface NavSubItem {
  id: string;
  title: string;
  url: AppPath;
  icon?: LucideIcon;
  badge?: NavBadge;
  disabled?: boolean;
  newTab?: boolean;
}

interface NavItemBase {
  id: string;
  title: string;
  icon?: LucideIcon;
  badge?: NavBadge;
  disabled?: boolean;
  newTab?: boolean;
}

export interface NavMainLinkItem extends NavItemBase {
  url: AppPath;
  subItems?: never;
}

export interface NavMainParentItem extends NavItemBase {
  subItems: NavSubItem[];
}

export type NavMainItem = NavMainLinkItem | NavMainParentItem;

export interface NavGroup {
  id: number;
  label?: string;
  items: NavMainItem[];
}

/**
 * Shodasha admin nav — grouped by the admin's mental model (roadmap round 2):
 * Monitor = what's happening · Money = what's owed · People = who serves ·
 * Operate = how it runs. Trust badge count is wired live in nav-main via
 * GET /v1/admin/metrics (quality_open).
 */
export const sidebarItems: NavGroup[] = [
  {
    id: 1,
    label: "Monitor",
    items: [
      {
        id: "overview",
        title: "Overview",
        url: "/dashboard",
        icon: ChartBarBig,
      },
      {
        id: "analytics",
        title: "Analytics",
        url: "/dashboard/analytics",
        icon: TrendingUp,
        badge: "new",
      },
      {
        id: "orders",
        title: "Orders",
        url: "/dashboard/orders",
        icon: ClipboardList,
      },
    ],
  },
  {
    id: 2,
    label: "Money",
    items: [
      {
        id: "finance",
        title: "Finance",
        url: "/dashboard/finance",
        icon: Banknote,
        badge: "new",
      },
      {
        id: "payments",
        title: "Payments",
        url: "/dashboard/payments",
        icon: Wallet,
      },
      {
        id: "ledger",
        title: "Jar ledger",
        url: "/dashboard/ledger",
        icon: Layers,
      },
    ],
  },
  {
    id: 3,
    label: "People",
    items: [
      {
        id: "users",
        title: "Users",
        url: "/dashboard/users",
        icon: Users,
      },
      {
        id: "vendors",
        title: "Vendors",
        url: "/dashboard/vendors",
        icon: Truck,
      },
      {
        id: "trust",
        title: "Trust",
        url: "/dashboard/trust",
        icon: ShieldHalf,
      },
    ],
  },
  {
    id: 4,
    label: "Operate",
    items: [
      {
        id: "dispatch",
        title: "Dispatch",
        url: "/dashboard/dispatch",
        icon: Route,
        badge: "new",
      },
      {
        id: "operations",
        title: "Operations",
        url: "/dashboard/operations",
        icon: BadgeIndianRupee,
      },
      {
        id: "audit",
        title: "Audit log",
        url: "/dashboard/audit",
        icon: ScrollText,
      },
      {
        id: "config",
        title: "Config",
        url: "/dashboard/config",
        icon: Settings2,
      },
    ],
  },
];
