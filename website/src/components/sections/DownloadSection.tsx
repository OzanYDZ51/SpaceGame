"use client";

import { useEffect, useState } from "react";
import { motion } from "framer-motion";
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
      .get<UpdatesResponse>("/api/v1/updates")
      .then(setUpdates)
      .catch(() => {});
  }, []);

  const launcher = updates?.launcher;
  const game = updates?.game;

  return (
    <section id="download" className="relative py-20 sm:py-24 md:py-32 overflow-hidden">
      {/* Animated background glow */}
      <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
        <motion.div
          className="w-[300px] h-[300px] sm:w-[500px] sm:h-[500px] md:w-[600px] md:h-[600px] rounded-full bg-cyan/[0.03] blur-[80px] sm:blur-[100px]"
          animate={{
            scale: [1, 1.1, 1],
            opacity: [0.6, 1, 0.6],
          }}
          transition={{ duration: 4, repeat: Infinity, ease: "easeInOut" }}
        />
      </div>

      <Container className="relative z-10 text-center px-6">
        <ScrollReveal>
          <h2 className="text-3xl sm:text-4xl md:text-5xl font-bold uppercase tracking-wider text-cyan text-glow-cyan mb-4">
            Rejoignez l&apos;aventure
          </h2>
          <p className="text-text-secondary text-base sm:text-lg mb-8 sm:mb-10 max-w-md sm:max-w-xl mx-auto">
            Téléchargez le launcher, créez votre compte et prenez les commandes
            de votre vaisseau.
          </p>
        </ScrollReveal>

        <ScrollReveal delay={0.2}>
          <div className="inline-flex flex-col items-center gap-4">
            {launcher ? (
              <Button
                href={launcher.download_url}
                className="text-sm sm:text-lg px-6 sm:px-10 py-3 sm:py-4"
              >
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                  <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
                  <polyline points="7 10 12 15 17 10" />
                  <line x1="12" x2="12" y1="15" y2="3" />
                </svg>
                Télécharger le launcher
              </Button>
            ) : (
              <Button className="text-sm sm:text-lg px-6 sm:px-10 py-3 sm:py-4" disabled>
                Launcher bientôt disponible
              </Button>
            )}

            {launcher && (
              <p className="text-xs font-mono text-text-muted tracking-wider">
                v{launcher.version} — Launcher {formatBytes(launcher.size)}
                {game ? ` | Jeu ${formatBytes(game.size)}` : ""}
              </p>
            )}

            <p className="text-xs text-text-muted mt-2">
              Windows 10+ requis
            </p>
          </div>
        </ScrollReveal>
      </Container>
    </section>
  );
}
