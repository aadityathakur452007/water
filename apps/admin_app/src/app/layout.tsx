import type { Metadata } from "next";
import { GeistSans } from "geist/font/sans";
import { GeistMono } from "geist/font/mono";
import "./globals.css";
import { AdminSessionProvider } from "@/features/shell/session-context";

export const metadata: Metadata = {
  title: "Shodasha · Super Admin",
  description: "Operations cockpit for Shodasha Mineral Waters",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${GeistSans.variable} ${GeistMono.variable}`}>
      <body className="min-h-[100dvh] antialiased">
        <AdminSessionProvider>{children}</AdminSessionProvider>
      </body>
    </html>
  );
}
