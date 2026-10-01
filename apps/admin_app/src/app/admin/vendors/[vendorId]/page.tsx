"use client";

import { use } from "react";
import { VendorDetailPanel } from "@/features/vendors/vendor-detail";

export default function VendorDetailPage({ params }: { params: Promise<{ vendorId: string }> }) {
  const { vendorId } = use(params);
  return <VendorDetailPanel vendorId={vendorId} />;
}
