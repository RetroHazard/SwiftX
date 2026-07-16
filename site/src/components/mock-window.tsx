import { Circle, Search, Star, Upload } from "lucide-react";

const thumbs = [
  "from-indigo-500/40 to-sky-400/20",
  "from-fuchsia-500/40 to-pink-400/10",
  "from-emerald-500/40 to-teal-400/10",
  "from-amber-500/40 to-orange-400/10",
  "from-sky-500/40 to-indigo-400/10",
  "from-rose-500/40 to-fuchsia-400/10",
  "from-teal-500/40 to-emerald-400/10",
  "from-violet-500/40 to-purple-400/10",
];

export function MockWindow() {
  return (
    <div className="relative rounded-2xl border border-white/10 bg-white/[0.03] p-2 shadow-[0_0_0_1px_rgba(255,255,255,0.02),0_40px_80px_-20px_rgba(0,0,0,0.6)] backdrop-blur">
      <div className="overflow-hidden rounded-xl border border-white/10 bg-[#0b0b0d]">
        <div className="flex items-center gap-2 border-b border-white/5 bg-white/[0.02] px-4 py-3">
          <div className="flex gap-1.5">
            <span className="h-2.5 w-2.5 rounded-full bg-[#ff5f57]" />
            <span className="h-2.5 w-2.5 rounded-full bg-[#febc2e]" />
            <span className="h-2.5 w-2.5 rounded-full bg-[#28c840]" />
          </div>
          <div className="mx-auto flex items-center gap-2 rounded-md bg-white/5 px-3 py-1 text-[11px] text-white/40">
            <Search size={11} />
            Search history
          </div>
        </div>

        <div className="flex">
          <div className="hidden w-40 shrink-0 flex-col gap-1 border-r border-white/5 p-3 text-[11px] text-white/50 sm:flex">
            {[
              "All Captures",
              "Screenshots",
              "Recordings",
              "Favorites",
              "Uploaded",
            ].map((item, i) => (
              <div
                key={item}
                className={`rounded-md px-2.5 py-1.5 ${
                  i === 0 ? "bg-white/10 text-white" : ""
                }`}
              >
                {item}
              </div>
            ))}
          </div>

          <div className="grid flex-1 grid-cols-4 gap-2.5 p-3">
            {thumbs.map((gradient, i) => (
              <div
                key={i}
                className={`relative aspect-video rounded-lg border border-white/5 bg-gradient-to-br ${gradient}`}
              >
                {i === 2 && (
                  <Star
                    size={11}
                    className="absolute right-1.5 top-1.5 fill-amber-300 text-amber-300"
                  />
                )}
                {i === 5 && (
                  <div className="absolute inset-x-1.5 bottom-1.5 flex items-center gap-1 rounded bg-black/50 px-1.5 py-0.5 text-[9px] text-white/70">
                    <Upload size={9} />
                    98%
                  </div>
                )}
              </div>
            ))}
          </div>
        </div>

        <div className="flex items-center justify-between border-t border-white/5 px-4 py-2 text-[10px] text-white/30">
          <span className="flex items-center gap-1.5">
            <Circle size={6} className="fill-emerald-400 text-emerald-400" />
            SwiftX &middot; menu bar
          </span>
          <span>1,204 items</span>
        </div>
      </div>
    </div>
  );
}
