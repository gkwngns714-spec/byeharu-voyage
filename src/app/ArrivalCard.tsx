import { useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Button, FLOAT_CARD_CLASS, glassBesideRailClass, masteredTone } from '../components/ui'
import { formatInt, moneyFigure, moneyWord, type MoneyKind } from '../lib/format'
import { num, str } from '../lib/json'
import { useLocale, useT } from '../lib/i18n'
import { levelName } from '../live/levelWords'
import { levelLines, type LevelLine } from './levelLines'
import type { LedgerEvent, LogbookFound, LogbookSale, LogbookSetDone, MasterySale, PlayerHouse } from '../lib/rpc'
import { goodWordOf, portNameOf, useWorld } from '../live/worldStore'
import { ArrivalRaids } from '../live/ArrivalRaids'
import { bountyOf, type PaidBounty } from '../live/bountyPaid'
import { bountyName } from '../live/bountyWords'
import { ArrivalRepeat } from '../live/ArrivalRepeat'
import { ArrivalSighting } from '../live/ArrivalSighting'
import { sightingOf, type Sighting } from '../live/sightingOf'
import { arrivalLogbookOf, saleLogbookOf } from '../live/logbookOf'
import { ArrivalFound, ArrivalNewGood, ArrivalSetDone } from '../live/ArrivalLogbook'
import { saleMasteryOf } from '../live/goodsMastery'
import { MasteryUpChip } from '../live/MasteryUp'
import { HOME_TAB, tabWord } from './navTabs'

// THE ARRIVAL CARD (owner row 307, the remaster's S3): a fleet comes in, sells, and the player was told nothing. One
// card, over whatever tab is open, says what the arrival did. It reads FACTS THE SERVER ALREADY REPORTS and adds none:
//   - an arrival is a new VOYAGE_REPORT event (the player's OWN ledger, so another player's fleet is never in it);
//   - its sales are the new SOLD events of that fleet at that port: qty, good and the server's own `trip_net` (0474: the sale's profit
//     less its profit tax, the wages it paid and the dock fee of this call: what her purse moved for the trip, the Buy & sell sheet's
//     figure; an event before 0474 has none, and its `profit` (0081) is printed as before);
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
// 0468 (P2, each level opens something): what a level OPENS stood under its line here ("Opens: Ships a fleet +1"). Since roadmap slice 10
// it stands on the level-up card (LevelUpCard.tsx), the one loud moment a level has; this card keeps the level's line and its gift.
// An overlay: fixed, never in the flow, pointer-events only on the card itself; reduced motion is index.css's rule.
// 0477 (roadmap slice 7): an EARLY_SIGHTING event (a weak pirate's sighting, told at its close) is said on the card of her next arrival
// (src/live/ArrivalSighting.tsx: what happened, what insurance and guns would have done). Told while her fleet is still at sea it waits for
// that arrival; told after she came in (or while a card is open) it is said at once.
// 0478 (roadmap slice 9, the logbook): a VOYAGE_REPORT's `logbook.found` is the "Discovered" moment at the card's head (it replaces
// "New port"), a SOLD event's `logbook` is "New: Cinnamon · Spice 3 / 22" under its sale, and a set finished is its own line with the
// Reputation it paid (src/live/ArrivalLogbook.tsx; that Reputation is not counted again in the card's Reputation line). Dark: never there.
// 0479 (roadmap slice 11, goods mastery): a SOLD event's mastery names the sale line in gold when the good stands at the top of its
// ladder (the server's `next` is null), and a level it raised is a chip under the line (src/live/MasteryUp.tsx). Dark: never there.

const SHOWN_MS = 20_000

