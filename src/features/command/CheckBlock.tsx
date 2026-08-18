import { Badge, Button, Notice } from '../../components/ui'
import type { CheckResult } from './validate'

// THE LIVE CHECK LINE — E.1's block under the input, and F.5's whole contract in one component.
//
//   ✓ parsed   fleet=Ponente(3 ships)  8 legs  11,020 nm
//     ETA 4h 12m real · 92.4 voyage-days
//     stores 47.6 d endurance ▸ NEEDS 106 d   ✗ E_ENDURANCE
//     fix: PROVISION Ponente FULL  (est. 8,240 d.)  [insert]
//
// A refusal is NEVER a bare code: the code is a small mono badge, the sentence is the thing the
// player actually reads, and every fix is a REAL COMMAND they can tap to load into the input.
//
// THE REACH LAW (CORE_REUSE 1.5): the fix buttons are actions, so this component must never be
// rendered inside a capped or scrolling box. It has no max-height and no overflow of its own, and
// its call site does not give it one. A fix the player can see but cannot press is the exact
// defect that law exists to prevent.

export function CheckBlock({
  result,
  onInsert,
}: {
  result: CheckResult | null
  onInsert: (command: string) => void
}) {
  if (!result) {
    return (
      <p className="font-mono text-xs text-ink-faint">
        Type an order, or build one by tapping below. The check runs as you type.
      </p>
    )
  }

  if (result.ok) {
    return (
      <div className="space-y-2">
        <p className="flex flex-wrap items-center gap-2 font-mono text-sm text-success">
          <span aria-hidden>✓</span>
          <span>{result.summary}</span>
        </p>
        <ul className="space-y-0.5 pl-4">
          {result.details.map((line) => (
            <li key={line} className="font-mono text-xs text-ink-muted">
              {line}
            </li>
          ))}
        </ul>
        {result.warnings.map((w) => (
          <Notice key={w} tone="warning" className="font-mono text-xs">
            {w}
          </Notice>
        ))}
      </div>
    )
  }

  return (
    <div className="space-y-2">
      <p className="flex flex-wrap items-center gap-2">
        <span aria-hidden className="font-mono text-sm text-danger">
          ✗
        </span>
        <Badge tone="danger">{result.code}</Badge>
      </p>
      <p className="text-sm text-ink">{result.sentence}</p>
      {result.details && result.details.length > 0 && (
        <ul className="space-y-0.5 pl-4">
          {result.details.map((line) => (
            <li key={line} className="font-mono text-xs text-ink-muted">
              {line}
            </li>
          ))}
        </ul>
      )}
      <div className="space-y-1">
        {result.fixes.map((fix) => (
          <div key={fix.command + (fix.note ?? '')} className="flex flex-wrap items-center gap-2">
            <span aria-hidden className="font-mono text-xs text-ink-faint">
              →
            </span>
            <code className="min-w-0 flex-1 break-words font-mono text-xs text-accent">{fix.command}</code>
            {fix.note && <span className="font-mono text-[11px] text-ink-faint">({fix.note})</span>}
            {/* size="md" is 44px tall — this is a primary affordance on a phone, not an in-row
                secondary, so it clears the touch floor rather than looking tidy. */}
            <Button variant="secondary" onClick={() => onInsert(fix.command)}>
              insert
            </Button>
          </div>
        ))}
      </div>
    </div>
  )
}
