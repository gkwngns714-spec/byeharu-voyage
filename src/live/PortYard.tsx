import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  Button,
  Field,
  Figure,
  Hint,
  Icon,
  Note,
  Row,
  Tile,
  TileField,
  Tray,
  type TrayDetent,
} from '../components/ui'
import { HullCountry } from './HullCountry'
import { HullCrown } from './HullCrown'
import { HullTech } from './HullTech'
import { HullJob } from './HullJob'
import { hullJobOf } from './hullJobWord'
import { HullFight } from './HullFight'
import { useBuildingYard } from './useBuildingYard'
import { useYardSources } from './useYardSources'
import { useWorld } from './worldStore'
import { formatDucats, formatInt, formatMiles, formatTons } from '../lib/format'
import type { FleetView, HullMaterial, Refusal, YardHull, YardSource } from '../lib/rpc'
import { goTo, useGoTo } from '../chart'
import { useDeskGood } from '../store/deskGood'
import { useDeskView } from '../features/command/deskView'
import { properName, useLocale, useT, t as tNow } from '../lib/i18n'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE YARD — where a hull is laid down (0072), as a field of tiles.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner: *"i want another building - a 건조소 in korean, where you can create ships. Building
// ships will require not only some of the trading goods, but some items."*
//
// ── THE ONE THING THIS SCREEN HAS TO MAKE OBVIOUS ──────────────────────────────────────────────
// The materials come out of THIS CITY — its storage for timber, your store for fittings — and
// never out of her hold. A player who does not understand that will carry 40 tuns of timber to the
// yard, watch the order refuse, and conclude the game is broken. So every material row prints what
// is ashore HERE against what she wants.
//
// ── NO DRAFT WARNING (0139) ────────────────────────────────────────────────────────────────────
// Migration 0139 removed the E_DRAFT sailing gate: any hull enters any harbour, so a hull laid down
// here can never be too deep for this quay, and the yard says nothing about depth.
//
// ── A BORDER THAT NEVER RENDERED ───────────────────────────────────────────────────────────────
// The name box was `rounded border border-line bg-surface`. There has never been a `--color-line`
// token in `src/index.css` — the border was invisible from the day it was written, which is what a
// hand-drawn skin buys you (§3 rule 4). It is a `Field` now: one recipe, one focus ring, one 44px
// floor, and no token that has to exist for it to look right.
//
// ── A HULL'S COUNTRY (0130) ────────────────────────────────────────────────────────────────────
// Every hull belongs to a country's shipbuilding line and shows that country's flag. A hull is
// built only at build yards in its line's countries (some, like the three first hulls, at any).
// The server serves both halves of `buildable` — `tier_ok` and `wrong_yard`, the very sentence
// cmd.do_build refuses with (E_WRONG_YARD) — and the tray prints them as served.
//
// ── WHAT A HULL NEEDS OF YOU (0133) ────────────────────────────────────────────────────────────
// A hull may need a skill ("Nau / Carrack needs Portuguese Medium Hulls IV"). The server serves that
// sentence as `needs` — the very one cmd.do_build refuses with (E_NEEDS_SKILL) — and folds it into
// `buildable`; the tray prints it as served. null (nothing printed) while skills do not bite.
//
// ── A CROWN'S SHIP (0332) ──────────────────────────────────────────────────────────────────────
// The cargo ship and the navy ship are classes like any other and go through the same order; the server names them (`crown`), they stand first
// in their group so a player can find the hull he saw at sea, and the tray says she is his own to run. No price, gate or path differs.
//
// ── A YARD A PLAYER CAN FINISH (S8, 2026-11-11; owner rows 180, 305) ───────────────────────────
// The playtest: 50+ hulls, the cheapest wanting six materials, and nothing saying where any of them is had, so
// no player could plan a second ship. Now (1) the hulls the server says are buildable HERE AND NOW (`buildable`)
// stand first and every other hull waits under one "More" row, which opens below itself and moves nothing above
// it; nothing is removed. (2) Each missing material carries the nearest harbour that sells it (a good) or makes
// it (a fitting), served by world.yard_sources (0349) with the sailed miles, and a press that goes there by the
// doors that already exist: a good opens the Trade desk on that city with that good in hand (the map's own
// "Open in Command" hand-over, store/deskGood.ts); a fitting made here opens this city's Workshop face; one made
// elsewhere shows that harbour on the map (chart/goTo.ts). (3) The Build button stands when nothing is short.
//
// ── WHAT THIS FILE DOES NOT KNOW ───────────────────────────────────────────────────────────────
// Whether a hull can be built here. All of that is `cmd.do_build`'s and arrives answered.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** The crown's ships first, the served order otherwise. A presentation of the served list, not a rule. */
const crownFirst = (list: readonly YardHull[]) => [...list.filter((h) => h.crown), ...list.filter((h) => !h.crown)]

