import { useMemo } from 'react'
import { Figure, Row } from '../../components/ui'
import { buildingsOf } from '../../domain/port'
import { formatPct } from '../../lib/format'
import { useWorld } from '../../live/worldStore'
import type { SnapshotPort } from '../../lib/rpc'
import { PORT_FACES, type PortFace } from './portView'

// THE TOWN — what this city costs you, and what it keeps. §6: *"Town face = rows: Tax 3 %, Port's
// cut 2 %, … then building rows"*.
//
// ── WHAT WENT ─────────────────────────────────────────────────────────────────────────────────
//   THE GARRISON.  `dev_military` was printed with a hint admitting that nothing reads it. §2 item
//     16: a stat the rules do not read is a stat the player cannot use.
//   THE LEVELS (2026-09-13, owner row 83: *"in town, trade level? what is this? market level? inn
//     level? who designed this? remove levels."*). `Trade level 3 / 20` and `Craft level 2 / 20`
//     with their bars, and the `level N` figure beside a building, are gone. They were readings of
//     `dev_commerce`, `dev_industry` and a building's tier — figures the server folds into the
//     spread and into what a workshop or a yard will make (0005:299,331; 0067; 0068) — and each of
//     those rules already says its own consequence where it bites: the Port fee row below, a
//     fitting's "Needs a level N workshop" in its tray, a hull's in the yard's. A level printed on
//     its own asks the player to know what it decides, and the owner did not. Deleted, not hidden.
//   THE `/20` SENTENCES and the three ⓘ paragraphs behind them, with the levels they explained.
//   THE BUILDING BLURBS.  `What this city keeps` printed `kind.does` — a sentence per building,
//     naming what storage is to a player who is standing in it. The row is the building and the
//     chevron opens its face, which is the same fact as a demonstration instead of a lecture.
//   DRAFT.  It left the header with the badge and it is not a row here: it decides nothing at a
//     port you are already docked in. It appears where it actually refuses something — the yard,
//     on a hull too deep for this harbour (PortYard.tsx).
//
// ── THE BUILDING'S WORD IS THE TAB'S WORD (owner rows 86 and 87) ──────────────────────────────
// A building row prints the LABEL of the face it opens (`PORT_FACES`, the one client word map:
// `Storage`, `Repair`, `Build`, …), not the served `building_kinds.name` (`Warehouse`,
// `Shipyard`) — two words for one building was exactly what the owner read and refused. The
// served name is read only for a kind no face names, so a new kind still prints as something
// true before it has a face.
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
        hairline={buildings.length > 0}
      />

      {buildings.map((b, i) => {
        const face = PORT_FACES.find((f) => f.building === b.kind)
        return (
          <Row
            key={b.kind}
            label={face?.label ?? nameOfKind[b.kind] ?? b.kind}
            chevron={face !== undefined}
            onClick={face ? () => onOpenFace(face.id) : undefined}
            hairline={i < buildings.length - 1}
            data-testid={`town-${b.kind}`}
          />
        )
      })}
    </>
  )
}
