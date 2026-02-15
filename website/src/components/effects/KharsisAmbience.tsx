"use client";

import { useFaction } from "@/lib/faction";
import { useEffect, useState } from "react";

interface Ember {
  id: number;
  left: number;
  duration: number;
  delay: number;
  size: number;
  color: string;
  side: "left" | "right";
}

function generateEmbers(count: number): Ember[] {
  const embers: Ember[] = [];
  const colors = [
    "rgba(255, 100, 20, 0.7)",
    "rgba(255, 60, 10, 0.6)",
    "rgba(255, 140, 40, 0.5)",
    "rgba(200, 40, 0, 0.6)",
    "rgba(255, 80, 0, 0.8)",
  ];

  for (let i = 0; i < count; i++) {
    const side = i % 2 === 0 ? "left" : "right";
    embers.push({
      id: i,
      left: side === "left" ? Math.random() * 80 : 0,
      duration: 8 + Math.random() * 12,
      delay: Math.random() * 15,
      size: 2 + Math.random() * 3,
      color: colors[Math.floor(Math.random() * colors.length)],
      side,
    });
  }
  return embers;
}

export function KharsisAmbience() {
  const { faction } = useFaction();
  const [embers, setEmbers] = useState<Ember[]>([]);

  useEffect(() => {
    if (faction === "kharsis") {
      setEmbers(generateEmbers(16));
    } else {
      setEmbers([]);
    }
  }, [faction]);

  if (faction !== "kharsis") return null;

  return (
    <>
      {/* Warm vignette overlay */}
      <div className="kharsis-vignette" />

      {/* Side heat glows with animation */}
      <div
        className="fixed top-0 bottom-0 left-0 w-[120px] pointer-events-none z-30"
        style={{ animation: "ember-pulse-left 6s ease-in-out infinite" }}
      />
      <div
        className="fixed top-0 bottom-0 right-0 w-[120px] pointer-events-none z-30"
        style={{ animation: "ember-pulse-right 6s ease-in-out infinite 3s" }}
      />

      {/* Floating ember particles on edges */}
      {embers.map((ember) => (
        <div
          key={ember.id}
          className="kharsis-ember"
          style={{
            bottom: "-10px",
            ...(ember.side === "left"
              ? { left: `${ember.left}px` }
              : { right: `${ember.left}px` }),
            width: `${ember.size}px`,
            height: `${ember.size}px`,
            backgroundColor: ember.color,
            boxShadow: `0 0 ${ember.size * 2}px ${ember.color}`,
            animationDuration: `${ember.duration}s`,
            animationDelay: `${ember.delay}s`,
          }}
        />
      ))}
    </>
  );
}
