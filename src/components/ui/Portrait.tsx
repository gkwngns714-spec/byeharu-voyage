// A CAPTAIN'S PORTRAIT PLATE (2026-11-23, the visual overhaul's slice 6: "a portrait plate, role glyph on a nation-tinted disc").
//
// Drawn here, inline, in the kit's own manner (1.5-px strokes, round joins, no bitmap from outside): a disc in her tint, her head and
// shoulders, and the HAT OF HER ROLE — a merchant's soft cap for Trading, a tricorne for Exploration, a gunner's bicorne for Combat at
// long range, a boarder's knotted scarf for Combat at close range; a role this file does not know draws her bare-headed. Her face is
// one of three (clean, a beard, a moustache) by her own code, so a room of six is six people and the same captain is the same face on
// every screen. Her grade is the letter in the corner, gold at the top grade.
//
// PURE PROPS: the caller (src/live/captainLook.ts) decides the role, the tint and the seed from the served card; this draws them.

const HATS: Record<string, readonly string[]> = {
  // a soft round cap with its button
  trading: ['M15.6 18.2c-.4-4.6 3.4-7.4 8.4-7.4s8.8 2.8 8.4 7.4c-2.6-1-5.4-1.4-8.4-1.4s-5.8.4-8.4 1.4Z', 'M24 9.6v1.2'],
  // a tricorne, its three points
  exploration: ['M12.5 18 24 10.5 35.5 18c-2.4-.6-4.6-.4-6.4.8L24 16.6l-5.1 2.2c-1.8-1.2-4-1.4-6.4-.8Z'],
  // a bicorne, worn athwart, with its cockade
  'combat:long': ['M11.5 18.4c2.2-6.2 7-8.6 12.5-8.6s10.3 2.4 12.5 8.6c-3.8-1.6-8-2.2-12.5-2.2s-8.7.6-12.5 2.2Z', 'M24 12.4a1.4 1.4 0 1 0 0 2.8 1.4 1.4 0 0 0 0-2.8Z'],
  // a scarf knotted at the side, its tails loose
  'combat:close': ['M16.4 19.4c-.6-5 2.8-8.2 7.6-8.2s8.2 3.2 7.6 8.2c-2.4-1.2-4.9-1.8-7.6-1.8s-5.2.6-7.6 1.8Z', 'M31.2 17.6l3.6 2.6', 'M31 18.6l2.4 4.2'],
}

/** The three faces, by the seed. */
const FACES: readonly (readonly string[])[] = [
  [],
  // a short beard along the jaw
  ['M19.4 24.6c.8 3 2.6 4.6 4.6 4.6s3.8-1.6 4.6-4.6'],
  // a moustache
  ['M21.4 25.4c1-.8 1.8-.8 2.6 0 .8-.8 1.6-.8 2.6 0'],
]

function seedOf(s: string): number {
  let h = 0
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) >>> 0
  return h
}

export function Portrait({
  role,
  tint,
  seed,
  grade = null,
  top = false,
  size = 40,
  label,
}: {
  /** The role key (`trading`, `exploration`, `combat:long`, `combat:close`), or null. */
  role: string | null
  /** A CSS colour: her tint. */
  tint: string
  /** What picks her face: her code. */
  seed: string
  /** C / B / A / S, served; null draws no corner. */
  grade?: string | null
  /** The top grade: the corner is gold. */
  top?: boolean
  size?: number
  /** Set when the plate stands alone and must say who it is; otherwise it is decoration beside her name. */
  label?: string
}) {
  const hat = (role === null ? undefined : HATS[role]) ?? []
  const face = FACES[seedOf(seed) % FACES.length]
  return (
    <svg
      viewBox="0 0 48 48"
      width={size}
      height={size}
      fill="none"
      strokeWidth={1.5}
      strokeLinecap="round"
      strokeLinejoin="round"
      role={label === undefined ? undefined : 'img'}
      aria-label={label}
      aria-hidden={label === undefined ? 'true' : undefined}
      className="shrink-0"
      data-testid="captain-portrait"
      data-role={role ?? ''}
    >
      <circle cx="24" cy="24" r="22.5" fill={tint} fillOpacity={0.16} stroke={tint} strokeOpacity={0.75} />
      {/* her shoulders and coat, then her head, then the hat of her role over it */}
      <path d="M10.5 41.5c1.2-6.6 6.6-10.4 13.5-10.4s12.3 3.8 13.5 10.4" fill={tint} fillOpacity={0.4} stroke={tint} />
      <path d="M20.6 31.6 24 36l3.4-4.4" stroke="var(--color-ink-muted)" />
      <circle cx="24" cy="22.2" r="6.6" fill="var(--color-surface-2)" stroke="var(--color-ink-muted)" />
      {face.map((d) => (
        <path key={d} d={d} stroke="var(--color-ink-muted)" />
      ))}
      {hat.map((d, i) => (
        <path key={d} d={d} fill={i === 0 ? tint : 'none'} fillOpacity={0.9} stroke={tint} />
      ))}
      {grade && (
        <g>
          <circle cx="39.5" cy="39.5" r="7.5" fill="var(--color-bg)" stroke={top ? 'var(--color-accent)' : 'var(--color-ink-faint)'} />
          <text
            x="39.5"
            y="43.3"
            textAnchor="middle"
            fontSize="10.5"
            fontWeight={700}
            fill={top ? 'var(--color-accent)' : 'var(--color-ink-muted)'}
            stroke="none"
          >
            {grade}
          </text>
        </g>
      )}
    </svg>
  )
}
