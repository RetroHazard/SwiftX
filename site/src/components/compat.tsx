"use client";

import { motion } from "motion/react";
import { links } from "@/lib/content";

const carried = [
  { file: ".sxcu", what: "Custom uploaders" },
  { file: ".sxie", what: "Effect presets" },
  { file: ".json", what: "History database" },
];

export function Compat() {
  return (
    <section className="px-5 py-20 sm:px-8 lg:py-24">
      <motion.div
        initial={{ opacity: 0, y: 16 }}
        whileInView={{ opacity: 1, y: 0 }}
        viewport={{ once: true, margin: "-70px" }}
        transition={{ duration: 0.55 }}
        className="marquee-corners relative mx-auto max-w-6xl rounded-xl border border-line bg-panel px-6 py-10 sm:px-10"
      >
        <div className="grid items-center gap-10 lg:grid-cols-[minmax(0,1fr)_auto]">
          <div>
            <div className="eyebrow">Coming from Windows</div>
            <h2 className="display-sm mt-3 text-[clamp(1.5rem,2.8vw,2.1rem)]">
              Your ShareX config comes with you
            </h2>
            <p className="mt-4 max-w-[56ch] text-[16px] leading-relaxed text-muted">
              SwiftX reads the same uploader and preset files, keeps a
              compatible history database, and works with the browser
              extensions you already have installed. The destinations you spent
              an evening getting right keep working.{" "}
              <a
                href={links.upstream}
                target="_blank"
                rel="noreferrer"
                className="text-ink-soft underline decoration-line-strong underline-offset-4 transition-colors hover:text-accent hover:decoration-accent"
              >
                ShareX
              </a>{" "}
              is a separate project — SwiftX is not affiliated with it.
            </p>
          </div>

          <div className="flex flex-col gap-2.5">
            {carried.map((c) => (
              <div
                key={c.file}
                className="flex items-center gap-3 rounded-lg border border-line bg-panel-2 px-4 py-3"
              >
                <span className="readout rounded bg-accent/12 px-2 py-1 text-[12px] font-semibold text-accent">
                  {c.file}
                </span>
                <span className="text-[13px] text-ink-soft">{c.what}</span>
              </div>
            ))}
          </div>
        </div>
      </motion.div>
    </section>
  );
}
