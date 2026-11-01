# 2026-11-02 — THE TRADE PANE AND THE INN'S GUEST TRAY ON A PHONE (branch `city-phone-pane`, client-only; part 7 of the HQ-on-a-phone slice)

> The first six PRs made the HQ's six faces and the desk's City board legible. Two states the walk could not reach stayed broken, and the coordinator named one of them: **the pane a good opens inside the Market** (the one
> `TradeTray`, pane mode — the act the Market is *for*) and **the Inn's guest tray** (`PortInn`'s trait rows, the same sentence-as-a-value defect the captain tray had). The slice is `docs/dev-log/2026-11-02-city-phone.md`.

## 1. Inventory (served `main` at f4e5dc46 / 173d74ce, headless, `localhost`)

**The trade pane (HQ › Market › a good).** The HQ's right panel is 170 px wide at 390 and 136 at 320. The tray stands IN it as a pane — and padded itself again (`px-gutter`, 16 px a side) inside a panel that already
has 15 px of padding, so the content column was **107 px at 390 and 72 px at 320**. In 72 px: two 44-px stepper buttons and the 12-px gaps are 112 px before the figure has a letter; the Add + Buy pair was a 62-px button, a gap and a
150-px label. Measured by the phone laws (`tests/city.phone.spec.ts`, red on `main`):

| | 390×844 | 320×640 |
|---|---|---|
| the Buy button (the act the pane is for) | **50 px past the tray's edge**, cut to "Buy / uni / 4,70" | **85 px past**, a sliver at the edge |
| the stepper's figure | squeezed to 0 px, its unit "units" standing on the `+` (350 px² of overlap) | the same, and the `+` itself pushed off the edge |
| the pane's scroll | — | **sideways 24 px** (128 px of content in 104) |
| other rows past the edge | — | "80 units" (7 px), the Kind row (14), "6,700 / 6,700" (18), the Bargain's tries (23 px inside a 72-px cell) |
| with the Bargain open | two 48-px buttons ("Take it", "Bargain"), the second wider than its box | sideways 5 px |

**The Inn's guest tray.** `PortInn` passed each trait's sentence ("−4.2% crew lost to pirates · −4.2 points of homesickness", 436 px) as the Row's **value**; `Row` keeps a value on one line. Read guest by guest (8 in the canary room):
guests 4–7 stood the trait's name **9 px wide, 7 lines high ("Surgeon") and 19 lines high ("Ship-supplies trader")** and the tray scrolled sideways, at 390, 320 and 1280 alike. It had measured clean at 390 only for the guests it was
asked about, whose sentences were short.

## 2. The changes (all at a shared primitive; nothing per face)

| file | change |
|---|---|
| `src/components/ui/Tray.tsx` | a PANE inside a narrow container (`narrow:`) does not pad twice: its four regions are `narrow:px-0` (and the action region `narrow:pb-2`). 107 → 139 px at 390, 72 → 104 at 320. A docked tray is its own query container at the glass's width, so nothing else matches. |
| `src/components/ui/Stepper.tsx` | in a narrow container the row wraps: the figure and its unit take the first line, whole, and the two buttons share the second (`flex: 1 1 2.75rem`) — or stand one over the other when 2 × 44 + the gap is more than the room. Anywhere else it is the row it has always been. |
| `src/components/ui/TradeTray.tsx` | the two acts stand one over the other in a narrow container (`narrow:grid-cols-1`); the Buy's label wraps inside its button (`text-center`, `narrow:px-2`). |
| `src/components/ui/Row.tsx`, `Figure.tsx` | a value wider than the whole row even beneath its label ("none on board" is 111 px in a 104-px column; `6,700 / 6,700` is 106) wraps at its own spaces in a narrow container instead of standing past the edge (`narrow:whitespace-normal`). A money figure and its coin never part (a no-break space, `lib/format`), and a value that fits stays one line. |
| `src/live/HaggleThread.tsx` | the Bargain row's tries and odds wrap instead of squeezing each other to letter columns; its two buttons stand one over the other in a narrow container. |
| `src/live/PortInn.tsx` | a trait is its name on line 1 and its sentence on line 2 — the pattern the captain tray took (`CaptainsFace`). |

## 3. The law

`tests/city.phone.spec.ts` reads, by the four laws, in English at 390×844, 320×640, 1280×800 and in Korean at 390 and 320:
the trade pane on **Buy**, with the **Bargain open**, and on **Sell** (with a good bought on the desk first, as a player does); the **Sell face** and the **Storage face** with that good on board (the canary's hold is empty, so
`StorageRow` and the Sell list were never drawn before); and **every guest of the Inn's room** (up to 8) in the hiring tray.

The fixture's readings of the box laws (`tests/unfold.fixture.ts`) were made honest in three ways, because the new states exposed three false positives that the old states could not:
* a box is measured **where it is on the glass** — clipped by every ancestor that clips (`overflow` not visible) and not by anything above a `fixed` one — so a row scrolled out of a pane, still under the pinned Add and Buy in the DOM, is
  not "overlapping" them;
* an element is measured **by fragment**: an inline caption that wraps is two boxes, and `getBoundingClientRect()` is the union of them, a rectangle covering whatever stands between its lines;
* an inline element is measured **from its first glyph to its last**, so GoodKind's mark that lies 3 px over a blank on purpose (`-mr-[3px]`) is no overlap of anything drawn; and a text that wraps is checked on every line it occupies,
  not only the first.

## 4. Numbers

(filled below from the final run)
