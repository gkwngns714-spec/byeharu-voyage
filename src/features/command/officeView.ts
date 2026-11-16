// THE OFFICE — the tab for what a company keeps ashore, apart from trading (owner, 2026-11-16: *"in trade, there are city
// invest report and levels, which aren't that related to trade. they should have separate tab like map you stats etc."*).
//
// THE FACES, EACH DESCRIBED ONCE: City · Invest · Report. They were the Trade desk's second to fourth faces and MOVED to this
// tab whole (their files stay in features/command/city, invest, report: OfficeScreen.tsx composes them in the desk's own shell);
// the desk keeps Trade alone, and Levels went to the You page, where the
// company's levels already stood. The ORDER is the strip's. Which face is up, and which building of the City face, are
// session state for portView's old reason: a face you turned to is a thing you are doing.

import { create } from 'zustand'
import { createJSONStorage, persist } from 'zustand/middleware'
import type { PortFace } from '../../live/cityFaces'
import { t } from '../../lib/i18n'

/** The Office's route: the one spelling every door to it uses. */
export const OFFICE_TAB = '/office'

export const OFFICE_FACES = [
  { id: 'city', get label() { return t('command.f_city') } },
  { id: 'invest', get label() { return t('command.f_invest') } },
  { id: 'report', get label() { return t('command.f_report') } },
] as const

export type OfficeFace = (typeof OFFICE_FACES)[number]['id']

export interface OfficeViewState {
  face: OfficeFace
  /** The City face's building (live/cityFaces.ts); one that the city lacks falls back to its first. */
  cityFace: PortFace
  turnTo: (face: OfficeFace) => void
  setCityFace: (face: PortFace) => void
}

export const useOfficeView = create<OfficeViewState>()(
  persist(
    (set) => ({
      face: 'city',
      cityFace: 'market',
      turnTo: (face) => set({ face }),
      setCityFace: (cityFace) => set({ cityFace }),
    }),
    {
      name: 'byeharu-voyage.office.v1',
      storage: createJSONStorage(() => sessionStorage),
      partialize: (s) => ({ face: s.face, cityFace: s.cityFace }),
      // A stale or corrupt byte opens a face that EXISTS.
      merge: (persisted, current) => {
        const p = (persisted ?? {}) as Partial<OfficeViewState>
        return {
          ...current,
          face: OFFICE_FACES.some((f) => f.id === p.face) ? (p.face as OfficeFace) : 'city',
          cityFace: typeof p.cityFace === 'string' ? p.cityFace : 'market',
        }
      },
    },
  ),
)

/** THE ONE DOOR TO A BUILDING OF THE CITY FACE from anywhere else (the yard's hire and workshop links, an old `/port` link):
 *  turns the Office to City at that building and returns the route to navigate to. */
export function openOfficeCity(building?: PortFace): string {
  const s = useOfficeView.getState()
  if (building) s.setCityFace(building)
  s.turnTo('city')
  return OFFICE_TAB
}
