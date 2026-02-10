"use client";

import { motion } from "framer-motion";
import { StarfieldCanvas } from "@/components/effects/StarfieldCanvas";
import { Badge } from "@/components/ui/Badge";
import { Button } from "@/components/ui/Button";
import { Container } from "@/components/ui/Container";

export function HeroSection() {
  return (
    <section
      id="hero"
      className="relative min-h-screen flex items-center justify-center overflow-hidden"
    >
      {/* Starfield background */}
      <StarfieldCanvas />

      {/* Gradient overlay */}
      <div className="absolute inset-0 bg-gradient-to-b from-bg-primary/30 via-transparent to-bg-primary pointer-events-none" />

      <Container className="relative z-10 text-center py-20">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.8, delay: 0.2 }}
        >
          <Badge className="mb-8">Alpha 0.1 — Accès anticipé</Badge>
        </motion.div>

        <motion.h1
          className="text-6xl sm:text-7xl md:text-8xl lg:text-9xl font-bold uppercase tracking-wider leading-none"
          initial={{ opacity: 0, y: 30 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.8, delay: 0.4 }}
        >
          <span className="text-cyan text-glow-cyan">Imperion</span>
          <br />
          <span className="text-text-primary text-4xl sm:text-5xl md:text-6xl tracking-[0.4em]">
            Online
          </span>
        </motion.h1>

        <motion.p
          className="mt-6 text-lg sm:text-xl text-text-secondary max-w-xl mx-auto"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ duration: 0.8, delay: 0.7 }}
        >
          Explorez. Commercez. Conquérez.
          <br />
          Un univers persistant vous attend.
        </motion.p>

        <motion.div
          className="mt-10 flex flex-col sm:flex-row items-center justify-center gap-4"
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6, delay: 1.0 }}
        >
          <Button href="#download" className="text-base px-8 py-3">
            Télécharger le launcher
          </Button>
          <Button variant="outline" href="#features" className="text-base px-8 py-3">
            Découvrir le jeu
          </Button>
        </motion.div>
      </Container>

      {/* Scroll indicator */}
      <motion.div
        className="absolute bottom-8 left-1/2 -translate-x-1/2"
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 1.5 }}
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
