import { useMemo } from 'react'
import { worldGoodsMastery, type GoodMastery, type GoodsMasteryView, type LedgerEvent, type MasterySale } from '../lib/rpc'
import { useServedRead } from './useServedRead'
import { useWorld } from './worldStore'

// GOODS MASTERY (0479, roadmap 2026-11-23 slice 11; Melvor's mastery per item). Each good she sells has a ladder 1-10 the server keeps
// (public.goods_mastery): each level a slightly better sale price and a bigger day's allowance, which the server's own quotes already
// carry, so no figure here is worked out. The client draws the level: a ring per good on the logbook's Goods page, her specialty on
// You's plate, the good's name in gold at the top (the Trade desk's cards, the From here tiles, the arrival card's sale line), and a
// chip or a toast when a sale raises it. Dark the read is {on: false} and none of it is drawn.

/** The newest sale she has (its instant): her ladder can only have moved when one lands. */
const lastSaleAt = (s: ReturnType<typeof useWorld.getState>): number =>
  s.events.reduce((m, e) => (e.kind === 'SOLD' ? Math.max(m, Date.parse(e.at) || 0) : m), 0)

/** The ONE mastery read (`world.goods_mastery()`), cached by name: every face shares it. Asked again only when a new sale of hers
 *  lands, never on the world's beat. */
export function useGoodsMastery() {
  const trigger = useWorld(lastSaleAt)
  return useServedRead<GoodsMasteryView>('goods_mastery', () => worldGoodsMastery(), { name: 'worldGoodsMastery', trigger, freshMs: 10 * 60_000 })
}

type Ready = Extract<GoodsMasteryView, { company: true }>

/** The served view when it is lit for her company, else null (dark, signed out, or not yet read). */
export function readyMastery(v: GoodsMasteryView | null): Ready | null {
  return v && v.on && v.company ? v : null
}

export interface MasteryLevels {
  /** Her mastery of a good by CODE, or null when she has not sold it (or the ladder is dark). */
  of: (code: string) => GoodMastery | null
  /** Whether a good stands at the top of its ladder: its name is drawn in gold. */
  mastered: (code: string) => boolean
  /** The ladder's top (10 as served), 0 while dark. */
  top: number
  /** Her specialty: her highest good, or null. */
  specialty: GoodMastery | null
}

const NONE: MasteryLevels = { of: () => null, mastered: () => false, top: 0, specialty: null }

/** Her ladder by good, from the one read. Dark: nothing is mastered and no level is known. */
export function useMasteryLevels(): MasteryLevels {
  const v = readyMastery(useGoodsMastery().view)
  return useMemo(() => {
    if (!v) return NONE
    const by = new Map(v.goods.map((g) => [g.good, g]))
    return {
      of: (code) => by.get(code) ?? null,
      mastered: (code) => (by.get(code)?.level ?? 0) >= v.top,
      top: v.top,
      specialty: v.specialty,
    }
  }, [v])
}

const isObj = (x: unknown): x is Record<string, unknown> => typeof x === 'object' && x !== null && !Array.isArray(x)
const num = (x: unknown): number | null => (typeof x === 'number' && Number.isFinite(x) ? x : null)

/** A SOLD event's mastery word (the level after the sale, and whether it rose), or null when it carries none (dark, a merchant). */
export function saleMasteryOf(e: LedgerEvent): MasterySale | null {
  if (e.kind !== 'SOLD' || !isObj(e.payload.mastery)) return null
  const m = e.payload.mastery
  const level = num(m.level)
  if (typeof m.good !== 'string' || m.good === '' || level === null) return null
  return {
    good: m.good,
    level,
    from: num(m.from) ?? 0,
    units: num(m.units) ?? 0,
    at: num(m.at),
    next: num(m.next),
    up: m.up === true,
  }
}
