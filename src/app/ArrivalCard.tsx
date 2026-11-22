import { useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Button, FLOAT_CARD_CLASS, glassBesideRailClass } from '../components/ui'
import { formatInt, moneyFigure, moneyWord, type MoneyKind } from '../lib/format'
import { num, str } from '../lib/json'
import { useLocale, useT } from '../lib/i18n'
import { levelName, levelOpens } from '../live/levelWords'
import { worldLevels, type LedgerEvent, type LevelsView, type PlayerHouse } from '../lib/rpc'
import { useServedRead } from '../live/useServedRead'
import { goodWordOf, portNameOf, useWorld } from '../live/worldStore'
import { ArrivalRaids } from '../live/ArrivalRaids'
import { ArrivalRepeat } from '../live/ArrivalRepeat'
import { HOME_TAB, tabWord } from './navTabs'

// THE ARRIVAL CARD (owner row 307, the remaster's S3): a fleet comes in, sells, and the player was told nothing. One
// card, over whatever tab is open, says what the arrival did. It reads FACTS THE SERVER ALREADY REPORTS and adds none:
//   - an arrival is a new VOYAGE_REPORT event (the player's OWN ledger, so another player's fleet is never in it);
//   - its sales are the new SOLD events of that fleet at that port: qty, good and the server's own `profit` (0081);
//   - a level-up is a LEVEL_UP event (0356: `public.level_marks_settle` writes one a level crossed, with the Reputation it
//     gave): the ones on the read that brings the arrival, the ones that land while the card is open, and the ones that came
//     since the last card (a level crossed at the quay has no card of its own);
//   - "New port" is the served `ports_reached` going up on that same read.
// It never computes profit or a level. A sale whose profit the server did not record prints the sale's total instead
// (also served), never a guess. Arrivals that land while a card is open MERGE into it. Its first press goes to the Trade desk
// and is named by that tab's own word ("Trade"; it said "Next", which read as Close in the 2026-11-22 play-test).
// WHAT IT DOES NOT DO: announce what happened while the page was closed (nothing served says "unseen"; the first read
// after a load is the baseline; the "While away" card, AwayCard.tsx, says what the routes and the purse did meanwhile) or a
// sale made by pressing Sell at the quay (the Trade panel's own toast says that).
// SLICE B (2026-11-16): a profitable trip between two harbours offers "Make route" (src/live/ArrivalRepeat.tsx).
// 0468 (P2, each level opens something): under a level line, what that level OPENS ("Opens: Ships a fleet +1"): the served list of
// what each level gives (`world.levels()`, public.level_benefits, worded by levelWords.levelOpens). Asked only while a level line is on
// the card (the same cached read the goal card holds), so a closed card costs no read. Nothing served for that level: no line.
// An overlay: fixed, never in the flow, pointer-events only on the card itself; reduced motion is index.css's rule.

const SHOWN_MS = 20_000

interface Sale {
  id: string
  good: string
  qty: number | null
  /** The server's profit for the sale, or its total when no profit was on record. */
  figure: number | null
  /** Which of the two the figure is, so it is printed with its word: Profit / Loss, or Total. */
  kind: MoneyKind
}

interface Arrival {
  id: string
  /** Port CODE, or null for open water. */
  to: string | null
  /** Port CODE she sailed from, or null for open water (or a report that does not name it). */
  from: string | null
  /** The fleet's NAME, as the events carry it. */
  fleet: string | null
  sales: Sale[]
}

interface Card {
  arrivals: Arrival[]
  /** 0356: each track's LEVEL_UP events on this card, as one line: the highest level reached and the Reputation they gave. */
  levels: LevelLine[]
  /** How many new ports the served count gained on the read(s) this card holds. */
  newPorts: number
  /** 0352: the Reputation the served book gained on the read(s) this card holds (earns only). */
  reputation: number
}

interface LevelLine {
  /** The level's code (`public.level_skills`): since 0411 every level raised by doing fires the same LEVEL_UP. */
  track: string
  level: number
  /** 0468: the lowest level crossed on this card, so "Opens:" names what every level crossed opened, not only the highest. */
  low: number
  reputation: number
}

/** The LEVEL_UP events among these, one line a track: the highest level, and the Reputation of all its crossings added. */
function levelLines(events: LedgerEvent[], into: LevelLine[] = []): LevelLine[] {
  const lines = [...into]
  for (const e of events) {
    if (e.kind !== 'LEVEL_UP') continue
    const track = str(e.payload, 'track')
    const level = num(e.payload, 'level')
    if (track === null || track === '' || level === null) continue
    const reputation = num(e.payload, 'reputation') ?? 0
    const at = lines.findIndex((l) => l.track === track)
    if (at < 0) lines.push({ track, level, low: level, reputation })
    else lines[at] = { track, level: Math.max(lines[at].level, level), low: Math.min(lines[at].low, level), reputation: lines[at].reputation + reputation }
  }
  return lines
}

