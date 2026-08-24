import { Button, Explain, fineClass, Notice, RefusalNote, StatRow } from '../../components/ui'
import { formatDucats, formatFixed, formatInt, formatNm, formatRealShort, formatTuns, formatUnitPrice, formatVoyageDays } from '../../lib/format'
import type { PreviewResult, Refusal, VerbSpec } from '../../lib/rpc'
// THE PAYLOAD READERS ARE MACHINERY NOW (2026-08-23). `num` and `str` were declared at the foot of
// this file and again in `features/ledger/LedgerScreen.tsx`, and they had drifted — LEDGER's `num`
// tolerated a numeric that arrived as a string and this one did not. docs/NO_SPAGHETTI.md §2 named
// the pair as debt; the Map tab needing a third reader triggered §1's "found a third time" rule.
import { num, str } from '../../lib/json'
import type { FixAction } from '../../domain/order'
// AND THE SAIL ESTIMATE'S KEYS BELONG TO THE ORDER SECTION. The Map tab prints the same passage
// beside "Sail here", so `total_nm` / `voyage_days` have one READING (domain/order/estimate.ts)
// and two renderings — a rendering is a screen's chrome, not a second authority.
import { fixAction, sailEstimate } from '../../domain/order'

// THE DRY RUN — F.5 layer 3, rendered.
//
// `cmd.preview()` executes the REAL verb inside a subtransaction and throws the writes away, so
// what is printed here is not an estimate of what the order would do: it is what the order just
// did, before being rolled back. The preview and the commit share one code path by construction
// and cannot disagree. That is why there is no client-side checker any more — validate.ts was 838
// lines of second opinion, and a second opinion about legality is a second authority.
//
// A REFUSAL IS THE GAME WORKING (F.5). It is never a bare code: the code is a small mono badge,
// the SENTENCE is the thing the player reads, and every fix is a real order they can TAP to load.
//
// THE REACH LAW: the fix buttons are actions, so nothing here is inside a capped or scrolling box.

export type CheckState =
  | { status: 'idle' }
  | { status: 'checking' }
  | { status: 'ok'; result: PreviewResult }
  | { status: 'refused'; refusal: Refusal }

