// ═══════════════════════════════════════════════════════════════════════════════════════════════
// WHAT CAN BE FORGED HERE, AND FROM WHAT? — asked, not worked out.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// "Is every ingredient ashore in its quantity?" is a rule cmd.forge_good enforces, and a client
// that worked it out from a recipe and a shed would be a second copy of that rule with its own way
// of drifting. world.goods_forge answers; this hook carries the answer.
//
// Re-asked whenever the world is read again — a forge spends ingredients and lands a product, and
// the next answer must say so. The mechanism (and why the last answer stays on screen while it
// re-asks) is useServedRead.ts.

import { worldGoodsForge } from '../lib/rpc'
import type { ForgeView } from '../lib/rpc'
import { useServedRead, type ServedRead } from './useServedRead'

export type ForgeState = ServedRead<ForgeView>

export function useForge(portId: string | null): ForgeState {
  return useServedRead(portId, () => worldGoodsForge(portId as string))
}
