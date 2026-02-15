"use client";

import { useFaction } from "@/lib/faction";
import { useEffect, useState } from "react";

interface Ember {
  id: number;
  x: number;
  duration: number;
  delay: number;
  size: number;
  color: string;
}

function generateEmbers(count: number): Ember[] {
  const embers: Ember[] = [];
  const colors = [
    "rgba(255, 100, 20, 0.8)",
    "rgba(255, 60, 10, 0.7)",
    "rgba(255, 140, 40, 0.6)",
    "rgba(200, 40, 0, 0.7)",
    "rgba(255, 80, 0, 0.9)",
    "rgba(255, 180, 60, 0.5)",
  ];

  for (let i = 0; i < count; i++) {
    // Spread across full width but weighted toward edges
    const rand = Math.random();
    const x = rand < 0.35
      ? Math.random() * 15        // left 15%
      : rand > 0.65
        ? 85 + Math.random() * 15  // right 15%
        : Math.random() * 100;     // anywhere (30% of particles)

    embers.push({
      id: i,
      x,
      duration: 6 + Math.random() * 10,
      delay: Math.random() * 12,
      size: 2 + Math.random() * 4,
      color: colors[Math.floor(Math.random() * colors.length)],
    });
  }
  return embers;
}

export function KharsisAmbience() {
  const { faction } = useFaction();
  const [embers, setEmbers] = useState<Ember[]>([]);

  useEffect(() => {
    if (faction === "kharsis") {
      setEmbers(generateEmbers(30));
    } else {
      setEmbers([]);
    }
  }, [faction]);

  if (faction !== "kharsis") return null;

  return (
    <>
      {/* Heavy warm vignette */}
      <div className="kharsis-vignette" />

      {/* Left heat glow — wider and stronger */}
      <div
        className="fixed top-0 bottom-0 left-0 pointer-events-none z-30"
        style={{
          width: "250px",
          animation: "ember-pulse-left 5s ease-in-out infinite",
        }}
      />

      {/* Right heat glow — wider and stronger */}
      <div
        className="fixed top-0 bottom-0 right-0 pointer-events-none z-30"
        style={{
          width: "250px",
          animation: "ember-pulse-right 5s ease-in-out infinite 2.5s",
        }}
      />

      {/* Bottom heat haze */}
      <div
        className="fixed bottom-0 left-0 right-0 h-[200px] pointer-events-none z-30"
        style={{
          background: "linear-gradient(to top, rgba(255, 40, 0, 0.06) 0%, rgba(255, 60, 10, 0.02) 40%, transparent 100%)",
        }}
      />

      {/* Floating ember particles — spread across the page */}
      {embers.map((ember) => (
        <div
          key={ember.id}
          className="kharsis-ember"
          style={{
            bottom: "-10px",
            left: `${ember.x}%`,
            width: `${ember.size}px`,
            height: `${ember.size}px`,
            backgroundColor: ember.color,
            boxShadow: `0 0 ${ember.size * 3}px ${ember.color}, 0 0 ${ember.size * 6}px ${ember.color.replace(/[\d.]+\)$/, "0.3)")}`,
            animationDuration: `${ember.duration}s`,
            animationDelay: `${ember.delay}s`,
          }}
        />
      ))}
    </>
  );
}
