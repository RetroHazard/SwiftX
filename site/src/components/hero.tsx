"use client";

import { motion } from "motion/react";
import { ArrowRight, Terminal } from "lucide-react";
import { links } from "@/lib/content";
import { MockWindow } from "@/components/mock-window";
import { GithubMark } from "@/components/icons/github-mark";

export function Hero() {
  return (
    <section
      id="top"
      className="relative flex flex-col items-center px-4 pb-16 pt-40 text-center sm:pt-48"
    >
      <motion.div
        initial={{ opacity: 0, y: 12 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.6 }}
        className="inline-flex items-center gap-2 rounded-full border border-white/10 bg-white/5 px-3.5 py-1.5 text-xs text-white/60"
      >
        <span className="relative flex h-1.5 w-1.5">
          <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-emerald-400 opacity-75" />
          <span className="relative inline-flex h-1.5 w-1.5 rounded-full bg-emerald-400" />
        </span>
        Ground-up native rewrite &middot; Swift &amp; SwiftUI
      </motion.div>

      <motion.h1
        initial={{ opacity: 0, y: 18 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.7, delay: 0.1 }}
        className="mt-6 max-w-3xl text-balance text-5xl font-semibold tracking-tight text-white sm:text-6xl md:text-7xl"
      >
        ShareX, rebuilt for
        <span className="bg-gradient-to-r from-indigo-400 via-sky-300 to-fuchsia-400 bg-clip-text text-transparent">
          {" "}
          the Mac.
        </span>
      </motion.h1>

      <motion.p
        initial={{ opacity: 0, y: 18 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.7, delay: 0.2 }}
        className="mt-6 max-w-xl text-balance text-lg text-white/60"
      >
        Capture, record, annotate, and upload — the ShareX workflow you know,
        ported feature-for-feature to a native menu bar app built on
        ScreenCaptureKit, SwiftUI, and Vision.
      </motion.p>

      <motion.div
        initial={{ opacity: 0, y: 18 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.7, delay: 0.3 }}
        className="mt-9 flex flex-wrap items-center justify-center gap-3"
      >
        <a
          href={links.github}
          target="_blank"
          rel="noreferrer"
          className="group flex items-center gap-2 rounded-full bg-white px-5 py-2.5 text-sm font-medium text-black transition-transform hover:scale-[1.03] active:scale-[0.98]"
        >
          <GithubMark size={16} />
          Star on GitHub
          <ArrowRight
            size={14}
            className="transition-transform group-hover:translate-x-0.5"
          />
        </a>
        <a
          href={links.roadmap}
          target="_blank"
          rel="noreferrer"
          className="flex items-center gap-2 rounded-full border border-white/15 bg-white/5 px-5 py-2.5 text-sm font-medium text-white/80 backdrop-blur transition-colors hover:border-white/25 hover:bg-white/10 hover:text-white"
        >
          <Terminal size={15} />
          Read the roadmap
        </a>
      </motion.div>

      <motion.div
        initial={{ opacity: 0, y: 32, scale: 0.97 }}
        animate={{ opacity: 1, y: 0, scale: 1 }}
        transition={{ duration: 0.8, delay: 0.4, ease: [0.16, 1, 0.3, 1] }}
        className="mt-20 w-full max-w-4xl"
      >
        <MockWindow />
      </motion.div>
    </section>
  );
}
