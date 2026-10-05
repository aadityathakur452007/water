import { createFileRoute } from "@tanstack/react-router";

import { VendorLoginForm } from "./-components/vendor-login-form";

export const Route = createFileRoute("/(main)/vendor/login/")({
  component: VendorLogin,
});

function VendorLogin() {
  return (
    <div className="flex h-dvh">
      <div className="hidden bg-primary lg:block lg:w-1/3">
        <div className="flex h-full flex-col items-center justify-center p-12 text-center">
          <div className="space-y-6">
            <h1 className="font-light text-5xl text-primary-foreground">Shodasha</h1>
            <div className="space-y-2">
              <p className="text-primary-foreground/80 text-xl">Vendor</p>
            </div>
          </div>
        </div>
      </div>

      <div className="flex w-full items-center justify-center bg-background p-8 lg:w-2/3">
        <div className="w-full max-w-md space-y-10 py-24 lg:py-32">
          <div className="space-y-4 text-center">
            <div className="font-medium tracking-tight">Vendor sign-in</div>
            <div className="mx-auto max-w-xl text-muted-foreground">
              Phone number + admin-issued access code se sign in karein.
            </div>
          </div>
          <div className="space-y-4">
            <VendorLoginForm />
          </div>
        </div>
      </div>
    </div>
  );
}
