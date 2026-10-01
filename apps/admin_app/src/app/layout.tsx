import type { Metadata } from "next";
import Script from "next/script";
import { GeistSans } from "geist/font/sans";
import { GeistMono } from "geist/font/mono";
import { Toaster } from "sonner";
import "./globals.css";
import { AdminSessionProvider } from "@/features/shell/session-context";

export const metadata: Metadata = {
  title: "Shodasha · Super Admin",
  description: "Operations cockpit for Shodasha Mineral Waters",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${GeistSans.variable} ${GeistMono.variable}`}>
      {/* Firebase compat SDK (phone auth). beforeInteractive is only honored
          in the root layout — placed anywhere else Next silently drops it. */}
      <Script
        src="https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js"
        strategy="beforeInteractive"
      />
      <Script
        src="https://www.gstatic.com/firebasejs/10.12.2/firebase-auth-compat.js"
        strategy="beforeInteractive"
      />
      <body className="min-h-[100dvh] antialiased">
        <AdminSessionProvider>{children}</AdminSessionProvider>
        <Toaster position="top-right" theme="light" richColors closeButton />
      </body>
    </html>
  );
}
