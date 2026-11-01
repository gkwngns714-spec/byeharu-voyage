import { useMemo, useState, type ReactNode } from 'react'
import { FactsLine, FilterBar, Figure, Hint, Icon, ListPanel, Row, Tray, type TrayDetent } from '../../components/ui'
import { formatFixed, formatInt, formatOfTotal } from '../../lib/format'
import type { SnapshotShipClass } from '../../lib/rpc'
import { fold, foldedMatch } from '../../lib/text'
import { HullCountry } from '../../live/HullCountry'
import { HullTech } from '../../live/HullTech'
import { nationNameOf, useWorld } from '../../live/worldStore'
import { NoAnswer } from './NoAnswer'
import { useT, t as tNow, translateMaybe, getLocale } from '../../lib/i18n'

// THE SHIPS FACE — every class of hull, as the shipwright rates her, ON THE GLASS (the unfold slice,
// 2026-11-02): one row a class in the Codex's list panel, the four filters one line of selects in its header.
//
// HOLD, SPEED, CREW, AND NOTHING ELSE ON THE ROW (docs/UI_DIRECTION.md §6). `build 40 h` and
// `cost 2,400 d.` described hulls no order can commission — domain/fleet/statGloss.ts says so in
// its own header — and guns arm a combat the game does not have. A stat the rules do not read is
// a stat the player cannot use. Hull IS read (repair reads condition), so it is in the tray with the
// tier. Draft is shown there as a fact of the hull only — 0139 removed the gate that read it.
//
// SERVED ORDER: the snapshot serves ship classes by tier (0009:97) — the catalogue's own ladder.
//
// THE COUNTRY (0130): each class arrives with its line's flag nation; the row and the tray print
// it through the one renderer, HullCountry.
//
// THE GRID (0135, Wave A: 55 hulls): four filters — country (line), size, role, tech — each a picker
// of the values the SERVED classes carry (`line`, `size`, `role`, `tech` on the snapshot), plus
// "All". Nothing is offered that no served hull has; the words for a size, a role and a tech are
// the ones below and nowhere else.

const EMPTY: readonly SnapshotShipClass[] = []

/** The words for the served size (`class_profile.size`), role and tech. */
// Keys in the codex dictionary (`size_3`, `role_trade`, `tech_F`); a value with no entry prints as served.
const word = (key: string, served: string) => translateMaybe(getLocale(), 'codex', key) ?? served
const sizeWord = (n: number | null | undefined) => (n == null ? null : word(`size_${n}`, String(n)))
const roleWord = (r: string | null | undefined) => (r == null ? null : word(`role_${r}`, r))
const techWord = (t: string | null | undefined) => (t == null ? null : word(`tech_${t}`, t))

type Filters = { line: string; size: string; role: string; tech: string }
const ALL = 'all'
const NO_FILTER: Filters = { line: ALL, size: ALL, role: ALL, tech: ALL }

interface Option {
  id: string
  label: string
}

/** The distinct served values of one key, in a stable order, as options behind "All". */
function optionsOf(
  all: string,
  classes: readonly SnapshotShipClass[],
  key: (s: SnapshotShipClass) => string | null,
  label: (value: string, s: SnapshotShipClass) => string,
  order: (a: string, b: string) => number = (a, b) => a.localeCompare(b),
): Option[] {
  const firstOf = new Map<string, SnapshotShipClass>()
  for (const s of classes) {
    const v = key(s)
    if (v != null && !firstOf.has(v)) firstOf.set(v, s)
  }
  return [{ id: ALL, label: all }, ...[...firstOf.keys()].sort(order).map((v) => ({ id: v, label: label(v, firstOf.get(v)!) }))]
}

