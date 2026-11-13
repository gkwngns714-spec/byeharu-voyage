import type { MapFleet } from '../../chart'
import type { ArmadaView } from '../../lib/rpc'

// AN ARMADA AT SEA IS ONE MARK (0367, docs/ARMADA.md section 8; owner row 323). Her fleets sail one course at one speed, so on the chart they would be marks drawn on top of
// each other. This folds them: the first of her fleets that is at sea keeps its mark, takes the armada's name and carries EVERY hull of the fleets sailing with her (the
// chart's own hull group draws them as one line of ships, as it draws any fleet of several); the others are not drawn. Nothing is computed: names and hull classes are the
// served ones, and the position is the lead fleet's served position.
//
// In port her fleets are drawn as they always were (each lies at the quay), and an armada with fewer than two fleets at sea is left alone.

export function armadaMarks(fleets: readonly MapFleet[], armadas: readonly ArmadaView[]): readonly MapFleet[] {
  if (armadas.length === 0) return fleets
  const drop = new Set<string>()
  const lead = new Map<string, { name: string; hulls: (string | null)[] }>()
  for (const a of armadas) {
    const atSea = a.fleets.flatMap((id) => fleets.find((f) => f.id === id && f.kind === 'sailing') ?? [])
    if (atSea.length < 2) continue
    lead.set(atSea[0].id, { name: a.name, hulls: atSea.flatMap((f) => f.hulls ?? [null]) })
    for (const f of atSea.slice(1)) drop.add(f.id)
  }
  if (lead.size === 0) return fleets
  return fleets.filter((f) => !drop.has(f.id)).map((f) => (lead.has(f.id) ? { ...f, ...lead.get(f.id) } : f))
}