/** What is missing, in the server's own numbers, or null when everything is to hand. */
function shortfall(hull: YardHull): string | null {
  const short = [...hull.goods, ...hull.items].filter((m) => m.have < m.qty)
  if (short.length === 0) return null
  return short.map((m) => `${m.name} ${formatInt(m.have)}/${formatInt(m.qty)}`).join(' · ')
}

export function PortYard({
  portId,
  fleet,
  tier,
}: {
  portId: string
  /** A fleet of yours lying here, or null — a new hull joins the fleet that ordered her. */
  fleet: FleetView | null
  /** This city's building-yard tier, from the port's own building row. */
  tier: number
}) {
  const t = useT()
  const { view, loading } = useBuildingYard(portId)
  const locale = useLocale()
  const classes = useWorld((s) => s.snapshot?.ship_classes)
  const [open, setOpen] = useState<YardHull | null>(null)
  const [detent, setDetent] = useState<TrayDetent>('half')
  const [name, setName] = useState('')
  const [sending, setSending] = useState(false)
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  // 0276 — the toast after a build: the ship just laid down and her grade word (nothing when the
  // hull is standard, or when the server is older than 0276 and serves no grade).
  const [built, setBuilt] = useState<{ name: string; grade: string } | null>(null)
  const issue = useWorld((s) => s.issue)
  // S8: the hulls you cannot build here and now wait under one row; it opens once and stays open (a press never collapses the page).
  const [more, setMore] = useState(false)
  const sources = useYardSources(portId, open?.class ?? null)

  const build = (hull: YardHull) => {
    if (!fleet || sending || name.trim().length < 3) return
    setSending(true)
    setRefusal(null)
    const wanted = name.trim()
    void (async () => {
      const okay = await issue(fleet.id, `BUILD ${hull.class} ${wanted}`, null)
      setSending(false)
      if (okay) {
        setOpen(null)
        setName('')
        // The world was read back on success: the ship just laid down is the one the order named,
        // and her grade word is the server's — nothing is derived from the roll here.
        const ships = useWorld.getState().fleets.find((f) => f.id === fleet.id)?.ships ?? []
        const grade = ships.find((s) => s.name === wanted)?.grade
        if (grade) setBuilt({ name: wanted, grade })
      } else {
        setRefusal(useWorld.getState().refusal)
      }
    })()
  }

  if (loading && !view) return <Note tone="neutral">{t('yard.loading')}</Note>
  if (!view) return <Note tone="neutral">{t('yard.noYard')}</Note>

  // S8 — WHAT YOU CAN BUILD HERE AND NOW FIRST: the server's own `buildable` (this yard's tier and country, your
  // skills, one famous ship to a house) splits the list; the rest wait under one "More" row — the hulls this
  // port's country builds that you cannot yet (0135: `wrong_yard` null), then the ones built abroad, under their
  // caption. A split of the served list, not a rule.
  const now = crownFirst(view.hulls.filter((h) => h.buildable))
  const later = crownFirst(view.hulls.filter((h) => !h.buildable && !h.wrong_yard))
  const elsewhere = crownFirst(view.hulls.filter((h) => !h.buildable && h.wrong_yard))
  const hidden = later.length + elsewhere.length
  // 0366: a hull is named in the viewer's language here as in the Codex (the one name map; a name with no entry prints as served)
  const hullName = (served: string) => properName('hull', served, served, locale)
  const tile = (hull: YardHull) => (
    <Tile
      key={hull.class}
      mark={<Icon name="ship" size={20} />}
      name={hullName(hull.name)}
      meta={
        <>
          <HullCountry nation={hull.line_nation} compact />
          {hull.line_nation ? ' ' : ''}
          <HullTech tech={hull.tech} />
          <HullCrown crown={hull.crown} />
          <HullJob code={hull.class} />
          {formatTons(hull.hold)}
        </>
      }
      state={hull.buildable ? 'rest' : 'muted'}
      tap="whole"
      onClick={() => {
        setRefusal(null)
        setBuilt(null)   // 0276: a fresh look at a hull clears the last build's toast
        setDetent('half')
        setOpen(hull)
      }}
      figure={<Figure value={formatDucats(hull.ducats)} unit={t('yard.toBuild')} />}
      data-testid={`hull-${hull.class}`}
    />
  )
  const short = open ? shortfall(open) : null
  const ready = open !== null && open.buildable && fleet !== null && short === null

  return (
    <div data-testid="port-yard">
      {built && (
        <Note tone="accent" data-testid="yard-built" className="mb-3">
          {built.grade === 'fine' ? t('yard.builtFine', { name: built.name }) : t('yard.builtPoor', { name: built.name })}
        </Note>
      )}
      {!fleet && (
        <Note tone="warning" className="mb-3">
          {t('yard.noFleetYard')}
        </Note>
      )}

      {now.length > 0 && (
        <div data-testid="yard-now">
          <TileField>{now.map(tile)}</TileField>
        </div>
      )}
      {hidden > 0 && (
        <Row
          label={t('yard.moreN', { n: formatInt(hidden) })}
          chevron={!more}
          onClick={more ? undefined : () => setMore(true)}
          aria-expanded={more}
          className={now.length > 0 ? 'mt-3' : undefined}
          hairline={false}
          data-testid="yard-more"
        />
      )}
      {more && later.length > 0 && (
        <div data-testid="yard-later">
          <TileField>{later.map(tile)}</TileField>
        </div>
      )}
      {more && elsewhere.length > 0 && (
        <div className={later.length > 0 ? 'mt-4' : undefined} data-testid="yard-elsewhere">
          <Hint className="mb-2">{t('yard.elsewhere')}</Hint>
          <TileField>{elsewhere.map(tile)}</TileField>
        </div>
      )}

      {open && (
        <Tray
          detent={detent}
          onDetentChange={(next) => (next === 'closed' ? setOpen(null) : setDetent(next))}
          title={hullName(open.name)}
          data-testid="yard-tray"
          action={
            ready ? (
              <Button
                variant="primary"
                className="w-full"
                busy={sending}
                busyLabel={t('yard.building')}
                disabled={name.trim().length < 3}
                onClick={() => build(open)}
                data-testid={`lay-down-${open.class}`}
              >
                {t('yard.layDown')}
              </Button>
            ) : undefined
          }
        >
          {/* 0166 (S17): a famous ship carries her history line — the hull's served note, printed as served */}
          {open.tech === 'F' && (
            <Hint className="mb-2" data-testid="yard-history">
              {open.note}
            </Hint>
          )}
          {open.crown && (
            <>
              <Row label={t('yard.type')} value={<HullCrown crown={open.crown} />} hairline={false} />
              <Hint className="mb-2" data-testid="yard-crown-note">
                {t('yard.crownNote')}
              </Hint>
            </>
          )}
          {open.line_nation && <Row label={t('yard.country')} value={<HullCountry nation={open.line_nation} />} />}
          {/* 0366: what she is built to do */}
          {hullJobOf(open.class) && <Row label={t('codex.hullJob')} value={<HullJob code={open.class} />} data-testid="yard-job" />}
          <Row label={t('yard.cargo')} value={<Figure value={formatInt(open.hold)} unit={t('yard.tons')} />} />
          <Row label={t('yard.speed')} value={<Figure value={open.speed_kn} unit={t('yard.knots')} />} />
          <Row label={t('yard.crewNeeded')} value={<Figure value={formatInt(open.crew_required)} />} />
          {/* 0366: the five figures the fight reads, from the class's own row (the snapshot's) */}
          <HullFight cls={classes?.find((c) => c.code === open.class)} />
          {/* 0276 — the blind roll, said before you build: the class figures above are the average,
              and a new hull strays by this much (the rare Poor and Fine beyond). */}
          {open.variety_pct !== undefined && open.variety_pct > 0 && (
            <Row
              label={t('yard.variety')}
              value={<Figure value={`±${formatInt(open.variety_pct)} %`} />}
              data-testid="yard-variety"
            />
          )}
          <Materials label={t('yard.materials')} list={open.goods} sources={sources.view?.goods} kind="good" />
          <Materials label={t('yard.parts')} list={open.items} sources={sources.view?.items} kind="item" />
          {open.goods.some((m) => m.have < m.qty) && (
            <Hint className="mb-2" data-testid="yard-store-hint">
              {t('yard.storeHint')}
            </Hint>
          )}

          {open.wrong_yard && (
            <Note tone="warning" data-testid="yard-country">
              {open.wrong_yard}
            </Note>
          )}
          {open.needs && (
            <Note tone="warning" data-testid="yard-needs">
              {open.needs}
            </Note>
          )}
          {open.unmade && (
            <Note tone="warning" data-testid="yard-unmade">
              {open.unmade}
            </Note>
          )}
          {open.famous_held && (
            <Note tone="warning" data-testid="yard-famous-held">
              {open.famous_held}
            </Note>
          )}
          {open.tier_ok === false && (
            <Note tone="warning">
              {t('yard.yardTier', { have: formatInt(tier), need: formatInt(open.yard_tier) })}
            </Note>
          )}
          {open.buildable && short !== null && (
            <Note tone="warning">{t('yard.missing', { list: short })}</Note>
          )}

          {ready && (
            /* THE NAME IS THE PLAYER'S, and it is asked for before the order is sent rather than
               invented — a ship you did not name is not yours. */
            <Field
              icon={null}
              value={name}
              maxLength={24}
              placeholder={t('yard.shipName')}
              onChange={(e) => setName(e.target.value)}
              className="mt-3"
              aria-label={t('yard.shipName')}
              data-testid="yard-name"
            />
          )}
          {refusal && (
            <Note tone="danger" code={refusal.code} figures={refusal.figures}>
              {refusal.sentence}
            </Note>
          )}
        </Tray>
      )}
    </div>
  )
}

