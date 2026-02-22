"use client";

import { useState, useCallback, useEffect } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { Container } from "@/components/ui/Container";
import { SectionHeading } from "@/components/ui/SectionHeading";
import { ScrollReveal } from "@/components/effects/ScrollReveal";
import { SCREENSHOT_DATA } from "@/lib/constants";
import { useI18n } from "@/i18n";
import type { ScreenshotText } from "@/i18n";

type Screenshot = ScreenshotText & {
  src: string;
  category: "space" | "ui";
  span: string;
  index: number;
};

type FilterType = "all" | "space" | "ui";

/* ── Lightbox with prev/next navigation ────────── */

function LightboxModal({
  screenshots,
  currentIndex,
  onClose,
  onNavigate,
}: {
  screenshots: Screenshot[];
  currentIndex: number;
  onClose: () => void;
  onNavigate: (index: number) => void;
}) {
  const shot = screenshots[currentIndex];

  useEffect(() => {
    function handleKey(e: KeyboardEvent) {
      if (e.key === "Escape") onClose();
      if (e.key === "ArrowRight") onNavigate((currentIndex + 1) % screenshots.length);
      if (e.key === "ArrowLeft") onNavigate((currentIndex - 1 + screenshots.length) % screenshots.length);
    }
    window.addEventListener("keydown", handleKey);
    return () => window.removeEventListener("keydown", handleKey);
  }, [currentIndex, screenshots.length, onClose, onNavigate]);

  return (
    <motion.div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/95 backdrop-blur-md cursor-pointer"
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      transition={{ duration: 0.25 }}
      onClick={onClose}
    >
      {/* Counter */}
      <div className="absolute top-6 left-1/2 -translate-x-1/2 font-mono text-xs tracking-[0.3em] text-text-muted uppercase">
        <span className="text-cyan">{String(currentIndex + 1).padStart(2, "0")}</span>
        <span className="mx-2">/</span>
        <span>{String(screenshots.length).padStart(2, "0")}</span>
      </div>

      {/* Close button */}
      <button
        className="absolute top-5 right-5 w-10 h-10 rounded-full border border-white/10 flex items-center justify-center text-text-muted hover:text-cyan hover:border-cyan/50 transition-all duration-300 z-10"
        onClick={onClose}
      >
        <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
          <path d="M1 1L13 13M13 1L1 13" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
        </svg>
      </button>

      {/* Prev arrow */}
      <button
        className="absolute left-4 sm:left-8 top-1/2 -translate-y-1/2 w-12 h-12 rounded-full border border-white/10 flex items-center justify-center text-text-muted hover:text-cyan hover:border-cyan/50 hover:bg-cyan/5 transition-all duration-300 z-10"
        onClick={(e) => { e.stopPropagation(); onNavigate((currentIndex - 1 + screenshots.length) % screenshots.length); }}
      >
        <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
          <path d="M10 3L5 8L10 13" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </button>

      {/* Next arrow */}
      <button
        className="absolute right-4 sm:right-8 top-1/2 -translate-y-1/2 w-12 h-12 rounded-full border border-white/10 flex items-center justify-center text-text-muted hover:text-cyan hover:border-cyan/50 hover:bg-cyan/5 transition-all duration-300 z-10"
        onClick={(e) => { e.stopPropagation(); onNavigate((currentIndex + 1) % screenshots.length); }}
      >
        <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
          <path d="M6 3L11 8L6 13" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </button>

      {/* Image */}
      <AnimatePresence mode="wait">
        <motion.div
          key={currentIndex}
          className="relative max-w-[92vw] max-h-[85vh] cursor-default"
          initial={{ opacity: 0, scale: 0.95 }}
          animate={{ opacity: 1, scale: 1 }}
          exit={{ opacity: 0, scale: 0.95 }}
          transition={{ duration: 0.2 }}
          onClick={(e) => e.stopPropagation()}
        >
          <img
            src={shot.src}
            alt={shot.alt}
            className="max-w-full max-h-[80vh] rounded-lg object-contain shadow-2xl shadow-cyan/5"
          />
          {/* Glow frame */}
          <div className="absolute inset-0 rounded-lg border border-cyan/10 pointer-events-none" />

          {/* Caption */}
          <div className="text-center mt-4">
            <p className="text-text-primary text-sm font-medium">{shot.alt}</p>
            <p className="text-text-muted text-xs font-mono mt-1">{shot.caption}</p>
          </div>
        </motion.div>
      </AnimatePresence>
    </motion.div>
  );
}

