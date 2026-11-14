# 2026-11-14: the roster is not kept waiting behind a ship the day's room cannot build (migration 0418)

**State: built, PR open, not deployed.** 0418 = 0417 + 1 (production head 0416; 0417 is the level benefits, PR #683). One hunk in `public.pirate_add`. No production read was made by the builder; the figures are the coordinator's read of `pacific-pirates/after.sql`, 18 minutes after 0414.

## What was seen

Roster built 0 of 108; 7 pirate fleets, all wrecks; the day's room 0 (spent 4,175,000, the morning's gifts, against a room of about 2.34 M); hoard 975.9 M.

## The cause, in the code

`public.pirate_add` adds one fleet a turn: the one `public.pirate_next_ord` names. That is 0339's own ships first (ords 1 to `public.pirate_size()`: 4 + 9 = 13 at this hoard), then the roster. Production had 7 of the 13, so the next was **ord 8**. Her build (`public.pirate_commission`, one xebec, 160,000, kind BUILD_NAVY) goes through `public.pirate_pay`, **inside the day's room**, and the room was 0. The build answered null, `public.pirate_add` returned null without moving its clock, and ord 8 was asked for again every minute. The roster's builds are outside the room (0414), but they were never reached.

None of the other suspects: the clock (`added_at`) was not the gate; the trading rule skips the add only in a run in which a ship traded (none did: all seven were wrecks); `pirate_size()` caps only 0339's ords; every hub has a yard in reach (0414 asserts it); the 400 M floor is far below 975.9 M.

**Would it have cleared by itself?** Only by luck. At 00:00 UTC the room is new (about 2.34 M). The first run mends the seven wrecks (280,000), pays, builds ord 8 (160,000) and gifts the seven pirate houses (560,000). Ords 9 to 13 need 800,000 more, ten minutes apart, until 00:50; the merchants' hourly gift pass at 00:07 takes 250,000 a broke house of the pirates out of the same room (16 this morning). The room is 0 again within minutes, ord 9 or 10 is the next wall, and the roster waits another day. A defect: the roster's pace was meant to be `pirate_add_minutes` alone.

## The fix

When the fleet named is one of 0339's own and the day's room does not hold what she needs now (her class's build cost, or an hour's pay to wake her), the add takes the next **unbuilt roster fleet** instead, in the roster's own order. 0339's ship keeps her place and is asked for again at the first turn the room holds her. With the room open nothing changes.

After the deploy: one roster fleet every 10 real minutes from the next run, whatever the room reads: 108 fleets in about 18 hours. Ords 8 to 13 are built on the days the room holds them.

## The guard

Proof 106, new marker `PH_NOT_BEHIND`: the day's room spent and one of 0339's ships pending, the add must build a roster fleet; the room open, the next add builds 0339's ship first. **Red first:** with 0418 taken out of the chain it fails with "the add answered NULL and built no roster fleet (the fault of 2026-11-14)". The file's own probe does the same on a rolled-back copy of the live rows.

## What the seven old wrecks do

They are stamped and waiting (five with a row in `npc_refit_waits`, "broke"); the room is 0 so nobody can pay today. At the first run of the pirates' job after 00:00 UTC, in this order inside the one run:

1. **The steps** (before anything else is paid): each wreck asks `public.pirate_refit_pay`: her own house's purse (0 today), then her home city (Port Royal for the ship homed there; Djerba, Goto and Lingga hold too little), then another pirate city (the hubs hold a few hundred), then **the hoard, inside the room**: 40,000 each, 280,000 in all. All seven are mended, manned and stored in that run.
2. **The add** (ord 8 if the room holds her, else a roster fleet).
3. **The hour's pay**, only if an hour has passed since the last pay run (a run that could pay nobody still moves its clock, so this may be up to an hour after midnight): 500 a fleet at work.
4. **The gift** (0415): each house of a fleet at work under the line is given 80,000 (up to 560,000), the pay's room for the rest of the day kept back first.

**The five marked unpaid take a detour.** A mended ship that is still marked unpaid is off duty: at her next step, a minute later, she is laid up at home (0339's rule), and a laid-up ship is not paid by the hour's pay. The add wakes her: 0339's ships come first in the add's order, one a turn, so the five are woken one every 10 minutes (each needs only 500 of room) and sail from then. The two that were paid sail for their haunts at 00:01. After the five, ord 8 and the rest follow as the room allows, and the roster takes every turn the room cannot serve.

So the refits come before the day's pay and the gifts, and all of it fits the new room (about 0.85 M of 2.34 M). What is left is then open to the merchants' gifts at 00:07.

## Still true, and not fixed here

The merchants' gifts of 0408 (250,000 each) do not keep the pay's room back; 0415 does that for the pirate ships' houses only. With 121 fleets the day's pay is 1.45 M of a 2.34 M room: a morning of sixteen merchant gifts would leave the fleets unpaid by afternoon, and an unpaid fleet sails home and is laid up until the next day. One line would fix it (the same reserve in `public.pirate_gift_pay` for a merchant house). Not done: it changes 0408's rule and was not asked for.

## Checks run

The file on the cached chain (main `c883d375`, head 0416): the hunk once and reversing, its probe; proofs 106 (8 of 8), 46 (20 of 20), 114 (8 of 8); 106 red first without the file; the rollback draft restores the pre-image md5 (`1212dc6813faff05512e5ab43e32e36c`); `before.sql` read on the local world before and after.

## PROD CHECKS

1. Before: `npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/pirate-add/before.sql`. Wanted: head ...0417; applied false; hunk 1. Write down `next_ord`, `old_pending`, `roster_built`, `room_today`.
2. Deploy: `~/bin/bv-deploy.sh <pr>`.
3. After, at +2 min, +30 min, +3 h: `... -f scripts/ops/harness/pirate-add/after.sql`. Wanted: applied true; `roster_built` up by one every 10 minutes whatever `room_today` reads (about 3 at +30 min, about 18 at +3 h); `added_at` moving.
4. Rollback: `scripts/ops/harness/pirate-add/rollback-0418.sql`, a draft.
