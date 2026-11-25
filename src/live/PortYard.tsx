import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  Bar,
  Button,
  Field,
  Figure,
  GroupHeading,
  Hint,
  Icon,
  KEEP_WORDS_CLASS,
  Note,
  Row,
  Tile,
  TileField,
  Tray,
  goodIcon,
  type TrayDetent,
} from '../components/ui'
import { ShipPicture } from './ShipPicture'
import { HullCountry } from './HullCountry'
import { HullCrown } from './HullCrown'
import { HullTech } from './HullTech'
import { HullJob } from './HullJob'
import { hullJobOf } from './hullJobWord'
import { HullFight } from './HullFight'
import { useBuildingYard } from './useBuildingYard'
import { useServedRead } from './useServedRead'
import { useYardSources } from './useYardSources'
import { WrecksLine } from './WrecksLine'
import { useWorld } from './worldStore'
import { planStops, yardPlan, type PlanGood, type PlanPart } from './yardPlan'
import { fleetCargoByCode, fleetCrew } from '../domain/fleet/derive'
import { formatDucats, formatInt, formatMiles, formatRealShort, formatTons, voyageDaysToRealMs } from '../lib/format'
import { cmdLaunchHull, cmdOrderHull, worldHullQuote, worldLevels } from '../lib/rpc'
import type { FleetView, HullQuote, LevelsView, PlanLine, Refusal, YardHull, YardInput, YardSource } from '../lib/rpc'
import { goTo, useGoTo } from '../chart'
import { useDeskGood } from '../store/deskGood'
import { openOfficeCity, useYardAsk } from '../features/command/officeView'
import { useRouteSeed } from '../features/map/routeSeed'
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
// ── THE YARD PLANS THE BUILD (S1 of docs/SECOND_SHIP.md, 0358; owner rows 180, 305, 316) ──────────────────────
// The playtest of the above: a new company could still not finish. The two parts hide three more goods (flax, hemp,
// iron), nothing said that hull goods must be STORED here while parts are MADE from the hold, no price or weight was
// added up, the Build button was hidden until everything was there, a full fleet refused only after the whole errand,
// and the new ship came with no crew. So the sheet now carries ONE button, always there for a hull this yard builds,
// whose label is the next thing she can do (./yardPlan.ts: Make parts, Store, Build; else Build off beside
// "Ready 2 / 6"; "Hire crew" once she is laid down). Each line reads need / in storage / on board and, while short, the
// seller with miles, real time and cost; a part unfolds into its goods; a totals row adds the cost and weighs the errand
// against her free hold; "Fleet full" is said first. world.yard_sources serves the goods, weights and prices (0358);
// the fleet's room is world.levels()'s (`room.fleet_ship_max`, public.earned_caps: the cap cmd.do_build's ship insert
// is refused by). A press moves nothing above it: the totals stand above the lines, a part opens below itself, and the
// button is the tray's pinned action.
//
// ── THE BARCA NEEDS NO PARTS, AND THE TRIP IS ONE PRESS (S2 + S3, 0363) ────────────────────────────────────────
// Since 0363 the first hull a house builds takes four goods and no part ("Ready 0 / 4"); the Caravela latina, the Nau
// and the famous ships keep theirs, so everything above about parts still stands. "Plan trip" (under the totals,
// while something is still to fetch by sea) hands the sellers of what is short, nearest first and then this quay
// again, to the Map's route builder as a draft (features/map/routeSeed.ts). Nothing is sent by the press.
//
// ── THE YARD TAKES AN ORDER (0465, content plan slice C) ─────────────────────────────────────────────────────────
// While the server serves the yard's `order` key (yard_order_enabled lit; absent dark, so nothing here shows), a hull this yard
// builds for you carries a second press under the one button: "Order · price", the whole price paid now (labour, every good at
// the nearest seller's ask, and the fee: world.hull_quote, the one reading) with the wait beside the totals. The order then stands
// at the top of the yard with its countdown; once ready, a name and "Launch" put her into the fleet lying here (cmd.launch_hull).
// Your orders at other yards stand under it. The materials route is untouched and stays the cheaper, instant way.
//
// ── HULLS AS PICTURES, ONE PRICE, MATERIALS AS BARS (2026-11-23, the visual overhaul's slice 10) ──────────────────────────────
// The play-test read four prices on one hull (the tile's labour, Labour, Total, the Order and its fee). #800 made the Order the gold
// press while materials are short and named Labour and the First-ship fee; that logic stands. The look is simpler: a hull's tile leads
// with her picture (`ShipPicture`, the Fleets tab's own: the one drawing of a ship, at the class's served tier) and carries ONE
// figure, her labour; the sheet opens on her picture and carries two prices, one a road: Total (build her yourself) and the Order
// press. Labour and the order's fee are the small print under them, not rows of their own. Each material is its mark, its need, and a
// bar of what is stored here (what is on board washed on: it counts once stored), with the words under the bar.
//
// ── WHAT THIS FILE DOES NOT KNOW ───────────────────────────────────────────────────────────────
// Whether a hull can be built here. All of that is `cmd.do_build`'s and arrives answered.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** The crown's ships first, the served order otherwise. A presentation of the served list, not a rule. */
const crownFirst = (list: readonly YardHull[]) => [...list.filter((h) => h.crown), ...list.filter((h) => !h.crown)]

