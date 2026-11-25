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
export interface Pace { top: number; levelSpeedPct: number; toolPct: number; crowdMaxPct: number; yieldPct: number }
export const FASTEST: Pace
export function fastestTurn(seconds: number, pace?: Pace): number
export function fastestHour(seconds: number, pace?: Pace): number
export function jobFigures(level: number, base: number, target?: number, pace?: Pace): { seconds: number; xp: number }
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

// 0461 (L2): the smith's make jobs, by the same rule at the fastest make pace
export interface SmithRow {
  code: string
  skill: string
  kind: 'make'
  level: number
  seconds: number
  xp: number
  ord: number
}
export const FASTEST_MAKE: Pace
export const MAKERS: Record<string, { goods: Array<[number, string]> }>
export function smithRows(): SmithRow[]
export function smithBlock(): string

// 0531: the wood, by the same rule, with no tool
export const FASTEST_WOOD: Pace
export const WOODS: Record<string, { ground: string; goods: Array<[number, string]> }>
export function woodRows(): Array<Omit<LandRow, 'tool'>>
export function woodBlock(): string
