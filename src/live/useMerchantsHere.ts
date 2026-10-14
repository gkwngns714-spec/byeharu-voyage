// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE MERCHANTS THIS HARBOUR CONCERNS — `world.port_merchants(port)` (0104, owner row 121)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-10-11: *"By clicking the city, i get to see what trading ships started, resting,
// ending etc."*
//
// ── WHY THIS IS A READ OF ITS OWN, AND NOT THE TRAFFIC THE CHART USES ──────────────────────────
// Until now PORT listed the merchants lying at the harbour out of `useWorld(s => s.traffic)` — the
// shell's 3-second beat read, which serves the whole world. Two things it cannot do: it has no
// harbour to be ABOUT (what a merchant is doing is a fact about a PORT, not about a hull), and
// since 0102 it is windowed and capped, so the merchant who is three legs away on her way back
// here — the one the owner's "etc." is about — is exactly the row it drops. So the harbour asks
// its own question when it is opened, and PORT no longer bumps the traffic reader at all: one
// screen, one read, and the beat's read got no bigger (migration 0104's header argues the numbers).
//
// ── A DOORWAY ONTO useServedRead, NOT A SECOND HOOK ────────────────────────────────────────────
// The SUBJECT is the port. A re-read of the same harbour keeps the last list on screen, silently,
// while the next one is on the wire — the beat's re-ask is not `loading` (src/live/useServedRead.ts,
// 2026-09-30) — and a different harbour shows nothing of this one's. Which is what makes this a
// LIVE list rather than a snapshot: the shell's beat re-asks it, so a merchant who sails while the
// city is open stops saying she is in it.
//
// It lives beside the screen that asks it, like `useHaggleState` and `useStepOrder` do, because
// nothing else asks it; the hook it stands on, the sheet it opens and the one line beside a
// merchant's name are all shared (src/live).

import { worldPortMerchants } from '../lib/rpc'
import type { PortMerchants } from '../lib/rpc'
import { useServedRead, type ServedRead } from './useServedRead'

export function useMerchantsHere(portId: string | null): ServedRead<PortMerchants> {
  return useServedRead<PortMerchants>(portId, () => worldPortMerchants(portId as string))
}
