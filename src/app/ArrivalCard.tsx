import { useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Button, glassBesideRailClass } from '../components/ui'
import { formatInt, moneyFigure, moneyWord, type MoneyKind } from '../lib/format'
import { num, str } from '../lib/json'
import { useT } from '../lib/i18n'
import type { LedgerEvent, PlayerHouse } from '../lib/rpc'
import { portNameOf, useWorld } from '../live/worldStore'

// THE ARRIVAL CARD (owner row 307, the remaster's S3): a fleet comes in, sells, and the player was told nothing. One
// card, over whatever tab is open, says what the arrival did. It reads FACTS THE SERVER ALREADY REPORTS and adds none:
//   - an arrival is a new VOYAGE_REPORT event (the player's OWN ledger, so another player's fleet is never in it);
//   - its sales are the new SOLD events of that fleet at that port: qty, good and the server's own `profit` (0081);
//   - a level-up is a served level (house.levels.*.level) that is higher than on the read before;
//   - "New port" is the served `ports_reached` going up on that same read.
// It never computes profit or a level. A sale whose profit the server did not record prints the sale's total instead
// (also served), never a guess. Arrivals that land while a card is open MERGE into it. Next goes to the Trade desk.
// WHAT IT DOES NOT DO: announce what happened while the page was closed (nothing served says "unseen"; the first read
// after a load is the baseline) or a sale made by pressing Sell at the quay (the Trade panel's own toast says that).
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
  sales: Sale[]
}

interface Card {
  arrivals: Arrival[]
  levels: { track: 'trading' | 'exploration'; level: number }[]
  /** How many new ports the served count gained on the read(s) this card holds. */
  newPorts: number
  /** 0352: the Reputation the served book gained on the read(s) this card holds (earns only). */
  reputation: number
}

const TRACKS = ['trading', 'exploration'] as const

function saleOf(e: LedgerEvent): Sale {
  const profit = num(e.payload, 'profit')
  return { id: e.id, good: str(e.payload, 'good') ?? '', qty: num(e.payload, 'qty'), figure: profit ?? num(e.payload, 'total'), kind: profit === null ? 'total' : 'profit' }
}

/** The facts of one read: the events not seen before, against the house as it stood on the read before. */
function readArrival(fresh: LedgerEvent[], before: PlayerHouse | null, now: PlayerHouse | null): Card | null {
  const reports = fresh.filter((e) => e.kind === 'VOYAGE_REPORT')
  if (reports.length === 0) return null
  const arrivals = reports.map((r): Arrival => {
    const to = str(r.payload, 'to')
    const fleet = str(r.payload, 'fleet')
    return {
      id: r.id,
      to,
      sales: fresh.filter((e) => e.kind === 'SOLD' && str(e.payload, 'fleet') === fleet && str(e.payload, 'port') === to).map(saleOf),
    }
  })
  const levels: Card['levels'] = []
  if (before && now) {
    for (const track of TRACKS) {
      const level = now.levels[track].level
      if (level > before.levels[track].level) levels.push({ track, level })
    }
  }
  const newPorts = before && now ? Math.max(0, now.levels.exploration.ports_reached - before.levels.exploration.ports_reached) : 0
  // 0352: the served book's rows past the row the read before ended on. Earns only; the server's own amounts, added.
  const seenSeq = before?.reputation?.seq ?? 0
  const reputation = (now?.reputation?.recent ?? []).reduce((n, r) => (r.seq > seenSeq && r.delta > 0 ? n + r.delta : n), 0)
  return { arrivals, levels, newPorts, reputation }
}

function merge(a: Card | null, b: Card): Card {
  if (!a) return b
  return {
    arrivals: [...a.arrivals, ...b.arrivals],
    levels: [...a.levels.filter((x) => !b.levels.some((y) => y.track === x.track)), ...b.levels],
    newPorts: a.newPorts + b.newPorts,
    reputation: a.reputation + b.reputation,
  }
}

export function ArrivalCard() {
  const t = useT()
  const navigate = useNavigate()
  const portByCode = useWorld((s) => s.portByCode)
  const [card, setCard] = useState<Card | null>(null)
  const seen = useRef<Set<string> | null>(null)

  useEffect(() => {
    let before: PlayerHouse | null = null
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
      const found = readArrival(fresh, before, s.player)
      before = s.player
      if (found) setCard((c) => merge(c, found))
    }
    read(useWorld.getState())
    return useWorld.subscribe(read)
  }, [])

  useEffect(() => {
    if (card === null) return
    const id = window.setTimeout(() => setCard(null), SHOWN_MS)
    return () => window.clearTimeout(id)
  }, [card])

  if (card === null) return null
  const sales = card.arrivals.flatMap((a) => a.sales)
  const net = sales.reduce((n, s) => n + (s.figure ?? 0), 0)
  const only = card.arrivals.length === 1 ? card.arrivals[0].to : null
  const port = only ? portNameOf(portByCode, only) : null
  return (
    // Over the page, clear of the bar on a phone (bottom-24) and beside the rail from `lg`, centred on the page and not the window
    // (screenLayout.ts `glassBesideRailClass`, THE SHELL).
    <div className={`pointer-events-none ${glassBesideRailClass()} bottom-24 z-60 flex justify-center px-4 lg:bottom-10`} data-testid="arrival-card-wrap">
      <div
        role="status"
        aria-live="polite"
        data-testid="arrival-card"
        data-net={sales.length ? net : undefined}
        className="bv-fade-in pointer-events-auto w-full max-w-sm rounded-card bg-surface-2 p-4 text-ink shadow-float"
      >
        <p className="text-t-label font-semibold">{port ? t('feed.arrivedAt', { port }) : t('feed.arrived')}</p>
        {sales.map((s) => (
          <p key={s.id} className="mt-1 flex justify-between gap-3 text-t-body" data-testid="arrival-sale">
            <span className="min-w-0 break-words">{t('feed.arrSold', { n: s.qty === null ? '' : formatInt(s.qty), good: s.good })}</span>
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
        {card.newPorts > 0 && (
          <p className="mt-1 text-t-body text-accent" data-testid="arrival-newport">
            {t('feed.newPort')}
          </p>
        )}
        {card.levels.map((l) => (
          <p key={l.track} className="mt-1 text-t-body text-accent" data-testid="arrival-level">
            {t('feed.levelUp', { track: t(l.track === 'trading' ? 'command.lvTrading' : 'command.lvExploration'), n: l.level })}
          </p>
        ))}
        {card.reputation > 0 && (
          <p className="mt-1 text-t-body text-accent" data-testid="arrival-reputation" data-reputation={card.reputation}>
            {t('feed.repEarned', { n: formatInt(card.reputation) })}
          </p>
        )}
        <div className="mt-3 flex gap-2">
          <Button
            variant="primary"
            size="sm"
            className="flex-1"
            data-testid="arrival-next"
            onClick={() => {
              setCard(null)
              navigate('/command')
            }}
          >
            {t('feed.next')}
          </Button>
          <Button variant="secondary" size="sm" className="flex-1" data-testid="arrival-close" onClick={() => setCard(null)}>
            {t('feed.close')}
          </Button>
        </div>
      </div>
    </div>
  )
}
