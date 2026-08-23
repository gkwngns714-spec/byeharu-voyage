// Design-system GOOD-TILE layout logic — pure (no React), beside GoodTile.tsx exactly as
// tableLayout.ts sits beside Table.tsx and screenLayout.ts beside Screen.tsx: the react-refresh
// rule keeps component files component-only, and the grid is a recipe a test can read.

/** The field of tiles. Two columns on a phone — MEASURED at 390px (docs/UI_DIRECTION.md §1):
 *  a card body is ~326px inside its padding, so two tiles get ~159px each, which holds the
 *  longest good name ("Wool Cloth", "Black Pepper") wrapped at most once; three would crush the
 *  figures to fragments. `items-stretch` so a short tile in a row of tall ones still fills its
 *  cell and the whole tile stays tappable. */
export function goodTileGridClass(): string {
  return 'grid grid-cols-2 items-stretch gap-2 sm:grid-cols-3 xl:grid-cols-4'
}
