import { Note } from '../../components/ui'
import type { Refusal } from '../../lib/rpc'

// THE CHART'S SEA WITH ONE LINE ON IT — opening, or the reason it could not open.
//
// A failure is rendered, never spun on: the refusal arrives with a sentence a player can read
// (DESIGN §F.5) and printing it is the whole handling; the code goes to console.debug through
// `Note`, never to the glass. The opening is one quiet line on the chart's own sea, so the tab does
// not flash a different surface before settling — and never an endless spinner, because the
// store's phase always resolves.
export function ChartMessage({ refusal }: { refusal: Refusal | null }) {
  return (
    <div className="bv-sea flex h-full w-full items-center justify-center p-gutter" data-testid="map-chart">
      {refusal ? (
        <Note tone="danger" code={refusal.code} className="max-w-sm" data-testid="map-fatal">
          {refusal.sentence}
        </Note>
      ) : (
        <p className="text-t-caption text-ink-faint" data-testid="map-loading">
          opening the chart…
        </p>
      )}
    </div>
  )
}
