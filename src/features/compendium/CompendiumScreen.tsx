import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import type { ReactNode } from 'react'
import {
  Badge,
  Button,
  Card,
  CardHeader,
  EntryTile,
  EntryTileLine,
  GoodTile,
  HSCROLL_HINT,
  Icon,
  Input,
  Notice,
  PageHeader,
  RARITY_TIERS,
  Screen,
  SectionLabel,
  Skeleton,
  StatLegend,
  TD,
  TH,
  TabRow,
  Table,
  categoryLabel,
  fineClass,
  hScrollClass,
  rarityLabel,
  scrollTableClass,
  tileFieldClass,
  useClipped,
} from '../../components/ui'
import { formatDucats, formatFixed, formatInt, formatKnots, formatOfTotal, formatPct, formatPctPoints, formatTuns } from '../../lib/format'
import type { Officer, SnapshotGood, SnapshotNation, SnapshotPort, SnapshotShipClass } from '../../lib/rpc'
import { fold, foldedMatch } from '../../lib/text'
// WHAT EACH SHIP FIGURE DECIDES — the one sentence per stat, shared with FLEETS and PORT.
import { shipStatItems } from '../../domain/fleet'
import { nationNameOf, portNameOf, useWorld } from '../../live/worldStore'
import { WorldFailed, WorldLoading } from '../../live/WorldGate'

// COMPENDIUM — the 도감: everything that exists in this world, catalogued, whether or not you have
// met it. The owner, 2026-08-23: "create a 도감, separate tab, showing all the trade goods, ships,
// captains that are made in this game. categorize them, make filters."
//
// ── IT IS A REFERENCE. IT COMMANDS NOTHING. ────────────────────────────────────────────────────
// No buy, no hire, no sail, no hand-off. Every acting surface already exists once — orders are
// composed on COMMAND, officers sign on at their home quay on PORT, hulls are a shipyard's business —
// and a button here would be a second one of it. The moment this screen wants an action, the
// action belongs to the tab that owns it.
//
// ── NOTHING HERE IS COMPUTED, AND NO PRICE IS PRINTED ──────────────────────────────────────────
// Every figure is a served field read off `world.snapshot()` or `world.officers()`. A good's BASE
// is the catalogue's anchor value, not a price — prices are per-port and live, on MARKET, and a
// compendium that printed one would be lying the moment the market drifted. Nothing is averaged,
// ranked or derived: the client's job is to print what the server said (worldStore.ts rule 3).
//
// ── THE FOUR FACES, AND WHY NATIONS IS ONE OF THEM ─────────────────────────────────────────────
// The owner named goods, ships and captains. Nations ride along because they are the fourth noun
// every other page speaks in codes: `SnapshotPort.nation`, `Officer.nation`, the board's flags —
// and 0028 serves the catalogue (`snapshot.nations`) precisely so a code can become a name. A
// compendium is where a player looks a code up, so the one catalogue the server keeps for that
// purpose is listed here. Ports are deliberately NOT a face: 214 harbours already have a whole
// surface of their own (MAP draws them all; MARKET lists them), and a fifth copy of the port list
// would be a directory nobody asked for.
//
// ── CATEGORIES ARE THE DATA'S, NOT THIS FILE'S ─────────────────────────────────────────────────
// The kind chips are derived from the served rows — a good's `category`, a hull's `family`, an
// officer's `specialty` — in order of first appearance, and the chip row only renders when the
// data actually distinguishes two kinds. Today every hull is family "Western", so the ships face
// shows no chips; the day a migration lands an Eastern family, the chips appear with no edit here.

type FaceId = 'goods' | 'ships' | 'captains' | 'nations'

interface FaceSpec {
  id: FaceId
  label: string
  /** The plural noun the count line and the no-answer sentence speak in. */
  noun: string
  title: string
  /** The face's standing explanation — column meanings and refusals. Behind the ⓘ, never live.
   *  A node, not a string, so the ships face can compose domain/fleet's stat legend. */
  explain: ReactNode
}

