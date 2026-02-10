import { HeroSection } from "@/components/sections/HeroSection";
import { FeaturesSection } from "@/components/sections/FeaturesSection";
import { UniverseSection } from "@/components/sections/UniverseSection";
import { ScreenshotsSection } from "@/components/sections/ScreenshotsSection";
import { ChangelogSection } from "@/components/sections/ChangelogSection";
import { DownloadSection } from "@/components/sections/DownloadSection";
import { ScanlineOverlay } from "@/components/effects/ScanlineOverlay";

export default function HomePage() {
  return (
    <>
      <HeroSection />
      <FeaturesSection />
      <UniverseSection />
      <ScreenshotsSection />
      <ChangelogSection />
      <DownloadSection />
      <ScanlineOverlay />
    </>
  );
}
