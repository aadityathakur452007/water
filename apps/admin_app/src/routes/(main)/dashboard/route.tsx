import type { CSSProperties } from "react";

import { createFileRoute, Outlet, redirect } from "@tanstack/react-router";

import { cn } from "cn";

import { Separator } from "@/components/ui/separator";
import { SidebarInset, SidebarProvider, SidebarTrigger } from "@/components/ui/sidebar";
import { adminMeServer, adminRoleServer } from "@/server/admin-api";
import { hasSessionServer, refreshSessionServer, storeRotatedSessionServer } from "@/server/admin-session";
import { getDashboardLayout } from "@/server/server-actions";

import { AccountSwitcher } from "./-components/header/account-switcher";
import { WhatsAppAdminButton } from "./-components/header/github-repositories-menu";
import { LayoutControls } from "./-components/header/layout-controls";
import { SearchDialog } from "./-components/header/search-dialog";
import { ThemeSwitcher } from "./-components/header/theme-switcher";
import { AppSidebar } from "./-components/sidebar/app-sidebar";

/**
 * Dashboard shell with live admin session gate:
 * - Server-side cookie check with auto-refresh on expired session
 * - Asserts role=admin against worker
 * - Passes real authenticated admin profile to layout and sidebar
 */
export const Route = createFileRoute("/(main)/dashboard")({
  loader: async () => {
    const { authed } = await hasSessionServer();
    if (!authed) {
      const pair = await refreshSessionServer();
      if (pair) {
        await storeRotatedSessionServer({ data: pair });
      } else {
        throw redirect({ to: "/auth/v1/login", search: { next: "/dashboard" }, replace: true });
      }
    }
    const me = await adminMeServer();
    if (!me || me.role !== "admin") {
      throw redirect({
        to: "/auth/v1/login",
        search: { next: "/dashboard", reason: "denied" },
        replace: true,
      });
    }
    const layout = await getDashboardLayout();
    return { ...layout, user: me };
  },
  component: DashboardLayout,
});

function DashboardLayout() {
  const { defaultOpen, variant, collapsible, user } = Route.useLoaderData();

  return (
    <SidebarProvider
      defaultOpen={defaultOpen}
      style={
        {
          "--sidebar-width": "calc(var(--spacing) * 68)",
        } as CSSProperties
      }
    >
      <AppSidebar currentUser={user} variant={variant} collapsible={collapsible} />
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
              <WhatsAppAdminButton />
              <AccountSwitcher user={user} />
            </div>
          </div>
        </header>
        <div className="min-h-0 min-w-0 flex-1 overflow-x-hidden p-4 has-data-[content-padding=false]:p-0 md:p-6 md:has-data-[content-padding=false]:p-0">
          <Outlet />
        </div>
      </SidebarInset>
    </SidebarProvider>
  );
}
