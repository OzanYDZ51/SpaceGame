export function ScanlineOverlay() {
  return (
    <div
      className="pointer-events-none fixed inset-0 z-50 opacity-[0.03]"
      style={{
        background:
          "repeating-linear-gradient(0deg, transparent, transparent 2px, rgba(0, 200, 255, 0.08) 2px, rgba(0, 200, 255, 0.08) 4px)",
      }}
    />
  );
}
