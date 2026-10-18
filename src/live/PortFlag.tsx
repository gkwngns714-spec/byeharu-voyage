import { Flag, type FlagSize } from '../components/ui'
import { nationNameOf, portNationOf, useWorld } from './worldStore'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A CITY'S FLAG BESIDE ITS NAME (the owner, 2026-10-18: "beside the name show flag that are
// influenced by") — the flag of the nation whose influence holds the harbour today.
//
// WHERE THE FACT COMES FROM: `portNationOf` (worldStore), the one client reading of
// `world.allegiance`, which serves `public.port_nation` (0143-0148). No influence rule lives here:
// the server says who holds the city, this draws that nation's `Flag`. Until the first read lands,
// or for a harbour no country holds, it draws NOTHING — never a guessed flag.
//
// CALLERS: the city tray's name (SendFleet), the Port tab's title (PortScreen), your fleet tray's
// "In port" / "Bound for" (VoyageTray). The chart's names draw the same flags from the same
// reading through `usePortFlags`, because a chart label is SVG, not HTML.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

export function PortFlag({ code, size = 'body' }: { code: string; size?: FlagSize }) {
  const allegiance = useWorld((s) => s.allegiance)
  const nationByCode = useWorld((s) => s.nationByCode)
  const nation = portNationOf(allegiance, code)?.nation
  if (!nation) return null
  return <Flag code={nation} name={nationNameOf(nationByCode, nation)} size={size} />
}
