import { useNavigate } from "@tanstack/react-router";
import { LogOut, MessageCircle, ShieldCheck } from "lucide-react";

import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { getInitials } from "@/lib/utils";
import type { CurrentAdminUser } from "@/server/admin-api";
import { logoutServer } from "@/server/admin-session";

export function AccountSwitcher({
  user,
}: {
  readonly user: CurrentAdminUser;
}) {
  const navigate = useNavigate();

  async function logout() {
    await logoutServer();
    await navigate({ to: "/auth/v1/login", replace: true });
  }

  const displayName = user.name || "Admin";
  const displayPhone = user.phone ? (user.phone.startsWith("+91") ? user.phone : `+91 ${user.phone}`) : "";

  return (
    <DropdownMenu>
      <DropdownMenuTrigger nativeButton={false} render={<Avatar className="size-9 rounded-lg cursor-pointer" />}>
        <AvatarImage src={user.avatar || undefined} alt={displayName} />
        <AvatarFallback>{getInitials(displayName)}</AvatarFallback>
      </DropdownMenuTrigger>
      <DropdownMenuContent className="min-w-60 space-y-1 rounded-lg" side="bottom" align="end" sideOffset={4}>
        <DropdownMenuLabel className="p-0 font-normal">
          <div className="flex items-center gap-2 px-2 py-1.5 text-left text-sm">
            <Avatar className="size-8 rounded-lg">
              <AvatarImage src={user.avatar || undefined} alt={displayName} />
              <AvatarFallback className="rounded-lg">{getInitials(displayName)}</AvatarFallback>
            </Avatar>
            <div className="grid flex-1 text-left text-sm leading-tight">
              <span className="truncate font-semibold">{displayName}</span>
              <span className="truncate text-muted-foreground text-xs">{displayPhone}</span>
            </div>
            <Badge variant="outline" className="text-[10px] uppercase font-mono px-1.5 py-0">
              {user.role}
            </Badge>
          </div>
        </DropdownMenuLabel>
        <DropdownMenuSeparator />
        <DropdownMenuGroup>
          <DropdownMenuItem
            render={
              <a
                href="https://wa.me/917828442476"
                target="_blank"
                rel="noreferrer"
                className="flex w-full items-center gap-2"
              />
            }
          >
            <MessageCircle className="size-4 text-emerald-600" />
            <span>Admin WhatsApp Support</span>
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
  );
}
