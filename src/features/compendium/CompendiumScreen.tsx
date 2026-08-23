import { useCallback, useEffect, useMemo, useState } from 'react'
import {
  Badge,
  Button,
  Card,
  CardHeader,
  Icon,
  Input,
  Notice,
  PageHeader,
  RARITY_TIERS,
  RarityMark,
  Screen,
  Skeleton,
  TD,
  TH,
  TabRow,
  Table,
  categoryLabel,
  fineClass,
  goodIcon,
  headRowClass,
  rarityLabel,
  scrollTableClass,
} from '../../components/ui'
import { formatDucats, formatFixed, formatInt, formatKnots, formatOfTotal, formatPct, formatPctPoints, formatTuns } from '../../lib/format'
import type { Officer, SnapshotGood, SnapshotNation, SnapshotPort, SnapshotShipClass } from '../../lib/rpc'
import { fold, foldedMatch } from '../../lib/text'
import { nationNameOf, portNameOf, useWorld } from '../../live/worldStore'
import { ReadAgain, WorldFailed, WorldLoading } from '../../live/WorldGate'

// COMPENDIUM — the 도감: everything that exists in this world, catalogued, whether or not you have
// met it. The owner, 2026-08-23: "create a 도감, separate tab, showing all the trade goods, ships,
// captains that are made in this game. categorize them, make filters."
//
// ── IT IS A REFERENCE. IT COMMANDS NOTHING. ────────────────────────────────────────────────────
// No buy, no hire, no sail, no hand-off. Every acting surface already exists once — orders are
// composed on COMMAND, officers sign on at their home quay on PORT, hulls are a yard's business —
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
  /** The face's standing explanation — column meanings and refusals. Behind the ⓘ, never live. */
  explain: string
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
    explain:
      'Every class of hull a yard can lay down, as the shipwright rates her — before any ' +
      'officer or skill touches the figures. CREW is what she must have aboard against the berths ' +
      'she carries. HULL is her rated durability. DRAFT is the water she needs — a port’s ' +
      'harbour has a depth, and a hull that draws more cannot come alongside. BUILD is the yard’s ' +
      'time and the yard’s bill.',
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
  const refresh = useWorld((s) => s.refresh)
  const portByCode = useWorld((s) => s.portByCode)
  const nationByCode = useWorld((s) => s.nationByCode)

  // WHETHER THE ROSTER HAS ANSWERED, which `officers === null` alone cannot say (the RANK board's
  // reason, borrowed with its shape): null is both "not asked yet" and "the read was refused", and
  // without the distinction a refused read draws a skeleton for ever.
  const [rosterAnswered, setRosterAnswered] = useState(false)

  useEffect(() => {
    let alive = true
    void loadOfficers().then(() => {
      if (alive) setRosterAnswered(true)
    })
    return () => {
      alive = false
    }
  }, [loadOfficers])

  // READ AGAIN MEANS THE ROSTER TOO: `refresh()` does not know about officers (its cadence is the
  // world's), and the one live thing on this screen — who has signed, and whose fleet they serve —
  // moves with the roster.
  const readAgain = useCallback(async () => {
    await Promise.all([refresh(), loadOfficers()])
  }, [refresh, loadOfficers])

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
        actions={<ReadAgain read={readAgain} />}
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
      {groups
        .filter((g) => g.kinds.length >= 2)
        .map((g) => (
          /* `md`, not `sm`: these chips are the face's primary filter, not an in-row secondary
             action, and md is the size that clears the 44px reach floor (buttonStyles.ts). */
          <div
            key={g.axis}
            className="flex flex-wrap gap-1.5"
            role="group"
            aria-label={`Filter ${noun} by ${g.axis}`}
          >
            <Button
              variant={g.kind == null ? 'chip-on' : 'chip'}
              size="md"
              className="font-mono text-xs uppercase tracking-wider"
              onClick={() => g.onKind(null)}
            >
              all
            </Button>
            {g.kinds.map((k) => (
              <Button
                key={k.value}
                variant={g.kind === k.value ? 'chip-on' : 'chip'}
                size="md"
                className="font-mono text-xs uppercase tracking-wider"
                onClick={() => g.onKind(g.kind === k.value ? null : k.value)}
              >
                {k.label}
              </Button>
            ))}
          </div>
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
      {rows.length > 0 && (
        <Table scrollHint className={scrollTableClass()}>
          <thead>
            <tr>
              <TH>Good</TH>
              <TH>Kind</TH>
              <TH>Rarity</TH>
              <TH align="num">Base</TH>
              <TH align="num">Bulk</TH>
              <TH align="num">Spoils</TH>
              <TH>Refused by</TH>
            </tr>
          </thead>
          <tbody>
            {rows.map((g) => (
              <tr key={g.code}>
                <TD>
                  <span className="flex items-center gap-2">
                    {/* Every one of the seventy has its OWN drawn mark (goodIcons.ts) — the
                        category glyph is only the fallback for a good a migration lands undrawn. */}
                    <Icon name={goodIcon(g.code, g.category)} size={18} className="shrink-0 text-ink-muted" />
                    {g.name}
                  </span>
                </TD>
                <TD className="text-ink-muted">{categoryLabel(g.category)}</TD>
                <TD>
                  {/* Colour AND shape, from the one rendering (Rarity.tsx) — the tier qualifies
                      the good; the drawn mark and the name stay the row's subject. */}
                  <RarityMark rarity={g.rarity} withWord />
                </TD>
                {/* Some anchors are half-ducat figures (82.50) — rounding them would misprint a
                    served value, so the halves keep one decimal and the whole figures stay whole. */}
                <TD align="num">{g.base_value % 1 === 0 ? formatDucats(g.base_value) : `${formatFixed(g.base_value, 1)} d.`}</TD>
                <TD align="num">{formatTuns(g.bulk, 1)}</TD>
                <TD align="num">
                  {g.perishable_pct_day > 0 ? (
                    `${formatPct(g.perishable_pct_day, 1)}/day`
                  ) : (
                    <span className="text-ink-faint">{'—'}</span>
                  )}
                </TD>
                <TD>
                  {g.culture_mask.length === 0 ? (
                    <span className="text-ink-faint">{'—'}</span>
                  ) : (
                    // UNAVAILABLE IS SHOWN WITH ITS REASON (§4 rule 5): the cultures whose ports
                    // refuse this good outright, in the server's own words.
                    <span className="text-warning">{g.culture_mask.join(', ')}</span>
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
      {rows.length > 0 && (
        <Table scrollHint className={scrollTableClass()}>
          <thead>
            <tr>
              <TH>Ship</TH>
              <TH align="num">Tier</TH>
              <TH align="num">Hold</TH>
              <TH align="num">Crew</TH>
              <TH align="num">Speed</TH>
              <TH align="num">Guns</TH>
              <TH align="num">Hull</TH>
              <TH align="num">Draft</TH>
              <TH align="num">Build</TH>
              <TH align="num">Cost</TH>
            </tr>
          </thead>
          <tbody>
            {rows.map((s) => (
              <tr key={s.code}>
                <TD>
                  <span className="flex flex-col">
                    <span>{s.name}</span>
                    <span className={fineClass()}>
                      {s.family} {'·'} {s.rig}
                    </span>
                  </span>
                </TD>
                <TD align="num">{formatInt(s.tier)}</TD>
                <TD align="num">{formatTuns(s.hold)}</TD>
                {/* crew she must have / berths she carries — two served figures, one pair. */}
                <TD align="num">{formatOfTotal(s.crew_required, s.crew_max)}</TD>
                <TD align="num">{formatKnots(s.speed_kn)}</TD>
                <TD align="num">{formatInt(s.guns)}</TD>
                <TD align="num">{formatInt(s.durability)}</TD>
                <TD align="num">{formatInt(s.draft)}</TD>
                <TD align="num">{formatInt(s.build_hours)} h</TD>
                <TD align="num">{formatDucats(s.build_cost)}</TD>
              </tr>
            ))}
          </tbody>
        </Table>
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
        read again to try the roster once more.
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
      <ul>
        {rows.map((o) => (
          <li key={o.code} className="border-b border-edge/50 py-2.5 last:border-b-0">
            <div className={headRowClass(true, 'mb-0')}>
              <span className="font-serif text-base text-ink">{o.name}</span>
              <span className="flex items-center gap-1.5">
                <Badge tone={o.takes_effect ? 'accent' : 'neutral'}>{o.specialty}</Badge>
                {/* SIGNED is a fact about the world, not an offer: whose house holds their mark,
                    and which fleet they serve in, is read from the roster and only read. */}
                {o.hired && <Badge tone="success">signed</Badge>}
              </span>
            </div>
            <p className="mt-0.5 text-xs text-ink-muted">{o.blurb}</p>
            <div className="mt-1.5 flex flex-wrap items-baseline gap-x-4 gap-y-1 font-mono text-xs">
              <span className={o.takes_effect ? 'text-success' : 'text-ink-faint'}>
                +{formatPctPoints(o.bonus_pct)}
              </span>
              {/* "signs for" is the server's own phrase (0015's refusal says it word for word). */}
              <span className="text-ink-muted">signs for {formatDucats(o.wage)}</span>
              <span className="text-ink-muted">
                {o.port === null ? 'no fixed port' : `of ${portNameOf(portByCode, o.port)}`}
              </span>
              {o.nation !== null && (
                <span className="text-ink-faint">{nationNameOf(nationByCode, o.nation)}</span>
              )}
              {o.hired && <span className="text-accent">{o.fleet === null ? 'ashore' : `aboard ${o.fleet}`}</span>}
            </div>
            {/* A bonus nothing reads is shown WITH that fact, never sold as working — the same
                reading PortFaces keeps, on the day a migration authors ahead of its rule. */}
            {!o.takes_effect && (
              <p className={fineClass('mt-1')}>no rule reads this specialty yet — the bonus changes nothing</p>
            )}
          </li>
        ))}
      </ul>
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