const FACES: readonly FaceSpec[] = [
  {
    id: 'goods',
    label: 'Goods',
    noun: 'goods',
    title: 'Trade goods',
    explain:
      'Every good this world trades, in its seven kinds. BASE is the catalogue anchor a tun is ' +
      'reckoned from before any port’s supply, distance or tax moves it — it is not a price ' +
      'you can trade at; live prices are per port, on Market. RARITY is how hard a cheap source ' +
      'is to find — how few of the world’s ports produce the good, from common (you are never ' +
      'far from one) to exotic (one or two harbours in the world) — said by the world itself, ' +
      'never reckoned here. BULK is the room one unit takes in the hold. SPOILS is what a day at sea costs of it — a dash keeps indefinitely. REFUSED BY ' +
      'names the cultures whose ports will not trade it at all.',
  },
  {
    id: 'ships',
    label: 'Ships',
    noun: 'ship classes',
    title: 'Ship classes',
    /* EVERY FIGURE GLOSSED FROM THE ONE TABLE. This was a prose paragraph explaining four of the
       ten figures in this face's own words; the sentences now come from domain/fleet's statGloss —
       the single authority FLEETS' ships table and PORT's draft badge also compose — so no two
       screens can explain a stat apart. BUILD and COST say out loud that no rule reads them yet
       (statGloss.ts's header carries the citations, and the limit of that claim). */
    explain: (
      <>
        Every class of hull, as the shipwright rates her — before any officer or skill touches the
        figures. What each figure decides:
        <StatLegend
          className="mt-1"
          items={shipStatItems([
            'tier',
            'hold',
            'crew',
            'speed',
            'guns',
            'hull',
            'draft',
            'build',
            'cost',
            'lineage',
          ])}
        />
      </>
    ),
  },
  {
    id: 'captains',
    label: 'Captains',
    noun: 'officers',
    title: 'Officers',
    explain:
      'Every officer in the world, signed or not, in their four callings. Each is found at their ' +
      'home port and signs on there — hiring happens on the Port tab, at their quay; nothing ' +
      'here signs anyone. The bonus is what their specialty is worth to a fleet they are posted to.',
  },
  {
    id: 'nations',
    label: 'Nations',
    noun: 'nations',
    title: 'Nations',
    explain:
      'The flags this world sails under, and the capital each names. Everywhere else the game ' +
      'says a nation as a three-letter code — this is the catalogue that turns the code into a ' +
      'name, served by the world itself so no screen keeps a table of its own.',
  },
]

export function CompendiumScreen() {
  // FIELDS, NOT THE STORE (worldStore.ts rule 4).
  const phase = useWorld((s) => s.phase)
  const fatal = useWorld((s) => s.fatal)

  if (phase === 'failed') {
    return <WorldFailed eyebrow="Reference" title="Compendium" refusal={fatal} />
  }
  if (phase !== 'ready') {
    return (
      <WorldLoading
        eyebrow="Reference"
        title="Compendium"
        subtitle="Everything that exists in this world, catalogued."
        panels={2}
      />
    )
  }
  return <CompendiumBody />
}

