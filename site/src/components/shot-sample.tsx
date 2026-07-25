/**
 * A stand-in for "whatever is on your screen right now" — a small dashboard
 * UI built entirely in CSS. It is reused as the subject of the hero capture,
 * the annotation canvas, the effect swatches and the text-recognition panel,
 * so the page keeps operating on one consistent piece of material.
 *
 * Colours here are deliberately fixed rather than themed: this is a picture
 * of someone else's screen, not part of our own surface.
 */

const bars = [38, 62, 45, 78, 54, 88, 66, 95, 72];

export function ShotSample({ className = "" }: { className?: string }) {
  return (
    <div
      aria-hidden
      className={`relative overflow-hidden bg-[#eef1f6] ${className}`}
    >
      {/* ambient colour wash so filters and effects have something to bite on */}
      <div
        className="absolute inset-0"
        style={{
          background:
            "radial-gradient(120% 90% at 8% 0%, #dbe6ff 0%, transparent 55%)," +
            "radial-gradient(90% 80% at 100% 10%, #ffe2cf 0%, transparent 60%)," +
            "radial-gradient(100% 100% at 60% 100%, #d8f3e6 0%, transparent 65%)",
        }}
      />

      <div className="relative flex h-full w-full">
        {/* sidebar */}
        <div className="hidden h-full w-[18%] shrink-0 flex-col gap-[6%] border-r border-black/5 bg-white/55 p-[4%] sm:flex">
          <div className="h-[7%] w-[70%] rounded-full bg-[#2b3444]/70" />
          <div className="flex flex-col gap-[5%]">
            <div className="h-[5%] w-[85%] rounded-full bg-[#5b6b85]/35" />
            <div className="h-[5%] w-[65%] rounded-full bg-[#5b6b85]/25" />
            <div className="h-[5%] w-[75%] rounded-full bg-[#5b6b85]/25" />
            <div className="h-[5%] w-[55%] rounded-full bg-[#5b6b85]/25" />
          </div>
        </div>

        {/* main column */}
        <div className="flex h-full min-w-0 flex-1 flex-col gap-[3%] p-[3.5%]">
          <div className="flex items-center justify-between">
            <div className="h-[10px] w-[34%] rounded-full bg-[#26304a]/75" />
            <div className="h-[10px] w-[14%] rounded-full bg-[#ff6a2b]/80" />
          </div>

          {/* stat row */}
          <div className="grid grid-cols-3 gap-[3%]">
            {[
              ["#3b82f6", "62%"],
              ["#10b981", "38%"],
              ["#f59e0b", "80%"],
            ].map(([colour, w]) => (
              <div
                key={colour}
                className="rounded-[6px] border border-black/5 bg-white/80 p-[8%]"
              >
                <div
                  className="h-[6px] rounded-full"
                  style={{ background: colour, width: w }}
                />
                <div className="mt-[14%] h-[5px] w-[70%] rounded-full bg-[#5b6b85]/25" />
              </div>
            ))}
          </div>

          {/* chart */}
          <div className="relative flex min-h-0 flex-1 items-end gap-[1.6%] rounded-[6px] border border-black/5 bg-white/70 p-[2.5%]">
            {bars.map((h, i) => (
              <div
                key={i}
                className="flex-1 rounded-[2px]"
                style={{
                  height: `${h}%`,
                  background:
                    i === 7
                      ? "linear-gradient(180deg,#ff6a2b,#e8551f)"
                      : "linear-gradient(180deg,#93b4f5,#6d8fd6)",
                }}
              />
            ))}
          </div>

          {/* text lines */}
          <div className="flex flex-col gap-[8px]">
            <div className="h-[5px] w-[92%] rounded-full bg-[#5b6b85]/22" />
            <div className="h-[5px] w-[78%] rounded-full bg-[#5b6b85]/18" />
          </div>
        </div>
      </div>
    </div>
  );
}
