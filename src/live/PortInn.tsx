import { useMemo, useState, type ReactNode } from 'react'
import { GoToLink } from '../chart'
import {
  Bar,
  Button,
  Figure,
  Hint,
  Icon,
  Note,
  Row,
  Stepper,
  Tile,
  TileField,
  Tray,
  type TrayDetent,
  type TrayMode,
} from '../components/ui'
import { OrderCheck } from './orderCheck'
import { StepQuestion } from './StepQuestion'
import { useShellState } from '../app/shellState'
import { useStepOrder, type StepVerb } from './useStepOrder'
import { fleetCrew } from '../domain/fleet'
import { useCrewCost } from './useCrewCost'
import { useInn } from './useInn'
import { useWorld } from './worldStore'
import { cmdHireOfficer } from '../lib/rpc'
import {
  formatDucats,
  formatInt,
  formatOfTotal,
  formatRealDuration,
  formatVoyageDays,
  instantMs,
} from '../lib/format'
import type { FleetView, InnGuest, Refusal, SnapshotPort } from '../lib/rpc'

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
// might help. So the room says outright when it turns over, in ONE line.
//
// ── THE ROOM TURNS EVERY QUARTER HOUR (0119, owner 2026-10-15) ─────────────────────────────────
// *"captains should be randomly distributed and change locations every few time (set real 15min
// for now)"*. The key is no longer the game day but `world.inn_shift()` — 15 real minutes, a knob —
// still derived, still the same room for everybody. The read serves `turns_at`; the head line
// counts down to it on the shell's one clock, and the world's beat re-asks the room after it.
//
// ── HIRING AN OFFICER IS A DIRECT CALL, NOT AN ORDER ───────────────────────────────────────────
// `cmd.hire_officer` is not one of the verbs and never has been (0015): signing somebody is not
// something a fleet does at sea, it is something you do standing in a room. So this screen calls
// it and then asks the world to re-read, rather than composing a line.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

// ── A CAPTAIN IS HER CARD (0156, K4) ───────────────────────────────────────────────────────────
// Grade, job, the traits she knows and what each does, and the languages she speaks are the
// server's — world.captain_card, composed onto every guest by world.inn. This screen prints them and
// writes no word of its own about what a job does (the client's old SPECIALTY_DOES table is gone).

/** The tile's line: `S · Navigator`. A server before 0156 sends no card, and the job code is all
 *  there is to say. */
function guestMeta(guest: InnGuest): string {
  return guest.grade && guest.job_word ? `${guest.grade} · ${guest.job_word}` : guest.specialty.toLowerCase()
}

/** Her nation and home port — the port a go-to link when the world names it (the inn serves the
 *  port's NAME, 0073, so it is found by name in the snapshot). */
function whereFrom(guest: InnGuest, ports: readonly SnapshotPort[] | undefined): ReactNode {
  if (!guest.home) return 'Unknown'
  const code = ports?.find((p) => p.name === guest.home)?.code
  const home = code ? <GoToLink to={{ kind: 'port', code }}>{guest.home}</GoToLink> : guest.home
  return guest.nation ? (
    <>
      {guest.nation} · {home}
    </>
  ) : (
    home
  )
}

export function PortInn({
  port,
  fleet,
  alongside,
  trayMode,
}: {
  port: SnapshotPort
  /** The fleet an officer signs with — the acting fleet, wherever it is (`cmd.hire_officer`). */
  fleet: FleetView | null
  /** A fleet of yours docked HERE, or null — crew are hired and let go from the port they are in. */
  alongside: FleetView | null
  /** Where this face's trays stand — PORT's docked default; the MAP's city panel (2026-10-15)
   *  slides them out beside itself (`side-next`). The same face, composed by a second caller. */
  trayMode?: TrayMode
}) {
  return (
    <div data-testid="port-inn">
      {alongside ? (
        <>
          <CrewFace port={port} fleet={alongside} />
          <Supplies port={port} fleet={alongside} trayMode={trayMode} />
        </>
      ) : (
        <>
          <Row
            label="Crew available"
            value={<Figure value={formatInt(port.crew_pool)} unit="people" />}
            tone="muted"
            data-testid="inn-pool"
          />
          {/* WHY NOTHING HERE CAN BE PRESSED — one line, not a dead stepper. */}
          <Row label="Dock a fleet here to hire crew or buy supplies." tone="muted" hairline={false} data-testid="inn-none-docked" />
        </>
      )}
      <Room port={port} fleet={fleet} trayMode={trayMode} />
    </div>
  )
}

