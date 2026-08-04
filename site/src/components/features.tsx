"use client";

import {
  ArrowUpRight,
  Circle,
  Highlighter,
  MousePointer2,
  Square,
  Type,
  Droplet,
  Hash,
  Pause,
  Check,
  Download,
  type LucideIcon,
} from "lucide-react";
import { destinations, effectSwatches, hotkeys, languages } from "@/lib/content";
import { Panel } from "@/components/panel";
import { SectionHead } from "@/components/section-head";
import { ShotSample } from "@/components/shot-sample";

/* ------------------------------------------------------------------ */
/* Annotation — the editor caught mid-markup                           */
/* ------------------------------------------------------------------ */

const tools: LucideIcon[] = [
  MousePointer2,
  Square,
  Circle,
  ArrowUpRight,
  Type,
  Highlighter,
  Droplet,
  Hash,
];

function AnnotationVisual() {
  return (
    <div className="flex h-full min-h-[15rem] gap-3">
      {/* tool rail */}
      <div className="flex flex-col gap-1 rounded-lg border border-line bg-panel p-1.5">
        {tools.map((Tool, i) => (
          <span
            key={i}
            className={`flex h-7 w-7 items-center justify-center rounded-md ${
              i === 3
                ? "bg-accent text-accent-ink"
                : "text-muted"
            }`}
          >
            <Tool size={14} />
          </span>
        ))}
      </div>

      {/* canvas */}
      <div className="relative flex-1 overflow-hidden rounded-lg border border-line">
        <ShotSample className="h-full w-full" />

        {/* blurred-out region hiding something private */}
        <div className="absolute left-[22%] top-[16%] h-[15%] w-[24%] rounded-[3px] backdrop-blur-[6px]">
          <div className="absolute inset-0 rounded-[3px] bg-white/10" />
        </div>

        {/* highlight box */}
        <div className="absolute bottom-[13%] left-[24%] h-[16%] w-[30%] rounded-[3px] border-2 border-accent" />

        {/* arrow pointing at the outlier bar */}
        <svg
          className="absolute inset-0 h-full w-full"
          viewBox="0 0 100 100"
          preserveAspectRatio="none"
        >
          <defs>
            <marker
              id="ann-arrow"
              markerWidth="5"
              markerHeight="5"
              refX="3.6"
              refY="2.5"
              orient="auto"
            >
              <path d="M0,0 L5,2.5 L0,5 z" fill="var(--accent)" />
            </marker>
          </defs>
          <path
            d="M62,74 C72,70 76,62 78,55"
            fill="none"
            stroke="var(--accent)"
            strokeWidth="1.6"
            strokeLinecap="round"
            markerEnd="url(#ann-arrow)"
            vectorEffect="non-scaling-stroke"
          />
        </svg>

        {/* step numbers */}
        {[
          { n: 1, left: "20%", top: "14%" },
          { n: 2, left: "56%", top: "72%" },
        ].map((s) => (
          <span
            key={s.n}
            className="readout absolute flex h-5 w-5 -translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-full bg-accent text-[10px] font-bold text-accent-ink shadow"
            style={{ left: s.left, top: s.top }}
          >
            {s.n}
          </span>
        ))}
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Effects                                                             */
/* ------------------------------------------------------------------ */

function EffectsVisual() {
  return (
    <div className="grid grid-cols-4 gap-2.5">
      {effectSwatches.map((fx) => (
        <figure key={fx.name} className="min-w-0">
          <div
            className={`relative aspect-[4/3] overflow-hidden rounded-md border ${
              fx.name === "Original" ? "border-accent" : "border-line"
            }`}
            style={{ filter: fx.css === "none" ? undefined : fx.css }}
          >
            <ShotSample className="h-full w-full" />
          </div>
          <figcaption className="mt-1.5 truncate text-[11px] text-muted">
            {fx.name}
          </figcaption>
        </figure>
      ))}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Recording                                                           */
/* ------------------------------------------------------------------ */

function RecordingVisual() {
  return (
    <div className="flex h-full min-h-[15rem] flex-col justify-between gap-4">
      <div className="relative flex-1 overflow-hidden rounded-lg border-2 border-accent">
        <ShotSample className="h-full w-full" />
        <span className="readout absolute left-2 top-2 flex items-center gap-1.5 rounded bg-[#06090e]/85 px-1.5 py-1 text-[10px] font-semibold tracking-wider text-white">
          <span className="animate-rec h-1.5 w-1.5 rounded-full bg-accent-hot" />
          REC
        </span>
      </div>

      <div className="flex items-center gap-3 rounded-lg border border-line bg-panel px-3 py-2.5">
        <span className="readout text-sm font-semibold tabular-nums">
          00:42
        </span>
        <span className="flex h-5 items-end gap-[3px]">
          {[0, 1, 2, 3, 4, 5].map((i) => (
            <span
              key={i}
              className="animate-meter w-[3px] rounded-full bg-accent"
              style={{
                height: "100%",
                animationDelay: `${i * 0.13}s`,
              }}
            />
          ))}
        </span>
        <span className="ml-auto flex items-center gap-1.5">
          <span className="flex h-6 w-6 items-center justify-center rounded-md border border-line text-muted">
            <Pause size={11} />
          </span>
          <span className="flex h-6 w-6 items-center justify-center rounded-md bg-accent text-accent-ink">
            <Square size={9} fill="currentColor" />
          </span>
        </span>
      </div>

      <div className="flex flex-wrap gap-1.5">
        {["H.264", "HEVC", "GIF", "WebM"].map((f) => (
          <span
            key={f}
            className="readout rounded border border-line bg-panel px-1.5 py-0.5 text-[10px] text-muted"
          >
            {f}
          </span>
        ))}
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Hotkeys                                                             */
/* ------------------------------------------------------------------ */

function HotkeysVisual() {
  return (
    <ul className="flex h-full min-h-[15rem] flex-col justify-center gap-2.5">
      {hotkeys.map((h) => (
        <li
          key={h.action}
          className="flex items-center justify-between gap-3 rounded-lg border border-line bg-panel px-3 py-2.5"
        >
          <span className="text-[13px] text-ink-soft">{h.action}</span>
          <span className="flex shrink-0 gap-1">
            {h.keys.map((k) => (
              <kbd
                key={k}
                className="readout flex h-6 min-w-6 items-center justify-center rounded-[5px] border border-line-strong bg-panel-2 px-1 text-[11px] font-medium text-ink-soft"
              >
                {k}
              </kbd>
            ))}
          </span>
        </li>
      ))}
    </ul>
  );
}

/* ------------------------------------------------------------------ */
/* Destinations                                                        */
/* ------------------------------------------------------------------ */

function DestinationsVisual() {
  return (
    <div className="flex h-full flex-col gap-4">
      <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
        {destinations.map((d) => (
          <div
            key={d.name}
            className="rounded-lg border border-line bg-panel px-3 py-2.5"
          >
            <div className="truncate text-[13px] font-medium text-ink-soft">
              {d.name}
            </div>
            <div className="readout mt-0.5 truncate text-[10px] text-muted">
              {d.kind}
            </div>
          </div>
        ))}
      </div>

      <div className="mt-auto flex items-center gap-2.5 rounded-lg border border-line bg-panel px-3 py-2.5">
        <span className="flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-live/15 text-live">
          <Check size={12} strokeWidth={3} />
        </span>
        <span className="readout min-w-0 flex-1 truncate text-[12px] text-ink-soft">
          https://cdn.your-domain.com/8fk2p.png
        </span>
        <span className="shrink-0 text-[11px] text-muted">copied</span>
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Text recognition                                                    */
/* ------------------------------------------------------------------ */

function OcrVisual() {
  return (
    <div className="flex h-full min-h-[15rem] flex-col gap-3">
      <div className="relative flex-1 overflow-hidden rounded-lg border border-line">
        <ShotSample className="h-full w-full" />
        <div className="absolute inset-0 bg-[#06090e]/35" />
        {/* recognised text regions */}
        {[
          { l: "22%", t: "12%", w: "34%", h: "7%" },
          { l: "22%", t: "80%", w: "70%", h: "5%" },
          { l: "22%", t: "88%", w: "56%", h: "5%" },
        ].map((b, i) => (
          <span
            key={i}
            className="absolute rounded-[2px] border border-dashed border-accent-hot bg-accent/15"
            style={{ left: b.l, top: b.t, width: b.w, height: b.h }}
          />
        ))}
        <span className="animate-scan absolute inset-x-0 top-0 h-[2px] bg-accent-hot/70 shadow-[0_0_12px_var(--accent-hot)]" />
      </div>
      <div className="rounded-lg border border-line bg-panel px-3 py-2">
        <span className="readout text-[11px] text-muted">47 words · copied</span>
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Localization                                                        */
/* ------------------------------------------------------------------ */

function LocalizationVisual() {
  return (
    <div className="flex flex-wrap items-center justify-center gap-2.5 sm:gap-3">
      {languages.map((l) => (
        <div
          key={l.code}
          className="flex items-center gap-2 rounded-lg border border-line bg-panel px-3.5 py-2.5"
        >
          <span className="readout rounded bg-accent/12 px-1.5 py-0.5 text-[10px] font-semibold uppercase text-accent">
            {l.code}
          </span>
          <span className="text-[13px] text-ink-soft">{l.name}</span>
        </div>
      ))}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Updates — the About pane offering the version that just shipped     */
/* ------------------------------------------------------------------ */

function UpdatesVisual() {
  return (
    <div className="grid h-full gap-3 sm:grid-cols-3">
      {/* the notification: a release you didn't go looking for */}
      <div className="flex flex-col rounded-lg border border-line bg-panel p-3.5 sm:col-span-2">
        <div className="flex items-center gap-2.5">
          <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-md bg-accent text-accent-ink">
            <Download size={13} strokeWidth={2.5} />
          </span>
          <span className="min-w-0 flex-1 truncate text-[13px] font-medium text-ink-soft">
            SwiftX 2026.8.1 is available
          </span>
          <span className="readout shrink-0 text-[10px] text-muted">
            you have 2026.7.1
          </span>
        </div>

        <div className="mt-3 flex flex-wrap gap-2">
          <span className="rounded-md bg-accent px-2.5 py-1 text-[11px] font-medium text-accent-ink">
            Install Update
          </span>
          <span className="rounded-md border border-line-strong px-2.5 py-1 text-[11px] text-muted">
            View Release
          </span>
          <span className="rounded-md border border-line-strong px-2.5 py-1 text-[11px] text-muted">
            Skip This Version
          </span>
        </div>

        <div className="mt-auto flex items-center gap-2.5 pt-3.5">
          <span className="flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-live/15 text-live">
            <Check size={12} strokeWidth={3} />
          </span>
          <span className="min-w-0 flex-1 truncate text-[11.5px] text-muted">
            Checksum and Developer ID verified before install
          </span>
        </div>
      </div>

      {/* the cadence you picked, including not at all */}
      <div className="flex flex-col rounded-lg border border-line bg-panel p-3.5">
        <span className="text-[12px] text-ink-soft">Check automatically</span>
        <ul className="mt-2.5 flex flex-col gap-1.5">
          {["Daily", "Weekly", "Monthly", "Off"].map((choice) => (
            <li
              key={choice}
              className={`readout flex items-center justify-between rounded-[5px] border px-2 py-1 text-[11px] ${
                choice === "Daily"
                  ? "border-accent/40 bg-accent/10 text-ink-soft"
                  : "border-line-strong text-muted"
              }`}
            >
              {choice}
              {choice === "Daily" && (
                <Check size={11} strokeWidth={3} className="text-accent" />
              )}
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */

export function Features() {
  return (
    <section id="features" className="px-5 py-20 sm:px-8 lg:py-28">
      <div className="mx-auto max-w-6xl">
        <SectionHead
          eyebrow="What you get"
          title="Everything the screenshot needs before it&rsquo;s useful"
          lede="Marking up, hiding the parts nobody should see, recording the bug instead of describing it, and getting it somewhere other people can open."
        />

        <div className="mt-12 grid gap-4 lg:grid-cols-3">
          <Panel
            className="lg:col-span-2"
            title="Annotation editor"
            description="Arrows, boxes, step numbers, speech balloons, highlighter and a smart eraser — plus blur and pixelate for anything that shouldn't leave your machine."
          >
            <AnnotationVisual />
          </Panel>

          <Panel
            title="Screen recording"
            description="Record a window or a region to H.264, HEVC, GIF or WebM, with system and microphone audio and pause/resume mid-take."
            delay={0.06}
          >
            <RecordingVisual />
          </Panel>

          <Panel
            title="Global hotkeys"
            description="Bind any capture, tool or workflow to a key combination that works from any app, whether or not SwiftX is in front."
            delay={0.12}
          >
            <HotkeysVisual />
          </Panel>

          <Panel
            className="lg:col-span-2"
            title="51 image effects"
            description="Adjustments, filters, manipulations and drawings you can stack into a preset and apply automatically to every capture."
            delay={0.06}
          >
            <EffectsVisual />
          </Panel>

          <Panel
            className="lg:col-span-2"
            title="Your own destinations"
            description="Upload to storage you control, a self-hosted server, an image host, or a connected Google Drive, YouTube or OneDrive account — then get the URL back on your clipboard. No SwiftX account, no SwiftX servers."
          >
            <DestinationsVisual />
          </Panel>

          <Panel
            title="Text and codes on screen"
            description="Pull text straight off the screen with Vision-powered recognition, or read a QR code without reaching for your phone."
            delay={0.06}
          >
            <OcrVisual />
          </Panel>

          <Panel
            className="lg:col-span-3"
            title="Speaks your language"
            description="English, French, German, Italian, Japanese, Portuguese and Spanish ship today, following your Mac's system language by default or picked directly in Settings → General. Community translations are welcome — it's a text file, no code involved."
          >
            <LocalizationVisual />
          </Panel>

          <Panel
            className="lg:col-span-3"
            title="Updates that find you"
            description="SwiftX watches for its own releases — daily, weekly, monthly or never, your call — and installs them in place once the download matches the published checksum and carries the same Developer ID signature. Installed through Homebrew? It defers to brew upgrade instead."
          >
            <UpdatesVisual />
          </Panel>
        </div>
      </div>
    </section>
  );
}
