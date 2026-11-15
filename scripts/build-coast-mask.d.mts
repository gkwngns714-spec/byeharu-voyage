// Types for build-coast-mask.mjs — hand-written, so a spec can rebuild the mask in-process and hold
// the shipped file to it.
import type { CoastMaskPayload } from '../src/lib/sea/coastMask.ts'

export declare const MASK_FILE: string
export declare const SUB: number
export declare function buildCoastMask(raster: {
  cols: number
  rows: number
  cell_deg: number
  bits_per_cell: number
  cells_base64: string
}): CoastMaskPayload
