import { useShellState } from '../../app/shellState'
import { Empty, FilterBar, Row } from '../../components/ui'
import { formatDucatsDelta, formatRelative } from '../../lib/format'
import { properName, translateMaybe, useLocale, useT } from '../../lib/i18n'
import type { MoneyMove } from '../../lib/rpc'
import { moveAtMs, type MoveFilter, type MovePick } from './moneyFeed'
import { SECTORS, type Sector } from './moneySectors'

// THE MONEY LOG (0235, owner row 219): every money move in the world as it happens. On the compact
// screens of 2026-10-31 it was ONE summary row with a count and a page behind it; since the unfold slice
// (2026-11-02, owner row 260) its rows stand in the Overview's list panel and its 13 sector tiles are one
// select that carries the same counts. The feed, the drip and the filter's memory are moneyFeed.ts.

/** The panel's controls for the moves view: which sector, and only mine. The counts ride the options, so
 *  the old tiles' `Bought 12` is still read — in the choice rather than beside it. */
export function MoneyLogControls({
  filter,
  onFilter,
  total,
  counts,
}: {
  filter: MoveFilter
  onFilter: (f: MoveFilter) => void
  total: number
  counts: ReadonlyMap<Sector, number>
}) {
  const t = useT()
  return (
    <FilterBar
      compact
      data-testid="money-log-filters"
      picks={[
        {
          id: 'sector',
          label: t('feed.filter'),
          options: [
            { id: 'all', label: `${t('feed.s_all')} ${total}` },
            ...SECTORS.map((k) => ({ id: k, label: `${t(`feed.s_${k}`)} ${counts.get(k) ?? 0}` })),
          ],
          value: filter.pick,
          onChange: (id) => onFilter({ ...filter, pick: id as MovePick }),
        },
      ]}
      toggles={[{ id: 'mine', label: t('feed.s_mine'), on: filter.mine, onChange: (on) => onFilter({ ...filter, mine: on }) }]}
    />
  )
}

export function MoneyRows({ rows }: { rows: readonly MoneyMove[] }) {
  const t = useT()
  const locale = useLocale()
  const { nowMs } = useShellState()
  if (rows.length === 0) return <Empty className="my-1">{t('feed.none')}</Empty>

  const word = (m: MoneyMove) =>
    (m.holder === 'city' ? translateMaybe(locale, 'feed', `c_${m.kind}`) : null) ??
    translateMaybe(locale, 'feed', `k_${m.kind}`) ??
    m.word
  const who = (m: MoneyMove) => (m.holder === 'city' ? properName('port', m.who, m.who, locale) : m.who)

  return (
    <>
      {rows.map((m, i) => {
        const gain = m.delta > 0
        return (
          // TWO LINES, ALWAYS (the unfold slice): the amount and whose it is, then what it was and when. One
          // sentence that wrapped at a company's long name was 35 px or 57 px by luck of the name; this is 48.
          <Row
            key={m.key}
            // THE AMOUNT AND THE NAME ARE BOXES, NOT INLINE RUNS (2026-11-02, the page laws): two inline spans that wrap across lines
            // have bounding boxes that cross (the name's box spans both lines), which is what the overlap law reads — and at 320 a
            // company's long name wrapped under its amount. A wrapping flex line keeps each its own box and the same words.
            label={
              <span className="flex flex-wrap items-baseline gap-x-1.5 break-words">
                <span className={`tabular-nums ${gain ? 'text-success' : 'text-danger'}`}>{formatDucatsDelta(m.delta)}</span>
                <span className="text-ink-faint" aria-hidden="true">
                  ·
                </span>
                <span className={`min-w-0 ${m.own ? 'text-accent' : ''}`}>{who(m)}</span>
                {m.own && <span className="text-t-caption text-ink-faint">({t('feed.you')})</span>}
              </span>
            }
            hairline={i < rows.length - 1}
            data-testid="money-move"
            data-holder={m.holder}
            data-kind={m.kind}
            data-tone={gain ? 'gain' : 'drop'}
          >
            <span className="block text-t-caption text-ink-faint">
              {word(m)} · {formatRelative(moveAtMs(m), nowMs, { seconds: true })}
            </span>
          </Row>
        )
      })}
    </>
  )
}
