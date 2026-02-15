import type { Metadata } from "next";
import { rajdhani, shareTechMono } from "@/lib/fonts";
import { SITE_NAME } from "@/lib/constants";
import { AuthProvider } from "@/lib/auth";
import { FactionProvider } from "@/lib/faction";
import { I18nProvider } from "@/i18n";
import { KharsisAmbience } from "@/components/effects/KharsisAmbience";
import { Navbar } from "@/components/layout/Navbar";
import { Footer } from "@/components/layout/Footer";
import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL(process.env.NEXT_PUBLIC_SITE_URL || "https://imperiononline.fr"),
  title: `${SITE_NAME} — MMORPG Spatial`,
  description:
    "La galaxie n'obéit à personne. MMORPG spatial en monde ouvert — explorez, combattez, conquérez.",
  icons: { icon: "/favicon.svg" },
  openGraph: {
    title: SITE_NAME,
    description:
      "La galaxie n'obéit à personne. MMORPG spatial en monde ouvert — explorez, combattez, conquérez.",
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
        <I18nProvider>
          <FactionProvider>
            <KharsisAmbience />
            <AuthProvider>
              <Navbar />
              <main>{children}</main>
              <Footer />
            </AuthProvider>
          </FactionProvider>
        </I18nProvider>
      </body>
    </html>
  );
}
