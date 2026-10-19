# 2026-10-19 — COMMAND: every face changes in place (no pop-ups, no new screen)

The owner: *"at top right, when pressing plans, city, invest, i want the screen of the original command tab
to stay same, meaning no pop ups or no new screen, but reloading on the same page. get it?"*

## Before (local build, `before-*.png`)

| Face | 1440×900 | 390×844 |
|---|---|---|
| Markets | the terminal: three panes, faces at the top right | the list; a good opens its page as a tray |
| Plans | the header re-flowed into a phone column (faces stretched under it); the plan builder rose as a side tray over the right of the glass | the plan builder rose as a full-height tray |
| City | the same re-flow; the basket stood as a side tray over the right of the glass, and every trade / hire / job / supplies act rose there too | the basket (when it had lines) and every act rose as a bottom tray |
| Invest | the same re-flow; Invest / Donate rose as a side tray | Invest / Donate rose as a bottom tray |
| Profit | the same re-flow into a column | the column |

## After (`after-*.png`)

One frame for every face (`src/features/command/DeskFrame.tsx`). The header is the terminal's on every
face; the three panes keep the same grid, widths and borders. A face hands the desk its parts:

| Face | left pane | centre pane | right pane |
|---|---|---|---|
| Markets | watchlist | chart | ticket · trade tray · plan builder |
| Plans | Orders | Route | plan builder (else a one-line hint) |
| City | the city and its buildings (wrapping) | the building | basket, trade, hire, job, supplies |
| Invest | your holdings | the Town Hall | Invest / Donate |
| Profit | today, 7 days, seven bars | the day-by-day books | a one-line hint |

A tray opened inside a face no longer pops up: the desk provides a slot (`trayContext.ts`
`DeskTraySlot`), read in one place (`Tray.tsx`). A `docked` tray under it becomes a `pane` — portalled
into the right pane on a wide glass, in flow inside the face on a phone (scrolled into view when it
opens). A pane is a `region`, not a `dialog`. ManifestPanel draws its button in the slot (no peek there).
On a phone the parts stack (Plans: Plan, Route, Orders). Markets' good page on a phone is still a tray: it
opens from a press on a good, not on a face.

## Proof (local build, `.env.local` absent in the worktree)

- `tests/desk.inplace.spec.ts` (new), 1440×900 and 390×844: each face press keeps the header / Sheet the
  same element, the faces strip and (wide) the three pane boxes identical, shows the face selected, opens
  no dialog, keeps every tray inside the right pane; a plan stands inside the Plans face. 4/4 pass on
  the new build. Against the old build it fails 3/4 ("Plans moved the desk's frame", "the plan builder is
  a pop-up on Plans" at both sizes): it detects the old behaviour.
- `tests/wide.layout.spec.ts`: the two City › Trade tests that pinned the old 26-rem side tray now pin
  the tray and the basket to the desk's right pane. 6/6 pass.
- desk.city, desk.plan, desk.sweep, desk.terminal, desk.layout: all pass on the new build.
