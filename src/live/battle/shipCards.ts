import type { BattleShipCard } from '../../lib/rpc'

// THE SHEET'S HULLS, READ (0450): the two small readings the battle screen makes of `world.battle_ticks().ships`. Pure.

/** A side's best level (what the server's run chance reads for a side), or null when no hull of it has a level served. */
export function sideLevel(cards: readonly BattleShipCard[] | undefined): number | null {
  const lv = (cards ?? []).map((c) => Number(c.lv)).filter((n) => Number.isFinite(n) && n > 0)
  return lv.length > 0 ? Math.max(...lv) : null
}

/** What is fitted, as "Name" or "Name ×2", in the server's order. */
export function fittedWords(fit: BattleShipCard['fit']): string[] {
  const count = new Map<string, number>()
  for (const f of fit ?? []) count.set(f.n, (count.get(f.n) ?? 0) + 1)
  return [...count].map(([n, k]) => (k > 1 ? `${n} ×${k}` : n))
}
