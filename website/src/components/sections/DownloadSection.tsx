"use client";

import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import { formatBytes } from "@/lib/utils";
import { Container } from "@/components/ui/Container";
import { Button } from "@/components/ui/Button";
import { ScrollReveal } from "@/components/effects/ScrollReveal";
import type { UpdatesResponse } from "@/types/api";

export function DownloadSection() {
  const [updates, setUpdates] = useState<UpdatesResponse | null>(null);

  useEffect(() => {
    api
      .get<UpdatesResponse>("/api/v1/updates/check")
      .then(setUpdates)
      .catch(() => {});
  }, []);

  const launcher = updates?.launcher;

  return (
    <section id="download" className="relative py-24 sm:py-32 overflow-hidden">
      {/* Background glow */}
      <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
        <div className="w-[600px] h-[600px] rounded-full bg-cyan/[0.03] blur-[100px]" />
      </div>

      <Container className="relative z-10 text-center">
        <ScrollReveal>
          <h2 className="text-4xl sm:text-5xl font-bold uppercase tracking-wider text-cyan text-glow-cyan mb-4">
            Rejoignez l&apos;aventure
          </h2>
          <p className="text-text-secondary text-lg mb-10 max-w-xl mx-auto">
            Téléchargez le launcher, créez votre compte et prenez les commandes
            de votre vaisseau.
          </p>
        </ScrollReveal>

        <ScrollReveal delay={0.2}>
          <div className="inline-flex flex-col items-center gap-4">
            {launcher ? (
              <Button
                href={launcher.download_url}
                className="text-lg px-10 py-4"
              >
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                  <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
                  <polyline points="7 10 12 15 17 10" />
                  <line x1="12" x2="12" y1="15" y2="3" />
                </svg>
                Télécharger le launcher
              </Button>
            ) : (
              <Button className="text-lg px-10 py-4" disabled>
                Launcher bientôt disponible
              </Button>
            )}

            {launcher && (
              <p className="text-xs font-mono text-text-muted tracking-wider">
                v{launcher.version} — {formatBytes(launcher.size)}
              </p>
            )}

            <p className="text-xs text-text-muted mt-2">
              Windows 10+ requis | ~200 Mo
            </p>
          </div>
        </ScrollReveal>
      </Container>
    </section>
  );
}
