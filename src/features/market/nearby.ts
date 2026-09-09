// WHICH HARBOURS THE FIELD OFFERS — pure, no React, and never all of them.
//
// docs/UI_DIRECTION.md §2 item 8, measured: the port picker opened onto 238 chips and the page
// grew to 5,566px, "the search's failure mode made permanent". §6 redraws it as "a `Field` at the
// top with the nearest ten as chips under it while typing", and this is the one place that decides
// which ten.
//
// NEAREST BY SEA, from where she lies. `world.reach(port)` (0039) serves the sailed distance from
// one place to every harbour — the same figures the SAIL picker and the map's `Sail here` print —
// so the chips are ordered by how far the fleet would actually have to go to trade at that price,
// which is the only sense in which one distant market is "nearer" than another. A harbour the reach
// does not name (unreachable from here, or the read not landed yet) sorts after every one it does,
// by name, so the list is still whole while the distances arrive.
//
// THE ANCHOR STANDS FIRST, always: the harbour the fleet is in or bound for is one tap away from
// any search, which is what the old picker's pinned "Your fleet" chip did in a row of its own.
//
// TYPING NARROWS, IT NEVER WIDENS. Ten chips when the field is empty, at most ten when it is not —
// and the matcher is `foldedMatch`, the one folding both pickers already share, so `sao` finds
// São Vicente here exactly as it does on COMMAND.

import type { ReachPayload, SnapshotPort } from '../../lib/rpc'
import { fold, foldedMatch } from '../../lib/text'

/** How many chips the field ever shows. §6: "the nearest ten". */
export const NEAR_PORTS = 10

export function nearbyHarbours(
  ports: readonly SnapshotPort[],
  /** The sailed distances from the anchor, or undefined while that read is in flight. */
  reach: ReachPayload | undefined,
  /** The harbour she is in or bound for, by CODE — pinned first, whatever the query. */
  anchor: string | null,
  query: string,
  limit = NEAR_PORTS,
): SnapshotPort[] {
  const needle = fold(query.trim())
  const nm = (p: SnapshotPort): number => reach?.reaches[p.code] ?? Number.POSITIVE_INFINITY
  return ports
    // Harbours only (0036): a SEA PLACE keeps no book, so it has no prices to read.
    .filter((p) => p.kind === 'HARBOUR')
    .filter((p) => foldedMatch(needle, p.name, p.code, p.region))
    .sort(
      (a, b) =>
        Number(b.code === anchor) - Number(a.code === anchor) ||
        nm(a) - nm(b) ||
        a.name.localeCompare(b.name),
    )
    .slice(0, limit)
}
