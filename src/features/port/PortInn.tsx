import { useMemo, useState } from 'react'
import {
  Bar,
  Button,
  Figure,
  Icon,
  Note,
  Row,
  Stepper,
  Tile,
  TileField,
  Tray,
  type TrayDetent,
} from '../../components/ui'
import { OrderCheck } from './orderCheck'
import { useStepOrder, type StepVerb } from './useStepOrder'
import { fleetCrew } from '../../domain/fleet'
import { useCrewCost } from '../../live/useCrewCost'
import { useInn } from '../../live/useInn'
import { useWorld } from '../../live/worldStore'
import { cmdHireOfficer } from '../../lib/rpc'
import { formatDucats, formatInt, formatOfTotal } from '../../lib/format'
import type { FleetView, InnGuest, Refusal, SnapshotPort } from '../../lib/rpc'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE INN — the crew, hired and let go from one stepper, and who is drinking here today (0073).
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner: *"i want a buliding called Inn, where you can hire crew, and also captains"*, and
// (row 85, 2026-09-13): *"inn, it should be like trade, where you can hire, dismiss crews, and by
// doing so show how much it will consume everyday"*.
//
// ── LIKE TRADE (2026-09-13, migration 0086) ────────────────────────────────────────────────────
// The Trade face is a figure, a stepper and ONE button whose word follows the direction. This
// face is the same shape for the crew: `Crew 12 / 20`, with the bar; the stepper sets how many
// crew the ship should have, from the complement it needs to sail (`crew_required`) to the crew
// slots it has (`crew_max`); the direction the stepper moved from what is aboard names the verb
// — up is `HIRE n`, down is `DISMISS n` — and the one button says which. Until this slice the
// Inn opened a tray with a `Hire N` stepper (StepQuestion.tsx) and there was no way to let crew
// go at all; the tray is gone from here and StepQuestion keeps REPAIR and PROVISION.
//
// ── EVERY FIGURE IS SERVED ─────────────────────────────────────────────────────────────────────
//   * what the chosen crew will cost per day at sea — `world.crew_cost(fleet, n)`, which is
//     `public.crew_wages`, the sum `voyage.settle` charges on every voyage-day (0086). Read
//     through `useCrewCost` as the stepper moves; nothing here multiplies a rate by a count.
//   * what hiring costs today — `cmd.preview` of the exact `HIRE n` line the button sends,
//     through `useStepOrder`, exactly as the tray did; the dry run runs the real verb and rolls
//     it back, so the price printed is the price charged (F.5).
//   * what may be let go — the server's: `DISMISS` below `crew_required` is refused
//     E_CREW_REQUIRED with the two figures, and the dry run says so before the press.
//
// ── ONE HOOK, TWO VERBS ────────────────────────────────────────────────────────────────────────
// HIRE and DISMISS share their one argument, `count`, so ONE `useStepOrder` is run with whichever
// verb the direction names; the same count composes either line. A second hook per verb would be
// a second `checked`/`issuing` pair for one act (useStepOrder.ts's own "wrong shape").
//
// ── THE ONE THING THIS SCREEN MUST NOT OFFER ───────────────────────────────────────────────────
// A refresh of the room. Who is in it is derived from (officer, port, day, world secret): the
// same port on the same day shows the same faces to everybody, for ever. A button that re-read it
// would be honest — it would change nothing — but it would TEACH the player that re-reading
// might help. So the room says outright that it is today's room, in ONE line.
//
// ── HIRING AN OFFICER IS A DIRECT CALL, NOT AN ORDER ───────────────────────────────────────────
// `cmd.hire_officer` is not one of the verbs and never has been (0015): signing somebody is not
// something a fleet does at sea, it is something you do standing in a room. So this screen calls
// it and then asks the world to re-read, rather than composing a line.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const SPECIALTY_DOES: Record<string, string> = {
  NAVIGATOR: 'faster voyages',
  QUARTERMASTER: 'more cargo space',
  SURGEON: 'healthier crew',
  PURSER: 'better prices on every trade',
}

function whereFrom(guest: InnGuest): string {
  if (guest.nation && guest.home) return `${guest.nation} · ${guest.home}`
  if (guest.home) return guest.home
  return 'Unknown'
}

export function PortInn({
  port,
  fleet,
  alongside,
}: {
  port: SnapshotPort
  /** The fleet an officer signs with — the acting fleet, wherever it is (`cmd.hire_officer`). */
  fleet: FleetView | null
  /** A fleet of yours docked HERE, or null — crew are hired and let go from the port they are in. */
  alongside: FleetView | null
}) {
  return (
    <div data-testid="port-inn">
      {alongside ? (
        <CrewFace port={port} fleet={alongside} />
      ) : (
        <Row
          label="Crew available"
          value={<Figure value={formatInt(port.crew_pool)} unit="people" />}
          tone="muted"
          data-testid="inn-pool"
        />
      )}
      <Room port={port} fleet={fleet} />
    </div>
  )
}

