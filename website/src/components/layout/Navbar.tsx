"use client";

import { useState } from "react";
import { NAV_LINKS } from "@/lib/constants";
import { useScrollPosition } from "@/hooks/useScrollPosition";
import { useAuth } from "@/hooks/useAuth";
import { Button } from "@/components/ui/Button";
import { Container } from "@/components/ui/Container";
import { AuthModal } from "@/components/auth/AuthModal";
import { cn } from "@/lib/utils";

export function Navbar() {
  const scrollY = useScrollPosition();
  const { user, isAuthenticated, logout } = useAuth();
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
          {/* Logo */}
          <a href="#hero" className="flex items-center gap-2 group">
            <span className="text-xl font-bold uppercase tracking-wider text-cyan text-glow-cyan-sm group-hover:brightness-125 transition-all">
              Imperion
            </span>
            <span className="text-xs font-mono uppercase tracking-[0.3em] text-text-secondary">
              Online
            </span>
          </a>

          {/* Desktop nav */}
          <div className="hidden md:flex items-center gap-6">
            {NAV_LINKS.map((link) => (
              <a
                key={link.href}
                href={link.href}
                className="text-sm uppercase tracking-[0.15em] text-text-secondary hover:text-cyan transition-colors duration-200"
              >
                {link.label}
              </a>
            ))}
            {isAuthenticated ? (
              <div className="flex items-center gap-3">
                <span className="text-xs font-mono text-cyan tracking-wider">
                  {user?.username}
                </span>
                <Button variant="ghost" onClick={logout} className="text-xs px-3 py-1.5">
                  Déconnexion
                </Button>
              </div>
            ) : (
              <Button
                variant="outline"
                onClick={() => setAuthOpen(true)}
                className="text-xs px-4 py-1.5"
              >
                Connexion
              </Button>
            )}
          </div>

          {/* Mobile hamburger */}
          <button
            className="md:hidden text-text-secondary hover:text-cyan transition-colors cursor-pointer"
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
                  {link.label}
                </a>
              ))}
              {isAuthenticated ? (
                <div className="flex items-center justify-between pt-2 border-t border-border-subtle">
                  <span className="text-xs font-mono text-cyan">{user?.username}</span>
                  <Button variant="ghost" onClick={logout} className="text-xs px-3 py-1.5">
                    Déconnexion
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
                  Connexion
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