export function PreviewPanel({
  state,
  verbs,
  timeCompression,
  onFix,
}: {
  state: CheckState
  /** The server's schema, so a fix can be read back into the composer through the same grammar. */
  verbs: readonly VerbSpec[]
  /** `config.time_compression` — the server's own knob, so a voyage's real-world ETA is its ETA. */
  timeCompression: number
  onFix: (action: FixAction) => void
}) {
  if (state.status === 'idle') {
    // The HOW of the check is standing prose, so it is behind the dot (Explain.tsx) — beside the
    // short line it explains, never orphaned on a line of its own. What stays visible is only the
    // state that is true right now: there is nothing to check yet.
    return (
      <p className="flex flex-wrap items-center gap-x-1 font-mono text-xs text-ink-faint">
        Nothing to check yet
        <Explain label="the check" panelClassName="w-full normal-case tracking-normal">
          Finish the order and the server will run it, roll it back, and tell you what it would
          cost — before a ducat moves.
        </Explain>
      </p>
    )
  }

  if (state.status === 'checking') {
    return <p className="font-mono text-xs text-ink-faint">Asking the server what this would do…</p>
  }

  if (state.status === 'refused') {
    const { refusal } = state
    // THE REFUSAL ITSELF IS RefusalNote — the design system's ONE concise rendering (the owner's
    // 2026-08-24 law: graphics and figures, never a paragraph; the served figures draw the bar
    // the moment a migration serves them, and the sentence carries the reason until then). The
    // ✗ that used to head this branch went with the hand-written copy: its ✓ partner marks the
    // PASSED readout below, and the refusal's own badge-or-bar is mark enough. What stays THIS
    // panel's is the fixes block — loading a fix into the composer is the composer's affair.
    return (
      <RefusalNote refusal={refusal}>
        {refusal.fixes.length > 0 && (
          <div className="space-y-2">
            <p className={fineClass('uppercase tracking-wider')}>Instead</p>
            {refusal.fixes.map((fix) => {
              const action = fixAction(fix, verbs)
              const hole = HOLE.test(fix)
              return (
                <div key={fix} className="flex flex-wrap items-center gap-2">
                  <code className="min-w-0 flex-1 break-words font-mono text-xs text-accent">
                    <FixLine fix={fix} />
                  </code>
                  {action.kind === 'none' ? (
                    <span className={fineClass()}>nothing to load</span>
                  ) : (
                    <Button variant="secondary" onClick={() => onFix(action)}>
                      {/* WHAT THE BUTTON PROMISES HAS TO BE WHAT HAPPENS. `SELL <good> ALL` cannot
                          be "made" by tapping — it loads SELL and opens the good picker, because a
                          placeholder is a hole the server left for the player (text.ts:146). It
                          said "make this" anyway, beside a line reading a literal `<good>`. */}
                      {action.kind === 'queue' ? 'do it' : hole ? 'start this' : 'make this'}
                    </Button>
                  )}
                </div>
              )
            })}
          </div>
        )}
      </RefusalNote>
    )
  }

  const { result } = state

  if (result.immediate) {
    return (
      <Notice tone="accent" className="text-xs">
        This acts at once — there is nothing to estimate.
      </Notice>
    )
  }

  if (result.queued) {
    return (
      <Notice tone="accent" className="text-xs">
        The fleet is at sea, so this order will WAIT in her queue and run the moment she is
        alongside. Nothing can cost it until then — prices will have moved by the time she arrives,
        and that is the whole gamble.
      </Notice>
    )
  }

  return (
    <div className="space-y-2">
      <p className="flex flex-wrap items-center gap-2 font-mono text-sm text-success">
        {/* Text, deliberately: `icons.ts` has no tick, and `close` is the DISMISS mark (it shuts
            panels), so borrowing it would give one glyph two meanings. The refused state's mark
            is RefusalNote's own badge-or-bar since 2026-08-24. */}
        <span aria-hidden>✓</span>
        <span>ran on the server and was rolled back — this is what it would do</span>
      </p>
      <dl className="space-y-1">
        <Estimate verb={result.parsed.verb} estimate={result.estimate} timeCompression={timeCompression} />
      </dl>
    </div>
  )
}

// ── a refusal's fixes, and the holes the server leaves in them ──────────────────────────────────
//
// A fix arrives as a real order line, and some of them carry a `<placeholder>`: `SELL <good> ALL`,
// `BUY <good> HALF`, `SAIL Gaivota TO <a nearer port>`. Those are not broken templates — they are
// the server saying "this, and you choose the rest", and `fixAction` (domain/order/text.ts:146)
// already reads everything up to the hole and leaves the argument unset so the composer opens its
// picker on it. Tapping one WORKS.
//
// What was wrong was the rendering: the line printed the raw `<good>` in the same brass mono as a
// real token, so it read as a variable name that leaked out of the server — and the button beside
// it said "make this" about an order it could not finish making. The hole is now drawn as a hole
// (dimmed, italic, without the angle brackets, which are a programmer's punctuation) and the button
// says "start this". Nothing about the fix's meaning is invented here: the words inside the
// brackets are the server's own, and they are printed.

/** A `<…>` hole in a fix line — the server's mark for "you choose this part". */
const HOLE = /<[^>]+>/

/** The fix line, with the server's placeholders drawn as holes rather than as tokens. */
function FixLine({ fix }: { fix: string }) {
  // `split` with a capturing group keeps the delimiters, so the pieces alternate literal / hole.
  const pieces = fix.split(/(<[^>]+>)/g).filter((p) => p !== '')
  return (
    <>
      {pieces.map((piece, i) =>
        piece.startsWith('<') && piece.endsWith('>') ? (
          <span key={i} className="italic text-ink-faint">
            {piece.slice(1, -1)}
          </span>
        ) : (
          <span key={i}>{piece}</span>
        ),
      )}
    </>
  )
}

// ── the verb-shaped estimates cmd.do_*() return (migration 0007) ────────────────────────────────
//
// `num` and `str` were declared HERE until 2026-08-23. They are `src/lib/json.ts` now — see the
// import at the head of this file, and that module's header for the drift they had already
// accumulated against LEDGER's copies.