/** What is missing, in the server's own numbers, or null when everything is to hand. */
function shortfall(hull: YardHull): string | null {
  const short = [
    ...hull.goods.map((m) => ({ ...m, name: properName('good', m.code, m.name) })),
    ...hull.items,
  ].filter((m) => m.have < m.qty)
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
  const issueLines = useWorld((s) => s.issueLines)
  const navigate = useNavigate()
  // S1: which parts stand unfolded (a part opens below itself), and whether a hull was laid down from this sheet
  const [unfolded, setUnfolded] = useState<ReadonlySet<string>>(new Set())
  const [laid, setLaid] = useState(false)
  // the fleet's room: the same cached read the You page's levels ask (world.levels, 0325)
  const levels = useServedRead<LevelsView>('levels', () => worldLevels(), { name: 'worldLevels' })
  // 0465: the yard's order (absent dark), the quote of the hull in hand, and the order's countdown
  const order = view?.order
  const refresh = useWorld((s) => s.refresh)
  const quoteClass = order?.on && open && !order.open ? open.class : null
  const quote = useServedRead<HullQuote>(
    quoteClass === null ? null : `${portId}:${quoteClass}`,
    () => worldHullQuote(portId, quoteClass as string),
    { name: 'worldHullQuote' },
  )
  const [ordering, setOrdering] = useState(false)
  const [launchName, setLaunchName] = useState('')
  const [launchRefusal, setLaunchRefusal] = useState<Refusal | null>(null)
  const [launched, setLaunched] = useState<string | null>(null)
  const [clock, setClock] = useState(() => Date.now())
  // her purse: the Order she cannot pay yet says by how much, on the button (2026-11-23 play-test: the refusal stood below the fold)
  const purse = useWorld((s) => s.ducats)
  // A HULL ASKED FOR FROM OUTSIDE (the goal card's press, officeView.ts `useYardAsk`): its sheet opens once the yard has answered
  const asked = useYardAsk((s) => s.hull)
  useEffect(() => {
    if (asked === null || !view) return
    // on the next frame, as a press would: the yard's tiles are drawn first, and the sheet rises over them
    const frame = requestAnimationFrame(() => {
      const h = view.hulls.find((x) => x.class === useYardAsk.getState().take())
      if (!h) return
      setRefusal(null)
      setDetent('half')
      setOpen(h)
    })
    return () => cancelAnimationFrame(frame)
  }, [asked, view])
  const waiting = order?.open && !order.open.ready ? order.open.ready_at : null
  useEffect(() => {
    if (waiting === null) return
    const id = setInterval(() => setClock(Date.now()), 1000)
    return () => clearInterval(id)
  }, [waiting])

  const placeOrder = (hull: YardHull) => {
    if (ordering) return
    setOrdering(true)
    setRefusal(null)
    setLaunched(null)
    void (async () => {
      const r = await cmdOrderHull(portId, hull.class)
      if (r.ok) {
        await refresh()
        setOpen(null)
      } else {
        setRefusal(r.refusal)
      }
      setOrdering(false)
    })()
  }
  const launch = () => {
    const wanted = launchName.trim()
    if (!fleet || ordering || wanted.length < 3) return
    setOrdering(true)
    setLaunchRefusal(null)
    void (async () => {
      const r = await cmdLaunchHull(fleet.id, wanted)
      if (r.ok) {
        setLaunched(r.value.name)
        setLaunchName('')
        await refresh()
      } else {
        setLaunchRefusal(r.refusal)
      }
      setOrdering(false)
    })()
  }

  const send = (lines: readonly PlanLine[]) => {
    if (!fleet || sending || lines.length === 0) return
    setSending(true)
    setRefusal(null)
    void (async () => {
      const okay = await issueLines(fleet.id, lines)
      setSending(false)
      if (!okay) setRefusal(useWorld.getState().refusal)
    })()
  }
  /** The hire door that exists: this city's Inn, on the Office tab's City face. */
  const toInn = () => {
    navigate(openOfficeCity('inn'))
  }

  const build = (hull: YardHull) => {
    if (!fleet || sending || name.trim().length < 3) return
    setSending(true)
    setRefusal(null)
    const wanted = name.trim()
    void (async () => {
      const okay = await issue(fleet.id, `BUILD ${hull.class} ${wanted}`, null)
      setSending(false)
      if (okay) {
        // S1: the sheet stays: its one button now reads "Hire crew", the next thing she can do
        setLaid(true)
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
      mark={<ShipPicture code={hull.class} />}
      name={hullName(hull.name)}
      meta={
        <>
          <HullCountry nation={hull.line_nation} compact />
          {hull.line_nation ? ' ' : ''}
          <HullTech tech={hull.tech} />
          <HullCrown crown={hull.crown} />
          <HullJob code={hull.class} />
          {/* the tonnage is one figure: "1,275 tons" stood as "1,275" over "tons" in a half-width tile (2026-11-14) */}
          <span className="whitespace-nowrap">{formatTons(hull.hold)}</span>
        </>
      }
      state={hull.buildable ? 'rest' : 'muted'}
      tap="whole"
      onClick={() => {
        setRefusal(null)
        setBuilt(null)   // 0276: a fresh look at a hull clears the last build's toast
        setLaid(false)
        setUnfolded(new Set())
        setDetent('half')
        setOpen(hull)
      }}
      // the yard's LABOUR, said as such (2026-11-22 second play-test: the bare figure read as the hull's price beside Total and Order)
      figure={<Figure value={formatDucats(hull.ducats)} unit={t('yard.labour')} />}
      data-testid={`hull-${hull.class}`}
    />
  )
  // The sheet reads the hull as the yard serves it NOW (a STORE or a MAKE moves `have`), not as it was when pressed.
  const hull = open ? (view.hulls.find((h) => h.class === open.class) ?? open) : null
  const short = hull ? shortfall(hull) : null
  const plan = hull ? yardPlan(hull, sources.view ?? undefined, fleet ? fleetCargoByCode(fleet) : {}) : null
  const room = levels.view?.company ? levels.view.room.fleet_ship_max : null
  const full = fleet !== null && room !== null && fleet.ships.length >= room
  const crewShort = fleet ? fleetCrew(fleet).short : 0
  // THE ONE BUTTON: the next thing she can do. A full fleet takes no hull, so nothing is offered but the crew she lacks.
  const step =
    !hull || !plan || !hull.buildable || !fleet
      ? 'wait'
      : crewShort > 0 && (full || laid)
        ? 'hire'
        : full
          ? 'full'
          : plan.step
  const ready = step === 'build'
  // S3 — PLAN TRIP: the harbours that sell what is still short, nearest first, then back to this quay (the goods count
  // once stored HERE). Handed to the Map's route builder as a draft: nothing is sent, and the server judges each leg there.
  const trip = hull && plan && hull.buildable && fleet?.port && step === 'wait' ? planStops(plan) : []
  const planTrip = () => {
    if (!fleet?.port || trip.length === 0) return
    useRouteSeed.getState().plan(fleet.id, [...trip, fleet.port])
    const { openMap } = useGoTo.getState()
    if (openMap) openMap()
    else navigate('/map')
  }

  // 0465: the order at this yard is ready once its time has passed (the read's `ready`, or the clock since)
  const openOrder = order?.open ?? null
  const orderReady = openOrder !== null && (openOrder.ready || clock >= Date.parse(openOrder.ready_at))
  const untilReady = (at: string) => t('yard.readyIn', { t: formatRealShort(Math.max(0, Date.parse(at) - clock)) })
  const offerOrder = hull !== null && order?.on === true && openOrder === null && hull.buildable
  const quoted = quote.view?.on ? quote.view : null
  const orderPrice = quoted && typeof quoted.price === 'number' ? quoted.price : null
  const orderShort = orderPrice !== null && purse !== null && purse < orderPrice ? orderPrice - purse : 0
  // THE PRIMARY BUTTON IS THE ONE SHE CAN DO (2026-11-23 play-test, finding 5): while materials are missing the Build button cannot be
  // pressed, so the Order is the gold one and Build the plain one; once the materials are in, Build is gold again.
  const orderFirst = offerOrder && step === 'wait'

  return (
    <div data-testid="port-yard">
      <WrecksLine />
      {launched && (
        <Note tone="accent" data-testid="yard-launched" className="mb-3">
          {t('yard.launched', { name: launched })}
        </Note>
      )}
      {openOrder && (
        <div className="mb-3" data-testid="yard-order-open" data-ready={orderReady} data-class={openOrder.class}>
          <Row
            label={`${t('yard.onOrder')} · ${hullName(openOrder.name)}`}
            value={<Figure value={orderReady ? t('yard.readyNow') : untilReady(openOrder.ready_at)} />}
            hairline={!orderReady}
            data-testid="yard-order-row"
          />
          {orderReady && fleet && (
            <>
              <Field
                icon={null}
                value={launchName}
                maxLength={24}
                placeholder={t('yard.shipName')}
                onChange={(e) => setLaunchName(e.target.value)}
                aria-label={t('yard.shipName')}
                data-testid="yard-launch-name"
              />
              <Button
                variant="primary"
                className="mt-2 w-full"
                busy={ordering}
                busyLabel={t('yard.launching')}
                disabled={launchName.trim().length < 3}
                onClick={launch}
                data-testid="yard-launch"
              >
                {t('yard.launch')}
              </Button>
            </>
          )}
          {launchRefusal && (
            <Note tone="danger" code={launchRefusal.code} figures={launchRefusal.figures} className="mt-2">
              {launchRefusal.sentence}
            </Note>
          )}
        </div>
      )}
      {order?.elsewhere.map((e) => (
        <Row
          key={e.port}
          label={`${t('yard.onOrder')} · ${hullName(e.name)} · ${properName('port', e.port_name, e.port_name)}`}
          value={<Figure value={e.ready || clock >= Date.parse(e.ready_at) ? t('yard.readyNow') : untilReady(e.ready_at)} />}
          data-testid={`yard-order-elsewhere-${e.port}`}
        />
      ))}
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

      {open && hull && plan && (
        <Tray
          detent={detent}
          onDetentChange={(next) => (next === 'closed' ? setOpen(null) : setDetent(next))}
          title={hullName(hull.name)}
          data-testid="yard-tray"
          action={
            hull.buildable ? (
              <>
                {/* always one line and one button, so a change of the label moves nothing */}
                {/* a refusal stands here, over the buttons, where the press was (it stood below the sheet's fold) */}
                {refusal && (
                  <Note tone="danger" code={refusal.code} figures={refusal.figures} className="mb-2" data-testid="yard-refusal">
                    {refusal.sentence}
                  </Note>
                )}
                <div className="mb-2 text-center text-t-label text-ink-dim" data-testid="yard-ready">
                  {t('yard.ready', { n: formatInt(plan.ready), of: formatInt(plan.of) })}
                </div>
                <Button
                  variant={orderFirst ? 'secondary' : 'primary'}
                  data-variant={orderFirst ? 'secondary' : 'primary'}
                  className="w-full"
                  busy={sending}
                  busyLabel={step === 'build' ? t('yard.building') : undefined}
                  disabled={step === 'wait' || step === 'full' || (step === 'build' && name.trim().length < 3)}
                  onClick={() =>
                    step === 'build' ? build(hull) : step === 'hire' ? toInn() : step === 'make' || step === 'store' ? send(plan.lines) : undefined
                  }
                  data-testid="yard-next"
                  data-step={step}
                >
                  {step === 'make'
                    ? t('yard.makeParts')
                    : step === 'store'
                      ? t('yard.store')
                      : step === 'hire'
                        ? t('yard.hireCrewN', { n: formatInt(crewShort) })
                        : step === 'full'
                          ? t('yard.fleetFull')
                          : t('yard.layDown')}
                </Button>
                {/* 0465: the order, under the one button: the whole price now and a real wait (served only while the yard takes orders) */}
                {offerOrder && (
                  <Button
                    variant={orderFirst ? 'primary' : 'secondary'}
                    data-variant={orderFirst ? 'primary' : 'secondary'}
                    className="mt-2 w-full"
                    busy={ordering}
                    busyLabel={t('yard.ordering')}
                    disabled={orderPrice === null || orderShort > 0 || sending}
                    onClick={() => placeOrder(hull)}
                    data-testid="yard-order"
                    data-price={orderPrice ?? undefined}
                    data-short={orderShort > 0 ? orderShort : undefined}
                  >
                    {orderPrice === null
                      ? t('yard.order')
                      : orderShort > 0
                        ? `${t('yard.orderN', { price: formatDucats(orderPrice) })} · ${t('yard.orderShort', { n: formatInt(orderShort) })}`
                        : t('yard.orderN', { price: formatDucats(orderPrice) })}
                  </Button>
                )}
              </>
            ) : undefined
          }
        >
          {/* her picture across the top of her sheet (slice 10): the hull you are about to lay down */}
          <div className="mb-3" data-testid="yard-hull-picture">
            <ShipPicture code={hull.class} size="hero" />
          </div>
          {/* S1: a full fleet is said FIRST, before she fetches anything */}
          {full && hull.buildable && (
            <Note tone="warning" className="mb-2" data-testid="yard-fleet-full">
              {t('yard.fleetFull')}
            </Note>
          )}
          {/* 0166 (S17): a famous ship carries her history line — the hull's served note, printed as served */}
          {hull.tech === 'F' && (
            <Hint className="mb-2" data-testid="yard-history">
              {hull.note}
            </Hint>
          )}
          {hull.crown && (
            <>
              <Row label={t('yard.type')} value={<HullCrown crown={hull.crown} />} hairline={false} />
              <Hint className="mb-2" data-testid="yard-crown-note">
                {t('yard.crownNote')}
              </Hint>
            </>
          )}
          {hull.line_nation && <Row label={t('yard.country')} value={<HullCountry nation={hull.line_nation} />} />}
          {/* 0366: what she is built to do */}
          {hullJobOf(hull.class) && <Row label={t('codex.hullJob')} value={<HullJob code={hull.class} />} data-testid="yard-job" />}
          <Row label={t('yard.cargo')} value={<Figure value={formatInt(hull.hold)} unit={t('yard.tons')} />} />
          <Row label={t('yard.speed')} value={<Figure value={hull.speed_kn} unit={t('yard.knots')} />} />
          <Row label={t('yard.crewNeeded')} value={<Figure value={formatInt(hull.crew_required)} />} />
          {/* 0366: the five figures the fight reads, from the class's own row (the snapshot's) */}
          <HullFight cls={classes?.find((c) => c.code === hull.class)} />
          {/* 0276 — the blind roll, said before you build: the class figures above are the average,
              and a new hull strays by this much (the rare Poor and Fine beyond). */}
          {hull.variety_pct !== undefined && hull.variety_pct > 0 && (
            <Row
              label={t('yard.variety')}
              value={<Figure value={`±${formatInt(hull.variety_pct)} %`} />}
              data-testid="yard-variety"
            />
          )}
          {/* S1 — THE TOTALS, above the lines so a part unfolding moves neither: what is still to buy at the sellers'
              prices now plus the yard's labour, and the weight of what is still to fetch against her free hold. */}
          {/* ONE PRICE A ROAD (slice 10): Total is the road of building her yourself; the labour in it (the tile's one figure) is its
              small print, so Total still reads as labour + the goods still to buy */}
          <Row
            label={t('yard.total')}
            value={<Figure value={plan.goodsCost === null ? '…' : formatDucats(Math.round(plan.goodsCost) + hull.ducats)} />}
            data-testid="yard-total"
            data-cost={plan.goodsCost === null ? undefined : Math.round(plan.goodsCost) + hull.ducats}
          >
            <span className="block text-t-caption tabular-nums text-ink-faint" data-testid="yard-labour" data-labour={hull.ducats}>
              {`${t('yard.labour')} ${formatDucats(hull.ducats)}`}
            </span>
          </Row>
          <Row
            label={t('yard.weight')}
            value={
              <Figure
                value={plan.weight === null ? '…' : formatTons(plan.weight, 1)}
                unit={plan.weight === null || !fleet ? undefined : plan.weight <= fleet.free_hold ? t('yard.fits') : t('yard.tooHeavy')}
                tone={plan.weight !== null && fleet && plan.weight > fleet.free_hold ? 'warning' : 'ink'}
              />
            }
            data-testid="yard-weight"
            data-fits={plan.weight === null || !fleet ? undefined : plan.weight <= fleet.free_hold}
          />
          {/* 0465: an order's wait, beside the totals; the order's price is its press, under the one button */}
          {offerOrder && (
            <Row
              label={t('yard.wait')}
              value={<Figure value={quoted && typeof quoted.minutes === 'number' ? formatRealShort(quoted.minutes * 60_000) : '…'} />}
              data-testid="yard-order-wait"
            >
              {/* an order's fee (world.hull_quote): what the order adds over labour and every good bought at the nearest ask, the
                  Order's small print. 0472: on her second hull the fee is raised to the floor (served `first`, absent dark), and it says
                  "First-ship fee" so the price says why */}
              {quoted && typeof quoted.fee === 'number' ? (
                quoted.first === true ? (
                  <span className="block text-t-caption tabular-nums text-ink-faint" data-testid="yard-order-first" data-fee={quoted.fee}>
                    {`${t('yard.firstOrder')} ${formatDucats(quoted.fee)}`}
                  </span>
                ) : (
                  <span className="block text-t-caption tabular-nums text-ink-faint" data-testid="yard-order-fee" data-fee={quoted.fee}>
                    {`${t('yard.orderFee')} ${formatDucats(quoted.fee)}`}
                  </span>
                )
              ) : null}
            </Row>
          )}
          {/* S3: one press from the totals to the trip that fetches what is short. It stands above the lines, with the
              totals, so a part unfolding does not move it; it goes when nothing is left to fetch by sea. */}
          {trip.length > 0 && (
            <Row
              label={t('yard.planTrip')}
              value={<Figure value={formatInt(trip.length)} unit={t('yard.stops')} />}
              chevron
              onClick={planTrip}
              data-testid="yard-plan-trip"
              data-stops={trip.join(' ')}
            />
          )}
          {plan.goods.length > 0 && <GroupHeading className="mt-3">{t('yard.materials')}</GroupHeading>}
          {plan.goods.map((g) => (
            <GoodLine
              key={g.code}
              good={g}
              label={properName('good', g.code, g.name)}
              speed={fleet?.speed_kn ?? null}
              id={g.code}
            />
          ))}
          {plan.parts.length > 0 && <GroupHeading className="mt-3">{t('yard.parts')}</GroupHeading>}
          {plan.parts.map((p) => (
            <PartLine
              key={p.code}
              part={p}
              label={p.name}
              speed={fleet?.speed_kn ?? null}
              open={unfolded.has(p.code)}
              onToggle={() =>
                setUnfolded((was) => {
                  const next = new Set(was)
                  if (!next.delete(p.code)) next.add(p.code)
                  return next
                })
              }
            />
          ))}
          {hull.goods.some((m) => m.have < m.qty) && (
            <Hint className="mb-2" data-testid="yard-store-hint">
              {t('yard.storeHint')}
            </Hint>
          )}

          {hull.wrong_yard && (
            <Note tone="warning" data-testid="yard-country">
              {hull.wrong_yard}
            </Note>
          )}
          {hull.needs && (
            <Note tone="warning" data-testid="yard-needs">
              {hull.needs}
            </Note>
          )}
          {hull.unmade && (
            <Note tone="warning" data-testid="yard-unmade">
              {hull.unmade}
            </Note>
          )}
          {hull.famous_held && (
            <Note tone="warning" data-testid="yard-famous-held">
              {hull.famous_held}
            </Note>
          )}
          {hull.tier_ok === false && (
            <Note tone="warning">
              {t('yard.yardTier', { have: formatInt(tier), need: formatInt(hull.yard_tier) })}
            </Note>
          )}
          {hull.buildable && short !== null && (
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
          {refusal && !hull.buildable && (
            <Note tone="danger" code={refusal.code} figures={refusal.figures}>
              {refusal.sentence}
            </Note>
          )}
        </Tray>
      )}
    </div>
  )
}

/** One good's line: what the recipe wants, what is in storage here and what is on board for it — and, while she is
 *  short of it, where it is sold nearest (0349) with the miles, the real time and the cost (0358), as a press. */
function GoodLine({
  good,
  label,
  speed,
  id,
  part,
}: {
  good: PlanGood
  label: string
  /** The fleet's speed in knots, for the real time to the seller; null with no fleet here. */
  speed: number | null
  id: string
  /** Set for a part's input: it is made from the hold, so storage is not printed. */
  part?: string
}) {
  const source = good.short > 0 ? good.source : undefined
  const testid = part ? `yard-input-${part}-${id}` : `yard-good-${id}`
  const category = useWorld((s) => s.goodByCode[good.code]?.category ?? '')
  // the bar: what counts toward her need. A hull's good counts once STORED here, so storage is the fill and what is on board the
  // wash it would add (Bar's `pending`); a part's input is made from the hold, so what is on board is the fill.
  const have = part ? good.aboard : good.stored
  const of = Math.max(1, good.need)
  return (
    <div className={part ? 'pl-4' : undefined}>
      <Row
        mark={<Icon name={goodIcon(good.code, category)} size={20} className={good.short > 0 ? 'text-ink-muted' : 'text-accent'} />}
        label={<span className={KEEP_WORDS_CLASS}>{label}</span>}
        hairline={!source}
        value={<Figure value={formatInt(good.need)} tone={good.short > 0 ? 'warning' : 'ink'} />}
        data-testid={testid}
        data-short={good.short}
      >
        <Bar
          pct={(have / of) * 100}
          pending={part ? undefined : (Math.min(good.aboard, Math.max(0, good.need - good.stored)) / of) * 100}
          label={label}
          className="mt-1"
        />
        <span className="mt-0.5 block text-t-caption tabular-nums text-ink-faint">
          {part
            ? tNow('yard.onBoard', { n: formatInt(good.aboard) })
            : `${tNow('yard.inStorage', { n: formatInt(good.stored) })} · ${tNow('yard.onBoard', { n: formatInt(good.aboard) })}`}
        </span>
      </Row>
      {source && <SourceRow source={source} kind="good" speed={speed} units={good.short} testid={part ? `yard-input-source-${part}-${id}` : undefined} />}
    </div>
  )
}

/** One part's line: how many she wants and keeps here; where it is made while she lacks it; and, unfolded, the goods it
 *  is made of (0358), each with its own seller. It opens below itself. */
function PartLine({
  part,
  label,
  speed,
  open,
  onToggle,
}: {
  part: PlanPart
  label: string
  speed: number | null
  open: boolean
  onToggle: () => void
}) {
  const short = part.have < part.need
  const folds = part.inputs.length > 0
  return (
    <div>
      <Row
        mark={<Icon name="mallet" size={20} className={short ? 'text-ink-muted' : 'text-accent'} />}
        label={<span className={KEEP_WORDS_CLASS}>{label}</span>}
        hairline={!(short && part.source) && !open}
        chevron={folds && !open}
        onClick={folds ? onToggle : undefined}
        aria-expanded={folds ? open : undefined}
        value={<Figure value={formatInt(part.need)} tone={short ? 'warning' : 'ink'} />}
        data-testid={`yard-part-${part.code}`}
      >
        <Bar pct={(part.have / Math.max(1, part.need)) * 100} label={label} className="mt-1" />
        <span className="mt-0.5 block text-t-caption tabular-nums text-ink-faint">{tNow('yard.inStorage', { n: formatInt(part.have) })}</span>
      </Row>
      {short && part.source && <SourceRow source={part.source} kind="item" speed={speed} />}
      {open && (
        <div data-testid={`yard-inputs-${part.code}`}>
          {part.inputs.map((g) => (
            <GoodLine key={g.code} good={g} label={properName('good', g.code, g.name)} speed={speed} id={g.code} part={part.code} />
          ))}
        </div>
      )}
    </div>
  )
}

/** Where a missing material is had nearest, and the press that goes there by a door that already exists. */
function SourceRow({
  source,
  kind,
  speed,
  units,
  testid,
}: {
  source: YardSource | YardInput
  kind: 'good' | 'item'
  /** The fleet's speed in knots: the real time to the seller is the miles at that speed (a calm estimate). */
  speed: number | null
  /** How many are still to buy there: the cost is that many at the seller's price now (0358). */
  units?: number
  testid?: string
}) {
  const t = useT()
  const navigate = useNavigate()
  const openOnDesk = useDeskGood((s) => s.open)
  if (source.port === null || source.name === null) {
    return <Row label={t('yard.nowhere')} data-testid={testid ?? `yard-source-${source.code}`} />
  }
  const here = source.miles === 0
  const port = source.port
  // the seller's name in her language (the one map of port names); `data-seller` keeps the served one
  const seller = properName('port', source.name, source.name)
  const go = () => {
    if (kind === 'good') {
      // the map's own hand-over (live/PriceTray.tsx "Open in Command"): the Trade desk reads this city, this good in hand
      openOnDesk(source.code, port)
      navigate('/command')
    } else if (here) {
      // a fitting is made at this city's Workshop, on the Office tab's City face
      navigate(openOfficeCity('workstation'))
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
        : t('yard.buyAt', { name: seller })
      : here
        ? t('yard.makeHere')
        : t('yard.makeAt', { name: seller })
  const ask = 'ask' in source ? source.ask : null
  const figures = [
    here || source.miles === null ? null : formatMiles(source.miles),
    here || source.miles === null || speed === null || speed <= 0 ? null : `~${formatRealShort(voyageDaysToRealMs(source.miles / (speed * 24)))}`,
    typeof ask === 'number' && units !== undefined ? formatDucats(Math.round(ask * units)) : null,
  ].filter((x): x is string => x !== null)
  return (
    <Row
      label={<span className={KEEP_WORDS_CLASS}>{words}</span>}
      chevron
      onClick={go}
      data-testid={testid ?? `yard-source-${source.code}`}
      data-port={port}
      data-seller={source.name}
    >
      {/* the figures stand UNDER the words, on their own line: beside them a seller's name broke inside itself at 320 px */}
      {figures.length > 0 ? <span className="whitespace-nowrap tabular-nums text-ink-dim">{figures.join(' · ')}</span> : null}
    </Row>
  )
}
