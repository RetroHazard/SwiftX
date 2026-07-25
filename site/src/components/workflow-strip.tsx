"use client";

import { motion } from "motion/react";
import { Crop, Link, PenTool, UploadCloud, type LucideIcon } from "lucide-react";
import { workflow } from "@/lib/content";
import { SectionHead } from "@/components/section-head";

const icons: Record<string, LucideIcon> = { Crop, PenTool, UploadCloud, Link };

export function WorkflowStrip() {
  return (
    <section
      id="workflow"
      className="border-y border-line bg-panel-2/60 px-5 py-20 sm:px-8 lg:py-24"
    >
      <div className="mx-auto max-w-6xl">
        <SectionHead
          eyebrow="One motion"
          title="Four beats between seeing it and sending it"
          lede="Every step after the hotkey is something you configured once and never think about again."
        />

        <ol className="mt-12 grid gap-px overflow-hidden rounded-xl border border-line bg-line sm:grid-cols-2 lg:grid-cols-4">
          {workflow.map((step, i) => {
            const Icon = icons[step.icon];
            return (
              <motion.li
                key={step.id}
                initial={{ opacity: 0, y: 12 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true, margin: "-60px" }}
                transition={{ duration: 0.45, delay: i * 0.08 }}
                className="relative flex flex-col bg-panel p-6"
              >
                <div className="flex items-center justify-between">
                  <span className="flex h-9 w-9 items-center justify-center rounded-lg bg-accent/10 text-accent">
                    <Icon size={17} />
                  </span>
                  <span className="readout text-[11px] text-muted">
                    {String(i + 1).padStart(2, "0")}
                  </span>
                </div>
                <div className="eyebrow mt-5 !text-[10px]">{step.label}</div>
                <h3 className="display-sm mt-1.5 text-lg">{step.title}</h3>
                <p className="mt-2 text-sm leading-relaxed text-muted">
                  {step.detail}
                </p>
              </motion.li>
            );
          })}
        </ol>
      </div>
    </section>
  );
}
