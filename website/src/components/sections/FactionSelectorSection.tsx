"use client";

import { useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { useFaction, type FactionId } from "@/lib/faction";
import { useI18n } from "@/i18n";
import type { FactionText } from "@/i18n";
import { Container } from "@/components/ui/Container";
import { ScrollReveal } from "@/components/effects/ScrollReveal";

const FACTION_STYLE = {
  nova_terra: {
    color: "#00c8ff",
    colorDim: "rgba(0,200,255,0.15)",
    colorGlow: "rgba(0,200,255,0.4)",
    icon: (
      <svg width="48" height="48" viewBox="0 0 48 48" fill="none" stroke="currentColor" strokeWidth="1.5">
        <polygon points="24,4 44,40 4,40" strokeLinejoin="round" />
        <line x1="24" y1="16" x2="24" y2="28" />
        <circle cx="24" cy="33" r="2" fill="currentColor" stroke="none" />
      </svg>
    ),
  },
  kharsis: {
    color: "#ff2244",
    colorDim: "rgba(255,34,68,0.15)",
    colorGlow: "rgba(255,34,68,0.4)",
    icon: (
      <svg width="48" height="48" viewBox="0 0 48 48" fill="none" stroke="currentColor" strokeWidth="1.5">
        <path d="M24 4L4 24L24 44L44 24Z" strokeLinejoin="round" />
        <circle cx="24" cy="24" r="6" />
        <line x1="24" y1="10" x2="24" y2="18" />
        <line x1="24" y1="30" x2="24" y2="38" />
        <line x1="10" y1="24" x2="18" y2="24" />
        <line x1="30" y1="24" x2="38" y2="24" />
      </svg>
    ),
  },
} as const;

function FactionCard({
  factionId,
  factionText,
  hovered,
  otherHovered,
  onHover,
  onLeave,
  onSelect,
  chooseLabel,
}: {
  factionId: FactionId;
  factionText: FactionText;
  hovered: boolean;
  otherHovered: boolean;
  onHover: () => void;
  onLeave: () => void;
  onSelect: () => void;
  chooseLabel: string;
}) {
  const style = FACTION_STYLE[factionId];

  return (
    <motion.button
      className="relative flex flex-col items-center justify-center p-6 sm:p-8 rounded-xl border cursor-pointer overflow-hidden text-center"
      style={{
        borderColor: hovered ? style.colorGlow : "rgba(255,255,255,0.08)",
        background: hovered
          ? `linear-gradient(180deg, ${style.colorDim} 0%, rgba(5,8,16,0.95) 100%)`
          : "rgba(5,8,16,0.8)",
      }}
      onMouseEnter={onHover}
      onMouseLeave={onLeave}
      onClick={onSelect}
      animate={{
        flex: hovered ? 1.4 : otherHovered ? 0.6 : 1,
        opacity: otherHovered ? 0.5 : 1,
      }}
      transition={{ duration: 0.4, ease: "easeOut" }}
      whileTap={{ scale: 0.98 }}
    >
      <motion.div
        className="absolute inset-0 pointer-events-none"
        animate={{
          boxShadow: hovered
            ? `inset 0 0 80px ${style.colorDim}, 0 0 40px ${style.colorDim}`
            : "inset 0 0 0px transparent",
        }}
        transition={{ duration: 0.4 }}
      />

      <div className="relative z-10 flex flex-col items-center gap-4">
        <motion.div
          style={{ color: style.color }}
          animate={{ scale: hovered ? 1.15 : 1 }}
          transition={{ duration: 0.3 }}
        >
          {style.icon}
        </motion.div>

        <div>
          <h3
            className="text-2xl sm:text-3xl font-bold uppercase tracking-wider"
            style={{ color: style.color }}
          >
            {factionText.name}
          </h3>
          <p className="text-xs uppercase tracking-[0.3em] text-text-muted mt-1">
            {factionText.subtitle}
          </p>
        </div>

        <p className="text-sm text-text-secondary leading-relaxed max-w-xs">
          {factionText.description}
        </p>

        <div className="flex flex-wrap justify-center gap-2 mt-2">
          {factionText.traits.map((trait) => (
            <span
              key={trait}
              className="text-xs font-mono px-2 py-0.5 rounded border"
              style={{
                borderColor: `${style.color}33`,
                color: style.color,
                backgroundColor: `${style.color}0d`,
              }}
            >
              {trait}
            </span>
          ))}
        </div>

        <p
          className="text-xs italic mt-2 font-mono tracking-wider"
          style={{ color: `${style.color}99` }}
        >
          &ldquo;{factionText.motto}&rdquo;
        </p>

        <motion.div
          className="mt-3 px-6 py-2 rounded border text-sm font-bold uppercase tracking-wider"
          style={{
            borderColor: style.color,
            color: style.color,
          }}
          animate={{
            backgroundColor: hovered ? `${style.color}22` : "transparent",
          }}
          transition={{ duration: 0.3 }}
        >
          {chooseLabel} {factionText.name}
        </motion.div>
      </div>
    </motion.button>
  );
}

export function FactionSelectorSection() {
  const { faction, setFaction } = useFaction();
  const { t } = useI18n();
  const [hovered, setHovered] = useState<FactionId | null>(null);
  const [justChose, setJustChose] = useState(false);

  if (faction && !justChose) return null;

  const handleSelect = (f: FactionId) => {
    setFaction(f);
    setJustChose(true);
    setTimeout(() => {
      document.getElementById("features")?.scrollIntoView({ behavior: "smooth" });
    }, 400);
  };

  return (
    <AnimatePresence>
      {(!faction || justChose) && (
        <motion.section
          id="faction-select"
          className="relative py-16 sm:py-24"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0, height: 0, marginTop: 0, marginBottom: 0, paddingTop: 0, paddingBottom: 0 }}
          transition={{ duration: 0.6 }}
          onAnimationComplete={() => {
            if (justChose) setJustChose(false);
          }}
        >
          <Container>
            <ScrollReveal>
              <div className="text-center mb-10 sm:mb-14">
                <h2 className="text-3xl sm:text-4xl md:text-5xl font-bold uppercase tracking-wider text-text-primary">
                  {t.faction.title} <span className="text-cyan text-glow-cyan-sm">{t.faction.titleHighlight}</span>
                </h2>
                <p className="mt-4 text-sm sm:text-base text-text-secondary max-w-2xl mx-auto leading-relaxed">
                  {t.faction.backstory}
                </p>
              </div>
            </ScrollReveal>

            <ScrollReveal delay={0.2}>
              <div className="flex flex-col sm:flex-row gap-4 sm:gap-6 min-h-[420px] sm:min-h-[480px]">
                <FactionCard
                  factionId="nova_terra"
                  factionText={t.faction.novaTerra}
                  hovered={hovered === "nova_terra"}
                  otherHovered={hovered === "kharsis"}
                  onHover={() => setHovered("nova_terra")}
                  onLeave={() => setHovered(null)}
                  onSelect={() => handleSelect("nova_terra")}
                  chooseLabel={t.faction.choose}
                />
                <FactionCard
                  factionId="kharsis"
                  factionText={t.faction.kharsis}
                  hovered={hovered === "kharsis"}
                  otherHovered={hovered === "nova_terra"}
                  onHover={() => setHovered("kharsis")}
                  onLeave={() => setHovered(null)}
                  onSelect={() => handleSelect("kharsis")}
                  chooseLabel={t.faction.choose}
                />
              </div>
            </ScrollReveal>
          </Container>
        </motion.section>
      )}
    </AnimatePresence>
  );
}
