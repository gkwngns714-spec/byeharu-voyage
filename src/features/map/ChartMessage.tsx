import { Note } from '../../components/ui'
import type { Refusal } from '../../lib/rpc'

// THE CHART'S SEA BEFORE THE CHART — opening, or the reason it could not open.
//
// A failure is rendered, never spun on: the refusal arrives with a sentence a player can read
// (DESIGN §F.5) and printing it is the whole handling; the code goes to console.debug through
// `Note`, never to the glass. The opening is the chart's own sea with nothing on it but the
// loading meter MapScreen lays over it (owner row 255: the percentage of real work done), so the
// tab does not flash a different surface before settling — and never an endless spinner, because
// the store's phase always resolves. Until the drive audit (2026-11-08, D6) this was one plain
// line, "opening the chart…", and the map had no percentage.
export function ChartMessage({ refusal }: { refusal: Refusal | null }) {
  return (
    <div className="bv-sea flex h-full w-full items-center justify-center p-gutter" data-testid="map-chart">
      {refusal && (
        <Note tone="danger" code={refusal.code} figures={refusal.figures} className="max-w-sm" data-testid="map-fatal">
          {refusal.sentence}
        </Note>
      )}
    </div>
  )
}
