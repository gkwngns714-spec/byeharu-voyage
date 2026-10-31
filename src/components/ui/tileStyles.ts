// THE CHOICE GRID'S PURE HALF (owner, 2026-10-31) — the column table and the one cell recipe,
// kept out of TileGrid.tsx so that file exports COMPONENTS ONLY (react-refresh's rule: a file that
// exports a helper beside its components cannot hot-reload). `Segmented` (Chip.tsx) and every
// filter set read the same numbers, so a tab and a filter cannot drift apart.

export type ChoiceColumns = 2 | 3 | 4 | 5 | 6

/** Tailwind cannot see a class built from a number, so the fixed column counts are typed out. */
export const COLUMN_CLASS: Record<ChoiceColumns, string> = {
  2: 'grid-cols-2',
  3: 'grid-cols-3',
  4: 'grid-cols-4',
  5: 'grid-cols-5',
  6: 'grid-cols-6',
}

/** The cell's base recipe — layout only. The STATE skin belongs to the caller (a filter washes
 *  accent; a face stands on the segmented track), because those are two different meanings. */
export function tileCellClass(): string {
  return 'flex min-h-11 min-w-0 items-center justify-center rounded-control px-2 py-1 text-center text-t-caption leading-tight transition'
}