/**
 * THE JUMPS THE OWNER ASKED FOR BY NAME — row 16: *"how many crew to hire, have it + 10, +100, max,
 * make it more friendly"*, and row 29: *"what is max 12 in hire? just max is enough"*, which is why
 * the last chip reads `Max` and not `Max 12`. The figure is already on the rail beside it.
 *
 * A JUMP IS RELATIVE AND THE CEILING IS ABSOLUTE, so `+10` is computed from where the stepper is
 * now and `Max` is not. Jumps that would land at or past the end are dropped rather than shown as
 * three chips that all mean the same thing, and `Stepper` clamps every one of them anyway.
 *
 * WHAT THIS DELIBERATELY DOES NOT DO: row 16 also says MAX must be the smallest of the crew slots
 * free, the port's idle crew, and what the purse can pay. That is a SERVED ceiling — `Stepper`'s
 * `cap`, whose own contract says it "is never recomputed here". No such figure is served for HIRE
 * today, so this passes none and the server's dry run keeps refusing an over-large hire, as it
 * does now. The served ceiling is owed.
 */
function presets(value: number, max: number) {
  if (max <= 0) return undefined
  const jumps = [10, 100].filter((n) => value + n < max).map((n) => ({ label: `+${n}`, value: value + n }))
  return [...jumps, { label: 'Max', value: max }]
}

/** The crew, as Trade draws a good: the figure and its bar, the stepper, the served cost of the
 *  count chosen, the dry run of the line the button sends, and the ONE button. */
function CrewFace({ port, fleet }: { port: SnapshotPort; fleet: FleetView }) {
  const crew = fleetCrew(fleet)
  // THE ASK FOLLOWS THE SHIP. What the stepper asks for is stored WITH the crew it was asked
  // against; when an order lands the world is read back, the crew aboard moves, and an ask made
  // against the old count no longer applies — the stepper stands at what is true again, with no
  // effect writing state behind the render.
  const [ask, setAsk] = useState<{ fleet: string; aboard: number; chosen: number } | null>(null)
  const chosen = ask !== null && ask.fleet === fleet.id && ask.aboard === crew.aboard ? ask.chosen : crew.aboard
  const setChosen = (n: number) => setAsk({ fleet: fleet.id, aboard: crew.aboard, chosen: n })

  const delta = chosen - crew.aboard
  const verb: StepVerb = delta < 0 ? 'DISMISS' : 'HIRE'
  // The count is the SIZE of the move; the direction is the verb. No change, no argument, no dry
  // run — `count` is DERIVED and handed in, never copied into the hook's own state.
  const given = useMemo(() => {
    const out: Record<string, string> = {}
    if (delta !== 0) out.count = String(Math.abs(delta))
    return out
  }, [delta])
  const step = useStepOrder(fleet, verb, delta !== 0, () => {}, given)

  const cost = useCrewCost(fleet.id, chosen)

  const refused = step.check.status === 'refused' || step.check.status === 'checking'
  const label = delta > 0 ? `Hire ${formatInt(delta)}` : delta < 0 ? `Dismiss ${formatInt(-delta)}` : 'No change'
  const range = crew.max > crew.required

  return (
    <div data-testid="inn-crew-face">
      <Row
        label="Crew"
        value={<Figure value={formatOfTotal(crew.aboard, crew.max)} unit="crew" size="figure" />}
        data-testid="inn-crew"
      >
        {/* THE BAR IS THE SHIP'S: what is aboard against the crew slots it has, and the change the
            stepper is asking for washed on — Bar.pending, this repo's one word for "not yet". */}
        <Bar
          pct={crew.max > 0 ? (crew.aboard / crew.max) * 100 : 0}
          pending={crew.max > 0 && delta !== 0 ? (delta / crew.max) * 100 : undefined}
          tone={crew.short > 0 ? 'warning' : 'accent'}
          label={`crew, ${formatOfTotal(chosen, crew.max)}`}
          className="mt-1"
        />
      </Row>
      <Row
        label="Crew available here"
        value={<Figure value={formatInt(port.crew_pool)} unit="people" />}
        data-testid="inn-pool"
      />

      {range ? (
        <div className="py-3">
          <Stepper
            value={chosen}
            onChange={setChosen}
            min={crew.required}
            max={crew.max}
            step={1}
            unit="crew"
            label="crew on board"
            presets={presets(chosen, crew.max)}
            data-testid="inn-crew-stepper"
          />
        </div>
      ) : (
        <Note tone="neutral">These ships have no spare crew slots.</Note>
      )}

      {/* WHAT THE CHOSEN CREW WILL COST, PER DAY AT SEA — the server's one sum (0086), moving with
          the stepper. Wages are charged at sea only; in port the crew cost nothing per day. */}
      {cost.cost !== null ? (
        <Row
          label="Wages"
          value={<Figure value={formatDucats(cost.cost.per_day)} unit="per day at sea" />}
          hairline={false}
          data-testid="inn-crew-cost"
        />
      ) : (
        <Row label={cost.loading ? 'Checking the wages…' : 'Wages unknown'} tone="muted" hairline={false} />
      )}

      {/* THE DRY RUN of the exact line the button sends: what hiring costs today, or the reason. */}
      <OrderCheck check={step.check} timeCompression={step.timeCompression} />

      <div className="pb-3 pt-2">
        <Button
          variant="primary"
          className="w-full"
          disabled={delta === 0 || step.issuing || refused}
          busy={step.issuing}
          busyLabel="Sending…"
          onClick={step.send}
          data-testid="inn-crew-send"
        >
          {label}
        </Button>
      </div>
    </div>
  )
}

