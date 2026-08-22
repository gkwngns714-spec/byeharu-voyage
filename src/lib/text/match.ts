// DOES THIS TEXT MATCH WHAT WAS TYPED — the one answer, for every filter box in the game.
//
// ── WHY IT IS HERE AND NOT IN A SCREEN ─────────────────────────────────────────────────────────
// It lived in `features/command/ArgPickers.tsx:27`, unexported, so the Market tab's port filter
// could not reach it and matched with a bare `toLowerCase()` instead. Two spellings of "does this
// text match" is two behaviours: the Command tab found `São Vicente` when you typed `sao`, and the
// Market tab did not. A screen may not own a rule another screen needs — docs/SECTIONS.md — and
// this is machinery rather than a part of the game, so it is a `lib`, not a `domain`.
//
// ── IT AGREES WITH THE SERVER ON PURPOSE ───────────────────────────────────────────────────────
// `cmd.fold()` (migration 0008) does the same to a name before it looks it up, so a port a picker
// offers under a typed `sao` is a port the parser will accept spelt that way. If the SQL ever
// changes what folding means, this is the one place on the client that changes with it.

/**
 * Case- and accent-insensitive form of a piece of text, the way the server's `cmd.fold()` makes it.
 * `São` and `SAO` both fold to `sao`, so a filter matches what a player can actually type.
 */
export function fold(text: string): string {
  return (
    text
      .normalize('NFD')
      // The combining-marks block, built from a string because `erasableSyntaxOnly` builds are
      // happier with it than with a literal full of escapes — and it is the same range either way.
      .replace(new RegExp('[\\u0300-\\u036f]', 'g'), '')
      .toLowerCase()
  )
}

/**
 * True when EVERY field of a row answers to the needle in the folded sense. An empty needle matches
 * everything — a filter box that has not been typed in hides nothing.
 *
 * The needle is folded ONCE by the caller (`fold(query.trim())`) and the fields folded per row;
 * folding the needle inside the loop would be the same work N times.
 */
export function foldedMatch(foldedNeedle: string, ...fields: (string | null | undefined)[]): boolean {
  if (foldedNeedle === '') return true
  return fields.some((f) => f != null && fold(f).includes(foldedNeedle))
}
