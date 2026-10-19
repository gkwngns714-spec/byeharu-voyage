# 2026-10-19 — an out-of-reach city reads in plain words (client only, `ui-plan-wording`)

**The order.** The owner's map-UX rule is *no jargon*. `src/features/command/plans/planLines.ts` still told a player
`Antalya cannot be reached in legs of 1,700 nm — needs Navigation 3 (reach 2,600 nm)` and, with no reach served,
`legs of her reach`. Rewrite the player-facing strings in plain words; a distance reads as days of sailing; if miles
must appear, write "miles".

## What was wrong, and where

- `reachWords` (planLines.ts) said `nm` three ways and `her reach` once. `tests/words.spec.ts` bans `\d\s?nm\b`, but
  it blanked every `${…}` hole to a space, so `(reach ${formatInt(n)} nm)` read as `(reach   nm)` — no digit, no hit.
  The guard existed and could not see the shape every unit actually ships in.
- The same concept had a second copy: `whyNot` in `src/features/command/markets/GoodTicket.tsx` (the best-trade card
  and both city lists), with its own `nm a leg`, `passage` and `stores` — three words docs/WORDS.md bans. `viaLine`
  there was a second copy of `viaWords` too, with a different separator. Two authorities for one sentence.
- `whyLines.ts` printed the haul term as `1,234 nm`.

## What changed

- **One wording.** `reachWords(row, reachBoard(board))` in planLines.ts is the only place the reason is written. The
  plan builder's note and the best-trade card, the Buy-at rows and the Sell-at rows all read it after the city's name
  and a dash. `whyNot` and `viaLine` are deleted.
- **Days, not miles.** A leg's length is `days at sea` at the fleet's served speed (`legWords`), through the same
  `daysAt` the plan already uses to decide a PROVISION line. Miles appear only when the board served no speed, and
  then through `formatMiles` ("2,600 miles").
- **The three answers:**
  - `farther than your navigator can plot in one leg (up to 14.2 days); Navigation 3 plots legs of up to 21.7 days`
  - `farther than your navigator can plot in one leg (up to 14.2 days); no navigator plots one that long (33.3 days at
    the most), and no chain of ports gets there`
  - `its longest leg is 20.8 days at sea, more than your 36.0 days of supplies`
- **The guard sees holes now.** `tests/words.spec.ts` reads a `${…}` hole as `0`, so a unit abbreviation after a
  figure is caught wherever it ships. Run over the whole client it finds nothing else.
- `tests/planWords.spec.ts` (pure) pins the three answers, the miles fallback, and that no answer says nm / her /
  passage / stores. docs/WORDS.md gains the row.

## Verified

`tsc -b`, `eslint .`, `tests/words.spec.ts` and `tests/planWords.spec.ts` green in the worktree. No migration, no
server change, no `.env.local`.
