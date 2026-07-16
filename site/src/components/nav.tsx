"use client";

import Image from "next/image";
import { links } from "@/lib/content";
import { GithubMark } from "@/components/icons/github-mark";

const navItems = [
  { href: "#features", label: "Features" },
  { href: "#roadmap", label: "Roadmap" },
  { href: "#faq", label: "FAQ" },
];

export function Nav() {
  return (
    <header className="fixed inset-x-0 top-0 z-50 flex justify-center px-4 pt-4">
      <div className="flex w-full max-w-5xl items-center justify-between rounded-full border border-white/10 bg-black/40 px-4 py-2.5 backdrop-blur-xl supports-[backdrop-filter]:bg-black/30">
        <a href="#top" className="flex items-center gap-2">
          <Image
            src={`${process.env.NEXT_PUBLIC_BASE_PATH ?? ""}/icons/swiftx-192.png`}
            alt="SwiftX"
            width={26}
            height={26}
            className="rounded-lg"
          />
          <span className="text-sm font-semibold tracking-tight text-white">
            SwiftX
          </span>
        </a>

        <nav className="hidden items-center gap-6 text-sm text-white/70 md:flex">
          {navItems.map((item) => (
            <a
              key={item.href}
              href={item.href}
              className="transition-colors hover:text-white"
            >
              {item.label}
            </a>
          ))}
        </nav>

        <a
          href={links.github}
          target="_blank"
          rel="noreferrer"
          className="flex items-center gap-1.5 rounded-full bg-white px-3.5 py-1.5 text-sm font-medium text-black transition-transform hover:scale-[1.03] active:scale-[0.98]"
        >
          <GithubMark size={15} />
          GitHub
        </a>
      </div>
    </header>
  );
}
