import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "SwiftX — native screen capture for macOS",
  description:
    "SwiftX is a native macOS app for screen capture, recording, annotation, image effects, and uploads — built in Swift, inspired by ShareX's workflow.",
  openGraph: {
    title: "SwiftX — native screen capture for macOS",
    description:
      "A native Swift & SwiftUI menu bar app built on ScreenCaptureKit, Vision, and AVFoundation.",
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