/* ── Screenshot Card ───────────────────────────── */

function ScreenshotCard({
  screenshot,
  onClick,
  isHero,
}: {
  screenshot: Screenshot;
  onClick: () => void;
  isHero: boolean;
}) {
  const [imageLoaded, setImageLoaded] = useState(false);
  const [imageError, setImageError] = useState(false);

  return (
    <motion.div
      className={`relative rounded-lg border border-white/[0.06] overflow-hidden cursor-pointer group ${screenshot.span} ${
        isHero ? "aspect-[21/9]" : "aspect-video"
      }`}
      whileHover={{ scale: 1.015 }}
      transition={{ duration: 0.3, ease: "easeOut" }}
      onClick={onClick}
      layout
    >
      {/* Image */}
      {!imageError ? (
        <img
          src={screenshot.src}
          alt={screenshot.alt}
          className={`w-full h-full object-cover transition-all duration-700 group-hover:scale-105 ${
            imageLoaded ? "opacity-100" : "opacity-0"
          }`}
          onLoad={() => setImageLoaded(true)}
          onError={() => setImageError(true)}
          loading={isHero ? "eager" : "lazy"}
        />
      ) : null}

      {/* Loading placeholder */}
      {(!imageLoaded || imageError) && (
        <div className="absolute inset-0 bg-gradient-to-br from-cyan/5 via-bg-secondary to-bg-primary">
          <div className="absolute inset-0 flex items-center justify-center">
            <span className="text-xs font-mono uppercase tracking-[0.2em] text-text-muted">
              {screenshot.alt}
            </span>
          </div>
        </div>
      )}

      {/* Permanent subtle vignette */}
      <div className="absolute inset-0 bg-gradient-to-t from-black/50 via-transparent to-black/20 pointer-events-none" />

      {/* Hover overlay */}
      <div className="absolute inset-0 bg-gradient-to-t from-black/80 via-black/20 to-transparent opacity-0 group-hover:opacity-100 transition-all duration-500 pointer-events-none" />

      {/* Hover glow border */}
      <div className="absolute inset-0 rounded-lg border border-cyan/0 group-hover:border-cyan/30 transition-all duration-500 pointer-events-none" />
      <div className="absolute inset-0 rounded-lg shadow-[inset_0_0_30px_rgba(0,200,255,0)] opacity-0 group-hover:opacity-[0.07] transition-all duration-500 pointer-events-none" />

      {/* Category badge */}
      <div className="absolute top-3 left-3 opacity-0 group-hover:opacity-100 transition-all duration-300 translate-y-1 group-hover:translate-y-0">
        <span className={`text-[10px] font-mono uppercase tracking-[0.2em] px-2.5 py-1 rounded-full border backdrop-blur-sm ${
          screenshot.category === "space"
            ? "text-cyan/90 border-cyan/20 bg-cyan/5"
            : "text-amber-400/90 border-amber-400/20 bg-amber-400/5"
        }`}>
          {screenshot.category === "space" ? "SPACE" : "UI"}
        </span>
      </div>

      {/* Expand icon */}
      <div className="absolute top-3 right-3 w-8 h-8 rounded-full bg-black/30 border border-white/10 flex items-center justify-center opacity-0 group-hover:opacity-100 transition-all duration-300 backdrop-blur-sm">
        <svg width="14" height="14" viewBox="0 0 16 16" fill="none">
          <path d="M6 2H3C2.45 2 2 2.45 2 3V6M10 2H13C13.55 2 14 2.45 14 3V6M6 14H3C2.45 14 2 13.55 2 13V10M10 14H13C13.55 14 14 13.55 14 13V10" stroke="white" strokeWidth="1.5" strokeLinecap="round" />
        </svg>
      </div>

      {/* Caption */}
      <div className="absolute bottom-0 left-0 right-0 p-4 translate-y-2 group-hover:translate-y-0 opacity-0 group-hover:opacity-100 transition-all duration-400">
        <p className="text-sm text-white font-medium drop-shadow-lg">{screenshot.alt}</p>
        <p className="text-xs text-white/60 font-mono mt-0.5">{screenshot.caption}</p>
      </div>
    </motion.div>
  );
}

/* ── Filter Button ─────────────────────────────── */

