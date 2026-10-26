import { useRef } from 'react'
import { useShellState } from '../../app/shellState'
import { Empty, Row, SheetSection } from '../../components/ui'
import { formatDucatsDelta, formatRelative } from '../../lib/format'
import { properName, translateMaybe, useLocale, useT } from '../../lib/i18n'
import { worldMoneyFeed, type MoneyMove, type RpcResult } from '../../lib/rpc'
import { useLiveRead } from './statsLive'

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
// THE LAYOUT: on a phone, under World money; on the wide glass, in the column's right gutter (the tray's room —
// the Stats tab opens no tray), its heading on World money's line (World money's own top margin collapses
// through the face, so the log's section drops its margin there). A name is never cut: the label wraps. "5 s ago" is
// read against the shell's one clock, which is the server's (formatRelative).

const KEEP = 100
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
  return useLiveRead<MoneyMove[]>('stats:money-feed', async (): Promise<RpcResult<MoneyMove[]>> => {
    const newest = held.current[0]
    const after = newest === undefined ? null : new Date(atMs(newest) - LATE_MS).toISOString()
    const r = await worldMoneyFeed(after, KEEP)
    if (!r.ok) return r
    held.current = merge(held.current, r.value.moves)
    return { ok: true, value: held.current }
  })
}

export function MoneyLog() {
  const t = useT()
  const locale = useLocale()
  const { nowMs } = useShellState()
  const { view } = useMoneyFeed()
  if (view === null) return null

  const word = (m: MoneyMove) =>
    (m.holder === 'city' ? translateMaybe(locale, 'feed', `c_${m.kind}`) : null) ??
    translateMaybe(locale, 'feed', `k_${m.kind}`) ??
    m.word
  const who = (m: MoneyMove) => (m.holder === 'city' ? properName('port', m.who, m.who, locale) : m.who)

  return (
    <div className="mt-6 lg:absolute lg:top-0 lg:left-[calc(100%+1.5rem)] lg:mt-0 lg:w-[26rem] lg:[&>section]:mt-0!" data-testid="money-log">
      <SheetSection heading={t('feed.heading')}>
        {view.length === 0 ? (
          <Empty>{t('feed.none')}</Empty>
        ) : (
          <div className="bv-scroll max-h-[28rem] overflow-y-auto lg:max-h-[36rem]">
            {view.map((m, i, all) => {
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
