"use client";

import { motion } from "motion/react";
import { stats } from "@/lib/content";

export function StatsBand() {
  return (
    <section className="relative border-y border-white/10 bg-white/[0.02] px-4 py-14">
      <div className="mx-auto grid max-w-5xl grid-cols-2 gap-8 sm:grid-cols-4">
        {stats.map((stat, i) => (
          <motion.div
            key={stat.label}
            initial={{ opacity: 0, y: 10 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={{ once: true }}
            transition={{ duration: 0.5, delay: i * 0.08 }}
            className="text-center"
          >
            <div className="bg-gradient-to-b from-white to-white/60 bg-clip-text text-3xl font-semibold text-transparent sm:text-4xl">
              {stat.value}
            </div>
            <div className="mt-1.5 text-xs text-white/45 sm:text-sm">
              {stat.label}
            </div>
          </motion.div>
        ))}
      </div>
    </section>
  );
}