/** Today's room — the read, the faces, and the hiring tray. */
function Room({ port, fleet }: { port: SnapshotPort; fleet: FleetView | null }) {
  const { view, loading } = useInn(port.id)
  const [open, setOpen] = useState<InnGuest | null>(null)
  const [detent, setDetent] = useState<TrayDetent>('half')
  const [signing, setSigning] = useState(false)
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  const refresh = useWorld((s) => s.refresh)

  const sign = (guest: InnGuest) => {
    if (signing) return
    setSigning(true)
    setRefusal(null)
    void (async () => {
      const r = await cmdHireOfficer(guest.code, fleet?.id ?? null)
      setSigning(false)
      if (r.ok) {
        setOpen(null)
        // Re-read the world, not the inn: hiring changes your books, and the room itself cannot
        // change — which is the whole design.
        await refresh()
      } else {
        setRefusal(r.refusal)
      }
    })()
  }

  if (loading && !view) return <Note tone="neutral" className="mt-3">Loading…</Note>
  if (!view || !view.has_inn) return <Note tone="neutral" className="mt-3">No inn in this port.</Note>

  return (
    <>
      <Note tone="neutral" className="my-3">
        Officers available today. Tomorrow there will be different ones.
      </Note>

      {view.present.length === 0 ? (
        <Row
          label="No officers available today. Try a port closer to the kind of officer you want."
          tone="muted"
          hairline={false}
        />
      ) : (
        <TileField>
          {view.present.map((guest) => (
            <Tile
              key={guest.code}
              mark={<Icon name="crew" size={20} />}
              name={guest.name}
              meta={guest.specialty.toLowerCase()}
              state={guest.signed ? 'muted' : 'rest'}
              tap="whole"
              onClick={() => {
                setRefusal(null)
                setDetent('half')
                setOpen(guest)
              }}
              figure={<Figure value={formatDucats(guest.wage)} unit="per voyage" />}
              data-testid={`guest-${guest.code}`}
            />
          ))}
        </TileField>
      )}

      {open && (
        <Tray
          detent={detent}
          onDetentChange={(next) => (next === 'closed' ? setOpen(null) : setDetent(next))}
          title={open.name}
          data-testid="inn-tray"
          action={
            open.signed ? undefined : (
              <Button
                variant="primary"
                className="w-full"
                busy={signing}
                busyLabel="Hiring…"
                onClick={() => sign(open)}
                data-testid={`sign-${open.code}`}
              >
                {`Hire ${open.name.split(' ')[0]} for ${formatDucats(open.wage)}`}
              </Button>
            )
          }
        >
          <Row
            label="Role"
            value={`${open.specialty.toLowerCase()} · ${SPECIALTY_DOES[open.specialty] ?? ''}`}
          />
          <Row
            label="Bonus"
            value={<Figure value={`+${formatInt(open.bonus_pct)}%`} tone="success" />}
          />
          <Row label="From" value={whereFrom(open)} hairline={!open.signed} />
          {open.signed && <Row label="Already working for you." tone="muted" hairline={false} />}
          <p className="pt-2 text-t-label text-ink-muted">{open.blurb}</p>
          {refusal && (
            <Note tone="danger" code={refusal.code}>
              {refusal.sentence}
            </Note>
          )}
        </Tray>
      )}
    </>
  )
}