interface Sale {
  id: string
  good: string
  qty: number | null
  /** The server's net for the trip (`trip_net`, 0474), else its profit (an event before 0474), or its total when no profit was on record. */
  figure: number | null
  /** The sale's own margin as served (`profit`: its money less what the goods cost; what Reputation counts, 0352). */
  profit: number | null
  /** Which of the two the figure is, so it is printed with its word: Profit / Loss, or Total. */
  kind: MoneyKind
  /** 0478: the good's first sale ("New: Cinnamon · Spice 3 / 22"), when the logbook is lit; else null. */
  logbook: LogbookSale | null
  /** 0479: her mastery of the good after the sale (its level, whether it rose), when the ladder is lit; else null. */
  mastery: MasterySale | null
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
  /** 0478: a first harbour (the "Discovered" moment) and the sets it finished, when the logbook is lit. */
  found: LogbookFound | null
  sets: LogbookSetDone[]
}

interface Card {
  arrivals: Arrival[]
  /** 0356: each track's LEVEL_UP events on this card, as one line: the highest level reached and the Reputation they gave. */
  levels: LevelLine[]
  /** How many new ports the served count gained on the read(s) this card holds. */
  newPorts: number
  /** 0352: the Reputation the served book gained on the read(s) this card holds (earns only). */
  reputation: number
  /** 0471: the bounties collected on the read(s) this card holds (a fight's BATTLE_REPORT that paid one). */
  bounties: PaidBounty[]
  /** 0477: the early sightings told (EARLY_SIGHTING), held until her arrival when told at sea. */
  sightings: Sighting[]
}

function saleOf(e: LedgerEvent): Sale {
  const profit = num(e.payload, 'profit')
  const net = num(e.payload, 'trip_net') ?? profit
  return { id: e.id, good: str(e.payload, 'good') ?? '', qty: num(e.payload, 'qty'), figure: net ?? num(e.payload, 'total'), kind: net === null ? 'total' : 'profit', profit, logbook: saleLogbookOf(e), mastery: saleMasteryOf(e) }
}

