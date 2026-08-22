import { useEffect } from 'react'
import { Card, Explain, HeroFigure, SectionLabel, fineClass } from '../../components/ui'
import { formatPct, formatPctPoints, formatRealDuration, formatRelative } from '../../lib/format'
import { useWorld } from '../../live/worldStore'
import { useShellState } from '../../app/shellState'
import type { BuffKind, BuffsView } from '../../lib/rpc'

// WHAT IS ON AT THE QUAY — the visible half of 0026.
//
// ── WHY A FAIR HAD TO BECOME VISIBLE ───────────────────────────────────────────────────────────
// 0026 shaves 30 per cent off the port's published cut for a few days, through `world.spread()`,
// which every quote and every executed trade already composes. So before this file the fair was
// REAL and INVISIBLE: the price simply differed and nothing on the screen said why. §3a's third
// trap is exactly that — "invisible rules are bugs, not content" — and the reference game's own
// answer to one of its own was to DELETE the rule rather than document it, because a player could
// not read it in game. This is the other answer.
//
// ── THERE IS ONE SPREAD NUMBER, AND THIS PANEL IS NOT IT ───────────────────────────────────────
// `world.buffs()` serves `spread_published`, and it is the same figure `world.market()` serves as
// `port.spread` — 0026's self-assert (d) requires the two to be equal, because "the screen and the
// till would disagree" otherwise. The City face already prints it. So this panel deliberately
// prints NEITHER `spread_published` NOR any before/after pair computed on this side: two printings
// of one number are two authorities the moment their two payloads are fetched a second apart, and
// a client-derived "was 3.8%, now 2.7%" is a third (docs/NO_SPAGHETTI.md §1, question 3).
//
// What it prints instead is `buff_pct` — served, already capped, and the one figure that is ABOUT
// the fair rather than about the port. `magnitude_pct` is not printed beside it: with one fair
// running the two are the same number twice, and with two running `buff_pct` is the capped total
// the till actually applied while the sum of the magnitudes is not.
//
// ── THE CLIENT NEVER DECIDES WHETHER A FAIR IS ON ──────────────────────────────────────────────
// `live` is the server's own reading of the window at the payload's `now`. This file filters on
// that flag and never recomputes it from `starts_at`/`ends_at`, which it could — and which would
// be a second authority for "is it running" that can disagree with the one the price was quoted
// through. Staleness is answered by ASKING AGAIN (`quayEdgeMs` below), never by flipping the flag.

/**
 * WHAT IS ON AT THIS QUAY RIGHT NOW, and the read that settles it.
 *
 * Three states, and the QUIET one is a state rather than an absence: 0026 measured a fair at about
 * 1.6 per cent of port-days, so "nothing is on" is what a player reads 98 times out of 100 and a
 * screen that said nothing would read as broken. It gets ONE dim line and no panel — a panel spent
 * on nothing is the density failure docs/UI_DIRECTION.md §1 diagnosed.
 *
 * The catalogue of what CAN happen rides behind the ⓘ of that same line. It is what makes a fair
 * feel like part of a world rather than a random discount, and behind the dot it costs no pixels,
 * so it can never push a running fair below the fold.
 *
 * IT OWNS ITS OWN READ, the way OfficersFace owns the roster's: the component that renders a
 * payload is the one that asks for it, so there is nowhere for a caller to render this and forget.
 */
