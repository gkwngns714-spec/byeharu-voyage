// THE CODEX'S FILTER VOCABULARY — "the distinct served values of one key, as options behind All" (2026-11-02, the page slice).
//
// ShipsFace and CaptainsFace each wrote their own `optionsOf` and their own `ALL` on 2026-11-02 (the unfold slice), and the
// Goods face's kind and rarity choices would have been the third spelling — docs/NO_SPAGHETTI.md §1: found a third time, fold
// it the same turn. `ALL` itself is the design system's (filterState.ts: Stats was its first caller, this screen its second);
// what stays here is the one way this screen turns a served catalogue into a picker's options.
//
// WHERE IT LIVES, AND WHY. It is a way of LISTING what the server served — never a fact about the world and never a look — so
// it is the screen's, beside the faces that ask it. THE SECOND CALLER would be the Stats faces (statsFilters.ts `countriesOf`
// lists distinct nations the same way, without the labels); the day one of them wants the labels too, this moves to
// src/components/ui/filterState.ts beside `ALL` and `oneOf`, and both import it from there.

import { ALL } from '../../components/ui'

export interface Option {
  id: string
  label: string
}

/** The distinct served values of one key, in the served order of first appearance unless `order` says otherwise, as options
 *  behind "All" (`ALL`). `label` reads the player's word for a value off the first item that carries it; a value with no word
 *  prints as served. */
export function optionsOf<T>(
  all: string,
  items: readonly T[],
  key: (item: T) => string | null | undefined,
  label: (value: string, item: T) => string | null | undefined,
  order?: (a: string, b: string) => number,
): Option[] {
  const firstOf = new Map<string, T>()
  for (const item of items) {
    const v = key(item)
    if (v != null && !firstOf.has(v)) firstOf.set(v, item)
  }
  const ids = [...firstOf.keys()]
  if (order) ids.sort(order)
  return [{ id: ALL, label: all }, ...ids.map((v) => ({ id: v, label: label(v, firstOf.get(v)!) ?? v }))]
}
