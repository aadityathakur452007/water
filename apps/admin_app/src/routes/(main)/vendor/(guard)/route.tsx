import { createFileRoute, Link, Outlet, redirect, useRouter, useRouterState } from "@tanstack/react-router";
import { LogOut, MessageCircle } from "lucide-react";

import { cn } from "cn";

import { Button } from "@/components/ui/button";
import { hasVendorSessionServer, logoutVendorServer, refreshVendorSessionServer } from "@/server/vendor-session";

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
 * Vendor guard shell — server-side session gate (cookie → silent refresh once → else bounce to /vendor/login)
 * with dedicated namespaced vendor session and header nav.
 */
export const Route = createFileRoute("/(main)/vendor/(guard)")({
  loader: async () => {
    const { authed } = await hasVendorSessionServer();
    if (!authed) {
      const pair = await refreshVendorSessionServer();
      if (!pair) {
        throw redirect({ to: "/vendor/login", replace: true });
      }
    }
    return null;
  },
  component: VendorLayout,
});

function VendorLayout() {
  const pathname = useRouterState({ select: (s) => s.location.pathname });
  const router = useRouter();

  async function handleLogout() {
    await logoutVendorServer();
    await router.navigate({ to: "/vendor/login", replace: true });
  }

  return (
    <div className="mx-auto flex w-full max-w-screen-md flex-col gap-4 p-4 md:p-6">
      <header className="flex flex-col gap-2">
        <div className="flex items-center justify-between">
          <p className="font-semibold text-lg leading-none">Shodasha Vendor</p>
          <div className="flex items-center gap-2">
            <a
              href="https://wa.me/917828442476"
              target="_blank"
              rel="noreferrer"
              className="inline-flex items-center gap-1.5 text-xs font-medium text-emerald-600 dark:text-emerald-400 bg-emerald-50 dark:bg-emerald-950/40 px-2.5 py-1 rounded-md border border-emerald-500/30 hover:opacity-85"
            >
              <MessageCircle className="size-3.5" />
              <span>Admin WhatsApp</span>
            </a>
            <Button
              variant="ghost"
              size="sm"
              onClick={() => void handleLogout()}
              className="h-7 px-2 text-xs text-muted-foreground hover:text-destructive"
            >
              <LogOut className="size-3.5 mr-1" />
              Logout
            </Button>
          </div>
        </div>
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