function CompendiumBody() {
  const snapshot = useWorld((s) => s.snapshot)
  const roster = useWorld((s) => s.officers)
  const loadOfficers = useWorld((s) => s.loadOfficers)
  const readAt = useWorld((s) => s.readAt)
  const portByCode = useWorld((s) => s.portByCode)
  const nationByCode = useWorld((s) => s.nationByCode)

  // WHETHER THE ROSTER HAS ANSWERED, which `officers === null` alone cannot say (the RANK board's
  // reason, borrowed with its shape): null is both "not asked yet" and "the read was refused", and
  // without the distinction a refused read draws a skeleton for ever.
  const [rosterAnswered, setRosterAnswered] = useState(false)

  // KEYED ON `readAt`: the `read again` button is deleted (the owner: "read again on top left of
  // the game is useless. remove it") — the world re-reads itself every thirty seconds and on tab
  // focus, and the one live thing on this screen (who has signed, and whose fleet they serve)
  // rides that same beat. A refused roster read is retried on the next beat with no button.
  useEffect(() => {
    if (readAt === null) return
    let alive = true
    void loadOfficers().then(() => {
      if (alive) setRosterAnswered(true)
    })
    return () => {
      alive = false
    }
  }, [loadOfficers, readAt])

  const [face, setFace] = useState<FaceId>('goods')
  const [query, setQuery] = useState('')
  const [kind, setKind] = useState<string | null>(null)
  // The goods face filters on TWO served fields — category and rarity (0032) — and they compose:
  // "rare metals" is a question the reference should answer. Other faces have one axis.
  const [tier, setTier] = useState<string | null>(null)

  // A filter belongs to the face it was typed against. Carrying "pepper" onto the ships face
  // would show an empty catalogue for a reason the player typed a minute ago on another list.
  const pickFace = useCallback((next: FaceId) => {
    setFace(next)
    setQuery('')
    setKind(null)
    setTier(null)
  }, [])

  // `phase === 'ready'` implies the snapshot answered (worldStore.open sets it before `ready`),
  // so this guard is for the type, not for a state the game can reach.
  if (!snapshot) return null

  const shownFace = FACES.find((f) => f.id === face) ?? FACES[0]
  const officers = roster?.officers ?? null

  return (
    <Screen>
      <PageHeader
        eyebrow="Reference"
        title="Compendium"
        explain="Everything that exists in this world — every trade good, every class of hull, every officer, every flag — whether or not you have met it yet. A reference only: nothing on this tab buys, hires or sails."
      />

      <Card head={<CardHeader flush title={shownFace.title} explain={shownFace.explain} />}>
        <TabRow
          label="Compendium faces"
          value={face}
          onChange={pickFace}
          className="mb-3"
          tabs={FACES.map((f) => ({
            id: f.id,
            label: f.label,
            hint:
              f.id === 'goods'
                ? snapshot.goods.length
                : f.id === 'ships'
                  ? snapshot.ship_classes.length
                  : f.id === 'captains'
                    ? (officers?.length ?? undefined)
                    : snapshot.nations.length,
          }))}
        />

        <div role="tabpanel" aria-label={shownFace.title}>
          {face === 'goods' && (
            <GoodsFace
              goods={snapshot.goods}
              query={query}
              onQuery={setQuery}
              kind={kind}
              onKind={setKind}
              tier={tier}
              onTier={setTier}
            />
          )}
          {face === 'ships' && (
            <ShipsFace classes={snapshot.ship_classes} query={query} onQuery={setQuery} kind={kind} onKind={setKind} />
          )}
          {face === 'captains' && (
            <CaptainsFace
              officers={officers}
              answered={rosterAnswered}
              portByCode={portByCode}
              nationByCode={nationByCode}
              query={query}
              onQuery={setQuery}
              kind={kind}
              onKind={setKind}
            />
          )}
          {face === 'nations' && (
            <NationsFace nations={snapshot.nations} portByCode={portByCode} query={query} onQuery={setQuery} />
          )}
        </div>
      </Card>
    </Screen>
  )
}

// ── the filter, the kinds, and the count — one recipe for all four faces ────────────────────────

/** A kind the data distinguishes: the raw value it filters on, and the word a player reads. */
interface KindOption {
  value: string
  label: string
}

/** Distinct values of one served field, in order of first appearance — the data's own order. */
function kindsOf<T>(rows: readonly T[], of: (row: T) => string, label: (value: string) => string): KindOption[] {
  const seen = new Set<string>()
  const out: KindOption[] = []
  for (const row of rows) {
    const v = of(row)
    if (seen.has(v)) continue
    seen.add(v)
    out.push({ value: v, label: label(v) })
  }
  return out
}

/** One chip-row filter over one served field. The goods face has two; the rest have at most one. */
interface FilterGroup {
  /** What the group filters by, for the group's accessible name: 'kind', 'rarity'. */
  axis: string
  kinds: KindOption[]
  kind: string | null
  onKind: (k: string | null) => void
}

