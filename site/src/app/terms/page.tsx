import type { Metadata } from "next";
import { Nav } from "@/components/nav";
import { Footer } from "@/components/footer";
import { LegalDoc } from "@/components/legal-doc";
import { terms } from "@/lib/legal";

// Microsoft's app registration takes this URL as the "Terms of service URL".
// Keep the route at `/terms/` for as long as that registration exists.
export const metadata: Metadata = {
  title: `SwiftX — ${terms.title}`,
  description: terms.description,
  openGraph: {
    title: `SwiftX — ${terms.title}`,
    description: terms.description,
    type: "website",
  },
};

export default function TermsPage() {
  return (
    <div className="flex min-h-screen flex-col overflow-x-clip">
      <Nav variant="sub" />
      <main className="flex-1">
        <LegalDoc
          doc={terms}
          other={{ href: "/privacy/", label: "Privacy Policy" }}
        />
      </main>
      <Footer />
    </div>
  );
}
