"use client";

import { useI18n } from "@/i18n";
import { Container } from "@/components/ui/Container";

export function Footer() {
  const { t } = useI18n();

  return (
    <footer className="border-t border-border-subtle bg-bg-secondary/50 py-8 sm:py-10">
      <Container>
        <div className="flex flex-col items-center gap-4 sm:flex-row sm:justify-between">
          <div className="flex items-center gap-2">
            <span className="text-sm font-bold uppercase tracking-wider text-cyan">
              Imperion
            </span>
            <span className="text-xs font-mono uppercase tracking-[0.3em] text-text-secondary">
              Online
            </span>
          </div>

          <div className="flex items-center gap-4 sm:gap-6">
            <a href="#hero" className="text-xs uppercase tracking-wider text-text-secondary hover:text-cyan transition-colors">
              {t.footer.home}
            </a>
            <a href="#features" className="text-xs uppercase tracking-wider text-text-secondary hover:text-cyan transition-colors">
              {t.footer.features}
            </a>
            <a href="#download" className="text-xs uppercase tracking-wider text-text-secondary hover:text-cyan transition-colors">
              {t.footer.download}
            </a>
          </div>

          <p className="text-xs text-text-muted font-mono">
            &copy; {new Date().getFullYear()} Imperion Online
          </p>
        </div>
      </Container>
    </footer>
  );
}