function Estimate({
  verb,
  estimate,
  timeCompression,
}: {
  verb: string
  estimate: Record<string, unknown> | undefined
  timeCompression: number
}) {
  if (!estimate) {
    return <StatRow label="estimate" value="the server returned none" plain />
  }

  switch (verb) {
    case 'SAIL': {
      // ONE READING, TWO SCREENS (domain/order/estimate.ts). The Map tab prints the same two
      // figures beside "Sail here"; what differs is the chrome, never the keys.
      const { nm, days } = sailEstimate(estimate)
      // The real-world wait is voyage-days ÷ the compression the SERVER serves in snapshot.config —
      // not the constant in lib/format, which pins 480 at build time and would lie the day a
      // migration retunes the clock.
      const realMs = days === null ? null : (days * 24 * 60 * 60 * 1000) / Math.max(timeCompression, 1)
      return (
        <>
          {nm !== null && <StatRow label="distance" value={formatNm(nm)} />}
          {days !== null && <StatRow label="passage" value={formatVoyageDays(days)} />}
          {realMs !== null && <StatRow label="you wait" value={formatRealShort(realMs)} />}
        </>
      )
    }
    case 'BUY':
    case 'SELL': {
      const qty = num(estimate, 'qty')
      const total = num(estimate, 'total')
      const avg = num(estimate, 'avg_price')
      return (
        <>
          {qty !== null && <StatRow label={verb === 'BUY' ? 'aboard' : 'landed'} value={formatTuns(qty)} />}
          {avg !== null && <StatRow label="average" value={formatUnitPrice(avg)} />}
          {total !== null && (
            <StatRow label={verb === 'BUY' ? 'it costs' : 'it fetches'} value={formatDucats(total)} />
          )}
          {str(estimate, 'good') && <StatRow label="good" value={str(estimate, 'good')} plain />}
        </>
      )
    }
    case 'PROVISION': {
      const water = num(estimate, 'water_t')
      const food = num(estimate, 'food_t')
      const cost = num(estimate, 'cost')
      const endurance = num(estimate, 'endurance_days')
      return (
        <>
          {water !== null && <StatRow label="water" value={formatTuns(water, 1)} />}
          {food !== null && <StatRow label="food" value={formatTuns(food, 1)} />}
          {cost !== null && <StatRow label="it costs" value={formatDucats(cost)} />}
          {endurance !== null && <StatRow label="endurance after" value={formatVoyageDays(endurance)} />}
        </>
      )
    }
    case 'HIRE': {
      const hired = num(estimate, 'hired')
      const urgent = num(estimate, 'urgent')
      const cost = num(estimate, 'cost')
      return (
        <>
          {hired !== null && <StatRow label="signed on" value={formatInt(hired)} />}
          {urgent !== null && urgent > 0 && (
            <StatRow label="beyond the pool" value={`${formatInt(urgent)} at the urgent rate`} plain />
          )}
          {cost !== null && <StatRow label="it costs" value={formatDucats(cost)} />}
        </>
      )
    }
    case 'REPAIR': {
      const points = num(estimate, 'points')
      const cost = num(estimate, 'cost')
      const hours = num(estimate, 'sim_hours')
      return (
        <>
          {points !== null && <StatRow label="hull mended" value={formatFixed(points, 1)} />}
          {cost !== null && <StatRow label="it costs" value={formatDucats(cost)} />}
          {/* "shipyard", not "yard" — the owner asked what a yard was (2026-08-23), and a label a
              player must ask about is jargon. The LABEL is this client's; the figure is served. */}
          {hours !== null && <StatRow label="in the shipyard" value={`${formatFixed(hours, 1)} h`} />}
        </>
      )
    }
    default:
      // A verb this screen has never seen still gets its estimate printed, honestly and unstyled,
      // rather than silently dropped. The server's vocabulary may grow before this file does.
      return (
        <>
          {Object.entries(estimate).map(([k, v]) => (
            <StatRow key={k} label={k} value={String(v)} plain />
          ))}
        </>
      )
  }
}
