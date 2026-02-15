"use client";

import { useState, useCallback } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { Container } from "@/components/ui/Container";
import { SectionHeading } from "@/components/ui/SectionHeading";
import { ScrollReveal } from "@/components/effects/ScrollReveal";
import { SCREENSHOT_PATHS } from "@/lib/constants";
import { useI18n } from "@/i18n";
import type { ScreenshotText } from "@/i18n";

type Screenshot = ScreenshotText & { src: string };

function LightboxModal({
  screenshot,
  onClose,
}: {
  screenshot: Screenshot;
  onClose: () => void;
}) {
  return (
    <motion.div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/90 backdrop-blur-sm cursor-pointer"
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      transition={{ duration: 0.2 }}
      onClick={onClose}
    >
      <motion.div
        className="relative max-w-[90vw] max-h-[90vh] cursor-default"
        initial={{ scale: 0.9, opacity: 0 }}
        animate={{ scale: 1, opacity: 1 }}
        exit={{ scale: 0.9, opacity: 0 }}
        transition={{ duration: 0.25 }}
        onClick={(e) => e.stopPropagation()}
      >
        <img
          src={screenshot.src}
          alt={screenshot.alt}
          className="max-w-full max-h-[85vh] rounded-lg object-contain"
        />
        <p className="text-center text-text-secondary text-sm mt-3 font-mono">
          {screenshot.caption}
        </p>
        <button
          className="absolute -top-3 -right-3 w-8 h-8 rounded-full bg-bg-secondary border border-border-subtle flex items-center justify-center text-text-muted hover:text-cyan hover:border-cyan transition-colors"
          onClick={onClose}
        >
          <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
            <path d="M1 1L13 13M13 1L1 13" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
          </svg>
        </button>
      </motion.div>
    </motion.div>
  );
}

function ScreenshotCard({
  screenshot,
  index,
  onClick,
}: {
  screenshot: Screenshot;
  index: number;
  onClick: () => void;
}) {
  const [imageLoaded, setImageLoaded] = useState(false);
  const [imageError, setImageError] = useState(false);

  const gradients = [
    "from-cyan/20 via-blue-900/30 to-purple-900/20",
    "from-red-900/20 via-orange-900/20 to-cyan/10",
    "from-cyan/10 via-teal-900/20 to-blue-900/20",
    "from-purple-900/20 via-cyan/15 to-blue-900/20",
    "from-amber-900/20 via-cyan/10 to-teal-900/20",
  ];

  return (
    <motion.div
      className="relative aspect-video rounded-lg border border-border-subtle overflow-hidden cursor-pointer group"
      whileHover={{ scale: 1.02, borderColor: "rgba(0, 200, 255, 0.4)" }}
      transition={{ duration: 0.2 }}
      onClick={onClick}
    >
      {!imageError ? (
        <img
          src={screenshot.src}
          alt={screenshot.alt}
          className={`w-full h-full object-cover transition-opacity duration-300 ${
            imageLoaded ? "opacity-100" : "opacity-0"
          }`}
          onLoad={() => setImageLoaded(true)}
          onError={() => setImageError(true)}
          loading="lazy"
        />
      ) : null}

      {(!imageLoaded || imageError) && (
        <div className={`absolute inset-0 bg-gradient-to-br ${gradients[index % gradients.length]}`}>
          <div className="absolute inset-0 flex items-center justify-center">
            <span className="text-xs font-mono uppercase tracking-[0.2em] text-text-muted">
              {screenshot.alt}
            </span>
          </div>
        </div>
      )}

      <div className="absolute inset-0 bg-gradient-to-t from-black/60 via-transparent to-transparent opacity-0 group-hover:opacity-100 transition-opacity duration-300">
        <div className="absolute bottom-0 left-0 right-0 p-4">
          <p className="text-sm text-text-primary font-medium">{screenshot.caption}</p>
        </div>
        <div className="absolute top-3 right-3 w-8 h-8 rounded-full bg-black/40 border border-white/20 flex items-center justify-center">
          <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
            <path d="M6 2H3C2.45 2 2 2.45 2 3V6M10 2H13C13.55 2 14 2.45 14 3V6M6 14H3C2.45 14 2 13.55 2 13V10M10 14H13C13.55 14 14 13.55 14 13V10" stroke="white" strokeWidth="1.5" strokeLinecap="round" />
          </svg>
        </div>
      </div>
    </motion.div>
  );
}

export function ScreenshotsSection() {
  const { t } = useI18n();
  const [lightboxIndex, setLightboxIndex] = useState<number | null>(null);
  const handleClose = useCallback(() => setLightboxIndex(null), []);

  const screenshots: Screenshot[] = SCREENSHOT_PATHS.map((src, i) => ({
    src,
    ...t.screenshots.items[i],
  }));

  return (
    <section id="screenshots" className="py-20 sm:py-24 md:py-32">
      <Container>
        <ScrollReveal>
          <SectionHeading
            title={t.screenshots.title}
            subtitle={t.screenshots.subtitle}
          />
        </ScrollReveal>

        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {screenshots.slice(0, 2).map((shot, i) => (
            <ScrollReveal key={i} delay={i * 0.1} className={i === 0 ? "sm:col-span-1 lg:col-span-2" : ""}>
              <ScreenshotCard
                screenshot={shot}
                index={i}
                onClick={() => setLightboxIndex(i)}
              />
            </ScrollReveal>
          ))}
          {screenshots.slice(2).map((shot, i) => (
            <ScrollReveal key={i + 2} delay={(i + 2) * 0.1}>
              <ScreenshotCard
                screenshot={shot}
                index={i + 2}
                onClick={() => setLightboxIndex(i + 2)}
              />
            </ScrollReveal>
          ))}
        </div>
      </Container>

      <AnimatePresence>
        {lightboxIndex !== null && (
          <LightboxModal
            screenshot={screenshots[lightboxIndex]}
            onClose={handleClose}
          />
        )}
      </AnimatePresence>
    </section>
  );
}
