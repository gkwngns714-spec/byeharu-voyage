# 2026-10-19/20 — 0211: a cargo can be insured (insurance v1) — `osn-insurance-v1`

The owner asked "what about insurance" twice (2026-10-19). Built by default; every choice below is his to reverse.

## What it is
- **The price comes from ONE function, `voyage.risk_quote(voyage)`:** for each day of the voyage, the raid roll's own
  hazard chance (`voyage.hazard_roll`'s `p_hazard` column — the roll's outcome is never read) × that sea's PIRATES share
  (`voyage.sea_mix`) × what one raid carries off on average (knob `insurance_raid_loss` 0.084 = prod's PLUNDERED
  share 78/348 × the mean plunder 0.375). `loss = 1 − Π(1 − that)`. The pirates design (PR #268, Z1/Z7) re-cuts this
  one body when danger becomes a frozen number; nothing else about insurance moves.
- **The price:** `public.insurance_price(value, risk)` = ⌈value × risk × (1 − keep 0.10) × (1 + margin 0.10)⌉, at least 1.
- **Who insures:** the HARBOUR the ship sails from, paid through `public.pay_city` (ledger `INSURANCE`). The policy is
  `public.insured_voyages` (server-only; cargo and cost basis frozen at departure).
- **The payout:** `public.insurance_claim`, read by `voyage.settle`'s PIRATES arm after `voyage.raid_takes`: the lost
  units at the policy's basis, less the 10 % deductible, from the city's surplus (`public.city_pays`, ledger
  `INSURANCE_PAID`); what the purse cannot cover is recorded as `short`. Purses dark: paid in full.
- **A plundered hold now loses cargo.** Since 0007 PLUNDERED took nothing (prod, lit: 78 PLUNDERED of 348 raids,
  0 STRIPPED → no cargo ever lost). `voyage.raid_takes`: PLUNDERED takes 25–50 % of every good by the day's own roll
  (DESIGN B.6); STRIPPED all of it; out through `public.fleet_unload`. The day's payload names it (`cargo_lost`).
- **Merchants insure every laden voyage** (`cmd.do_sail` → `public.insure_voyage`, always for an NPC) **and the free
  refound is retired**: `npc_tend_houses` loses its refound pass, the two knobs and `public.npc_worth` go, the merchant
  card serves `insurance {claims, paid, short}` in place of `refounded`. A ruined merchant sails on with what she has.
- **Players ask with `SAIL <port> INSURED`** (`cmd.parse`, `cmd.verb_schema` enum `insurance`). Every SAIL's result
  carries `insurance` — quoted unasked (`insured: false`, the price it would cost), so `cmd.preview` shows it.
- **The books:** `standing_route_laps.insurance` (paid less paid back) comes off a lap's net; `world.books` names
  Insurance · Insurance paid; `world.insurance()` is the one client read (registered, authenticated).

## Client
- Map › Send fleet: under Keep, `Insurance 12 🪙` with the press **Insure the cargo** / **Insured**, only when the dry
  run quoted a price (a laden hold, in port). The send writes `SAIL <dest> INSURED` through the one line composer.
- Plan builder: one press **Insure the cargo**; the laden SAIL lines carry INSURED (planLines.ts), empty legs never.
- Plans: an **Insurance** section (world.insurance) — insured voyages under way and what was paid — only when there is any.
- History: `Gaivota's cargo (2,000 🪙) insured at Lisbon for 12 🪙.` · `Lisbon's insurance paid Gaivota 1,800 🪙 for
  cargo lost to pirates (worth 2,000 🪙).`
- Merchant sheet: `insurance paid twice, 1,800 🪙` in place of the refound line. WORDS.md rows added; never "premium".

## Measured
### Prod, read-only (2026-10-20, head 0208)
- All 16 hunks occur exactly once in the live bodies (11 functions); heads once; `insured_voyages` absent; the probe
  ids and `Casa do Seguro 0211` free; LIS/FNC and their roadsteads present; 837 merchant fleets, 821 houses.
- The only bodies naming the retired knobs / `npc_worth` are `npc_tend_houses` (the hunk removes them) and ONE
  stale comment line in `public.npc_tend` — re-cut by a 16th hunk, or the file's last assert would have failed on prod.
- Raids with the fight lit: 348 in 211,909 sea-days (0.164 %/day) → expected loss 0.0138 % of cargo per sea-day.

### The premium, over the merchants' 837 real voyages (sim world at 0208 + 0211; `insurance_margin` 0.10)
| route | n | avg nm | avg days | risk (avg) | price, % of cargo | price on 2,000 🪙 |
|---|---|---|---|---|---|---|
| < 500 nm | 142 | 377 | 3.6 | 0.042 % | **0.046 %** | 1 |
| 500–1,000 | 338 | 719 | 5.5 | 0.057 % | 0.061 % | 2 |
| 1,000–2,000 | 154 | 1,451 | 10.5 | 0.123 % | 0.127 % | 3 |
| 2,000–4,000 | 155 | 2,834 | 20.8 | 0.269 % | 0.271 % | 6 |
| 4,000+ | 48 | 4,923 | 37.8 | 0.563 % | **0.562 %** | 12 |

The quote matches the measured world (0.010–0.015 % per sea-day against prod's 0.0138 %): raids are rare today, so
insurance is cheap — 1–12 🪙 on a 2,000 🪙 cargo. It becomes a real price when the pirates slices raise the danger.
`risk_quote`: 3–12 ms on a 5-day voyage in the probe; 77 ms average over the 837 voyages (PGlite, loaded machine).

### The self-assert (local, the real applier)
Whole chain 12.2 s with the prefix restore; 0211 alone ~1.5 s. Receipt: 2,000 insured LIS → FNC over 5 days at risk
0.000597 for 2 🪙, charged once, preview quoted without charging, unasked SAIL identical to the pre-image but for the
quote; PLUNDERED 5 days took its 25–50 % shares exactly as re-derived, paid 1,531 by Lisbon and none by Funchal;
SHORT paid 50 of 1,396 and recorded 1,346 short; STRIPPED paid 1,800 of 2,000; the merchant insured herself for 1 and
sailed uninsured when broke; the pre-image refounded the broke house once and the new body never; INSURED parses and
the pre-image refused it; a 23-hazard-day passage (CALM, FAIR_WIND, STORM) and a hazard-free passage to arrival settle
to the byte the same under both bodies; readers one each; walls hold; 16 hunks reverse; ACLs unchanged.

### Paired merchant sim (20 min, two arms side by side, prod's state of 2026-10-19 23:37 UTC)
_(filled in below when the arms finish)_

## What went wrong on the way (2026-10-20), recorded
1. **The first local apply ran 70 min in P7 and was killed.** P7 forced a hazard EVERY day with only STORM/CALM/
   FAIR_WIND in the mix and set the voyage back 30 real days (≈ 28,800 game-days of clock). A storm costs 36 h and a
   calm 24–96 h, so the ETA ran away faster than the days were settled; the loop ends only when the clock catches the
   day (~10,000 settled days). The same would have run at db push. Fixed: the weather passage is set back EIGHT
   voyage-lengths (≤ ~40 voyage-days of clock, whatever the rolls; 23 days, 147 ms) and is not asked to arrive; a
   second, hazard-free passage proves the arrival arm (LANDFALL, VOYAGE_REPORT) in 49 ms.
2. **Four probes could never have passed.** P1, P5, P6 and the parse probe wrote their `probe_0211` row INSIDE the
   block they then rolled back with `RB_0211`, so the asserts always saw no row. The rows are written after the block.
3. `o->'q' - 'insurance'` parses as `o -> ('q' - 'insurance')` (`-` binds before `->`); parenthesised.
4. The generator sources (`docs/dev-log/insurance-wip/`) were a second copy of the migration and were deleted; the
   migration file is the one source.

## Decided by default (the owner may reverse each)
- Cargo only; one voyage per policy; a turn at sea (DIVERT) ends the cover.
- The insurer is the port she sails FROM; nothing is insured from open water (`E_NO_INSURER`).
- The price ignores the fleet's guns in v1 (the fight's measured average loss); a per-escort price is Z7's.
- Merchants insure every laden voyage; a player insures by asking. A merchant who cannot pay sails uninsured.
- PLUNDERED takes 25–50 % of every good. Storms, shoals and wrecks take no cargo today, so they are not claims.
- A ruined merchant is not refounded or rescued.
- Player standing routes are not insured in v1 (the plan builder's press writes the laden SAIL lines only).
- `insurance_margin` 0.10 is NOT the owner's figure; `insurance_keep_pct` 0.10 is his "10 % deductible".

## Not verified
- On prod: nothing is written before the deploy; the probes' volatile paths ran on the local 0208 image only.
- The site: the map tray and the plan builder were not driven in a browser (headless only; specs cover the seam).
