import { useEffect, useRef, useState } from 'react'
import { useShellState } from '../../app/shellState'
import { Chip, ChipRow, Empty, Row, SheetSection } from '../../components/ui'
import { formatDucatsDelta, formatRelative } from '../../lib/format'
import { properName, translateMaybe, useLocale, useT } from '../../lib/i18n'
import { worldMoneyFeed, type MoneyMove, type RpcResult } from '../../lib/rpc'
import { useLiveRead } from './statsLive'
import { emptyDrip, enqueue, step, type Drip } from './moneyDrip'
import { SECTORS, sectorOf, type Sector } from './moneySectors'

// THE MONEY LOG — every money move in the world as it happens, beside World money (0235; the owner, row 219,
// 2026-10-26: *"beside the stat, world money, i want to see the live log of each happenings that cause money -
// drop and gain, at the right side. possible?"*).
//
// ONE READ, world.money_feed: both money books (a company's ledger, a city's flows), newest first. Each row is ONE
// purse's gain or loss — a sale is two rows, the company's "+1,200 · Casa X · Sold" and the city's "−1,200 ·
// Lisbon · Bought" (decided by default in the migration). Green for a gain, red for a drop, and how long ago.
//
// ON THE TAB'S ONE WAY OF ASKING (statsLive.ts, useLiveRead): asked on mount and every second while the face is
// open, never stacked, a hidden page skips. Each ask names only what is newer than the newest row held — less
// LATE_MS, because a job's moves carry the instant its transaction BEGAN and land when it commits (the
// arrivals tick, every 15 s, ran up to 12.5 s on prod 2026-10-26), so a batch can land older than a row already
// shown. Rows merge by key and the newest KEEP are held, so the overlap never doubles a row.
//
// THE DRIP (moneyDrip.ts): the arrivals job writes rows in batches every 15 s, so new rows are not shown all at once —
// they are queued oldest first and revealed a few per second; the player's own rows show at once. Each row keeps its
// real time. (No animation, so reduced motion is the same.)
//
// THE LAYOUT: on a phone, under World money; on the wide glass, in the column's right gutter (the tray's room —
// the Stats tab opens no tray), its heading on World money's line (World money's own top margin collapses
// through the face, so the log's section drops its margin there). A name is never cut: the label wraps. "5 s ago" is
// read against the shell's one clock, which is the server's (formatRelative).

// KEEP is what is held and filtered (a filter must not be empty after a minute); ASK is one read's size.
const KEEP = 300
const ASK = 100
const FILTER_KEY = 'bv:moneylog-filter'
type Pick = 'all' | Sector
type Filter = { pick: Pick; mine: boolean }

function loadFilter(): Filter {
  try {
    const j = JSON.parse(localStorage.getItem(FILTER_KEY) ?? 'null') as Partial<Filter> | null
    const pick = j?.pick
    return { pick: pick === 'all' || (SECTORS as readonly string[]).includes(pick as string) ? (pick as Pick) : 'all', mine: j?.mine === true }
  } catch {
    return { pick: 'all', mine: false }
  }
}
const LATE_MS = 20_000

const atMs = (m: MoneyMove) => Date.parse(m.at)

/** Newest first on (at, key) — the server's order. */
function newestFirst(a: MoneyMove, b: MoneyMove): number {
  const d = atMs(b) - atMs(a)
  if (d !== 0) return d
  if (a.at !== b.at) return a.at < b.at ? 1 : -1
  return a.key < b.key ? 1 : a.key > b.key ? -1 : 0
}

function merge(held: MoneyMove[], got: MoneyMove[]): MoneyMove[] {
  const byKey = new Map<string, MoneyMove>()
  for (const m of held) byKey.set(m.key, m)
  for (const m of got) byKey.set(m.key, m)
  return [...byKey.values()].sort(newestFirst).slice(0, KEEP)
}

