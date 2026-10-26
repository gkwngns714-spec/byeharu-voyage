import { useMemo, useState } from 'react'
import { SmallChart } from '../../../chart'
import { Figure, Hint, Note, Row } from '../../../components/ui'
import { fleetCrew } from '../../../domain/fleet'
import { useSeaConditions } from '../../../live/useSeaConditions'
import { portNameOf, useWorld } from '../../../live/worldStore'
import { formatInt, formatVoyageDays } from '../../../lib/format'
import type { BoardBuyRow, BoardSellRow, FleetView, GoodBoard } from '../../../lib/rpc'
import { useT } from '../../../lib/i18n'
import type { PlanDraft } from './planDraft'
import { daysAt, planLines, reachBoard, reachWords, seaAsksWords } from './planLines'

// THE PLAN'S VOYAGE — the owner, 2026-10-20 (docs/OWNER_REQUESTS.md row 183):
//
//     "In command, when I press plan this trade, it should switch to plan tab and make planning there. It
//      should show map (without npcs or name of the cities that aren't associated with the route/plan, and
//      show how long, provision needed for the current crew, how many crews needed, etc... It should show
//      restrictions – if whether my level, my class, my ship can go to that location."
//
// Four parts, under the trade card, on the Trade face:
//
//   THE CHART — `SmallChart`, the same chart the Map tab draws with, handed ONLY the plan's cities (where the
//   fleet is, the ports on the way, the buy city, the sell city) and only this fleet (no merchants), with the
//   plan's courses dashed: the courses `planLines` proposes, the same `path` the queued SAIL lines carry.
//
//   THE VOYAGE — days at sea as the board serves them (to the buy city, then on to the sell city) and the crew
//   against the ships' minimum (`fleetCrew`, row 179's model: `ship_classes.crew_required`, below which SAIL
//   refuses E_CREW_SHORT). The supplies are not worked out here any more (0225): the trade card prints the
//   board's own `supplies` for the chosen row — public.supply_need's reading, the rule cmd.do_sail buys by.
//
//   CAN YOU GO THERE — the ONE authority, read and printed, never re-judged here:
//     · the reach (0188): the board's `sailable` / `needs` per city, in `reachWords`, THE wording;
//     · the sea conditions (0215 / 0216): the served title, the fleet's served wave resistance, its ship
//       classes, and whether the conditions bite. Dark, they are a reading only — exactly what the server's
//       gate answers then (`public.sea_gate` is null while `sea_conditions_bite` is off). Lit, the server
//       refuses a plan into a closed sea at `cmd.issue_lines` and its sentence is printed by the builder.
//     · what the seas on the way ask, per city (0218): the board row's `sea` — the most its route's legs ask
//       and the one rule's verdict (`public.sea_refusal`), served dark too. Printed in `seaAsksWords`, THE
//       wording; dark, a refusal reads "not in force yet"; lit, a city the sea closes is the reach note's
//       reason (`reachWords`), printed once. Nothing is compared here.
//
//   THE LEGS — each SAIL of the plan, from → to, with its days at sea at the fleet's speed. Last, so a
//   change in how many legs there are moves nothing above it.
//
// A PRESS SELECTS: every row above the legs is always drawn (a dash while a figure is unknown), and the chart
// has a fixed shape, so choosing another city changes figures in place and moves nothing.

