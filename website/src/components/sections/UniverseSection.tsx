"use client";

import { useRef } from "react";
import { motion, useInView } from "framer-motion";
import { UNIVERSE_STATS } from "@/lib/constants";
import { Container } from "@/components/ui/Container";
import { SectionHeading } from "@/components/ui/SectionHeading";
import { ScrollReveal } from "@/components/effects/ScrollReveal";

function AnimatedCounter({ value, label, delay }: { value: string; label: string; delay: number }) {
  const ref = useRef<HTMLDivElement>(null);
  const isInView = useInView(ref, { once: true, margin: "-50px" });

  return (
    <div ref={ref} className="text-center">
      <motion.div
        className="text-4xl sm:text-5xl md:text-6xl font-bold text-cyan text-glow-cyan font-mono"
        initial={{ opacity: 0, scale: 0.5, y: 20 }}
        animate={isInView ? { opacity: 1, scale: 1, y: 0 } : {}}
        transition={{ duration: 0.6, delay, type: "spring", stiffness: 120 }}
      >
        {value}
      </motion.div>
      <motion.p
        className="mt-2 text-xs sm:text-sm uppercase tracking-[0.15em] sm:tracking-[0.2em] text-text-secondary"
        initial={{ opacity: 0 }}
        animate={isInView ? { opacity: 1 } : {}}
        transition={{ duration: 0.5, delay: delay + 0.2 }}
      >
        {label}
      </motion.p>
    </div>
  );
}

export function UniverseSection() {
  return (
    <section id="universe" className="relative py-20 sm:py-24 md:py-32 overflow-hidden">
      {/* Background gradient */}
      <div className="absolute inset-0 bg-gradient-to-b from-bg-primary via-bg-secondary to-bg-primary" />

      {/* Corner accents — responsive */}
      <div className="absolute top-0 left-0 w-12 h-12 sm:w-24 sm:h-24 border-t border-l border-cyan/20" />
      <div className="absolute top-0 right-0 w-12 h-12 sm:w-24 sm:h-24 border-t border-r border-cyan/20" />
      <div className="absolute bottom-0 left-0 w-12 h-12 sm:w-24 sm:h-24 border-b border-l border-cyan/20" />
      <div className="absolute bottom-0 right-0 w-12 h-12 sm:w-24 sm:h-24 border-b border-r border-cyan/20" />

      <Container className="relative z-10">
        <ScrollReveal>
          <SectionHeading
            title="L'Univers"
            subtitle="Un cosmos généré procéduralement, relié par des jump gates et des wormholes inter-galaxies."
          />
        </ScrollReveal>

        {/* Stats row — stacks on mobile */}
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-6 sm:gap-8 mb-12 sm:mb-16 max-w-2xl mx-auto">
          {UNIVERSE_STATS.map((stat, i) => (
            <AnimatedCounter key={stat.label} value={stat.value} label={stat.label} delay={i * 0.15} />
          ))}
        </div>

        <ScrollReveal>
          <div className="max-w-3xl mx-auto space-y-4 text-center">
            <p className="text-sm sm:text-base text-text-secondary leading-relaxed">
              Chaque système stellaire possède sa propre identité visuelle : étoiles
              de classes spectrales variées (M, K, G, F, A, B, O), nébuleuses colorées,
              ceintures d&apos;astéroïdes riches en ressources et stations orbitales.
            </p>
            <p className="text-sm sm:text-base text-text-secondary leading-relaxed">
              Naviguez entre les systèmes via les jump gates, ou osez traverser
              un wormhole pour rejoindre une autre galaxie — hébergée sur un
              serveur différent, avec sa propre économie et ses propres joueurs.
            </p>
          </div>
        </ScrollReveal>
      </Container>
    </section>
  );
}
