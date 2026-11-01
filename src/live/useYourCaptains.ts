import { useState } from 'react'
import type { TrayDetent } from '../components/ui'
import { worldCaptains } from '../lib/rpc'
import type { YourCaptain } from '../lib/rpc'
import { useServedRead } from './useServedRead'

// YOUR CAPTAINS, READ ONCE AND HELD WITH THE ONE THAT IS OPEN — what the YOU screen composes its panel from (2026-11-02).
//
// The roster used to be ONE component that drew its own section AND its own tray. The unfold laws (docs/dev-log/2026-11-01-ui-unfold.md,
// U2) put the rows INSIDE the screen's one list panel and the tray OUTSIDE it, a sibling of the panel — a tray inside a scroller is the
// defect those laws name. So the face is two parts that share ONE read and ONE open captain: this hook (a `.ts` file, so
// react-refresh keeps YourCaptains.tsx component-only), and `CaptainRows` / `CaptainTray` in YourCaptains.tsx.
//
// The read is the same one it always was: `world.captains` on the world's beat, kept across a tab switch (useServedRead).

const NONE: readonly YourCaptain[] = []

export function useYourCaptains() {
  const { view } = useServedRead('captains', () => worldCaptains(), { name: 'worldCaptains' })
  const [open, setOpen] = useState<string | null>(null)
  const [detent, setDetent] = useState<TrayDetent>('half')
  const captains = view?.captains ?? NONE
  const shown = captains.find((c) => c.code === open) ?? null
  return {
    captains,
    /** The captain whose tray is up, by code — so the tray survives a world read that serves a new object. */
    shown,
    detent,
    /** A press on a row: her tray opens at half. */
    press: (code: string) => {
      setDetent('half')
      setOpen(code)
    },
    /** The tray's own detent ladder; `closed` closes it. */
    move: (next: TrayDetent) => (next === 'closed' ? setOpen(null) : setDetent(next)),
  }
}

/** What `useYourCaptains` hands the two parts of the face. */
export type YourCaptainsFace = ReturnType<typeof useYourCaptains>
