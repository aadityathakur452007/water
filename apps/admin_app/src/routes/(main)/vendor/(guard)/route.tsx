import { createFileRoute, Link, Outlet, redirect, useRouterState } from "@tanstack/react-router";

import { cn } from "cn";

import { storeRotatedSessionServer } from "@/server/admin-session";
import { hasVendorSessionServer, refreshVendorSessionServer } from "@/server/vendor-session";

const NAV = [
  { to: "/vendor", label: "Overview" },
  { to: "/vendor/route", label: "Route" },
  { to: "/vendor/collections", label: "Collections" },
  { to: "/vendor/payouts", label: "Payouts" },
  { to: "/vendor/deposits", label: "Deposits" },
  { to: "/vendor/support", label: "Support" },
  { to: "/vendor/profile", label: "Profile" },
] as const;

/**
 * Vendor guard shell — server-side session gate (mirrors the dashboard
 * guard: cookie → silent refresh once → else bounce to /vendor/login) plus
 * a minimal vendor header nav. Lives in a pathless (guard) group so the
 * public /vendor/login page stays outside it (else the guard would bounce
 * the login page to itself). Deliberately NOT the admin sidebar: vendors
 * never see /dashboard/* links.
 */
export const Route = createFileRoute("/(main)/vendor/(guard)")({
  loader: async () => {
    const { authed } = await hasVendorSessionServer();
    if (!authed) {
      const pair = await refreshVendorSessionServer();
      if (pair) {
        await storeRotatedSessionServer({ data: pair });
      } else {
        throw redirect({ to: "/vendor/login", replace: true });
      }
    }
    return null;
  },
  component: VendorLayout,
});

function VendorLayout() {
  const pathname = useRouterState({ select: (s) => s.location.pathname });
  return (
    <div className="mx-auto flex w-full max-w-screen-md flex-col gap-4 p-4 md:p-6">
      <header className="flex flex-col gap-2">
        <p className="font-medium text-lg leading-none">Shodasha Vendor</p>
        <nav aria-label="Vendor sections" className="flex gap-1 overflow-x-auto border-b pb-1">
          {NAV.map((item) => {
            const active =
              item.to === "/vendor" ? pathname === "/vendor" || pathname === "/vendor/" : pathname.startsWith(item.to);
            return (
              <Link
                key={item.to}
                to={item.to}
                className={cn(
                  "shrink-0 rounded-md px-3 py-2 text-sm",
                  "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring",
                  active ? "bg-muted font-medium text-foreground" : "text-muted-foreground hover:text-foreground",
                )}
                aria-current={active ? "page" : undefined}
              >
                {item.label}
              </Link>
            );
          })}
        </nav>
      </header>
      <Outlet />
    </div>
  );
}
