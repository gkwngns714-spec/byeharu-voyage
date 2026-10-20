import { useT, type TKey } from '../lib/i18n'
// A HULL'S TECH BADGE (0159, S15) — "T2" (and "Famous", S17) beside a hull's name, small. ONE renderer for
// the Codex and the build yard, as HullCountry is for the flag, so the two can never badge a hull
// differently. The tech code is served (snapshot `ship_classes[].tech`, `world.building_yard`
// `hulls[].tech`, `class_profile.tech`); a T1 hull carries no badge — it is the standard of its line.

const TECH_BADGE: Readonly<Record<string, TKey | 'T2'>> = { T2: 'T2', F: 'town.famous' }

export function HullTech({ tech }: { tech: string | null | undefined }) {
  const t = useT()
  const key = tech ? TECH_BADGE[tech] : undefined
  if (!key) return null
  const word = key === 'T2' ? key : t(key)
  return (
    <span className="mr-1 rounded-chip bg-accent-soft px-1.5 text-accent" data-testid="hull-tech">
      {word}
    </span>
  )
}
