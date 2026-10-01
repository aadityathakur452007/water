"use client";

import { use } from "react";
import { UserDetailPanel } from "@/features/users/user-detail";

export default function UserDetailPage({ params }: { params: Promise<{ userId: string }> }) {
  const { userId } = use(params);
  return <UserDetailPanel userId={userId} />;
}
