import { DangerMark, fineClass } from '../../components/ui'
import type { MapWater } from '../../chart'
import { watersView } from './watersRows'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// AHEAD — the waters a fleet at sea still has to cross, and how far off each one is.
//
// ── WHAT IT IS, AND WHAT IT IS NOT ─────────────────────────────────────────────────────────────
// `docs/NAVIGATION_PLAN.md:173` asks for *"the contacts panel with distances"*, from the owner's
// spec: *"a panel on the map lists nearby contacts and their distance; the player clicks one to
// engage."* A CONTACT means a ship, and there are no ships to meet: an event at sea has no
// subject, `docs/PLATFORM.md` §3 SEAM 2 names the table that would give it one, and it is
// deliberately unbuilt. So this panel names what there IS — the water itself, which is a real,
// authored, spatial thing (`seas.danger_level` and `seas.note`, migration 0040) that until 0055
// was read by no rule and shown on no screen.
//
// **IT IS NOT A FORECAST, and that is a rule rather than a shortage.** `voyage.hazard_roll` is a
// pure function of (voyage, day, world secret), so listing what WILL happen on the days ahead is
// trivial — and it is refused twice over: it hands the player the dice, and migration 0055
// measured that a look-ahead is not even authoritative (`voyage.leg_at_day` subtracts delays that
// have not been recorded yet). Every figure here is frozen at departure except her own progress.
//
// ── THE SHAPE, WHICH IS THE OWNER'S CONCISE LAW ────────────────────────────────────────────────
// *"too long. make it very concise… Always show in graphics, concisely."* So: one row per sea,
// three facts on it — the danger tier as countable pips, the sea's NAME, and the distance as the
// hero figure. No sentence, no paragraph, no label that reads like prose. The sea she is in now
// gets one extra line, its character in the words the world authored ("steep ugly seas"), because
// where she IS earns four facts and where she is going does not.
//
// ── WHERE THE DECISIONS LIVE ───────────────────────────────────────────────────────────────────
// ./watersRows.ts, not here. This file is markup: every choice it makes about WHAT a row says —
// the cap, the remainder, the figure, which row carries the character — is `watersView`'s, so the
// contract is data a spec reads instead of markup a spec greps. Nothing in this folder derives a
// tier, a note or a distance; they are the server's, copied.
//
// ── WHAT IS DELIBERATELY ABSENT ────────────────────────────────────────────────────────────────
//   · any control. Nothing here is pressable, because there is nothing yet to select: engaging a
//     contact needs an actor. The panel this sits inside already folds and dismisses (MapPanel),
//     and pressing either keeps the panel on the glass — no control on this surface has ever been
//     able to destroy it, which tests/waters.panel.spec.ts measures in a real browser.
//   · the per-sea encounter MIX (0055). It exists, it is authored, and it is DARK: printing "these
//     waters breed corsairs" while `voyage.settle` can never produce one would be a legible lie.
//     It becomes a fourth fact on the row the day the mix is lit, and nothing else here moves —
//     the tier these pips draw is the very column that mix is keyed on.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

export function WatersAhead({ waters }: { waters: readonly MapWater[] }) {
  const { rows, total, hidden } = watersView(waters)
  if (rows.length === 0) return null

  return (
    <div className="mt-1 border-t border-rule pt-1" data-testid="map-waters">
      <div className="flex items-baseline justify-between gap-2">
        <span className="font-mono text-[10px] uppercase tracking-wider text-ink-faint">ahead</span>
        <span
          className="font-mono text-[10px] tabular-nums text-ink-faint"
          data-testid="map-waters-count"
        >
          {total}
        </span>
      </div>
      <ul>
        {rows.map((row) => (
          <li key={`${row.code}-${row.figure}`} data-testid="map-water-row" data-sea={row.code}>
            <div className="flex items-baseline gap-1.5 py-0.5">
              <DangerMark tier={row.danger} className="translate-y-px" />
              <span className="min-w-0 flex-1 truncate font-serif text-[11px] text-ink">
                {row.name}
              </span>
              <span
                className="shrink-0 font-mono text-[11px] tabular-nums text-ink"
                data-testid="map-water-distance"
              >
                {row.figure}
              </span>
            </div>
            {/* The character line is indented to sit UNDER THE NAME, not under the pips: five
                6 px pips with four 1 px gaps is 34 px, plus the row's own `gap-1.5` (6 px), so
                the name's left edge is at 40 px — `pl-10`. Measured off the mark rather than
                guessed, because a line that starts half under the tier reads as a caption for
                the tier instead of for the sea. */}
            {row.note !== null && (
              <p className={`${fineClass()} truncate pl-10`} data-testid="map-water-note">
                {row.note}
              </p>
            )}
          </li>
        ))}
      </ul>
      {hidden > 0 && (
        <p className={`${fineClass()} tabular-nums`} data-testid="map-waters-more">
          +{hidden} beyond
        </p>
      )}
    </div>
  )
}
