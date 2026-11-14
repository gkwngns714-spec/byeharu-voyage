import { useMemo } from 'react'
import type { Point, ViewBox } from '../lib/geo'
import type { CoastPaths } from './fineCoastBuild'
import { landfallPorts } from './landfall'
import type { MapPort } from './mapTypes'
import type { BackdropState } from './useBackdrop'
import { useFineCoast } from './useFineCoast'

// THE SHORE ON THE GLASS, AND THE HARBOURS SET ON IT (2026-11-14).
//
// The coast a chart draws depends on its zoom (./useFineCoast.ts): the 110m world when wide, finer
// tiles close in. A harbour's mark is set on the DRAWN shore (./landfall.ts), so it has to be set on
// whichever coast that is: a mark left on the 110m shore stood up to 8 nautical miles from the fine
// one (Tainan inland, Ceuta out at sea).
//
// ONE PLACE DECIDES BOTH. This hook picks the coast and runs the one landfall against it, in the
// same render, and hands back the coast, the ports and the islets together. So the mark, its name,
// its tap target, its roads' dotted line and a docked fleet's glyph move in the very frame the coast
// under them changes, and by no more than the coast itself does. Wide, it returns the backdrop's own
// three, untouched.
//
// A PICTURE ONLY: the served coordinate, the roadstead, every route and distance are the server's and
// are not read differently here. A harbour off the fine sheet keeps its place on the world coast.

export interface ChartShore {
  /** The coast to draw: the fine tiles' paths, or the 110m world's, or null before either. */
  readonly coast: CoastPaths | null
  /** The whole port table, every harbour set on that coast. */
  readonly ports: readonly MapPort[]
  /** Harbours that coast has no land for: a speck is drawn under each. */
  readonly islets: readonly Point[]
}

export function useChartShore(backdrop: BackdropState, box: ViewBox, unitsPerPx: number): ChartShore {
  const fine = useFineCoast(box, unitsPerPx)
  const { served, ports, islets, coast } = backdrop
  const landed = useMemo(() => (fine ? landfallPorts(served, fine.shore, { ports, islets }) : null), [fine, served, ports, islets])
  return landed && fine ? { coast: fine, ports: landed.ports, islets: landed.islets } : { coast, ports, islets }
}
