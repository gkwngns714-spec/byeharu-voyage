import { Fragment, useMemo, useState, type ReactNode } from 'react'
import {
  ALL,
  Card,
  Figure,
  FilterBar,
  GoodClassMark,
  Icon,
  ListHeading,
  ListPanel,
  Note,
  PageSplit,
  RARITY_TIERS,
  RarityMark,
  Row,
  Tray,
  categoryLabel,
  goodClassRow,
  goodIcon,
  rarityLabel,
  useWide,
  type TrayDetent,
} from '../../components/ui'
import { COIN, formatFixed, formatInt, formatPct } from '../../lib/format'
import type { SnapshotGood } from '../../lib/rpc'
import { fold, foldedMatch } from '../../lib/text'
import { useWorld } from '../../live/worldStore'
import { optionsOf } from './codexFilters'
import { NoAnswer } from './NoAnswer'
import { useT } from '../../lib/i18n'

// THE GOODS FACE — every good this world trades, grouped under its kind, one figure a row, ON THE PAGE.
//
// THE PAGE, NOT THE PACKED COLUMN (2026-11-02, owner row 267: *"it looks so wrong. The past was better. right now everything is
// on left, too packed. this was a mistake"*; the pattern is Stats', docs/dev-log/2026-11-02-stats-design.md). The face is
// MAIN | SIDE (screenLayout.ts "THE PAGE"): MAIN is ONE list card — the goods under their kind headings, the search on its title
// line, its rows in as many columns as the main holds (1 on a phone, 2 in the 840 px of main at 1,440); the SIDE is the tray's
// column and holds what the list is read with — the KIND and the RARITY as choice grids, every choice visible (the past's
// eighteen kind chips, which docs/dev-log/2026-11-02-design-past-vs-now.md §3 names among what made the past better; a
// drop-down hides the choice behind a press). A press on a good opens its tray, which slides over the side column and moves
// nothing; a press on a kind SELECTS it — the list narrows, nothing else moves.
//
// ON A PHONE THE LIST COMES FIRST (2026-11-02, the review of the first cut: the two grids filled the whole first glass at 390×844
// and "Goods 629" stood at its bottom edge — the Codex's purpose is the list). Below the split (`useWide`, the same 1,024 px as
// the page's MAIN | SIDE) there is no side: the kind and the rarity are two PICKERS in the list card's own header — the same
// compact FilterBar the Ships and Captains faces hold their filters in — and the first rows stand on the first glass. ONE state
// drives both: the grid from 1,024 and the picker below it are two faces of the one choice, never two choices.
//
// THE KIND IS A HEADING, NOT A CHIP ON THE ROW. The snapshot serves goods by CODE (0009:96), which interleaves the seven kinds;
// sorting on two served fields is presentation, not authorship. The heading says the kind once per group instead of once per
// good, across every column of the card.
//
// ONE FIGURE. Base is the figure the catalogue exists to carry; bulk, spoilage and the cultures that refuse a good are in the
// tray, and a good that keeps or is traded everywhere simply has no such row — a dash is not a figure.

const EMPTY: readonly SnapshotGood[] = []

