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

export type FeatureData = {
  title: string;
  description: string;
  icon: string;
  size: "hero" | "medium" | "standard";
};

export const FEATURES: FeatureData[] = [
  {
    title: "Liberté totale de vol",
    description:
      "Six degrés de liberté. Aucun rail, aucune limite. Votre vaisseau répond à chaque impulsion — tangage, lacet, roulis, translation. Le vide spatial n'a pas de haut ni de bas, et c'est exactement comme ça que ça doit être. Maîtrisez le vol Newtonien ou laissez l'assistance vous guider.",
    icon: "rocket",
    size: "hero",
  },
  {
    title: "120+ systèmes stellaires",
    description:
      "Une galaxie entière générée procéduralement vous attend. Jump gates, wormholes inter-galaxies, 7 classes d'étoiles — chaque système a son identité, ses dangers et ses opportunités. Explorez l'inconnu ou tracez vos routes commerciales.",
    icon: "globe",
    size: "medium",
  },
  {
    title: "Combat sans merci",
    description:
      "Boucliers directionnels, armes primaires et secondaires, gestion d'énergie en temps réel. Chaque affrontement est un duel de tactique et de réflexes. Visez les boucliers faibles, esquivez les torpilles, et achevez vos ennemis.",
    icon: "crosshair",
    size: "medium",
  },
  {
    title: "Économie vivante",
    description:
      "Les prix fluctuent selon l'offre et la demande entre les stations. Trouvez les routes les plus rentables, transportez du cargo précieux à travers des systèmes dangereux.",
    icon: "trending-up",
    size: "standard",
  },
  {
    title: "Minage & Raffinage",
    description:
      "8 minerais, des ceintures d'astéroïdes procédurales, un laser de minage avec gestion thermique. Raffinez vos matériaux bruts en composants de valeur avec 18 recettes.",
    icon: "pickaxe",
    size: "standard",
  },
  {
    title: "Clans & Flottes",
    description:
      "Fondez votre clan, déployez des escadrons autonomes, gérez la diplomatie. Vos vaisseaux persistent même hors-ligne — construisez un empire.",
    icon: "users",
    size: "standard",
  },
];

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

export const SHIPS_BY_FACTION: Record<string, ShipData[]> = {
  nova_terra: [
    {
      id: "nt-fighter",
      name: "Fighter NT-7",
      class: "Chasseur",
      modelPath: "/models/tie.glb",
      scale: 1.5,
      cameraDistance: 4,
      stats: {
        speed: "340 m/s",
        hull: "400 HP",
        shields: "280 SP",
        class: "Intercepteur de ligne",
      },
      description:
        "Le NT-7 incarne la doctrine Nova Terra : précision et protection. Ses boucliers surpuissants et sa vitesse en font le chasseur parfait pour les patrouilles de la Confédération.",
    },
    {
      id: "nt-frigate",
      name: "Frégate Aurore",
      class: "Frégate",
      modelPath: "/models/frigate_mk1.glb",
      scale: 0.6,
      cameraDistance: 6,
      stats: {
        speed: "160 m/s",
        hull: "2400 HP",
        shields: "1600 SP",
        class: "Frégate de défense",
      },
      description:
        "La Frégate Aurore est le bouclier de la flotte. Conçue pour encaisser et protéger, ses générateurs de boucliers de dernière génération sont inégalés dans la galaxie.",
    },
  ],
  kharsis: [
    {
      id: "kh-fighter",
      name: "Intercepteur Kha'ri",
      class: "Chasseur",
      modelPath: "/models/tie.glb",
      scale: 1.5,
      cameraDistance: 4,
      stats: {
        speed: "300 m/s",
        hull: "550 HP",
        shields: "150 SP",
        class: "Chasseur d'assaut",
      },
      description:
        "Forgé au-delà du Rift, le Kha'ri est une machine de guerre brute. Sa coque renforcée par des alliages aliens et ses armes dévastatrices compensent largement ses boucliers limités.",
    },
    {
      id: "kh-frigate",
      name: "Croiseur Kha'ri",
      class: "Croiseur",
      modelPath: "/models/frigate_mk1.glb",
      scale: 0.6,
      cameraDistance: 6,
      stats: {
        speed: "120 m/s",
        hull: "3600 HP",
        shields: "800 SP",
        class: "Croiseur lourd",
      },
      description:
        "Le Croiseur Kha'ri est la terreur des champs de bataille. Sa masse colossale et son armement dévastateur en font un vaisseau conçu pour un seul objectif : la destruction totale.",
    },
  ],
};

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
    id: "interiors",
    title: "Intérieurs 3D",
    status: "upcoming",
    summary: "Explorez l'intérieur des stations et de vos vaisseaux",
    details: [
      "Intérieurs de stations visitables à pied",
      "Ponts de vaisseaux accessibles en vue FPS",
      "Interactions avec les PNJ et les équipements",
      "Personnalisation des cabines de vaisseau",
    ],
  },
  {
    id: "planets",
    title: "Atterrissage planétaire",
    status: "upcoming",
    summary: "Posez-vous sur des planètes aux atmosphères uniques",
    details: [
      "Planètes avec LOD haute fidélité",
      "Atmosphères dynamiques par type de planète",
      "Végétation et biomes procéduraux",
      "Bases et colonies en surface",
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
