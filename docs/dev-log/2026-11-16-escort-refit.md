# 2026-11-16 - An escort is re-rated in harbour (0452; a repair of 0451's ladder)

## The bug

0451's ladder (`public.npc_ladder_refit`) re-rated 38 of prod's 46 navy fleets and never the other 8: the last ship of the line of ENG,
ESP, JPN, MNG, MUG, NLD, OTT and PRT. Every one escorts a cargo ship (`navy_ships.escort_of` set, mission `ESCORT`). At the read
(`scripts/ops/harness/escort-refit/before.sql`, prod 00:25 UTC, head 0451, gate green: beat 112 ms, 781 MB, 0 waiting on the disk): 3
docked (ENG, ESP, JPN), 5 sailing; none busy, called out, in a battle or unpaid. Each is still one `galion`; her rung wants two cutters
or brigs of her line (ESP and PRT a frigate of their own line).

## The cause (verified in the code and on the local world)

- `public.npc_ladder_refit` refused any navy ship with `escort_of` set (0451, line 450).
- `public.navy_escort_step` (0333, fenced by 0342) runs first in every in-port step of the last ship of a line. While ANY cargo ship of her
  country sails with funds aboard toward a harbour the pirates do not hold, she takes the richest as her ward (`escort_of` set) and either
  takes the next leg or, when she is already at the ward's harbour, waits there. It clears `escort_of` only when no cargo ship of hers
  sails with funds. With a hundred cargo ships at sea, that never happens, so the refusal never lifts.
- Reproduced on the local world (`scripts/ops/harness/escort-refit/scene.sql`, `probe.mjs`): Spain with two navy ships and one cargo ship at
  sea with funds; her escort step makes ord 2 the escort; the pass re-rates ord 1 in the first minute and refuses ord 2 every minute after.

## What the refusal protected

Nothing the refit's other refusals do not:

- at sea: refused by her status (only `DOCKED` or `UNABLE_TO_SAIL`);
- in a fight: refused by `navy_ships.battle_id` and a `FIGHTING` side; sent for: by `called_to`;
- her duty is her row in `public.navy_ships` (mission, `escort_of`). The refit never writes it: it swaps her hulls and nothing else.
- A raid on her ward finds her by that row (`public.navy_call`), takes her fleet row SKIP LOCKED and needs one hull above 0 health. A
  re-rating keeps her health share, so she answers as before, on her new hulls. The one thing she can miss is a call during the few
  milliseconds the refit holds her row, as any navy ship can.

## The fix (decided by default)

The refit no longer refuses an escort. An escort in harbour (not at sea, not in a fight, not called out, not busy) is re-rated like any other
navy fleet, by the one re-rating and inside its limits: two of a kind a minute, harbour only, free. Her mission and her ward are untouched.
There is no second path and no new rule for escorts. Two hunks of `public.npc_ladder_refit`: the refusal line, and its header comment.

## Load

No table, job or knob. About 8 one-time re-ratings of about 20 rows each, as each escort next lies in harbour. The 3 docked now should go
in the first minutes, the 5 at sea when they dock. That is at most 40 extra rows a minute for a few minutes (inside 0451's pace), about 160
rows in all, then nothing beyond 0451's own.

## Measured here (PGlite, this machine)

- 0452 on the cached head world (main's chain, 0451): 140-170 ms. Self-assert ok: 2 hunks, each once and reversing; nothing else moved.
  The probe: an ESP escort at ord 900, a galion, is re-rated to `brigantin*2` in harbour and is still ESCORT of her ward; she is refused when
  called out, in a fight or at sea.
- Proof 155 (new): 4/4 with 0452. Without it, ER_RATED fails: the escort stays `galion*1`. The rollback draft
  (`scripts/ops/harness/escort-refit/rollback-0452.sql`) brings the failure back.
- `BYEHARU_PREFIX_CACHE=required node scripts/db/proof.mjs 15 --exclude=115_,150_,152_,15_city` (the CI world, 412 files, 331 from the
  prefix cache): proof 154 10/10, proof 155 4/4.

## After the deploy

`scripts/ops/harness/escort-refit/after.sql` at +10 and +30 minutes. `due` should fall to `[]` as the escorts at sea come into harbour.
Each escort keeps mission ESCORT with `has` = `wants`. `navy_rated_10m` should be at most 20 and `unpaid` 0.

Rollback: `rollback-0452.sql` (a draft). The quick stop for the whole ladder is still 0451's switch.
