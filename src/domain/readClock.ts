// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE SHELL'S READ CADENCE — how often the world is read again, derived from the served clock
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// THE READ IS THE CATCH-UP (DESIGN D.2): every read settles every voyage server-side before it
// answers, so this interval is not a poll for changes — it IS how time passes in this game, and it
// is also how often a fleet's position on the chart can move.
//
// THIS USED TO BE A FLAT 30 SECONDS, and its own comment justified that as "well inside a
// voyage-day (three real minutes at TIME_COMPRESSION 480)". Migration 0045 took the compression to
// 9600 for testing, which makes a voyage-day NINE SECONDS — so thirty seconds became THREE AND A
// THIRD voyage-days between reads. A short passage could begin and end between two of them, and a
// fleet under way jumped across the chart instead of crawling. The owner: *"i want the location of
// my fleet moving in map to be shown more often, updated more often"*.
//
// So the cadence is DERIVED from the served clock rather than pinned beside it. The rule is "read
// several times per voyage-day", which is what the old comment actually meant; the number 30_000
// was that rule evaluated once, by hand, against a knob that has since moved. A second hand-tuned
// constant would drift again the next time anyone touches the compression.
//
// Clamped at both ends: never faster than 3 s (a read settles voyages server-side, and hammering
// it buys nothing a player can see), never slower than 30 s (the old cadence remains the floor on
// a slow world, so nothing can arrive unnoticed).
//
// HOW MANY IS "SEVERAL", AND WHY IT ROSE TO TWELVE (2026-10-11). Four was enough while a
// voyage-day was nine real seconds: the arithmetic gave 2.25 s and the 3-s floor took over, so the
// number did nothing. 0100 made a voyage-day NINETY real seconds, and four reads of it is a
// twenty-two-second beat — a player watching a hull creep sees her correct her course four times a
// passage, and an arrival they are waiting for can sit unread for twenty seconds. Twelve gives a
// 7.5-second beat at the current clock AND lands under the 3-s floor at every clock this game has
// shipped before, so nothing that was tuned against the old speed moves. The RULE is still "read
// several times per voyage-day" and it is still derived from the served knob; only the reading of
// "several" is now one a slow world can live with.
//
// THE ONE AUTHORITY (2026-10-31): AppShell arms the interval from this function and writes the
// result into `worldStore.readEveryMs`; `useServedRead` reads that number as the default lifetime
// of a kept answer. A second copy of either the constants or the arithmetic would let "how often
// the world is read" and "how long an answer is kept" drift apart — the very thing the cache-once
// slice exists to stop.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

export const READS_PER_VOYAGE_DAY = 12
export const READ_MIN_MS = 3_000
export const READ_MAX_MS = 30_000

export function readIntervalMs(timeCompression: number | undefined): number {
  if (!timeCompression || timeCompression <= 0) return READ_MAX_MS
  const voyageDaySeconds = (24 * 3600) / timeCompression
  const ms = (voyageDaySeconds / READS_PER_VOYAGE_DAY) * 1000
  return Math.min(READ_MAX_MS, Math.max(READ_MIN_MS, Math.round(ms)))
}
