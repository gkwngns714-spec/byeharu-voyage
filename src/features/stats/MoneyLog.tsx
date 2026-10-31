import { useEffect, useRef, useState } from 'react'
import { useShellState } from '../../app/shellState'
import { DetailPage, Empty, Row, SummaryRow, TileChoice, TileGrid } from '../../components/ui'
import { formatDucatsDelta, formatInt, formatRelative } from '../../lib/format'
import { properName, translateMaybe, useLocale, useT } from '../../lib/i18n'
import { worldMoneyFeed, type MoneyMove, type RpcResult } from '../../lib/rpc'
import { useLiveRead } from './statsLive'
import { emptyDrip, enqueue, step, type Drip } from './moneyDrip'
import { SECTORS, sectorOf, type Sector } from './moneySectors'

// THE MONEY LOG (0235, owner row 219): every money move in the world as it happens. On the compact
// Stats screen it is ONE summary row carrying the number of moves held; the sector grid and the
// live list live on a pop-up page (owner, 2026-10-31: compact screens, pages on press). The drip
// (moneyDrip.ts) reveals batches a few rows a second; each row keeps its real time.

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
  const [open, setOpen] = useState(false)
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
    <>
      <SummaryRow
        title={t('feed.heading')}
        figure={formatInt(base.length)}
        word={t('common.open')}
        onClick={() => setOpen(true)}
        data-testid="money-log"
      />
      {open && (
        <DetailPage title={t('feed.heading')} figure={formatInt(base.length)} onClose={() => setOpen(false)} data-testid="money-log-page">
          {/* THE FILTERS ARE A GRID (owner, 2026-10-31). Every sector owns one equal cell on fixed
              column lines, in the fixed order above. */}
          <TileGrid label={t('feed.filter')} columns={4} className="mb-2">
            <TileChoice on={filter.pick === 'all'} onClick={() => choose({ ...filter, pick: 'all' })} data-testid="money-chip-all">
              {t('feed.s_all')} {base.length}
            </TileChoice>
            <TileChoice on={filter.mine} onClick={() => choose({ ...filter, mine: !filter.mine })} data-testid="money-chip-mine">
              {t('feed.s_mine')}
            </TileChoice>
            {SECTORS.map((k) => (
              <TileChoice key={k} on={filter.pick === k} onClick={() => choose({ ...filter, pick: k })} data-testid={`money-chip-${k}`}>
                {t(`feed.s_${k}`)} {counts.get(k) ?? 0}
              </TileChoice>
            ))}
          </TileGrid>
          {rows.length === 0 ? (
            <Empty>{t('feed.none')}</Empty>
          ) : (
            rows.map((m, i, all) => {
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
            })
          )}
        </DetailPage>
      )}
    </>
  )
}
