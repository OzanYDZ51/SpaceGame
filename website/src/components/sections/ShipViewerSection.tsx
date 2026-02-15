"use client";

import { useState, Suspense, useRef } from "react";
import { Canvas, useFrame } from "@react-three/fiber";
import { OrbitControls, useGLTF, Environment, ContactShadows } from "@react-three/drei";
import { Container } from "@/components/ui/Container";
import { SectionHeading } from "@/components/ui/SectionHeading";
import { ScrollReveal } from "@/components/effects/ScrollReveal";
import { SHIPS } from "@/lib/constants";
import type { ShipData } from "@/lib/constants";
import * as THREE from "three";

function ShipModel({ ship }: { ship: ShipData }) {
  const { scene } = useGLTF(ship.modelPath);
  const ref = useRef<THREE.Group>(null!);

  useFrame((_, delta) => {
    if (ref.current) {
      ref.current.rotation.y += delta * 0.15;
    }
  });

  return (
    <group ref={ref} scale={ship.scale}>
      <primitive object={scene.clone()} />
    </group>
  );
}

function LoadingSpinner() {
  return (
    <div className="absolute inset-0 flex items-center justify-center">
      <div className="w-10 h-10 border-2 border-cyan/30 border-t-cyan rounded-full animate-spin" />
    </div>
  );
}

function ShipTab({
  ship,
  isActive,
  onClick,
}: {
  ship: ShipData;
  isActive: boolean;
  onClick: () => void;
}) {
  return (
    <button
      onClick={onClick}
      className={`
        px-4 py-2.5 text-sm font-medium uppercase tracking-wider transition-all duration-200 border-b-2
        ${isActive
          ? "text-cyan border-cyan text-glow-cyan-sm"
          : "text-text-muted border-transparent hover:text-text-secondary hover:border-cyan/20"
        }
      `}
    >
      {ship.name}
    </button>
  );
}

function LockedTab() {
  return (
    <div className="px-4 py-2.5 text-sm font-medium uppercase tracking-wider text-text-muted border-b-2 border-transparent flex items-center gap-2 cursor-default">
      <svg width="12" height="14" viewBox="0 0 12 14" fill="none">
        <rect x="0.5" y="5.5" width="11" height="8" rx="1.5" stroke="currentColor" strokeOpacity="0.4" />
        <path d="M3 5.5V4C3 2.34 4.34 1 6 1C7.66 1 9 2.34 9 4V5.5" stroke="currentColor" strokeOpacity="0.4" strokeLinecap="round" />
      </svg>
      <span>???</span>
    </div>
  );
}

function StatRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex justify-between items-center py-1.5">
      <span className="text-xs uppercase tracking-wider text-text-muted">{label}</span>
      <span className="text-sm font-mono text-cyan">{value}</span>
    </div>
  );
}

export function ShipViewerSection() {
  const [activeIndex, setActiveIndex] = useState(0);
  const activeShip = SHIPS[activeIndex];

  return (
    <section id="ships" className="py-20 sm:py-24 md:py-32 relative">
      <Container>
        <ScrollReveal>
          <SectionHeading
            title="Vaisseaux"
            subtitle="Inspectez les vaisseaux qui vous attendent dans l'univers d'Imperion."
          />
        </ScrollReveal>

        <ScrollReveal delay={0.15}>
          <div className="rounded-xl border border-border-subtle overflow-hidden bg-bg-card backdrop-blur-sm">
            {/* Tabs */}
            <div className="flex items-center border-b border-border-subtle bg-black/30 overflow-x-auto">
              {SHIPS.map((ship, i) => (
                <ShipTab
                  key={ship.id}
                  ship={ship}
                  isActive={i === activeIndex}
                  onClick={() => setActiveIndex(i)}
                />
              ))}
              <LockedTab />
              <div className="flex-1" />
              <span className="px-4 text-xs text-text-muted font-mono hidden sm:block">
                Plus de vaisseaux à découvrir...
              </span>
            </div>

            {/* Content */}
            <div className="grid grid-cols-1 lg:grid-cols-5 min-h-[400px] sm:min-h-[450px]">
              {/* 3D Viewer */}
              <div className="lg:col-span-3 relative bg-gradient-to-b from-black/20 to-transparent">
                <Suspense fallback={<LoadingSpinner />}>
                  <Canvas
                    camera={{ position: [0, 1, activeShip.cameraDistance], fov: 45 }}
                    className="touch-none"
                    gl={{ antialias: true, alpha: true }}
                  >
                    <ambientLight intensity={0.3} />
                    <directionalLight position={[5, 5, 5]} intensity={1} />
                    <directionalLight position={[-3, 2, -2]} intensity={0.4} color="#00c8ff" />
                    <pointLight position={[0, -2, 3]} intensity={0.5} color="#00c8ff" />

                    <ShipModel key={activeShip.id} ship={activeShip} />
                    <ContactShadows position={[0, -1.5, 0]} opacity={0.4} scale={10} blur={2} color="#00c8ff" />

                    <OrbitControls
                      enablePan={false}
                      enableZoom={false}
                      minPolarAngle={Math.PI / 4}
                      maxPolarAngle={Math.PI / 1.5}
                      autoRotate={false}
                    />

                    <Environment preset="night" />
                  </Canvas>
                </Suspense>

                {/* Drag hint */}
                <div className="absolute bottom-3 left-1/2 -translate-x-1/2 flex items-center gap-2 text-text-muted text-xs font-mono pointer-events-none opacity-60">
                  <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
                    <path d="M2 8H14M14 8L10 4M14 8L10 12" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round" strokeLinejoin="round" />
                  </svg>
                  <span>Glisser pour tourner</span>
                </div>
              </div>

              {/* Stats Panel */}
              <div className="lg:col-span-2 p-6 border-t lg:border-t-0 lg:border-l border-border-subtle flex flex-col">
                <div className="mb-4">
                  <span className="text-xs font-mono uppercase tracking-widest text-cyan/60">
                    {activeShip.stats.class}
                  </span>
                  <h3 className="text-2xl font-bold text-text-primary mt-1">
                    {activeShip.name}
                  </h3>
                </div>

                <p className="text-sm text-text-secondary leading-relaxed mb-6">
                  {activeShip.description}
                </p>

                <div className="border-t border-border-subtle pt-4 space-y-0.5">
                  <StatRow label="Vitesse max" value={activeShip.stats.speed} />
                  <StatRow label="Coque" value={activeShip.stats.hull} />
                  <StatRow label="Boucliers" value={activeShip.stats.shields} />
                </div>

                <div className="mt-auto pt-6">
                  <div className="flex items-center gap-2 text-text-muted text-xs">
                    <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
                      <circle cx="7" cy="7" r="6" stroke="currentColor" strokeOpacity="0.4" />
                      <path d="M7 4V7.5L9 9" stroke="currentColor" strokeOpacity="0.4" strokeLinecap="round" />
                    </svg>
                    <span>Armement et modules — à découvrir en jeu</span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </ScrollReveal>
      </Container>
    </section>
  );
}
