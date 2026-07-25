import type { Metadata } from "next";
import { Nav } from "@/components/nav";
import { Footer } from "@/components/footer";
import { LegalDoc } from "@/components/legal-doc";
import { privacy } from "@/lib/legal";

// Google's OAuth verification and Microsoft's app registration both point at
// this URL, so the route must stay `/privacy/` for as long as those app
// registrations exist. Moving it breaks sign-in for every connected account.
export const metadata: Metadata = {
  title: `SwiftX — ${privacy.title}`,
  description: privacy.description,
  openGraph: {
    title: `SwiftX — ${privacy.title}`,
    description: privacy.description,
    type: "website",
  },
};

export default function PrivacyPage() {
  return (
    <div className="flex min-h-screen flex-col overflow-x-clip">
      <Nav variant="sub" />
      <main className="flex-1">
        <LegalDoc
          doc={privacy}
          other={{ href: "/terms/", label: "Terms of Service" }}
        />
      </main>
      <Footer />
    </div>
  );
}
