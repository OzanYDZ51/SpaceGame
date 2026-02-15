"use client";

import { useState, useRef, useEffect } from "react";
import { NAV_LINKS } from "@/lib/constants";
import { useI18n, LOCALES, type Locale } from "@/i18n";
import { useScrollPosition } from "@/hooks/useScrollPosition";
import { useAuth } from "@/hooks/useAuth";
import { useFaction, type FactionId } from "@/lib/faction";
import { Button } from "@/components/ui/Button";
import { Container } from "@/components/ui/Container";
import { AuthModal } from "@/components/auth/AuthModal";
import { cn } from "@/lib/utils";

const FACTION_LABELS: Record<FactionId, { name: string; color: string }> = {
  nova_terra: { name: "Nova Terra", color: "#00c8ff" },
  kharsis: { name: "Kharsis", color: "#ff2244" },
};

const NAV_LABEL_KEYS: Record<string, keyof ReturnType<typeof useI18n>["t"]["nav"]> = {
  home: "home",
  features: "features",
  ships: "ships",
  universe: "universe",
  roadmap: "roadmap",
  download: "download",
};

function LanguageSwitcher() {
  const { locale, setLocale } = useI18n();
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    function handleClick(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) {
        setOpen(false);
      }
    }
    if (open) document.addEventListener("mousedown", handleClick);
    return () => document.removeEventListener("mousedown", handleClick);
  }, [open]);

  return (
    <div ref={ref} className="relative">
      <button
        onClick={() => setOpen(!open)}
        className="flex items-center gap-1.5 px-2 py-1 rounded border border-border-subtle text-xs font-mono uppercase tracking-wider text-text-secondary transition-all cursor-pointer hover:text-cyan hover:border-cyan/40"
      >
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
          <circle cx="12" cy="12" r="10" />
          <path d="M12 2a14.5 14.5 0 0 0 0 20 14.5 14.5 0 0 0 0-20" />
          <path d="M2 12h20" />
        </svg>
        {locale.toUpperCase()}
      </button>

      {open && (
        <div className="absolute top-full right-0 mt-2 w-28 rounded border border-border-subtle bg-bg-secondary/95 backdrop-blur-md shadow-lg z-50 overflow-hidden">
          {LOCALES.map((l) => (
            <button
              key={l.code}
              onClick={() => {
                setLocale(l.code as Locale);
                setOpen(false);
              }}
              className={cn(
                "w-full text-left px-3 py-2 text-sm flex items-center gap-2 transition-colors cursor-pointer",
                l.code === locale
                  ? "bg-cyan/10 text-cyan"
                  : "text-text-secondary hover:text-text-primary hover:bg-white/5"
              )}
            >
              {l.label}
              {l.code === locale && (
                <svg width="12" height="12" viewBox="0 0 12 12" fill="currentColor" className="ml-auto">
                  <path d="M10 3L4.5 8.5L2 6" stroke="currentColor" strokeWidth="1.5" fill="none" strokeLinecap="round" strokeLinejoin="round" />
                </svg>
              )}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

function FactionBadge() {
  const { faction, setFaction, clearFaction } = useFaction();
  const { t } = useI18n();
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    function handleClick(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) {
        setOpen(false);
      }
    }
    if (open) document.addEventListener("mousedown", handleClick);
    return () => document.removeEventListener("mousedown", handleClick);
  }, [open]);

  if (!faction) return null;

  const info = FACTION_LABELS[faction];

  return (
    <div ref={ref} className="relative">
      <button
        onClick={() => setOpen(!open)}
        className="flex items-center gap-1.5 px-2 py-1 rounded border text-xs font-mono uppercase tracking-wider transition-all cursor-pointer hover:brightness-125"
        style={{
          borderColor: `${info.color}44`,
          color: info.color,
          backgroundColor: `${info.color}11`,
        }}
      >
        <span
          className="w-1.5 h-1.5 rounded-full"
          style={{ backgroundColor: info.color }}
        />
        {info.name}
      </button>

      {open && (
        <div className="absolute top-full right-0 mt-2 w-48 rounded border border-border-subtle bg-bg-secondary/95 backdrop-blur-md shadow-lg z-50 overflow-hidden">
          <div className="px-3 py-2 text-xs text-text-muted uppercase tracking-wider border-b border-border-subtle">
            {t.nav.changeFaction}
          </div>
          {(Object.keys(FACTION_LABELS) as FactionId[]).map((id) => (
            <button
              key={id}
              onClick={() => {
                setFaction(id);
                setOpen(false);
              }}
              className={cn(
                "w-full text-left px-3 py-2 text-sm flex items-center gap-2 transition-colors cursor-pointer",
                id === faction
                  ? "bg-cyan/10 text-cyan"
                  : "text-text-secondary hover:text-text-primary hover:bg-white/5"
              )}
            >
              <span
                className="w-2 h-2 rounded-full"
                style={{ backgroundColor: FACTION_LABELS[id].color }}
              />
              {FACTION_LABELS[id].name}
              {id === faction && (
                <svg width="12" height="12" viewBox="0 0 12 12" fill="currentColor" className="ml-auto">
                  <path d="M10 3L4.5 8.5L2 6" stroke="currentColor" strokeWidth="1.5" fill="none" strokeLinecap="round" strokeLinejoin="round" />
                </svg>
              )}
            </button>
          ))}
          <button
            onClick={() => {
              clearFaction();
              setOpen(false);
            }}
            className="w-full text-left px-3 py-2 text-xs text-text-muted hover:text-text-secondary border-t border-border-subtle transition-colors cursor-pointer"
          >
            {t.nav.resetFaction}
          </button>
        </div>
      )}
    </div>
  );
}

export function Navbar() {
  const scrollY = useScrollPosition();
  const { user, isAuthenticated, logout } = useAuth();
  const { t } = useI18n();
  const [mobileOpen, setMobileOpen] = useState(false);
  const [authOpen, setAuthOpen] = useState(false);

  const scrolled = scrollY > 50;

  return (
    <>
      <nav
        className={cn(
          "fixed top-0 left-0 right-0 z-40 transition-all duration-300",
          scrolled
            ? "bg-bg-primary/90 backdrop-blur-md border-b border-border-subtle"
            : "bg-transparent"
        )}
      >
        <Container className="flex items-center justify-between h-16">
          {/* Logo + Faction badge */}
          <div className="flex items-center gap-3">
            <a href="#hero" className="flex items-center gap-2 group">
              <span className="text-xl font-bold uppercase tracking-wider text-cyan text-glow-cyan-sm group-hover:brightness-125 transition-all">
                Imperion
              </span>
              <span className="text-xs font-mono uppercase tracking-[0.3em] text-text-secondary">
                Online
              </span>
            </a>
            <div className="hidden sm:block">
              <FactionBadge />
            </div>
          </div>

          {/* Desktop nav */}
          <div className="hidden md:flex items-center gap-6">
            {NAV_LINKS.map((link) => (
              <a
                key={link.href}
                href={link.href}
                className="text-sm uppercase tracking-[0.15em] text-text-secondary hover:text-cyan transition-colors duration-200"
              >
                {t.nav[NAV_LABEL_KEYS[link.id]]}
              </a>
            ))}
            {isAuthenticated ? (
              <div className="flex items-center gap-3">
                <span className="text-xs font-mono text-cyan tracking-wider">
                  {user?.username}
                </span>
                <Button variant="ghost" onClick={logout} className="text-xs px-3 py-1.5">
                  {t.nav.logout}
                </Button>
              </div>
            ) : (
              <Button
                variant="outline"
                onClick={() => setAuthOpen(true)}
                className="text-xs px-4 py-1.5"
              >
                {t.nav.login}
              </Button>
            )}
            <LanguageSwitcher />
          </div>

          {/* Mobile: language switcher + hamburger */}
          <div className="md:hidden flex items-center gap-3">
            <LanguageSwitcher />
            <button
              className="text-text-secondary hover:text-cyan transition-colors cursor-pointer"
              onClick={() => setMobileOpen(!mobileOpen)}
              aria-label="Menu"
            >
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none">
              {mobileOpen ? (
                <path d="M6 6L18 18M18 6L6 18" stroke="currentColor" strokeWidth="1.5" />
              ) : (
                <>
                  <path d="M4 7H20" stroke="currentColor" strokeWidth="1.5" />
                  <path d="M4 12H20" stroke="currentColor" strokeWidth="1.5" />
                  <path d="M4 17H20" stroke="currentColor" strokeWidth="1.5" />
                </>
              )}
            </svg>
            </button>
          </div>
        </Container>

        {/* Mobile menu */}
        {mobileOpen && (
          <div className="md:hidden bg-bg-secondary/95 backdrop-blur-md border-b border-border-subtle">
            <Container className="py-4 flex flex-col gap-3">
              {NAV_LINKS.map((link) => (
                <a
                  key={link.href}
                  href={link.href}
                  className="text-sm uppercase tracking-[0.15em] text-text-secondary hover:text-cyan py-2"
                  onClick={() => setMobileOpen(false)}
                >
                  {t.nav[NAV_LABEL_KEYS[link.id]]}
                </a>
              ))}
              <div className="pt-2 border-t border-border-subtle sm:hidden">
                <FactionBadge />
              </div>
              {isAuthenticated ? (
                <div className="flex items-center justify-between pt-2 border-t border-border-subtle">
                  <span className="text-xs font-mono text-cyan">{user?.username}</span>
                  <Button variant="ghost" onClick={logout} className="text-xs px-3 py-1.5">
                    {t.nav.logout}
                  </Button>
                </div>
              ) : (
                <Button
                  variant="outline"
                  onClick={() => {
                    setAuthOpen(true);
                    setMobileOpen(false);
                  }}
                  className="text-xs mt-2"
                >
                  {t.nav.login}
                </Button>
              )}
            </Container>
          </div>
        )}
      </nav>

      <AuthModal isOpen={authOpen} onClose={() => setAuthOpen(false)} />
    </>
  );
}
