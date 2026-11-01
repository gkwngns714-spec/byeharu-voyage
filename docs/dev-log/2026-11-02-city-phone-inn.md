# 2026-11-02 — THE INN'S GUEST TRAY, READ GUEST BY GUEST (branch `city-phone-inn`, client-only; part 7 of the HQ-on-a-phone slice — a DEFECT fix, nothing denser)

> The coordinator, after #460 (the captain tray): *"src/live/PortInn.tsx:411 has the identical sentence-in-a-value pattern … move it to the row's second line the same way … and extend your city.phone law to assert no sideways overflow in that tray at
> 320/390/1280 (it measured fine at 390 only because the sentences there were short)."* The slice is `docs/dev-log/2026-11-02-city-phone.md`.

## 1. Measured on `main` (6558f12f, headless, `localhost`; the law reads every guest the room offers — 8 in the canary — in the hiring tray)

`PortInn` passed each trait's sentence ("−4.2% crew lost to pirates · −4.2 points of homesickness", 436 px) as the Row's **value**, which `Row` keeps on one line. Red, at **390, 320 and 1280**:
guests 4–7 stood the trait's name **9 px wide over 7 lines ("Surgeon") and over 19 lines ("Ship-supplies trader")** — one letter a line — and the tray scrolled **sideways** (the widest, guest 5 at 390: **74 px**, the figure the
captain tray had); the label was cut (`9 in 0 px`). Screenshot: `p7-inn-guest-390.png` (before).

## 2. The change

`src/live/PortInn.tsx`: a trait is **its name on line 1 and its sentence on line 2** — the pattern `CaptainsFace` took in #460 (`<span className="block text-t-body …">` under the label, the row's tone and the served `in_use` still colouring
it, the `Hint` after). One call site; no primitive touched; no word added. At 1280 the sentence now stands under the name instead of beside it — it overflowed there too (guests 5 and 6: sideways).

## 3. The law

`tests/city.phone.spec.ts`: HQ › Inn › *Captains here* › each guest (up to 8) pressed in turn, the tray read by the four laws (`phoneLaws`) and closed — at 390×844, 320×640, 1280×800, and 320×640 in Korean. Red on `main`, green here.

Reading the tray exposed a flaw in the fixture's box laws that the earlier states could not: a row **scrolled out of the tray's scroll region** is still in the DOM under the pinned *Hire* button, and the text-on-a-control law read its raw rectangle
("Animal trader" standing on *Hire Li for 6,300*, 89 × 17 px — nothing of the kind is on the glass). `tests/unfold.fixture.ts` now reads every box **where it is on the glass** (clipped by each ancestor that clips; nothing above a `fixed` one), an
inline element **by fragment** and **from its first glyph to its last** (a wrapped caption is two boxes, not their union; a mark that lies 3 px over a blank on purpose is no overlap), and a wrapped text on **every line** it occupies. It also
repairs a regex that had lost its backslash (`/s+/g` collapsed the letter *s* in the messages: "Li bon"). Test-only; the specs that read it (`city.nocity`, `desk.city`, `profile.phone`, `captains.roster`, `fleets.you.grow`) stay green.

## 4. Left over — the HQ Market's TRADE PANE on a phone (built, measured, PARKED on branch `city-phone-pane`, not merged)

The pane a good opens inside the Market (the one `TradeTray`, pane mode) is broken at 390 and 320 and has been since before this slice: the tray pads itself again inside a panel that already pads (content column **107 px at 390, 72 px at 320**),
so at 390 the **Buy button stands 50 px past the tray's edge** (cut to "Buy / uni / 4,70") and the stepper's figure is squeezed to 0 px with its unit on the `+` (350 px² overlap); at 320 the **Buy is a sliver 85 px past the edge**, the pane
scrolls **sideways 24 px**, and with the Bargain open its two buttons overlap. English and Korean. The fix is built (Stepper wraps, the two acts stand one over the other, a value wider than its row wraps at its own spaces, a title breaks inside its
word, the Bargain wraps; and — the part that is *density*, which the owner's 11-02 reversal stops — the pane stops padding twice), green by the law locally, and parked because it touches `Row` / `Tray` / `Figure`, which the layout redesign
carries. It is one `git merge` away; say the word. Before/after: `p7-pane-{buy,bargain,sell}-{390,320}.png`.
