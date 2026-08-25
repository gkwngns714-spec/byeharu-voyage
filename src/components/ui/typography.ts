// Design-system TYPE RECIPES — pure class builders, the `buttonStyles.ts` / `tableLayout.ts` idiom
// applied to the text treatments this game repeats most.
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
//   inlineFigureClass
//                the READ FIGURE inside a row — full-strength ink, mono, tabular. `fineClass` is
//                the number you may ignore; this is the number the row exists to show, sitting
//                beside the bar that draws it rather than above the block as its headline (that
//                is `HeroFigure`, and it is `text-2xl` and a `<p>` for exactly that reason).
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

/**
 * THE FIGURE BESIDE THE BAR — mono, tabular, full-strength ink, at reading size.
 *
 * Found by `tests/duplication.spec.ts` at 100% across two files that had never met:
 * `RefusalNote.tsx`'s `2.9 / 33` beside its danger Meter, and `HaggleBlock.tsx`'s odds percentage
 * beside its own. Both had hand-written `shrink-0 font-mono text-sm tabular-nums text-ink`, and
 * both were right — which is precisely the shape the twelve chip copies started in
 * (`buttonStyles.ts:31-35`). One recipe, one place, before a third one landed.
 *
 * `tabular-nums` is the load-bearing token and the reason this is not just "small mono text": the
 * figure sits in a flex row whose other child is a `Meter` that grows, so a proportional `9` and a
 * proportional `1` would shift the bar's end every time the number ticked. Fixed-width digits make
 * the figure's box a function of its DIGIT COUNT and nothing else.
 *
 * The FLEX BEHAVIOUR is the caller's, not this recipe's — the same boundary `rowLinkClass` keeps
 * with the 44 px floor. Both callers today pass `shrink-0` because both sit beside a `min-w-0
 * flex-1` Meter, but a figure standing on its own line needs no such thing, and a recipe that
 * baked it in would have to be un-baked by the first caller that did.
 */
export function inlineFigureClass(extra = ''): string {
  return `font-mono text-sm tabular-nums text-ink${extra ? ` ${extra}` : ''}`
}

/**
 * THE HEAD ROW OF A PANEL — a name on the left, its meta on the right, and it WRAPS.
 *
 * Found by `tests/duplication.spec.ts` at 83% similarity across two screens that had never met:
 * the Ledger's entry head (time · fleet · kind · when) and the haggle block's head (title ·
 * attempts left). Neither was wrong; both were the same idea typed twice, which is how the twelve
 * chip copies started.
 *
 * `flex-wrap` with `items-baseline` is the load-bearing part, and it is the same reasoning
 * `CardHeader` records: the right-hand side is meta that must not truncate, so without wrapping the
 * row's MINIMUM width is left + gap + right — a number made of glyphs, which differs per platform
 * and can push a 320px page sideways. Wrapping makes the minimum the WIDER OF THE TWO instead of
 * their sum, and is a no-op whenever they fit.
 *
 * `spread` is the only choice a caller gets: `true` pushes the meta to the far edge
 * (`justify-between`), `false` lets it sit straight after the title.
 */
export function headRowClass(spread = true, extra = ''): string {
  return [
    'mb-2 flex flex-wrap items-baseline gap-x-3 gap-y-1',
    spread ? 'justify-between' : '',
    extra,
  ]
    .filter(Boolean)
    .join(' ')
}
