"use client";

import { use } from "react";
import { OrderDetail } from "@/features/orders/order-detail";

export default function OrderDetailPage({
  params,
}: {
  params: Promise<{ orderId: string }>;
}) {
  const { orderId } = use(params);
  return <OrderDetail orderId={orderId} />;
}
