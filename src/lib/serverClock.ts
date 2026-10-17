// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE SERVER'S CLOCK, ON THIS DEVICE — the owner, 2026-10-15: *"is the game not server controlled?
// meaning that every player logged in to this game will share same clock and same vision?"* — and,
// told the game clock and the Sun were computed from each device's own clock, *"yes"* to running
// them from the server's time instead.
//
// ONE AUTHORITY: `serverNow()` is the server's "now" as best this device knows it — `Date.now()`
// plus an offset measured off every Supabase response's `Date` header (exposed to the page by the
// API's CORS `access-control-expose-headers`). The header is whole seconds, so a sample takes the
// middle of that second (+500 ms) against the middle of the round trip, and the offset is the
// MEDIAN of the last few samples, so one slow response cannot jerk the clock. Until the first
// response lands — and always in LOCAL mode, which has no header — the offset is 0: the device's
// own clock, which is what every player read before this file.
//
// Readers: the shell's ONE CLOCK (app/AppShell.tsx), the Sun (chart/useSunlight.ts) and the
// daylight slide (chart/DaylightSheet.tsx). The game clock and the Sun are pure functions of it
// (lib/format gameTimeOfDayMs), so every player sees the same hour and the same day and night.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const SAMPLES = 7
const samples: number[] = []
let offsetMs = 0

function record(sample: number) {
  samples.push(sample)
  if (samples.length > SAMPLES) samples.shift()
  const sorted = [...samples].sort((a, b) => a - b)
  offsetMs = sorted[Math.floor(sorted.length / 2)]
}

/** The server's "now", in ms since the epoch, as this device best knows it. */
export function serverNow(): number {
  return Date.now() + offsetMs
}

/** A `fetch` that measures the server's clock off every response it carries. Handed to the ONE
 *  Supabase client (lib/supabase.ts); it changes nothing about the request or the response. */
export const clockedFetch: typeof fetch = async (input, init) => {
  const sent = Date.now()
  const response = await fetch(input, init)
  const received = Date.now()
  const header = response.headers.get('date')
  const serverMs = header ? Date.parse(header) : NaN
  // A round trip over 5 s says nothing useful about the midpoint; skip it.
  if (Number.isFinite(serverMs) && received - sent < 5000) {
    record(serverMs + 500 - (sent + received) / 2)
  }
  return response
}
