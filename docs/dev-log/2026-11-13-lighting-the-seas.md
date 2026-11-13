# 2026-11-13: lighting the seas (0378 the players' step; 0379 the merchants' step)

**Owner row 324** (2026-11-13): *"do all, make everything work. open them if everything is built and is workable."* Row 166: far seas ask a title and the
fleet's wave resistance. **Nothing here is lit or deployed by an agent. The lead lights, on the owner's word.**

## Why the light is a guarded step and not a switch thrown by a migration (decided by default)

The brief asked for a lighting migration whose guards raise. Built as asked it cannot live in the chain:

- A migration is applied to **every** world of the chain: CI's disposable chain, every developer's cached world, the private world in the browser and every
  replay from zero. Those worlds hold 13 probe companies, 4 of them lying at Accra and Acapulco, and `fleet_room_bite` is off there (it was lit on prod by
  hand, never in the chain). A file that raised on "no company lies in a closed sea" or "fleet room is on" would fail on every one of them, for ever.
- A file that lit without those guards would shut every far sail of every existing proof and browser spec (they sail title-1 probes across oceans), and
  the lit switch could not be told apart from prod's own state.
- The guards read **live** data (where every company's fleet lies this minute). They belong to the moment of lighting, on the world being lit.

So each lighting migration installs **the step** and **the read of its guards**, lights nothing, and the lead lights with one statement, as every switch
since W6 has been lit (Route A), but with the guards and the news inside the statement:

| | 0378 (players) | 0379 (merchants) |
|---|---|---|
| the guards, as figures (STABLE, a prod check) | `public.sea_conditions_ready()` | `public.sea_conditions_npc_ready()` |
| the step (VOLATILE, server-only) | `public.sea_conditions_light()` | `public.sea_conditions_npc_light()` |
| what it does | refuses naming every failed guard; else `sea_conditions_bite` true + news `update:0378` | refuses the same way; else `sea_conditions_bite_npc` true + news `update:0379` |

The news lint is satisfied honestly: the one `news_update` call of each file is inside its step, so the row is posted when the light happens, not at deploy.

## 0378: the players' guards (each one raises; the step changes nothing when any fails)

| Guard | Why |
|---|---|
| `wall_reads_in`: 0376 is deployed (`public.far_powers`, `world.sea_zone_map`) | the page can say why a sea is shut, and nobody is founded in a far sea |
| `fleet_room`: `fleet_room_bite` is on | the fleet's wave resistance is an AVERAGE: a barca and a caravel in one fleet read 19 and cannot cross the Doldrums (24); she must be able to sail them apart |
| `fleets_in_closed_seas` = 0 | a company's fleet lying in, or under way to, a harbour whose sea refuses her could never leave it |
| `capitals_closed` = 0 | a company whose country's capital lies in a sea her title does not open |
| `route_legs_closed` = 0 | a standing route with a leg that would be refused. Guarded rather than paused: pausing a player's route from a lighting step is a change to her property; the lead tells her or waits |

Told, not guarded: `queued_sails_closed` (each such queued SAIL fails with its reason when it runs).
Not guarded, a known gap: a company can strand herself AFTER the light (she moves her big ship out of a fleet lying in the Far East, or loses it in a fight).
The gate then tells her which of the two is short; a "way home" rule is a later slice (the parent's design section).

## The step list for the lead: players (`sea_conditions_bite`)

Order of deploys first: 0376, 0377, 0378 (and 0379) in number order, each by `~/bin/bv-deploy.sh`, each with its own PROD CHECKS. None of them lights.

1. `fleet_room_bite` must already be lit (its own window, its own after-check).
2. Pick the moment: about 20 minutes before a :37, never at :06 to :08 or :36 to :38 (the standing rule).
3. Read-only, each one statement:
   ```
   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/sea-conditions/volatility.sql
   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/sea-conditions/impact.sql
   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/sea-light/volatility.sql
   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/sea-light/before.sql
   ```
   Wanted: `guards.ready` true. Keep before.sql's row: it is the window's baseline. Not ready: stop; impact.sql names the company and the reason.
4. Light (the one write; the owner's word covers it, an agent never runs it):
   ```
   npx --yes supabase@2.120.0 db query --linked "select public.sea_conditions_light()"
   ```
   It answers its figures with `lit: true`, or raises `sea_conditions_light refuses: ...` and changes nothing.
5. At +1, +5 and +30 minutes: `scripts/ops/harness/sea-light/after-check.sql` and `bash scripts/ops/health.sh`. Wanted there: switch true, news_row 1,
   `fleets_in_closed_seas` 0, `merchant_refusals` 0, beats errors 0 with avg <= 3000 ms and p95 < 5000 ms, departures not fallen to 0 with players online.
6. **Rollback, at once:**
   ```
   npx --yes supabase@2.120.0 db query --linked "update public.world_config set value = 'false'::jsonb where key = 'sea_conditions_bite' returning key, value"
   ```
   Every passage is then judged as before the light (proof 71 SL_BACK). The news row stays. Forward removal of the step: `sea-light/rollback-0378.sql` (a draft).

Rollback signals: a fleet of a company in a closed sea after the light; departures of companies at 0 with players online; the arrivals beat past its line;
a company refused again and again from one screen (a page offering what the server refuses).

## 0379: the merchants' guards and step list (`sea_conditions_bite_npc`)

| Guard | Why |
|---|---|
| `players_lit`: `sea_conditions_bite` is on | the design's order (section 6: S3 is "lit after S2's window"): one change a window, so each after-check reads one thing. Decided by default; the code of the two switches is independent, so the lead can reverse the order by lighting with the plain Route A line instead of the step |
| `merchants_with_no_open_leg` = 0 | the "no open loop" figure: a merchant on a loop the sea closes who has known legs out of the harbour her loop starts at and would keep none. Locally 0 of 837 |

Told, not guarded: `loops_closed` (179 locally as founded; the planner moves each at her next lap start), `closed_at_sea` (they finish their trip),
`courses_not_remembered` (sampled live).

What the simulation says to expect (docs/dev-log/2026-11-13-merchants-under-the-sea-rule.md): every merchant on a closed loop moves to one her hull can hold
at her next lap start; about one merchant in a hundred more waits in port than before (9 of 837 locally); fourteen far harbours lose every merchant call
until the far traders (S4) exist; a lap start costs no more than before.

Steps, after the players' window is closed and clean:
1. Read-only, each one statement:
   ```
   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/sea-merchants/volatility.sql
   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/sea-light/before-npc.sql
   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/sea-merchants/after-lit.sql
   ```
   Wanted: `guards.ready` true. Keep after-lit.sql's row: the baseline (`laid_up`, `no_buy`, `beats`).
2. Light: `npx --yes supabase@2.120.0 db query --linked "select public.sea_conditions_npc_light()"`
3. At +5, +15 and +30 minutes: `sea-merchants/after-lit.sql` and `bash scripts/ops/health.sh`. Wanted: `loops_closed` falling and never rising,
   `closed_and_buying` falling to 0, `refused_at_the_door` 0, `laid_up` no more than the baseline plus about 1 % of the roster, beats inside their line.
4. **Rollback, at once:** `npx --yes supabase@2.120.0 db query --linked "update public.world_config set value = 'false'::jsonb where key = 'sea_conditions_bite_npc' returning key, value"`.
   A merchant already moved keeps her new loop until the planner moves her again.

Rollback signals: `laid_up` jumping well past the baseline; `refused_at_the_door` above 0; the arrivals beat past its line (the planner is in the beat).

News, merchants: EN "Merchants keep to seas their ships hold", KO "상선도 내파에 맞는 바다만 항해". Posted because players will see it: fewer merchant sails
on the far seas and no merchant calls at fourteen far harbours.

Proved locally: 0379 applies in 3.3 s (its read walks every merchant loop; budget 30 s); the step probed and rolled back (refuses on the chain's world: the
players' seas are dark). Proof 72 (5 markers): as shipped refused; every sea asking wave 99, 837 merchants with no leg, refused naming them; a ready world
lit with one news row in both languages, asked again refused; lit by the step a merchant is offered 18 of her 19 known legs, none through a closed sea; the
switch back. Proofs 70 and 71 green beside it.

Not verified for 0379: the read's cost on prod (about 1.5 s locally); `merchants_with_no_open_leg` reads the sea alone with 400 days of stores, so a merchant
whose only open legs are longer than her stores carry would not be counted (her stores rule is 0203's, unchanged, and she would be laid up as today).

## What was proved (local cached world, 0376 + 0377 + 0378)

- 0378 applies in 0.12 s; its self-assert: the two functions server-only and of the declared volatility, nothing else moved; the step probed and rolled
  back (on the chain's world it refuses naming fleet room and the four fleets in far seas); the wall forced on and rolled back: the gate's answer equals the
  one rule for all 13 companies' fleets to Funchal and to Las Palmas, and a title-1 fleet is free to Funchal and refused Las Palmas by Macaronesia.
- Proof 71 (8 markers): as shipped not ready and refused; each guard red alone (fleet room; a fleet at Accra, and the same under way; a capital at Sakai; a
  route leg through Macaronesia); a ready world lit with one news row in English and Korean, asked again refused; the wall and the sail door; the switch back.
- The four harness files run locally and answer as documented.

## Decided by default

1. The light is a guarded step called by the lead, not a switch thrown by the migration (above).
2. A standing route that would be refused is a guard, not an automatic pause.
3. Queued SAILs into a closed sea are told, not guarded.
4. News, players: EN "Seas ask a title and a sturdy ship", KO "바다마다 작위와 내파 필요".
5. `seas-light` is built on a merge of `seas-npc` (0377) and `seas-wall` (0376), so its proof reads 0376's `short_title` / `short_wave`.

## Not verified

- Nothing was read or run on prod. `ready` on prod is unknown until before.sql is read there.
- A plan refused at the press is written to no table, so no check can count how often players meet the wall; after-check.sql counts only queued SAILs
  refused when they ran.
- The Korean news line was not read by a Korean speaker other than this agent.
- The step under two callers at once (two leads lighting in the same second) was not tried; the second would light an already lit switch or refuse.