/** One material line: what she wants, against what is ashore in this city — and, while she is short of it, where it
 *  is had nearest (0349), as a press that goes there. */
function Materials({
  label,
  list,
  sources,
  kind,
}: {
  label: string
  list: readonly HullMaterial[]
  /** world.yard_sources' rows for this list; undefined while the read is on the wire. */
  sources: readonly YardSource[] | undefined
  kind: 'good' | 'item'
}) {
  if (list.length === 0) return null
  return (
    <>
      {list.map((m, i) => {
        const short = m.have < m.qty
        const source = short ? sources?.find((s) => s.code === m.code) : undefined
        return (
          <div key={m.code}>
            <Row
              label={i === 0 ? `${label} · ${m.name}` : m.name}
              hairline={!source}
              value={
                <Figure
                  value={formatInt(m.qty)}
                  unit={tNow('yard.inStorageN', { n: formatInt(m.have) })}
                  tone={short ? 'warning' : 'ink'}
                />
              }
            />
            {source && <SourceRow source={source} kind={kind} />}
          </div>
        )
      })}
    </>
  )
}

/** Where a missing material is had nearest, and the press that goes there by a door that already exists. */
function SourceRow({ source, kind }: { source: YardSource; kind: 'good' | 'item' }) {
  const t = useT()
  const navigate = useNavigate()
  const openOnDesk = useDeskGood((s) => s.open)
  if (source.port === null || source.name === null) {
    return <Row label={t('yard.nowhere')} data-testid={`yard-source-${source.code}`} />
  }
  const here = source.miles === 0
  const port = source.port
  const go = () => {
    if (kind === 'good') {
      // the map's own hand-over (live/PriceTray.tsx "Open in Command"): the Trade desk reads this city, this good in hand
      openOnDesk(source.code, port)
      navigate('/command')
    } else if (here) {
      // a fitting is made at this city's Workshop face
      useDeskView.getState().setCityFace('workstation')
      useDeskView.getState().turnTo('city')
      navigate('/command')
    } else {
      // a fitting made elsewhere: that harbour on the map (outside the shell no tab answers the request, so the route does)
      goTo({ kind: 'port', code: port })
      if (!useGoTo.getState().openMap) navigate('/map')
    }
  }
  const words =
    kind === 'good'
      ? here
        ? t('yard.buyHere')
        : t('yard.buyAt', { name: source.name })
      : here
        ? t('yard.makeHere')
        : t('yard.makeAt', { name: source.name })
  return (
    <Row
      label={words}
      value={here || source.miles === null ? undefined : <Figure value={formatMiles(source.miles)} />}
      chevron
      onClick={go}
      data-testid={`yard-source-${source.code}`}
      data-port={port}
    />
  )
}
