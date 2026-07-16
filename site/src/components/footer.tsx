import Image from "next/image";
import { links } from "@/lib/content";

export function Footer() {
  return (
    <footer className="relative border-t border-white/10 px-4 py-10">
      <div className="mx-auto flex max-w-5xl flex-col items-center justify-between gap-4 text-sm text-white/40 sm:flex-row">
        <div className="flex items-center gap-2">
          <Image
            src={`${process.env.NEXT_PUBLIC_BASE_PATH ?? ""}/icons/swiftx-192.png`}
            alt="SwiftX"
            width={18}
            height={18}
            className="rounded-md opacity-80"
          />
          <span>SwiftX &mdash; an independent Swift port of ShareX.</span>
        </div>
        <div className="flex items-center gap-5">
          <a href={links.github} target="_blank" rel="noreferrer" className="hover:text-white/70">
            GitHub
          </a>
          <a href={links.upstream} target="_blank" rel="noreferrer" className="hover:text-white/70">
            Upstream ShareX
          </a>
          <a href={links.roadmap} target="_blank" rel="noreferrer" className="hover:text-white/70">
            Roadmap
          </a>
        </div>
      </div>
    </footer>
  );
}
