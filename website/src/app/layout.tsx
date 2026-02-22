import type { Metadata } from "next";
import { rajdhani, shareTechMono } from "@/lib/fonts";
import { SITE_NAME, SITE_URL } from "@/lib/constants";
import { AuthProvider } from "@/lib/auth";
import { FactionProvider } from "@/lib/faction";
import { I18nProvider } from "@/i18n";
import { KharsisAmbience } from "@/components/effects/KharsisAmbience";
import { Navbar } from "@/components/layout/Navbar";
import { Footer } from "@/components/layout/Footer";
import "./globals.css";

const description =
  "La galaxie n'obéit à personne. MMORPG spatial en monde ouvert — explorez, combattez, conquérez. 120+ systèmes stellaires, combat PvP, minage, commerce et flottes persistantes.";
const descriptionEn =
  "The galaxy obeys no one. Open-world space MMORPG — explore, fight, conquer. 120+ star systems, PvP combat, mining, trading and persistent fleets.";

export const metadata: Metadata = {
  metadataBase: new URL(process.env.NEXT_PUBLIC_SITE_URL || SITE_URL),
  title: {
    default: `${SITE_NAME} — MMORPG Spatial en Monde Ouvert`,
    template: `%s | ${SITE_NAME}`,
  },
  description,
  keywords: [
    "Imperion Online",
    "MMORPG spatial",
    "space MMORPG",
    "jeu spatial",
    "space game",
    "open world",
    "monde ouvert",
    "PvP",
    "minage spatial",
    "space mining",
    "combat spatial",
    "flotte",
    "fleet",
    "multijoueur",
    "multiplayer",
    "free to play",
    "gratuit",
    "Godot",
  ],
  authors: [{ name: "Imperion Online Team" }],
  creator: "Imperion Online",
  publisher: "Imperion Online",
  icons: {
    icon: "/favicon.svg",
  },
  manifest: "/manifest.json",
  openGraph: {
    title: `${SITE_NAME} — MMORPG Spatial en Monde Ouvert`,
    description,
    type: "website",
    url: SITE_URL,
    siteName: SITE_NAME,
    locale: "fr_FR",
    alternateLocale: "en_US",
    images: [
      {
        url: "/og-image.png",
        width: 1920,
        height: 1080,
        alt: "Imperion Online — Champ d'astéroïdes dans une nébuleuse",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: `${SITE_NAME} — MMORPG Spatial`,
    description,
    images: ["/og-image.png"],
  },
  robots: {
    index: true,
    follow: true,
    googleBot: {
      index: true,
      follow: true,
      "max-video-preview": -1,
      "max-image-preview": "large",
      "max-snippet": -1,
    },
  },
  alternates: {
    canonical: SITE_URL,
    languages: {
      "fr": SITE_URL,
      "en": SITE_URL,
    },
  },
  other: {
    "google-site-verification": process.env.NEXT_PUBLIC_GOOGLE_SITE_VERIFICATION || "",
  },
};

/* ── JSON-LD Structured Data ──────────────────── */

const jsonLd = {
  "@context": "https://schema.org",
  "@graph": [
    {
      "@type": "WebSite",
      "@id": `${SITE_URL}/#website`,
      url: SITE_URL,
      name: SITE_NAME,
      description,
      inLanguage: ["fr-FR", "en-US"],
    },
    {
      "@type": "VideoGame",
      "@id": `${SITE_URL}/#game`,
      name: SITE_NAME,
      description,
      url: SITE_URL,
      genre: ["MMORPG", "Space simulation", "Open world"],
      gamePlatform: "PC",
      operatingSystem: "Windows 10+",
      applicationCategory: "Game",
      offers: {
        "@type": "Offer",
        price: "0",
        priceCurrency: "EUR",
        availability: "https://schema.org/InStock",
      },
      image: `${SITE_URL}/og-image.png`,
      inLanguage: ["fr", "en"],
    },
    {
      "@type": "Organization",
      "@id": `${SITE_URL}/#organization`,
      name: SITE_NAME,
      url: SITE_URL,
      logo: `${SITE_URL}/logo.svg`,
    },
  ],
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="fr" className={`${rajdhani.variable} ${shareTechMono.variable}`}>
      <head>
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
        />
      </head>
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
