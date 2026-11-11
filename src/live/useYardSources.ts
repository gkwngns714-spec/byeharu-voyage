// ═══════════════════════════════════════════════════════════════════════════════════════════════
// WHERE IS EACH MATERIAL HAD NEAREST? — asked, not worked out (0349, world.yard_sources).
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// Asked when a hull's sheet opens, once per (yard, hull): who sells a good and who makes a fitting are
// the city rosters and workstations, which a beat of the world does not move, so the answer is not
// re-asked on the beat (trigger 0) and is kept for the session.

import { worldYardSources } from '../lib/rpc'
import type { YardSources } from '../lib/rpc'
import { SESSION_MS } from '../store/resourceCache'
import { useServedRead, type ServedRead } from './useServedRead'

export function useYardSources(portId: string, classCode: string | null): ServedRead<YardSources> {
  return useServedRead(
    classCode === null ? null : `${portId}:${classCode}`,
    () => worldYardSources(portId, classCode as string),
    { name: 'worldYardSources', trigger: 0, freshMs: SESSION_MS },
  )
}
