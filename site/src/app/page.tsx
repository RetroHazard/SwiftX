import { Nav } from "@/components/nav";
import { Hero } from "@/components/hero";
import { WorkflowStrip } from "@/components/workflow-strip";
import { Features } from "@/components/features";
import { MenuBar } from "@/components/menubar";
import { Compat } from "@/components/compat";
import { Faq } from "@/components/faq";
import { Cta } from "@/components/cta";
import { Footer } from "@/components/footer";

export default function Home() {
  return (
    <div className="flex min-h-screen flex-col overflow-x-clip">
      <Nav />
      <main className="flex-1">
        <Hero />
        <WorkflowStrip />
        <Features />
        <MenuBar />
        <Compat />
        <Faq />
        <Cta />
      </main>
      <Footer />
    </div>
  );
}