function useMoneyFeed(): { view: MoneyMove[] | null; loading: boolean } {
  const held = useRef<MoneyMove[]>([])
  const seen = useRef<Set<string> | null>(null)
  const drip = useRef<Drip>(emptyDrip)
  const [shown, setShown] = useState<MoneyMove[] | null>(null)
  const read = useLiveRead<MoneyMove[]>('stats:money-feed', async (): Promise<RpcResult<MoneyMove[]>> => {
    const newest = held.current[0]
    const after = newest === undefined ? null : new Date(atMs(newest) - LATE_MS).toISOString()
    const r = await worldMoneyFeed(after, ASK)
    if (!r.ok) return r
    held.current = merge(held.current, r.value.moves)
    if (seen.current === null) {
      // the first read is history: shown at once
      seen.current = new Set(r.value.moves.map((m) => m.key))
      setShown(held.current)
    } else {
      const fresh = r.value.moves.filter((m) => !seen.current!.has(m.key))
      for (const m of fresh) seen.current.add(m.key)
      const mine = fresh.filter((m) => m.own)
      if (mine.length > 0) setShown((s) => merge(s ?? [], mine))
      drip.current = enqueue(drip.current, fresh.filter((m) => !m.own))
    }
    return { ok: true, value: held.current }
  })
  useEffect(() => {
    const id = setInterval(() => {
      const { released, next } = step(drip.current)
      if (released.length === 0) return
      drip.current = next
      setShown((s) => merge(s ?? [], released))
    }, 1000)
    return () => clearInterval(id)
  }, [])
  return { view: read.view === null ? null : shown ?? read.view, loading: read.loading }
}

export function MoneyLog() {
  const t = useT()
  const locale = useLocale()
  const { nowMs } = useShellState()
  const { view } = useMoneyFeed()
  const [filter, setFilter] = useState<Filter>(loadFilter)
  if (view === null) return null

  const choose = (f: Filter) => {
    setFilter(f)
    try {
      localStorage.setItem(FILTER_KEY, JSON.stringify(f))
    } catch {
      /* storage may be blocked: the choice just is not remembered */
    }
  }
  const base = filter.mine ? view.filter((m) => m.own) : view
  const counts = new Map<Sector, number>()
  for (const m of base) {
    const k = sectorOf(m.kind, m.holder)
    counts.set(k, (counts.get(k) ?? 0) + 1)
  }
  const rows = filter.pick === 'all' ? base : base.filter((m) => sectorOf(m.kind, m.holder) === filter.pick)

  const word = (m: MoneyMove) =>
    (m.holder === 'city' ? translateMaybe(locale, 'feed', `c_${m.kind}`) : null) ??
    translateMaybe(locale, 'feed', `k_${m.kind}`) ??
    m.word
  const who = (m: MoneyMove) => (m.holder === 'city' ? properName('port', m.who, m.who, locale) : m.who)

  return (
    <div className="mt-6 lg:absolute lg:top-0 lg:left-[calc(100%+1.5rem)] lg:mt-0 lg:w-[26rem] lg:[&>section]:mt-0!" data-testid="money-log">
      <SheetSection heading={t('feed.heading')}>
        <ChipRow label={t('feed.filter')} className="mb-2">
          <Chip on={filter.pick === 'all'} onClick={() => choose({ ...filter, pick: 'all' })} data-testid="money-chip-all">
            {t('feed.s_all')} {base.length}
          </Chip>
          <Chip on={filter.mine} onClick={() => choose({ ...filter, mine: !filter.mine })} data-testid="money-chip-mine">
            {t('feed.s_mine')}
          </Chip>
          {SECTORS.map((k) => (
            <Chip key={k} on={filter.pick === k} onClick={() => choose({ ...filter, pick: k })} data-testid={`money-chip-${k}`}>
              {t(`feed.s_${k}`)} {counts.get(k) ?? 0}
            </Chip>
          ))}
        </ChipRow>
        {rows.length === 0 ? (
          <Empty>{t('feed.none')}</Empty>
        ) : (
          <div className="bv-scroll max-h-[28rem] overflow-y-auto lg:max-h-[36rem]">
            {rows.map((m, i, all) => {
              const gain = m.delta > 0
              return (
                <Row
                  key={m.key}
                  label={
                    <span className="break-words">
                      <span className={`tabular-nums ${gain ? 'text-success' : 'text-danger'}`}>{formatDucatsDelta(m.delta)}</span>
                      {' · '}
                      <span className={m.own ? 'text-accent' : undefined}>{who(m)}</span>
                      {m.own && <span className="text-t-caption text-ink-faint"> ({t('feed.you')})</span>}
                      {' · '}
                      {word(m)}
                    </span>
                  }
                  value={
                    <span className="text-t-caption text-ink-faint">
                      {formatRelative(atMs(m), nowMs, { seconds: true })}
                    </span>
                  }
                  hairline={i < all.length - 1}
                  data-testid="money-move"
                  data-holder={m.holder}
                  data-kind={m.kind}
                  data-tone={gain ? 'gain' : 'drop'}
                />
              )
            })}
          </div>
        )}
      </SheetSection>
    </div>
  )
}
