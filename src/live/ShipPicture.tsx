import { hullTierOf, type ShipTier } from '../chart'
import { ShipArtIcon } from './battle/ShipArt'

// HER PICTURE ON THE FLEETS TAB (2026-11-23, the visual overhaul's slice 5: "each fleet is a tile with its flagship's silhouette").
//
// ONE DRAWING OF A SHIP. The picture is the battle stage's and the Codex key's own (`ShipArtIcon`, src/live/battle/ShipArt.tsx): your
// family ("yours", a merchant's hull in the accent with a long pennant) at her TIER, and the tier is the served one (`hullTierOf`, off the
// class's served size, src/chart/glyphs.ts): a barca is a sloop, a nau a frigate, here as on the map and in a fight. Nothing here draws a
// hull of its own. A class no snapshot has named yet draws the smallest picture, which claims nothing about her.
//
// THE TONE IS THE ROW'S MEANING, NOT A NEW ONE: her outline wears the tone her row already reads in (a fleet's status tone, a flagship's
// accent), so the picture carries no meaning the row did not.

/** Her tier, from the class CODE her row serves (`FleetShip.class_code`); a code no snapshot has named reads as the smallest. */
function shipTierOfCode(code: string | null | undefined): ShipTier {
  return hullTierOf(code ?? null) ?? 1
}

const PLATE = {
  /** a mark beside a figure (the title's count of ships): no plate, the picture alone */
  mark: { box: 'h-5 w-8 bg-transparent!', width: 32 },
  /** a row's mark: 56 × 40, the 52-px row grows by nothing */
  row: { box: 'h-10 w-14', width: 52 },
  /** a ship's own page: her picture across the top */
  hero: { box: 'h-32 w-full rounded-tile! sm:w-72', width: 240 },
} as const

export function ShipPicture({
  code,
  tone,
  label,
  size = 'row',
  'data-testid': testId,
}: {
  /** The class CODE (`barca`), as served on her row. */
  code: string | null | undefined
  /** Her outline: a token, e.g. `var(--color-accent)`. Unset: the sea's. */
  tone?: string
  /** What the picture says on its own (her status, "flagship"); unset, it is decoration beside her name. */
  label?: string
  size?: keyof typeof PLATE
  'data-testid'?: string
}) {
  const plate = PLATE[size]
  return (
    <span
      className={`flex shrink-0 items-center justify-center rounded-chip bg-surface-2 ${plate.box}`}
      role={label === undefined ? undefined : 'img'}
      aria-label={label}
      data-ship-picture={size}
      data-testid={testId}
    >
      <ShipArtIcon family="yours" tier={shipTierOfCode(code)} width={plate.width} tone={tone} fit />
    </span>
  )
}
