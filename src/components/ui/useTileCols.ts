import { useEffect, useState } from 'react'
import { TILE_FIELD, tileFieldCols } from './tileLayout'

/**
 * How many tiles stand in one row of a tile field, right now.
 *
 * THE SAME NUMBER `tileFieldClass()` DRAWS, read in JavaScript — see tileLayout.ts's header for why
 * a field has to be said twice and why both spellings come off one table. A caller needs this only
 * when it must know where a ROW ENDS: an unfolding panel has to land AFTER the whole row holding
 * the pressed tile, or it lands mid-row and shoves the tiles beside it around, and nothing may move
 * when a fold opens (docs/OWNER_REQUESTS.md rows 15/25).
 *
 * It watches every step of the field, not one query: the hand-written version this replaces
 * (features/command/ArgPickers.tsx, harbour tiles) watched a single `(min-width: 640px)` and so
 * could only ever answer 2 or 3, while the CSS beside it went to 4.
 */
export function useTileCols(): number {
  const [cols, setCols] = useState(() =>
    typeof window === 'undefined' ? TILE_FIELD[0].cols : tileFieldCols(window.innerWidth),
  )
  useEffect(() => {
    const read = () => setCols(tileFieldCols(window.innerWidth))
    // The 0px step is the floor and matches everything, so it carries no query of its own.
    const queries = TILE_FIELD.filter((s) => s.minWidth > 0).map((s) =>
      window.matchMedia(`(min-width: ${s.minWidth}px)`),
    )
    queries.forEach((q) => q.addEventListener('change', read))
    read()
    return () => queries.forEach((q) => q.removeEventListener('change', read))
  }, [])
  return cols
}