function FilterButton({
  label,
  active,
  count,
  onClick,
}: {
  label: string;
  active: boolean;
  count: number;
  onClick: () => void;
}) {
  return (
    <button
      onClick={onClick}
      className={`relative px-5 py-2 text-xs font-mono uppercase tracking-[0.2em] rounded-full border transition-all duration-300 ${
        active
          ? "text-cyan border-cyan/40 bg-cyan/10 shadow-[0_0_20px_rgba(0,200,255,0.1)]"
          : "text-text-muted border-white/[0.06] bg-white/[0.02] hover:text-text-secondary hover:border-white/10"
      }`}
    >
      {label}
      <span className={`ml-2 text-[10px] ${active ? "text-cyan/60" : "text-text-muted/50"}`}>
        {count}
      </span>
    </button>
  );
}

/* ── Main Section ──────────────────────────────── */

export function ScreenshotsSection() {
  const { t } = useI18n();
  const [lightboxIndex, setLightboxIndex] = useState<number | null>(null);
  const [filter, setFilter] = useState<FilterType>("all");

  const handleClose = useCallback(() => setLightboxIndex(null), []);
  const handleNavigate = useCallback((i: number) => setLightboxIndex(i), []);

  // Build screenshot array with merged data
  const allScreenshots: Screenshot[] = SCREENSHOT_DATA.map((data, i) => ({
    src: data.src,
    category: data.category,
    span: data.span,
    index: i,
    ...t.screenshots.items[i],
  }));

  const filtered = filter === "all"
    ? allScreenshots
    : allScreenshots.filter((s) => s.category === filter);

  const spaceCount = allScreenshots.filter((s) => s.category === "space").length;
  const uiCount = allScreenshots.filter((s) => s.category === "ui").length;

  return (
    <section id="screenshots" className="py-20 sm:py-28 md:py-36 relative overflow-hidden">
      {/* Ambient background glow */}
      <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[800px] h-[600px] bg-cyan/[0.02] rounded-full blur-[120px] pointer-events-none" />

      <Container>
        <ScrollReveal>
          <SectionHeading
            title={t.screenshots.title}
            subtitle={t.screenshots.subtitle}
          />
        </ScrollReveal>

        {/* Filter bar */}
        <ScrollReveal delay={0.1}>
          <div className="flex items-center justify-center gap-3 mb-10">
            <FilterButton
              label={t.screenshots.filterAll}
              active={filter === "all"}
              count={allScreenshots.length}
              onClick={() => setFilter("all")}
            />
            <FilterButton
              label={t.screenshots.filterSpace}
              active={filter === "space"}
              count={spaceCount}
              onClick={() => setFilter("space")}
            />
            <FilterButton
              label={t.screenshots.filterUi}
              active={filter === "ui"}
              count={uiCount}
              onClick={() => setFilter("ui")}
            />
          </div>
        </ScrollReveal>

        {/* Gallery grid */}
        <motion.div
          className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3 sm:gap-4"
          layout
        >
          <AnimatePresence mode="popLayout">
            {filtered.map((shot, i) => (
              <motion.div
                key={shot.src}
                className={`${shot.span}`}
                initial={{ opacity: 0, scale: 0.95 }}
                animate={{ opacity: 1, scale: 1 }}
                exit={{ opacity: 0, scale: 0.95 }}
                transition={{ duration: 0.35, delay: i * 0.05 }}
                layout
              >
                <ScrollReveal delay={i * 0.06}>
                  <ScreenshotCard
                    screenshot={shot}
                    isHero={shot.index === 0}
                    onClick={() => setLightboxIndex(shot.index)}
                  />
                </ScrollReveal>
              </motion.div>
            ))}
          </AnimatePresence>
        </motion.div>

        {/* Bottom decorative line */}
        <div className="mt-12 flex items-center justify-center gap-4">
          <div className="h-px flex-1 max-w-[100px] bg-gradient-to-r from-transparent to-cyan/20" />
          <span className="text-[10px] font-mono uppercase tracking-[0.3em] text-text-muted">
            {allScreenshots.length} captures
          </span>
          <div className="h-px flex-1 max-w-[100px] bg-gradient-to-l from-transparent to-cyan/20" />
        </div>
      </Container>

      {/* Lightbox */}
      <AnimatePresence>
        {lightboxIndex !== null && (
          <LightboxModal
            screenshots={allScreenshots}
            currentIndex={lightboxIndex}
            onClose={handleClose}
            onNavigate={handleNavigate}
          />
        )}
      </AnimatePresence>
    </section>
  );
}
