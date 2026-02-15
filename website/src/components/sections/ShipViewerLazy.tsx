"use client";

import dynamic from "next/dynamic";

const ShipViewerSection = dynamic(
  () =>
    import("@/components/sections/ShipViewerSection").then(
      (mod) => mod.ShipViewerSection
    ),
  {
    ssr: false,
    loading: () => (
      <section id="ships" className="py-20 sm:py-24 md:py-32">
        <div className="mx-auto max-w-6xl px-4 sm:px-6 lg:px-8">
          <div className="h-[450px] rounded-xl border border-border-subtle bg-bg-card flex items-center justify-center">
            <div className="w-10 h-10 border-2 border-cyan/30 border-t-cyan rounded-full animate-spin" />
          </div>
        </div>
      </section>
    ),
  }
);

export function ShipViewerLazy() {
  return <ShipViewerSection />;
}
