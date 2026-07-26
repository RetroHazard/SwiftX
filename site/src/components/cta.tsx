"use client";

import { motion } from "motion/react";
import { release } from "@/lib/content";
import { InstallActions } from "@/components/install";

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
            {`Free and open source, for ${release.minMacOS}.`}
          </p>

          <div className="mt-9">
            <InstallActions />
          </div>
        </div>
      </motion.div>
    </section>
  );
}
