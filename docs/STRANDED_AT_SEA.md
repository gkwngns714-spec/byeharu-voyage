# A ship that runs dry is forced home

> The owner, 2026-10-30: **"then the ships need to be fixed and be set on a right course. i mean if there
> is no provision left at sea - long time voyage, you will be forced back to the closest city, losing all of
> your cargo, damaged ship, but at that city you will receive your insurance if you've paid for it, and if it
> is too much to handle, the city should give donations."**

This is the design for that mechanic, grounded in what already exists. It is a design, not a build: the build
follows, one migration at a time, by the repo's own rules (self-assert, hunks, prod checks, `~/bin/bv-deploy.sh`).

## What prod does today (verified, read-only)

- Provisions are `ships.water_t` / `ships.food_t` (tonnes), drunk each settled voyage-day in `voyage.settle`
  (0007), floored at 0 by `greatest(0, …)`. **After that floor there is nothing**: a ship at 0 stores keeps
  sailing at SHORT_RATIONS wages ×1.5 (0007:940-946) until she arrives. There is no forced return, no cargo
  loss, no damage from running dry.
- The one endurance figure is `voyage.endurance_days(fleet)` — the lesser of days-of-water and days-of-food.
  SHORT_RATIONS already reads it (`v_end < short_rations_threshold × total_days`).
- Cargo is unloaded through one door, `public.fleet_unload(fleet, code, units)`.
- Insurance is built (0213): `public.insurance_claim(voyage, day, lost, cause)` pays a cargo loss at the
  policy's basis less `insurance_keep_pct` (10 %), from the insuring city's surplus. 0213's "decided by
  default" says in so many words: **"a later loss writer calls insurance_claim"** — storms, shoals and wrecks
  take no cargo today, so they are not claims. This feature is that later loss writer.
- Ship damage exists (storms shave `ships.durability`, 0007:958-969); a fleet whose flagship reaches 0 is a
  wreck (`UNABLE_TO_SAIL`). Recovery exists in port only: `public.tow_for` (0152) tows a wreck to the nearest
  shipyard, `cmd.do_repair` repairs a DOCKED fleet. A wreck **at sea** is refused `E_NOT_AT_PORT` (0152's own
  NOT-DONE note); ADRIFT is "not a wreck".
- Donations: `public.donate_for` / `cmd.donate` exist (ECONOMY_LOOP §12.2). The city→player safety-net grant
  the owner describes does not.

So every piece the owner names already exists except the connective tissue: a "ran dry" branch in the settle,
and a city grant for when the loss is too big. That is what this builds.

## The mechanic (one authority per concept)

1. **THE TRIGGER — ran dry.** In `voyage.settle`, after the day's consumption, a fleet at sea with crew aboard
   whose `voyage.endurance_days(fleet) = 0` has run dry. Same figure SHORT_RATIONS reads, so "dry" is a sharper
   reading of the same column, not a second rule. SHORT_RATIONS stays as the warning the day before.
2. **FORCED HOME — the closest city.** The voyage is cut that day and the fleet is forced to the closest open
   harbour. "Closest" reuses the reach table: the nearest open harbour reachable from the current leg's two
   roadsteads (`voyage.reach_from`, the figure the tow already reads) — no new distance authority, no guessing
   from a bare point. The voyage ends; the fleet lies **DOCKED** there.
3. **CARGO LOST.** All cargo is dropped through `public.fleet_unload` (the one unload), named `cargo_lost` in
   the day's payload, exactly as `voyage.raid_takes` names it.
4. **INSURANCE.** `public.insurance_claim(voyage, day, cargo_lost, 'FORCED_HOME')` pays the loss at the
   policy's basis less 10 % — only if the voyage was insured (a player who asked `SAIL … INSURED`; a merchant's
   laden voyage always is). Uninsured, nothing is paid, as the owner's "if you've paid for it" says.
5. **DAMAGED SHIP.** Hull damage is applied — a share of durability by the day's own roll, as a storm does —
   and the fleet is DOCKED, so the existing REPAIR takes her. If the flagship does reach 0, she is a wreck and
   the existing tow + repair path (0152) takes over; no new wreck rule.
6. **CITY DONATION — too much to handle.** After the forced home, if the house's purse + insurance payout
   cannot cover the yard's repair of the damaged fleet, the city donates the shortfall through the existing
   city-pays / DONATION path. One authority: the repair the yard quotes vs. the purse.

## New vs reused

- **NEW:** the dry-day branch in `voyage.settle` (trigger + forced home + cargo drop + damage + claim +
  donation); a new event kind (`FORCED_HOME`); a new voyage status value if the existing ones do not fit; the
  donation safety-net rule; whatever client surface shows it (the report and the fleet's own card).
- **REUSED, untouched:** `voyage.endurance_days`, `public.fleet_unload`, `public.insurance_claim`,
  `voyage.reach_from`, `public.city_surplus` / `public.city_pays`, the DONATION money path, `cmd.do_repair`,
  `public.tow_for`, SHORT_RATIONS.

## Decided by default (the owner may reverse each)

- **"Closest city" is measured from the current leg's two roadsteads**, not from a bare point at sea (reach
  measures from harbours only — 0152's stated reason for refusing sea wrecks).
- **Damage is a share, not a fixed amount, and never to 0 by itself**: the owner said "damaged ship", not
  "wrecked". A wreck still comes only from the existing paths, then is towed.
- **The donation covers the repair shortfall**, not a general restart purse — it is the city standing behind
  the specific loss the owner named, not a reborn refound.
- **Merchants get the same chain through their hourly upkeep**, the way the tow does (0152), so a merchant who
  runs dry is forced home, paid, and repaired, not parked.

## Open to resolve during the build (not guessed here)

- The exact dry-day trigger ordering vs. the hazard roll (consume → dry-check → hazard, or the hazard first),
  and whether a dry day also ends the voyage before the day's hazard.
- Whether an already-ADRIFT / sea-wrecked fleet (no voyage under sail) also gets a forced-home path, and what
  carries her there — the owner's first sentence ("the ships need to be fixed and be set on a right course")
  reads like a yes; this decides whether it is one migration or two.
