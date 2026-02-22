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
  stats: { speed: string; hull: string; shields: string; price: string };
};

export const SHIP_STRUCTURE: ShipStructure[] = [
  {
    id: "chasseur_viper",
    modelPath: "/models/chasseur_viper.glb",
    scale: 1.5,
    cameraDistance: 4,
    stats: { speed: "380 m/s", hull: "1 200 HP", shields: "600 SP", price: "55 000" },
  },
  {
    id: "chasseur_arrw",
    modelPath: "/models/chasseur_arrw.glb",
    scale: 1.5,
    cameraDistance: 4,
    stats: { speed: "350 m/s", hull: "1 500 HP", shields: "800 SP", price: "80 000" },
  },
  {
    id: "chasseur_lourd_cv",
    modelPath: "/models/chasseur_lourd_cv.glb",
    scale: 1.0,
    cameraDistance: 5,
    stats: { speed: "240 m/s", hull: "2 800 HP", shields: "1 400 SP", price: "160 000" },
  },
  {
    id: "croiseur_bodhammer",
    modelPath: "/models/croiseur_bodhammer.glb",
    scale: 0.6,
    cameraDistance: 6,
    stats: { speed: "100 m/s", hull: "12 000 HP", shields: "6 000 SP", price: "850 000" },
  },
];

/* Faction ship variants — currently both factions share the same buyable ships.
   Faction selection only affects UI color theme (cyan vs red rim lighting). */
export const SHIP_STRUCTURE_BY_FACTION: Record<string, ShipStructure[]> = {};

/* ── Screenshots — structural data (paths + layout) ── */

export type ScreenshotLayout = {
  src: string;
  category: "space" | "ui";
  /** Tailwind col-span class for the grid */
  span: string;
};

export const SCREENSHOT_DATA: ScreenshotLayout[] = [
  { src: "/screenshots/asteroid_field.png",   category: "space", span: "sm:col-span-2 lg:col-span-3" },  // hero — full width
  { src: "/screenshots/station_docking.png",  category: "space", span: "lg:col-span-2" },
  { src: "/screenshots/combat_flight.png",    category: "space", span: "" },
  { src: "/screenshots/mining_laser.png",     category: "space", span: "" },
  { src: "/screenshots/galaxy_map.png",       category: "ui",    span: "" },
  { src: "/screenshots/system_map.png",       category: "ui",    span: "" },
  { src: "/screenshots/station_services.png", category: "ui",    span: "" },
  { src: "/screenshots/ship_equipment.png",   category: "ui",    span: "sm:col-span-2 lg:col-span-2" },
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
