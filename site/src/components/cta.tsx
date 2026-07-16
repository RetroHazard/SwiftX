"use client";

import { motion } from "motion/react";
import { Star } from "lucide-react";
import { links } from "@/lib/content";
import { GithubMark } from "@/components/icons/github-mark";

export function Cta() {
  return (
    <section className="relative px-4 pb-28">
      <motion.div
        initial={{ opacity: 0, y: 16 }}
        whileInView={{ opacity: 1, y: 0 }}
        viewport={{ once: true }}
        transition={{ duration: 0.6 }}
        className="relative mx-auto max-w-4xl overflow-hidden rounded-3xl border border-white/10 bg-gradient-to-b from-white/[0.06] to-white/[0.01] px-8 py-16 text-center"
      >
        <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_50%_0%,rgba(99,102,241,0.25),transparent_60%)]" />
        <div className="relative">
          <Star size={22} className="mx-auto text-white/70" />
          <h2 className="mt-4 text-3xl font-semibold tracking-tight text-white sm:text-4xl">
            Follow the build in real time
          </h2>
          <p className="mx-auto mt-3 max-w-md text-white/55">
            SwiftX ships in the open on GitHub — issues, roadmap, and every
            commit toward feature parity.
          </p>
          <a
            href={links.github}
            target="_blank"
            rel="noreferrer"
            className="mt-8 inline-flex items-center gap-2 rounded-full bg-white px-6 py-3 text-sm font-medium text-black transition-transform hover:scale-[1.03] active:scale-[0.98]"
          >
            <GithubMark size={16} />
            View the repository
          </a>
        </div>
      </motion.div>
    </section>
  );
}
