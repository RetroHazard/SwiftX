"use client";

import { motion } from "motion/react";
import type { ReactNode } from "react";

export function SectionHead({
  eyebrow,
  title,
  lede,
  align = "left",
}: {
  eyebrow: string;
  title: ReactNode;
  lede?: ReactNode;
  align?: "left" | "center";
}) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 14 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: "-80px" }}
      transition={{ duration: 0.5 }}
      className={align === "center" ? "mx-auto max-w-2xl text-center" : ""}
    >
      <div className="eyebrow">{eyebrow}</div>
      <h2 className="display-sm mt-3 text-[clamp(1.75rem,3.4vw,2.6rem)]">
        {title}
      </h2>
      {lede ? (
        <p
          className={`mt-4 text-[17px] leading-relaxed text-muted ${
            align === "center" ? "mx-auto max-w-[58ch]" : "max-w-[58ch]"
          }`}
        >
          {lede}
        </p>
      ) : null}
    </motion.div>
  );
}
