"use client";

import { Container } from "@/components/ui/Container";
import { SectionHeading } from "@/components/ui/SectionHeading";
import { ScrollReveal } from "@/components/effects/ScrollReveal";

const SCREENSHOTS = [
  { alt: "Vol spatial", gradient: "from-cyan/20 via-blue-900/30 to-purple-900/20" },
  { alt: "Combat", gradient: "from-red-900/20 via-orange-900/20 to-cyan/10" },
  { alt: "Station orbitale", gradient: "from-cyan/10 via-teal-900/20 to-blue-900/20" },
  { alt: "Galaxy map", gradient: "from-purple-900/20 via-cyan/15 to-blue-900/20" },
  { alt: "Minage", gradient: "from-amber-900/20 via-cyan/10 to-teal-900/20" },
];

export function ScreenshotsSection() {
  return (
    <section id="screenshots" className="py-24 sm:py-32">
      <Container>
        <ScrollReveal>
          <SectionHeading
            title="Aperçu"
            subtitle="Quelques captures de l'univers d'Imperion Online."
          />
        </ScrollReveal>
      </Container>

      {/* Horizontal scrollable gallery */}
      <div className="overflow-x-auto pb-4 scrollbar-thin">
        <div className="flex gap-4 px-4 sm:px-8 min-w-max">
          {SCREENSHOTS.map((shot, i) => (
            <ScrollReveal key={i} delay={i * 0.1} direction="right">
              <div className="relative w-80 h-48 sm:w-96 sm:h-56 rounded border border-border-subtle overflow-hidden border-glow-hover flex-shrink-0">
                {/* Placeholder gradient — replace with actual screenshots */}
                <div
                  className={`absolute inset-0 bg-gradient-to-br ${shot.gradient}`}
                />
                <div className="absolute inset-0 flex items-center justify-center">
                  <span className="text-xs font-mono uppercase tracking-[0.2em] text-text-muted">
                    {shot.alt}
                  </span>
                </div>
              </div>
            </ScrollReveal>
          ))}
        </div>
      </div>
    </section>
  );
}
