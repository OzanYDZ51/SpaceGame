"use client";

import { useState, Suspense, useRef, useEffect, useMemo } from "react";
import { Canvas, useFrame, useThree } from "@react-three/fiber";
import { OrbitControls, useGLTF, Environment, ContactShadows } from "@react-three/drei";
import { Container } from "@/components/ui/Container";
import { SectionHeading } from "@/components/ui/SectionHeading";
import { ScrollReveal } from "@/components/effects/ScrollReveal";
import { SHIP_STRUCTURE, SHIP_STRUCTURE_BY_FACTION } from "@/lib/constants";
import type { ShipStructure } from "@/lib/constants";
import type { ShipText } from "@/i18n";
import { useI18n } from "@/i18n";
import { useFaction } from "@/lib/faction";
import * as THREE from "three";

type MergedShip = ShipStructure & ShipText;

function ShipModel({ ship }: { ship: MergedShip }) {
  const { scene } = useGLTF(ship.modelPath);
  const ref = useRef<THREE.Group>(null!);
  const { camera } = useThree();

  const cloned = useMemo(() => scene.clone(), [scene]);

  useEffect(() => {
    if (!ref.current) return;

    const box = new THREE.Box3().setFromObject(ref.current);
    const center = new THREE.Vector3();
    const size = new THREE.Vector3();
    box.getCenter(center);
    box.getSize(size);

    ref.current.position.set(-center.x, -center.y, -center.z);

    const maxDim = Math.max(size.x, size.y, size.z);
    const fov = (camera as THREE.PerspectiveCamera).fov * (Math.PI / 180);
    const dist = (maxDim / 2) / Math.tan(fov / 2) * 1.6;

    camera.position.set(dist * 0.5, dist * 0.3, dist);
    camera.lookAt(0, 0, 0);
    camera.updateProjectionMatrix();
  }, [cloned, camera]);

  useFrame((_, delta) => {
    if (ref.current) {
      ref.current.rotation.y += delta * 0.15;
    }
  });

  return (
    <group>
      <group ref={ref}>
        <primitive object={cloned} />
      </group>
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
  name,
  isActive,
  onClick,
}: {
  name: string;
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
      {name}
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
  const { faction } = useFaction();
  const { t } = useI18n();

  const structures = faction && SHIP_STRUCTURE_BY_FACTION[faction]
    ? SHIP_STRUCTURE_BY_FACTION[faction]
    : SHIP_STRUCTURE;
  const texts = faction && t.ships.factionShips[faction]
    ? t.ships.factionShips[faction]
    : t.ships.defaultShips;

  const ships: MergedShip[] = structures.map((s, i) => ({ ...s, ...texts[i] }));

  const [activeIndex, setActiveIndex] = useState(0);
  const safeIndex = activeIndex >= ships.length ? 0 : activeIndex;
  const activeShip = ships[safeIndex];
  const rimColor = faction === "kharsis" ? "#ff2244" : "#00c8ff";

  const subtitle = faction === "nova_terra"
    ? t.ships.subtitleNovaTerra
    : faction === "kharsis"
      ? t.ships.subtitleKharsis
      : t.ships.subtitleDefault;

  return (
    <section id="ships" className="py-20 sm:py-24 md:py-32 relative">
      <Container>
        <ScrollReveal>
          <SectionHeading title={t.ships.title} subtitle={subtitle} />
        </ScrollReveal>

        <ScrollReveal delay={0.15}>
          <div className="rounded-xl border border-border-subtle overflow-hidden bg-bg-card backdrop-blur-sm">
            {/* Tabs */}
            <div className="flex items-center border-b border-border-subtle bg-black/30 overflow-x-auto">
              {ships.map((ship, i) => (
                <ShipTab
                  key={ship.id}
                  name={ship.name}
                  isActive={i === safeIndex}
                  onClick={() => setActiveIndex(i)}
                />
              ))}
              <LockedTab />
              <div className="flex-1" />
              <span className="px-4 text-xs text-text-muted font-mono hidden sm:block">
                {t.ships.moreShips}
              </span>
            </div>

            {/* Content */}
            <div className="grid grid-cols-1 lg:grid-cols-5 min-h-[400px] sm:min-h-[450px]">
              {/* 3D Viewer */}
              <div className="lg:col-span-3 relative bg-gradient-to-b from-black/20 to-transparent">
                <Suspense fallback={<LoadingSpinner />}>
                  <Canvas
                    camera={{ position: [0, 2, 10], fov: 40 }}
                    className="touch-none"
                    gl={{ antialias: true, alpha: true }}
                  >
                    <ambientLight intensity={0.4} />
                    <directionalLight position={[5, 8, 5]} intensity={1.2} />
                    <directionalLight position={[-3, 2, -2]} intensity={0.5} color={rimColor} />
                    <pointLight position={[0, -2, 3]} intensity={0.4} color={rimColor} />

                    <ShipModel key={activeShip.id} ship={activeShip} />

                    <OrbitControls
                      target={[0, 0, 0]}
                      enablePan={false}
                      enableZoom={false}
                      minPolarAngle={Math.PI / 6}
                      maxPolarAngle={Math.PI / 1.3}
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
                  <span>{t.ships.dragHint}</span>
                </div>
              </div>

              {/* Stats Panel */}
              <div className="lg:col-span-2 p-6 border-t lg:border-t-0 lg:border-l border-border-subtle flex flex-col">
                <div className="mb-4">
                  <span className="text-xs font-mono uppercase tracking-widest text-cyan/60">
                    {activeShip.statsClass}
                  </span>
                  <h3 className="text-2xl font-bold text-text-primary mt-1">
                    {activeShip.name}
                  </h3>
                </div>

                <p className="text-sm text-text-secondary leading-relaxed mb-6">
                  {activeShip.description}
                </p>

                <div className="border-t border-border-subtle pt-4 space-y-0.5">
                  <StatRow label={t.ships.statLabels.speed} value={activeShip.stats.speed} />
                  <StatRow label={t.ships.statLabels.hull} value={activeShip.stats.hull} />
                  <StatRow label={t.ships.statLabels.shields} value={activeShip.stats.shields} />
                  <StatRow label={t.ships.statLabels.price} value={`${activeShip.stats.price} ¢`} />
                </div>

                <div className="mt-auto pt-6">
                  <div className="flex items-center gap-2 text-text-muted text-xs">
                    <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
                      <circle cx="7" cy="7" r="6" stroke="currentColor" strokeOpacity="0.4" />
                      <path d="M7 4V7.5L9 9" stroke="currentColor" strokeOpacity="0.4" strokeLinecap="round" />
                    </svg>
                    <span>{t.ships.weaponsHint}</span>
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
