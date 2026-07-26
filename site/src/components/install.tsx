"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { ArrowRight, Check, Copy, Download } from "lucide-react";
import { links, release } from "@/lib/content";

/** The Homebrew one-liner, with the copy affordance the app itself is about. */
export function BrewCommand({ muted = false }: { muted?: boolean }) {
  const [copied, setCopied] = useState(false);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(
    () => () => {
      if (timer.current) clearTimeout(timer.current);
    },
    [],
  );

  const copy = useCallback(async () => {
    try {
      await navigator.clipboard.writeText(release.brewCommand);
      setCopied(true);
      if (timer.current) clearTimeout(timer.current);
      timer.current = setTimeout(() => setCopied(false), 2000);
    } catch {
      /* clipboard blocked — the command is still selectable */
    }
  }, []);

  return (
    <div
      className={`readout flex w-full max-w-md items-center gap-2.5 rounded-lg border border-line bg-panel-2 px-3.5 py-2.5 text-[12.5px] ${
        muted ? "opacity-75" : ""
      }`}
    >
      <span aria-hidden className="text-accent">
        $
      </span>
      <code className="min-w-0 flex-1 truncate text-ink-soft">
        {release.brewCommand}
      </code>
      <button
        type="button"
        onClick={copy}
        aria-label={copied ? "Command copied" : "Copy command"}
        className="flex h-6 w-6 shrink-0 items-center justify-center rounded-md text-muted transition-colors hover:bg-panel hover:text-ink"
      >
        {copied ? (
          <Check size={13} strokeWidth={3} className="text-live" />
        ) : (
          <Copy size={13} />
        )}
      </button>
    </div>
  );
}

/** Download SwiftX for macOS. */
export function PrimaryAction({ large = false }: { large?: boolean }) {
  const size = large ? "px-6 py-3" : "px-5 py-2.5";
  const className = `group flex items-center gap-2 rounded-full bg-accent ${size} text-sm font-semibold text-accent-ink transition-transform hover:scale-[1.025] active:scale-[0.98]`;

  return (
    <a href={release.dmgUrl} className={className}>
      <Download size={15} />
      Download for macOS
      <ArrowRight
        size={14}
        className="transition-transform group-hover:translate-x-0.5"
      />
    </a>
  );
}

/** The closing acquisition block: download first, Homebrew alongside. */
export function InstallActions() {
  return (
    <div className="flex flex-col items-center gap-5">
      <div className="flex flex-wrap items-center justify-center gap-3">
        <PrimaryAction large />
        <a
          href={links.releases}
          target="_blank"
          rel="noreferrer"
          className="flex items-center gap-2 rounded-full border border-line px-6 py-3 text-sm font-medium text-ink-soft transition-colors hover:border-line-strong hover:text-ink"
        >
          All releases
        </a>
      </div>

      <BrewCommand />
      <p className="readout text-[11px] text-muted">
        v{release.version} · {release.minMacOS} · signed and notarized
      </p>
    </div>
  );
}
