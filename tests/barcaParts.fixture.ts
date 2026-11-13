// THE BARCA AS SHE WAS BEFORE 0363 — a hull with two parts a new company can pay for.
//
// 0363 (S2 of docs/SECOND_SHIP.md) took the Barca's Suit of Sails and Anchor & Cable out of her recipe. The yard's
// sheet still plans hulls WITH parts (the Caravela latina, the Nau, the famous ships): a part unfolds into its goods,
// "Make parts" comes before "Store". The specs that prove that half (tests/yard.plan.spec.ts) were written on the
// Barca, the only such hull a new company's purse and hold can play to the end, so they run on a copy of the shipped
// world with her two rows put back: the very rows 0363 deleted, which are also its forward rollback. The shipped
// world, where she takes no part, is proven by tests/second.ship.spec.ts.

import type { PGlite } from '@electric-sql/pglite'
import { patchedWorldImage } from './worldImage.fixture'

/** The two rows 0363 deleted. */
export const BARCA_PARTS_SQL = `insert into public.hull_recipe_items (class_code, item_code, qty) values ('barca', 'suit-of-sails', 1), ('barca', 'anchor-and-cable', 1);`

export async function putBarcaPartsBack(pg: PGlite): Promise<void> {
  await pg.exec(BARCA_PARTS_SQL)
}

/** The shipped world with the Barca's two parts back in her recipe, and nothing else changed. */
export function barcaWithParts(): Promise<Buffer> {
  return patchedWorldImage('barca-with-parts', putBarcaPartsBack)
}
