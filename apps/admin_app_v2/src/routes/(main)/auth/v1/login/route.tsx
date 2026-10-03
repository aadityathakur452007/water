import { createFileRoute } from "@tanstack/react-router";

import { AdminLoginForm } from "../../-components/admin-login-form";

type LoginSearch = { next?: string };

export const Route = createFileRoute("/(main)/auth/v1/login")({
  validateSearch: (search: Record<string, unknown>): LoginSearch => ({
    next: typeof search.next === "string" ? search.next : undefined,
  }),
  component: LoginV1,
});

function LoginV1() {
  return (
    <div className="flex h-dvh">
      <div className="hidden bg-primary lg:block lg:w-1/3">
        <div className="flex h-full flex-col items-center justify-center p-12 text-center">
          <div className="space-y-6">
            <h1 className="font-light text-5xl text-primary-foreground">Shodasha</h1>
            <div className="space-y-2">
              <p className="text-primary-foreground/80 text-xl">Super Admin</p>
            </div>
          </div>
        </div>
      </div>

      <div className="flex w-full items-center justify-center bg-background p-8 lg:w-2/3">
        <div className="w-full max-w-md space-y-10 py-24 lg:py-32">
          <div className="space-y-4 text-center">
            <div className="font-medium tracking-tight">Admin sign-in</div>
            <div className="mx-auto max-w-xl text-muted-foreground">
              Sign in with the admin phone number to manage orders, users, vendors and money.
            </div>
          </div>
          <div className="space-y-4">
            <AdminLoginForm />
          </div>
        </div>
      </div>
    </div>
  );
}
