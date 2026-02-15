"use client";

import { motion } from "framer-motion";
import { StarfieldCanvas } from "@/components/effects/StarfieldCanvas";
import { Badge } from "@/components/ui/Badge";
import { Button } from "@/components/ui/Button";
import { Container } from "@/components/ui/Container";
import { useFaction } from "@/lib/faction";

export function HeroSection() {
  const { faction } = useFaction();

  const tagline = faction === "nova_terra"
    ? "Per Aspera Ad Astra.\nLa Confédération vous attend."
    : faction === "kharsis"
      ? "Ignis Fortem Facit.\nLe Dominion vous attend."
      : "Explorez. Commercez. Conquérez.\nUn univers persistant vous attend.";

  return (
    <section
      id="hero"
      className="relative min-h-screen flex items-center justify-center overflow-hidden"
    >
      {/* Starfield background */}
      <StarfieldCanvas />

      {/* Gradient overlay */}
      <div className="absolute inset-0 bg-gradient-to-b from-bg-primary/30 via-transparent to-bg-primary pointer-events-none" />

      {/* Animated radial pulse behind title */}
      <motion.div
        className="absolute inset-0 flex items-center justify-center pointer-events-none"
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 0.5, duration: 1.5 }}
      >
        <motion.div
          className="w-[300px] h-[300px] sm:w-[500px] sm:h-[500px] rounded-full bg-cyan/[0.04] blur-[80px] sm:blur-[120px]"
          animate={{
            scale: [1, 1.15, 1],
            opacity: [0.5, 0.8, 0.5],
          }}
          transition={{ duration: 5, repeat: Infinity, ease: "easeInOut" }}
        />
      </motion.div>

      <Container className="relative z-10 text-center py-20 px-6">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.8, delay: 0.2 }}
        >
          <Badge className="mb-6 sm:mb-8">Alpha 0.1 — Accès anticipé</Badge>
        </motion.div>

        <motion.h1
          className="text-5xl sm:text-6xl md:text-7xl lg:text-8xl xl:text-9xl font-bold uppercase tracking-wider leading-none"
          initial={{ opacity: 0, y: 30, scale: 0.95 }}
          animate={{ opacity: 1, y: 0, scale: 1 }}
          transition={{ duration: 1, delay: 0.4, ease: "easeOut" }}
        >
          <motion.span
            className="text-cyan text-glow-cyan inline-block"
            animate={{
              textShadow: [
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

        <motion.p
          className="mt-4 sm:mt-6 text-base sm:text-lg md:text-xl text-text-secondary max-w-md sm:max-w-xl mx-auto"
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.8, delay: 0.9 }}
        >
          {tagline.split("\n").map((line, i) => (
            <span key={i}>
              {i > 0 && <br />}
              {line}
            </span>
          ))}
        </motion.p>

        <motion.div
          className="mt-8 sm:mt-10 flex flex-col sm:flex-row items-center justify-center gap-3 sm:gap-4"
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6, delay: 1.2 }}
        >
          <Button href="#download" className="w-full sm:w-auto text-sm sm:text-base px-6 sm:px-8 py-3">
            Télécharger le launcher
          </Button>
          <Button variant="outline" href="#features" className="w-full sm:w-auto text-sm sm:text-base px-6 sm:px-8 py-3">
            Découvrir le jeu
          </Button>
        </motion.div>
      </Container>

      {/* Scroll indicator */}
      <motion.div
        className="absolute bottom-6 sm:bottom-8 left-1/2 -translate-x-1/2"
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 1.8 }}
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