function CatalogueControls({
  noun,
  query,
  onQuery,
  groups = [],
}: {
  noun: string
  query: string
  onQuery: (q: string) => void
  /** Each group renders only when the data distinguishes at least two — one chip filters nothing. */
  groups?: FilterGroup[]
}) {
  const shown = groups.filter((g) => g.kinds.length >= 2)

  // WHICH STRIPS ARE REALLY CLIPPED, so the swipe hint prints once, under the block, and only
  // while it is true — the Table.tsx rule (a hint that is false teaches the player to ignore the
  // hints that are not). Keyed by axis; the `shown.some` guard below keeps an axis that stopped
  // rendering (a face whose data distinguishes only one kind) from holding the hint up.
  const [clippedAxes, setClippedAxes] = useState<readonly string[]>([])
  const onClipped = useCallback((axis: string, clipped: boolean) => {
    setClippedAxes((prev) => {
      const has = prev.includes(axis)
      if (clipped) return has ? prev : [...prev, axis]
      return has ? prev.filter((a) => a !== axis) : prev
    })
  }, [])

  return (
    <div className="space-y-2">
      <Input
        size="sm"
        value={query}
        onChange={(e) => onQuery(e.target.value)}
        spellCheck={false}
        autoCorrect="off"
        aria-label={`Filter ${noun} by name`}
        placeholder={`Filter ${noun}…`}
      />
      {shown.map((g) => (
        <ChipStrip key={g.axis} noun={noun} group={g} onClipped={onClipped} />
      ))}
      {shown.some((g) => clippedAxes.includes(g.axis)) && (
        <p className={fineClass()}>{HSCROLL_HINT}</p>
      )}
    </div>
  )
}

/**
 * ONE FILTER AXIS IS ONE ROW, and the row scrolls sideways instead of wrapping.
 *
 * Wrapped, the goods face's two axes stood FIVE ROWS of 44px chips deep at 390px — ~250px of
 * filter before the first entry of the catalogue the tab exists to browse, and every category the
 * world grows adds another part-row. A strip's height is constant however large the catalogue
 * gets, and nothing about it ever appears, folds or moves on a press — the no-restructure law
 * (docs/OWNER_REQUESTS.md 15/25) is why this is a scroll and not a "Filters" fold: a strip is
 * static layout, a fold is a control that moves the list under the player's finger.
 *
 * A SIDEWAYS SCROLL MUST BE VISIBLE, or it is a feature that does not exist — this project has
 * shipped that defect once (tableLayout.ts's header carries the measurements). So the strip wears
 * the same two affordances the wide tables wear, from the same single authorities:
 *   · the drawn, thin, permanent scrollbar (hScrollClass — one recipe, both callers);
 *   · the swipe hint, printed only while the strip is really clipped (useClipped — one
 *     measurement, both callers; the parent prints it so two strips say it once).
 *
 * AND THE `all` CHIP IS STICKY AT THE LEFT — the tables' own reach rule (tableLayout.ts rule 3:
 * the first cell is the tap target and may never be scrolled out of reach), applied to the one
 * chip that clears the axis: however far the strip is swiped, the way back to "no filter" stays
 * on screen. It paints `bg-panel` for the same reason the tables' sticky column does — the card
 * body it sits on is bg-panel, and the chips sliding under it must not show through.
 *
 * `md`, not `sm`: these chips are the face's primary filter, not an in-row secondary action, and
 * md is the size that clears the 44px reach floor (buttonStyles.ts).
 */
function ChipStrip({
  noun,
  group,
  onClipped,
}: {
  noun: string
  group: FilterGroup
  onClipped: (axis: string, clipped: boolean) => void
}) {
  const boxRef = useRef<HTMLDivElement>(null)
  const clipped = useClipped(boxRef)
  useEffect(() => {
    onClipped(group.axis, clipped)
  }, [onClipped, group.axis, clipped])

  return (
    <div
      ref={boxRef}
      role="group"
      aria-label={`Filter ${noun} by ${group.axis}`}
      className={`flex gap-1.5 overflow-x-auto pb-1 ${hScrollClass()}`}
    >
      {/* The wrapper's pr + negative mr paint the flex gap beside the sticky chip, so a chip
          sliding under it can never show through the 6px seam. Layout is unchanged: the negative
          margin gives back exactly the padding's width. */}
      <span className="sticky left-0 z-10 -mr-1.5 shrink-0 bg-panel pr-1.5">
        <Button
          variant={group.kind == null ? 'chip-on' : 'chip'}
          size="md"
          className="font-mono text-xs uppercase tracking-wider"
          onClick={() => group.onKind(null)}
        >
          all
        </Button>
      </span>
      {group.kinds.map((k) => (
        <Button
          key={k.value}
          variant={group.kind === k.value ? 'chip-on' : 'chip'}
          size="md"
          className="shrink-0 whitespace-nowrap font-mono text-xs uppercase tracking-wider"
          onClick={() => group.onKind(group.kind === k.value ? null : k.value)}
        >
          {k.label}
        </Button>
      ))}
    </div>
  )
}