/**
 * SUPPLIES, BOUGHT AT THE INN (owner, 2026-10-15: *"inn should be a place where we can hire crew and
 * buy provisions"*). The same act the quay's Trade face offers — `useStepOrder(…, 'PROVISION')`
 * judged by the dry run and sent by the one button in `StepQuestion` — composed here as a second
 * caller, never a second rule: how many days, what it costs and whether it is allowed are the
 * server's, exactly as on the quay.
 */
function Supplies({ port, fleet, trayMode }: { port: SnapshotPort; fleet: FleetView; trayMode?: TrayMode }) {
  const [open, setOpen] = useState(false)
  const step = useStepOrder(fleet, 'PROVISION', open, () => setOpen(false))
  return (
    <>
      <Row
        label="Supplies"
        value={<Figure value={formatVoyageDays(fleet.endurance_days)} />}
        chevron
        onClick={() => setOpen(true)}
        data-testid="inn-supplies"
      />
      {open && <StepQuestion fleet={fleet} port={port} step={step} mode={trayMode} onClose={() => setOpen(false)} />}
    </>
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
          the stepper. 0128: it is owed per day at sea and paid only out of a sale's profit. */}
      {cost.cost !== null ? (
        <Row
          label="Wages"
          value={<Figure value={formatDucats(cost.cost.per_day)} unit="per day at sea, paid from profit" />}
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

/** This quarter hour's room — the read, the faces, and the hiring tray. */
function Room({ port, fleet, trayMode }: { port: SnapshotPort; fleet: FleetView | null; trayMode?: TrayMode }) {
  const { view, loading } = useInn(port.id)
  // THE ONE CLOCK (src/app/shellState.ts) counts down to the served turn (0119 `turns_at`).
  const { nowMs } = useShellState()
  const turnsAt = instantMs(view?.turns_at)
  const [open, setOpen] = useState<InnGuest | null>(null)
  const [detent, setDetent] = useState<TrayDetent>('half')
  const [signing, setSigning] = useState(false)
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  const refresh = useWorld((s) => s.refresh)
  const ports = useWorld((s) => s.snapshot?.ports)

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
      {/* WHEN THE ROOM TURNS OVER (0119: every inn_captain_rotate_minutes REAL minutes). A server
          that has not applied 0119 serves no instant, and the line says only what is true. */}
      <div className="flex items-baseline justify-between pb-2 pt-4" data-testid="inn-room-head">
        <h3 className="text-t-caption uppercase tracking-wider text-ink-faint">Captains here</h3>
        {turnsAt !== null && (
          <span className="text-t-caption tabular-nums text-ink-faint" data-testid="inn-turns">
            {turnsAt > nowMs ? `New faces in ${formatRealDuration(turnsAt - nowMs)}` : 'New faces arriving'}
          </span>
        )}
      </div>

      {view.present.length === 0 ? (
        <Row label="Nobody in the inn right now." tone="muted" hairline={false} data-testid="inn-empty" />
      ) : (
        <TileField>
          {view.present.map((guest) => (
            <Tile
              key={guest.code}
              mark={<Icon name="crew" size={20} />}
              name={guest.name}
              meta={guestMeta(guest)}
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
          mode={trayMode}
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
          {open.grade && open.job_word ? (
            <>
              <Row label="Grade" value={open.grade} data-testid="inn-grade" />
              <Row label="Job" value={`${open.job_word} · ${open.focus_word ?? ''}`} data-testid="inn-job" />
              {(open.traits ?? []).map((t) => (
                <Row
                  key={t.code}
                  label={t.word}
                  value={<Figure value={t.lines.join(' · ')} tone={t.in_use ? 'success' : 'faint'} />}
                  tone={t.in_use ? 'default' : 'muted'}
                  data-testid={`inn-trait-${t.code}`}
                >
                  {t.note && <Hint>{t.note}</Hint>}
                </Row>
              ))}
              {open.speaks && <Row label={open.speaks} tone="muted" data-testid="inn-speaks" />}
            </>
          ) : (
            <Row label="Job" value={open.specialty.toLowerCase()} />
          )}
          <Row label="From" value={whereFrom(open, ports)} hairline={!open.signed} />
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
