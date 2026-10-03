import {
  BadgeIndianRupee,
  ChartBarBig,
  ClipboardList,
  Layers,
  type LucideIcon,
  ScrollText,
  Settings2,
  ShieldHalf,
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
 * Shodasha admin nav — only the surfaces the water-delivery operations need
 * (spec §2: everything else removed). Trust badge count is wired live in
 * nav-main via GET /v1/admin/metrics (quality_open).
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
        id: "orders",
        title: "Orders",
        url: "/dashboard/orders",
        icon: ClipboardList,
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
    id: 2,
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
    id: 3,
    label: "Operate",
    items: [
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