export function PlanVoyage({
  fleet,
  plan,
  board,
  buyRow,
  sellRow,
}: {
  fleet: FleetView
  plan: PlanDraft
  board: GoodBoard | null
  buyRow: BoardBuyRow | null
  sellRow: BoardSellRow | null
}) {
  const t = useT()
  const seaNav = useWorld((s) => s.seaNav)
  const portByCode = useWorld((s) => s.portByCode)
  const snapshot = useWorld((s) => s.snapshot)
  const sea = useSeaConditions()
  const name = (code: string) => portNameOf(portByCode, code)

  // THE FLEET THE COURSES ARE PROPOSED FROM, held while nothing about where it starts has changed: the world is
  // re-read every 3 s and every read is a new object, and proposing a course is the pathfinder's work. A new
  // version (a trade, an arrival, an order) or status hands the new one over (derive-from-the-last-render).
  const fleetKey = `${fleet.id}:${fleet.version}:${fleet.status}:${fleet.port ?? ''}`
  const [held, setHeld] = useState({ key: fleetKey, fleet })
  if (held.key !== fleetKey) setHeld({ key: fleetKey, fleet })

  const toBuyKey = (buyRow?.stops ?? []).join(' ')
  const toSellKey = (sellRow?.stops ?? []).join(' ')
  const legs = useMemo(() => {
    if (!seaNav || !plan.sellAt) return []
    const text = planLines(plan, held.fleet, seaNav, portByCode, {
      toBuy: toBuyKey ? toBuyKey.split(' ') : [],
      toSell: toSellKey ? toSellKey.split(' ') : [],
    })
    return text.ok ? text.legs : []
  }, [seaNav, plan, held.fleet, portByCode, toBuyKey, toSellKey])

  const courses = useMemo(() => legs.map((l) => l.path.map(([lat, lon]) => ({ lat, lon }))), [legs])
  const docked = fleet.status === 'DOCKED' ? fleet.port : null
  const onlyKey = [docked, ...legs.map((l) => l.to), plan.buyAt, plan.sellAt]
    .filter((c): c is string => c !== null)
    .filter((c, i, all) => all.indexOf(c) === i)
    .join(' ')
  const only = useMemo(() => (onlyKey ? onlyKey.split(' ') : []), [onlyKey])
  const endsKey = [plan.buyAt, plan.sellAt].filter((c): c is string => c !== null).join(' ')
  const considering = useMemo(() => (endsKey ? endsKey.split(' ') : []), [endsKey])

  const crew = fleetCrew(fleet)

  // CAN YOU GO THERE — the reach, per city the plan sails to (the board's verdict, in THE wording).
  const reachRows = [plan.buyAt && buyRow && !buyRow.here ? buyRow : null, sellRow].filter(
    (r): r is BoardBuyRow | BoardSellRow => r !== null,
  )
  const s = sea.view
  const seaBite = board ? reachBoard(board).seaBite : (s?.bite ?? false)
  const wave = s?.fleets.find((f) => f.id === fleet.id)?.wave ?? fleet.wave ?? null
  const classes = [...new Set(fleet.ships.map((sh) => sh.class))].join(', ')

  return (
    <div className="mt-4" data-testid="plan-voyage">
      <SmallChart
        ports={snapshot?.ports ?? []}
        fleets={[fleet]}
        considering={considering}
        highlight={null}
        only={only}
        legs={courses}
        wholeWorld
        ariaLabel={t('desk.planChart')}
        className="aspect-[3/2] w-full"
      />
      <span className="sr-only" data-testid="plan-chart-cities">
        {only.join(' ')}
      </span>

      <span className="mt-4 block text-t-caption text-ink-faint">{t('desk.crewNow')}</span>
      <Row label={t('desk.crewNow')} value={<Figure value={t('desk.crewOf', { n: formatInt(crew.aboard), max: formatInt(crew.max) })} />} />
      <Row
        label={t('desk.crewMin')}
        value={<Figure value={formatInt(crew.required)} tone={crew.short > 0 ? 'warning' : 'ink'} />}
        hairline={false}
        data-testid="plan-crew-min"
      />
      <Hint>{crew.short > 0 ? t('desk.crewShort', { n: crew.short }) : t('desk.crewOk')}</Hint>

      <section className="mt-4" data-testid="plan-restrictions">
        <span className="block text-t-caption text-ink-faint">{t('desk.restrictions')}</span>
        <Row
          label={t('desk.yourTitle')}
          value={
            <Figure
              value={s?.title ? (s.title.name ? t('desk.titleOf', { level: s.title.level, name: s.title.name }) : String(s.title.level)) : '—'}
            />
          }
        />
        <Row label={t('desk.yourShips')} value={<Figure value={classes || '—'} />} />
        <Row
          label={t('desk.waveResistance')}
          value={<Figure value={wave !== null ? formatInt(wave) : '—'} />}
          hairline={false}
          data-testid="plan-wave"
        />
        <Hint data-testid="plan-sea-state">
          {s ? (s.bite ? t('desk.seaLit') : t('desk.seaDark')) : sea.loading ? '' : t('desk.seaUnread')}
        </Hint>
        {reachRows.map((r) => {
          // 0218: the seas on the way, per city — unless lit and closing it: then the reach note below says so
          if (!r.sea || (seaBite && r.sea.refusal && r.sailable === false)) return null
          const verdict = r.sea.refusal ? (seaBite ? null : t('desk.seaNotYet')) : t('desk.seaEnough')
          return (
            <Hint key={`sea:${r.port}`} data-testid="plan-sea-ask">
              {`${name(r.port)} — ${seaAsksWords(r.sea)}${verdict ? `: ${verdict}` : ''}.`}
            </Hint>
          )
        })}
        {board &&
          reachRows.map((r) =>
            r.sailable === false ? (
              <Note key={r.port} tone="danger" className="mt-2" data-testid="plan-unreachable">
                {`${name(r.port)} — ${reachWords(r, reachBoard(board))}.`}
              </Note>
            ) : (
              <Hint key={r.port} data-testid="plan-reach">
                {t('desk.reachOk', { port: name(r.port) })}
              </Hint>
            ),
          )}
      </section>

      {legs.length > 0 && (
        <section className="mt-4" data-testid="plan-legs">
          <span className="block text-t-caption text-ink-faint">{t('desk.legs')}</span>
          {legs.map((l, i) => (
            <Row
              key={`${i}:${l.to}`}
              label={t('desk.legLine', { from: l.from ? name(l.from) : t('desk.atSea'), to: name(l.to) })}
              value={<Figure value={fleet.speed_kn > 0 ? formatVoyageDays(daysAt(l.nm, fleet.speed_kn)) : '—'} />}
              hairline={i < legs.length - 1}
              data-testid="plan-leg"
            />
          ))}
        </section>
      )}
    </div>
  )
}
