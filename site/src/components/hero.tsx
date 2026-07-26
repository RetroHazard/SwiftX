"use client";

import { motion } from "motion/react";
import { links, release } from "@/lib/content";
import { CaptureOverlay } from "@/components/capture-overlay";
import { PrimaryAction } from "@/components/install";

const rise = {
  hidden: { opacity: 0, y: 14 },
  show: { opacity: 1, y: 0 },
};

export function Hero() {
  return (
    <section id="top" className="relative overflow-hidden">
      {/* one soft warm bloom behind the capture, so the accent has somewhere
          to come from without turning into a gradient wash */}
      <div
        aria-hidden
        className="pointer-events-none absolute right-[-10%] top-[-25%] h-[42rem] w-[42rem] rounded-full opacity-[0.14] blur-3xl"
        style={{
          background:
            "radial-gradient(circle at center, var(--accent-hot), transparent 62%)",
        }}
      />

      <div className="relative mx-auto grid max-w-6xl items-center gap-14 px-5 pb-20 pt-16 sm:px-8 lg:grid-cols-[minmax(0,1.05fr)_minmax(0,1.1fr)] lg:gap-14 lg:pb-28 lg:pt-24">
        <motion.div
          initial="hidden"
          animate="show"
          transition={{ staggerChildren: 0.09 }}
        >
          <motion.div
            variants={rise}
            transition={{ duration: 0.5 }}
            className="mb-6 inline-flex items-center gap-2 rounded-full border border-line bg-panel px-3 py-1.5"
          >
            <span className="relative flex h-1.5 w-1.5">
              <span className="absolute inline-flex h-full w-full animate-rec rounded-full bg-accent" />
              <span className="relative inline-flex h-1.5 w-1.5 rounded-full bg-accent" />
            </span>
            <span className="eyebrow !text-[10px] !tracking-[0.14em] text-ink-soft">
              Native macOS menu bar app
            </span>
          </motion.div>

          <motion.h1
            variants={rise}
            transition={{ duration: 0.6 }}
            className="display text-[clamp(2.3rem,4.3vw,3.5rem)]"
          >
            <span className="block whitespace-nowrap">Capture it.</span>
            <span className="block whitespace-nowrap">Mark it up.</span>
            <span className="block whitespace-nowrap text-accent">
              Paste the link.
            </span>
          </motion.h1>

          <motion.p
            variants={rise}
            transition={{ duration: 0.6 }}
            className="mt-6 max-w-[46ch] text-[17px] leading-relaxed text-muted"
          >
            SwiftX takes a screenshot from hotkey to shareable URL without you
            touching another app. Annotation, effects, recording and your own
            upload destinations — one pass, no round trips.
          </motion.p>

          <motion.div
            variants={rise}
            transition={{ duration: 0.6 }}
            className="mt-9 flex flex-wrap items-center gap-3"
          >
            <PrimaryAction />
            <a
              href="#workflow"
              className="rounded-full border border-line px-5 py-2.5 text-sm font-medium text-ink-soft transition-colors hover:border-line-strong hover:text-ink"
            >
              See how it works
            </a>
          </motion.div>

          {/* The honest status line — everything the old roadmap section was
              actually telling people, in one sentence. */}
          <motion.p
            variants={rise}
            transition={{ duration: 0.6 }}
            className="mt-6 text-[13px] leading-relaxed text-muted"
          >
            {release.status === "released" ? (
              <>
                Signed, notarized and on Homebrew. Capture, editing,
                recording and uploads all work today —{" "}
                <a
                  href={links.parity}
                  target="_blank"
                  rel="noreferrer"
                  className="text-ink-soft underline decoration-line-strong underline-offset-4 transition-colors hover:text-accent hover:decoration-accent"
                >
                  see what&rsquo;s next
                </a>
                .
              </>
            ) : (
              <>
                Pre-release. Capture, editing, recording and uploads all work
                today; signed builds and a Homebrew cask land with the first
                release —{" "}
                <a
                  href={links.parity}
                  target="_blank"
                  rel="noreferrer"
                  className="text-ink-soft underline decoration-line-strong underline-offset-4 transition-colors hover:text-accent hover:decoration-accent"
                >
                  track what&rsquo;s left
                </a>
                .
              </>
            )}
          </motion.p>
        </motion.div>

        <motion.div
          initial={{ opacity: 0, y: 22, scale: 0.98 }}
          animate={{ opacity: 1, y: 0, scale: 1 }}
          transition={{ duration: 0.8, delay: 0.15, ease: [0.16, 1, 0.3, 1] }}
        >
          <CaptureOverlay />
        </motion.div>
      </div>
    </section>
  );
}
