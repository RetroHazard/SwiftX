import { AuroraBackground } from "@/components/aurora-background";
import { Nav } from "@/components/nav";
import { Hero } from "@/components/hero";
import { StatsBand } from "@/components/stats-band";
import { FeatureGrid } from "@/components/feature-grid";
import { Roadmap } from "@/components/roadmap";
import { Faq } from "@/components/faq";
import { Cta } from "@/components/cta";
import { Footer } from "@/components/footer";

export default function Home() {
  return (
    <div className="relative flex min-h-screen flex-col overflow-x-clip">
      <AuroraBackground />
      <Nav />
      <main className="flex-1">
        <Hero />
        <StatsBand />
        <FeatureGrid />
        <Roadmap />
        <Faq />
        <Cta />
      </main>
      <Footer />
    </div>
  );
}
