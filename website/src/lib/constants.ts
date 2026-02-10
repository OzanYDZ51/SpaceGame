export const SITE_NAME = "Imperion Online";
export const SITE_DESCRIPTION =
  "Explorez. Commercez. Conquérez. Un univers persistant vous attend.";
export const SITE_URL = "https://imperiononline.fr";

export const API_URL =
  process.env.NEXT_PUBLIC_API_URL || "https://backend-production-05a9.up.railway.app";

export const NAV_LINKS = [
  { label: "Accueil", href: "#hero" },
  { label: "Features", href: "#features" },
  { label: "Univers", href: "#universe" },
  { label: "Changelog", href: "#changelog" },
  { label: "Télécharger", href: "#download" },
] as const;

export const FEATURES = [
  {
    title: "Vol 6DOF",
    description:
      "Pilotez votre vaisseau avec une liberté totale dans les 6 degrés de mouvement. Tangage, lacet, roulis — le vide spatial est votre terrain de jeu.",
    icon: "rocket",
  },
  {
    title: "Univers Massif",
    description:
      "Plus de 120 systèmes stellaires générés procéduralement, reliés par des jump gates et des wormholes inter-galaxies.",
    icon: "globe",
  },
  {
    title: "Combat Temps Réel",
    description:
      "Affrontez des PNJ et d'autres joueurs avec un système de combat dynamique : boucliers directionnels, armes multiples, gestion de l'énergie.",
    icon: "crosshair",
  },
  {
    title: "Économie Dynamique",
    description:
      "Achetez, vendez et transportez des marchandises entre les stations. Les prix fluctuent selon l'offre et la demande.",
    icon: "trending-up",
  },
  {
    title: "Minage",
    description:
      "Extrayez 8 types de minerais dans les ceintures d'astéroïdes. Gérez la chaleur de votre laser et optimisez vos routes de minage.",
    icon: "pickaxe",
  },
  {
    title: "Système de Clans",
    description:
      "Créez ou rejoignez un clan, gérez la diplomatie, et déployez votre flotte pour contrôler des systèmes stratégiques.",
    icon: "users",
  },
] as const;

export const UNIVERSE_STATS = [
  { value: "120+", label: "Systèmes stellaires" },
  { value: "8", label: "Minerais extractibles" },
  { value: "7", label: "Classes d'étoiles" },
] as const;
