import type { ReactNode } from 'react'
import { openHq } from '../app/hqPlace'
import { fleetCargo, fleetPortCode } from '../domain/fleet'
import { cmdPreview, ok, type FleetView, type Refusal } from '../lib/rpc'
import { TowNow, type TowQuote } from './TowNote'
import { useServedRead } from './useServedRead'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A WRECK IN A PORT, AND HER ONE NEXT PRESS (0497 `a-wreck-can-sell`; the owner's own company, 2026-11-25)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// Her fleet lay UNABLE_TO_SAIL at Diego Garcia (no shipyard), purse 0, 899 black coral aboard, and HQ offered her nothing.
// The way out is three presses, ONE AT A TIME, each decided by a SERVED answer and none by a rule of this file:
//   tow         the tow's own dry run answers a quote (`cmd.preview_tow`: where to, how far, the fee): "Tow 14,366", and its press
//               tows her (live/TowNote.tsx keeps the act: the one importer of `cmdTow`)
//   sell        the tow is refused for coin (E_TOW_FUNDS) and she has cargo, and THE SERVER RUNS A WRECK'S SALE (0497 lit: the dry
//               run of `SELL <good> ALL` answers a quote or the quay's own refusal, not `queued`): "Sell cargo" opens the sell face
//               on her. While 0497 is dark that dry run answers `queued` and the press is NOT DRAWN: it would be a press that
//               never runs
//   repair      after the tow she lies DOCKED at a yard with a dead flagship: the Repair press every stopped worker has
//               (live/FixButton.tsx; domain/fleet `wreckFix` names it)
// A refusal that is not for coin, or a wreck with nothing to sell, shows the tow's own sentence under a plain "Tow".

/** What the row, her sheet and While away draw for her now. `press` null: the answer is not in yet, or the press would not act
 *  (the sentence stands in her sheet). */
export interface WreckStep {
  kind: 'tow' | 'sell'
  /** The tow's fee, when its quote is in and her purse covers it. */
  fee: number | null
  /** Where the tow takes her (the served name), once the dry run has answered. */
  to: string | null
  /** The tow's own sentence (what it is, where to), or the server's refusal of it. */
  sentence: string | null
  refusal: Refusal | null
  busy: boolean
  press: (() => void) | null
}

/** DOES THE SERVER RUN A WRECK'S SALE? Asked of the server, once a fleet and good: the dry run of her SELL. `queued` is the old
 *  answer (the order would wait for ever: 0497 dark); anything else, a quote or the quay's refusal, is the real thing. */
function useWreckSells(fleet: FleetView, good: string | null): boolean | null {
  const read = useServedRead<{ lit: boolean }>(
    `wreck-sells:${fleet.id}:${good ?? ''}:${fleet.version}`,
    async () => {
      if (good === null) return ok({ lit: false })
      const r = await cmdPreview(fleet.id, `SELL ${good} ALL`, null)
      // a refusal is the quay's or the wreck rule's own answer: the order was judged, not queued
      return ok({ lit: r.ok ? r.value.queued !== true : true })
    },
    { name: 'wreckSells', cache: false },
  )
  return read.view ? read.view.lit : null
}

/** Her largest cargo, by units: the good the sell face opens on. */
function topCargo(fleet: FleetView): string | null {
  const lines = [...fleetCargo(fleet)].sort((a, b) => b.qty - a.qty)
  return lines[0]?.code ?? null
}

function Step({ fleet, tow, children }: { fleet: FleetView; tow: TowQuote; children: (step: WreckStep) => ReactNode }) {
  const good = topCargo(fleet)
  const port = fleetPortCode(fleet)
  const short = tow.refusal?.code === 'E_TOW_FUNDS'
  const sells = useWreckSells(fleet, short ? good : null)
  if (tow.fee !== null) {
    return <>{children({ kind: 'tow', fee: tow.fee, to: tow.to, sentence: tow.sentence, refusal: null, busy: tow.busy, press: tow.send })}</>
  }
  if (short && good !== null && port !== null && sells === true) {
    return <>{children({ kind: 'sell', fee: null, to: null, sentence: null, refusal: tow.refusal, busy: false, press: () => openHq({ sheet: 'trade', port, fleet: fleet.id, good, side: 'sell' }) })}</>
  }
  return <>{children({ kind: 'tow', fee: null, to: tow.to, sentence: tow.sentence, refusal: tow.refusal, busy: tow.busy, press: null })}</>
}

/** HER NEXT PRESS, handed to whoever draws it (a worker row's pill, a button in her sheet). `fleet` is a wreck in a port
 *  (domain/fleet `wreckFix`). */
export function WreckNow({ fleet, children }: { fleet: FleetView; children: (step: WreckStep) => ReactNode }) {
  return (
    <TowNow fleet={fleet}>
      {(tow) => (
        <Step fleet={fleet} tow={tow}>
          {children}
        </Step>
      )}
    </TowNow>
  )
}
