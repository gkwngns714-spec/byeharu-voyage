# 2026-11-06 - A house has a regard (migration 0319, slice W1, DARK)

Branch `a-house-has-a-regard` · migration `supabase/migrations/20260818000319_a_house_has_a_regard.sql` · proof `scripts/db/proofs/27_regard.sql` · seam `tests/rpc.regard.spec.ts` and `tests/map.townhall.spec.ts` · mutation harness `scripts/ops/harness/regard/proof-0319.mjs` · prod check `scripts/ops/harness/regard/before.sql`.

## The order
Owner row 288: *"we need to build systems such as affinity prior to the system"*. `docs/WORLD_POWERS.md` section 2.1, slice W1, the first foundation after W0a and W0b. Nothing that fights is built until W1-W5 are done.

## What is built, all dark (`regard_enabled` false)
| Part | Where |
|---|---|
| Earned points only, so a merchant has no row | `public.house_regard` |
| One reader, one writer | `public.regard_of`, `public.regard_add` (event `REGARD_CHANGED`) |
| Five bands from one knob | `public.regard_band`, `regard_bands` |
| Multiplier on tax and dock fee | `public.regard_factor`, one hunk each in `world.tax_rate`, `public.port_fee` |
| Gifts and stakes earn it | `public.regard_gift`, hooked in `public.donate_for`, `public.invest_for` |
| `FINE`, a moved kind | `public.fine_for`, `cmd.pay_fine`, event `FINE_PAID`, through `public.pay_city` |
| The hall's line | `public.regard_line`, inside `dues`. Relationship shows the band; the purse line adds `Wary -180`; a `Fine` row and `Pay fine` button at a capital (`src/live/FineRow.tsx`) |
| Words | EN and KO; Report, Stats sector, History lines, refusal codes |

New knobs, all from the migration, none on an existing key: `regard_enabled` false, `regard_half_life_hours` 72, `regard_stance_base`, `regard_bands`, `regard_per_100k` 10, `regard_fine_per_point` 200.

## Why the hall line goes through `port_dues`
0317 cuts hunks in `world.town_hall`. `world.town_hall` already concatenates `public.port_dues`, so 0319 does not touch it. The trade board's `dues` carries the same term, which is correct and also dark.

## Dark
- `regard_factor` answers the integer 1, so numeric × 1 keeps its value and its scale. Proof 27 compares tax, fee and dues as text against the pre-image bodies, over every stance, human and merchant, with -9,000 planted under both.
- Cost dark: one `world_config` read per quote. No row of `house_regard` is read.
- `REGARD_CHANGED`, `FINE_PAID` and `FINE` cannot occur dark: `regard_add` returns before writing and `fine_for` refuses `E_NOT_IN_USE`.

## Decided by default (the owner may reverse)
- **A fine is a way back, not a way up.** It buys back earned bad points only, never the stance base. Without this, a fine at 200 d. a point is 50 × cheaper than a donation at 10,000 d. a point, and Honoured from Neutral costs 100,000 d.
- A fine is paid at that country's capital, a fleet docked there, as Donate. It is held to what is owed and to her purse. It buys no influence.
- The gift hook is in W1: section 2.1 prices it, it can happen today, and no later slice names it.
- `tariff_rate_max` still caps the rate on top of the multiplier. A Hostile company at war meets the cap, so her ×2 is clipped. The dock fee has no cap.
- A free city has no regard: multiplier 1, no line.
- The score is rounded before the band, so the band always agrees with the whole number the player reads.

## What the owner should know before lighting (not now)
- **The base alone moves every company on day one**, with no row written: home is Friendly (× 0.9) and war is Wary (× 1.25).
- Today regard can only rise: gifts and stakes. Nothing lowers it until W11, so `Pay fine` cannot appear for a real player before then.
- A dock fee and a tax read regard at settle time, not at the ETA. A late settle could read a slightly faded score. The mayor's rate has the same property today. The beat settles within seconds.

## Not in this slice
The attack, sink and pirate rows of section 2.1 (W11, W18, W19). No attack verb exists. No PvP: the law stands, and the owner's "not for now" on pirate players attacking other players' merchants is honoured by there being no attack at all.

## Measured
- Local, cached world, 299 of 300 files restored, none from zero: the file applies, 7 hunks once each and reversing, self-assert about 60-80 ms on the small world. Not measured on a populated world: it reads the catalog and one knob only, and 0314's digest of every function took about 70 ms on prod.
- Proof 27: all 12 markers. 26 of 26 mutations red, each for its intended reason (two of them are red through the next door along, written so in the harness).
- Deploy order: 0316 and 0317 from their branches, then 0319, then proof 27: green, self-assert 83 ms (`--first=`).

## PROD CHECKS (read-only, `scripts/ops/harness/regard/before.sql`, one SELECT, stable functions only)
Run 2026-11-06 at head 0315: all 7 pre-images occur exactly once on prod's live bodies. `regard%` keys 0, `FINE` word 0, `ord` 48 free, `house_regard` absent, `regard_of` absent. **Run it again before deploying, at head 0318.** The fix that takes 0318 was on no ref when this was written, so this check is the only proof it left the 7 pre-images alone. Wanted: every `times` 1, the rest as stated in the file's header.

After the deploy, also read-only: `regard_enabled` false; `house_regard` 0 rows. No after-check window is owed: nothing changes for anyone while dark.

## Rollback
`regard_enabled` stays false. To remove: a new forward migration swaps the file's old and new hunks, then drops what it created.

## Not verified
- Nothing has run on prod.
- `disposable-chain` on real Postgres roles: CI decides. Local runs are PGlite.
- Lit behaviour with real players: only probes.
- The band words and the Fine row in a real browser on a phone at the owner's DPR: the spec drives them headless at phone size, no picture was looked at.
- Whether the bands and half-life feel right: only play shows.
