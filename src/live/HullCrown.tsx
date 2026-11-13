import { useT } from '../lib/i18n'
import type { CrownHull } from '../lib/rpc'
import { CROWN_WORD } from './crownWord'
import { HullBadge } from './HullBadge'

// A HULL THE CROWNS SAIL (0332): "Cargo ship" or "Navy ship" beside a hull's name, small. ONE renderer for the Codex and the build yard, as
// HullTech is for the tech badge, so the two can never name a hull differently. The word says what the chart calls such a ship, so a player can
// find the hull he saw at sea; she is his own ship once built. Served (snapshot `ship_classes[].crown`, `world.building_yard` `hulls[].crown`,
// both from public.crown_classes, which reads the knobs): no hull code is known here.

export function HullCrown({ crown }: { crown: CrownHull | null | undefined }) {
  const t = useT()
  if (!crown) return null
  return (
    <HullBadge data-testid="hull-crown">{t(CROWN_WORD[crown])}</HullBadge>
  )
}
