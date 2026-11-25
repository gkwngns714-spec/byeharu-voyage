import type { FleetJobParams } from '../../../lib/rpc'

// The settings of a fixed job (0516): the boxes, what stands in them, and what a press sends.

/** The boxes in their order; `sale`: only while the run ends in a sale. */
export const SETTINGS = [
  { code: 'under', sale: false },
  { code: 'over', sale: true },
  { code: 'crew', sale: false },
  { code: 'days', sale: false },
  { code: 'stop_profit', sale: true },
  { code: 'stop_damage', sale: false },
] as const satisfies readonly { code: keyof FleetJobParams; sale: boolean }[]

type Code = (typeof SETTINGS)[number]['code']
export type JobSettingsDraft = Partial<Record<Code, string>>

/** The boxes as her running job has them. */
export function draftOf(p: FleetJobParams | null | undefined): JobSettingsDraft {
  const out: JobSettingsDraft = {}
  for (const s of SETTINGS) if (typeof p?.[s.code] === 'number') out[s.code] = String(p[s.code])
  return out
}

/** What the press sends: each box with a number, as typed (a sale's settings only while the run ends in a sale). */
export function settingsOf(d: JobSettingsDraft, sells: boolean): FleetJobParams {
  const out: FleetJobParams = {}
  for (const s of SETTINGS) {
    const v = (d[s.code] ?? '').trim().replaceAll(',', '')
    if (v !== '' && Number.isFinite(Number(v)) && (sells || !s.sale)) out[s.code] = Number(v)
  }
  return out
}
