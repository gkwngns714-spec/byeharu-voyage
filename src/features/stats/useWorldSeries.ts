import { worldStatsOverview, type StatsOverview } from '../../lib/rpc'
import { useLiveRead } from '../../live/liveRead'
import { useChartSpan } from '../../store/chartSpan'

// The world's series, for the faces that draw a general graph (WorldSeries.tsx): the Overview's own read, under its own subject.
const HOURS = 24 // the Overview's own window — the subject 'stats:overview' names ONE question

export function useWorldSeries(): StatsOverview | null {
  const { span } = useChartSpan()
  return useLiveRead<StatsOverview>('stats:overview', () => worldStatsOverview(HOURS, span), span).view
}