function saleOf(e: LedgerEvent): Sale {
  const profit = num(e.payload, 'profit')
  return { id: e.id, good: str(e.payload, 'good') ?? '', qty: num(e.payload, 'qty'), figure: profit ?? num(e.payload, 'total'), kind: profit === null ? 'total' : 'profit' }
}

/** The facts of one read: the events not seen before, against the house as it stood on the read before. */
function readArrival(fresh: LedgerEvent[], before: PlayerHouse | null, now: PlayerHouse | null, held: LevelLine[]): Card | null {
  const reports = fresh.filter((e) => e.kind === 'VOYAGE_REPORT')
  if (reports.length === 0) return null
  const arrivals = reports.map((r): Arrival => {
    const to = str(r.payload, 'to')
    const fleet = str(r.payload, 'fleet')
    return {
      id: r.id,
      to,
      from: str(r.payload, 'from'),
      fleet,
      sales: fresh.filter((e) => e.kind === 'SOLD' && str(e.payload, 'fleet') === fleet && str(e.payload, 'port') === to).map(saleOf),
    }
  })
  const levels = levelLines(fresh, held)
  const newPorts = before && now ? Math.max(0, now.levels.exploration.ports_reached - before.levels.exploration.ports_reached) : 0
  // 0352: the served book's rows past the row the read before ended on. Earns only; the server's own amounts, added.
  // 0356: a level's gift is not in this sum: it stands on its own level line.
  const seenSeq = before?.reputation?.seq ?? 0
  const reputation = (now?.reputation?.recent ?? []).reduce((n, r) => (r.seq > seenSeq && r.delta > 0 && r.kind !== 'level' ? n + r.delta : n), 0)
  return { arrivals, levels, newPorts, reputation }
}

function merge(a: Card | null, b: Card): Card {
  if (!a) return b
  return {
    arrivals: [...a.arrivals, ...b.arrivals],
    levels: b.levels.reduce(
      (lines, y) =>
        lines.some((x) => x.track === y.track)
          ? lines.map((x) =>
              x.track === y.track ? { track: x.track, level: Math.max(x.level, y.level), low: Math.min(x.low, y.low), reputation: x.reputation + y.reputation } : x,
            )
          : [...lines, y],
      a.levels,
    ),
    newPorts: a.newPorts + b.newPorts,
    reputation: a.reputation + b.reputation,
  }
}

