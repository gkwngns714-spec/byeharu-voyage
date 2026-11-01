# 2026-11-02 — THE PROFILE ON A PHONE (branch `city-phone-profile`, client-only; part 3 of the HQ-on-a-phone slice)

> The brief's defect (e): *"Profile page: the logout control overlaps something at phone width — find it and fix it."* The slice is `docs/dev-log/2026-11-02-city-phone.md`;
> this is its third PR (the first is the shared primitives and the HQ, the second the desk's City board).

## 1. Inventory — what the logout control overlaps (served `main`, headless, English and Korean, DPR 1)

The page is a `Sheet` of five sections: the house line, Country, Language, Appearance, and the session card holding the `Sign out` button. Heights at 320×640 (Sheet 551 px):
header 46 · house 66 · Country 92 · **Language 92 · Appearance 92** · session 88 · plus the Sheet's own 24 px of bottom padding = **572**.

| glass | the Sheet | the sign-out control |
|---|---|---|
| 390×844 | 755 in 755 — flat | stands at 440…484 of a Sheet that ends at 787 — clear |
| 360×640 | **558 in 551** (7 px of scroll inside the Sheet) | card flush on the rail |
| 320×640 | **572 in 551** (21 px) | card flush on the rail, its padding scrolled out of reach |
| 320×568 (the smallest the repo measures) | **572 in 479** (93 px) | button bottom **534 — 23 px past the Sheet's bottom (511)**; its rectangle **lies 22 px over the rail's Stats and Menu cells** and the label's over the HQ, Fleets and Map cells (any-pair overlap probe: 8 in English, 10 in Korean) — the Sheet clips it, so it reads as cut, not drawn over |

So the answer to *"overlaps something"*: **the rail**, at 320×568 as a rectangle overlap (the Sheet hides it, which is a cut), and at 320×640 / 360×640 as a Sheet that scrolls inside itself when the
unfold laws (U2) say no tab scrolls at 320×640. The overlap was never the label or the button against each other: at every glass the label stands 12 px clear of the button.
(In the cloud build the label is the account's e-mail instead of a sentence — the same row, the same widths; local mode is what CI serves.)

## 2. The change (one existing primitive, one prop, two callers)

Language and Appearance were a heading on one line and a 44-px switch on the next: 92 px each for 24 px of word and 52 of control. `SheetSection` takes `inline` — *the section is one small
control, so its heading and the control stand on ONE line, the control right behind the word* (the owner's hug, rows 258/260), and the control drops under the word only when the two do not fit
(`flex-wrap`; no variant, no container: it is content-aware by itself). Language and Appearance are its two callers. Nothing else on the page moves.

## 3. Budget (before the code) and measured (after)

| | before | budget | after |
|---|---|---|---|
| Language section · Appearance section | 92 · 92 | 52 · 52 (the control's own height) | **52 · 52** |
| the page at 320×640 (Sheet 551) | 572 | ≤ 551 → 492 | **551 in 551** — the page's content ends 59 px above the Sheet's bottom edge, its padding is in |
| the page at 360×640 | 558 | ≤ 551 | **551 in 551** |
| the page at 320×568 (Sheet 479) | 572 | cannot all stand | 492 in 479 — **13 px, all of it the Sheet's 24-px padding**; the sign-out button's bottom is 454, the Sheet's 511, the rail's 511 |
| sign-out vs the rail, any-pair rectangle overlap at 320×568 | 8 (EN) / 10 (KO) | 0 | **0** |
| the word and its switch (Language, Appearance) | one above the other | one line, ≤ 24 px apart | one line, 12 px apart, at 390, 360, 320 and 1280, English and Korean |

## 4. The law (`tests/profile.phone.spec.ts`; red on `main`, green here)

At 390×844, 360×640 and 320×640 the Sheet does not scroll, the sign-out button lies wholly inside the Sheet and clear of the rail, and each switch stands on its word's line (within 6 px) and within 24 px of it;
at 320×568 the button is still whole and clear of the rail and only the Sheet's own 24 px of padding scrolls; the same at 320×640 in Korean. On `98a75c04` it fails four of five (390: the switches under their words;
360 and 320×640: the Sheet scrolls 7 and 21 px; 320×568: the button runs 23 px past the Sheet). `i18n.ko.spec.ts`'s switch test and `consistency.spec.ts`'s title walk still pass.

## 5. Unverified

The cloud-mode row (a signed-in account's e-mail beside the button) was not exercised — it needs a Supabase session; its widths are the local row's with a longer label, which wraps in the same track.
