import { createContext, useContext } from 'react'

// THE PAGE SAYS IT IS A PAGE (2026-11-02, owner row 267).
//
// A `Sheet layout="page"` (screenLayout.ts "THE PAGE") has a side column — the tray's column — and a docked `Tray` opened from
// anywhere inside it must stand over THAT column (the same x, the same width), not where the old wide glass keeps its tray (the
// right edge of a 75-rem pair, `trayDockWideClass`). The Tray cannot ask the page by prop (it is opened from a chart, a row, a
// card, five levels down), so the page SAYS so by context, as `InTray` does for what stands in a tray: one provider (the Sheet),
// one reader (the Tray). Every screen that is not a page reads `false` and docks exactly as it always did.
//
// In its own file rather than Sheet.tsx: the react-refresh rule keeps a component file to components, and a context is not one.
export const InPage = createContext(false)

/** True inside a `Sheet layout="page"`. */
export function useInPage(): boolean {
  return useContext(InPage)
}
