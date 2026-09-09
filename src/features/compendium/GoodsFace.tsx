import { useMemo, useState } from 'react'
import {
  Figure,
  Hint,
  Icon,
  Note,
  RarityMark,
  Row,
  SheetSection,
  Tile,
  TileField,
  Tray,
  categoryLabel,
  goodIcon,
  rarityLabel,
  type TrayDetent,
} from '../../components/ui'
import { formatFixed, formatInt, formatPct } from '../../lib/format'
import type { SnapshotGood } from '../../lib/rpc'
import { fold, foldedMatch } from '../../lib/text'
import { useWorld } from '../../live/worldStore'
import { NoAnswer } from './NoAnswer'

// THE GOODS FACE — every good this world trades, grouped under its kind, one figure a tile.
//
// THE KIND IS A HEADING, NOT A CHIP. The snapshot serves goods by CODE (0009:96), which interleaves
// the seven kinds; sorting on two served fields is presentation, not authorship. The heading says
// the kind once per group instead of once per good, and the filter field answers to the kind's
// word, so the chip strip that used to select it is not missed.
//
// ONE FIGURE. Base is the figure the catalogue exists to carry; bulk, spoilage and the cultures
// that refuse a good are in the tray, and a good that keeps or is traded everywhere simply has no
// such row — a dash is not a figure.

const EMPTY: readonly SnapshotGood[] = []

export function GoodsFace({ query }: { query: string }) {
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

  if (groups.length === 0) return <NoAnswer />

  return (
    <>
      {groups.map((group) => (
        <SheetSection key={group.category} heading={categoryLabel(group.category)}>
          <TileField>
            {group.rows.map((g) => (
              <Tile
                key={g.code}
                mark={<Icon name={goodIcon(g.code, g.category)} size={20} />}
                name={g.name}
                meta={<RarityLine rarity={g.rarity} />}
                figure={<Figure value={anchor(g.base_value)} unit="d." />}
                tap="whole"
                onClick={() => {
                  setDetent('half')
                  setOpen(g)
                }}
                data-testid="good-tile"
              />
            ))}
          </TileField>
        </SheetSection>
      ))}

      {open && (
        <Tray
          detent={detent}
          onDetentChange={(next) => (next === 'closed' ? setOpen(null) : setDetent(next))}
          title={open.name}
          data-testid="good-tray"
        >
          <Row label="Kind" value={categoryLabel(open.category)} />
          {open.rarity && <Row label="Rarity" value={<RarityLine rarity={open.rarity} />} />}
          <Row label="Base" value={<Figure value={anchor(open.base_value)} unit="d." />} />
          <Row
            label="Bulk"
            value={<Figure value={formatFixed(open.bulk, 1)} unit="t" />}
            hairline={open.perishable_pct_day > 0}
          />
          {open.perishable_pct_day > 0 && (
            <Row
              label="Spoils"
              value={<Figure value={formatPct(open.perishable_pct_day, 1)} unit="a day" tone="warning" />}
              hairline={false}
            />
          )}
          {open.culture_mask.length > 0 && (
            // UNAVAILABLE IS SHOWN WITH ITS REASON: the cultures whose ports refuse this good
            // outright, in the server's own words (DESIGN B.4).
            <Note tone="warning" className="mt-2">{`Refused at ${open.culture_mask.join(', ')} ports.`}</Note>
          )}
          <Hint className="mt-2">Base is the catalogue's anchor, not a price. Prices are per port.</Hint>
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

/** The served rarity tier (0032) as its mark and its word. Absent renders nothing. */
function RarityLine({ rarity }: { rarity: string | undefined }) {
  if (!rarity) return null
  return (
    <span className="inline-flex items-center gap-1">
      <RarityMark rarity={rarity} size={10} />
      {rarityLabel(rarity)}
    </span>
  )
}
