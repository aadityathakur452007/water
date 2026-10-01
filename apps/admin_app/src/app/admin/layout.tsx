import { AdminChrome } from "@/features/shell/admin-chrome";

export default function AdminLayout({ children }: { children: React.ReactNode }) {
  return <AdminChrome>{children}</AdminChrome>;
}
