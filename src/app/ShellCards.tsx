import { MasteryToast } from '../live/MasteryUp'
import { ArrivalCard } from './ArrivalCard'
import { AwayCard } from './AwayCard'
import { LaunchOffer } from './LaunchOffer'
import { LevelUpCard } from './LevelUpCard'

// THE SHELL'S CARDS, ONE LIST FOR BOTH FRAMES (H3 `desk-into-hq`, 2026-11-24). They are fixed overlays over the glass, never in the
// flow. Until H3 only the shell (AppShell.tsx) drew them, and HQ, which stands outside the shell in its own frame, drew none: with
// the Trade desk gone HQ is the home screen, and a player standing on it would have had no arrival, level, mastery, away or launch
// card. So the shell and HQ (HqSheet.tsx, HQ's layer host) draw this one list.
export function ShellCards() {
  return (
    <>
      {/* THE ARRIVAL CARD at the glass's foot and, on a return, the WHILE AWAY card at its head (ArrivalCard.tsx, AwayCard.tsx) */}
      <ArrivalCard />
      {/* a level crossed: its own loud card over the glass's middle, which takes no press (LevelUpCard.tsx, roadmap slice 10) */}
      <LevelUpCard />
      {/* a sale raised a good's mastery, with no arrival card to say it (src/live/MasteryUp.tsx, roadmap slice 11) */}
      <MasteryToast />
      <AwayCard />
      {/* a hull joined her fleet: its own fleet on her best route, or stay (LaunchOffer.tsx, the roadmap's slice 6) */}
      <LaunchOffer />
    </>
  )
}
