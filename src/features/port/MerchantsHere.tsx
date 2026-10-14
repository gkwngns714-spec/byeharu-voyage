import { SheetSection } from '../../components/ui'
import { MerchantRow } from '../../live/MerchantRow'
import { merchantLine } from '../../live/merchantLine'
import type { PortMerchant } from '../../lib/rpc'

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
// from where her fleet is (`public.merchant_doing_at`, migration 0104); her `level` is the server's
// too (0113). The row — name, company, level, the word or the countdown — is `src/live/MerchantRow`,
// the SAME row the chart's city tray prints (2026-10-13), and the words are spelled once in
// `src/live/merchantWords.ts`, so PORT and MAP cannot drift. The line beside her name is
// `merchantLine`'s, the one the sheet's head prints.
//
// This section adds the one thing a quay wants and a chart does not: HER LOOP, as a second line.

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
    <SheetSection heading="Merchants" surface data-testid="port-merchants">
      {rows.map((t, i) => (
        <MerchantRow
          key={t.id}
          m={t}
          here={t.port === portCode}
          detail={merchantLine(t, portName, nowMs)}
          nowMs={nowMs}
          onOpen={onOpen}
          hairline={i < rows.length - 1}
        >
          {/* HER LOOP, with this harbour in it — the fact that put her on this list. Codes are
              the server's; the names are the world's. */}
          <span className="block truncate text-t-caption text-ink-faint" data-testid="merchant-row-loop">
            {t.stops.map(portName).join(' → ')}
          </span>
        </MerchantRow>
      ))}
    </SheetSection>
  )
}