export function QuayToday({ portId }: { portId: string | null }) {
  // `world.buffs()` SETTLES THE CALENDAR BEFORE IT ANSWERS (0026 §6 and §7: "the read IS the
  // catch-up", 0009's idiom). SINCE 0028 IT IS NO LONGER THE ONLY THING THAT DOES, and the block
  // that used to stand here — DO NOT REMOVE THIS READ, IT IS WHAT MAKES A FAIR HAPPEN — has been
  // deleted because it stopped being true. `world.fleets()`, the read AppShell makes every thirty
  // seconds and again on every tab focus, winds the same one writer; a fair now happens because
  // the game is being played rather than because this panel was looked at. Both call
  // `public.tick_buff_calendar`, so there is still exactly one definition of when a fair happens
  // (0028 asserts the writer count, and names its callers, on every apply).
  //
  // IT IS STILL CHEAP TO CALL: the tick is idempotent by construction (the draw is a pure function
  // of port, season and the world secret), so every caller after the first in a season pays one
  // index probe.
  const buffs = useWorld((s) => (portId ? s.buffs[portId] : undefined))
  const loadBuffs = useWorld((s) => s.loadBuffs)
  // THE CALENDAR CLOCK, from the server (0028). The catalogue's figures are counted in game-days
  // and this is the only thing that turns one into real time. Selected as a primitive, per the
  // store's rule 4.
  const gameDaySeconds = useWorld((s) => s.snapshot?.config.game_day_seconds ?? null)
  // THE ONE CLOCK (app/shellState). A timer of this panel's own would be the second one, and two
  // countdowns in this app would then disagree by a second.
  const { nowMs } = useShellState()

  // RE-ASK AT THE EDGE, NEVER RE-REASON. A fair opens and closes on served instants; when the clock
  // crosses one, the payload in hand has stopped being true. The screen asks the server again
  // rather than flipping `live` itself. The `buffsAt < edge` term is what makes this terminate:
  // after the re-read the payload's own `now` is past that edge, so one edge cannot fire twice.
  const edge = buffs ? quayEdgeMs(buffs) : null
  const buffsAt = buffs ? Date.parse(buffs.now) : null
  useEffect(() => {
    if (!portId) return
    if (!buffs) {
      void loadBuffs(portId)
      return
    }
    if (edge !== null && nowMs >= edge && buffsAt !== null && buffsAt < edge) {
      void loadBuffs(portId)
    }
  }, [portId, buffs, edge, buffsAt, nowMs, loadBuffs])

  if (!buffs) {
    return (
      <p className={fineClass()} data-testid="quay-today" data-state="reading">
        Reading what is on at the quay…
      </p>
    )
  }

  const quay = buffs.port
  const live = quay ? quay.running.filter((r) => r.live) : []
  // `running` is served ordered by `starts_at` and holds only rows that have not ended, so the
  // first one that is not live is the NEXT one — no sort of this list is written on this side.
  const next = quay ? (quay.running.find((r) => !r.live) ?? null) : null

  if (!quay || live.length === 0) {
    return (
      <p className={fineClass()} data-testid="quay-today" data-state="quiet">
        The quay is quiet — nothing is on.
        {next && ` ${next.name} opens ${formatRelative(Date.parse(next.starts_at), nowMs)}.`}
        <Explain label="what can be on at a quay" dotClassName="ml-1">
          <Catalogue kinds={buffs.kinds} gameDaySeconds={gameDaySeconds} />
        </Explain>
      </p>
    )
  }

  return (
    <Card tone="accent" data-testid="quay-today" data-state="on">
      <SectionLabel>On at the quay</SectionLabel>
      {/* THE NUMBER IS THE HERO (docs/UI_DIRECTION.md §4 rule 2). `buff_pct` is served already
          capped by `buff_bonus_cap_pct`, so this is the figure world.spread() actually applied —
          never a sum of the rows beneath it. */}
      <HeroFigure value={formatPctPoints(quay.buff_pct)} unit="off the port's cut" />
      <ul className="mt-2 space-y-1">
        {live.map((r) => (
          <li key={r.code} className="text-sm text-ink">
            {r.name}
            <span className="ml-2 font-mono text-xs text-ink-muted">
              ends {formatRelative(Date.parse(r.ends_at), nowMs)}
            </span>
            <Explain label={r.name} dotClassName="ml-1">
              {r.blurb} It is already inside the cut this port publishes — the spread on the City
              face, the prices on Market and every trade you make read that one figure. Nothing is
              taken off again afterwards.
            </Explain>
          </li>
        ))}
      </ul>
    </Card>
  )
}

