import { worldNationRace, type NationRaceView } from '../lib/rpc'
import { useServedRead, type ServedRead } from './useServedRead'
import { useWorld } from './worldStore'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE COUNTRY RACE (0484, docs/design/roadmap-2026-11-23.md slice 15) — world.nation_race(): this week's countries (the contested cities
// each leads, its points, its place), each contested city's leader, her own points and place, her title, last week's winner. ONE READ,
// shared by HQ's bridge and the map's Race layer (one key in the cache): asked when either opens and when one of her fleets acts (a sale
// or a request moves the race); never on the beat. Dark it answers {on: false} after one knob read, kept a minute.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const DARK_MS = 60_000
const LIT_MS = 60_000

/** The read, lit for her company; else null (dark, signed out, a merchant, unread). */
export function litRace(v: NationRaceView | null): Extract<NationRaceView, { company: true }> | null {
  return v && v.on && v.company ? v : null
}

export function useNationRace(): ServedRead<NationRaceView> {
  const company = useWorld((s) => s.player?.id ?? null)
  const fleets = useWorld((s) => s.fleets)
  const question = company === null ? null : `${company}:${fleets.map((f) => `${f.id}.${f.version}`).join(',')}`
  return useServedRead<NationRaceView>(company, () => worldNationRace(), {
    question,
    trigger: 0,
    name: 'nation_race',
    freshMs: (v: NationRaceView) => (v.on && v.company ? LIT_MS : DARK_MS),
  })
}
