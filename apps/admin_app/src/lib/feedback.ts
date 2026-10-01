"use client";

import { toast } from "sonner";

type ActionJson = { error?: { message?: string }; revoked_sessions?: number };

/**
 * Success toast for admin actions, carrying facts from the worker's response
 * (e.g. "Blocked · 3 sessions revoked"). Errors are NOT toasted here — surfaces
 * show them inline next to the control that triggered the action.
 */
export function toastActionSuccess(label: string, json: ActionJson | null) {
  const revoked = json?.revoked_sessions ?? 0;
  toast.success(
    label,
    revoked > 0
      ? { description: `${revoked} session${revoked === 1 ? "" : "s"} revoked` }
      : undefined,
  );
}
