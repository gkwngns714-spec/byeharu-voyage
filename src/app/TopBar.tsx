import { useLocation } from 'react-router-dom'
import { Countdown, Figure } from '../components/ui'
import { useWorld } from '../live/worldStore'
import { isTradeRoute } from './navTabs'
import { useShellState } from './shellState'
import { COIN, formatGameClock, formatGameToday, formatKoreaTime, formatInt, instantMs } from '../lib/format'
import { useT } from '../lib/i18n'

// THE STATUS STRIP — 32px, two facts, and nothing that says the obvious.
//
// ── WHAT THIS BAR WAS, AND WHAT WAS DELETED (docs/UI_DIRECTION.md §6, "Shell") ──────────────────
// It was 44px of `BYEHARU VOYAGE` in letter-spaced uppercase mono, a "live read" dot, and the
// purse. §6 keeps one of the three:
//
//   · THE WORDMARK IS GONE. It cost the full width of the bar to tell a player which game they had
//     opened, on every screen of that game, forever. (It was also the only route to Profile, which
//     is why the Cabin tray now carries one — Profile was already a member of that group.)
//   · THE DOT IS GONE. It lit while a read was in flight. A player cannot act on it, cannot make
//     it stop, and is never blocked by it: §2 counts it among the telemetry a screen prints about
//     itself rather than about the world. The read is still how time passes (AppShell's
//     READ_INTERVAL_MS); it just no longer reports on itself.
//   · THE PURSE STAYS, as a `Figure`. It is the only number this server actually keeps that is
//     true on every screen, and every decision in the game is against it.
//
// …and one fact arrived: HOW LONG THESE PRICES STAND. The owner asked for it ("how much left for
// it to change the prices live"), COMMAND already printed it, and it belongs to the shell rather
// than to a screen because it is true of the whole market at once.
//
// ── WHY THE COUNTDOWN IS A SHELL FACT AT ALL ───────────────────────────────────────────────────
// `MarketClock.next_change_at` is `public.next_drift_change_at()` (migration 0029), which is the
// instant THE WHOLE MARKET steps — not this port's instant. Every loaded market's payload
// therefore carries the same answer, so the strip may read it off whichever it has without
// inventing a "current port" the shell has no business knowing. Where two payloads were read
// across a boundary they can disagree by one slot; the LATEST is the one that was read most
// recently, so that is the one taken.
//
// IT ONLY APPEARS ON A TRADE SCREEN (navTabs.ts owns which three, and why). And it DOES NOT
// re-ask: the re-ask at the edge is what actually steps the drift where pg_cron is absent, it
// belongs to the screen that is showing the prices, and a second copy in the shell would be a
// second authority for "when do prices move" firing on every tab. Past the instant the strip reads
// `now` — which is true, and the screen's own re-ask replaces it.

export function TopBar() {
  const t = useT()
  const { pathname } = useLocation()
  const { nowMs } = useShellState()
  const ducats = useWorld((s) => s.ducats)

  // A NUMBER, not the markets object: a selector that returned the record would hand the bar a new
  // identity on every market read and re-render it for a port it is not showing. This collapses to
  // one ms value, which zustand compares with Object.is.
  const priceEdgeMs = useWorld((s) => {
    let latest: number | null = null
    for (const view of Object.values(s.markets)) {
      const at = instantMs(view.clock.next_change_at)
      if (at !== null && (latest === null || at > latest)) latest = at
    }
    return latest
  })

  const showCountdown = isTradeRoute(pathname) && priceEdgeMs !== null

  return (
    <header className="flex h-8 shrink-0 items-center justify-between gap-3 px-gutter">
      {/* Left: how long the quay's prices stand. An empty span holds the slot when there is
          nothing true to say, so the purse does not slide across the bar between tabs. */}
      <span className="min-w-0 truncate text-t-caption text-ink-muted">
        {/* THE GAME CLOCK — the world's DATE and its hour (owner row 176, 2026-10-20: *"There is
            one right now showing the time only, but I want to see the date, year, months and so
            on."*). Two clocks, side by side and in that order, because they run at different rates
            and lib/format/time.ts says why: the date is the calendar clock, which is the day
            `world.game_day` counts and every served `*_game_days` figure is in; the hour is the
            game clock the Sun stands on (gameTimeOfDayMs). Neither is read from anywhere new —
            both are pure functions of THE ONE CLOCK. */}
        {/* The date's word (row 195) is for a wide bar: on a phone it would push the hour out. */}
        <span className="hidden sm:inline">{t('shell.gameDate')} </span>
        <span data-testid="game-date" className="text-ink">
          {formatGameToday(nowMs)}
        </span>
        {' · '}
        <span data-testid="game-clock" className="tabular-nums text-ink">
          {formatGameClock(nowMs)}
        </span>
        {showCountdown && (
          <>
            {' · '}{t('shell.prices')} <Countdown untilMs={priceEdgeMs} nowMs={nowMs} dueText={t('shell.now')} />
          </>
        )}
      </span>

      {/* Right: the purse. Deliberately NOT hidden while the world opens — a dash holds the
          column's width, so the bar does not jump by the width of a number the moment the first
          read lands. */}
      {/* THE REAL TIME IN KOREA (owner row 195, 2026-10-25: *"i need a real time clock, set in
          korea since i am in korea"*) — the same instant as the game's clocks on the left, printed
          in Asia/Seoul (lib/format/time.ts formatKoreaTime) and ticking with the shell's one-second
          beat. Fixed width digits, so the bar does not shift as the seconds turn. */}
      <span className="ml-auto shrink-0 text-t-caption text-ink-muted">
        {t('shell.kst')}{' '}
        <span data-testid="kst-clock" className="tabular-nums text-ink">
          {formatKoreaTime(nowMs)}
        </span>
      </span>

      <span data-testid="purse" className="shrink-0">
        <Figure value={ducats === null ? '—' : formatInt(ducats)} unit={COIN} />
      </span>
    </header>
  )
}
