import { useState } from 'react'
import {
  Badge,
  Button,
  Explain,
  fineClass,
  headRowClass,
  inlineFigureClass,
  Meter,
  Notice,
  SectionLabel,
} from '../../components/ui'
import { formatPctPoints } from '../../lib/format'
import type { HaggleAttempt, MarketGood, Refusal } from '../../lib/rpc'
import { useWorld } from '../../live/worldStore'
import type { HaggleStateRead } from './useHaggleState'

/** Only reachable if the store lost the refusal between the call and the read — never in practice,
 *  but a blank panel after a press that plainly did something is the worse failure. */
const FALLBACK: Refusal = {
  code: 'E_REFUSED',
  sentence: 'The factor turned away, and the server did not say why.',
  fixes: [],
  source: 'server',
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// STRIKE A BARGAIN — the client half of migration 0022
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// 0022 shipped `cmd.haggle` and `world.haggle_state` with no caller anywhere in src/. This is the
// caller. The FIGURES are next door in the rail (BuyFleetPanel); this is the ACT, and it is here —
// in the working pane, under the quantity stepper — for one reason, stated in
// src/components/ui/screenLayout.ts and in CORE_REUSE §1.5:
//
//     "An action may never live inside a region that can scroll or clip it."
//
// The rail is `md:sticky`, and a sticky panel taller than the viewport hides its own foot. A
// button in it would be the "right now i can't press hunt" defect rebuilt from scratch.
//
// ── THREE RULES THIS COMPONENT KEEPS, AND WHY EACH IS EASY TO BREAK ────────────────────────────
//
// 1. THE BUTTON IS NEVER DISABLED BY A CLIENT-SIDE RULE. Not when `attempts_left` is 0, not when
//    she is at sea, not when the quay holds no stock. Every one of those is a refusal the server
//    already writes better than this file could — `E_HAGGLE_SPENT` comes with "The factor will
//    hear no more about Black Pepper in Lisboa today. You have had 3 of 3." and three fixes. A
//    client check would (a) duplicate a rule the server owns, and (b) go stale between reads,
//    which is how a player ends up unable to press a button that would have worked.
//
// 2. A LOST HAGGLE IS NOT AN ERROR. `cmd.haggle` returns `ok:true, won:false` when the factor
//    refuses — he heard you and said no, which is the game working. It renders in `warning`, with
//    the server's own sentence, and never in the danger tone a refusal wears.
//
// 3. NOTHING IS RETRIED, EVER, AND NOTHING IS PREDICTED. The attempt is written and the count
//    incremented BEFORE the roll is taken, and the roll is keyed on the attempt index (0022:508),
//    so a retry is a different draw that has already cost a chance. There is no re-roll to be had
//    and no outcome to guess at; one press is one attempt.

export function HaggleBlock({
  fleetId,
  good,
  read,
}: {
  fleetId: string | null
  /** The good being bought, from THIS port's market. Null while the list is still open. */
  good: MarketGood | undefined
  /** The composer's reading of `world.haggle_state`, shared with the rail. */
  read: HaggleStateRead
}) {
  const haggle = useWorld((s) => s.haggle)
  const [busy, setBusy] = useState(false)
  // THE OUTCOME OF THE LAST PRESS OF THIS BUTTON, stamped with the good it was about — so a bargain
  // struck over pepper never reads as a bargain over silk once the player changes their mind.
  //
  // IT IS HELD LOCALLY RATHER THAN READ FROM `useWorld(s => s.refusal)`, and that is not a style
  // choice: the store keeps ONE refusal for the whole tab and the composer's own `cmd.preview()`
  // writes it on every keystroke of a pick. Rendering that field here would print an unrelated
  // preview refusal under the haggle button, which is worse than printing nothing. `haggle()`
  // returns null on a refusal and stores it, so the refusal is taken from the store at the instant
  // of the press — the same idiom CommandScreen uses after `issue()`.
  const [outcome, setOutcome] = useState<
    { good: string; attempt: HaggleAttempt } | { good: string; refusal: Refusal } | null
  >(null)

  if (!fleetId || !good) return null

  const state = read.state
  const onQuay = state?.docked === true ? state : null
  const mine = outcome?.good === good.code ? outcome : null
  const attempt = mine && 'attempt' in mine ? mine.attempt : null
  const refusal = mine && 'refusal' in mine ? mine.refusal : null

  const strike = async () => {
    setBusy(true)
    const result = await haggle(fleetId, good.good_id, 'buy')
    setBusy(false)
    setOutcome(
      result
        ? { good: good.code, attempt: result }
        : { good: good.code, refusal: useWorld.getState().refusal ?? FALLBACK },
    )
  }

  return (
    <div className="bv-cut mt-2 border border-edge bg-surface-2 p-3">
      <div className={headRowClass()}>
        <span className="flex flex-wrap items-center gap-x-1">
          <SectionLabel className="mb-0">Strike a bargain</SectionLabel>
          {/* THE STANDING EXPLANATION IS BEHIND THE DOT (Explain.tsx): how a haggle works is a rule
              the player learns once, and it stood here as a permanent two-sentence paragraph. The
              tries-left count, the odds and the outcome stay in the open — they are live. */}
          <Explain label="the bargain" panelClassName="w-full normal-case tracking-normal">
            Offer the factor less for {good.name}. He may come down off his cut, or he may fold his
            arms — and either way the try is spent.
          </Explain>
        </span>
        {onQuay && (
          <span className={fineClass()}>
            {onQuay.attempts_left} of {onQuay.attempts_max} tries left today
          </span>
        )}
      </div>

      {/* AT SEA — the server's own sentence, printed as it wrote it. A REASON attached to a thing
          she cannot do stays visible; reasons never go behind a dot. */}
      {state?.docked === false ? (
        <p className="text-sm text-ink-muted">{state.why}</p>
      ) : (
        <>
          {onQuay && (
            <div className="mt-2 space-y-1">
              <div className="flex items-center gap-2">
                <span className={fineClass('shrink-0')}>your odds</span>
                <Meter
                  pct={onQuay.next_odds_pct}
                  tone={onQuay.next_odds_pct >= 45 ? 'success' : 'warning'}
                  className="min-w-0 flex-1"
                />
                <span className={inlineFigureClass('shrink-0')}>
                  {formatPctPoints(onQuay.next_odds_pct, 1)}
                </span>
              </div>
              {/* THE HARDENING IS DISCLOSED BEFORE IT BITES, not explained after. 0022 multiplies
                  the NEXT attempt's odds by (1 - haggle_hardening_per_fail) for every REFUSAL
                  already taken today, which is what makes a finite number of tries a decision
                  rather than three free rolls.

                  A REFUSAL IS `attempts_used - wins`, NOT `attempts_used`, and the first draft of
                  this line got it wrong — it read the attempt count and told a player who had won
                  once and been refused twice that "he has already refused you 3 times". Caught in
                  the running game, against a screen that said `0 of 3 tries left` beside a bargain
                  it had plainly won. The server does the same subtraction in `haggle_odds`
                  (0022:264, `greatest(0, h.attempts - h.wins)`), which is the number this sentence
                  is about; both fields are served, so this composes them rather than guessing. */}
              {onQuay.attempts_used - onQuay.wins > 0 && (
                <p className={fineClass()}>
                  He has already refused you{' '}
                  {onQuay.attempts_used - onQuay.wins === 1
                    ? 'once'
                    : `${onQuay.attempts_used - onQuay.wins} times`}{' '}
                  over this today, and he is harder for it.
                </p>
              )}
            </div>
          )}

          <div className="mt-3 flex flex-wrap items-center gap-2">
            <Button
              variant="secondary"
              busy={busy}
              busyLabel="Bargaining…"
              onClick={() => void strike()}
            >
              Haggle over {good.name}
            </Button>
            {onQuay && onQuay.concession > 0 && (
              <Badge tone="success">
                {formatPctPoints(onQuay.concession_pct, 1)} off his cut, held
              </Badge>
            )}
          </div>

          {/* THE OUTCOME, IN THE SERVER'S WORDS. Won and lost are both `ok`; only the tone differs.
              `message` is composed by cmd.haggle — three sentences, one of them for reaching the
              cap — and nothing here rewrites or supplements it. */}
          {attempt && (
            <Notice tone={attempt.won ? 'success' : 'warning'} className="mt-3 text-sm">
              {attempt.message}
            </Notice>
          )}

          {/* A REFUSAL — E_NOT_DOCKED, E_NO_STOCK, E_HAGGLE_SPENT … — code, sentence and the
              server's own fixes, rendered the way every other refusal on this tab is (F.5). The
              fixes are printed as words, not buttons: 0022's are parenthesised advice
              ("(come back tomorrow)"), not orders a composer could load. */}
          {refusal && (
            <Notice tone="danger" className="mt-3 text-sm">
              <span className="font-mono text-xs">{refusal.code}</span> — {refusal.sentence}
              {refusal.fixes.length > 0 && (
                <span className={fineClass('mt-1 block')}>{refusal.fixes.join(' · ')}</span>
              )}
            </Notice>
          )}
        </>
      )}
    </div>
  )
}