/**
 * HOW MANY OF HOW MANY — always stated, never implied. The goods list was once silently capped at
 * 12 of 68 in this project's history and it was a real defect; a list that says "70 of 70 goods"
 * cannot truncate quietly. And a filter that matches nothing says so WITH the filter it applied
 * (docs/UI_DIRECTION.md §4 rule 5): a bare empty list is indistinguishable from a broken one.
 */
function CatalogueCount({
  shown,
  total,
  noun,
  query,
  applied = [],
}: {
  shown: number
  total: number
  noun: string
  query: string
  /** The chip filters in force, pre-phrased by the face: 'the kind “Spices”', 'the rarity “rare”'. */
  applied?: string[]
}) {
  if (shown === 0) {
    const q = query.trim()
    return (
      <p className="py-2 text-sm text-ink-muted">
        {q === '' && applied.length === 0
          ? `The world serves no ${noun} yet.`
          : `None of the ${formatInt(total)} ${noun} answers to ` +
            [q === '' ? null : `“${q}”`, applied.length === 0 ? null : applied.join(' and ')]
              .filter(Boolean)
              .join(' under ') +
            '. Clear the filter to see them all.'}
      </p>
    )
  }
  return (
    <p className={fineClass('py-1')}>
      {formatInt(shown)} of {formatInt(total)} {noun}
    </p>
  )
}

// ── goods ───────────────────────────────────────────────────────────────────────────────────────

