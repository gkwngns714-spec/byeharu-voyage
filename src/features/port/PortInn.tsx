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
import { useInn } from '../../live/useInn'
import { useWorld } from '../../live/worldStore'
import { cmdHireOfficer } from '../../lib/rpc'
import { formatDucats, formatInt } from '../../lib/format'
import type { FleetView, InnGuest, Refusal } from '../../lib/rpc'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE INN — who is drinking here today (0073), as a field of faces.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner: *"i want a buliding called Inn, where you can hire crew, and also captains"*, and
// *"captains should also have country of origin, and should be randomly appear in inn (not 100%,
// S tear especially) on their country land, or related fields."*
//
// ── THE ONE THING THIS SCREEN MUST NOT OFFER ───────────────────────────────────────────────────
// A refresh. Who is in the room is derived from (officer, port, day, world secret): the same quay
// on the same day shows the same faces to everybody, for ever. A button that re-read it would be
// honest — it would change nothing — but it would TEACH the player that re-reading might help. So
// the room says outright that it is today's room, in ONE line, and that is the whole of the
// three-paragraph preamble §6 cut.
//
// ── HIRING IS A DIRECT CALL, NOT AN ORDER ──────────────────────────────────────────────────────
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

export function PortInn({ portId, fleet }: { portId: string; fleet: FleetView | null }) {
  const { view, loading } = useInn(portId)
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

  if (loading && !view) return <Note tone="neutral">Seeing who is in tonight…</Note>
  if (!view || !view.has_inn) return <Note tone="neutral">This city keeps no inn.</Note>

  return (
    <div data-testid="port-inn">
      <Note tone="neutral" className="mb-3">
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
    </div>
  )
}
