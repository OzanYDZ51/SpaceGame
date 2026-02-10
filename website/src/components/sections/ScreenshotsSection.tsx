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
    <section id="screenshots" className="py-20 sm:py-24 md:py-32">
      <Container>
        <ScrollReveal>
          <SectionHeading
            title="Aperçu"
            subtitle="Quelques captures de l'univers d'Imperion Online."
          />
        </ScrollReveal>

        {/* Grid on mobile, horizontal scroll on desktop */}
        {/* Mobile: vertical grid */}
        <div className="grid grid-cols-1 sm:hidden gap-4">
          {SCREENSHOTS.map((shot, i) => (
            <ScrollReveal key={i} delay={i * 0.08}>
              <div className="relative w-full aspect-video rounded border border-border-subtle overflow-hidden border-glow-hover">
                <div className={`absolute inset-0 bg-gradient-to-br ${shot.gradient}`} />
                <div className="absolute inset-0 flex items-center justify-center">
                  <span className="text-xs font-mono uppercase tracking-[0.2em] text-text-muted">
                    {shot.alt}
                  </span>
                </div>
              </div>
            </ScrollReveal>
          ))}
        </div>

        {/* Desktop: horizontal scrollable gallery */}
        <div className="hidden sm:block overflow-x-auto pb-4 scrollbar-thin -mx-4 sm:-mx-6 lg:-mx-8">
          <div className="flex gap-4 px-4 sm:px-6 lg:px-8" style={{ width: "max-content" }}>
            {SCREENSHOTS.map((shot, i) => (
              <ScrollReveal key={i} delay={i * 0.1} direction="right">
                <div className="relative w-80 md:w-96 lg:w-[28rem] aspect-video rounded border border-border-subtle overflow-hidden border-glow-hover flex-shrink-0">
                  <div className={`absolute inset-0 bg-gradient-to-br ${shot.gradient}`} />
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
      </Container>
    </section>
  );
}
