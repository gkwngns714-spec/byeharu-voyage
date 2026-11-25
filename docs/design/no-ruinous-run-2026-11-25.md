# No ruinous run (0502 `no-ruinous-run`, dark): the design, before the build

The owner's own company, 24-25 Nov: repaired at 23:36 for 736 coin, purse about 8,240, the Best run sent her Island of Mozambique ->
Palma -> Diego Garcia with 899 black coral bought. At 00:22 a storm's safe default took 5,000 (`SEA_LOSS`), the dock fee took 3,233,
the purse was 0, and she lay wrecked in a harbour with no yard. Read in the bodies: **the Best plan weighs nothing of that.** It
ranks cards by profit a second (`public.fleet_job_plan`); a fixed run's quote (0497 `public.fleet_run_quote`) counts wages, stores
and dock fees into the PROFIT, but no plan asks whether her PURSE can pay them on the way, and none keeps anything back for a repair.

## The rule, in ten lines

1. **One reading, `public.run_need(player, fleet, from, lines)`** (STABLE, server only): what a run asks of her purse before its sale
   pays: `fees` = the wages, stores and dock fees of its sails (`public.job_trip` -> `world.trip_cost`, the map's own quote, no second
   estimate) + the crew she lacks (`public.crew_hire_cost`); `buy` = the BUY's quote; `reserve` (line 2); `after` = purse - buy - fees.
2. **The repair reserve** is the yard's own price for mending her whole fleet from nothing (`public.fleet_repair_cost` on the sum of
   her hulls' full durability and her fittings) plus, while choices at sea are lit, the largest loss a safe default can take from this
   cargo (`public.sea_choice_options`: a storm's shelter, 0.25 of the stake). No new knob: every figure is an existing price.
3. **Passive (the job tick), the guard:** a plan's lines are issued only when `after >= reserve`. All kinds: Best, the near round, fixed,
   bring home, the haul.
4. **A buying run is cut before it waits:** the BUY names the units that leave `after >= reserve` (as 0497 cuts a BUY to the sale
   harbour's allowance). She sails with a smaller cargo and a purse that survives the trip.
5. **No units fit:** the job WAITS (`{wait: low, code: reserve}`, "purse 8,240: this run asks 3,233 in fees and keeps <the reserve> for a
   repair"), asked again 10 minutes on, not stopped, nothing issued. `world.workers` serves it as `wait`, as 0497's.
6. **Cargo already aboard is carried to its sale** when the sale's quote covers the fees (the run nets coin); otherwise she waits where
   she lies. A sail home with an empty hold (the near round) is guarded like any run.
7. **Active trading (the Trade tab), the same reading, as words, not a wall:** the trip's quote serves `fees`, `reserve` and `after`;
   the desk shows "Purse after <coin> · Repair reserve <coin>" in the warning tone when `after < reserve`. Her press is not refused:
   active trading is her own judgement (the owner's specification, 25 Nov).
8. **Provisions and crew in a passive run's settings** (the specification: "PASSIVE METHOD should also require you to make provision,
   crew up in the setting") are a later slice; until then the guard counts what the SAIL will buy by itself (0225: her leg's
   stores, even on credit) and what the Inn would charge to man her, so neither can surprise the purse.
9. **Danger times hull** is NOT in this slice: a leg's danger is frozen at departure (`voyage.leg_danger`) and no read prices a hull's
   expected loss on a course yet. The reserve covers the cost of the worst case (a whole repair) instead of its odds. Said plainly.
10. **Dark behind `run_guard_enabled`**; lit by the lead after a measured window (runs started, coin an hour, waits, at five homes,
    before and after, by the real tick: `hq-figures/measure-*.mjs`), with her exact run as proof: at 8,240 coin it is cut or waits.

## What it needs before it can be built

`public.fleet_job_plan` after the stack's renumbering (0498 jobs-never-lose, 0499 near-round, 0500 fit-to-sail), because the guard is a
hunk at the one place every kind's lines are made. On 25 Nov the remote had only 0497 + 0498 renumbered (`stack-jobs-never-lose`); the
build starts from the renumbered `fit-to-sail` tip.

## Decided by default (the owner may reverse)

- The reserve is a whole repair, not a part of one: a hull at 0 is what stranded her.
- A cut run, not a refused one, where a smaller cargo is safe.
- Active trading is warned, never blocked.
- The tow is not in the reserve: with a repair's coin kept, a wreck can sell (0497) and tow herself.
