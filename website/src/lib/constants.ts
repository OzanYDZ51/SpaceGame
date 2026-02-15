export const SITE_NAME = "Imperion Online";
export const SITE_URL = "https://imperiononline.fr";

export const API_URL =
  process.env.NEXT_PUBLIC_API_URL || "https://backend-production-05a9.up.railway.app";

export const NAV_LINKS = [
  { id: "home", href: "#hero" },
  { id: "features", href: "#features" },
  { id: "ships", href: "#ships" },
  { id: "universe", href: "#universe" },
  { id: "roadmap", href: "#roadmap" },
  { id: "download", href: "#download" },
] as const;

/* ── Features — structural data (icons, sizes) ── */

export type FeatureStructure = {
  icon: string;
  size: "hero" | "medium" | "standard";
};

export const FEATURE_STRUCTURE: FeatureStructure[] = [
  { icon: "rocket", size: "hero" },
  { icon: "crosshair", size: "medium" },
  { icon: "trending-up", size: "medium" },
  { icon: "users", size: "standard" },
  { icon: "globe", size: "standard" },
  { icon: "signal", size: "standard" },
];

/* ── Ships — structural data (models, scale) ──── */

export type ShipStructure = {
  id: string;
  modelPath: string;
  scale: number;
  cameraDistance: number;
  stats: { speed: string; hull: string; shields: string };
};

export const SHIP_STRUCTURE: ShipStructure[] = [
  {
    id: "fighter",
    modelPath: "/models/tie.glb",
    scale: 1.5,
    cameraDistance: 4,
    stats: { speed: "320 m/s", hull: "450 HP", shields: "200 SP" },
  },
  {
    id: "frigate",
    modelPath: "/models/frigate_mk1.glb",
    scale: 0.6,
    cameraDistance: 6,
    stats: { speed: "140 m/s", hull: "2800 HP", shields: "1200 SP" },
  },
];

export const SHIP_STRUCTURE_BY_FACTION: Record<string, ShipStructure[]> = {
  nova_terra: [
    {
      id: "nt-fighter",
      modelPath: "/models/tie.glb",
      scale: 1.5,
      cameraDistance: 4,
      stats: { speed: "340 m/s", hull: "400 HP", shields: "280 SP" },
    },
    {
      id: "nt-frigate",
      modelPath: "/models/frigate_mk1.glb",
      scale: 0.6,
      cameraDistance: 6,
      stats: { speed: "160 m/s", hull: "2400 HP", shields: "1600 SP" },
    },
  ],
  kharsis: [
    {
      id: "kh-fighter",
      modelPath: "/models/tie.glb",
      scale: 1.5,
      cameraDistance: 4,
      stats: { speed: "300 m/s", hull: "550 HP", shields: "150 SP" },
    },
    {
      id: "kh-frigate",
      modelPath: "/models/frigate_mk1.glb",
      scale: 0.6,
      cameraDistance: 6,
      stats: { speed: "120 m/s", hull: "3600 HP", shields: "800 SP" },
    },
  ],
};

/* ── Screenshots — structural data (paths) ─────── */

export const SCREENSHOT_PATHS = [
  "/screenshots/flight.jpg",
  "/screenshots/combat.jpg",
  "/screenshots/station.jpg",
  "/screenshots/planet.jpg",
  "/screenshots/galaxy.jpg",
];

/* ── Roadmap — structural IDs + statuses ────────── */

export type RoadmapStatus = "done" | "in-progress" | "upcoming";

export const ROADMAP_STRUCTURE: { id: string; status: RoadmapStatus }[] = [
  { id: "flight", status: "done" },
  { id: "universe", status: "done" },
  { id: "combat", status: "done" },
  { id: "economy", status: "done" },
  { id: "multiplayer", status: "done" },
  { id: "launcher", status: "in-progress" },
  { id: "interiors", status: "upcoming" },
  { id: "planets", status: "upcoming" },
  { id: "future", status: "upcoming" },
];
