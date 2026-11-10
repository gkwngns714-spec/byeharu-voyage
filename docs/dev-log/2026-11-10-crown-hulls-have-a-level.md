# 0344: crown and pirate hulls have a level (owner row 288, docs/WORLD_POWERS.md 2.3)

## What was missing
Part 1 of `docs/WORLD_POWERS.md` (W1-W5) was all on prod when checked on 2026-11-10 (head 0343): W1 0319, W2 lit (`levels_bite` true), W3 0337, W4 0321, W5 0320. One line of 2.3 had no code: *"Crown and pirate hulls take a fixed level by knob, `npc_ship_level` 5."*

Measured on prod, read only, 2026-11-10, head 0343:

| Kind | Hulls | With a `ship_xp` row | Level |
|---|---|---|---|
| cargo | 372 | 0 | 1 |
| navy | 6 | 0 | 1 |
| pirate | 3 | 0 | 1 |
| merchant | 919 | 919 | 1-4 (`npc_fix_level`) |
| human | 22 | 1 | 1-3 |

`public.crown_house` answered true for 385 hulls (the three kinds, plus hulls laid since the first count). `voyage.settle` writes no experience for an `is_npc` house, so nothing ever gave these hulls a level.

## What 0344 does
- `public.crown_hull_level_fix(p_player default null)`: the one writer of a crown or pirate hull's experience. Lit, every hull of a `public.crown_house` holds `level_points(npc_ship_level)`. Dark, none holds a row (level 1). It writes only rows that differ and returns how many, so a second run writes 0.
- Knobs: `npc_ship_level_enabled` false (owner's switch), `npc_ship_level` 5.
- Job `byeharu-voyage:crown-hull-level`, every ten minutes. New hulls, refits, the switch and the knob take effect within ten minutes.
- Nothing else moves. Every reader already reads `ship_xp` through the level in force.

## Decided by default
- **Dark, behind a switch.** 2.3 names no switch, but lit it changes every navy, pirate and armed cargo fight on prod: +4 handling, +6 accuracy, +0.6 sighting at level 5 (knobs 1, 1.5, 0.15 a level). Changing the balance is the owner's call.
- **A crown or pirate hull is `public.crown_house`**: cargo, navy and pirate ships. A pirate merchant is a merchant (`npc_fix_level`). A player who built a crown class owns a COMPANY hull and earns her level.
- **One writer, run as a reconcile**, not a hunk in each of the three makers. That gives one place, no change to any live body, and turning the switch off takes it back.

## Proofs
- Migration self-assert: the catalog (no other function, knob, table, trigger or job moved; the posture reads zero), then a probe navy hull and a probe merchant made by hand and rolled back. Dark writes nothing. Lit: level 5, the stats move by exactly the knobs, a second run writes 0, the merchant is never written. Dark again: as before.
- Proof 51 (6 markers): a cargo, a navy and a pirate ship made by their real makers, the writer run over the whole world, the level read where the fight reads it (`world.ship_stats`, `voyage.fleet_hulls`), the knob at 3, other `ship_xp` rows byte for byte, dark again.
- Harness `scripts/ops/harness/crown-level/proof-0344.mjs`: red first (proof 51 fails without the file), positive control green, 15 mutations red for the intended reason.
- A note for the next file: `p.oid::regprocedure::text` prints a `public` function without `public.`, so exclude a new function from a catalog digest by oid, not by name. In plpgsql, call a volatile writer in its own statement. The parts of an `or` run in no fixed order, and a stable read next to it may run first.

## PROD CHECKS
Before (read only, done 2026-11-10): head 0343; 0 `ship_xp` rows on crown hulls; 385 crown hulls; neither knob present; no `crown-hull-level` job; `public.crown_house` is `s`.

After deploy (read only):
```sql
begin transaction read only;
select (select max(version) from supabase_migrations.schema_migrations) head,
       (select provolatile from pg_proc where oid = 'public.crown_hull_level_fix(uuid)'::regprocedure) vol,
       (select value from public.world_config where key = 'npc_ship_level_enabled') sw,
       (select value from public.world_config where key = 'npc_ship_level') lvl,
       (select count(*) from cron.job where jobname = 'byeharu-voyage:crown-hull-level' and active) job,
       (select count(*) from public.ship_xp x join public.ships s on s.id = x.ship_id where public.crown_house(s.player_id)) crown_rows;
```
Expected: head 0344 (or later), vol `v` (never call it from a check), sw false, lvl 5, job 1, crown_rows 0.

## Lighting (owner only)
`update public.world_config set value = 'true'::jsonb where key = 'npc_ship_level_enabled';`. Within ten minutes every crown and pirate hull is level 5. After-check at 30 minutes: crown_rows equals the crown hull count, and the fight after-check `scripts/ops/harness/raid/after-check.sh <start> <end>`. To roll back, set it to false. The next run deletes the rows.
