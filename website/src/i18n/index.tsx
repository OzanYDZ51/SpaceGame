"use client";

import {
  createContext,
  useContext,
  useState,
  useEffect,
  type ReactNode,
} from "react";
import fr from "./locales/fr";
import en from "./locales/en";

/* ── Types ─────────────────────────────────────── */

export type Locale = "fr" | "en";

export type StatItem = { value: string; label: string };

export type FeatureCardText = {
  title: string;
  subtitle: string;
  description: string;
  stats?: string;
};

export type ShipText = {
  name: string;
  class: string;
  description: string;
  statsClass: string;
};

export type ScreenshotText = { alt: string; caption: string };

export type RoadmapPhaseText = {
  title: string;
  summary: string;
  details: string[];
};

export type FactionText = {
  name: string;
  subtitle: string;
  motto: string;
  description: string;
  traits: string[];
};

export type Translations = {
  meta: { description: string };
  nav: {
    home: string;
    features: string;
    ships: string;
    universe: string;
    roadmap: string;
    download: string;
    login: string;
    logout: string;
    changeFaction: string;
    resetFaction: string;
  };
  hero: {
    badge: string;
    taglineDefault: string;
    taglineNovaTerra: string;
    taglineKharsis: string;
    subtitleDefault: string;
    subtitleNovaTerra: string;
    subtitleKharsis: string;
    ctaPlay: string;
    ctaDiscover: string;
    stats: StatItem[];
  };
  features: {
    tagline: string;
    title: string;
    titleHighlight: string;
    subtitle: string;
    cards: FeatureCardText[];
  };
  faction: {
    title: string;
    titleHighlight: string;
    backstory: string;
    choose: string;
    novaTerra: FactionText;
    kharsis: FactionText;
  };
  ships: {
    title: string;
    subtitleDefault: string;
    subtitleNovaTerra: string;
    subtitleKharsis: string;
    moreShips: string;
    dragHint: string;
    weaponsHint: string;
    statLabels: { speed: string; hull: string; shields: string };
    defaultShips: ShipText[];
    factionShips: Record<string, ShipText[]>;
  };
  universe: {
    title: string;
    subtitle: string;
    stats: StatItem[];
    paragraph1: string;
    paragraph2: string;
  };
  server: {
    online: string;
    offline: string;
    serverLabel: string;
    onlineLabel: string;
    registeredLabel: string;
    killEvent: (actor: string, target: string) => string;
    joinEvent: (actor: string) => string;
    genericEvent: (actor: string) => string;
  };
  screenshots: {
    title: string;
    subtitle: string;
    items: ScreenshotText[];
  };
  roadmap: {
    title: string;
    subtitle: string;
    statusDone: string;
    statusInProgress: string;
    statusUpcoming: string;
    phases: RoadmapPhaseText[];
  };
  changelog: {
    title: string;
    subtitle: string;
    empty: string;
  };
  download: {
    title: string;
    subtitle: string;
    cta: string;
    ctaUnavailable: string;
    launcherLabel: string;
    gameLabel: string;
    windowsRequired: string;
  };
  auth: {
    loginTitle: string;
    registerTitle: string;
    accountTitle: string;
    username: string;
    email: string;
    password: string;
    confirmPassword: string;
    loginButton: string;
    loginLoading: string;
    registerButton: string;
    registerLoading: string;
    logoutButton: string;
    closeButton: string;
    noAccount: string;
    createAccount: string;
    hasAccount: string;
    switchToLogin: string;
    launcherHint: string;
    errorLogin: string;
    errorRegister: string;
    errorPasswordMismatch: string;
    errorPasswordLength: string;
  };
  footer: {
    home: string;
    features: string;
    download: string;
  };
  notFound: {
    code: string;
    title: string;
    description: string;
    backHome: string;
  };
};

/* ── Locale registry ───────────────────────────── */

export const LOCALES: { code: Locale; label: string }[] = [
  { code: "fr", label: "FR" },
  { code: "en", label: "EN" },
];

const dictionaries: Record<Locale, Translations> = { fr, en };

/* ── Context ───────────────────────────────────── */

type I18nContextValue = {
  locale: Locale;
  setLocale: (l: Locale) => void;
  t: Translations;
};

const I18nContext = createContext<I18nContextValue | null>(null);

const STORAGE_KEY = "imperion_lang";

function detectLocale(): Locale {
  if (typeof window === "undefined") return "fr";
  try {
    const stored = localStorage.getItem(STORAGE_KEY);
    if (stored === "fr" || stored === "en") return stored;
  } catch {}
  const lang = navigator.language || "";
  return lang.startsWith("fr") ? "fr" : "en";
}

/* ── Provider ──────────────────────────────────── */

export function I18nProvider({ children }: { children: ReactNode }) {
  const [locale, setLocaleState] = useState<Locale>(detectLocale);

  function setLocale(l: Locale) {
    setLocaleState(l);
    try {
      localStorage.setItem(STORAGE_KEY, l);
    } catch {}
    document.documentElement.lang = l;
  }

  // Sync <html lang> on mount
  useEffect(() => {
    document.documentElement.lang = locale;
  }, [locale]);

  return (
    <I18nContext.Provider
      value={{ locale, setLocale, t: dictionaries[locale] }}
    >
      {children}
    </I18nContext.Provider>
  );
}

/* ── Hook ──────────────────────────────────────── */

export function useI18n() {
  const ctx = useContext(I18nContext);
  if (!ctx) throw new Error("useI18n must be used within I18nProvider");
  return ctx;
}
