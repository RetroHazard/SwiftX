import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "SwiftX — ShareX, rebuilt for macOS",
  description:
    "SwiftX is an independent, ground-up native Swift port of ShareX — screen capture, recording, annotation, image effects, and uploads for macOS.",
  openGraph: {
    title: "SwiftX — ShareX, rebuilt for macOS",
    description:
      "A native Swift & SwiftUI port of ShareX built on ScreenCaptureKit, Vision, and AVFoundation.",
    type: "website",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className="h-full antialiased dark">
      <body className="flex min-h-full flex-col bg-[#050505] text-white">
        {children}
      </body>
    </html>
  );
}
