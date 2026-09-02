import { useState } from 'react'
import { Button, DetailRow, RefusalNote, SectionLabel, fineClass } from '../../components/ui'
import { useInn } from '../../live/useInn'
import { useWorld } from '../../live/worldStore'
import { cmdHireOfficer } from '../../lib/rpc'
import { formatDucats, formatInt } from '../../lib/format'
import type { FleetView, InnGuest, Refusal } from '../../lib/rpc'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE INN — who is drinking here today (0073).
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner: *"i want a buliding called Inn, where you can hire crew, and also captains"*, and
// *"captains should also have country of origin, and should be randomly appear in inn (not 100%,
// S tear especially) on their country land, or related fields."*
//
// ── THE ONE THING THIS SCREEN MUST NOT OFFER ───────────────────────────────────────────────────
// A refresh. Who is in the room is derived from (officer, port, day, world secret): the same quay
// on the same day shows the same faces to everybody, for ever. A button that re-read it would be
// honest — it would change nothing — but it would TEACH the player that re-reading might help, and
// they would sit there pressing it. So the screen says outright that the room is today's, and that
// coming back tomorrow is the only thing that changes it.
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
  const [signing, setSigning] = useState<string | null>(null)
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  const [signed, setSigned] = useState<string | null>(null)
  const refresh = useWorld((s) => s.refresh)

  const sign = (guest: InnGuest) => {
    if (signing) return
    setSigning(guest.code)
    setRefusal(null)
    setSigned(null)
    void (async () => {
      const r = await cmdHireOfficer(guest.code, fleet?.id ?? null)
      setSigning(null)
      if (r.ok) {
        setSigned(guest.name)
        // Re-read the world, not the inn: signing her changes the house's books, and the room
        // itself cannot change — which is the whole design.
        await refresh()
      } else {
        setRefusal(r.refusal)
      }
    })()
  }

  if (loading && !view) return <p className={fineClass()}>Seeing who is in tonight…</p>
  if (!view || !view.has_inn) return <p className={fineClass()}>This city keeps no inn.</p>

  return (
    <div className="space-y-3" data-testid="port-inn">
      <p className={fineClass()}>
        Who is drinking here today. The same room shows the same faces to everybody, and there is
        nothing to refresh — come back tomorrow and it is a different room. People keep to their own
        coast, so look for a captain near her home.
      </p>

      {view.present.length === 0 ? (
        <p className="text-sm text-ink-muted">
          Nobody worth hiring is in tonight. That is the room, not a fault — try again tomorrow, or
          try a quay closer to the sort of officer you want.
        </p>
      ) : (
        view.present.map((guest) => (
          <div key={guest.code} className="border-t border-line pt-2">
            <div className="flex items-baseline justify-between gap-2">
              <SectionLabel>{guest.name}</SectionLabel>
              <span className={fineClass()}>{formatDucats(guest.wage)} a voyage</span>
            </div>
            <p className={fineClass('mt-0.5')}>{guest.blurb}</p>

            <dl className="mt-1 space-y-1">
              <DetailRow
                label="Rates as"
                value={`${guest.specialty.toLowerCase()} · ${SPECIALTY_DOES[guest.specialty] ?? ''} by ${formatInt(guest.bonus_pct)}%`}
              />
              <DetailRow label="Out of" value={whereFrom(guest)} />
            </dl>

            <div className="mt-1.5">
              {guest.signed ? (
                <p className={fineClass()}>Already in your service.</p>
              ) : (
                <Button
                  variant="primary"
                  onClick={() => sign(guest)}
                  disabled={signing !== null}
                  data-testid={`sign-${guest.code}`}
                >
                  {signing === guest.code ? 'Signing…' : `Sign ${guest.name.split(' ')[0]}`}
                </Button>
              )}
            </div>
          </div>
        ))
      )}

      {signed && (
        <p className="font-mono text-xs text-sea" data-testid="port-inn-signed">
          signed: {signed}
        </p>
      )}
      {refusal && <RefusalNote refusal={refusal} />}
    </div>
  )
}
