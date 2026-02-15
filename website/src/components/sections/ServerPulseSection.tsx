"use client";

import { useEffect, useState, useRef } from "react";
import { motion, useInView } from "framer-motion";
import { API_URL } from "@/lib/constants";

type ServerStats = {
  players_online: number;
  players_total: number;
  clans_total: number;
  server_status: "online" | "offline";
  last_event?: {
    event_type: string;
    actor_name: string;
    target_name: string;
    system_id: number;
    created_at: string;
  } | null;
};

function AnimatedNumber({ value, suffix = "" }: { value: number; suffix?: string }) {
  const ref = useRef<HTMLSpanElement>(null);
  const isInView = useInView(ref, { once: true });
  const [display, setDisplay] = useState(0);

  useEffect(() => {
    if (!isInView) return;
    const duration = 1200;
    const start = Date.now();
    const from = 0;

    const tick = () => {
      const elapsed = Date.now() - start;
      const progress = Math.min(elapsed / duration, 1);
      const eased = 1 - Math.pow(1 - progress, 3);
      setDisplay(Math.round(from + (value - from) * eased));
      if (progress < 1) requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  }, [value, isInView]);

  return (
    <span ref={ref} className="font-mono text-cyan tabular-nums">
      {display.toLocaleString()}{suffix}
    </span>
  );
}

function StatusDot({ status }: { status: "online" | "offline" }) {
  const isOnline = status === "online";
  return (
    <span className="relative flex h-2.5 w-2.5">
      {isOnline && (
        <span className="absolute inline-flex h-full w-full rounded-full bg-accent opacity-75 animate-ping" />
      )}
      <span
        className={`relative inline-flex rounded-full h-2.5 w-2.5 ${
          isOnline ? "bg-accent" : "bg-danger"
        }`}
      />
    </span>
  );
}

function formatEvent(event: NonNullable<ServerStats["last_event"]>): string {
  const type = event.event_type;
  if (type === "kill" || type === "player_kill") {
    return `${event.actor_name} a détruit le vaisseau de ${event.target_name}`;
  }
  if (type === "player_join") {
    return `${event.actor_name} a rejoint l'univers`;
  }
  return `${event.actor_name || "Quelqu'un"} — activité détectée`;
}

export function ServerPulseSection() {
  const [stats, setStats] = useState<ServerStats | null>(null);
  const [error, setError] = useState(false);

  useEffect(() => {
    let cancelled = false;

    const fetchStats = async () => {
      try {
        const res = await fetch(`${API_URL}/api/v1/public/stats`);
        if (!res.ok) throw new Error("fetch failed");
        const data = await res.json();
        if (!cancelled) {
          setStats({ ...data, server_status: "online" });
          setError(false);
        }
      } catch {
        if (!cancelled) {
          setError(true);
          setStats((prev) =>
            prev ? { ...prev, server_status: "offline" } : null
          );
        }
      }
    };

    fetchStats();
    const interval = setInterval(fetchStats, 30_000);
    return () => {
      cancelled = true;
      clearInterval(interval);
    };
  }, []);

  return (
    <section className="py-6 sm:py-8 border-y border-border-subtle bg-gradient-to-r from-transparent via-cyan-faint to-transparent">
      <div className="mx-auto max-w-6xl px-4 sm:px-6 lg:px-8">
        <motion.div
          className="flex flex-wrap items-center justify-center gap-x-8 gap-y-3 sm:gap-x-12"
          initial={{ opacity: 0, y: 10 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          transition={{ duration: 0.5 }}
        >
          {/* Server status */}
          <div className="flex items-center gap-2">
            <StatusDot status={stats?.server_status ?? (error ? "offline" : "online")} />
            <span className="text-xs font-mono uppercase tracking-widest text-text-secondary">
              Serveur {stats?.server_status === "offline" || error ? "hors ligne" : "en ligne"}
            </span>
          </div>

          {/* Separator */}
          <div className="hidden sm:block w-px h-4 bg-border-subtle" />

          {/* Online players */}
          <div className="flex items-center gap-2 text-sm">
            <svg width="14" height="14" viewBox="0 0 14 14" fill="none" className="text-cyan/50">
              <circle cx="7" cy="5" r="2.5" stroke="currentColor" />
              <path d="M2 12.5C2 10.01 4.24 8 7 8C9.76 8 12 10.01 12 12.5" stroke="currentColor" strokeLinecap="round" />
            </svg>
            <AnimatedNumber value={stats?.players_online ?? 0} />
            <span className="text-text-muted text-xs">en ligne</span>
          </div>

          <div className="hidden sm:block w-px h-4 bg-border-subtle" />

          {/* Total players */}
          <div className="flex items-center gap-2 text-sm">
            <svg width="14" height="14" viewBox="0 0 14 14" fill="none" className="text-cyan/50">
              <path d="M5 6C6.1 6 7 5.1 7 4C7 2.9 6.1 2 5 2C3.9 2 3 2.9 3 4C3 5.1 3.9 6 5 6Z" stroke="currentColor" />
              <path d="M9 6C10.1 6 11 5.1 11 4C11 2.9 10.1 2 9 2" stroke="currentColor" strokeLinecap="round" />
              <path d="M1 12C1 9.79 2.79 8 5 8C7.21 8 9 9.79 9 12" stroke="currentColor" strokeLinecap="round" />
              <path d="M9 8C11.21 8 13 9.79 13 12" stroke="currentColor" strokeLinecap="round" />
            </svg>
            <AnimatedNumber value={stats?.players_total ?? 0} />
            <span className="text-text-muted text-xs">inscrits</span>
          </div>

          {/* Last event - only shown if available */}
          {stats?.last_event && (
            <>
              <div className="hidden md:block w-px h-4 bg-border-subtle" />
              <div className="hidden md:flex items-center gap-2 text-xs text-text-muted font-mono max-w-xs truncate">
                <svg width="12" height="12" viewBox="0 0 12 12" fill="none" className="text-warning/50 flex-shrink-0">
                  <path d="M6 1L11 10H1L6 1Z" stroke="currentColor" strokeLinejoin="round" />
                </svg>
                <span className="truncate">{formatEvent(stats.last_event)}</span>
              </div>
            </>
          )}
        </motion.div>
      </div>
    </section>
  );
}
