"use client";

import { useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { Container } from "@/components/ui/Container";
import { SectionHeading } from "@/components/ui/SectionHeading";
import { ScrollReveal } from "@/components/effects/ScrollReveal";
import { ROADMAP_PHASES } from "@/lib/constants";
import type { RoadmapPhase } from "@/lib/constants";

function StatusIcon({ status }: { status: RoadmapPhase["status"] }) {
  if (status === "done") {
    return (
      <div className="w-8 h-8 rounded-full bg-accent/15 border-2 border-accent flex items-center justify-center flex-shrink-0">
        <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
          <path d="M2.5 7L5.5 10L11.5 4" stroke="#00ff88" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </div>
    );
  }

  if (status === "in-progress") {
    return (
      <div className="w-8 h-8 rounded-full bg-cyan/15 border-2 border-cyan flex items-center justify-center flex-shrink-0 relative">
        <div className="w-2.5 h-2.5 rounded-full bg-cyan animate-pulse" />
        <div className="absolute inset-0 rounded-full border-2 border-cyan/30 animate-ping" />
      </div>
    );
  }

  return (
    <div className="w-8 h-8 rounded-full bg-white/5 border-2 border-text-muted flex items-center justify-center flex-shrink-0">
      <div className="w-2 h-2 rounded-full bg-text-muted" />
    </div>
  );
}

function StatusBadge({ status }: { status: RoadmapPhase["status"] }) {
  if (status === "done") {
    return (
      <span className="text-[10px] font-mono uppercase tracking-widest text-accent bg-accent/10 px-2 py-0.5 rounded-full border border-accent/20">
        Terminé
      </span>
    );
  }
  if (status === "in-progress") {
    return (
      <span className="text-[10px] font-mono uppercase tracking-widest text-cyan bg-cyan/10 px-2 py-0.5 rounded-full border border-cyan/20 text-glow-cyan-sm">
        En cours
      </span>
    );
  }
  return (
    <span className="text-[10px] font-mono uppercase tracking-widest text-text-muted bg-white/5 px-2 py-0.5 rounded-full border border-white/10">
      À venir
    </span>
  );
}

function PhaseItem({ phase, index }: { phase: RoadmapPhase; index: number }) {
  const [expanded, setExpanded] = useState(phase.status === "in-progress");
  const isLast = index === ROADMAP_PHASES.length - 1;

  return (
    <ScrollReveal delay={index * 0.08}>
      <div className="flex gap-4">
        {/* Timeline line + icon */}
        <div className="flex flex-col items-center">
          <StatusIcon status={phase.status} />
          {!isLast && (
            <div
              className={`w-px flex-1 my-1 ${
                phase.status === "done" ? "bg-accent/30" : "bg-border-subtle"
              }`}
            />
          )}
        </div>

        {/* Content */}
        <div className={`pb-8 flex-1 ${isLast ? "pb-0" : ""}`}>
          <button
            onClick={() => setExpanded((prev) => !prev)}
            className="w-full text-left group"
          >
            <div className="flex items-center gap-3 flex-wrap">
              <h3
                className={`text-lg font-bold ${
                  phase.status === "upcoming" ? "text-text-muted" : "text-text-primary"
                }`}
              >
                {phase.title}
              </h3>
              <StatusBadge status={phase.status} />
              <svg
                width="12"
                height="12"
                viewBox="0 0 12 12"
                fill="none"
                className={`text-text-muted transition-transform duration-200 ${
                  expanded ? "rotate-180" : ""
                }`}
              >
                <path d="M2 4L6 8L10 4" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
            </div>
            <p
              className={`text-sm mt-1 ${
                phase.status === "upcoming" ? "text-text-muted/60" : "text-text-secondary"
              }`}
            >
              {phase.summary}
            </p>
          </button>

          <AnimatePresence>
            {expanded && (
              <motion.div
                initial={{ height: 0, opacity: 0 }}
                animate={{ height: "auto", opacity: 1 }}
                exit={{ height: 0, opacity: 0 }}
                transition={{ duration: 0.25 }}
                className="overflow-hidden"
              >
                <ul className="mt-3 space-y-1.5 pl-4 border-l border-border-subtle">
                  {phase.details.map((detail, i) => (
                    <li
                      key={i}
                      className={`text-sm flex items-start gap-2 ${
                        phase.status === "upcoming" ? "text-text-muted/50" : "text-text-secondary"
                      }`}
                    >
                      <span className="text-cyan/40 mt-1.5 flex-shrink-0">
                        <svg width="6" height="6" viewBox="0 0 6 6">
                          <rect width="6" height="6" rx="1" fill="currentColor" />
                        </svg>
                      </span>
                      {detail}
                    </li>
                  ))}
                </ul>
              </motion.div>
            )}
          </AnimatePresence>
        </div>
      </div>
    </ScrollReveal>
  );
}

export function RoadmapSection() {
  return (
    <section id="roadmap" className="py-20 sm:py-24 md:py-32">
      <Container>
        <ScrollReveal>
          <SectionHeading
            title="Roadmap"
            subtitle="Le chemin parcouru et les horizons à venir."
          />
        </ScrollReveal>

        <div className="max-w-2xl mx-auto">
          {ROADMAP_PHASES.map((phase, i) => (
            <PhaseItem key={phase.id} phase={phase} index={i} />
          ))}
        </div>
      </Container>
    </section>
  );
}
