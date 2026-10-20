import { useState } from 'react'
import { Button, Note } from '../components/ui'
import { cmdSeatCaptain } from '../lib/rpc'
import type { Officer, Refusal, ShipSeats } from '../lib/rpc'
import { useWorld } from './worldStore'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// HER CABINS — who sits where, and (in port) seating them (0157, docs/SKILLS_AND_CAPTAINS.md K5).
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, row 68: *"Each ship will also have cabins that can have captain … 3 captain slot. it will
// grow as the tier of the ship grows"*. Every word and figure here is the server's (`world.ship_seats`,
// served on the ship): the cabin's name, the captain in it, her grade and job, and what her job is worth
// in that cabin (100 % in a cabin of its focus or the Captain's cabin, 50 % elsewhere) — and, while
// those rates do not count yet, the server's own sentence saying so. Nothing is computed here.
//
// SEATING IS THE SERVER'S RULE, PRESSED HERE. `seating` is passed only for one of YOUR ships (a
// merchant's cabins are read-only), and the buttons are drawn only while she is docked — the server
// refuses E_NOT_IN_PORT otherwise, and its refusal is printed if the two ever disagree. An empty cabin
// offers your captains who are not already in it; a seated one offers Ashore. One verb,
// cmd.seat_captain, for both.

export interface Seating {
  shipId: string
  /** Her fleet is docked: captains may change cabins. */
  docked: boolean
  /** The captains you keep (world.officers, `hired`). */
  captains: readonly Officer[]
}

export function ShipCabins({ seats, seating }: { seats: ShipSeats | undefined; seating?: Seating }) {
  const refresh = useWorld((s) => s.refresh)
  const loadOfficers = useWorld((s) => s.loadOfficers)
  const [picking, setPicking] = useState<number | null>(null)
  const [busy, setBusy] = useState(false)
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  if (!seats || seats.list.length === 0) return null
  const canSeat = seating !== undefined && seating.docked

  const seat = (code: string, shipId: string | null, at: number | null) => {
    if (busy) return
    setBusy(true)
    setRefusal(null)
    void (async () => {
      const r = await cmdSeatCaptain(code, shipId, at)
      setBusy(false)
      if (r.ok) {
        setPicking(null)
        await Promise.all([refresh(), loadOfficers()])
      } else {
        setRefusal(r.refusal)
      }
    })()
  }

  return (
    <section data-testid="ship-cabins">
      <div className="flex items-baseline justify-between pb-2 pt-4">
        <h3 className="text-t-caption uppercase tracking-wider text-ink-faint">Cabins</h3>
        {seats.note && <span className="text-t-caption text-ink-faint">{seats.note}</span>}
      </div>
      <ul className="flex flex-col gap-1">
        {seats.list.map((s) => (
          <li key={s.seat} className="rounded-control bg-surface-2 px-3 py-2" data-testid={`cabin-${s.seat}`}>
            <div className="flex items-baseline justify-between gap-3">
              <span className="min-w-0 truncate text-t-caption text-ink-faint">{s.cabin_word}</span>
              {s.captain && (
                <span className="shrink-0 text-t-caption tabular-nums text-accent">{`${s.captain.rate_pct}%`}</span>
              )}
            </div>
            <div className="flex items-center justify-between gap-3">
              <span className="min-w-0 truncate text-t-label text-ink">
                {s.captain ? `${s.captain.grade} · ${s.captain.name} · ${s.captain.job_word}` : 'Empty'}
              </span>
              {canSeat && s.captain && (
                <Button variant="quiet" size="sm" disabled={busy} onClick={() => seat(s.captain!.code, null, null)}
                  data-testid={`cabin-ashore-${s.seat}`}>
                  Ashore
                </Button>
              )}
              {canSeat && !s.captain && (
                <Button variant="quiet" size="sm" disabled={busy} onClick={() => setPicking(picking === s.seat ? null : s.seat)}
                  data-testid={`cabin-seat-${s.seat}`}>
                  Seat
                </Button>
              )}
            </div>
            {canSeat && picking === s.seat && (
              <div className="mt-2 flex flex-wrap gap-1" data-testid={`cabin-pick-${s.seat}`}>
                {seating.captains.length === 0 ? (
                  <span className="text-t-caption text-ink-faint">Hire a captain at an inn first.</span>
                ) : (
                  seating.captains.map((c) => (
                    <Button key={c.code} variant="secondary" size="sm" disabled={busy}
                      onClick={() => seat(c.code, seating.shipId, s.seat)} data-testid={`cabin-pick-${c.code}`}>
                      {c.grade ? `${c.grade} · ${c.name}` : c.name}
                    </Button>
                  ))
                )}
              </div>
            )}
          </li>
        ))}
      </ul>
      {refusal && (
        <Note tone="danger" code={refusal.code} figures={refusal.figures} className="mt-2">
          {refusal.sentence}
        </Note>
      )}
    </section>
  )
}
