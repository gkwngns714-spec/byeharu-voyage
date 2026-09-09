import { Note, Row, Figure } from '../../components/ui'
import {
  formatDucats,
  formatFixed,
  formatInt,
  formatNm,
  formatRealShort,
  formatTuns,
  formatUnitPrice,
  formatVoyageDays,
} from '../../lib/format'
import { num, str } from '../../lib/json'
import { sailEstimate } from '../../domain/order'
import type { PreviewResult, Refusal } from '../../lib/rpc'

// THE CHECK, COMPACT — the server's dry run, drawn as Rows and one Note.
//
// `cmd.preview()` runs the REAL verb in a subtransaction and rolls it back, so the estimate a tray
// shows is what the order just did before being undone; the preview and the commit share one code
// path and cannot disagree (F.5). What is deleted from the old PreviewPanel is its chrome, not its
// authority: the "Nothing to check yet" idle line (§2's noise), the ✓/✗ glyphs, the "ran on the
// server and was rolled back" sentence (§2 item 13's developer vocabulary), and the uppercase
// labels. What stays is the figures and — on a refusal — the server's own sentence, with the code
// going to console.debug through `Note` and never onto the quay.
//
// The fixes a refusal carries are not rendered as tappable buttons here (the old panel's most
// elaborate feature). §7 step 5 is a collapse, and a refused order in a tray is dismissed and
// recomposed rather than corrected in place; the server still names the reason. See the report.

export type CheckState =
  | { status: 'idle' }
  | { status: 'checking' }
  | { status: 'ok'; result: PreviewResult }
  | { status: 'refused'; refusal: Refusal }

export function OrderCheck({
  check,
  timeCompression,
}: {
  check: CheckState
  timeCompression: number
}) {
  if (check.status === 'idle') return null

  if (check.status === 'checking') {
    return <Row label="Asking the quay what this would do" tone="muted" hairline={false} />
  }

  if (check.status === 'refused') {
    return (
      <Note tone="danger" code={check.refusal.code} data-testid="order-check-refusal">
        {check.refusal.sentence}
      </Note>
    )
  }

  const { result } = check
  if (result.immediate || result.queued) {
    return (
      <Note tone="info">
        {result.queued
          ? 'She is at sea, so this waits in her queue and runs the moment she is alongside.'
          : 'This acts at once.'}
      </Note>
    )
  }

  return <Estimate verb={result.parsed.verb} estimate={result.estimate} timeCompression={timeCompression} />
}

/** The verb-shaped estimate `cmd.do_*()` returns (migration 0007), one Row per served figure. */
function Estimate({
  verb,
  estimate,
  timeCompression,
}: {
  verb: string
  estimate: Record<string, unknown> | undefined
  timeCompression: number
}) {
  if (!estimate) return null

  switch (verb) {
    case 'SAIL': {
      const { nm, days } = sailEstimate(estimate)
      const realMs = days === null ? null : (days * 24 * 60 * 60 * 1000) / Math.max(timeCompression, 1)
      return (
        <>
          {nm !== null && <Row label="Distance" value={<Figure value={formatNm(nm)} />} />}
          {days !== null && <Row label="Passage" value={<Figure value={formatVoyageDays(days)} />} />}
          {realMs !== null && (
            <Row label="You wait" value={<Figure value={formatRealShort(realMs)} />} hairline={false} />
          )}
        </>
      )
    }
    case 'PROVISION': {
      const cost = num(estimate, 'cost')
      const endurance = num(estimate, 'endurance_days')
      return (
        <>
          {cost !== null && <Row label="It costs" value={<Figure value={formatDucats(cost)} />} />}
          {endurance !== null && (
            <Row
              label="Endurance after"
              value={<Figure value={formatVoyageDays(endurance)} tone="success" />}
              hairline={false}
            />
          )}
        </>
      )
    }
    case 'HIRE': {
      const hired = num(estimate, 'hired')
      const cost = num(estimate, 'cost')
      return (
        <>
          {hired !== null && <Row label="Signed on" value={<Figure value={formatInt(hired)} />} />}
          {cost !== null && <Row label="It costs" value={<Figure value={formatDucats(cost)} />} hairline={false} />}
        </>
      )
    }
    case 'REPAIR': {
      const points = num(estimate, 'points')
      const cost = num(estimate, 'cost')
      return (
        <>
          {points !== null && <Row label="Hull mended" value={<Figure value={formatFixed(points, 1)} />} />}
          {cost !== null && <Row label="It costs" value={<Figure value={formatDucats(cost)} />} hairline={false} />}
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
          {qty !== null && (
            <Row label={verb === 'BUY' ? 'Aboard' : 'Landed'} value={<Figure value={formatTuns(qty)} />} />
          )}
          {avg !== null && <Row label="Average" value={<Figure value={formatUnitPrice(avg)} />} />}
          {total !== null && (
            <Row
              label={verb === 'BUY' ? 'It costs' : 'It fetches'}
              value={<Figure value={formatDucats(total)} />}
              hairline={false}
            />
          )}
        </>
      )
    }
    default:
      return (
        <>
          {str(estimate, 'good') && <Row label="Good" value={str(estimate, 'good')} hairline={false} />}
        </>
      )
  }
}
