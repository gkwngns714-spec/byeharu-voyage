import { useMemo, useState } from 'react'
import {
  Figure,
  Hint,
  Icon,
  Row,
  Tile,
  TileField,
  Tray,
  type TrayDetent,
} from '../../components/ui'
import { formatFixed, formatInt, formatOfTotal } from '../../lib/format'
import type { SnapshotShipClass } from '../../lib/rpc'
import { fold, foldedMatch } from '../../lib/text'
import { useWorld } from '../../live/worldStore'
import { NoAnswer } from './NoAnswer'

// THE SHIPS FACE — every class of hull, as the shipwright rates her.
//
// HOLD, SPEED, CREW, AND NOTHING ELSE ON THE TILE (docs/UI_DIRECTION.md §6). `build 40 h` and
// `cost 2,400 d.` described hulls no order can commission — domain/fleet/statGloss.ts says so in
// its own header — and guns arm a combat the game does not have. A stat the rules do not read is
// a stat the player cannot use. Draft and hull ARE read (the sailing gate refuses a harbour
// shallower than the deepest hull; repair reads condition), so they are in the tray with the tier.
//
// SERVED ORDER: the snapshot serves ship classes by tier (0009:97) — the catalogue's own ladder.

const EMPTY: readonly SnapshotShipClass[] = []

export function ShipsFace({ query }: { query: string }) {
  const snapshot = useWorld((s) => s.snapshot)
  const classes = snapshot?.ship_classes ?? EMPTY
  const [open, setOpen] = useState<SnapshotShipClass | null>(null)
  const [detent, setDetent] = useState<TrayDetent>('half')

  const rows = useMemo(() => {
    const needle = fold(query.trim())
    return classes.filter((s) => foldedMatch(needle, s.name, s.code, s.family, s.rig))
  }, [classes, query])

  if (rows.length === 0) return <NoAnswer />

  return (
    <>
      <TileField>
        {rows.map((s) => (
          <Tile
            key={s.code}
            mark={<Icon name="ship" size={20} />}
            name={s.name}
            meta={`${s.family} · ${s.rig}`}
            figure={<Figure value={formatInt(s.hold)} unit="tons" />}
            second={<Figure value={formatFixed(s.speed_kn, 1)} unit="knots" />}
            tap="whole"
            onClick={() => {
              setDetent('half')
              setOpen(s)
            }}
            data-testid="ship-tile"
          >
            <span className="text-t-caption text-ink-faint">{`crew ${formatOfTotal(s.crew_required, s.crew_max)}`}</span>
          </Tile>
        ))}
      </TileField>

      {open && (
        <Tray
          detent={detent}
          onDetentChange={(next) => (next === 'closed' ? setOpen(null) : setDetent(next))}
          title={open.name}
          data-testid="ship-tray"
        >
          <Row label="Cargo" value={<Figure value={formatInt(open.hold)} unit="tons" />} />
          <Row label="Speed" value={<Figure value={formatFixed(open.speed_kn, 1)} unit="knots" />} />
          {/* crew she must have / berths she carries — two served figures, one pair. */}
          <Row label="Crew (needed / max)" value={<Figure value={formatOfTotal(open.crew_required, open.crew_max)} />} />
          <Row label="Depth needed" value={<Figure value={formatInt(open.draft)} />} />
          <Row label="Hull" value={<Figure value={formatInt(open.durability)} />} />
          <Row label="Class" value={<Figure value={formatInt(open.tier)} />} hairline={false} />
          <Hint className="mt-2">Base figures, before any officer or skill bonus.</Hint>
        </Tray>
      )}
    </>
  )
}
