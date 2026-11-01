# 2026-11-02 — THE CAPTAIN'S TRAY AND THE MENU TRAY (branch `captain-menu`, client-only)

> From the read-only layout sweep of origin/main e6bf38d1 (its table, **rows 10 and 11**). Owner row 265 (state only).
> Two defects of one family — a tray whose content does not fit the tray — fixed in the files that own them, and held by specs that RUN.
> Headless chromium, the local canary world, 390×844 · 320×640 · 1280×800, English and Korean, on origin/main **937231f6** (after `city-phone` part 1 and
> `city-phone-profile` merged: their `narrow:` rows are for containers under 15 rem, and these trays are 18 rem and up, so they change nothing here —
> measured, not assumed). The sweep's numbers reproduced to the pixel before any change.

## 1. Row 10 — the officer tray (Codex → Captains), and the same line in YourCaptains

**Cause.** A trait's sentence ("−4.2% crew lost to pirates · −4.2 points of homesickness", 436 px) was passed as the Row's `value`. The value cell never wraps
(`Row.tsx`: `whitespace-nowrap`, a `max-content` track), so it took its whole 436 px and the label took what was left.

| first captain of the roster (Hajji Ghulam Husayn, A) | 390×844 | 320×640 | 1280×800 |
|---|---|---|---|
| BEFORE: tray content wider than the tray | **74 px** | **144 px** | **48 px** |
| BEFORE: "Surgeon" label (w × h) | 0 × 168 (a letter a line) | 0 × 168 | 0 × 168 |
| BEFORE: the scroll region, content / window | 1,028 / 336 | 1,124 / 234 | 1,028 / 626 |
| AFTER: wider than the tray, EN and KO, three captains each | **0** | **0** | **0** |
| AFTER: "Surgeon" label | 56 × 24 | 56 × 24 | 56 × 24 |
| AFTER: the scroll region, content / window | 1,082 / 336 | 1,082 / 234 | 1,082 / 626 |

Elsewhere in the roster, at 320 BEFORE: "Medicine trader" (Peder Oxe) 25 × 120 (five lines), "Weapons trader" 26 × 120, "Tobacco trader" 33 × 96, and most other trait names
two lines; at 390 "Medicine trader" 95 × 48. AFTER: every trait name is one 24-px line, in both languages (the spec below opens the first captain of every grade).

`YourCaptains.tsx:115` is the same line. The sweep could not reach it ("no captain hired"); it IS reachable — HQ → Inn → Captains → the first guest → Hire, in the
local world, 3,500–6,850 of the 40,000 ducats. BEFORE, on a hired Daniel Nijs (S): "Weapons trader" 26 × 120 and "Tobacco trader" 33 × 96 at 320, "Weapons trader"
96 × 48 at 390 (8 of her 10 trait names wrapped at 320, 1 at 390, none at 1280); on a hired Hendrick Uylenburgh (C, measured on 9a97051e) "Ship-supplies trader" was 79 × 72 at 390 and **9 × 432 (a letter a line) at 320**. There
is no sideways overflow there: the label gives way first, which is worse to read. AFTER: all ten of Daniel Nijs' trait names are one 24-px line at the three glasses, EN and KO.

**Change.** The sentence is the row's second line (`Row`'s `children`, which already spans label to edge and wraps): name on line 1, sentence on line 2, the served
note (`Not in use yet.`) under it; the sentence keeps the success tint when the server says the trait is in use. `CaptainsFace.tsx` (the tray) and `YourCaptains.tsx`
(her sheet). `Row.tsx` is untouched.

## 2. Row 11 — the Menu tray

**Cause.** `CABIN_DETENT = 'half'` was chosen when the Menu held four rows; it holds six (`navTabs.ts`). Six 52-px rows under the tray's 52-px handle row and its
34-px title are **406 px**; `half` is half the glass.

| | 390×844 | 320×640 | 1280×800 | 320×568 | 667×375 (landscape phone) |
|---|---|---|---|---|---|
| BEFORE: tray height | 422 | 320 | 400 | 284 | 188 |
| BEFORE: body, for 320 px of rows | 336 | **234** | **314** | 198 | 102 |
| BEFORE: inner scroll | 0 | **86 px** | **6 px** | 122 px | 218 px |
| BEFORE: rows whole | 6 / 6 | **4 / 6** ("You" cut, "Profile" hidden) | 6 / 6 | 3 / 6 | 1 / 6 |
| AFTER: tray height | 422 | **406** | **406** | 406 | 286 (head at y = 32) |
| AFTER: inner scroll | 0 | **0** | **0** | 0 | 120 px (the glass cannot hold six) |
| AFTER: rows whole / a finger lands on them | 6 / 6 · 6 | **6 / 6 · 6** | **6 / 6 · 6** | 6 / 6 · 6 | 3 / 6 · 4 |

