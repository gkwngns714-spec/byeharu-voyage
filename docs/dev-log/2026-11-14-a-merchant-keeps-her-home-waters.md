# 2026-11-14: a merchant keeps her home waters (0400, so the merchants' sea light can be lit)

Owner rows 166 ("NPCs under the same rule") and 324. Design: `docs/SEA_CONDITIONS_AND_REGIONS.md` section 10.

**State on prod when this was written:** head 0399. `sea_conditions_bite` (players) lit 2026-11-14 15:56 UTC. `sea_conditions_bite_npc` is FALSE. Nothing
here is deployed and nothing is lit by this file.

## Why

The merchants' guard refused on prod, rightly (`sea-light/before-npc.sql`, 16:04 UTC): `merchants_with_no_open_leg` 8, `loops_closed` 309 of 861,
`closed_at_sea` 236. Eight merchants have no known leg from home that their hull holds; lit, each would be laid up for good. The local world has none
like them (0 of 179 closed loops), so what they are is unknown until the lead runs the new read:

```
npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/sea-merchants/no-open-leg.sql
```

It names each one: company, fleet, hulls and wave, home and its sea with what that sea asks, her known legs, the nearest of them with the sea that refuses
it, the nearest harbour her wave holds, and how many of her legs the floor of 0400 opens. It counts exactly as the guard counts and runs at head 0399.
Checked locally on an analogue: 300 merchants put into fustas (wave 6) in a scratch world; it listed the houses of Callao and Panama, refused by their own
coast (asks 12), with 6 and 7 of 7 legs opened by the floor.

The likely shape, from the code: a hull whose wave is under what her OWN home sea asks. Oared hulls read 6 to 8 and 18; every coastal sea outside Europe
asks 8 to 16. A size-1 hull homed at Tokyo, Banda, Timor or the Sea of Japan (they ask 16) is another. Either way she is refused at her own quay.

## What 0400 does

Merchants get the two floors the players got in 0396, judged on wave only as 0397 judges them:

- `public.npc_sea_floor(fleet)`: her wave, what the sea she lies in asks, what her home's sea asks (her house's home port, else her route's first stop).
- `public.npc_sea_shut(wave, dest, course, lie_title, lie_wave, home_title, home_wave)`: 0397's question through `public.sea_judge` (0396). A sea of the
  rank of the sea she lies in, or of her home's sea, asks her hull no more than that sea asked.
- Three hunks, each once and reversing: `public.npc_feasible_legs` (the legs offered), `public.npc_loop_sea_shut` (is her loop closed) and
  `public.sea_conditions_npc_ready` (the guard counts as the planner will judge).
- Off = unchanged: the floors are read only while the switch is on (self-assert: 40 merchants' legs the same text; proof 95 `MH_OFF`).

"No merchant without an open leg, by construction" holds when a merchant has at least one known leg that stays in seas of her home's rank and asks no
more wave than her home's sea. That is every merchant whose home has a neighbour in the same sea. It is not a theorem for a home that is alone in its
sea: the guard still counts, and the lead reads it after the deploy.

## A merchant at sea when the switch is lit (the 236)

Read in the code, not changed: the sail door never asks a merchant (`public.passage_gate` returns null for `is_npc`, 0107; proof 92 `SM_DOOR`), so she
finishes the leg she is on and every later leg of her lap. At her next lap start `public.npc_plan` finds her loop closed and reviews it at once (0397):
she takes the best open loop on offer, or is laid up by the rule that already exists (0181) and is planned again at every tend. With 0400 the loops on
offer to her include those in the waters of the rank she then lies in and of her home's rank.

## The simulation, with the floor

`sim.mjs --name=20260818000400`: the local cached world, 837 merchants, each planned once at a lap start by the real planner.

| | Dark pass | Lit, before 0400 (2026-11-13) | Lit, with 0400 |
|---|---|---|---|
| Loops with a closed leg after the pass | 469 | 0 | 0 |
| Laid up | 54 | 62 | 55 |
| Plans that failed | 0 | 0 | 0 |
| Harbours that lose every merchant call | 0 | 14 | 16 |
| Merchant stops after the pass (3,302 before it) | 3,175 | 2,857 | 2,871 |
| A lap start, mean / max | 197 / 447 ms | 214 / 434 ms | 197 / 416 ms |

The 16: AMB BND CPT DIL GAL HAG HOB KOL MAK OLD PLO POR STG SYD TER TID, 142 of 3,302 stops (4.3 %). None has a local house; S4 restores them. Stops fall
9.6 % lit against dark; about a third of the loss is at those 16 harbours, the rest is loops that became shorter.

## Cost

`public.npc_feasible_legs`, lit, mean of 20 merchants on PGlite: 2.1 ms before, 6.4 ms after (the judge is three calls of the rule a leg where it was
one). A lap start asks it for up to sixteen harbours, so a lit lap start grows by up to about 70 ms. If the lit window shows lap starts past budget, the
judge can be asked once a leg with the zones split in SQL; not done here.

## Checks

- 0400 applies on the cached chain at head 0399 with its self-assert (2.6 s; budget 45 s).
- Proof 95; proofs 92 and 94 after it.
- `before-0400.sql`, `after-0400.sql`, `no-open-leg.sql` pass the read-only reader; the rollback draft returns the three bodies to their pre-images.

## Not verified

- What the eight on prod are.
- Whether `merchants_with_no_open_leg` reads 0 on prod after 0400: read `sea-light/before-npc.sql` after the deploy.
- Prod cost. Pirate merchants under the floor were not looked at separately.
- The simulation is one planning pass at lap 0 on a static local market, as before.

## Decided by default

1. A merchant's home is her house's home port, else her route's first stop.
2. The floors open a rank, as for players (0396): not every easier sea.
3. S4 (far-trader houses) is still not built; see the PR body for what the simulation says it would restore.
