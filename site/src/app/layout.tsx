import type { Metadata } from "next";
import localFont from "next/font/local";
import "./globals.css";

// Self-hosted via next/font/local so the build never reaches a font CDN —
// the woff2 files ship inside the @fontsource-variable packages.
const display = localFont({
  src: "../../node_modules/@fontsource-variable/archivo/files/archivo-latin-wdth-normal.woff2",
  weight: "100 900",
  style: "normal",
  display: "swap",
  variable: "--font-display-face",
  // Keeps Archivo's width axis live so headings can run expanded.
  declarations: [{ prop: "font-stretch", value: "62% 125%" }],
});

const body = localFont({
  src: "../../node_modules/@fontsource-variable/public-sans/files/public-sans-latin-wght-normal.woff2",
  weight: "100 900",
  style: "normal",
  display: "swap",
  variable: "--font-body",
});

const mono = localFont({
  src: "../../node_modules/@fontsource-variable/jetbrains-mono/files/jetbrains-mono-latin-wght-normal.woff2",
  weight: "100 800",
  style: "normal",
  display: "swap",
  variable: "--font-mono-face",
});

export const metadata: Metadata = {
  title: "SwiftX — screen capture that finishes the job",
  description:
    "Capture, annotate and share in one motion. SwiftX is a native macOS menu bar app for screenshots, screen recording, annotation, image effects and uploads.",
  openGraph: {
    title: "SwiftX — screen capture that finishes the job",
    description:
      "Capture, annotate and share in one motion. A native macOS menu bar app for screenshots, recording, annotation and uploads.",
    type: "website",
  },
};

// Applies a stored theme choice before first paint, so a light-mode visitor
// never sees a dark flash (or the reverse).
const themeScript = `(function(){try{var t=localStorage.getItem("swiftx-theme");if(t==="light"||t==="dark"){document.documentElement.setAttribute("data-theme",t);}}catch(e){}})();`;

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang="en"
      className={`${display.variable} ${body.variable} ${mono.variable} h-full antialiased`}
      suppressHydrationWarning
    >
      <head>
        <script dangerouslySetInnerHTML={{ __html: themeScript }} />
      </head>
      <body className="flex min-h-full flex-col bg-ground text-ink">
        {children}
      </body>
    </html>
  );
}
