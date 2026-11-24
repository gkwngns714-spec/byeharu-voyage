import type { ReactNode } from 'react'

// A FACE HANDS ITS PARTS TO ITS HOST, AND THE HOST LAYS THEM OUT (2026-10-19; here since 2026-11-24, H3 `desk-into-hq`).
// The Trade desk and the Office were two hosts with three panes; they are gone, and the one host left is HQ's sheet
// (src/app/HqSheet.tsx), which stands the parts one under the other. Invest and Report are the faces that still speak this shape.

export interface DeskParts {
  /** The face's test id (desk-invest, desk-report), on its frame. */
  testid: string
  list: ReactNode
  main: ReactNode
  side?: ReactNode
  /** The order the parts stand in (default list, main, side). */
  order?: readonly ('list' | 'main' | 'side')[]
  /** `data-*` marks on the frame element, for a read the face makes that draws nothing while pending. */
  marks?: Record<`data-${string}`, string>
}

/** How a host lays a face out: the one decision a face does not make. */
export type DeskLayout = (parts: DeskParts) => ReactNode
