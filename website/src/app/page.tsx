import { HeroSection } from "@/components/sections/HeroSection";
import { FeaturesSection } from "@/components/sections/FeaturesSection";
import { ShipViewerLazy } from "@/components/sections/ShipViewerLazy";
import { UniverseSection } from "@/components/sections/UniverseSection";
import { ServerPulseSection } from "@/components/sections/ServerPulseSection";
import { ScreenshotsSection } from "@/components/sections/ScreenshotsSection";
import { RoadmapSection } from "@/components/sections/RoadmapSection";
import { ChangelogSection } from "@/components/sections/ChangelogSection";
import { DownloadSection } from "@/components/sections/DownloadSection";
import { ScanlineOverlay } from "@/components/effects/ScanlineOverlay";

export default function HomePage() {
  return (
    <>
      <HeroSection />
      <FeaturesSection />
      <ShipViewerLazy />
      <UniverseSection />
      <ServerPulseSection />
      <ScreenshotsSection />
      <RoadmapSection />
      <ChangelogSection />
      <DownloadSection />
      <ScanlineOverlay />
    </>
  );
}
