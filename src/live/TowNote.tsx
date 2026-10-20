import { useState } from 'react'
import { Button, Note } from '../components/ui'
import { cmdPreviewTow, cmdTow, ok } from '../lib/rpc'
import type { FleetView, Refusal, TowReceipt } from '../lib/rpc'
import { formatDucats } from '../lib/format'
import { useServedRead } from './useServedRead'
import { useWorld } from './worldStore'

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
  const wrecks = docked.filter((f) => f.status === 'UNABLE_TO_SAIL')
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

function TowRow({ fleet }: { fleet: FleetView }) {
  const refresh = useWorld((s) => s.refresh)
  const [sending, setSending] = useState(false)
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  const quote = useServedRead<Served>(`tow:${fleet.id}`, async () => {
    const r = await cmdPreviewTow(fleet.id)
    return ok(r.ok ? { view: r.value, refusal: null } : { view: null, refusal: r.refusal })
  })
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

  // Until the dry run answers there is nothing true to say — the words are the server's.
  return (
    <>
      {estimate && (
        <Note
          tone="warning"
          data-testid="tow-note"
          action={
            <Button size="sm" busy={sending} busyLabel="Towing…" onClick={send} data-testid="tow-send">
              {estimate.fee > 0 ? `Tow · ${formatDucats(estimate.fee)}` : 'Tow'}
            </Button>
          }
        >
          {estimate.sentence}
        </Note>
      )}
      {shown && (
        <Note tone="danger" code={shown.code} figures={shown.figures} data-testid="tow-refusal">
          {shown.sentence}
        </Note>
      )}
    </>
  )
}