/**
 * THE INSTANT THIS PAYLOAD STOPS BEING TRUE, or null when nothing at this quay turns on a clock.
 *
 * A running fair stops at its `ends_at`; one that has not opened starts at its `starts_at`. Both
 * are served instants, so this reads the payload rather than deciding anything.
 *
 * NULL IS NOT "NOTHING WILL EVER HAPPEN HERE": a season that has drawn no fair for this port has
 * no row to edge on, and the next season's draw arrives with the next read. That read comes from
 * the player opening any quay at all, which is the whole point of the block above.
 */
function quayEdgeMs(buffs: BuffsView): number | null {
  const edges = (buffs.port?.running ?? [])
    .map((r) => Date.parse(r.live ? r.ends_at : r.starts_at))
    .filter((ms) => Number.isFinite(ms))
  return edges.length === 0 ? null : Math.min(...edges)
}

/**
 * HOW LONG A RUN OF GAME-DAYS IS, IN REAL TIME — the whole reason 0028 put `game_day_seconds` on
 * the wire.
 *
 * It takes the clock as an ARGUMENT rather than importing a constant, and that is the point. The
 * catalogue's `duration_game_days` and `season_game_days` are counted on the CALENDAR clock, and
 * `src/lib/format/time.ts` only knows the VOYAGE clock (`TIME_COMPRESSION`) — a different rate,
 * whose unit is also called a "day". Converting with the wrong one is wrong by the ratio between
 * them, invisibly. So the only number that may do this conversion is the one the server sent, and
 * a caller with no served clock gets nothing rather than a guess.
 *
 * One caller, deliberately. If a second screen ever needs it, it moves to `src/lib/format` — it
 * does not get written twice (docs/NO_SPAGHETTI.md §1).
 */
function realTimeOfGameDays(gameDays: number, gameDaySeconds: number): string {
  return formatRealDuration(gameDays * gameDaySeconds * 1000)
}

/**
 * WHAT CAN HAPPEN AT A QUAY — the authored catalogue, in the player's own terms.
 *
 * IT PRINTS HOW LONG AND HOW OFTEN, IN REAL TIME. Both are authored server-side on the calendar
 * clock and both are converted with the served `game_day_seconds` — never with the voyage clock
 * every other duration in this app is printed on, and never with a constant declared here. A fair
 * is something a player decides whether to sail for, so "it runs about three hours" is the fact
 * that makes the panel actionable rather than decorative.
 *
 * WITHOUT A SERVED CLOCK IT PRINTS NEITHER. A server older than 0028 sends no `game_day_seconds`,
 * and the honest answer then is silence — which is exactly what this panel did before 0028, and
 * why it is a fallback rather than a default.
 */
function Catalogue({
  kinds,
  gameDaySeconds,
}: {
  kinds: readonly BuffKind[]
  gameDaySeconds: number | null
}) {
  if (kinds.length === 0) return <>Nothing can be on at a quay yet.</>
  return (
    <>
      A fair happens to a PORT, not to you: while one runs, every house calling here pays the same
      lighter cut, and nobody bargains for it.{' '}
      {kinds.map((k) => (
        <span key={k.code}>
          <strong className="text-ink">{k.name}</strong> takes {formatPctPoints(k.magnitude_pct)} off
          the quay&apos;s cut
          {gameDaySeconds !== null && (
            <> and runs for about {realTimeOfGameDays(k.duration_game_days, gameDaySeconds)}</>
          )}
          .{' '}
          {gameDaySeconds !== null && k.season_game_days !== null && k.chance_per_season !== null && (
            <>
              Every quay in the world draws for one afresh each season — a{' '}
              {formatPct(k.chance_per_season)} chance every{' '}
              {realTimeOfGameDays(k.season_game_days, gameDaySeconds)}, wherever you are.{' '}
            </>
          )}
          {k.blurb}
        </span>
      ))}
    </>
  )
}
