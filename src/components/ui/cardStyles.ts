// THE CARD'S LOOK, said once (2026-11-11, the remaster's S9). Pure strings, no React, so the Card (Card.tsx) and the list drawn
// as a card (ListPanel `look="card"`) wear ONE surface, ONE padding ladder and ONE header — they had two copies of each.
//
// The playtest: *"keep the cards"*, but the page read flat — a 12-px corner, a hairline and nothing else, every block the same
// weight as the sea under it, the title floating over its content. The tuning, inside the kept identity (navy, gold, the cards):
//
//   surface   a 16-px corner (the sheet's radius, `--radius-sheet`: a card is a block of the page, not a tile inside one), the
//             `edge` hairline, and ONE faint raise (`--shadow-raise`, src/index.css: a 1-px top light and a soft cast under it) so
//             the card stands on the sea instead of being printed on it
//   padding   16 px on a phone (unchanged: every phone measure holds), 24 from 768 — the room a laptop's card was missing
//   header    the title at the card size (20 px) from 768, over a hairline that closes the head, 16 px above the content: the
//             card's name reads as its name, and the eye finds the content's start
//
// The rhythm BETWEEN cards is the page's gutter (screenLayout.ts `PAGE_GAP`: 12 · 16 · 20 · 24), unchanged and the one gap.

/** The card's surface: corner, hairline, tone and raise. */
export const CARD_SURFACE = 'min-w-0 rounded-sheet border border-edge bg-surface shadow-raise'

/** The card's room: 16 px on a phone, 24 from 768. */
export const CARD_PAD = 'p-4 md:p-6'

/** A one-figure card's room: the same sides, a little less above and below from 768. */
export const CARD_PAD_COMPACT = 'p-4 md:px-6 md:py-5'

/** The card's head: its title line closed by a hairline, the title 12 px over it and the content 12 px under it: one rhythm
 *  (2026-11-14, the second look pass; the content stood 16 under, and a row that centres its own words looked adrift). */
export const CARD_HEAD = 'mb-3 border-b border-edge pb-3'

/** The card's title: 16 px on a phone, the card size (20) from 768, semibold ink. */
export const CARD_TITLE = 'text-t-body font-semibold text-ink md:text-t-card'

/** Two summary rows (Detail.tsx `SummaryRow`) one over the other stand 8 px apart: each is a filled bar. Not inside a `narrow:`
 *  container, where a row has no fill. The caller that stacks them says so; two side by side (Trade's doors) do not. */
export const SUMMARY_STACK_CLASS = '[[data-summary-row]+&]:mt-2 narrow:[[data-summary-row]+&]:mt-0'
