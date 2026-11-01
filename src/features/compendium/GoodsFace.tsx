import { Fragment, useMemo, useState, type ReactNode } from 'react'
import {
  Figure,
  GoodClassMark,
  Icon,
  ListPanel,
  Note,
  RarityMark,
  Row,
  Tray,
  categoryLabel,
  goodClassRow,
  goodIcon,
  type TrayDetent,
} from '../../components/ui'
import { COIN, formatFixed, formatInt, formatPct } from '../../lib/format'
import type { SnapshotGood } from '../../lib/rpc'
import { fold, foldedMatch } from '../../lib/text'
import { useWorld } from '../../live/worldStore'
import { NoAnswer } from './NoAnswer'
import { useT } from '../../lib/i18n'

// THE GOODS FACE — every good this world trades, grouped under its kind, one figure a row, ON THE GLASS.
//
// THE KIND IS A HEADING, NOT A CHIP. The snapshot serves goods by CODE (0009:96), which interleaves
// the seven kinds; sorting on two served fields is presentation, not authorship. The heading says
// the kind once per group instead of once per good, and the filter field answers to the kind's
// word, so the chip strip that used to select it is not missed.
//
// ONE FIGURE. Base is the figure the catalogue exists to carry; bulk, spoilage and the cultures
// that refuse a good are in the tray, and a good that keeps or is traded everywhere simply has no
// such row — a dash is not a figure.
//
// A ROW, NOT A TILE (the unfold slice, 2026-11-02): the 629 goods stand in the Codex's list panel, ten and
// more of them on a phone, each a 44-px row that opens its tray. The tray is the item's detail, as it was.

const EMPTY: readonly SnapshotGood[] = []

export function GoodsFace({ query, search }: { query: string; search: ReactNode }) {
  const t = useT()
  const snapshot = useWorld((s) => s.snapshot)
  const goods = snapshot?.goods ?? EMPTY
  const [open, setOpen] = useState<SnapshotGood | null>(null)
  const [detent, setDetent] = useState<TrayDetent>('half')

  const groups = useMemo(() => {
    const needle = fold(query.trim())
    const rows = goods
      .filter((g) => foldedMatch(needle, g.name, g.code, categoryLabel(g.category), g.rarity ?? null))
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
  }, [goods, query])
  const total = groups.reduce((n, g) => n + g.rows.length, 0)

  return (
    <>
      <ListPanel title={t('codex.countGoods', { n: formatInt(total), count: total })} trailing={search} data-testid="codex-list">
        {groups.length === 0 ? (
          <NoAnswer />
        ) : (
          groups.map((group) => (
            <Fragment key={group.category}>
              <span className="block pt-2 text-t-caption font-semibold text-ink-muted" data-testid="good-kind">
                {categoryLabel(group.category)}
              </span>
              {group.rows.map((g) => (
                <Row
                  key={g.code}
                  {...goodClassRow(g.class)}
                  // THE PREMIUM CLASS (0294) HANGS UNDER THE GOOD'S OWN MARK: the mark cell is the icon's 20 px wide and its line the
                  // row's 24, so a meter under the icon costs no width and no height — the label keeps every pixel it had, the name is
                  // never cut or pushed to a second line by it, and the 44-px row stays 44 (the class word is the tray's Class row)
                  mark={
                    <span className="relative inline-flex">
                      <Icon name={goodIcon(g.code, g.category)} size={20} />
                      <GoodClassMark goodClass={g.class} className="absolute left-1/2 top-full mt-0.5 -translate-x-1/2" />
                    </span>
                  }
                  label={
                    // THE NAME IS NEVER CUT: it wraps at its spaces, and the rarity word drops under it when the two do not
                    // fit one line — a short name keeps one 44-px line, a long one (or a 320-px glass) takes a second.
                    <span className="flex flex-wrap items-center gap-x-2">
                      <span>{g.name}</span>
                      {g.rarity && <RarityMark rarity={g.rarity} size={10} withWord />}
                    </span>
                  }
                  value={<Figure value={anchor(g.base_value)} unit={COIN} />}
                  chevron
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