The same on the HQ page (its rail is the shell's `NavBar`): 86 px BEFORE at 320×640, 0 AFTER. English and Korean read the same (rows are 52 px in both).

**Change (`NavBar.tsx` only).** The Tray has no stop that is "as tall as its rows" (`Tray.tsx` `HEIGHT`: peek · half · full) and is not this slice's to edit, so NavBar
gives the tray a floor through the `className` the Tray already takes: `min-height: min(rows × --spacing-row + 5.875rem, the glass between the status strip and the
bar)`. `min-height` beats the Tray's inline `height`, so the tray is `half` wherever `half` is enough (390×844 is untouched: 422) and its rows' height where it is not.
`--cabin-floor` is set on the wrapper from the member count, so a seventh member needs no edit here. The floor applies at `half` only (a drag to `peek` is still a
peek), and the `min()` with the free glass is why a landscape phone gets 286 px with its head on the glass instead of a 406-px tray with its head cut off.
`trayDetents.ts` is untouched: the ladder is still the three stops.

**What a proper fix is, and why it is not here.** A `fit` stop in the ladder — `Tray.tsx` `HEIGHT.fit = 'auto'` and a `fit` member of `trayDetents.ts` — would let NavBar
say "my rows" without knowing the Tray's chrome (the floor's `5.875rem` is the Tray's own handle row 3.25 + head 2.125 + foot 0.5, written in a second place). That is a
primitive change; `Tray.tsx` is `city-phone`'s and this slice was fenced off it. When the Tray grows that stop, delete `CABIN_FLOOR` and `cabinFloor` from `NavBar.tsx`;
`tests/nav.geometry.spec.ts` ("the Menu tray stands as tall as its rows") is the guard, and it goes red the day the Tray's chrome changes without the floor.

## 3. The laws (all RUN; none skips)

* `tests/trayLaw.fixture.ts` — one reader for a tray of rows (sideways overflow of the scroll region, the tray and the page; each row's cells past the tray's content
  edge; a label or figure taller than a line and a half), shared by the two captain specs.
* `tests/captains.codex.spec.ts` — the officer tray at the three glasses, English and Korean, for the first captain of every grade in the data; it fails if no opened
  captain knows Surgeon (the widest sentence), so it cannot pass over nothing.
* `tests/captains.roster.spec.ts` — hires through the Inn's own screens, reaches You through the Menu, opens her tray at the three glasses.
* `tests/nav.geometry.spec.ts` — the Menu: every member whole and reachable (a finger lands on it), no inner scroll, at the three glasses; the head stays on the
  glass at 667×375.

## 4. Each law was red on the BEFORE build first (served on :4812, origin/main 937231f6)

* Codex officer tray, English and Korean: 74 / 144 / 48 px wider than the tray; "Surgeon" 0 × 168; about twenty trait names wrapped at 320 in each language (e.g. "Weapons trader" 26 × 120, "Tobacco trader" 33 × 96).
* A hired captain's tray: trait names wrapped at 320 and 390.
* The Menu: `320×640: tray 320px, 4/6 rows whole, inner scroll 86px`; `1280×800: tray 400px, inner scroll 6px`; `667×375: 1/6 rows whole`.
* The five other tests of the three files (the pre-existing ones) pass on both builds; AFTER all nine pass, none skipped.

## 5. Not changed, and why

* `src/live/PortInn.tsx:411` — the Inn's guest tray carries the identical `value={<Figure value={t.lines.join(' · ')} …/>}` line (`inn-trait-*`). `src/live/Port*` is the
  `city-phone` writer's. Measured only at 390 on a hired guest whose sentences were short (250 px at most): it fits there. Not measured at 320 or on a guest who knows
  Surgeon; the same one-line move fixes it.
* `YourCaptains.tsx` rows `Job` / `Where` still carry `value`s of the form `ship · cabin` (162 px for the canary's one fleet). A 24-character fleet name would push
  `Where` past the tray at 320; not reproduced, not changed — a different row, and the brief named line 115.
* The Menu at ≥ 1024 px is a 1,280-px-wide tray holding six short rows. Its height is fixed here; its width is the wide-glass question the sweep's row 17 raises.
* Not measured: light and Auto appearance, DPR 2, widths between the three glasses, the live cloud world, a captain whose traits cannot be changed (`can_change` false).
