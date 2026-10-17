import type { ReactNode } from 'react'
import { IconDisc, Row } from '../components/ui'
import { formatInt } from '../lib/format'
import type { PortMerchant } from '../lib/rpc'
import { GoToLink } from '../chart'
import { whereabouts } from '../domain/fleet'
import { DOING_WORD, levelOf, restEndsAt, restLeft } from './merchantWords'
import { HullCountry } from './HullCountry'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// ONE MERCHANT ON A HARBOUR'S LIST — her name and company, her level, and what she is doing here
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-10-13: *"when i press city, it says how many ships are resting. i want there to
// be a list, showing the total level, and its current time till the resting finishes."*
//
// TWO SCREENS PRINT THIS ROW and that is why it is here and not in either: PORT's "Merchants"
// section (every merchant the harbour concerns, 0104) and the MAP's city tray (the ones lying in
// it). One row, one order of facts, one place the words come from (merchantWords.ts), so the two
// cannot drift — a merchant who reads `Resting · 2 h 14 min` on the chart reads the same on the
// quay. A tap opens the same read-only sheet from both (MerchantSheet.tsx).
//
//   [disc]  Carreira da Guiné                           12          2 h 14 min
//           Casa de Aveiro · 3 ships · <detail>        level          Resting
//
// THE RIGHT-HAND PAIR IS TWO FIGURES, NOT A SENTENCE. Level is a tabular number with its word
// under it; the state is the countdown with the server's word under it while she is held, and
// the word alone otherwise. Nothing here is worked out: `doing` is the server's (0104), `level`
// is the server's (0113), the instant is `next_lap_at`, and the only arithmetic is a subtraction
// from the one shell clock.
export function MerchantRow({
  m,
  here,
  detail,
  nowMs,
  onOpen,
  hairline = true,
  children,
}: {
  m: PortMerchant
  /** She lies in the harbour being read. Elsewhere on her loop she recedes to `ink-3`. */
  here: boolean
  /** One more fact on the caption line — PORT passes her line (`to Kochi · 11m`). */
  detail?: ReactNode
  nowMs: number
  onOpen: (fleetId: string) => void
  hairline?: boolean
  /** A second line under the caption — PORT passes her loop. */
  children?: ReactNode
}) {
  const level = levelOf(m)
  const ends = restEndsAt(m)
  const word = DOING_WORD[m.doing]
  return (
    <Row
      mark={<IconDisc name="ship" tone={here ? 'info' : 'muted'} />}
      label={
        <span className="block min-w-0">
          <span className="block truncate text-t-body text-ink" data-testid="merchant-row-name">
            <GoToLink to={{ kind: 'fleet', id: m.id, where: whereabouts(m) }}>{m.name}</GoToLink>
          </span>
          <span className="block truncate text-t-caption text-ink-faint" data-testid="merchant-row-line">
            {/* 0143 (owner, 2026-10-17): her company's flag before its name. */}
            {m.nation_code && (
              <span data-testid="merchant-row-flag">
                <HullCountry nation={m.nation_code} compact />{' '}
              </span>
            )}
            {m.company}
            {` · ${formatInt(m.ships)} ${m.ships === 1 ? 'ship' : 'ships'}`}
            {detail !== undefined && <> · {detail}</>}
          </span>
        </span>
      }
      value={
        <span className="flex items-start gap-4">
          <Stat figure={level === null ? '—' : formatInt(level)} caption="level" testId="merchant-row-level" />
          {ends !== null ? (
            <Stat figure={restLeft(ends, nowMs)} caption={word} captionTestId="merchant-row-doing" testId="merchant-row-rest" />
          ) : (
            <Stat figure={word} testId="merchant-row-doing" muted={!here} />
          )}
        </span>
      }
      chevron
      hairline={hairline}
      onClick={() => onOpen(m.id)}
      data-testid="merchant-row"
    >
      {children}
    </Row>
  )
}

/** A figure with its word under it, right-aligned — the row's two right-hand facts. */
function Stat({
  figure,
  caption,
  muted = false,
  testId,
  captionTestId,
}: {
  figure: ReactNode
  caption?: ReactNode
  muted?: boolean
  testId?: string
  captionTestId?: string
}) {
  return (
    <span className="flex min-w-12 flex-col items-end">
      <span className={`text-t-body tabular-nums ${muted ? 'text-ink-faint' : 'text-ink'}`} data-testid={testId}>
        {figure}
      </span>
      {caption !== undefined && (
        <span className="text-t-caption text-ink-faint" data-testid={captionTestId}>
          {caption}
        </span>
      )}
    </span>
  )
}
