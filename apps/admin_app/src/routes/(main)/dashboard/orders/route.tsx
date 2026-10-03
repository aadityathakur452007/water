import { createFileRoute, Outlet } from "@tanstack/react-router";

type OrdersSearch = { state?: string; payment_status?: string };

/**
 * Orders layout — validates deep-link search (?state=&payment_status= from
 * Overview KPIs) and renders either the list (index) or the detail child.
 */
export const Route = createFileRoute("/(main)/dashboard/orders")({
  validateSearch: (search: Record<string, unknown>): OrdersSearch => ({
    state: typeof search.state === "string" ? search.state : undefined,
    payment_status: typeof search.payment_status === "string" ? search.payment_status : undefined,
  }),
  component: () => <Outlet />,
});
