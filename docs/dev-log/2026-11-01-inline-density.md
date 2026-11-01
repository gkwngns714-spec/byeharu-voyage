# INLINE DENSITY — the figure sits beside its label (owner, 2026-11-01)

> *"everything is folded in stats this is soo wrong. make it compact showing everything possible."*
> *"so is the same in command hq, city hall. there are empty spaces between words and numbers
> horizontally which is in effective. make it so that htey are closer, more compact with full detail,
> without having to fold anything unless it is necessary."*

The city screens are the city writer's. This slice is the SHARED ROW PRIMITIVES (Stats, the desk,
every tab that draws a `Row`) plus the alignment law that encoded the old spread.

## What changed (one authority each, no second row style)

- **`Row` (`src/components/ui/Row.tsx`)** — the label used to own a `1fr` grid track, so a short
  label's text ended early while its BOX ran to the row's end, and the figure stood at the far right.
  The tracks are now `mark · label (content) · value · slack (1fr) · chevron`: the slack absorbs the
  spare width AFTER the value, so the figure hugs the label and the chevron still stands at the row's
  edge; line-2 bars still span the full width.
- **`SummaryRow` (`src/components/ui/Detail.tsx`)** — `justify-between` pushed the figure to the
  right edge. The figure now follows its title; only the WORD and the chevron keep the edge. The
  three slots are named (`data-row-cell="label|value|action"`) so the alignment law can read them.

## Measured (served builds of `origin/main` f5976c61 vs this branch, 1280×800, headless)

The City Market face's rows (label text → figure, px; the text's own right edge, not the box):

| row | before | after |
|---|---|---|
| Range | **487** | **12** |
| In stock | **418** | **12** |
| Basket | **497** | **12** |
| Raw Silk / Silk Cloth / Woollen Cloth | 12 | 12 |

(The long labels had already filled their track; the short ones were the complaint.) Row pitch and
the 52-px row floor are unchanged — `primitives.geometry` (row: 52px, every target ≥44px) passes.

## The alignment law, updated rather than bypassed

`tests/align.spec.ts`'s COLUMN law required every list's values to share a right-edge column — the
pattern the owner has now retired. The law is now **HUG**: a `Row` value must sit within 16 px of its
own label (measured 12 px), the edge affordance is exempt, and hand-rolled rows keep their old
column rule. The gallery's column exhibit (equal columns inside a Row's label) demonstrates the
retired pattern; it is excluded by its own test id with the reason written at the check.

## Stats — the folds, measured

Re-measured on the served build at 390×568: the Overview face carries **546 px of Sheet content in
a 479-px Sheet BEFORE this change** — the Stats Sheet already scrolls at that size (both builds).
Every Stats fold holds either a CHART (the new-money bars and two series, the two merchant series) or
an UNBOUNDED LIST (the 629-good list, the live money feed, the ranked mover and day lists). There is
no single compact figure behind any fold: the faces' individual figures (the live band's, the four
merchant cells, the week's four cells) already stand inline.

Unfolding those blocks is therefore a content trade — something else must leave the face to keep the
no-scroll budget — not a patch. That redesign is the next slice, with the budget stated here so it is
decided with numbers instead of taste.

## Gates (served build, headless)

`primitives.geometry` 8/8 · `layout` 15/15 · `onepage` 2/2 (390×844 and 1280×800) · `align` 2/2
under the new HUG law (1.7 m / 2.0 m) · `tsc -b`, `eslint .`, `npm run build` clean.
