import Image from "next/image";
import { links } from "@/lib/content";

export function Footer() {
  return (
    <footer className="border-t border-line px-5 py-10 sm:px-8">
      <div className="mx-auto flex max-w-6xl flex-col gap-6 sm:flex-row sm:items-center sm:justify-between">
        <div className="flex items-center gap-2.5">
          <Image
            src={`${process.env.NEXT_PUBLIC_BASE_PATH ?? ""}/icons/swiftx-192.png`}
            alt=""
            width={20}
            height={20}
            className="rounded-md"
          />
          <span className="text-sm text-muted">
            SwiftX — native screen capture for macOS.
          </span>
        </div>

        <nav className="flex flex-wrap items-center gap-6 text-sm text-muted">
          <a
            href={links.github}
            target="_blank"
            rel="noreferrer"
            className="transition-colors hover:text-ink"
          >
            GitHub
          </a>
          <a
            href={links.roadmap}
            target="_blank"
            rel="noreferrer"
            className="transition-colors hover:text-ink"
          >
            Roadmap
          </a>
          <a
            href={links.releases}
            target="_blank"
            rel="noreferrer"
            className="transition-colors hover:text-ink"
          >
            Releases
          </a>
        </nav>
      </div>

      <p className="mx-auto mt-8 max-w-6xl text-xs leading-relaxed text-muted/80">
        Not affiliated with or endorsed by the ShareX project. ShareX is the
        work of its own authors and contributors.
      </p>
    </footer>
  );
}
