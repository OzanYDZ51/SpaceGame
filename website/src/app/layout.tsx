import type { Metadata } from "next";
import { rajdhani, shareTechMono } from "@/lib/fonts";
import { SITE_NAME, SITE_DESCRIPTION } from "@/lib/constants";
import { AuthProvider } from "@/lib/auth";
import { Navbar } from "@/components/layout/Navbar";
import { Footer } from "@/components/layout/Footer";
import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL(process.env.NEXT_PUBLIC_SITE_URL || "https://imperion-online.com"),
  title: `${SITE_NAME} — MMORPG Spatial`,
  description: SITE_DESCRIPTION,
  icons: { icon: "/favicon.svg" },
  openGraph: {
    title: SITE_NAME,
    description: SITE_DESCRIPTION,
    type: "website",
    images: [{ url: "/images/og-image.jpg", width: 1200, height: 630 }],
  },
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="fr" className={`${rajdhani.variable} ${shareTechMono.variable}`}>
      <body className="min-h-screen bg-bg-primary text-text-primary font-heading antialiased">
        <AuthProvider>
          <Navbar />
          <main>{children}</main>
          <Footer />
        </AuthProvider>
      </body>
    </html>
  );
}