export function ArrivalCard() {
  const t = useT()
  const locale = useLocale()
  const navigate = useNavigate()
  const portByCode = useWorld((s) => s.portByCode)
  const [card, setCard] = useState<Card | null>(null)
  const seen = useRef<Set<string> | null>(null)
  const open = useRef(false)   // 0356: a card is on the glass (read by the store's listener, which outlives a render)
  const [logOpen, setLogOpen] = useState(false)   // 0353: a raid's log is open on the card, and the card waits
  const [repeatHeld, setRepeatHeld] = useState(false)   // slice B: Make route is on the wire or refused, and the card waits

  useEffect(() => {
    let before: PlayerHouse | null = null
    // 0356: the level-ups that came on a read with no arrival and no open card. The next arrival's card says them.
    let held: LevelLine[] = []
    const read = (s: ReturnType<typeof useWorld.getState>) => {
      if (s.phase !== 'ready') return
      if (seen.current === null) {
        // THE BASELINE: the first ready read is what the player already had. Nothing in it is announced.
        seen.current = new Set(s.events.map((e) => e.id))
        before = s.player
        return
      }
      const fresh = s.events.filter((e) => !seen.current!.has(e.id))
      fresh.forEach((e) => seen.current!.add(e.id))
      const found = readArrival(fresh, before, s.player, held)
      before = s.player
      if (found) {
        held = []
        setCard((c) => merge(c, found))
        return
      }
      // No arrival on this read. A level-up joins the card that is open; with no card open it is held for the next one.
      const lines = levelLines(fresh)
      if (lines.length === 0) return
      if (open.current) setCard((c) => (c ? merge(c, { arrivals: [], levels: lines, newPorts: 0, reputation: 0 }) : c))
      else held = levelLines(fresh, held)
    }
    read(useWorld.getState())
    return useWorld.subscribe(read)
  }, [])

  useEffect(() => {
    if (card === null || logOpen || repeatHeld) return
    const id = window.setTimeout(() => setCard(null), SHOWN_MS)
    return () => window.clearTimeout(id)
  }, [card, logOpen, repeatHeld])

  useEffect(() => {
    open.current = card !== null
  }, [card])

  if (card === null) return null
  const sales = card.arrivals.flatMap((a) => a.sales)
  const net = sales.reduce((n, s) => n + (s.figure ?? 0), 0)
  const only = card.arrivals.length === 1 ? card.arrivals[0].to : null
  const port = only ? portNameOf(portByCode, only) : null
  // SLICE B (2026-11-16): one trip, between two harbours, sold at a served profit, may be repeated as a route
  // (src/live/ArrivalRepeat.tsx decides the rest, once, when the card comes up).
  const one = card.arrivals.length === 1 ? card.arrivals[0] : null
  const repeat =
    one && one.to && one.from && one.fleet && sales.length > 0 && sales.every((s) => s.kind === 'profit') && net > 0
      ? { id: one.id, trip: { fleet: one.fleet, here: one.to, there: one.from } }
      : null
  return (
    // Over the page, clear of the bar on a phone (bottom-24) and beside the rail from `lg`, centred on the page and not the window
    // (screenLayout.ts `glassBesideRailClass`, THE SHELL).
    <div className={`pointer-events-none ${glassBesideRailClass()} bottom-24 z-60 flex justify-center px-4 lg:bottom-10`} data-testid="arrival-card-wrap">
      <div
        role="status"
        aria-live="polite"
        data-testid="arrival-card"
        data-net={sales.length ? net : undefined}
        className={FLOAT_CARD_CLASS}
      >
        <p className="text-t-label font-semibold">{port ? t('feed.arrivedAt', { port }) : t('feed.arrived')}</p>
        {sales.map((s) => (
          <p key={s.id} className="mt-1 flex justify-between gap-3 text-t-body" data-testid="arrival-sale">
            <span className="min-w-0 break-words">{t('feed.arrSold', { n: s.qty === null ? '' : formatInt(s.qty), good: goodWordOf(s.good) })}</span>
            {/* THE FIGURE HAS ITS WORD (2026-11-11, the trade-flow slice): "−1,182" stood bare. It is the sale's served profit
                ("Profit" / "Loss": the sale's money less what the goods cost, before the voyage's wages), or its total. */}
            {s.figure !== null && (
              <span className="flex shrink-0 items-baseline gap-2" data-testid="arrival-figure" data-kind={s.kind}>
                <span className="text-t-caption text-ink-muted" data-testid="arrival-figure-word">
                  {moneyWord(s.kind, s.figure)}
                </span>
                <span className={`font-semibold tabular-nums ${s.kind !== 'profit' ? '' : s.figure < 0 ? 'text-danger' : 'text-success'}`}>{moneyFigure(s.kind, s.figure)}</span>
              </span>
            )}
          </p>
        ))}
        <ArrivalRaids ids={card.arrivals.map((a) => a.id)} onOpen={setLogOpen} />
        {card.newPorts > 0 && (
          <p className="mt-1 text-t-body text-accent" data-testid="arrival-newport">
            {t('feed.newPort')}
          </p>
        )}
        {card.levels.map((l) => (
          <p key={l.track} className="mt-1 text-t-body text-accent" data-testid="arrival-level" data-track={l.track} data-level={l.level} data-reputation={l.reputation}>
            {l.reputation > 0
              ? t('feed.levelUpRep', { track: levelName(locale, l.track), n: l.level, rep: formatInt(l.reputation) })
              : t('feed.levelUp', { track: levelName(locale, l.track), n: l.level })}
          </p>
        ))}
        {card.levels.length > 0 && <ArrivalOpens levels={card.levels} />}
        {card.reputation > 0 && (
          <p className="mt-1 text-t-body text-accent" data-testid="arrival-reputation" data-reputation={card.reputation}>
            {t('feed.repEarned', { n: formatInt(card.reputation) })}
          </p>
        )}
        {repeat && <ArrivalRepeat key={repeat.id} trip={repeat.trip} onHold={setRepeatHeld} />}
        <div className="mt-3 flex gap-2">
          <Button
            variant="primary"
            size="sm"
            className="flex-1"
            data-testid="arrival-next"
            onClick={() => {
              setCard(null)
              navigate(HOME_TAB)
            }}
          >
            {tabWord(locale, HOME_TAB)}
          </Button>
          <Button variant="secondary" size="sm" className="flex-1" data-testid="arrival-close" onClick={() => setCard(null)}>
            {t('feed.close')}
          </Button>
        </div>
      </div>
    </div>
  )
}

/** 0468: what each level on the card opens, one line a level that opens something: "Opens: Ships a fleet +1". The served list only. */
function ArrivalOpens({ levels }: { levels: LevelLine[] }) {
  const t = useT()
  const locale = useLocale()
  const read = useServedRead<LevelsView>('levels', () => worldLevels(), { name: 'worldLevels' })
  const v = read.view
  if (!v || !v.company) return null
  const lines = levels
    .map((l) => {
      const skill = v.level_skills.skills.find((s) => s.code === l.track)
      const crossed = Array.from({ length: l.level - l.low + 1 }, (_, i) => l.low + i)
      return { l, what: skill ? crossed.flatMap((n) => levelOpens(locale, n, skill.benefits)) : [] }
    })
    .filter((x) => x.what.length > 0)
  return (
    <>
      {lines.map(({ l, what }) => (
        <p key={l.track} className="mt-1 text-t-body text-accent" data-testid="arrival-opens" data-track={l.track} data-level={l.level}>
          {t('command.lvOpens', { what: what.join(', ') })}
        </p>
      ))}
    </>
  )
}
