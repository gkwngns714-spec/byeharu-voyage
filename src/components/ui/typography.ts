// Design-system TYPE RECIPES — pure class builders, the `buttonStyles.ts` / `tableLayout.ts` idiom
// applied to the two text treatments this game repeats most.
//
// ── WHY THESE ARE FUNCTIONS AND NOT A COMMENT SAYING "USE THESE CLASSES" ───────────────────────
// An audit on 2026-08-22 counted `font-mono text-[11px] text-ink-faint` written out THIRTY times
// across fourteen files, and the tappable row link written three times in three different
// spellings — `min-h-11 text-left font-mono text-sm text-accent underline-offset-4 hover:underline`
// on the fleet roster, the same without `font-mono` two hundred lines below it, and
// `block text-sm text-accent underline-offset-4 hover:underline` on the Market table. Nothing was
// broken; that is the point. A voice spelt thirty times is a voice nobody can retune, and three
// spellings of one link is three things that will keep drifting apart one class at a time.
//
// The same audit is why `buttonClasses` exists (twelve hand-rolled chips) and why `scrollTableClass`
// exists. This is that rule reaching the text.
//
// ── THE BOUNDARY BETWEEN THEM ──────────────────────────────────────────────────────────────────
//   fineClass    the FINE PRINT voice: a figure, a caption, a footnote under a table. Mono because
//                it is nearly always numeric, faint because it is never the thing being read.
//   rowLinkClass a piece of text that is a TAP TARGET inside a row — a fleet name that loads an
//                order, a good that hands a BUY to Command. It carries the colour and the
//                underline and nothing else, because the 44 px floor belongs to the <button>
//                around it and differs by row (see the callers, which pass `min-h-11 text-left`).
//
// `extra` is appended, never merged: Tailwind's later-class-wins is by stylesheet order, not by
// string order, so a caller that needs a different size passes the size and gets it.

/** The fine-print voice — mono, 11px, faint. The one place it is spelt. */
export function fineClass(extra = ''): string {
  return `font-mono text-[11px] text-ink-faint${extra ? ` ${extra}` : ''}`
}

/** Text that is a tap target inside a row. The tap FLOOR is the caller's button, not this. */
export function rowLinkClass(extra = ''): string {
  return `text-sm text-accent underline-offset-4 hover:underline${extra ? ` ${extra}` : ''}`
}
