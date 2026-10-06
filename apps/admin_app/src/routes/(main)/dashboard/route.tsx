import type { CSSProperties } from "react";

import { createFileRoute, Outlet, redirect } from "@tanstack/react-router";

import { cn } from "cn";

import { Separator } from "@/components/ui/separator";
import { SidebarInset, SidebarProvider, SidebarTrigger } from "@/components/ui/sidebar";
import { users } from "@/data/users";
import { adminRoleServer } from "@/server/admin-api";
import { hasSessionServer, refreshSessionServer, storeRotatedSessionServer } from "@/server/admin-session";
import { getDashboardLayout } from "@/server/server-actions";

import { AccountSwitcher } from "./-components/header/account-switcher";
import { GitHubRepositoriesMenu } from "./-components/header/github-repositories-menu";
import { LayoutControls } from "./-components/header/layout-controls";
import { SearchDialog } from "./-components/header/search-dialog";
import { ThemeSwitcher } from "./-components/header/theme-switcher";
import { AppSidebar } from "./-components/sidebar/app-sidebar";

/**
 * Dashboard shell — template layout VERBATIM, plus one addition: the admin
 * session gate. No valid sh_session cookie → bounce to sign-in with a `next`
 * param (server-side check in the loader; the worker re-checks the role on
 * every API call — the UI is never the security gate). A non-admin cookie
 * (e.g. vendor) bounces to sign-in with `reason=denied` before any admin
 * chrome renders.
 */
export const Route = createFileRoute("/(main)/dashboard")({
  loader: async () => {
    const { authed } = await hasSessionServer();
    if (!authed) {
      // Session cookie expired but the 7-day refresh cookie may live:
      // silently renew once before bouncing to sign-in, so desktops keep
      // their login across the 30-minute access TTL.
      const pair = await refreshSessionServer();
      if (pair) {
        await storeRotatedSessionServer({ data: pair });
      } else {
        throw redirect({ to: "/auth/v1/login", search: { next: "/dashboard" }, replace: true });
      }
    }
    const me = await adminRoleServer();
    if (!me || me.role !== "admin") {
      throw redirect({
        to: "/auth/v1/login",
        search: { next: "/dashboard", reason: "denied" },
        replace: true,
      });
    }
    return getDashboardLayout();
  },
  component: DashboardLayout,
});

function DashboardLayout() {
  const { defaultOpen, variant, collapsible } = Route.useLoaderData();

  return (
    <SidebarProvider
      defaultOpen={defaultOpen}
      style={
        {
          "--sidebar-width": "calc(var(--spacing) * 68)",
        } as CSSProperties
      }
    >
      <AppSidebar variant={variant} collapsible={collapsible} />
      <SidebarInset
        className={cn(
          "[html[data-content-layout=centered]_&>*]:mx-auto",
          "[html[data-content-layout=centered]_&>*]:w-full",
          "[html[data-content-layout=centered]_&>*]:max-w-screen-2xl",
          "peer-data-[variant=inset]:border",
          "[--dashboard-header-height:--spacing(12)]",
          "min-w-0 overflow-x-clip",
        )}
      >
        <header
          className={cn(
            "flex h-12 shrink-0 items-center gap-2 border-b transition-[width,height] ease-linear group-has-data-[collapsible=icon]/sidebar-wrapper:h-12",
            // Handle sticky navbar style with conditional classes so blur, background, z-index, and rounded corners remain consistent across all SidebarVariant layouts.
            "[html[data-navbar-style=sticky]_&]:sticky [html[data-navbar-style=sticky]_&]:top-0 [html[data-navbar-style=sticky]_&]:z-50 [html[data-navbar-style=sticky]_&]:overflow-hidden [html[data-navbar-style=sticky]_&]:rounded-t-[inherit] [html[data-navbar-style=sticky]_&]:bg-background/50 [html[data-navbar-style=sticky]_&]:backdrop-blur-md",
          )}
        >
          <div className="flex w-full items-center justify-between px-4 lg:px-6">
            <div className="flex items-center gap-1 lg:gap-2">
              <SidebarTrigger className="-ml-1" />
              <Separator
                orientation="vertical"
                className="mx-2 data-[orientation=vertical]:h-4 data-[orientation=vertical]:self-center"
              />
              <SearchDialog />
            </div>
            <div className="flex items-center gap-2">
              <LayoutControls />
              <ThemeSwitcher />
              <GitHubRepositoriesMenu />
              <AccountSwitcher users={users} />
            </div>
          </div>
        </header>
        {/* Pages can set data-content-padding="false" to render full-bleed app layouts. */}
        <div className="min-h-0 min-w-0 flex-1 overflow-x-hidden p-4 has-data-[content-padding=false]:p-0 md:p-6 md:has-data-[content-padding=false]:p-0">
          <Outlet />
        </div>
      </SidebarInset>
    </SidebarProvider>
  );
}
