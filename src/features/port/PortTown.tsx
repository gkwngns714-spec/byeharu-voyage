import { useMemo } from 'react'
import { Bar, Figure, Row } from '../../components/ui'
import { buildingsOf } from '../../domain/port'
import { formatInt, formatOfTotal, formatPct } from '../../lib/format'
import { useWorld } from '../../live/worldStore'
import type { SnapshotPort } from '../../lib/rpc'
import { PORT_FACES, type PortFace } from './portView'

// THE TOWN — what this city costs you, and what it keeps. §6: *"Town face = rows: Tax 3 %, Port's
// cut 2 %, … then building rows `Warehouse · tier 5 ›`"*.
//
// ── WHAT WENT ─────────────────────────────────────────────────────────────────────────────────
//   THE GARRISON.  `dev_military` was printed with a hint admitting that nothing reads it. §2 item
//     16: a stat the rules do not read is a stat the player cannot use. Trade and crafts stay,
//     because both really do change what you pay (0005:299,331 and 0007:736).
//   THE `/20` SENTENCES and the three ⓘ paragraphs behind them. A proportion is a `Bar`; the scale
//     is the bar's own length, and the figure beside it is the reading.
//   THE BUILDING BLURBS.  `What this city keeps` printed `kind.does` — a sentence per building,
//     naming what a warehouse is to a player who is standing in one. The row is the building and
//     the chevron opens its face, which is the same fact as a demonstration instead of a lecture.
//   DRAFT.  It left the header with the badge and it is not a row here: it decides nothing at a
//     quay you are already lying in. It appears where it actually refuses something — the yard,
//     on a hull too deep for this harbour (PortYard.tsx).
export function PortTown({
  port,
  onOpenFace,
}: {
  port: SnapshotPort
  /** Turn to the face a building keeps. The chevron on a building row is this. */
  onOpenFace: (face: PortFace) => void
}) {
  // READ AT THE LEAF (worldStore rule 4): the spread is the market's own figure, and this is the
  // only place it is printed — PortFair deliberately prints neither it nor a before/after pair.
  const spread = useWorld((s) => s.markets[port.id]?.port?.spread ?? null)
  // SELECT A SERVED REFERENCE, FOLD IT HERE. A selector that BUILDS an object returns a new one on
  // every store read, and zustand compares by identity: `Object.fromEntries(...)` inside the
  // selector is an infinite render loop (React error #185), which is exactly what it did the first
  // time this file was run. The fold belongs in a memo, not in the subscription.
  const kinds = useWorld((s) => s.snapshot?.building_kinds)
  const nameOfKind = useMemo(
    () => Object.fromEntries((kinds ?? []).map((k) => [k.kind, k.name])),
    [kinds],
  )

  const buildings = buildingsOf(port)

  return (
    <>
      <Row label="Market tax" value={<Figure value={formatPct(port.tax_rate, 1)} />} />
      <Row
        label="Port fee"
        value={<Figure value={spread === null ? '—' : formatPct(spread, 1)} tone={spread === null ? 'faint' : 'ink'} />}
      />
      <Row label="Trade level" value={<Figure value={formatOfTotal(port.dev_commerce, 20)} />}>
        <Bar pct={(port.dev_commerce / 20) * 100} label="how far trade has grown" className="mt-1" />
      </Row>
      <Row label="Craft level" value={<Figure value={formatOfTotal(port.dev_industry, 20)} />} hairline={buildings.length > 0}>
        <Bar pct={(port.dev_industry / 20) * 100} label="how far the crafts have grown" className="mt-1" />
      </Row>

      {buildings.map((b, i) => {
        const face = PORT_FACES.find((f) => f.building === b.kind)
        return (
          <Row
            key={b.kind}
            label={nameOfKind[b.kind] ?? b.kind}
            // A tier is printed only above 1: "tier 1" on every line is a column of noise, and
            // what a player wants to see is which city is BETTER at something than the last one.
            value={b.tier > 1 ? <Figure value={`level ${formatInt(b.tier)}`} tone="muted" /> : undefined}
            chevron={face !== undefined}
            onClick={face ? () => onOpenFace(face.id) : undefined}
            hairline={i < buildings.length - 1}
          />
        )
      })}
    </>
  )
}