export function ShipsFace({ query, search }: { query: string; search: ReactNode }) {
  const t = useT()
  const snapshot = useWorld((s) => s.snapshot)
  const nationByCode = useWorld((s) => s.nationByCode)
  const classes = snapshot?.ship_classes ?? EMPTY
  const [open, setOpen] = useState<SnapshotShipClass | null>(null)
  const [detent, setDetent] = useState<TrayDetent>('half')

  const [filters, setFilters] = useState<Filters>(NO_FILTER)

  const facets = useMemo(
    () => ({
      line: optionsOf(tNow('codex.country'), classes, (s) => s.line ?? null, (v, s) => (s.line_nation ? nationNameOf(nationByCode, s.line_nation) : v)),
      size: optionsOf(tNow('codex.size'), classes, (s) => (s.size == null ? null : String(s.size)), (v) => sizeWord(Number(v)) ?? v, (a, b) => Number(a) - Number(b)),
      role: optionsOf(tNow('codex.role'), classes, (s) => s.role ?? null, (v) => roleWord(v) ?? v),
      tech: optionsOf(tNow('codex.tech'), classes, (s) => s.tech ?? null, (v) => techWord(v) ?? v),
    }),
    [classes, nationByCode],
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

  const picks = (['line', 'size', 'role', 'tech'] as const)
    .filter((k) => facets[k].length > 2)
    .map((k) => ({
      id: k,
      label: t(({ line: 'codex.country', size: 'codex.size', role: 'codex.role', tech: 'codex.tech' } as const)[k]),
      options: facets[k],
      value: filters[k],
      onChange: (v: string) => setFilters((f) => ({ ...f, [k]: v })),
    }))

  return (
    <>
      <ListPanel
        title={t('codex.countShips', { n: formatInt(rows.length), count: rows.length })}
        trailing={search}
        controls={picks.length > 0 ? <FilterBar compact data-testid="ship-filters" picks={picks} /> : undefined}
        data-testid="codex-list"
      >
        {rows.length === 0 ? (
          <NoAnswer />
        ) : (
          rows.map((s) => (
            <Row
              key={s.code}
              mark={<Icon name="ship" size={20} />}
              // THE NAME IS NEVER CUT: the row's first line is the name and the hold; the speed leads the facts line
              // under it. With both figures beside the name a 320-px glass left it 45–55 px (measured: "Niaochuan"
              // needs 71, "Queen's Pinnace" 112), so the first cut build showed "Niao…".
              label={s.name}
              value={<Figure value={formatInt(s.hold)} unit={t('trade.tonsUnit')} />}
              chevron
              onClick={() => {
                setDetent('half')
                setOpen(s)
              }}
              data-testid="ship-tile"
            >
              <FactsLine>
                <Figure value={formatFixed(s.speed_kn, 1)} unit={t('trade.knotsUnit')} />
                {s.line_nation && <HullCountry nation={s.line_nation} compact />}
                <HullTech tech={s.tech} />
                <span>{[sizeWord(s.size), roleWord(s.role), `${s.family} · ${s.rig}`].filter(Boolean).join(' · ')}</span>
                <span>{`crew ${formatOfTotal(s.crew_required, s.crew_max)}`}</span>
              </FactsLine>
            </Row>
          ))
        )}
      </ListPanel>

      {open && (
        <Tray
          detent={detent}
          onDetentChange={(next) => (next === 'closed' ? setOpen(null) : setDetent(next))}
          title={open.name}
          data-testid="ship-tray"
        >
          {open.line_nation && <Row label={t('codex.country')} value={<HullCountry nation={open.line_nation} />} />}
          {open.size != null && <Row label={t('codex.size')} value={sizeWord(open.size)} />}
          {open.role && <Row label={t('codex.role')} value={roleWord(open.role)} />}
          {open.tech && <Row label={t('codex.tech')} value={techWord(open.tech)} />}
          <Row label={t('codex.cargo')} value={<Figure value={formatInt(open.hold)} unit={t('codex.tons')} />} />
          <Row label={t('codex.speed')} value={<Figure value={formatFixed(open.speed_kn, 1)} unit={t('codex.knots')} />} />
          {/* crew she must have / berths she carries — two served figures, one pair. */}
          <Row label={t('codex.crewNeeded')} value={<Figure value={formatOfTotal(open.crew_required, open.crew_max)} />} />
          <Row label={t('codex.draft')} value={<Figure value={formatInt(open.draft)} />} />
          <Row label={t('codex.hull')} value={<Figure value={formatInt(open.durability)} />} />
          <Row label={t('codex.class')} value={<Figure value={formatInt(open.tier)} />} hairline={false} />
          <Hint className="mt-2">{t('codex.baseFigures')}</Hint>
        </Tray>
      )}
    </>
  )
}
