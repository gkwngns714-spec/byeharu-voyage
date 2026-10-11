import { Row, SheetSection } from '../../components/ui'
import { merchantLine } from '../../live/merchantLine'
import type { MerchantDoing, PortMerchant } from '../../lib/rpc'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// MERCHANTS — who this harbour concerns, and what each one is doing here (0104, owner row 121)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-10-11: *"By clicking the city, i get to see what trading ships started, resting,
// ending etc."*
//
// Since 0099 PORT has listed the merchant fleets LYING here. This is the rest of that sentence:
// every merchant whose LOOP calls at this harbour, what she is doing about it, and the loop itself
// — and a tap still opens the same read-only sheet MAP opens (`src/live/MerchantSheet.tsx`).
//
// ── NOTHING HERE IS WORKED OUT ─────────────────────────────────────────────────────────────────
// `doing` is DERIVED BY THE SERVER from her route's stops and cursor, its hold and its pause, and
// from where her fleet is (`public.merchant_doing_at`, migration 0104). This file spells the word
// and nothing else: a second copy of the rule here is how two readings of the same thing come to
// disagree (docs/NO_SPAGHETTI.md §1). The line under her name is `merchantLine`'s — the SAME one
// the chart's tray prints, so PORT and MAP cannot drift in words.
//
// ── THE WORDS ──────────────────────────────────────────────────────────────────────────────────
// Six, one each, every one a NAME a person would use (docs/WORDS.md laws 1 and 3). The owner's own
// three — started, resting, ending — are kept as the states they describe; `laid up` is WORDS.md's
// standing row for a merchant that cannot sail on, and `away` is the plain word for "her loop
// calls here and she is somewhere else on it".
const DOING: Record<MerchantDoing, string> = {
  laid_up: 'Laid up',
  resting: 'Resting',
  starting: 'Starting',
  ending: 'Ending',
  passing: 'Passing',
  away: 'Away',
}

/**
 * The harbour's merchants, in the SERVER's order (the ones lying here first, then the ones coming,
 * then the rest — migration 0104 ranks them, so every screen lists them the same way).
 * Absent when there is none, because an empty label is not a state.
 */
export function MerchantsHere({
  rows,
  portCode,
  portName,
  nowMs,
  onOpen,
}: {
  rows: readonly PortMerchant[]
  /** The harbour being read — marked in each loop, and what decides whether she is HERE. */
  portCode: string
  portName: (code: string) => string
  nowMs: number
  onOpen: (fleetId: string) => void
}) {
  if (rows.length === 0) return null
  return (
    <SheetSection heading="Merchants" data-testid="port-merchants">
      {rows.map((t, i) => (
        <Row
          key={t.id}
          label={
            <span className="block min-w-0">
              <span className="block truncate">{`${t.company} · ${t.name}`}</span>
              <span className="block truncate text-t-caption text-ink-faint">
                {merchantLine(t, portName, nowMs)}
              </span>
            </span>
          }
          value={
            // QUIETER WHEN SHE IS NOT IN THIS HARBOUR: the hulls alongside read in full ink and the
            // ones elsewhere on their loop recede, which is the whole list's hierarchy in one token.
            <span
              className={t.port === portCode ? undefined : 'text-ink-faint'}
              data-testid="port-merchant-doing"
            >
              {DOING[t.doing]}
            </span>
          }
          chevron
          onClick={() => onOpen(t.id)}
          hairline={i < rows.length - 1}
          data-testid="port-merchant-row"
        >
          {/* HER LOOP, with this harbour standing out of it — the same `→` the merchant sheet uses,
              and the codes come served in sailing order so nothing is sorted here. */}
          <span className="block truncate text-t-caption text-ink-faint" data-testid="port-merchant-loop">
            {t.stops.map((code, n) => (
              <span key={`${code}-${n}`} className={code === portCode ? 'text-ink' : undefined}>
                {n > 0 ? ' → ' : ''}
                {portName(code)}
              </span>
            ))}
          </span>
        </Row>
      ))}
    </SheetSection>
  )
}
