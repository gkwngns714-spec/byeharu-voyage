import { useMemo, useState, type ReactNode } from 'react'
import { ALL, Card, FactsLine, FilterBar, Figure, Hint, Icon, ListPanel, PageSplit, RankBars, Row, Tray, type TrayDetent } from '../../components/ui'
import { formatFixed, formatInt, formatKnots, formatOfTotal, formatTons } from '../../lib/format'
import type { SnapshotShipClass } from '../../lib/rpc'
import { fold, foldedMatch } from '../../lib/text'
import { HullCountry } from '../../live/HullCountry'
import { HullTech } from '../../live/HullTech'
import { nationNameOf, useWorld } from '../../live/worldStore'
import { optionsOf } from './codexFilters'
import { NoAnswer } from './NoAnswer'
import { useT, t as tNow, translateMaybe, getLocale } from '../../lib/i18n'

// THE SHIPS FACE — every class of hull, as the shipwright rates her, ON THE PAGE (2026-11-02, owner row 267; the pattern
// is Stats', docs/dev-log/2026-11-02-stats-design.md). MAIN | SIDE: MAIN is ONE list card — a row a class, the four filters one
// line of pickers in its header, the search on its title line, the rows in as many columns as the main holds; the SIDE is the
// tray's column and holds the two figures a hull is chosen by AS GRAPHICS — the biggest holds and the fastest hulls among the
// classes the filters leave, five each, ranked bars (the question a list of figures cannot answer: which of these is big).
// A press on a row opens the class's tray, which slides over the side column and moves nothing.
//
// HOLD, SPEED, CREW, AND NOTHING ELSE ON THE ROW (docs/UI_DIRECTION.md §6). `build 40 h` and
// `cost 2,400 d.` described hulls no order can commission — domain/fleet/statGloss.ts says so in
// its own header — and guns arm a combat the game does not have. A stat the rules do not read is
// a stat the player cannot use. Hull IS read (repair reads condition), so it is in the tray with the
// tier. Draft is shown there as a fact of the hull only — 0139 removed the gate that read it.
//
// SERVED ORDER: the snapshot serves ship classes by tier (0009:97) — the catalogue's own ladder. The two boards are
// sorted on a served figure, which is presentation, not authorship.
//
// THE COUNTRY (0130): each class arrives with its line's flag nation; the row and the tray print
// it through the one renderer, HullCountry.
//
// THE GRID (0135, Wave A: 55 hulls): four filters — country (line), size, role, tech — each a picker
// of the values the SERVED classes carry (`line`, `size`, `role`, `tech` on the snapshot), plus
// "All". Nothing is offered that no served hull has; the words for a size, a role and a tech are
// the ones below and nowhere else.

const EMPTY: readonly SnapshotShipClass[] = []
/** How many hulls a board ranks. */
const BOARD = 5

/** The words for the served size (`class_profile.size`), role and tech. */
// Keys in the codex dictionary (`size_3`, `role_trade`, `tech_F`); a value with no entry prints as served.
const word = (key: string, served: string) => translateMaybe(getLocale(), 'codex', key) ?? served
const sizeWord = (n: number | null | undefined) => (n == null ? null : word(`size_${n}`, String(n)))
const roleWord = (r: string | null | undefined) => (r == null ? null : word(`role_${r}`, r))
const techWord = (t: string | null | undefined) => (t == null ? null : word(`tech_${t}`, t))

type Filters = { line: string; size: string; role: string; tech: string }
const NO_FILTER: Filters = { line: ALL, size: ALL, role: ALL, tech: ALL }

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
      role: optionsOf(tNow('codex.role'), classes, (s) => s.role ?? null, (v) => roleWord(v) ?? v, (a, b) => a.localeCompare(b)),
      tech: optionsOf(tNow('codex.tech'), classes, (s) => s.tech ?? null, (v) => techWord(v) ?? v, (a, b) => a.localeCompare(b)),
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

  // THE TWO BOARDS: the biggest holds and the fastest hulls among the rows on the face, the name breaking a tie
  const byHold = useMemo(() => [...rows].sort((a, b) => b.hold - a.hold || a.name.localeCompare(b.name)).slice(0, BOARD), [rows])
  const bySpeed = useMemo(() => [...rows].sort((a, b) => b.speed_kn - a.speed_kn || a.name.localeCompare(b.name)).slice(0, BOARD), [rows])

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
      <PageSplit
        data-testid="codex-ships"
        // no `sideFirst`: on a phone the boards stand AFTER the list — the Codex's purpose is the list, and its first rows are on the first glass
        stickySide
        main={
          <ListPanel
            look="card"
            columns="fit"
            title={t('codex.ships')}
            count={formatInt(rows.length)}
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
                  hairline={false}
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
        }
        side={
          <>
            <Card title={t('codex.biggestCargo')} data-testid="codex-ships-cargo">
              <RankBars
                rules={false}
                format={formatInt}
                empty={t('codex.noMatches')}
                rows={byHold.map((s) => ({ id: s.code, label: s.name, value: s.hold, text: formatTons(s.hold) }))}
              />
            </Card>
            <Card title={t('codex.fastest')} data-testid="codex-ships-speed">
              <RankBars
                rules={false}
                format={formatInt}
                empty={t('codex.noMatches')}
                rows={bySpeed.map((s) => ({ id: s.code, label: s.name, value: s.speed_kn, text: formatKnots(s.speed_kn) }))}
              />
            </Card>
          </>
        }
      />

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
