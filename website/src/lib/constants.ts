export const SITE_NAME = "Imperion Online";
export const SITE_DESCRIPTION =
  "Explorez. Commercez. Conquérez. Un univers persistant vous attend.";
export const SITE_URL = "https://imperiononline.fr";

export const API_URL =
  process.env.NEXT_PUBLIC_API_URL || "https://backend-production-05a9.up.railway.app";

export const NAV_LINKS = [
  { label: "Accueil", href: "#hero" },
  { label: "Features", href: "#features" },
  { label: "Vaisseaux", href: "#ships" },
  { label: "Univers", href: "#universe" },
  { label: "Roadmap", href: "#roadmap" },
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

export type ShipData = {
  id: string;
  name: string;
  class: string;
  modelPath: string;
  scale: number;
  cameraDistance: number;
  stats: {
    speed: string;
    hull: string;
    shields: string;
    class: string;
  };
  description: string;
};

export const SHIPS: ShipData[] = [
  {
    id: "fighter",
    name: "Fighter Mk1",
    class: "Chasseur",
    modelPath: "/models/tie.glb",
    scale: 1.5,
    cameraDistance: 4,
    stats: {
      speed: "320 m/s",
      hull: "450 HP",
      shields: "200 SP",
      class: "Chasseur léger",
    },
    description:
      "Agile et rapide, le Fighter Mk1 est l'épine dorsale de toute flotte. Idéal pour l'interception et les patrouilles.",
  },
  {
    id: "frigate",
    name: "Frigate Mk1",
    class: "Frégate",
    modelPath: "/models/frigate_mk1.glb",
    scale: 0.6,
    cameraDistance: 6,
    stats: {
      speed: "140 m/s",
      hull: "2800 HP",
      shields: "1200 SP",
      class: "Frégate d'assaut",
    },
    description:
      "Un vaisseau lourd conçu pour le combat prolongé. Ses tourelles multiples en font un adversaire redoutable.",
  },
];

export type RoadmapPhase = {
  id: string;
  title: string;
  status: "done" | "in-progress" | "upcoming";
  summary: string;
  details: string[];
};

export const ROADMAP_PHASES: RoadmapPhase[] = [
  {
    id: "flight",
    title: "Vol spatial",
    status: "done",
    summary: "Physique 6DOF, caméra, HUD de pilotage",
    details: [
      "Contrôleur de vaisseau 6 degrés de liberté",
      "Caméra 3e personne avec suivi dynamique",
      "Skybox procédural avec champ d'étoiles",
      "HUD de pilotage avec indicateurs de vitesse et cap",
    ],
  },
  {
    id: "universe",
    title: "Univers procédural",
    status: "done",
    summary: "120+ systèmes, jump gates, carte galactique",
    details: [
      "Génération procédurale de systèmes stellaires",
      "7 classes d'étoiles avec propriétés uniques",
      "Réseau de jump gates et wormholes",
      "Carte du système et carte galactique interactives",
    ],
  },
  {
    id: "combat",
    title: "Combat",
    status: "done",
    summary: "Armes, boucliers directionnels, IA ennemie",
    details: [
      "Système de combat avec armes primaires et secondaires",
      "Boucliers directionnels (4 faces)",
      "IA de combat : patrouille, poursuite, évasion, fuite",
      "Système de cible et verrouillage",
    ],
  },
  {
    id: "economy",
    title: "Économie & Commerce",
    status: "done",
    summary: "Stations, minage, raffinage, commerce dynamique",
    details: [
      "8 types de minerais extractibles",
      "Système de raffinage avec 18 recettes",
      "Prix dynamiques offre/demande entre stations",
      "Système de cargo et gestion d'inventaire",
    ],
  },
  {
    id: "multiplayer",
    title: "Multijoueur MMO",
    status: "done",
    summary: "Serveur dédié, clans, persistence de flotte",
    details: [
      "Synchronisation temps réel des joueurs et PNJ",
      "Système de clans avec diplomatie et trésorerie",
      "Déploiement de flotte persistant côté serveur",
      "Escadrons avec 5 rôles et formations",
    ],
  },
  {
    id: "planets",
    title: "Atterrissage planétaire",
    status: "done",
    summary: "Planètes avec atmosphère, végétation, villes",
    details: [
      "Planètes cube-sphère avec LOD quadtree",
      "Atmosphères Rayleigh/Mie par type de planète",
      "Végétation procédurale par biome",
      "Lumières de villes nocturnes",
    ],
  },
  {
    id: "launcher",
    title: "Launcher & Déploiement",
    status: "in-progress",
    summary: "Launcher desktop, auto-update, authentification",
    details: [
      "Launcher natif avec authentification",
      "Téléchargement et mise à jour automatique",
      "Backend Go/PostgreSQL sur Railway",
      "Bot Discord intégré",
    ],
  },
  {
    id: "future",
    title: "Et ensuite...",
    status: "upcoming",
    summary: "Quelque chose de grand se prépare...",
    details: [
      "Nouveaux types de vaisseaux et équipements",
      "Missions et événements dynamiques",
      "Territoires de clan et conquête",
      "...et bien plus à découvrir en jeu",
    ],
  },
];

export const SCREENSHOTS = [
  {
    src: "/screenshots/flight.jpg",
    alt: "Vol spatial",
    caption: "Explorez l'immensité du vide spatial",
  },
  {
    src: "/screenshots/combat.jpg",
    alt: "Combat",
    caption: "Affrontez vos ennemis dans des combats intenses",
  },
  {
    src: "/screenshots/station.jpg",
    alt: "Station orbitale",
    caption: "Amarrez-vous aux stations pour commercer et vous ravitailler",
  },
  {
    src: "/screenshots/planet.jpg",
    alt: "Vue planétaire",
    caption: "Atterrissez sur des planètes aux atmosphères uniques",
  },
  {
    src: "/screenshots/galaxy.jpg",
    alt: "Galaxy map",
    caption: "Naviguez à travers 120+ systèmes stellaires",
  },
];
