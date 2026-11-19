// Types for build-land-migration.mjs — hand-written, as build-image.d.mts is: the module is plain JavaScript run by Node, and
// tests/land.data.spec.ts still gets a checked surface to call.

export interface LandRow {
  code: string
  skill: string
  kind: 'gather' | 'make' | 'fight'
  level: number
  seconds: number
  xp: number
  ground: string
  tool: string
  ord: number
}

export const LADDERS: Record<string, { ground: string; tool: string; goods: Array<[number, string]> }>
export function payAt(level: number): number
export function worthAt(level: number): number
export const FASTEST: { top: number; levelSpeedPct: number; toolPct: number; crowdMaxPct: number; yieldPct: number }
export function fastestTurn(seconds: number): number
export function fastestHour(seconds: number): number
export function jobFigures(level: number, base: number, target?: number): { seconds: number; xp: number }
export function landRows(): LandRow[]
export function valuesBlock(): string

// 0458 (L1c): the mules, rare finds, and the guard over both
export interface DropRow {
  action: string
  good: string
  one_in: number
  ord: number
}
export const MULES: Array<{ packs: number; price: number }>
export function fastestHourPacked(seconds: number, packs: number, march: number): number
export const FIND_ONE_IN: number
export function findOneIn(jobSeconds: number, findTarget: number): number
export function fastestFindsHour(jobSeconds: number, oneIn: number): number
export function dropRows(): DropRow[]
export function dropsBlock(): string
