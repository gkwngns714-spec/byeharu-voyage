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

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE DESK'S SLOT — where a tray stands when it is opened INSIDE the COMMAND desk (2026-10-19).
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// The owner, 2026-10-19: *"when pressing plans, city, invest, i want the screen of the original command tab
// to stay same, meaning no pop ups or no new screen, but reloading on the same page."* The desk's faces
// compose the city's buildings, the Town Hall and the plan builder, and each of those opens its act as a
// Tray — by default `docked`: fixed at the bottom edge of a phone, a side panel over the right of a wide
// glass. Inside the desk that is a pop-up. So the desk PROVIDES a slot, and a docked tray under it stands
// there instead, as a `pane` (no handle, no shadow, in flow):
//   · `el` set — the desk's right pane on a wide glass (the ticket pane): the tray is portalled into it;
//   · `el: null` — a phone: the tray stands in flow, where its caller placed it, inside the face.
// Every tray composes `Tray`, so this is read in ONE place (Tray.tsx), plus the one panel whose own
// contents differ at a bottom-edge peek (ManifestPanel). No building learns about the desk. A tray that
// names its own mode (the map's 'side-next', the desk's own 'pane') is not redirected.
export interface TraySlot {
  el: HTMLElement | null
}
export const DeskTraySlot = createContext<TraySlot | null>(null)

/** The desk's slot, when this tray is opened inside the COMMAND desk; null elsewhere. */
export function useTraySlot(): TraySlot | null {
  return useContext(DeskTraySlot)
}
