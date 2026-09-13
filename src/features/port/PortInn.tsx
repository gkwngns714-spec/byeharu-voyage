import { useState } from 'react'
import {
  Button,
  Figure,
  Icon,
  Note,
  Row,
  Tile,
  TileField,
  Tray,
  type TrayDetent,
} from '../../components/ui'
import { StepQuestion } from './StepQuestion'
import { useStepOrder } from './useStepOrder'
import { useInn } from '../../live/useInn'
import { useWorld } from '../../live/worldStore'
import { cmdHireOfficer } from '../../lib/rpc'
import { formatDucats, formatInt } from '../../lib/format'
import type { FleetView, InnGuest, Refusal, SnapshotPort } from '../../lib/rpc'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE INN — crew for hire, and who is drinking here today (0073), as a row and a field of faces.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner: *"i want a buliding called Inn, where you can hire crew, and also captains"*, and
// *"captains should also have country of origin, and should be randomly appear in inn (not 100%,
// S tear especially) on their country land, or related fields."*
//
// ── CREW FIRST (2026-09-09) ───────────────────────────────────────────────────────────────────
// Row 60 named the Inn as where crew are hired, and 0067's own line for it reads "Hire crew, and
// meet the captains". Until this slice the HIRE verb's only doorway was a tile on COMMAND's grid;
// the owner: *"they should be located accordingly at different locations."* So the idle men are
// the first row of this face — a fact about the inn a player reads even from a distant quay — and
// pressing it, with a fleet alongside, opens the same step tray (StepQuestion.tsx) that COMMAND
// used to open: her crew, the idle men, the count, the server's price for the day.
//
// THE CREW ROW STANDS OUTSIDE THE ROOM'S READ, on purpose. The room re-reads on every world read
// (`useInn` rides `readAt` through useServedRead.ts), and a dry run of HIRE ends in exactly such
// a read (`cmd.preview` refreshes the world). The room used to blank to a waiting line on every
// re-read — a crew row mounted INSIDE it unmounted its own tray the moment the server priced it,
// which is what the first screenshot of this face showed: the tray gone, the counts unchanged.
// useServedRead now keeps the last room on screen while it re-asks, but the men idle on the quay
// are still not a fact ABOUT the room, so the row keeps its own place above it.
//
// ── THE ONE THING THIS SCREEN MUST NOT OFFER ───────────────────────────────────────────────────
// A refresh. Who is in the room is derived from (officer, port, day, world secret): the same quay
// on the same day shows the same faces to everybody, for ever. A button that re-read it would be
// honest — it would change nothing — but it would TEACH the player that re-reading might help. So
// the room says outright that it is today's room, in ONE line, and that is the whole of the
// three-paragraph preamble §6 cut.
//
// ── HIRING AN OFFICER IS A DIRECT CALL, NOT AN ORDER ───────────────────────────────────────────
// `cmd.hire_officer` is not one of the twelve verbs and never has been (0015): signing somebody is
// not something a fleet does at sea, it is something a house does standing in a room. So this
// screen calls it and then asks the world to re-read, rather than composing a line.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const SPECIALTY_DOES: Record<string, string> = {
  NAVIGATOR: 'shortens a passage',
  QUARTERMASTER: 'finds room in a full hold',
  SURGEON: 'keeps the crew on their feet',
  PURSER: 'shaves the spread on every trade',
}

function whereFrom(guest: InnGuest): string {
  if (guest.nation && guest.home) return `${guest.nation} · ${guest.home}`
  if (guest.home) return `${guest.home}, and no crown`
  return 'nowhere anyone can name'
}

export function PortInn({
  port,
  fleet,
  alongside,
}: {
  port: SnapshotPort
  /** The fleet an officer signs with — the acting fleet, wherever she lies (`cmd.hire_officer`). */
  fleet: FleetView | null
  /** A fleet of yours lying HERE, or null — crew sign on from the quay they are standing on. */
  alongside: FleetView | null
}) {
  return (
    <div data-testid="port-inn">
      {alongside ? (
        <CrewRow port={port} fleet={alongside} />
      ) : (
        <Row
          label="Crew for hire"
          value={<Figure value={formatInt(port.crew_pool)} unit="idle" />}
          tone="muted"
          data-testid="inn-crew"
        />
      )}
      <Room port={port} fleet={fleet} />
    </div>
  )
}

/** The idle men, and the press that signs some on — the HIRE verb's one doorway. Split so the
 *  hook never runs for a room with nobody of yours alongside. */
function CrewRow({ port, fleet }: { port: SnapshotPort; fleet: FleetView }) {
  const [open, setOpen] = useState(false)
  const step = useStepOrder(fleet, 'HIRE', open, () => setOpen(false))
  return (
    <>
      <Row
        label="Crew for hire"
        value={<Figure value={formatInt(port.crew_pool)} unit="idle" />}
        chevron
        onClick={() => setOpen(true)}
        data-testid="inn-crew"
      />
      {open && (
        <StepQuestion
          fleet={fleet}
          port={port}
          step={step}
          onClose={() => {
            setOpen(false)
            step.reset()
          }}
        />
      )}
    </>
  )
}

/** Tonight's room — the read, the faces, and the signing tray. */
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
        // Re-read the world, not the inn: signing her changes the house's books, and the room
        // itself cannot change — which is the whole design.
        await refresh()
      } else {
        setRefusal(r.refusal)
      }
    })()
  }

  if (loading && !view) return <Note tone="neutral" className="mt-3">Seeing who is in tonight…</Note>
  if (!view || !view.has_inn) return <Note tone="neutral" className="mt-3">This city keeps no inn.</Note>

  return (
    <>
      <Note tone="neutral" className="my-3">
        Tonight&apos;s room. Come back tomorrow and it is a different one.
      </Note>

      {view.present.length === 0 ? (
        <Row
          label="Nobody worth hiring is in tonight. Try a quay closer to the sort of officer you want."
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
              figure={<Figure value={formatDucats(guest.wage)} unit="a voyage" />}
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
                busyLabel="Signing…"
                onClick={() => sign(open)}
                data-testid={`sign-${open.code}`}
              >
                {`Sign ${open.name.split(' ')[0]} for ${formatDucats(open.wage)}`}
              </Button>
            )
          }
        >
          <Row
            label="Rates as"
            value={`${open.specialty.toLowerCase()} · ${SPECIALTY_DOES[open.specialty] ?? ''}`}
          />
          <Row
            label="Worth to a fleet"
            value={<Figure value={`+${formatInt(open.bonus_pct)}%`} tone="success" />}
          />
          <Row label="Out of" value={whereFrom(open)} hairline={!open.signed} />
          {open.signed && <Row label="Already in your service." tone="muted" hairline={false} />}
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
