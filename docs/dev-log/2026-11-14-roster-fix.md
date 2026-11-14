# 2026-11-14 - 0418: the roster does not wait on the day's room

Row 330 (the owner's 180 pirate ships, 0414). Branch `roster-fix`. Harness: `scripts/ops/harness/roster-fix/`.

## What prod showed

Read-only, after 0414 went live at 13:30 UTC (13:48 from `pacific-pirates/after.sql`; 14:28 from one targeted read):

- roster built 0 of 108; `pirate_clock.added_at` = 2026-11-13 18:01, so nothing had been added for 20 hours;
- `pirate_next_ord()` = 8, `pirate_size()` = 13, hoard 975,969,673;
- 0339's ships are ords 1-7. Ord 1 is docked at Port Royal. Ords 2-7 are wrecks, wrecked at 13:27, waiting on a purse since 14:27, and five of them are unpaid;
- the day's room is 0 (4,215,000 spent today against about 2,342,000). Of the other pirate cities, only Flores has a surplus above 1,500 (32,344), which is less than one refit (40,000).

## The cause

`public.pirate_add` (0339, re-cut by 0414) adds `pirate_next_ord()`. That function lists 0339's ords (1 to `pirate_size()`, which is 13 at this hoard) BEFORE the roster. Ords 8-13 were never built, so the head of the queue is ord 8, a 0339 xebec. Her build is `public.pirate_commission`, which calls `public.pirate_pay('BUILD_NAVY', 160000)`. That payment is INSIDE the day's room:
`if public.pirate_spend_room(p_now) < p_amount ... return 0`. So `pirate_commission` answers null and `pirate_add` reaches

```
                else public.pirate_commission(v_ord, v_home, v_yard, p_now) end) is null then
      return null;
```

It does this every ten minutes and never gets to a roster fleet. A laid-up fleet at the head of the queue stops it the same way: its wake also needs the room (`if public.pirate_spend_room(p_now) < v_slice ... return null;`), and a fleet is laid up whenever an hour's pay finds the room at 0.

None of the other suspects stops it:
- unpaid ships and wrecks are not read by the add;
- the gift and the pay run after the add;
- 0415's "a ship that traded" exit did not fire, because no ship was trading;
- the clock is not reset;
- every hub has a yard;
- the 400 M floor is right (975.9 M less 80 k is well above it).

## Proof in the local world (main's chain, `scene-prod-shape.sql`)

The scene rebuilds prod's shape: seven 0339 ships wrecked at their homes, five of them unpaid, the room spent, the hoard 975.9 M, and the clock due. Then it runs `tick_pirates` minute by minute.

| | today, 40 minutes | next UTC day from 00:00 |
|---|---|---|
| main (0417) | added nothing; roster 0 | 00:00 all 7 wrecks REBORN (HOARD, about 280 k of the room) and xebec 8 built; xebecs 9-13 built 00:10-00:50; the first roster fleet at 01:00, then one every 10 minutes |
| with 0418 | a roster fleet every 10 minutes (14:32, 14:42, ...), nothing written to the room | the same at 00:00, the xebecs are built first again, and the roster keeps its place |

## Is it a defect?

Yes. 0414 put the roster's build outside the room so that it would not wait on the room. The queue's order made it wait anyway: on any day the room runs out while a 0339 ord or a laid-up fleet heads the queue, the roster stops until 00:00 UTC.

## The fix (0418)

There is one new function, `public.pirate_add_roster`, and two hunks in `public.pirate_add`. When the head of the queue needs the room and the room cannot pay her, the add builds the next roster fleet never built instead. It uses the roster's own turn order and `pirate_commission_fleet`, pays outside the room, keeps the 400 M floor and keeps the same 10-minute pace. When the room can pay, nothing changes.

The self-assert includes a PROOF MARKER. It builds today's shape twice in a rolled-back sub-transaction:
- on the pre-image, the add must add nothing (the fault reproduced);
- on the new body, it must build roster fleet N, write nothing to the day, add nothing in the next minute, and build fleet N+1 ten minutes on.

Local run: 76 ms.

## What the wrecks will do

They wait until 00:00 UTC, when the room renews. In each run, `tick_pirates` steps the ships first, then adds, pays and gives the gift. So at the 00:00 run each wreck's `pirate_reborn` → `pirate_refit_pay` comes first. The payers are tried in this order:
1. her own purse (0);
2. her home (ord 5's home is Port Royal, and it pays through `pirate_pay`);
3. another pirate city with a surplus of 40,000 (none today);
4. the hoard (`pirate_pay`, inside the room).

Six refits of 40,000 (240,000) fit in a room of about 2.34 M. The same run's hour of pay then clears `unpaid`, and they sail. Locally all seven were REBORN at 00:00 and sailed in the next minutes.

## The day's room spent before the clock change

Today's room was spent by the morning's gifts (16 x 250,000), before 0413/0414. Measuring today's room from the clock change would be a one-day seam. With 0418 it blocks nothing real: the roster is built today, and the wrecks and the pay wait until 00:00, about 9 hours. No migration for it (decided by default).

A roster fleet built today will be unpaid at the next hour (the pay is the room's, by 0414's decision). She lies laid up at her haven until 00:00, when she is woken one per add slot.

## Checks

- `before.sql` / `after.sql` (one text, read-only, stable functions only). Before: head 20260818000417, applied false, hunks {1: 1, 2: 1}. After: head 0418, applied true, hunks {1: 0, 2: 0}, new_texts {1: 1, 2: 1}. Within 10 minutes `roster.built` rises by one and `spend_today` does not move.
- `rollback-0418.sql`: a draft. Tested locally, it restores `pirate_add` byte for byte (md5 1212dc68...) and drops the new function.
