import { useState, type ReactNode } from 'react'
import { Button, Note } from '../components/ui'
import { cmdPreviewTow, cmdTow, ok } from '../lib/rpc'
import type { FleetView, Refusal, TowReceipt } from '../lib/rpc'
import { formatDucats } from '../lib/format'
import { useServedRead } from './useServedRead'
import { useWorld } from './worldStore'
import { useT } from '../lib/i18n'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// TOW — a wrecked fleet of yours lying in this harbour, and the one press that moves it to a yard
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// §7B, answered before the first line. The CONCEPT: the doorway of the tow (0152, `cmd.tow`) for
// a fleet that cannot sail because its hulls are at 0 — the served status UNABLE_TO_SAIL. It LIVES
// in src/live because two screens draw a harbour's faces and the wreck lies in the harbour, not
// behind one of its buildings: PORT (above its faces) and the map's city panel (above its tabs) —
// those are the two callers, on day one. It is NOT the Repair face (PortShipyard): a wreck at a
// harbour with no shipyard has no Repair face to stand on, which is the whole reason it exists.
//
// NOTHING HERE DECIDES. Where it goes, how far, what it costs and the sentence that says so are
// the server's dry run (`cmd.preview_tow`, the real tow rolled back); the press is `cmd.tow` with
// the fleet's version (E_STALE). A refusal prints the server's own sentence (E_TOW_FUNDS names
// the fee and the purse). The status read only decides whether to ASK — the server refuses a fleet
// that is not a wreck (E_NOT_WRECKED) whatever this file thinks.
//
// What would make it the wrong shape: a second doorway (a Tow button on FLEETS, on COMMAND). The
// tell is a second importer of `cmdTow`.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** One note per wrecked fleet among `docked` — the fleets of yours lying in this harbour. */
export function TowNote({ docked }: { docked: readonly FleetView[] }) {
  const wrecks = docked.filter((f) => f.status === 'UNABLE_TO_SAIL' && f.ships.length > 0)   // 0321: an empty fleet is no wreck
  if (wrecks.length === 0) return null
  return (
    <div className="space-y-2" data-testid="tow">
      {wrecks.map((f) => (
        <TowRow key={f.id} fleet={f} />
      ))}
    </div>
  )
}

interface Served {
  view: TowReceipt | null
  refusal: Refusal | null
}

/** The tow, quoted (0497's HQ press reads it too, live/WreckFix.tsx): the fee and where to once the dry run has answered and her
 *  purse covers it; the server's own sentence; its refusal (E_TOW_FUNDS names the fee and the purse); and the one press. */
export interface TowQuote {
  fee: number | null
  to: string | null
  sentence: string | null
  refusal: Refusal | null
  busy: boolean
  send: () => void
}

/** THE TOW'S ONE ACT: its dry run and its press, handed to whoever draws them. This file stays the one importer of `cmdTow`. */
export function TowNow({ fleet, children }: { fleet: FleetView; children: (quote: TowQuote) => ReactNode }) {
  const refresh = useWorld((s) => s.refresh)
  const [sending, setSending] = useState(false)
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  // the purse is part of the question: a sale that fills it asks the tow again
  const quote = useServedRead<Served>(`tow:${fleet.id}:${fleet.version}`, async () => {
    const r = await cmdPreviewTow(fleet.id)
    return ok(r.ok ? { view: r.value, refusal: null } : { view: null, refusal: r.refusal })
  }, { name: 'cmdPreviewTow', cache: false })
  const estimate = quote.view?.view ?? null
  const shown = refusal ?? quote.view?.refusal ?? null

  const send = () => {
    if (sending) return
    setSending(true)
    setRefusal(null)
    void (async () => {
      const r = await cmdTow(fleet.id, fleet.version)
      setSending(false)
      if (r.ok) await refresh()
      else setRefusal(r.refusal)
    })()
  }
  return <>{children({ fee: estimate ? estimate.fee : null, to: estimate ? estimate.to_name : null, sentence: estimate ? estimate.sentence : null, refusal: shown, busy: sending, send })}</>
}

function TowRow({ fleet }: { fleet: FleetView }) {
  const t = useT()
  // Until the dry run answers there is nothing true to say — the words are the server's.
  return (
    <TowNow fleet={fleet}>
      {(q) => (
        <>
          {q.fee !== null && q.sentence !== null && (
            <Note
              tone="warning"
              data-testid="tow-note"
              action={
                <Button size="sm" busy={q.busy} busyLabel={t('ship.towing')} onClick={q.send} data-testid="tow-send">
                  {q.fee > 0 ? t('ship.towFee', { fee: formatDucats(q.fee) }) : t('ship.tow')}
                </Button>
              }
            >
              {q.sentence}
            </Note>
          )}
          {q.refusal && (
            <Note tone="danger" code={q.refusal.code} figures={q.refusal.figures} data-testid="tow-refusal">
              {q.refusal.sentence}
            </Note>
          )}
        </>
      )}
    </TowNow>
  )
}
