import { worldLogbook, type LogbookView } from '../../lib/rpc'
import { useServedRead } from '../../live/useServedRead'
import { useWorld } from '../../live/worldStore'

/** The newest arrival or sale she has (its instant): the logbook can only have moved when one of these lands. */
const lastFirstAt = (s: ReturnType<typeof useWorld.getState>): number =>
  s.events.reduce((m, e) => (e.kind === 'VOYAGE_REPORT' || e.kind === 'SOLD' ? Math.max(m, Date.parse(e.at) || 0) : m), 0)

/** The ONE logbook read (`world.logbook()`, 0478), cached by name: You's door and the page share it. It is NOT asked on every world
 *  beat (the page's read is a few kilobytes of lists): only when a new arrival or sale of hers lands, and kept until then. */
export function useLogbook() {
  const trigger = useWorld(lastFirstAt)
  return useServedRead<LogbookView>('logbook', () => worldLogbook(), { name: 'worldLogbook', trigger, freshMs: 10 * 60_000 })
}

/** The served view when it is lit for her company, else null (dark, signed out, or not yet read). */
export function readyLogbook(v: LogbookView | null): Extract<LogbookView, { company: true }> | null {
  return v && v.on && v.company ? v : null
}