function GoodsFace({
  goods,
  query,
  onQuery,
  kind,
  onKind,
  tier,
  onTier,
}: {
  goods: readonly SnapshotGood[]
  query: string
  onQuery: (q: string) => void
  kind: string | null
  onKind: (k: string | null) => void
  tier: string | null
  onTier: (t: string | null) => void
}) {
  // Chips in the same alphabetical-by-kind order the rows group under, so the strip reads as the
  // table's own contents list rather than as the payload's code order.
  const kinds = useMemo(
    () => kindsOf(goods, (g) => g.category, categoryLabel).sort((a, b) => a.label.localeCompare(b.label)),
    [goods],
  )

  // The rarity chips keep the SCALE's order (common → exotic, RARITY_TIERS), not first-appearance
  // or alphabetical — a rarity is an ordered word, and 'exotic' before 'common' would misstate the
  // scale. Only tiers the payload actually serves render, so against a server predating 0032 the
  // whole group disappears rather than offering chips that filter everything to nothing.
  const tiers = useMemo(
    () =>
      RARITY_TIERS.filter((t) => goods.some((g) => g.rarity === t)).map((t) => ({
        value: t,
        label: rarityLabel(t),
      })),
    [goods],
  )

  // GROUPED BY KIND, then named. The snapshot serves goods ordered by CODE (0009:96), which
  // interleaves the seven categories — an honest order for a payload and an uncategorised one for
  // a reading. Sorting on two served fields is presentation, not authorship: no rank, no figure.
  const rows = useMemo(() => {
    const needle = fold(query.trim())
    return [...goods]
      .sort((a, b) => a.category.localeCompare(b.category) || a.name.localeCompare(b.name))
      .filter((g) => (kind === null ? true : g.category === kind))
      .filter((g) => (tier === null ? true : g.rarity === tier))
      .filter((g) => foldedMatch(needle, g.name, g.code, categoryLabel(g.category), g.rarity ?? ''))
  }, [goods, query, kind, tier])

  // THE KIND IS A HEADING, NOT A CELL. The table this replaces spent a column printing the
  // category down seventy rows; as tiles the kind heads its own group — the same fact, said once
  // per group instead of once per good, and the sort above already delivers the groups whole.
  const groups = useMemo(() => {
    const out: { category: string; rows: SnapshotGood[] }[] = []
    for (const g of rows) {
      const last = out[out.length - 1]
      if (last && last.category === g.category) last.rows.push(g)
      else out.push({ category: g.category, rows: [g] })
    }
    return out
  }, [rows])

  return (
    <div className="space-y-2">
      <CatalogueControls
        noun="goods"
        query={query}
        onQuery={onQuery}
        groups={[
          { axis: 'kind', kinds, kind, onKind },
          { axis: 'rarity', kinds: tiers, kind: tier, onKind: onTier },
        ]}
      />
      <CatalogueCount
        shown={rows.length}
        total={goods.length}
        noun="goods"
        query={query}
        applied={[
          ...(kind === null ? [] : [`the kind “${categoryLabel(kind)}”`]),
          ...(tier === null ? [] : [`the rarity “${rarityLabel(tier)}”`]),
        ]}
      />
      {/* TILES, NOT ROWS (the owner, 2026-08-23: "make trade goods in blocks as well, not all
          alligned in sentences — horizontally"). The same GoodTile MARKET composes, carrying this
          face's own figures: the tile is the design system's, the figures are the catalogue's.
          Nothing scrolls sideways and no name truncates. */}
      <div className="space-y-4">
        {groups.map((group) => (
          <div key={group.category}>
            <SectionLabel>{categoryLabel(group.category)}</SectionLabel>
            <div className={tileFieldClass()}>
              {group.rows.map((g) => (
                <GoodTile
                  key={g.code}
                  code={g.code}
                  category={g.category}
                  name={g.name}
                  rarity={g.rarity}
                  testId="good-tile"
                >
                  {/* Some anchors are half-ducat figures (82.50) — rounding them would misprint a
                      served value, so the halves keep one decimal and whole figures stay whole. */}
                  <EntryTileLine label="base">
                    {g.base_value % 1 === 0 ? formatDucats(g.base_value) : `${formatFixed(g.base_value, 1)} d.`}
                  </EntryTileLine>
                  <EntryTileLine label="bulk">{formatTuns(g.bulk, 1)}</EntryTileLine>
                  <EntryTileLine label="spoils">
                    {g.perishable_pct_day > 0 ? (
                      `${formatPct(g.perishable_pct_day, 1)}/day`
                    ) : (
                      <span className="text-ink-faint">{'—'}</span>
                    )}
                  </EntryTileLine>
                  <EntryTileLine label="refused by">
                    {g.culture_mask.length === 0 ? (
                      <span className="text-ink-faint">{'—'}</span>
                    ) : (
                      // UNAVAILABLE IS SHOWN WITH ITS REASON (§4 rule 5): the cultures whose
                      // ports refuse this good outright, in the server's own words.
                      <span className="text-warning">{g.culture_mask.join(', ')}</span>
                    )}
                  </EntryTileLine>
                </GoodTile>
              ))}
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}

// ── ships ───────────────────────────────────────────────────────────────────────────────────────

function ShipsFace({
  classes,
  query,
  onQuery,
  kind,
  onKind,
}: {
  classes: readonly SnapshotShipClass[]
  query: string
  onQuery: (q: string) => void
  kind: string | null
  onKind: (k: string | null) => void
}) {
  // The served grouping field is `family`. Today it holds one value ("Western"), so the chip row
  // does not render — see kindsOf. `tier` is the catalogue's own ladder, so the rows climb it.
  const kinds = useMemo(() => kindsOf(classes, (s) => s.family, (v) => v), [classes])

  // SERVED ORDER: the snapshot already serves ship classes by tier (0009:97) — the catalogue's
  // own ladder. Re-sorting here would be a second spelling of an ordering the server owns.
  const rows = useMemo(() => {
    const needle = fold(query.trim())
    return classes
      .filter((s) => (kind === null ? true : s.family === kind))
      .filter((s) => foldedMatch(needle, s.name, s.code, s.family, s.rig))
  }, [classes, query, kind])

  return (
    <div className="space-y-2">
      <CatalogueControls
        noun="ship classes"
        query={query}
        onQuery={onQuery}
        groups={[{ axis: 'kind', kinds, kind, onKind }]}
      />
      <CatalogueCount
        shown={rows.length}
        total={classes.length}
        noun="ship classes"
        query={query}
        applied={kind === null ? [] : [`the kind “${kind}”`]}
      />
      {/* TILES, NOT A TABLE YOU MUST SWIPE (the owner, 2026-08-26: "i told trade goods to be in
          grid like shape - organized not in lines"). MEASURED at 390px before the change: ten
          columns rendered a table 680px wide inside a 332px box, so a ship class was a full-width
          line with six of its ten figures behind a sideways swipe — docs/UI_DIRECTION.md §1's
          second diagnosis and its "no data is hidden on a phone" law at the same time. As tiles it
          is the SAME ten served figures, two classes abreast, every figure labelled in place and
          nothing off the right edge. The field is the goods' own (tileFieldClass) — one field, not
          a second grid recipe for ships. */}
      {rows.length > 0 && (
        <div className={tileFieldClass()}>
          {rows.map((s) => (
            <EntryTile
              key={s.code}
              name={s.name}
              mark={<Icon name="ship" size={18} className="mt-0.5 shrink-0 text-ink-muted" />}
              /* The tier is the catalogue's own ladder and the one figure that RANKS a hull, so it
                 rides in the corner where a good's rarity rides — same slot, same meaning: how far
                 up the scale this entry sits. */
              corner={<Badge tone="neutral">{`T${formatInt(s.tier)}`}</Badge>}
              testId="ship-tile"
            >
              <span className={fineClass('block')}>
                {s.family} {'·'} {s.rig}
              </span>
              <EntryTileLine label="hold">{formatTuns(s.hold)}</EntryTileLine>
              {/* crew she must have / berths she carries — two served figures, one pair. */}
              <EntryTileLine label="crew">{formatOfTotal(s.crew_required, s.crew_max)}</EntryTileLine>
              <EntryTileLine label="speed">{formatKnots(s.speed_kn)}</EntryTileLine>
              <EntryTileLine label="guns">{formatInt(s.guns)}</EntryTileLine>
              <EntryTileLine label="hull">{formatInt(s.durability)}</EntryTileLine>
              <EntryTileLine label="draft">{formatInt(s.draft)}</EntryTileLine>
              <EntryTileLine label="build">{formatInt(s.build_hours)} h</EntryTileLine>
              <EntryTileLine label="cost">{formatDucats(s.build_cost)}</EntryTileLine>
            </EntryTile>
          ))}
        </div>
      )}
    </div>
  )
}

// ── captains ────────────────────────────────────────────────────────────────────────────────────

function CaptainsFace({
  officers,
  answered,
  portByCode,
  nationByCode,
  query,
  onQuery,
  kind,
  onKind,
}: {
  officers: readonly Officer[] | null
  answered: boolean
  portByCode: Record<string, SnapshotPort>
  nationByCode: Record<string, SnapshotNation>
  query: string
  onQuery: (q: string) => void
  kind: string | null
  onKind: (k: string | null) => void
}) {
  const kinds = useMemo(
    () => (officers === null ? [] : kindsOf(officers, (o) => o.specialty, (v) => v.toLowerCase())),
    [officers],
  )

  const rows = useMemo(() => {
    if (officers === null) return []
    const needle = fold(query.trim())
    return officers
      .filter((o) => (kind === null ? true : o.specialty === kind))
      .filter((o) =>
        foldedMatch(
          needle,
          o.name,
          o.specialty,
          o.port === null ? null : portNameOf(portByCode, o.port),
          o.nation === null ? null : nationNameOf(nationByCode, o.nation),
        ),
      )
  }, [officers, query, kind, portByCode, nationByCode])

  if (officers === null) {
    return answered ? (
      <Notice tone="warning">
        The roster could not be read just now. The rest of the compendium does not depend on it —
        it will be tried again in a moment.
      </Notice>
    ) : (
      <div className="space-y-2">
        <Skeleton className="h-6 w-full" />
        <Skeleton className="h-6 w-full" />
        <Skeleton className="h-6 w-2/3" />
      </div>
    )
  }

  return (
    <div className="space-y-2">
      <CatalogueControls
        noun="officers"
        query={query}
        onQuery={onQuery}
        groups={[{ axis: 'kind', kinds, kind, onKind }]}
      />
      <CatalogueCount
        shown={rows.length}
        total={officers.length}
        noun="officers"
        query={query}
        applied={kind === null ? [] : [`the kind “${kind.toLowerCase()}”`]}
      />
      {/* TILES, NOT A COLUMN OF ENTRIES (the owner, 2026-08-26: "i told trade goods to be in grid
          like shape - organized not in lines"). MEASURED at 390px before the change: every officer
          was a 324px full-width block 107px tall — one per line, exactly the shape the goods face
          left behind three days earlier and this face did not. The facts are unchanged and none is
          dropped; they are aligned figure lines now instead of a run-on mono row, which is
          docs/UI_DIRECTION.md §4 rule 2. Same field as the goods and the hulls (tileFieldClass). */}
      <div className={tileFieldClass()}>
        {rows.map((o) => (
          <EntryTile
            key={o.code}
            name={o.name}
            mark={<Icon name="crew" size={18} className="mt-0.5 shrink-0 text-ink-muted" />}
            /* SIGNED is a fact about the world, not an offer: whose house holds their mark, and
               which fleet they serve in, is read from the roster and only read. */
            corner={o.hired ? <Badge tone="success">signed</Badge> : undefined}
            testId="officer-tile"
          >
            <span className="flex flex-wrap items-center gap-1.5">
              <Badge tone={o.takes_effect ? 'accent' : 'neutral'}>{o.specialty}</Badge>
            </span>
            {/* The blurb is who they are — the one piece of prose the 도감 exists to carry. It
                stays printed rather than going behind a dot: an Explain fold inside a grid cell
                would move the tiles beside it on a press, and nothing may move on a press
                (docs/OWNER_REQUESTS.md rows 15/25). */}
            <span className="block text-xs text-ink-muted">{o.blurb}</span>
            <EntryTileLine label="bonus">
              <span className={o.takes_effect ? 'text-success' : 'text-ink-faint'}>
                +{formatPctPoints(o.bonus_pct)}
              </span>
            </EntryTileLine>
            {/* "signs for" is the server's own phrase (0015's refusal says it word for word) — it
                is the LABEL now, which is where a name belongs, and the figure is the hero. */}
            <EntryTileLine label="signs for">{formatDucats(o.wage)}</EntryTileLine>
            <EntryTileLine label="port">
              {o.port === null ? (
                <span className="text-ink-faint">none fixed</span>
              ) : (
                portNameOf(portByCode, o.port)
              )}
            </EntryTileLine>
            {o.nation !== null && (
              <EntryTileLine label="nation">{nationNameOf(nationByCode, o.nation)}</EntryTileLine>
            )}
            {o.hired && (
              <EntryTileLine label="serving">
                <span className="text-accent">{o.fleet === null ? 'ashore' : o.fleet}</span>
              </EntryTileLine>
            )}
            {/* A bonus nothing reads is shown WITH that fact, never sold as working — the same
                reading PortFaces keeps, on the day a migration authors ahead of its rule. */}
            {!o.takes_effect && (
              <span className={fineClass('block')}>
                no rule reads this specialty yet — the bonus changes nothing
              </span>
            )}
          </EntryTile>
        ))}
      </div>
    </div>
  )
}

// ── nations ─────────────────────────────────────────────────────────────────────────────────────

function NationsFace({
  nations,
  portByCode,
  query,
  onQuery,
}: {
  nations: readonly SnapshotNation[]
  portByCode: Record<string, SnapshotPort>
  query: string
  onQuery: (q: string) => void
}) {
  // No kind chips: the catalogue serves no grouping field for a nation, and inventing one here
  // would be this screen authoring what the server does not say.
  const rows = useMemo(() => {
    const needle = fold(query.trim())
    return [...nations]
      .sort((a, b) => a.name.localeCompare(b.name))
      .filter((n) =>
        foldedMatch(needle, n.name, n.code, n.capital === null ? null : portNameOf(portByCode, n.capital)),
      )
  }, [nations, query, portByCode])

  return (
    <div className="space-y-2">
      <CatalogueControls noun="nations" query={query} onQuery={onQuery} />
      <CatalogueCount shown={rows.length} total={nations.length} noun="nations" query={query} />
      {rows.length > 0 && (
        <Table scrollHint className={scrollTableClass()}>
          <thead>
            <tr>
              <TH>Nation</TH>
              <TH>Code</TH>
              <TH>Capital</TH>
            </tr>
          </thead>
          <tbody>
            {rows.map((n) => (
              <tr key={n.code}>
                <TD>
                  <span className="flex items-center gap-2">
                    <span aria-hidden>{n.flag_char}</span>
                    {n.name}
                  </span>
                </TD>
                <TD className="font-mono text-ink-muted">{n.code}</TD>
                <TD>
                  {n.capital === null ? (
                    <span className="text-ink-faint">none named</span>
                  ) : (
                    portNameOf(portByCode, n.capital)
                  )}
                </TD>
              </tr>
            ))}
          </tbody>
        </Table>
      )}
    </div>
  )
}
