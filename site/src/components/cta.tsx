"use client";

import { motion } from "motion/react";
import { ArrowRight, Terminal } from "lucide-react";
import { links } from "@/lib/content";
import { GithubMark } from "@/components/icons/github-mark";

export function Cta() {
  return (
    <section className="px-5 pb-24 pt-4 sm:px-8">
      <motion.div
        initial={{ opacity: 0, y: 16 }}
        whileInView={{ opacity: 1, y: 0 }}
        viewport={{ once: true, margin: "-70px" }}
        transition={{ duration: 0.55 }}
        className="relative mx-auto max-w-6xl overflow-hidden rounded-2xl border border-line bg-panel px-6 py-14 text-center sm:px-10"
      >
        <div
          aria-hidden
          className="pointer-events-none absolute inset-x-0 top-0 h-64 opacity-[0.13]"
          style={{
            background:
              "radial-gradient(60% 100% at 50% 0%, var(--accent-hot), transparent 70%)",
          }}
        />
        <div className="relative">
          <h2 className="display mx-auto max-w-[18ch] text-[clamp(1.9rem,4vw,3rem)]">
            Try it on your own screen
          </h2>
          <p className="mx-auto mt-5 max-w-[52ch] text-[16px] leading-relaxed text-muted">
            SwiftX is pre-release, so there is no signed download yet — but the
            source builds and runs today with Swift Package Manager on macOS 14
            or later.
          </p>

          <div className="mt-9 flex flex-wrap items-center justify-center gap-3">
            <a
              href={links.github}
              target="_blank"
              rel="noreferrer"
              className="group flex items-center gap-2 rounded-full bg-accent px-6 py-3 text-sm font-semibold text-accent-ink transition-transform hover:scale-[1.025] active:scale-[0.98]"
            >
              <GithubMark size={16} />
              Clone the repository
              <ArrowRight
                size={14}
                className="transition-transform group-hover:translate-x-0.5"
              />
            </a>
            <a
              href={links.releases}
              target="_blank"
              rel="noreferrer"
              className="flex items-center gap-2 rounded-full border border-line px-6 py-3 text-sm font-medium text-ink-soft transition-colors hover:border-line-strong hover:text-ink"
            >
              <Terminal size={15} />
              Watch for releases
            </a>
          </div>

          <div className="readout mx-auto mt-9 flex w-fit items-center gap-2 rounded-lg border border-line bg-panel-2 px-4 py-2.5 text-[12px] text-muted">
            <span className="text-accent">$</span>
            <span className="text-ink-soft">
              git clone https://github.com/RetroHazard/SwiftX.git
            </span>
          </div>
        </div>
      </motion.div>
    </section>
  );
}
