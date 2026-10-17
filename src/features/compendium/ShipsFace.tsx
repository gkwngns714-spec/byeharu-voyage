import { useMemo, useState } from 'react'
import {
  Figure,
  Hint,
  Icon,
  Row,
  Segmented,
  Tile,
  TileField,
  Tray,
  type SegmentSpec,
  type TrayDetent,
} from '../../components/ui'
import { formatFixed, formatInt, formatOfTotal } from '../../lib/format'
import type { SnapshotShipClass } from '../../lib/rpc'
import { fold, foldedMatch } from '../../lib/text'
import { HullCountry } from '../../live/HullCountry'
import { HullTech } from '../../live/HullTech'
import { useWorld } from '../../live/worldStore'
import { NoAnswer } from './NoAnswer'

// THE SHIPS FACE — every class of hull, as the shipwright rates her.
//
// HOLD, SPEED, CREW, AND NOTHING ELSE ON THE TILE (docs/UI_DIRECTION.md §6). `build 40 h` and
// `cost 2,400 d.` described hulls no order can commission — domain/fleet/statGloss.ts says so in
// its own header — and guns arm a combat the game does not have. A stat the rules do not read is
// a stat the player cannot use. Hull IS read (repair reads condition), so it is in the tray with the
// tier. Draft is shown there as a fact of the hull only — 0139 removed the gate that read it.
//
// SERVED ORDER: the snapshot serves ship classes by tier (0009:97) — the catalogue's own ladder.
//
// THE COUNTRY (0130): each class arrives with its line's flag nation; the tile and the tray print
// it through the one renderer, HullCountry.
//
// THE GRID (0135, Wave A: 55 hulls): four filters — country (line), size, role, tech — each a row
// of the values the SERVED classes carry (`line`, `size`, `role`, `tech` on the snapshot), plus
// "All". Nothing is offered that no served hull has; the words for a size, a role and a tech are
// the ones below and nowhere else.

const EMPTY: readonly SnapshotShipClass[] = []

/** The words for the served size (`class_profile.size`), role and tech. */
const SIZE_WORD: Readonly<Record<number, string>> = { 1: 'Small', 2: 'Light', 3: 'Medium', 4: 'Heavy', 5: 'Capital', 6: 'Flagship' }
const ROLE_WORD: Readonly<Record<string, string>> = { trade: 'Trade', combat: 'Combat', explorer: 'Explorer', support: 'Support' }
const TECH_WORD: Readonly<Record<string, string>> = { T1: 'T1', T2: 'T2', F: 'Famous' }
const sizeWord = (n: number | null | undefined) => (n == null ? null : (SIZE_WORD[n] ?? String(n)))
const roleWord = (r: string | null | undefined) => (r == null ? null : (ROLE_WORD[r] ?? r))
const techWord = (t: string | null | undefined) => (t == null ? null : (TECH_WORD[t] ?? t))

type Filters = { line: string; size: string; role: string; tech: string }
const ALL = 'all'
const NO_FILTER: Filters = { line: ALL, size: ALL, role: ALL, tech: ALL }

/** The distinct served values of one key, in a stable order, as segments behind "All". */
function segmentsOf(
  classes: readonly SnapshotShipClass[],
  key: (s: SnapshotShipClass) => string | null,
  label: (value: string, s: SnapshotShipClass) => SegmentSpec<string>['label'],
  order: (a: string, b: string) => number = (a, b) => a.localeCompare(b),
): SegmentSpec<string>[] {
  const firstOf = new Map<string, SnapshotShipClass>()
  for (const s of classes) {
    const v = key(s)
    if (v != null && !firstOf.has(v)) firstOf.set(v, s)
  }
  return [
    { id: ALL, label: 'All' },
    ...[...firstOf.keys()].sort(order).map((v) => ({ id: v, label: label(v, firstOf.get(v)!) })),
  ]
}

export function ShipsFace({ query }: { query: string }) {
  const snapshot = useWorld((s) => s.snapshot)
  const classes = snapshot?.ship_classes ?? EMPTY
  const [open, setOpen] = useState<SnapshotShipClass | null>(null)
  const [detent, setDetent] = useState<TrayDetent>('half')

  const [filters, setFilters] = useState<Filters>(NO_FILTER)

  const facets = useMemo(
    () => ({
      line: segmentsOf(classes, (s) => s.line ?? null, (_v, s) => <HullCountry nation={s.line_nation} />),
      size: segmentsOf(classes, (s) => (s.size == null ? null : String(s.size)), (v) => sizeWord(Number(v)) ?? v,
        (a, b) => Number(a) - Number(b)),
      role: segmentsOf(classes, (s) => s.role ?? null, (v) => roleWord(v) ?? v),
      tech: segmentsOf(classes, (s) => s.tech ?? null, (v) => techWord(v) ?? v),
    }),
    [classes],
  )

  const rows = useMemo(() => {
    const needle = fold(query.trim())
    return classes.filter(
      (s) =>
        foldedMatch(needle, s.name, s.code, s.family, s.rig) &&
        (filters.line === ALL || s.line === filters.line) &&
        (filters.size === ALL || String(s.size) === filters.size) &&
        (filters.role === ALL || s.role === filters.role) &&
        (filters.tech === ALL || s.tech === filters.tech),
    )
  }, [classes, query, filters])

  const filterBar = (
    <div className="mb-3 flex flex-col gap-2" data-testid="ship-filters">
      {(['line', 'size', 'role', 'tech'] as const).map((k) =>
        facets[k].length > 2 ? (
          <Segmented
            key={k}
            label={{ line: 'Country', size: 'Size', role: 'Role', tech: 'Tech' }[k]}
            segments={facets[k]}
            value={filters[k]}
            onChange={(v) => setFilters((f) => ({ ...f, [k]: v }))}
          />
        ) : null,
      )}
    </div>
  )

  if (rows.length === 0) {
    return (
      <>
        {filterBar}
        <NoAnswer />
      </>
    )
  }

  return (
    <>
      {filterBar}
      <TileField>
        {rows.map((s) => (
          <Tile
            key={s.code}
            mark={<Icon name="ship" size={20} />}
            name={s.name}
            meta={
              <>
                <HullCountry nation={s.line_nation} compact />
                {s.line_nation ? ' ' : ''}
                <HullTech tech={s.tech} />
                {[sizeWord(s.size), roleWord(s.role), `${s.family} · ${s.rig}`].filter(Boolean).join(' · ')}
              </>
            }
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
          {open.line_nation && <Row label="Country" value={<HullCountry nation={open.line_nation} />} />}
          {open.size != null && <Row label="Size" value={sizeWord(open.size)} />}
          {open.role && <Row label="Role" value={roleWord(open.role)} />}
          {open.tech && <Row label="Tech" value={techWord(open.tech)} />}
          <Row label="Cargo" value={<Figure value={formatInt(open.hold)} unit="tons" />} />
          <Row label="Speed" value={<Figure value={formatFixed(open.speed_kn, 1)} unit="knots" />} />
          {/* crew she must have / berths she carries — two served figures, one pair. */}
          <Row label="Crew (needed / max)" value={<Figure value={formatOfTotal(open.crew_required, open.crew_max)} />} />
          <Row label="Draft" value={<Figure value={formatInt(open.draft)} />} />
          <Row label="Hull" value={<Figure value={formatInt(open.durability)} />} />
          <Row label="Class" value={<Figure value={formatInt(open.tier)} />} hairline={false} />
          <Hint className="mt-2">Base figures, before any officer or skill bonus.</Hint>
        </Tray>
      )}
    </>
  )
}
