import { Bar } from './Bar'
import { formatInt, formatOfTotal, tonsWord } from '../../lib/format'

// THE CARGO BAR — how full the ship is, as `51 / 60 tons`, and what a staged basket would make it.
//
// ── ONE RECIPE, TWO CALLERS (docs/NO_SPAGHETTI.md §1) ──────────────────────────────────────────
// FLEETS drew this on every fleet row since the twelve primitives landed — a `Bar` at `used /
// total`, `warning` when the served free hold is gone, the figure `formatOfTotal(used, total)
// tons` beside it — and the basket panel (owner row 76, slice 2) needed the same gauge with the
// staged change washed on. The first cut of that panel (PR #59, `QuayHold.tsx`) hand-wrote the
// recipe a second time, byte-for-byte, and the adversarial review named it (SHOULD 4c). Written a
// second time → it becomes a function: this is that function, and FLEETS composes it too.
//
// ── WHAT IT DOES NOT KNOW ──────────────────────────────────────────────────────────────────────
// Whose ship, how the figures were folded, what the basket holds. `used` and `total` are the
// caller's folds over the served hulls (`fleetHoldUsed` / `fleetHoldTotal`, domain/fleet — the
// design system may not import a domain section); `free` is the SERVED `fleet.free_hold`, the one
// answer to "is there room", and it decides the tone alone. `after` is the SERVED room after a
// staged basket lands (`cmd.preview_basket`'s `hold.free_after`, 0083) — nothing here adds a
// quantity to a bulk. The wash is `Bar.pending`, this repo's one vocabulary for "not yet".
//
// ── THE WORDS (docs/WORDS.md, law 2) ───────────────────────────────────────────────────────────
// A share prints its whole: `51 / 60 tons`, never `9 t free`. With a basket staged the figure
// becomes `51 → 63 / 60 tons` — where it is now, where it would be, out of what.

export function CargoBar({
  used,
  total,
  free,
  after = null,
  className = '',
}: {
  /** Tons on board today — cargo and supplies, the caller's fold (`fleetHoldUsed`). */
  used: number
  /** Tons the fleet holds when empty — the caller's fold (`fleetHoldTotal`). */
  total: number
  /** The SERVED free hold today (`fleet.free_hold`): at or below zero the bar warns. */
  free: number
  /** The SERVED free hold after a staged basket lands (`hold.free_after`), or null when nothing
   *  is staged. Drawn as a wash between now and then, and as the arrow in the figure. */
  after?: number | null
  className?: string
}) {
  const pct = total > 0 ? (used / total) * 100 : 0
  // The room after, as tons on board after: `total − free_after`. Same formatting arithmetic as
  // `used / total`, over a served figure — never `used + qty × bulk`.
  const usedAfter = after !== null ? Math.max(0, total - after) : null
  const pending = usedAfter !== null && total > 0 ? ((usedAfter - used) / total) * 100 : undefined
  const figure =
    usedAfter !== null && Math.round(usedAfter) !== Math.round(used)
      ? `${formatInt(used)} → ${formatOfTotal(usedAfter, total)} ${tonsWord(total)}`
      : `${formatOfTotal(used, total)} ${tonsWord(total)}`
  return (
    <span className={`flex items-center gap-3 text-t-caption text-ink-faint ${className}`} data-testid="cargo-bar">
      <span className="shrink-0">cargo</span>
      <Bar
        pct={pct}
        pending={pending}
        tone={free <= 0 ? 'warning' : 'accent'}
        label={`cargo, ${figure}`}
        figure={<span className="tabular-nums">{figure}</span>}
        className="min-w-0 flex-1"
      />
    </span>
  )
}
