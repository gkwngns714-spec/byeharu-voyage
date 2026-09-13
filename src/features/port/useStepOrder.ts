// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A STEPPED ORDER, MADE AND JUDGED — the one act behind HIRE, REPAIR and PROVISION.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// THE CONCEPT (docs/NO_SPAGHETTI.md §7B): "the act of one stepped verb" — its arguments so far,
// the server's dry run of the exact line they make, and the one press that issues it.
//
// WHERE IT LIVES, AND WHY HERE. The design system may read nothing above it (tests/sections.spec.ts,
// "machinery knows nothing above it") and this reads the world — the grammar, `cmd.preview`,
// `cmd.issue` — so it cannot stand beside `Stepper`. Its one caller is PORT: the Inn asks it for
// HIRE, the Shipyard for REPAIR, the quay for PROVISION. The MAP is NOT a second caller — it runs
// a fix that is already complete (`PROVISION … FULL`) through `issue` with no stepper and no
// picker (useSendFleet.ts), and a distant harbour cannot host any of these three because every one
// needs her alongside. Until this slice the same state lived in CommandScreen (the debounced
// preview, the `checked` pair, `issuing`); it moved with the doorways rather than being copied.
//
// WHAT WOULD MAKE THIS THE WRONG SHAPE: a second file holding a `checked`/`issuing` pair for a
// verb. tests/verbHomes.spec.ts holds that `StepQuestion` is composed from features/port only.
//
// ONE PARSER, ON THE SERVER. `orderText` walks `cmd.verb_schema()` to the exact line; `preview`
// runs the REAL verb in a subtransaction and rolls it back (F.5); `issue` is the one door.

import { useEffect, useState } from 'react'
import { findVerb, isComplete, orderText } from '../../domain/order'
import { useWorld } from '../../live/worldStore'
import type { FleetView, Refusal, VerbSpec } from '../../lib/rpc'
import type { CheckState } from './orderCheck'

const FALLBACK_REFUSAL: Refusal = {
  code: 'E_REFUSED',
  sentence: 'The server refused, without a reason.',
  fixes: [],
  source: 'server',
}

export type StepVerb = 'HIRE' | 'REPAIR' | 'PROVISION'

export interface StepOrder {
  /** The served grammar for this verb; undefined until the snapshot has it. */
  spec: VerbSpec | undefined
  args: Record<string, string>
  setArg: (name: string, value: string | null) => void
  check: CheckState
  issuing: boolean
  /** The server's clock ratio, for "you wait" on a passage estimate. */
  timeCompression: number
  send: () => void
  /** Forget the arguments and the last verdict — the tray closed. */
  reset: () => void
}

export function useStepOrder(
  fleet: FleetView,
  verb: StepVerb,
  /** Dry runs cost a round trip; they run only while the tray is open. */
  open: boolean,
  /** Called once the order is issued: the caller closes its tray. */
  onDone: () => void,
): StepOrder {
  // A selector returns a SERVED reference, never a fresh literal (React #185 — worldStore rule).
  const verbs = useWorld((s) => s.snapshot?.verbs)
  const timeCompression = useWorld((s) => s.snapshot?.config.time_compression ?? 1)
  const preview = useWorld((s) => s.preview)
  const issue = useWorld((s) => s.issue)

  const [args, setArgs] = useState<Record<string, string>>({})
  const [checked, setChecked] = useState<{ text: string; state: CheckState } | null>(null)
  const [issuing, setIssuing] = useState(false)

  const setArg = (name: string, value: string | null) =>
    setArgs((s) => {
      const next = { ...s }
      if (value === null || value === '') delete next[name]
      else next[name] = value
      return next
    })

  const spec = findVerb(verbs ?? [], verb)
  const text = spec ? orderText(spec, args, fleet.name) : ''
  const ready = Boolean(spec && isComplete(spec, args))

  // THE DRY RUN — the exact line the button will send, priced on the day by the server.
  useEffect(() => {
    if (!open || !ready) return
    let alive = true
    const timer = setTimeout(() => {
      void preview(fleet.id, text, null).then((result) => {
        if (!alive) return
        setChecked({
          text,
          state: result
            ? { status: 'ok', result }
            : { status: 'refused', refusal: useWorld.getState().refusal ?? FALLBACK_REFUSAL },
        })
      })
    }, 250)
    return () => {
      alive = false
      clearTimeout(timer)
    }
  }, [open, ready, fleet.id, text, preview])

  const check: CheckState = !ready
    ? { status: 'idle' }
    : checked?.text === text
      ? checked.state
      : { status: 'checking' }

  const reset = () => {
    setArgs({})
    setChecked(null)
  }

  const send = () => {
    if (!ready || issuing) return
    setIssuing(true)
    void (async () => {
      const okay = await issue(fleet.id, text, null)
      setIssuing(false)
      if (okay) {
        reset()
        onDone()
      } else {
        setChecked({ text, state: { status: 'refused', refusal: useWorld.getState().refusal ?? FALLBACK_REFUSAL } })
      }
    })()
  }

  return { spec, args, setArg, check, issuing, timeCompression, send, reset }
}