/** The facts of one read: the events not seen before, against the house as it stood on the read before. */
function readArrival(fresh: LedgerEvent[], before: PlayerHouse | null, now: PlayerHouse | null, held: LevelLine[], sightings: Sighting[]): Card | null {
  const reports = fresh.filter((e) => e.kind === 'VOYAGE_REPORT')
  // 0471: a fight that paid a bounty brings the card up on its own, as an arrival does
  const bounties = fresh.flatMap((e) => bountyOf(e) ?? [])
  if (reports.length === 0 && bounties.length === 0) return null
  const arrivals = reports.map((r): Arrival => {
    const to = str(r.payload, 'to')
    const fleet = str(r.payload, 'fleet')
    const lb = arrivalLogbookOf(r)
    return {
      id: r.id,
      found: lb?.found ?? null,
      sets: lb?.sets ?? [],
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
  const reputation = (now?.reputation?.recent ?? []).reduce((n, r) => (r.seq > seenSeq && r.delta > 0 && r.kind !== 'level' && r.kind !== 'logbook' ? n + r.delta : n), 0)
  return { arrivals, levels, newPorts, reputation, bounties, sightings }
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
    bounties: [...a.bounties, ...b.bounties],
    sightings: [...a.sightings, ...b.sightings],
  }
}

/** A card with nothing on it but these sightings (told after she came in, or joining a card that is open). */
function sightingCard(sightings: Sighting[]): Card {
  return { arrivals: [], levels: [], newPorts: 0, reputation: 0, bounties: [], sightings }
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
    // 0477: the sightings told while her fleet was at sea, for her next arrival's card
    let heldSightings: Sighting[] = []
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
      const sighted = fresh.flatMap((e) => sightingOf(e) ?? [])
      const found = readArrival(fresh, before, s.player, held, [...heldSightings, ...sighted])
      before = s.player
      if (found) {
        held = []
        heldSightings = []
        setCard((c) => merge(c, found))
        return
      }
      // 0477: a sighting with no arrival on this read: said on the open card, or at once when her fleet is not at sea, else held
      if (sighted.length > 0) {
        const atSea = (x: Sighting) => s.fleets.some((f) => f.name === x.fleet && f.voyage != null)
        const now = open.current ? sighted : sighted.filter((x) => !atSea(x))
        heldSightings = [...heldSightings, ...sighted.filter((x) => !now.includes(x))]
        if (now.length > 0) setCard((c) => merge(c, sightingCard(now)))
      }
      // No arrival on this read. A level-up joins the card that is open; with no card open it is held for the next one.
      const lines = levelLines(fresh)
      if (lines.length === 0) return
      if (open.current) setCard((c) => (c ? merge(c, { arrivals: [], levels: lines, newPorts: 0, reputation: 0, bounties: [], sightings: [] }) : c))
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
        <p className="text-t-label font-semibold">
          {card.arrivals.length === 0
            ? card.bounties.length > 0 ? t('bounty.title') : t('battle.sightTitle')
            : port ? t('feed.arrivedAt', { port }) : t('feed.arrived')}
        </p>
        {/* 0478: a first harbour's "Discovered" moment, at the head of the card */}
        {card.arrivals.map((a) => (a.found ? <ArrivalFound key={`found-${a.id}`} f={a.found} /> : null))}
        {sales.map((s) => (
          <div key={s.id}>
          <p className="mt-1 flex justify-between gap-3 text-t-body" data-testid="arrival-sale" data-profit={s.profit ?? undefined}>
            <span className={`min-w-0 break-words ${masteredTone(s.mastery?.next === null, '')}`} data-mastered={s.mastery?.next === null ? 'true' : undefined}>
              {t('feed.arrSold', { n: s.qty === null ? '' : formatInt(s.qty), good: goodWordOf(s.good) })}
            </span>
            {/* THE FIGURE HAS ITS WORD (2026-11-11, the trade-flow slice): "−1,182" stood bare. It is the trip's served net (0474:
                "Profit" / "Loss": the sale's money less what the goods cost, the profit tax, the wages and the dock fee; the sheet's
                figure and what the purse moved), or its total. */}
            {s.figure !== null && (
              <span className="flex shrink-0 items-baseline gap-2" data-testid="arrival-figure" data-kind={s.kind}>
                <span className="text-t-caption text-ink-muted" data-testid="arrival-figure-word">
                  {moneyWord(s.kind, s.figure)}
                </span>
                <span className={`font-semibold tabular-nums ${s.kind !== 'profit' ? '' : s.figure < 0 ? 'text-danger' : 'text-success'}`}>{moneyFigure(s.kind, s.figure)}</span>
              </span>
            )}
          </p>
          {/* 0478: the good's first sale: "New: Cinnamon · Spice 3 / 22" */}
          {s.logbook && <ArrivalNewGood s={s.logbook} />}
          {/* 0479: the good's mastery rose with this sale */}
          {s.mastery?.up && <MasteryUpChip m={s.mastery} className="mt-0.5" />}
          </div>
        ))}
        <ArrivalRaids ids={card.arrivals.map((a) => a.id)} onOpen={setLogOpen} />
        {card.sightings.map((s) => (
          <ArrivalSighting key={s.id} s={s} />
        ))}
        {card.bounties.map((b, i) => (
          <p key={`${b.battle}-${i}`} className="mt-1 text-t-body text-accent" data-testid="arrival-bounty" data-paid={b.paid}>
            {t('bounty.claimed', { n: formatInt(b.paid) })} · {bountyName(locale, b, portByCode)}
          </p>
        ))}
        {/* 0478: a logbook set finished by this card's arrivals or sales (its Reputation paid once) */}
        {[...card.arrivals.flatMap((a) => a.sets), ...sales.flatMap((s) => s.logbook?.sets ?? [])].map((x) => (
          <ArrivalSetDone key={`${x.set}-${x.code}`} s={x} />
        ))}
        {/* the served count's "New port"; the logbook's Discovered moment says it better, so it stands alone only when that is not there */}
        {card.newPorts > 0 && !card.arrivals.some((a) => a.found) && (
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
