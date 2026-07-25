"use client";

import Image from "next/image";
import { links } from "@/lib/content";
import { GithubMark } from "@/components/icons/github-mark";
import { ThemeToggle } from "@/components/theme-toggle";

const navItems = [
  { href: "#workflow", label: "How it works" },
  { href: "#features", label: "Features" },
  { href: "#faq", label: "FAQ" },
];

export function Nav() {
  return (
    <header className="sticky top-0 z-50 border-b border-line bg-ground/85 backdrop-blur-xl">
      <div className="mx-auto flex h-14 max-w-6xl items-center justify-between gap-6 px-5 sm:px-8">
        <a href="#top" className="flex shrink-0 items-center gap-2.5">
          <Image
            src={`${process.env.NEXT_PUBLIC_BASE_PATH ?? ""}/icons/swiftx-192.png`}
            alt=""
            width={24}
            height={24}
            className="rounded-md"
          />
          <span className="display-sm text-[17px] tracking-tight">SwiftX</span>
        </a>

        <nav className="hidden items-center gap-7 text-sm text-muted md:flex">
          {navItems.map((item) => (
            <a
              key={item.href}
              href={item.href}
              className="transition-colors hover:text-ink"
            >
              {item.label}
            </a>
          ))}
        </nav>

        <div className="flex items-center gap-2.5">
          <ThemeToggle />
          <a
            href={links.github}
            target="_blank"
            rel="noreferrer"
            className="flex items-center gap-1.5 rounded-full border border-line px-3.5 py-1.5 text-sm font-medium text-ink-soft transition-colors hover:border-line-strong hover:text-ink"
          >
            <GithubMark size={14} />
            GitHub
          </a>
        </div>
      </div>
    </header>
  );
}
