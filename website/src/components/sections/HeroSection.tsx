"use client";

import { motion } from "framer-motion";
import { StarfieldCanvas } from "@/components/effects/StarfieldCanvas";
import { Badge } from "@/components/ui/Badge";
import { Button } from "@/components/ui/Button";
import { Container } from "@/components/ui/Container";
import { useFaction } from "@/lib/faction";
import { useI18n } from "@/i18n";

export function HeroSection() {
  const { faction } = useFaction();
  const { t } = useI18n();

  const tagline = faction === "nova_terra"
    ? t.hero.taglineNovaTerra
    : faction === "kharsis"
      ? t.hero.taglineKharsis
      : t.hero.taglineDefault;

  const subtitle = faction === "nova_terra"
    ? t.hero.subtitleNovaTerra
    : faction === "kharsis"
      ? t.hero.subtitleKharsis
      : t.hero.subtitleDefault;

  return (
    <section
      id="hero"
      className="relative min-h-screen flex items-center justify-center overflow-hidden"
    >
      <StarfieldCanvas />

      <div className="absolute inset-0 bg-gradient-to-b from-bg-primary/30 via-transparent to-bg-primary pointer-events-none" />

      {/* Animated radial pulse */}
      <motion.div
        className="absolute inset-0 flex items-center justify-center pointer-events-none"
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 0.5, duration: 1.5 }}
      >
        <motion.div
          className="w-[300px] h-[300px] sm:w-[600px] sm:h-[600px] rounded-full bg-cyan/[0.04] blur-[80px] sm:blur-[140px]"
          animate={{
            scale: [1, 1.2, 1],
            opacity: [0.4, 0.7, 0.4],
          }}
          transition={{ duration: 6, repeat: Infinity, ease: "easeInOut" }}
        />
      </motion.div>

      <Container className="relative z-10 text-center py-20 px-6">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.8, delay: 0.2 }}
        >
          <Badge className="mb-6 sm:mb-8">{t.hero.badge}</Badge>
        </motion.div>

        {/* Title */}
        <motion.h1
          className="text-5xl sm:text-6xl md:text-7xl lg:text-8xl xl:text-9xl font-bold uppercase tracking-wider leading-none"
          initial={{ opacity: 0, y: 30, scale: 0.95 }}
          animate={{ opacity: 1, y: 0, scale: 1 }}
          transition={{ duration: 1, delay: 0.4, ease: "easeOut" }}
        >
          <motion.span
            className="text-cyan text-glow-cyan inline-block"
            animate={{
              textShadow: faction === "kharsis"
                ? [
                    "0 0 10px rgba(255,34,68,0.6), 0 0 30px rgba(255,80,0,0.3), 0 0 60px rgba(255,34,68,0.15)",
                    "0 0 15px rgba(255,34,68,0.8), 0 0 40px rgba(255,120,20,0.5), 0 0 80px rgba(255,60,0,0.25)",
                    "0 0 10px rgba(255,34,68,0.6), 0 0 30px rgba(255,80,0,0.3), 0 0 60px rgba(255,34,68,0.15)",
                  ]
                : [
                    "0 0 10px rgba(0,200,255,0.6), 0 0 30px rgba(0,200,255,0.3), 0 0 60px rgba(0,200,255,0.15)",
                    "0 0 15px rgba(0,200,255,0.8), 0 0 40px rgba(0,200,255,0.5), 0 0 80px rgba(0,200,255,0.25)",
                    "0 0 10px rgba(0,200,255,0.6), 0 0 30px rgba(0,200,255,0.3), 0 0 60px rgba(0,200,255,0.15)",
                  ],
            }}
            transition={{ duration: 3, repeat: Infinity, ease: "easeInOut" }}
          >
            Imperion
          </motion.span>
          <br />
          <motion.span
            className="text-text-primary text-3xl sm:text-4xl md:text-5xl lg:text-6xl tracking-[0.3em] sm:tracking-[0.4em]"
            initial={{ opacity: 0, letterSpacing: "0.1em" }}
            animate={{ opacity: 1, letterSpacing: undefined }}
            transition={{ duration: 1.2, delay: 0.7 }}
          >
            Online
          </motion.span>
        </motion.h1>

        {/* Tagline */}
        <motion.p
          className="mt-6 sm:mt-8 text-lg sm:text-xl md:text-2xl text-text-primary font-medium max-w-lg mx-auto"
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.8, delay: 0.9 }}
        >
          {tagline}
        </motion.p>

        {/* Subtitle */}
        <motion.p
          className="mt-2 text-sm sm:text-base md:text-lg text-text-secondary max-w-xl mx-auto"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ duration: 0.8, delay: 1.1 }}
        >
          {subtitle}
        </motion.p>

        {/* CTA Buttons */}
        <motion.div
          className="mt-8 sm:mt-10 flex flex-col sm:flex-row items-center justify-center gap-3 sm:gap-4"
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6, delay: 1.3 }}
        >
          <Button href="#download" className="w-full sm:w-auto text-sm sm:text-base px-6 sm:px-8 py-3">
            {t.hero.ctaPlay}
          </Button>
          <Button variant="outline" href="#features" className="w-full sm:w-auto text-sm sm:text-base px-6 sm:px-8 py-3">
            {t.hero.ctaDiscover}
          </Button>
        </motion.div>

        {/* Stats bar */}
        <motion.div
          className="mt-12 sm:mt-16 flex flex-wrap items-center justify-center gap-6 sm:gap-10"
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.8, delay: 1.6 }}
        >
          {t.hero.stats.map((stat, i) => (
            <div key={i} className="text-center">
              <div className="text-2xl sm:text-3xl font-bold text-cyan font-mono">
                {stat.value}
              </div>
              <div className="text-xs uppercase tracking-[0.2em] text-text-muted mt-0.5">
                {stat.label}
              </div>
            </div>
          ))}
        </motion.div>
      </Container>

      {/* Scroll indicator */}
      <motion.div
        className="absolute bottom-6 sm:bottom-8 left-1/2 -translate-x-1/2"
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 2.0 }}
      >
        <motion.div
          animate={{ y: [0, 8, 0] }}
          transition={{ duration: 2, repeat: Infinity, ease: "easeInOut" }}
        >
          <svg
            width="24"
            height="24"
            viewBox="0 0 24 24"
            fill="none"
            className="text-cyan/50"
          >
            <path
              d="M7 10L12 15L17 10"
              stroke="currentColor"
              strokeWidth="1.5"
              strokeLinecap="round"
            />
          </svg>
        </motion.div>
      </motion.div>
    </section>
  );
}
