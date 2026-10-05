export type UserStatus = "Active" | "Suspended" | "Restricted" | "Pending KYC" | "Deactivated";

/** Adapter view over the worker's UserRow — every field is server-sourced
 * (invented Team/workspace/lastActive removed: the worker has no such data). */
export type UserRow = {
  id: string;
  email: string;
  joinedDate: string;
  name: string;
  phone: string | null;
  role: string;
  status: UserStatus;
};

export const filters = {
  role: ["All", "Customer", "Delivery Partner", "Admin"],
  status: ["All", "Active", "Suspended", "Restricted", "Pending KYC", "Deactivated"],
};

export const statusMeta: Record<UserStatus, { badgeClass: string; dotClass: string }> = {
  Active: {
    badgeClass: "border-emerald-500/20 bg-emerald-500/10 text-emerald-600 dark:text-emerald-400",
    dotClass: "bg-emerald-500",
  },
  "Pending KYC": {
    badgeClass: "border-amber-500/20 bg-amber-500/10 text-amber-600 dark:text-amber-400",
    dotClass: "bg-amber-500",
  },
  Restricted: {
    badgeClass: "border-orange-500/20 bg-orange-500/10 text-orange-600 dark:text-orange-400",
    dotClass: "bg-orange-500",
  },
  Deactivated: {
    badgeClass: "border-border bg-muted/50 text-muted-foreground",
    dotClass: "bg-muted-foreground",
  },
  Suspended: {
    badgeClass: "border-destructive/20 bg-destructive/10 text-destructive",
    dotClass: "bg-destructive",
  },
};
