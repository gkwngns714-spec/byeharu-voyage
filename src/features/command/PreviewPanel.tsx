import { Badge, Button, Notice, StatRow } from '../../components/ui'
import { formatDucats, formatFixed, formatInt, formatNm, formatRealShort, formatTuns, formatUnitPrice, formatVoyageDays } from '../../lib/format'
import type { PreviewResult, Refusal, VerbSpec } from '../../lib/rpc'
import type { FixAction } from './orderText'
import { fixAction } from './orderText'

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
    return (
      <p className="font-mono text-xs text-ink-faint">
        Finish the order and the server will run it, roll it back, and tell you what it would cost.
      </p>
    )
  }

  if (state.status === 'checking') {
    return <p className="font-mono text-xs text-ink-faint">Asking the server what this would do…</p>
  }

  if (state.status === 'refused') {
    const { refusal } = state
    return (
      <div className="space-y-3">
        <div className="flex flex-wrap items-center gap-2">
          <span aria-hidden className="font-mono text-sm text-danger">
            ✗
          </span>
          <Badge tone="danger">{refusal.code}</Badge>
          {refusal.source === 'fault' && <Badge tone="warning">fault</Badge>}
        </div>
        <p className="text-sm text-ink">{refusal.sentence}</p>
        {refusal.fixes.length > 0 && (
          <div className="space-y-2">
            <p className="font-mono text-[11px] uppercase tracking-wider text-ink-faint">Instead</p>
            {refusal.fixes.map((fix) => {
              const action = fixAction(fix, verbs)
              return (
                <div key={fix} className="flex flex-wrap items-center gap-2">
                  <code className="min-w-0 flex-1 break-words font-mono text-xs text-accent">{fix}</code>
                  {action.kind === 'none' ? (
                    <span className="font-mono text-[11px] text-ink-faint">nothing to load</span>
                  ) : (
                    <Button variant="secondary" onClick={() => onFix(action)}>
                      {action.kind === 'queue' ? 'do it' : 'make this'}
                    </Button>
                  )}
                </div>
              )
            })}
          </div>
        )}
      </div>
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
        alongside. The server cannot cost it until then — prices will have moved by the time she
        arrives, which is the whole gamble (F.2).
      </Notice>
    )
  }

  return (
    <div className="space-y-2">
      <p className="flex flex-wrap items-center gap-2 font-mono text-sm text-success">
        <span aria-hidden>✓</span>
        <span>ran on the server and was rolled back — this is what it would do</span>
      </p>
      <dl className="space-y-1">
        <Estimate verb={result.parsed.verb} estimate={result.estimate} timeCompression={timeCompression} />
      </dl>
    </div>
  )
}

// ── the verb-shaped estimates cmd.do_*() return (migration 0007) ────────────────────────────────

function num(estimate: Record<string, unknown> | undefined, key: string): number | null {
  const raw = estimate?.[key]
  if (raw === null || raw === undefined) return null
  const n = Number(raw)
  return Number.isFinite(n) ? n : null
}

function str(estimate: Record<string, unknown> | undefined, key: string): string | null {
  const raw = estimate?.[key]
  return typeof raw === 'string' ? raw : null
}

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
      const nm = num(estimate, 'total_nm')
      const days = num(estimate, 'voyage_days')
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
          {hours !== null && <StatRow label="in the yard" value={`${formatFixed(hours, 1)} h`} />}
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
