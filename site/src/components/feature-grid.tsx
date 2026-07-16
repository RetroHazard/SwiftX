"use client";

import { motion } from "motion/react";
import { features } from "@/lib/content";
import { iconMap } from "@/components/icon-map";
import { SpotlightCard } from "@/components/spotlight-card";

export function FeatureGrid() {
  return (
    <section id="features" className="relative px-4 py-28">
      <div className="mx-auto max-w-5xl">
        <div className="mx-auto max-w-xl text-center">
          <h2 className="text-3xl font-semibold tracking-tight text-white sm:text-4xl">
            Everything ShareX does. Nothing it shouldn&rsquo;t.
          </h2>
          <p className="mt-3 text-white/55">
            Every core workflow rebuilt on native macOS frameworks instead of
            emulated Win32 behavior.
          </p>
        </div>

        <div className="mt-14 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {features.map((feature, i) => {
            const Icon = iconMap[feature.icon];
            return (
              <motion.div
                key={feature.title}
                initial={{ opacity: 0, y: 16 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true, margin: "-60px" }}
                transition={{ duration: 0.5, delay: (i % 3) * 0.08 }}
              >
                <SpotlightCard className="h-full p-6">
                  <div className="flex h-9 w-9 items-center justify-center rounded-lg border border-white/10 bg-white/5 text-white/80">
                    <Icon size={17} />
                  </div>
                  <h3 className="mt-4 text-[15px] font-medium text-white">
                    {feature.title}
                  </h3>
                  <p className="mt-2 text-sm leading-relaxed text-white/50">
                    {feature.description}
                  </p>
                </SpotlightCard>
              </motion.div>
            );
          })}
        </div>
      </div>
    </section>
  );
}
