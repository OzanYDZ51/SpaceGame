"use client";

import { motion } from "framer-motion";
import { FEATURE_STRUCTURE } from "@/lib/constants";
import type { FeatureStructure } from "@/lib/constants";
import type { FeatureCardText } from "@/i18n";
import { useI18n } from "@/i18n";
import { Container } from "@/components/ui/Container";
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
  users: (s) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2" />
      <circle cx="9" cy="7" r="4" />
      <path d="M22 21v-2a4 4 0 0 0-3-3.87" />
      <path d="M16 3.13a4 4 0 0 1 0 7.75" />
    </svg>
  ),
  signal: (s) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <path d="M2 20h.01" />
      <path d="M7 20v-4" />
      <path d="M12 20v-8" />
      <path d="M17 20V8" />
      <path d="M22 4v16" />
    </svg>
  ),
};

type MergedFeature = FeatureStructure & FeatureCardText;

function FeatureCard({ feature, index }: { feature: MergedFeature; index: number }) {
  const isHero = feature.size === "hero";
  const isMedium = feature.size === "medium";
  const iconSize = isHero ? 44 : isMedium ? 36 : 30;

  return (
    <ScrollReveal delay={index * 0.08}>
      <motion.div
        className="h-full"
        whileHover={{ y: -6, transition: { duration: 0.25 } }}
      >
        <div
          className={`
            relative h-full rounded-lg border border-border-subtle bg-bg-card backdrop-blur-sm border-glow-hover group overflow-hidden
            ${isHero ? "p-8 sm:p-10 lg:p-12" : isMedium ? "p-6 sm:p-8" : "p-6"}
          `}
        >
          <div className="absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent via-cyan/40 to-transparent" />
          <div className="absolute inset-0 bg-gradient-to-br from-cyan/[0.03] to-transparent opacity-0 group-hover:opacity-100 transition-opacity duration-500" />

          <div className={`relative z-10 ${isHero ? "flex flex-col sm:flex-row sm:items-start gap-6 sm:gap-8" : ""}`}>
            <div
              className={`
                text-cyan transition-all duration-300
                group-hover:scale-110 group-hover:drop-shadow-[0_0_16px_var(--color-cyan-glow)]
                ${isHero ? "mb-4 sm:mb-0 shrink-0" : "mb-4"}
              `}
            >
              <div className="relative">
                {icons[feature.icon]?.(iconSize)}
                <div className="absolute -inset-2 rounded-full bg-cyan/[0.05] scale-0 group-hover:scale-100 transition-transform duration-500" />
              </div>
            </div>

            <div className="flex-1">
              <h3
                className={`
                  font-bold uppercase tracking-wider text-text-primary mb-1
                  ${isHero ? "text-2xl sm:text-3xl" : isMedium ? "text-xl sm:text-2xl" : "text-lg sm:text-xl"}
                `}
              >
                {feature.title}
              </h3>

              <p
                className={`
                  text-cyan/80 font-medium mb-3
                  ${isHero ? "text-base sm:text-lg" : "text-sm sm:text-base"}
                `}
              >
                {feature.subtitle}
              </p>

              <p
                className={`
                  text-text-secondary leading-relaxed
                  ${isHero ? "text-sm sm:text-base max-w-2xl" : "text-xs sm:text-sm"}
                `}
              >
                {feature.description}
              </p>

              {feature.stats && (
                <div className={`mt-4 pt-3 border-t border-border-subtle ${isHero ? "mt-6 pt-4" : ""}`}>
                  <span className="text-xs font-mono uppercase tracking-widest text-cyan/60">
                    {feature.stats}
                  </span>
                </div>
              )}
            </div>
          </div>
        </div>
      </motion.div>
    </ScrollReveal>
  );
}

export function FeaturesSection() {
  const { t } = useI18n();

  const features: MergedFeature[] = FEATURE_STRUCTURE.map((s, i) => ({
    ...s,
    ...t.features.cards[i],
  }));

  const hero = features.filter((f) => f.size === "hero");
  const medium = features.filter((f) => f.size === "medium");
  const standard = features.filter((f) => f.size === "standard");

  return (
    <section id="features" className="relative py-20 sm:py-28 md:py-36">
      <Container>
        <ScrollReveal>
          <div className="text-center mb-12 sm:mb-20">
            <div className="flex items-center justify-center gap-3 sm:gap-4 mb-4">
              <div className="h-px w-8 sm:w-16 bg-gradient-to-r from-transparent to-cyan/50" />
              <span className="text-xs font-mono uppercase tracking-[0.4em] text-cyan/60">
                {t.features.tagline}
              </span>
              <div className="h-px w-8 sm:w-16 bg-gradient-to-l from-transparent to-cyan/50" />
            </div>
            <h2 className="text-3xl sm:text-4xl md:text-5xl lg:text-6xl font-bold uppercase tracking-wider text-text-primary">
              {t.features.title}{" "}
              <span className="text-cyan text-glow-cyan-sm">{t.features.titleHighlight}</span>
            </h2>
            <p className="mt-4 text-text-secondary text-sm sm:text-base md:text-lg max-w-2xl mx-auto">
              {t.features.subtitle}
            </p>
          </div>
        </ScrollReveal>

        <div className="space-y-4 sm:space-y-6">
          {hero.map((f, i) => (
            <FeatureCard key={i} feature={f} index={i} />
          ))}

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 sm:gap-6">
            {medium.map((f, i) => (
              <FeatureCard key={i} feature={f} index={hero.length + i} />
            ))}
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 sm:gap-6">
            {standard.map((f, i) => (
              <FeatureCard key={i} feature={f} index={hero.length + medium.length + i} />
            ))}
          </div>
        </div>
      </Container>
    </section>
  );
}
