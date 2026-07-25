"use client";

import { useEffect } from "react";
import {
  animate,
  motion,
  useMotionValue,
  useReducedMotion,
  useTransform,
} from "motion/react";
import { ShotSample } from "@/components/shot-sample";

/**
 * The hero image: a region capture caught mid-drag.
 *
 * The dimming outside the selection is a single huge box-shadow spread on
 * the selection element itself, which is exactly how a real overlay reads —
 * one crisp rectangle cut out of a darkened screen, no duplicated content.
 */

// Selection geometry, in % of the frame.
const SEL = { left: 14, top: 17, width: 62, height: 55 };
const SHOT = { w: 1920, h: 1080 };

const handles = [
  { x: 0, y: 0 },
  { x: 50, y: 0 },
  { x: 100, y: 0 },
  { x: 0, y: 50 },
  { x: 100, y: 50 },
  { x: 0, y: 100 },
  { x: 50, y: 100 },
  { x: 100, y: 100 },
];

export function CaptureOverlay() {
  const reduce = useReducedMotion();

  const progress = useMotionValue(reduce ? 1 : 0);
  const width = useTransform(progress, (p) => `${SEL.width * p}%`);
  const height = useTransform(progress, (p) => `${SEL.height * p}%`);
  const pxW = useTransform(progress, (p) => Math.round(SHOT.w * p).toString());
  const pxH = useTransform(progress, (p) => Math.round(SHOT.h * p).toString());

  useEffect(() => {
    if (reduce) {
      progress.set(1);
      return;
    }
    const controls = animate(progress, 1, {
      duration: 1.15,
      delay: 0.35,
      ease: [0.16, 1, 0.3, 1],
    });
    return () => controls.stop();
  }, [progress, reduce]);

  return (
    <div className="relative aspect-[16/10] w-full select-none overflow-hidden rounded-xl border border-line bg-[#eef1f6] shadow-[var(--shadow-lift)]">
      {/* the screen being captured */}
      <ShotSample className="absolute inset-0 h-full w-full" />

      {/* crosshair guides, locked to the selection's leading edges */}
      <div
        className="pointer-events-none absolute inset-y-0 w-px bg-accent/40"
        style={{ left: `${SEL.left}%` }}
      />
      <div
        className="pointer-events-none absolute inset-x-0 h-px bg-accent/40"
        style={{ top: `${SEL.top}%` }}
      />

      {/* the selection — its box-shadow dims everything outside it */}
      <motion.div
        className="absolute"
        style={{
          left: `${SEL.left}%`,
          top: `${SEL.top}%`,
          width,
          height,
          boxShadow: "0 0 0 200vmax rgba(6, 9, 14, 0.62)",
        }}
      >
        {/* marching ants */}
        <svg className="absolute -inset-px h-[calc(100%+2px)] w-[calc(100%+2px)] overflow-visible">
          <rect
            x="0.5"
            y="0.5"
            width="calc(100% - 1px)"
            height="calc(100% - 1px)"
            fill="none"
            stroke="var(--accent-hot)"
            strokeWidth="1.5"
          />
          <rect
            x="0.5"
            y="0.5"
            width="calc(100% - 1px)"
            height="calc(100% - 1px)"
            fill="none"
            stroke="rgba(255,255,255,0.85)"
            strokeWidth="1.5"
            strokeDasharray="8 8"
            className="animate-ants"
          />
        </svg>

        {handles.map((h) => (
          <motion.span
            key={`${h.x}-${h.y}`}
            initial={reduce ? false : { opacity: 0, scale: 0.4 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ duration: 0.3, delay: 1.35 }}
            className="absolute h-2 w-2 -translate-x-1/2 -translate-y-1/2 rounded-[1px] border border-white/90 bg-accent-hot shadow-sm"
            style={{ left: `${h.x}%`, top: `${h.y}%` }}
          />
        ))}

        {/* live dimension readout */}
        <div className="absolute -bottom-8 right-0 flex items-center gap-1.5 rounded-md bg-[#06090e]/85 px-2 py-1 text-[11px] font-medium text-white shadow-lg backdrop-blur-sm">
          <span className="readout tabular-nums">
            <motion.span>{pxW}</motion.span>
            <span className="mx-1 text-white/45">×</span>
            <motion.span>{pxH}</motion.span>
          </span>
        </div>
      </motion.div>

      {/* Magnifier loupe. Sits just above the drag corner so the circle and
          its hex readout both stay inside the frame. */}
      <motion.div
        initial={reduce ? false : { opacity: 0, scale: 0.8 }}
        animate={{ opacity: 1, scale: 1 }}
        transition={{ duration: 0.45, delay: 1.5, ease: [0.16, 1, 0.3, 1] }}
        className="absolute z-10 flex -translate-y-[96%] translate-x-1.5 flex-col items-center gap-1.5"
        style={{
          left: `${SEL.left + SEL.width}%`,
          top: `${SEL.top + SEL.height}%`,
        }}
      >
        <div className="relative h-20 w-20 overflow-hidden rounded-full border-2 border-white/85 shadow-[0_8px_24px_rgba(0,0,0,0.45)]">
          {/* framed on the chart bars, which is where the hex readout below
              is sampled from */}
          <div className="absolute inset-0 origin-[46%_66%] scale-[7]">
            <ShotSample className="h-full w-full" />
          </div>
          {/* pixel grid */}
          <div
            className="absolute inset-0 opacity-45"
            style={{
              backgroundImage:
                "linear-gradient(to right, rgba(0,0,0,0.35) 1px, transparent 1px)," +
                "linear-gradient(to bottom, rgba(0,0,0,0.35) 1px, transparent 1px)",
              backgroundSize: "10px 10px",
            }}
          />
          <div className="absolute left-1/2 top-1/2 h-2.5 w-2.5 -translate-x-1/2 -translate-y-1/2 border border-white shadow-[0_0_0_1px_rgba(0,0,0,0.6)]" />
        </div>
        <span className="readout -translate-x-2 translate-y-2 rounded bg-[#06090e]/85 px-1.5 py-0.5 text-[10px] font-medium text-white shadow">
          #6D8FD6
        </span>
      </motion.div>

      {/* hotkey hint, bottom-left */}
      <div className="absolute bottom-3 left-3 flex items-center gap-1.5 rounded-md bg-[#06090e]/75 px-2 py-1.5 backdrop-blur-sm">
        {["⌘", "⇧", "4"].map((k) => (
          <kbd
            key={k}
            className="readout flex h-5 min-w-5 items-center justify-center rounded border border-white/20 bg-white/10 px-1 text-[10px] font-medium text-white"
          >
            {k}
          </kbd>
        ))}
        <span className="ml-1 text-[10px] text-white/65">to capture</span>
      </div>
    </div>
  );
}
