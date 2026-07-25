"use client";

import { motion } from "motion/react";
import type { ReactNode } from "react";

export function Panel({
  title,
  description,
  children,
  className = "",
  delay = 0,
}: {
  title: string;
  description: string;
  children: ReactNode;
  className?: string;
  delay?: number;
}) {
  return (
    <motion.article
      initial={{ opacity: 0, y: 16 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: "-70px" }}
      transition={{ duration: 0.5, delay }}
      className={`flex flex-col overflow-hidden rounded-xl border border-line bg-panel ${className}`}
    >
      <div className="relative flex-1 overflow-hidden bg-panel-2/70 p-5">
        {children}
      </div>
      <div className="border-t border-line p-5">
        <h3 className="display-sm text-[17px]">{title}</h3>
        <p className="mt-1.5 text-sm leading-relaxed text-muted">
          {description}
        </p>
      </div>
    </motion.article>
  );
}
