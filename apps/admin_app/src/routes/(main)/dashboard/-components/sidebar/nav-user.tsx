import { useNavigate } from "@tanstack/react-router";
import { EllipsisVertical, LogOut, MessageCircle } from "lucide-react";

import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { SidebarMenu, SidebarMenuButton, SidebarMenuItem, useSidebar } from "@/components/ui/sidebar";
import { getInitials } from "@/lib/utils";
import type { CurrentAdminUser } from "@/server/admin-api";
import { logoutServer } from "@/server/admin-session";

export function NavUser({
  user,
}: {
  readonly user: CurrentAdminUser;
}) {
  const { isMobile } = useSidebar();
  const navigate = useNavigate();

  async function logout() {
    await logoutServer();
    await navigate({ to: "/auth/v1/login", replace: true });
  }

  const displayName = user.name || "Admin";
  const displayPhone = user.phone ? (user.phone.startsWith("+91") ? user.phone : `+91 ${user.phone}`) : "";

  return (
    <SidebarMenu>
      <SidebarMenuItem>
        <DropdownMenu>
          <DropdownMenuTrigger
            render={
              <SidebarMenuButton
                size="lg"
                className="data-popup-open:bg-sidebar-accent data-popup-open:text-sidebar-accent-foreground cursor-pointer"
              />
            }
          >
            <Avatar className="h-8 w-8 rounded-lg">
              <AvatarImage src={user.avatar || undefined} alt={displayName} />
              <AvatarFallback className="rounded-lg">{getInitials(displayName)}</AvatarFallback>
            </Avatar>
            <div className="grid flex-1 text-left text-sm leading-tight">
              <span className="truncate font-medium">{displayName}</span>
              <span className="truncate text-muted-foreground text-xs">{displayPhone}</span>
            </div>
            <EllipsisVertical className="ml-auto size-4" />
          </DropdownMenuTrigger>
          <DropdownMenuContent
            className="w-(--anchor-width) min-w-56 rounded-lg"
            side={isMobile ? "bottom" : "right"}
            align="end"
            sideOffset={4}
          >
            <div className="flex items-center gap-2 px-2 py-1.5 text-left text-sm">
              <Avatar className="h-8 w-8 rounded-lg">
                <AvatarImage src={user.avatar || undefined} alt={displayName} />
                <AvatarFallback className="rounded-lg">{getInitials(displayName)}</AvatarFallback>
              </Avatar>
              <div className="grid flex-1 text-left text-sm leading-tight">
                <span className="truncate font-medium">{displayName}</span>
                <span className="truncate text-muted-foreground text-xs">{displayPhone}</span>
              </div>
              <Badge variant="outline" className="text-[10px] uppercase font-mono px-1.5 py-0">
                {user.role}
              </Badge>
            </div>
            <DropdownMenuSeparator />
            <DropdownMenuGroup>
              <DropdownMenuItem
                render={
                  <a
                    href="https://wa.me/917828442476"
                    target="_blank"
                    rel="noreferrer"
                    className="flex w-full items-center gap-2 cursor-pointer"
                  />
                }
              >
                <MessageCircle className="size-4 text-emerald-600" />
                <span>Admin WhatsApp</span>
              </DropdownMenuItem>
            </DropdownMenuGroup>
            <DropdownMenuSeparator />
            <DropdownMenuItem
              className="text-destructive focus:text-destructive cursor-pointer"
              onClick={() => void logout()}
            >
              <LogOut className="size-4" />
              <span>Log out</span>
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </SidebarMenuItem>
    </SidebarMenu>
  );
}
