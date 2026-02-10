"use client";

export function ScanlineOverlay() {
  return (
    <>
      {/* Scanlines */}
      <div
        className="pointer-events-none fixed inset-0 z-50 opacity-[0.03]"
        style={{
          background:
            "repeating-linear-gradient(0deg, transparent, transparent 2px, rgba(0, 200, 255, 0.08) 2px, rgba(0, 200, 255, 0.08) 4px)",
        }}
      />
      {/* Animated sweep line */}
      <div
        className="pointer-events-none fixed inset-0 z-50 opacity-[0.04] animate-scan-sweep"
        style={{
          background:
            "linear-gradient(180deg, transparent 0%, transparent 45%, rgba(0, 200, 255, 0.15) 50%, transparent 55%, transparent 100%)",
          backgroundSize: "100% 200%",
        }}
      />
    </>
  );
}