export function GoodsFace({ query, search }: { query: string; search: ReactNode }) {
  const t = useT()
  const snapshot = useWorld((s) => s.snapshot)
  const goods = snapshot?.goods ?? EMPTY
  const [open, setOpen] = useState<SnapshotGood | null>(null)
  const [detent, setDetent] = useState<TrayDetent>('half')
  const [kind, setKind] = useState(ALL)
  const [rarity, setRarity] = useState(ALL)
  const wide = useWide()

  // the kinds this world serves, each by its word, in the order the headings take
  const kinds = useMemo(
    () => [...new Set(goods.map((g) => g.category))].sort((a, b) => categoryLabel(a).localeCompare(categoryLabel(b))),
    [goods],
  )

  const groups = useMemo(() => {
    const needle = fold(query.trim())
    const rows = goods
      .filter(
        (g) =>
          (kind === ALL || g.category === kind) &&
          (rarity === ALL || g.rarity === rarity) &&
          foldedMatch(needle, g.name, g.code, categoryLabel(g.category), g.rarity ?? null),
      )
      .sort(
        (a, b) =>
          categoryLabel(a.category).localeCompare(categoryLabel(b.category)) || a.name.localeCompare(b.name),
      )
    const out: { category: string; rows: SnapshotGood[] }[] = []
    for (const g of rows) {
      const last = out[out.length - 1]
      if (last && last.category === g.category) last.rows.push(g)
      else out.push({ category: g.category, rows: [g] })
    }
    return out
  }, [goods, query, kind, rarity])
  const total = groups.reduce((n, g) => n + g.rows.length, 0)

  // THE TWO CHOICES, SPELLED ONCE (`optionsOf`, as the Ships' and Captains' filters): a PICKER'S "every one" option is the picker's
  // own NAME — "Kind", "Rarity" — so a picker with nothing chosen reads what it is (the review of the second cut: two pickers both
  // reading "All" could not be told apart; the Ships' read Country / Size / Role / Tech). The chip GRID's "every one" cell reads
  // "All": its card's title already says the name.
  const kindPicks = optionsOf(t('codex.kind'), kinds, (k) => k, (k) => categoryLabel(k))
  const rarityPicks = optionsOf(t('codex.rarity'), RARITY_TIERS, (r) => r, (r) => rarityLabel(r))
  const all = { id: ALL, label: t('codex.all') }
  const kindChips = [all, ...kindPicks.slice(1)]
  const rarityChips = [all, ...rarityPicks.slice(1)]

  const list = (
    <ListPanel
      look="card"
      columns="fit"
      title={t('codex.goods')}
      count={formatInt(total)}
      trailing={search}
      controls={
        wide ? undefined : (
          <FilterBar
            compact
            data-testid="goods-filters"
            picks={[
              { id: 'kind', label: t('codex.kind'), options: kindPicks, value: kind, onChange: setKind },
              { id: 'rarity', label: t('codex.rarity'), options: rarityPicks, value: rarity, onChange: setRarity },
            ]}
          />
        )
      }
      data-testid="codex-list"
    >
      {groups.length === 0 ? (
        <NoAnswer />
      ) : (
        groups.map((group) => (
          <Fragment key={group.category}>
            {/* THE HEADING SPANS THE CARD'S COLUMNS (ListHeading): a kind's goods follow it in every column, never a heading in
                column one with its goods in column two */}
            <ListHeading data-testid="good-kind">{categoryLabel(group.category)}</ListHeading>
            {group.rows.map((g) => (
              <Row
                key={g.code}
                {...goodClassRow(g.class)}
                // THE PREMIUM CLASS (0294) HANGS UNDER THE GOOD'S OWN MARK: the mark cell is the icon's 20 px wide and its line the
                // row's 24, so a meter under the icon costs no width and no height — the label keeps every pixel it had, the name is
                // never cut or pushed to a second line by it (the class word is the tray's Class row)
                mark={
                  <span className="relative inline-flex">
                    <Icon name={goodIcon(g.code, g.category)} size={20} />
                    <GoodClassMark goodClass={g.class} className="absolute left-1/2 top-full mt-0.5 -translate-x-1/2" />
                  </span>
                }
                label={
                  // THE NAME IS NEVER CUT: it wraps at its spaces, and the rarity word drops under it when the two do not
                  // fit one line — a short name keeps one line, a long one (or a 320-px glass) takes a second.
                  <span className="block">
                    <span>{g.name}</span>
                    {g.rarity && <> <RarityMark rarity={g.rarity} size={10} withWord className="ml-1 align-baseline" /></>}
                  </span>
                }
                value={<Figure value={anchor(g.base_value)} unit={COIN} />}
                chevron
                hairline={false}
                onClick={() => {
                  setDetent('half')
                  setOpen(g)
                }}
                data-testid="good-tile"
              />
            ))}
          </Fragment>
        ))
      )}
    </ListPanel>
  )

  return (
    <>
      {wide ? (
        <PageSplit
          data-testid="codex-goods"
          stickySide
          main={list}
          side={
            <>
              {/* THE KIND, EVERY CHOICE ON THE GLASS: one ordered grid of equal cells (FilterBar's chips, the owner's 2026-10-31 rule),
                  three across — "Ship supplies" is the widest word and stands in a third of the 352-px side at 1,024 */}
              <Card title={t('codex.kind')} data-testid="codex-kinds">
                <FilterBar chips={{ label: t('codex.kind'), options: kindChips, value: kind, onChange: setKind, columns: 3 }} />
              </Card>
              <Card title={t('codex.rarity')} data-testid="codex-rarity">
                <FilterBar chips={{ label: t('codex.rarity'), options: rarityChips, value: rarity, onChange: setRarity, columns: 3 }} />
              </Card>
            </>
          }
        />
      ) : (
        list
      )}

      {open && (
        <Tray
          detent={detent}
          onDetentChange={(next) => (next === 'closed' ? setOpen(null) : setDetent(next))}
          title={open.name}
          data-testid="good-tray"
        >
          <Row label={t('codex.kind')} value={categoryLabel(open.category)} />
          {open.rarity && <Row label={t('codex.rarity')} value={<RarityMark rarity={open.rarity} size={10} withWord />} />}
          {open.class != null && <Row label={t('codex.class')} value={<GoodClassMark goodClass={open.class} withWord />} data-testid="good-class-row" />}
          <Row label={t('codex.base')} value={<Figure value={anchor(open.base_value)} unit={COIN} />} />
          <Row
            label={t('codex.weight')}
            value={<Figure value={formatFixed(open.bulk, 1)} unit={t('codex.tons')} />}
            hairline={open.perishable_pct_day > 0}
          />
          {open.perishable_pct_day > 0 && (
            <Row
              label={t('codex.spoils')}
              value={<Figure value={formatPct(open.perishable_pct_day, 1)} unit={t('codex.perDay')} tone="warning" />}
              hairline={false}
            />
          )}
          {open.culture_mask.length > 0 && (
            // UNAVAILABLE IS SHOWN WITH ITS REASON: the cultures whose ports refuse this good
            // outright, in the server's own words (DESIGN B.4).
            <Note tone="warning" className="mt-2">{t('codex.notTradedAt', { cultures: open.culture_mask.join(', ') })}</Note>
          )}
        </Tray>
      )}
    </>
  )
}

/** Some anchors are half-ducat figures (82.50) — rounding them would misprint a served value, so
 *  the halves keep one decimal and whole figures stay whole. */
function anchor(value: number): string {
  return value % 1 === 0 ? formatInt(value) : formatFixed(value, 1)
}
