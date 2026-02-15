"use client";

import { motion } from "framer-motion";
import { FEATURES } from "@/lib/constants";
import type { FeatureData } from "@/lib/constants";
import { Container } from "@/components/ui/Container";
import { SectionHeading } from "@/components/ui/SectionHeading";
import { ScrollReveal } from "@/components/effects/ScrollReveal";

const icons: Record<string, (size: number) => React.ReactNode> = {
  rocket: (s) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <path d="M4.5 16.5c-1.5 1.26-2 5-2 5s3.74-.5 5-2c.71-.84.7-2.13-.09-2.91a2.18 2.18 0 0 0-2.91-.09z" />
      <path d="m12 15-3-3a22 22 0 0 1 2-3.95A12.88 12.88 0 0 1 22 2c0 2.72-.78 7.5-6 11a22.35 22.35 0 0 1-4 2z" />
      <path d="M9 12H4s.55-3.03 2-4c1.62-1.08 5 0 5 0" />
      <path d="M12 15v5s3.03-.55 4-2c1.08-1.62 0-5 0-5" />
    </svg>
  ),
  globe: (s) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="12" cy="12" r="10" />
      <path d="M12 2a14.5 14.5 0 0 0 0 20 14.5 14.5 0 0 0 0-20" />
      <path d="M2 12h20" />
    </svg>
  ),
  crosshair: (s) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="12" cy="12" r="10" />
      <line x1="22" x2="18" y1="12" y2="12" />
      <line x1="6" x2="2" y1="12" y2="12" />
      <line x1="12" x2="12" y1="2" y2="6" />
      <line x1="12" x2="12" y1="18" y2="22" />
    </svg>
  ),
  "trending-up": (s) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <polyline points="22 7 13.5 15.5 8.5 10.5 2 17" />
      <polyline points="16 7 22 7 22 13" />
    </svg>
  ),
  pickaxe: (s) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <path d="M14.531 12.469 6.619 20.38a1 1 0 1 1-1.414-1.414l7.912-7.912" />
      <path d="M15.686 4.314A12.5 12.5 0 0 0 5.461 2.958l-.108.031c-.043.012-.08.04-.104.074a.5.5 0 0 0 .054.55l2.398 2.398-1.414 1.414-2.398-2.398a.5.5 0 0 0-.55-.054c-.034.024-.062.061-.074.104l-.031.108a12.5 12.5 0 0 0 1.356 10.225" />
      <path d="m18.5 5.5 2.5 2.5" />
    </svg>
  ),
  users: (s) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2" />
      <circle cx="9" cy="7" r="4" />
      <path d="M22 21v-2a4 4 0 0 0-3-3.87" />
      <path d="M16 3.13a4 4 0 0 1 0 7.75" />
    </svg>
  ),
};

function FeatureCard({ feature, index }: { feature: FeatureData; index: number }) {
  const isHero = feature.size === "hero";
  const isMedium = feature.size === "medium";
  const iconSize = isHero ? 40 : isMedium ? 36 : 28;

  return (
    <ScrollReveal delay={index * 0.08}>
      <motion.div
        className="h-full"
        whileHover={{ y: -4, transition: { duration: 0.2 } }}
      >
        <div
          className={`
            relative h-full rounded border border-border-subtle bg-bg-card backdrop-blur-sm border-glow-hover group overflow-hidden
            ${isHero ? "p-8 sm:p-10" : isMedium ? "p-6 sm:p-8" : "p-6"}
          `}
        >
          {/* Subtle gradient accent at top */}
          <div className="absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent via-cyan/30 to-transparent" />

          <div className={isHero ? "flex flex-col sm:flex-row sm:items-start gap-6" : ""}>
            <div
              className={`
                text-cyan mb-4 transition-all duration-300
                group-hover:scale-110 group-hover:drop-shadow-[0_0_12px_var(--color-cyan-glow)]
                ${isHero ? "sm:mb-0 shrink-0" : ""}
              `}
            >
              {icons[feature.icon]?.(iconSize)}
            </div>

            <div>
              <h3
                className={`
                  font-bold uppercase tracking-wider text-text-primary mb-2
                  ${isHero ? "text-xl sm:text-2xl" : isMedium ? "text-lg sm:text-xl" : "text-base sm:text-lg"}
                `}
              >
                {feature.title}
              </h3>
              <p
                className={`
                  text-text-secondary leading-relaxed
                  ${isHero ? "text-sm sm:text-base" : "text-xs sm:text-sm"}
                `}
              >
                {feature.description}
              </p>
            </div>
          </div>
        </div>
      </motion.div>
    </ScrollReveal>
  );
}

export function FeaturesSection() {
  const hero = FEATURES.filter((f) => f.size === "hero");
  const medium = FEATURES.filter((f) => f.size === "medium");
  const standard = FEATURES.filter((f) => f.size === "standard");

  return (
    <section id="features" className="relative py-20 sm:py-24 md:py-32">
      <Container>
        <ScrollReveal>
          <SectionHeading
            title="Features"
            subtitle="Un MMORPG spatial ambitieux, construit pour les pilotes exigeants."
          />
        </ScrollReveal>

        <div className="space-y-4 sm:space-y-6">
          {/* Hero feature — full width */}
          {hero.map((f, i) => (
            <FeatureCard key={f.title} feature={f} index={i} />
          ))}

          {/* Medium features — 2 columns */}
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 sm:gap-6">
            {medium.map((f, i) => (
              <FeatureCard key={f.title} feature={f} index={hero.length + i} />
            ))}
          </div>

          {/* Standard features — 3 columns */}
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 sm:gap-6">
            {standard.map((f, i) => (
              <FeatureCard key={f.title} feature={f} index={hero.length + medium.length + i} />
            ))}
          </div>
        </div>
      </Container>
    </section>
  );
}
