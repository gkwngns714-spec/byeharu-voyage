// ═══════════════════════════════════════════════════════════════════════════════════════════════
// WHO IS DRINKING HERE TODAY? — asked, and deliberately not refreshable.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// What is different about this read is WHY the answer is stable: `world.inn` derives the room
// from (officer, port, day, world secret), so asking again gives the same faces. That is the
// point — an officer who could be re-rolled by reloading would make the good ones free, and the
// owner asked for the good ones to be rare.
//
// It still re-asks on every world read so the room re-reads after an order (signing somebody
// changes whether she is offered), but nothing about the READ can change who is in it. The
// mechanism (and why the last room stays on screen while it re-asks) is useServedRead.ts.

import { worldInn } from '../lib/rpc'
import type { InnView } from '../lib/rpc'
import { useServedRead, type ServedRead } from './useServedRead'

export type InnState = ServedRead<InnView>

export function useInn(portId: string | null): InnState {
  return useServedRead(portId, () => worldInn(portId as string))
}
