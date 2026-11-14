import { Clip } from '../components/ui'
import { useLocation } from 'react-router-dom'
import { Countdown, Figure } from '../components/ui'
import { useWorld } from '../live/worldStore'
import { isTradeRoute } from './navTabs'
import { useShellState } from './shellState'
import { COIN, formatDucatsDelta, formatGameClock, formatGameToday, formatKoreaTime, formatInt, instantMs } from '../lib/format'
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

/** 0241: how long the capital's gift shows beside the purse. */
const GIFT_SHOW_MS = 2 * 60_000

export function TopBar() {
  const t = useT()
  const { pathname } = useLocation()
  const { nowMs } = useShellState()
  const ducats = useWorld((s) => s.ducats)
  // 0241 (owner row 230): what she owes the cities (a SAIL's stores on credit, dock fees) — paid from her next sale.
  const owed = useWorld((s) => s.player?.owed ?? 0)
  // 0352 (owner row 317): her Reputation, the served balance (public.reputation_card). null: no company, or a server before 0352.
  const reputation = useWorld((s) => s.player?.reputation?.balance ?? null)
  // 0241: her capital's gift, for two minutes after it lands — one string, so the bar re-renders only when it changes.
  const giftKey = useWorld((s) => {
    const e = s.events.find((x) => x.kind === 'CAPITAL_GIFT')
    return e ? `${e.at}|${typeof e.payload.ducats === 'number' ? e.payload.ducats : (e.ducats_delta ?? 0)}` : null
  })
  const [giftAt, giftDucats] = giftKey ? giftKey.split('|') : [null, null]
  const giftMs = instantMs(giftAt)
  const showGift = giftMs !== null && nowMs - giftMs >= 0 && nowMs - giftMs < GIFT_SHOW_MS

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
  const korea = formatKoreaTime(nowMs)
  const bigPurse = ducats !== null && ducats >= 1_000_000

  return (
    <header className="flex h-8 shrink-0 items-center gap-2 px-gutter sm:gap-3">
      {/* Left: how long the quay's prices stand. An empty span holds the slot when there is
          nothing true to say, so the purse does not slide across the bar between tabs. */}
      {/* Cut only through Clip (row 201): on a phone the date, hour and price countdown can outrun
          the bar, and the full line must stay readable by hover or press. */}
      <Clip cut className="text-t-caption text-ink-muted">
        {/* THE GAME CLOCK — the world's DATE and its hour (owner row 176, 2026-10-20: *"There is
            one right now showing the time only, but I want to see the date, year, months and so
            on."*). ONE clock since 0413 (the owner, 2026-11-14: a game day is one real hour): the date
            turns when the hour passes midnight, and the Sun stands on the same hour
            (lib/format/time.ts `gameClockDays`, from the served `clock_anchor`). Both are pure
            functions of THE ONE CLOCK and of the served clock. */}
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
            {' · '}
            {/* The countdown's word is for a glass with room for it (2026-11-12): at 320 px it cut the hour off. */}
            <span className="hidden min-[375px]:inline">{t('shell.prices')} </span>
            <Countdown untilMs={priceEdgeMs} nowMs={nowMs} dueText={t('shell.now')} />
          </>
        )}
      </Clip>

      {/* Right: the purse. Deliberately NOT hidden while the world opens — a dash holds the
          column's width, so the bar does not jump by the width of a number the moment the first
          read lands. */}
      {/* THE REAL TIME IN KOREA (owner row 195, 2026-10-25: *"i need a real time clock, set in
          korea since i am in korea"*) — the same instant as the game's clocks on the left, printed
          in Asia/Seoul (lib/format/time.ts formatKoreaTime) and ticking with the shell's one-second
          beat. Fixed width digits, so the bar does not shift as the seconds turn. */}
      {/* A PHONE'S STRIP HOLDS EVERY FIGURE WHOLE (2026-11-12, the owner: *"word box overlapping"*). Measured at 390 px in
          Korean on Trade: the date, the hour, the price countdown, this clock with its word and the purse are 409 px in a
          358-px bar, and the date was cut to "12:…". So the clock's WORD stands only where there is room for it: from 375
          px on a screen with no price countdown, from `sm` on one with it; and under 375 px beside the countdown the
          clock itself gives way (the phone's own status bar shows the hour), as it does on any phone once the purse is
          seven figures; beside the countdown on a phone, and under 375 px, it reads to the minute. The digits are never cut. */}
      {/* WHAT DOES NOT FIT GIVES WAY WHOLE, THE CLOCK'S WORD FIRST (2026-11-14, owner row 318). The widths above are fixed steps, and a
          line that fits one purse and one language does not fit the next: in Korean at 390 px, with a purse of six figures, the
          date was cut to "06:…" (and at 320 px by 2 px). So the right side is ONE WRAPPING LINE, written from the right: the
          purse, then what is owed, the gift, the clock, and last the clock's word. Whatever does not fit goes to a second line,
          and the box is one line high, so it is not drawn: nothing is ever cut in half, and the date is cut only when the date
          and the purse alone do not fit the glass. The first child is a strut: it makes the line the bar's own height, so the
          rest are centred in the bar. */}
      <div className="flex h-8 min-w-min flex-1 flex-row-reverse flex-wrap content-start items-center gap-x-2 overflow-hidden sm:gap-x-3" data-testid="top-bar-right">
        <span aria-hidden className="-ml-2 h-8 w-0 sm:-ml-3" />
        <span data-testid="purse" className="shrink-0">
          <Figure value={ducats === null ? '—' : formatInt(ducats)} unit={COIN} />
        </span>
        {/* 0352: Reputation, left of the purse. The second number every screen is true of: what her successes have earned.
            FROM `sm` UP ONLY: at 390 px the date, the hour, the Korea clock and the purse leave 17 px, and a figure here
            cuts the game hour off (tests/shell.kstClock.spec.ts holds that line whole). On a phone it stands on the You tab
            and on the arrival card. */}
        {reputation !== null && (
          <span data-testid="reputation" data-value={reputation} className="hidden shrink-0 sm:inline">
            <Figure value={formatInt(reputation)} unit={t('shell.reputation')} />
          </span>
        )}
        {owed > 0 && (
          <span data-testid="owed" className="shrink-0 text-t-caption text-warning">
            {t('shell.owed')} {formatInt(owed)}
          </span>
        )}
        {showGift && (
          <span data-testid="gift-toast" className="shrink-0 text-t-caption text-success">
            {t('shell.gift')} {formatDucatsDelta(Number(giftDucats))}
          </span>
        )}
        <span className={`shrink-0 text-t-caption text-ink-muted ${showCountdown ? (bigPurse ? 'max-sm:hidden' : 'max-[374px]:hidden') : ''}`}>
          <span data-testid="kst-clock" className="tabular-nums text-ink">
            {korea.slice(0, 5)}
            <span className={showCountdown ? 'max-sm:hidden' : 'max-[374px]:hidden'}>{korea.slice(5)}</span>
          </span>
        </span>
        <span className={`-mr-1 shrink-0 text-t-caption text-ink-muted sm:-mr-2 ${showCountdown ? 'hidden sm:inline' : 'hidden min-[375px]:inline'}`} data-testid="kst-word">
          {t('shell.kst')}
        </span>
      </div>
    </header>
  )
}
