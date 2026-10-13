import { createContext, useContext } from 'react'

// WHAT STANDS IN A TRAY STEPS UP ONE TONE.
//
// §4.3: "separation is by tone step (`surface` on `bg`, `surface-2` inset on `surface`)". A sheet
// stands on the world (`bg`), so a `Tile` or a grouped section on it is `surface`. A TRAY is itself
// `surface` — and until 2026-10-13 a tile inside one was `surface` on `surface`: no step, no edge,
// an invisible panel. The owner read the merchant sheet and called it *"not good in terms of
// friendliness and style"*; measured, its ships, officers and skills were tiles nobody could see
// the shape of.
//
// So the tray SAYS it is a surface, and the two things that take a tone step read it and step up:
// `Tile` (rest and muted) and `SheetSection surface`. One context, two readers, no prop threaded
// through ShipTile / OfficerTile / SkillTile, and no CSS rule that silently re-points a token. A
// `Segmented` is deliberately NOT a reader: its selected face is `surface` on a `surface-2` track
// by design, and stepping both would erase the selection.
//
// In its own file rather than Tray.tsx: the react-refresh rule keeps a component file to
// components, and a context is not one.
export const InTray = createContext(false)

/** True inside a `Tray` — a tone step up for whatever is drawn on it. */
export function useInTray(): boolean {
  return useContext(InTray)
}
