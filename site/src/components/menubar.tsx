"use client";

import { motion } from "motion/react";
import { Camera, Crop, ScanText, Video, Pipette, FolderClock } from "lucide-react";
import { SectionHead } from "@/components/section-head";

const menuItems = [
  { icon: Crop, label: "Capture region", keys: "⌘⇧4" },
  { icon: Camera, label: "Capture window", keys: "⌘⇧5" },
  { icon: Video, label: "Record screen", keys: "⌘⇧6" },
  { icon: ScanText, label: "Grab text on screen", keys: "⌘⇧O" },
  { icon: Pipette, label: "Pick a colour", keys: "⌘⇧C" },
  { icon: FolderClock, label: "Open history", keys: "⌘⇧H" },
];

export function MenuBar() {
  return (
    <section className="border-y border-line bg-panel-2/60 px-5 py-20 sm:px-8 lg:py-28">
      <div className="mx-auto grid max-w-6xl items-center gap-14 lg:grid-cols-[minmax(0,1fr)_minmax(0,0.9fr)] lg:gap-20">
        <div>
          <SectionHead
            eyebrow="Always there"
            title="It lives in the menu bar, not in your Dock"
            lede="SwiftX has no window to find and no app to switch to. It sits in the menu bar waiting for a hotkey, and gets out of the way the moment your link is copied."
          />
          <motion.ul
            initial={{ opacity: 0 }}
            whileInView={{ opacity: 1 }}
            viewport={{ once: true }}
            transition={{ duration: 0.5, delay: 0.15 }}
            className="mt-8 flex flex-col gap-3 text-[15px] text-muted"
          >
            {[
              "Real global hotkeys that fire from any app",
              "Watch a folder and upload anything dropped in it",
              "Drive it from the command line or a sharex:// link",
            ].map((line) => (
              <li key={line} className="flex items-start gap-3">
                <span className="mt-[7px] h-1.5 w-1.5 shrink-0 rounded-full bg-accent" />
                {line}
              </li>
            ))}
          </motion.ul>
        </div>

        {/* menu bar mock */}
        <motion.div
          initial={{ opacity: 0, y: 18 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, margin: "-70px" }}
          transition={{ duration: 0.6, ease: [0.16, 1, 0.3, 1] }}
          className="relative"
        >
          <div className="overflow-hidden rounded-xl border border-line bg-panel shadow-[var(--shadow-lift)]">
            {/* the strip */}
            <div className="flex items-center justify-end gap-3.5 border-b border-line bg-panel-2 px-3 py-1.5">
              {[0, 1].map((i) => (
                <span key={i} className="text-[11px] text-muted">
                  ▮
                </span>
              ))}
              <span className="relative flex h-4 w-4 items-center justify-center rounded bg-accent text-[9px] font-bold text-accent-ink">
                X
              </span>
              <span className="readout text-[10px] text-muted">9:41</span>
            </div>

            {/* the dropdown */}
            <div className="p-1.5">
              {menuItems.map((item, i) => (
                <div
                  key={item.label}
                  className={`flex items-center gap-2.5 rounded-md px-2.5 py-2 ${
                    i === 0 ? "bg-accent text-accent-ink" : "text-ink-soft"
                  }`}
                >
                  <item.icon size={14} className="shrink-0" />
                  <span className="flex-1 text-[13px]">{item.label}</span>
                  <span
                    className={`readout text-[11px] ${
                      i === 0 ? "text-accent-ink/70" : "text-muted"
                    }`}
                  >
                    {item.keys}
                  </span>
                </div>
              ))}
              <div className="my-1.5 h-px bg-line" />
              <div className="flex items-center justify-between px-2.5 py-1.5 text-[12px] text-muted">
                <span>Last upload</span>
                <span className="readout">2.4 MB · 0.8s</span>
              </div>
            </div>
          </div>
        </motion.div>
      </div>
    </section>
  );
}
