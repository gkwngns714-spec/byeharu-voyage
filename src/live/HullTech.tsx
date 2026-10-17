// A HULL'S TECH BADGE (0159, S15) — "T2" (and "Famous", S17) beside a hull's name, small. ONE renderer for
// the Codex and the build yard, as HullCountry is for the flag, so the two can never badge a hull
// differently. The tech code is served (snapshot `ship_classes[].tech`, `world.building_yard`
// `hulls[].tech`, `class_profile.tech`); a T1 hull carries no badge — it is the standard of its line.

const TECH_BADGE: Readonly<Record<string, string>> = { T2: 'T2', F: 'Famous' }

export function HullTech({ tech }: { tech: string | null | undefined }) {
  const word = tech ? TECH_BADGE[tech] : undefined
  if (!word) return null
  return (
    <span className="mr-1 rounded-chip bg-accent-soft px-1.5 text-accent" data-testid="hull-tech">
      {word}
    </span>
  )
}
