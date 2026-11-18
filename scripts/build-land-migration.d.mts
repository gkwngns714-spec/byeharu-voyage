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
export function jobFigures(level: number, base: number): { seconds: number; xp: number }
export function landRows(): LandRow[]
export function valuesBlock(): string
