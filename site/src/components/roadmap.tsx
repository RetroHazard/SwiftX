"use client";

import { motion } from "motion/react";
import { CheckCircle2, Clock } from "lucide-react";
import { parityPhases, links } from "@/lib/content";

export function Roadmap() {
  return (
    <section id="roadmap" className="relative px-4 py-28">
      <div className="mx-auto max-w-3xl">
        <div className="mx-auto max-w-xl text-center">
          <h2 className="text-3xl font-semibold tracking-tight text-white sm:text-4xl">
            Built phase by phase, tracked in the open
          </h2>
          <p className="mt-3 text-white/55">
            Every phase lands runnable and testable before the next one
            starts.{" "}
            <a
              href={links.parity}
              target="_blank"
              rel="noreferrer"
              className="text-white/80 underline decoration-white/20 underline-offset-4 hover:text-white"
            >
              Full parity tracker &rarr;
            </a>
          </p>
        </div>

        <div className="mt-14 space-y-2.5">
          {parityPhases.map((row, i) => {
            const done = !row.detail.includes("Planned");
            return (
              <motion.div
                key={row.phase}
                initial={{ opacity: 0, x: -12 }}
                whileInView={{ opacity: 1, x: 0 }}
                viewport={{ once: true, margin: "-40px" }}
                transition={{ duration: 0.4, delay: i * 0.04 }}
                className="flex items-start gap-4 rounded-xl border border-white/10 bg-white/[0.03] px-4 py-3.5"
              >
                <div className="mt-0.5 shrink-0">
                  {done ? (
                    <CheckCircle2 size={17} className="text-emerald-400" />
                  ) : (
                    <Clock size={17} className="text-amber-400" />
                  )}
                </div>
                <div className="min-w-0">
                  <div className="flex flex-wrap items-baseline gap-2">
                    <span className="text-xs font-mono text-white/35">
                      Phase {row.phase}
                    </span>
                    <span className="text-sm font-medium text-white">
                      {row.title}
                    </span>
                  </div>
                  <p className="mt-0.5 text-sm text-white/50">{row.detail}</p>
                </div>
              </motion.div>
            );
          })}
        </div>
      </div>
    </section>
  );
}
