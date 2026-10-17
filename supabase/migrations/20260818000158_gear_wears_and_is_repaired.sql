-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0158 — GEAR WEARS, AND IS REPAIRED  (S13 Gear II: wear, repair, refits, what works an item — DARK)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY NOW ─────────────────────────────────────────────────────────────────────────────────────
-- docs/SHIPS_AND_SKILLS.md §8 row S13 (§6.1 actives, §6.2 one item model, §6.5 wear and repair, §6.8
-- refits; docs/SKILLS_AND_CAPTAINS.md §9: S13 "unchanged" by v2). The owner: *"the gear should be like
-- eve too, plus rs3"* — RS3's degradation (a mounted piece wears and is repaired at a yard) and EVE's
-- rigs (refits: permanent, fitted at a build yard, destroyed when removed). 0132 gave every mounted
-- piece its own row with a `wear` column that nothing wrote and nothing read ("wear factor 1 until S13").
--
-- ── WHAT SAYS THE OPPOSITE TODAY, NAMED ─────────────────────────────────────────────────────────
--   * public.fitted_units.wear is 0 on every unit and read by nothing (0132:266, 0132:272-276).
--   * world.ship_stats counts every unit whole (0132's hunk: "its wear factor is 1 until S13").
--   * cmd.do_repair repairs the hull only; public.unmount_fitting says "Repair on the way off is S13's".
--   * The Refit rack has places (carlat 1, nau 2, and the Wave A / B hulls) and nothing to put in them;
--     a FIT checks no building.
--   * item_profile.active is recorded (0132); what an active acts on (§6.1's trigger) and what it
--     consumes are recorded nowhere.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) KNOBS (only where absent): gear_wear_bite false (THE switch), gear_wear_per_1000nm 1,
--     gear_wear_per_fight 4, gear_wear_per_storm 3, gear_repair_pct 0.30.
-- (2) public.item_use (item_code, trigger, consumes) — WHAT WORKS AN ITEM, one row per item, generated
--     from scripts/build-gear.mjs USE_BY_BASE (one entry per base type) and held by the world guard:
--     `trigger` is the sea event a piece answers to — it WEARS by it (MILES: canvas, rigging, lookouts;
--     PIRATES: the High rack; STORM: the Low rack and the Mid hull-keeping gear) and an active module
--     acts on it (so an active's is PIRATES or STORM); null = never wears (the figurehead, every refit).
--     `consumes` = what an active spends a time it acts (long guns: shot-and-ball + gunpowder) —
--     RECORDED ONLY: no roll reads attack, armour or a trigger until SHIPS_AND_GEAR S4 and the hazard
--     re-cut. A SIDE TABLE, not two item_profile columns: an ALTER there would hold ACCESS EXCLUSIVE on
--     the table every ship read joins (world.ship_racks / ship_budget) until this file commits.
-- (3) THE FOURTEEN REFITS (§6.8; seven types × I / II — Shallow Keel left out, the generator says why):
--     item_kinds / item_profile (rack refit, deck 0, hands 0, passive) / item_effects / item_recipes and
--     skill_requirements (Refit I: Refitting I; II: Refitting V) — `--sql-0158`, pasted verbatim.
-- (4) THE ONE RULE OF WEAR AND ITS READERS:
--       public.gear_wear_on()            THE switch (inlinable, as public.skills_bite_on).
--       public.wear_factor(wear)         1 − wear / 200: a unit at 100 works at half; nothing breaks.
--       public.worn_delta(delta, wear)   THE worn unit's figure for one effect: a BUY (delta > 0) × the
--                                        factor, rounded to its own scale, while the switch is on; a
--                                        spend, an unworn unit, or the switch off: the delta itself.
--       public.unit_wear_card(item, w)   what the ship panel prints of a unit's wear (null: never wears).
-- (5) THE ONE WRITER OF WEAR: public.wear_units_for(fleet, voyage) — what one passage wore: every unit
--     of the fleet whose item answers to MILES gains total_nm / 1,000 × gear_wear_per_1000nm, to PIRATES
--     its PIRATES days × gear_wear_per_fight, to STORM its STORM days × gear_wear_per_storm; capped at
--     100. Called from ONE hunk of voyage.settle's arrival arm, INSIDE 0127's `not is_npc` block —
--     players only; a merchant's gear never wears (no read, no write). It accrues while dark.
-- (6) THE ONE PRICE AND THE ONE REPAIRER: public.item_recipe_value(item) (Σ recipe qty × base value),
--     public.unit_repair_cost(item, wear) (value × wear % × gear_repair_pct; a G1 suit of sails at 100
--     ≈ 220 🪙), public.gear_repair_quote(fleet) ({units, cost, words}), public.repair_units_for(fleet)
--     (wear → 0). THE REPAIR DOOR, cmd.do_repair, while the switch is on, also repairs every worn
--     unit of the fleet and charges it with the hull (one REPAIR payment to the city, 0122); "nothing
--     aboard needs repair" only when neither the hulls nor the gear do. public.unmount_fitting, while
--     the switch is on, charges a worn piece's repair to the same city on its way off (§6.2: the store
--     only ever holds pristine gear), refused E_INSUFFICIENT_FUNDS with figures when it cannot pay.
-- (7) A REFIT IS FITTED ONLY AT A BUILD YARD: public.mount_fitting refuses a Refit-rack item unless
--     the hull's fleet is docked at a port with a `building_yard` row (E_NO_YARD, in words). Removing a
--     refit destroys it (0132's unmount_fitting, unchanged).
-- (8) THE READS: world.ship_stats (both branches: one hunk each) counts a worn unit's buys through
--     public.worn_delta; world.ship_racks serves each unit's wear card while the switch is on.
--
-- ── WHAT IT DELIBERATELY DOES NOT DO ────────────────────────────────────────────────────────────
-- Light anything (gear_wear_bite ships false: wear ACCRUES on players' units and every stat, view,
-- repair and unfit answers exactly as before — proven for every hull and on probes). No
-- `gear_actives_bite` knob: §6.1's actives bite only with S4 and the hazard re-cut, and a switch that
-- nothing reads would be a second truth (K4's rule) — it lands with its reader. No perks (S16), no
-- Seasoned perk on wear, no client write, no new entry point, no cron, no ALTER of an existing table,
-- no FK. Merchants: nothing new, no exemption in any core (their units never wear because the one
-- writer is behind settle's one is_npc read; repairing a merchant's fleet finds nothing worn).
--
-- ── LOCKS (db push holds every lock until this file commits) ───────────────────────────────────
-- Heavy reads first (pre-images, before-timings). Then only ROW EXCLUSIVE on catalogue tables nothing
-- live writes (item_kinds, item_profile, item_effects, item_recipes, skill_requirements), five
-- world_config rows and a new table; CREATE OR REPLACE FUNCTION locks no table. Every probe write is in
-- a rolled-back subtransaction; a probe that meets a lock (55P03 / 40P01) is retried 5 × 0.2 s, then
-- LOCK CONTENTION, not a result.
--
-- SUPERSEDES, by hunks sliced from the LIVE bodies (LF-normalised), each asserted to occur exactly once
-- and to reverse to its pre-image, ACL / volatility / definer / config unchanged: voyage.settle (0155,
-- as K2 / K3 left it), world.ship_stats (0149), world.ship_racks (0132), cmd.do_repair (0142),
-- public.mount_fitting (0133), public.unmount_fitting (0132).
--
-- ROLLBACK (forward migration): reverse the six bodies' hunks (old text in hunks_0158); drop the nine
-- functions and public.item_use; delete the five knobs; delete the 14 refit rows (skill_requirements,
-- item_recipes, item_effects, item_profile, item_kinds) after asserting no fitted_units / player_items
-- row names one. Wear already written stays on the units (read by nothing once the hunks are out).
-- VERSION: 0158 (provisional; renumbered to head + 1 at deploy). Applies on 0157 (K5, #175) — and on 0156: no hunk here meets K5's.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  perform set_config('random_page_cost', '1.1', true);   -- prod's planner page cost (0149's header)
end $guard$;

-- ── 0. HELPERS (pg_temp, gone at commit) ───────────────────────────────────────────────────────
create or replace function pg_temp.occurs_0158(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- run a query whose writes are rolled back; return its one jsonb answer, or the refusal it raised
create or replace function pg_temp.rb_0158(p_sql text)
returns jsonb
language plpgsql
as $$
declare
  r     jsonb;
  v_msg text;
begin
  begin
    execute p_sql into r;
    raise exception 'RB_0158';
  exception when others then
    if sqlerrm <> 'RB_0158' then
      v_msg := sqlerrm;
      r := jsonb_build_object('refused', v_msg);
    end if;
  end;
  return r;
end $$;

-- ── 1. THE PRE-IMAGES (every heavy read happens here, before any write) ─────────────────────────
create temp table defs_before_0158 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('voyage.settle(uuid, timestamp with time zone)'), ('world.ship_stats(uuid)'),
               ('world.ship_racks(uuid, jsonb)'), ('cmd.do_repair(uuid, jsonb)'),
               ('public.mount_fitting(uuid, text)'), ('public.unmount_fitting(uuid, text)')) f(fn);

create temp table untouched_before_0158 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl
  from (values ('world.ship_view(uuid)'), ('world.ship_budget(uuid)'), ('world.ship_slots(uuid)'),
               ('cmd.do_fit(uuid, jsonb)'), ('cmd.do_unfit(uuid, jsonb)'), ('public.npc_fit_loadout(uuid)'),
               ('public.pay_city(uuid, uuid, text, bigint, uuid)'), ('voyage.ship_speed(uuid)'),
               ('public.ship_hold_capacity(uuid)'), ('public.requirements_unmet(uuid, text, text)')) f(fn);

create temp table before_0158 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from public.item_kinds) as kinds,
       (select md5(string_agg(to_jsonb(k)::text, '|' order by k.code)) from public.item_kinds k) as kinds_hash,
       (select md5(string_agg(to_jsonb(p)::text, '|' order by p.item_code)) from public.item_profile p) as profile_hash,
       (select md5(string_agg(to_jsonb(e)::text, '|' order by e.item_code, e.stat)) from public.item_effects e) as effects_hash,
       (select md5(string_agg(format('%s/%s/%s', r.item_code, r.good_id, r.qty), '|' order by r.item_code, r.good_id)) from public.item_recipes r) as recipes_hash,
       (select count(*) from public.skill_requirements) as requirements;

-- the old bodies under pg_temp names: the dark comparisons run old against new in one statement
do $$
declare
  d     record;
  v_def text;
  v_new text;
begin
  for d in select * from defs_before_0158 loop
    v_new := 'CREATE OR REPLACE FUNCTION pg_temp.' || replace(split_part(d.fn, '(', 1), '.', '_') || '_b0158(';
    v_def := replace(d.def, 'CREATE OR REPLACE FUNCTION ' || split_part(d.fn, '(', 1) || '(', v_new);
    if pg_temp.occurs_0158(v_def, v_new) <> 1 then
      raise exception '0158 self-assert FAIL: could not rename the pre-image of %', d.fn;
    end if;
    execute v_def;
  end loop;
  -- world.ship_view is not re-cut; its OLD answer is the same builder over the old stats and racks
  v_def := (select def from untouched_before_0158 where fn = 'world.ship_view(uuid)');
  v_def := replace(v_def, 'CREATE OR REPLACE FUNCTION world.ship_view(', 'CREATE OR REPLACE FUNCTION pg_temp.ship_view_b0158(');
  if pg_temp.occurs_0158(v_def, 'world.ship_stats(s.id)') <> 1 or pg_temp.occurs_0158(v_def, 'world.ship_racks(s.id, y.sl)') <> 1 then
    raise exception '0158 self-assert FAIL: world.ship_view does not read ship_stats and ship_racks once each where expected';
  end if;
  v_def := replace(replace(v_def, 'world.ship_stats(s.id)', 'pg_temp.world_ship_stats_b0158(s.id)'),
                   'world.ship_racks(s.id, y.sl)', 'pg_temp.world_ship_racks_b0158(s.id, y.sl)');
  execute v_def;
end $$;

-- What the arrivals tick and a merchant card read per merchant hull — speed + hold, ship_stats and
-- the whole ship — timed BEFORE the re-cut (printed, not gated: timings are a notice).
create temp table reads_0158 (phase text, what text, hulls bigint, ms numeric) on commit drop;
create or replace function pg_temp.time_reads_0158(p_phase text)
returns void
language plpgsql
as $$
declare
  v_t0 timestamptz;
  v_n  bigint;
  v_ids uuid[];
begin
  select array_agg(s.id order by s.id) into v_ids
    from public.ships s join public.players p on p.id = s.player_id where p.is_npc;
  v_n := coalesce(cardinality(v_ids), 0);
  v_t0 := clock_timestamp();
  perform voyage.ship_speed(x), public.ship_hold_capacity(x) from unnest(v_ids) x;
  insert into reads_0158 values (p_phase, 'speed+hold', v_n, round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
  v_t0 := clock_timestamp();
  perform world.ship_stats(x) from unnest(v_ids) x;
  insert into reads_0158 values (p_phase, 'ship_stats', v_n, round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
  v_t0 := clock_timestamp();
  perform world.ship_view(x) from unnest(v_ids) x;
  insert into reads_0158 values (p_phase, 'ship_view', v_n, round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
end $$;
select pg_temp.time_reads_0158('before');

-- ── 2. THE KNOBS (only where absent: a knob already set is left alone) ──────────────────────────
insert into public.world_config (key, value, description) values
  ('gear_wear_bite', 'false'::jsonb,
   '0158 (S13, docs/SHIPS_AND_SKILLS.md §6.5): THE switch of gear wear. Off: wear ACCRUES on players'' units '
   '(voyage.settle → public.wear_units_for) and nothing reads it — every stat, ship view, repair and unfit is '
   'the pre-image. On: a worn unit''s buys work at 1 − wear / 200 (public.worn_delta), cmd.do_repair repairs the '
   'gear with the hull, public.unmount_fitting charges a worn piece''s repair on its way off.'),
  ('gear_wear_per_1000nm', '1'::jsonb,
   '0158 (S13, §6.5): wear a passage of 1,000 miles puts on a unit whose item answers to MILES (canvas, rigging, lookouts).'),
  ('gear_wear_per_fight', '4'::jsonb,
   '0158 (S13, §6.5): wear a PIRATES day of a passage puts on a unit whose item answers to PIRATES (the High rack).'),
  ('gear_wear_per_storm', '3'::jsonb,
   '0158 (S13, §6.5): wear a STORM day of a passage puts on a unit whose item answers to STORM (the Low rack, the Mid hull-keeping gear).'),
  ('gear_repair_pct', '0.30'::jsonb,
   '0158 (S13, §6.5): repairing a unit costs its item''s recipe value × wear % × this (public.unit_repair_cost).')
on conflict (key) do nothing;

-- ── 3. THE FOURTEEN REFITS (scripts/build-gear.mjs --sql-0158, verbatim) ────────────────────────
insert into public.item_kinds (code, name, slot, buys, spends, note, volume, ws_tier) values
  ('fine-lines-1', 'Fine Lines I', 'hull', 'Speed', 'Cargo space', 'The hull is faired to finer lines: faster through the water, with less room inside.', 4, 2),
  ('fine-lines-2', 'Fine Lines II', 'hull', 'Speed', 'Cargo space', 'The hull is faired to finer lines: faster through the water, with less room inside.', 5, 3),
  ('extended-hold-1', 'Extended Hold I', 'hull', 'Cargo space', 'Handling', 'The cargo space is opened up and lengthened: more cargo, and a ship slower to answer the helm.', 4, 2),
  ('extended-hold-2', 'Extended Hold II', 'hull', 'Cargo space', 'Handling', 'The cargo space is opened up and lengthened: more cargo, and a ship slower to answer the helm.', 5, 3),
  ('doubled-frames-1', 'Doubled Frames I', 'hull', 'Hull', 'Speed', 'Every frame is doubled: the hull takes far more punishment and sits a little heavier.', 4, 2),
  ('doubled-frames-2', 'Doubled Frames II', 'hull', 'Hull', 'Speed', 'Every frame is doubled: the hull takes far more punishment and sits a little heavier.', 5, 3),
  ('raised-forecastle-1', 'Raised Forecastle I', 'hull', 'Armour', 'Handling', 'A high, stout forecastle that shelters the crew and catches the wind.', 4, 2),
  ('raised-forecastle-2', 'Raised Forecastle II', 'hull', 'Armour', 'Handling', 'A high, stout forecastle that shelters the crew and catches the wind.', 5, 3),
  ('lateen-rerig-1', 'Lateen Re-rig I', 'rig', 'Handling', 'Speed', 'The ship is re-rigged with lateen sails: it turns and points higher, and runs a little slower.', 4, 2),
  ('lateen-rerig-2', 'Lateen Re-rig II', 'rig', 'Handling', 'Speed', 'The ship is re-rigged with lateen sails: it turns and points higher, and runs a little slower.', 5, 3),
  ('pierced-gun-deck-1', 'Pierced Gun Deck I', 'weapon', 'Attack', 'Hull', 'A gun deck is cut through the side: more guns bear, and the hull is weaker for it.', 4, 2),
  ('pierced-gun-deck-2', 'Pierced Gun Deck II', 'weapon', 'Attack', 'Hull', 'A gun deck is cut through the side: more guns bear, and the hull is weaker for it.', 5, 3),
  ('lookout-refit-1', 'Lookout Top I', 'lookout', 'Sighting', 'Handling', 'A permanent lookout top high on the mainmast: the horizon moves out, and the ship is a little tender.', 4, 2),
  ('lookout-refit-2', 'Lookout Top II', 'lookout', 'Sighting', 'Handling', 'A permanent lookout top high on the mainmast: the horizon moves out, and the ship is a little tender.', 5, 3)
on conflict (code) do nothing;

insert into public.item_profile (item_code, base_type, rack, grade, meta, deck, hands, active) values
  ('fine-lines-1', 'Fine Lines', 'refit', 1, 0, 0, 0, false),
  ('fine-lines-2', 'Fine Lines', 'refit', 2, 0, 0, 0, false),
  ('extended-hold-1', 'Extended Hold', 'refit', 1, 0, 0, 0, false),
  ('extended-hold-2', 'Extended Hold', 'refit', 2, 0, 0, 0, false),
  ('doubled-frames-1', 'Doubled Frames', 'refit', 1, 0, 0, 0, false),
  ('doubled-frames-2', 'Doubled Frames', 'refit', 2, 0, 0, 0, false),
  ('raised-forecastle-1', 'Raised Forecastle', 'refit', 1, 0, 0, 0, false),
  ('raised-forecastle-2', 'Raised Forecastle', 'refit', 2, 0, 0, 0, false),
  ('lateen-rerig-1', 'Lateen Re-rig', 'refit', 1, 0, 0, 0, false),
  ('lateen-rerig-2', 'Lateen Re-rig', 'refit', 2, 0, 0, 0, false),
  ('pierced-gun-deck-1', 'Pierced Gun Deck', 'refit', 1, 0, 0, 0, false),
  ('pierced-gun-deck-2', 'Pierced Gun Deck', 'refit', 2, 0, 0, 0, false),
  ('lookout-refit-1', 'Lookout Top', 'refit', 1, 0, 0, 0, false),
  ('lookout-refit-2', 'Lookout Top', 'refit', 2, 0, 0, 0, false)
on conflict (item_code) do nothing;

insert into public.item_effects (item_code, stat, delta) values
  ('fine-lines-1', 'speed', 0.2),
  ('fine-lines-1', 'hold', -15),
  ('fine-lines-2', 'speed', 0.35),
  ('fine-lines-2', 'hold', -20),
  ('extended-hold-1', 'hold', 30),
  ('extended-hold-1', 'handling', -6),
  ('extended-hold-2', 'hold', 50),
  ('extended-hold-2', 'handling', -8),
  ('doubled-frames-1', 'durability', 200),
  ('doubled-frames-1', 'speed', -0.15),
  ('doubled-frames-2', 'durability', 320),
  ('doubled-frames-2', 'speed', -0.2),
  ('raised-forecastle-1', 'armour', 8),
  ('raised-forecastle-1', 'handling', -5),
  ('raised-forecastle-2', 'armour', 14),
  ('raised-forecastle-2', 'handling', -6),
  ('lateen-rerig-1', 'handling', 10),
  ('lateen-rerig-1', 'speed', -0.1),
  ('lateen-rerig-2', 'handling', 16),
  ('lateen-rerig-2', 'speed', -0.1),
  ('pierced-gun-deck-1', 'attack', 40),
  ('pierced-gun-deck-1', 'durability', -100),
  ('pierced-gun-deck-2', 'attack', 70),
  ('pierced-gun-deck-2', 'durability', -120),
  ('lookout-refit-1', 'sighting', 2),
  ('lookout-refit-1', 'handling', -2),
  ('lookout-refit-2', 'sighting', 4),
  ('lookout-refit-2', 'handling', -2)
on conflict (item_code, stat) do nothing;

create temp table refit_goods_0158 (item_code text, good_code text, qty numeric) on commit drop;
insert into refit_goods_0158 values
  ('fine-lines-1', 'live-oak', 8),
  ('fine-lines-1', 'lignum-vitae', 4),
  ('fine-lines-2', 'live-oak', 14),
  ('fine-lines-2', 'lignum-vitae', 8),
  ('extended-hold-1', 'timber', 8),
  ('extended-hold-1', 'ships-nails', 4),
  ('extended-hold-2', 'timber', 14),
  ('extended-hold-2', 'ships-nails', 8),
  ('doubled-frames-1', 'naval-timber', 8),
  ('doubled-frames-1', 'live-oak', 4),
  ('doubled-frames-2', 'naval-timber', 14),
  ('doubled-frames-2', 'live-oak', 8),
  ('raised-forecastle-1', 'timber', 8),
  ('raised-forecastle-1', 'oakum', 4),
  ('raised-forecastle-2', 'timber', 14),
  ('raised-forecastle-2', 'oakum', 8),
  ('lateen-rerig-1', 'hemp', 8),
  ('lateen-rerig-1', 'naval-timber', 4),
  ('lateen-rerig-2', 'hemp', 14),
  ('lateen-rerig-2', 'naval-timber', 8),
  ('pierced-gun-deck-1', 'timber', 8),
  ('pierced-gun-deck-1', 'bar-iron', 4),
  ('pierced-gun-deck-2', 'timber', 14),
  ('pierced-gun-deck-2', 'bar-iron', 8),
  ('lookout-refit-1', 'riga-mast', 8),
  ('lookout-refit-1', 'cordage', 4),
  ('lookout-refit-2', 'riga-mast', 14),
  ('lookout-refit-2', 'cordage', 8);
insert into public.item_recipes (item_code, good_id, qty)
select w.item_code, g.id, w.qty from refit_goods_0158 w join public.goods g on g.code = w.good_code
on conflict (item_code, good_id) do nothing;

insert into public.skill_requirements (subject_kind, subject_code, skill_code, level) values
  ('item', 'fine-lines-1', 'REFITTING', 1),
  ('item', 'fine-lines-2', 'REFITTING', 5),
  ('item', 'extended-hold-1', 'REFITTING', 1),
  ('item', 'extended-hold-2', 'REFITTING', 5),
  ('item', 'doubled-frames-1', 'REFITTING', 1),
  ('item', 'doubled-frames-2', 'REFITTING', 5),
  ('item', 'raised-forecastle-1', 'REFITTING', 1),
  ('item', 'raised-forecastle-2', 'REFITTING', 5),
  ('item', 'lateen-rerig-1', 'REFITTING', 1),
  ('item', 'lateen-rerig-2', 'REFITTING', 5),
  ('item', 'pierced-gun-deck-1', 'REFITTING', 1),
  ('item', 'pierced-gun-deck-2', 'REFITTING', 5),
  ('item', 'lookout-refit-1', 'REFITTING', 1),
  ('item', 'lookout-refit-2', 'REFITTING', 5)
on conflict (subject_kind, subject_code, skill_code) do nothing;

-- ── 4. WHAT WORKS AN ITEM (public.item_use) ────────────────────────────────────────────────────
create table if not exists public.item_use (
  item_code text primary key,
  trigger   text check (trigger in ('MILES', 'PIRATES', 'STORM')),
  consumes  jsonb not null default '[]'::jsonb check (jsonb_typeof(consumes) = 'array')
);
comment on table public.item_use is
  '0158 (S13, docs/SHIPS_AND_SKILLS.md §6.1 / §6.5): WHAT WORKS AN ITEM, one row per item_kinds row. trigger = '
  'the sea event the piece answers to: it wears by it (MILES a thousand miles, PIRATES a pirates day, STORM a '
  'storm day — public.wear_units_for) and an active module (item_profile.active) acts on it; null = never '
  'wears (the figurehead, every refit). consumes = [{good, qty}] an active spends each time it acts (recorded; '
  'read by nothing until SHIPS_AND_GEAR S4). Generated (scripts/build-gear.mjs USE_BY_BASE), held by the '
  'world guard. A side table so no ship read waits on an ALTER of item_profile. Server-only.';
alter table public.item_use enable row level security;
revoke all on table public.item_use from public, anon, authenticated;

insert into public.item_use (item_code, trigger, consumes) values
  ('anchor-and-cable', 'STORM', '[]'),
  ('ballast', 'STORM', '[]'),
  ('baltic-sailcloth', 'MILES', '[]'),
  ('bar-iron-sheet-anchor', 'STORM', '[]'),
  ('bilge-pumps', 'STORM', '[]'),
  ('binnacle-and-atlas', 'MILES', '[]'),
  ('binnacle-and-charts', 'MILES', '[]'),
  ('boarding-axes', 'PIRATES', '[]'),
  ('boarding-gear', 'PIRATES', '[]'),
  ('boarding-pikes', 'PIRATES', '[]'),
  ('bowsprit-and-jib', 'MILES', '[]'),
  ('brake-pumps', 'STORM', '[]'),
  ('brass-binnacle', 'MILES', '[]'),
  ('brass-carronades', 'PIRATES', '[{"good":"shot-and-ball","qty":1},{"good":"gunpowder","qty":1}]'),
  ('brass-chasers', 'PIRATES', '[{"good":"shot-and-ball","qty":1},{"good":"gunpowder","qty":1}]'),
  ('brass-guns', 'PIRATES', '[{"good":"shot-and-ball","qty":1},{"good":"gunpowder","qty":1}]'),
  ('brass-swivels', 'PIRATES', '[{"good":"shot-and-ball","qty":1},{"good":"gunpowder","qty":1}]'),
  ('broadside-guns', 'PIRATES', '[{"good":"shot-and-ball","qty":1},{"good":"gunpowder","qty":1}]'),
  ('bronze-carronades', 'PIRATES', '[{"good":"shot-and-ball","qty":1},{"good":"gunpowder","qty":1}]'),
  ('bronze-chasers', 'PIRATES', '[{"good":"shot-and-ball","qty":1},{"good":"gunpowder","qty":1}]'),
  ('bronze-guns', 'PIRATES', '[{"good":"shot-and-ball","qty":1},{"good":"gunpowder","qty":1}]'),
  ('bronze-swivels', 'PIRATES', '[{"good":"shot-and-ball","qty":1},{"good":"gunpowder","qty":1}]'),
  ('capstan', 'STORM', '[]'),
  ('carronades', 'PIRATES', '[{"good":"shot-and-ball","qty":1},{"good":"gunpowder","qty":1}]'),
  ('carved-figurehead', null, '[]'),
  ('cast-kentledge', 'STORM', '[]'),
  ('chain-pumps', 'STORM', '[]'),
  ('copper-chain-pumps', 'STORM', '[]'),
  ('copper-fast-anchor', 'STORM', '[]'),
  ('copper-fast-sheet-anchor', 'STORM', '[]'),
  ('copper-magazine', 'PIRATES', '[]'),
  ('copper-sheathing', 'STORM', '[]'),
  ('crows-nest', 'MILES', '[]'),
  ('culverin-chasers', 'PIRATES', '[{"good":"shot-and-ball","qty":1},{"good":"gunpowder","qty":1}]'),
  ('culverins', 'PIRATES', '[{"good":"shot-and-ball","qty":1},{"good":"gunpowder","qty":1}]'),
  ('deal-planking', 'STORM', '[]'),
  ('double-capstan', 'STORM', '[]'),
  ('double-duck-storm-canvas', 'STORM', '[]'),
  ('doubled-copper', 'STORM', '[]'),
  ('doubled-frames-1', null, '[]'),
  ('doubled-frames-2', null, '[]'),
  ('duck-canvas', 'MILES', '[]'),
  ('duck-jib', 'MILES', '[]'),
  ('duck-studding-sails', 'MILES', '[]'),
  ('extended-hold-1', null, '[]'),
  ('extended-hold-2', null, '[]'),
  ('figurehead', null, '[]'),
  ('fine-lines-1', null, '[]'),
  ('fine-lines-2', null, '[]'),
  ('gilded-figurehead', null, '[]'),
  ('grand-magazine', 'PIRATES', '[]'),
  ('greenheart-frames', 'STORM', '[]'),
  ('greenheart-planking', 'STORM', '[]'),
  ('greenheart-rudder', 'STORM', '[]'),
  ('greenheart-sheathing', 'STORM', '[]'),
  ('greenheart-whipstaff', 'STORM', '[]'),
  ('heavy-carronades', 'PIRATES', '[{"good":"shot-and-ball","qty":1},{"good":"gunpowder","qty":1}]'),
  ('hemp-canvas', 'MILES', '[]'),
  ('hemp-jib', 'MILES', '[]'),
  ('hemp-storm-canvas', 'STORM', '[]'),
  ('hemp-studding-sails', 'MILES', '[]'),
  ('hold-fittings', 'STORM', '[]'),
  ('holland-duck', 'MILES', '[]'),
  ('holland-headsails', 'MILES', '[]'),
  ('holland-storm-canvas', 'STORM', '[]'),
  ('holland-studding-sails', 'MILES', '[]'),
  ('iron-kentledge', 'STORM', '[]'),
  ('iron-swivels', 'PIRATES', '[{"good":"shot-and-ball","qty":1},{"good":"gunpowder","qty":1}]'),
  ('knee-braced-frames', 'STORM', '[]'),
  ('lateen-rerig-1', null, '[]'),
  ('lateen-rerig-2', null, '[]'),
  ('lead-ballast', 'STORM', '[]'),
  ('light-room-magazine', 'PIRATES', '[]'),
  ('lined-magazine', 'PIRATES', '[]'),
  ('live-oak-and-copper', 'STORM', '[]'),
  ('live-oak-frames', 'STORM', '[]'),
  ('live-oak-planking', 'STORM', '[]'),
  ('live-oak-rudder', 'STORM', '[]'),
  ('live-oak-whipstaff', 'STORM', '[]'),
  ('lodestone-compass', 'MILES', '[]'),
  ('lookout-refit-1', null, '[]'),
  ('lookout-refit-2', null, '[]'),
  ('lookout-top', 'MILES', '[]'),
  ('manila-anchor', 'STORM', '[]'),
  ('manila-capstan', 'STORM', '[]'),
  ('masters-binnacle', 'MILES', '[]'),
  ('masthead-glass', 'MILES', '[]'),
  ('oak-planking', 'STORM', '[]'),
  ('oak-rudder', 'STORM', '[]'),
  ('oak-whipstaff', 'STORM', '[]'),
  ('osmund-anchor', 'STORM', '[]'),
  ('osmund-capstan', 'STORM', '[]'),
  ('osmund-grapnels', 'PIRATES', '[]'),
  ('osmund-sheet-anchor', 'STORM', '[]'),
  ('painted-figurehead', null, '[]'),
  ('pierced-gun-deck-1', null, '[]'),
  ('pierced-gun-deck-2', null, '[]'),
  ('pig-iron-ballast', 'STORM', '[]'),
  ('powder-magazine', 'PIRATES', '[]'),
  ('raised-forecastle-1', null, '[]'),
  ('raised-forecastle-2', null, '[]'),
  ('royal-figurehead', null, '[]'),
  ('royal-lookout', 'MILES', '[]'),
  ('rudder-and-helm', 'STORM', '[]'),
  ('sailcloth-headsails', 'MILES', '[]'),
  ('sailcloth-storm-canvas', 'STORM', '[]'),
  ('sailcloth-studding-sails', 'MILES', '[]'),
  ('sheet-anchor', 'STORM', '[]'),
  ('stern-chasers', 'PIRATES', '[{"good":"shot-and-ball","qty":1},{"good":"gunpowder","qty":1}]'),
  ('storm-canvas', 'STORM', '[]'),
  ('storming-gear', 'PIRATES', '[]'),
  ('studding-sails', 'MILES', '[]'),
  ('suit-of-sails', 'MILES', '[]'),
  ('swedish-anchor', 'STORM', '[]'),
  ('swedish-capstan', 'STORM', '[]'),
  ('swedish-carronades', 'PIRATES', '[{"good":"shot-and-ball","qty":1},{"good":"gunpowder","qty":1}]'),
  ('swedish-chasers', 'PIRATES', '[{"good":"shot-and-ball","qty":1},{"good":"gunpowder","qty":1}]'),
  ('swedish-guns', 'PIRATES', '[{"good":"shot-and-ball","qty":1},{"good":"gunpowder","qty":1}]'),
  ('swedish-sheet-anchor', 'STORM', '[]'),
  ('swedish-swivels', 'PIRATES', '[{"good":"shot-and-ball","qty":1},{"good":"gunpowder","qty":1}]'),
  ('swivel-guns', 'PIRATES', '[{"good":"shot-and-ball","qty":1},{"good":"gunpowder","qty":1}]'),
  ('teak-and-copper', 'STORM', '[]'),
  ('teak-chain-pumps', 'STORM', '[]'),
  ('teak-frames', 'STORM', '[]'),
  ('teak-planking', 'STORM', '[]'),
  ('teak-rudder', 'STORM', '[]'),
  ('teak-whipstaff', 'STORM', '[]'),
  ('topgallant-mast', 'MILES', '[]'),
  ('whipstaff', 'STORM', '[]')
on conflict (item_code) do nothing;

-- ── 5. THE ONE RULE OF WEAR, ITS WRITER, ITS PRICE AND ITS REPAIRER ─────────────────────────────
create or replace function public.gear_wear_on()
returns boolean
language sql
stable
as $$
  -- 0158 (S13): THE switch (world_config gear_wear_bite). A plain SQL read — no SET, no SECURITY DEFINER —
  -- so the planner inlines it, as public.skills_bite_on (0133). Missing row = off.
  select coalesce((select c.value = 'true'::jsonb from public.world_config c where c.key = 'gear_wear_bite'), false)
$$;
comment on function public.gear_wear_on() is
  '0158 (S13): THE switch of gear wear (world_config gear_wear_bite), inlinable. Server-only.';
revoke all on function public.gear_wear_on() from public, anon, authenticated;

create or replace function public.wear_factor(p_wear numeric)
returns numeric
language sql
immutable
as $$
  -- 0158 (S13, §6.5): HOW WELL A WORN PIECE WORKS — 1 − wear / 200 (wear held to 0-100): a unit at 100
  -- works at half. Nothing ever breaks to dust (the owner's long grind is in the skills, not in loss).
  select 1 - least(greatest(coalesce(p_wear, 0), 0), 100) / 200
$$;
comment on function public.wear_factor(numeric) is
  '0158 (S13): THE wear factor, 1 − wear / 200. Read by public.worn_delta and public.unit_wear_card. Server-only.';
revoke all on function public.wear_factor(numeric) from public, anon, authenticated;

create or replace function public.worn_delta(p_delta numeric, p_wear numeric)
returns numeric
language plpgsql
stable
set search_path = public, pg_temp
as $$
begin
  -- 0158 (S13, §6.5): ONE EFFECT OF ONE WORN UNIT — what world.ship_stats adds for it. Only what the piece
  -- BUYS wears (delta > 0); what it spends is spent whole. While gear_wear_bite is off — or the unit is
  -- unworn — the delta itself, untouched, so a dark sum is the pre-image to the digit.
  if coalesce(p_wear, 0) <= 0 or p_delta <= 0 or not public.gear_wear_on() then
    return p_delta;
  end if;
  return round(p_delta * public.wear_factor(p_wear), scale(p_delta));
end $$;
comment on function public.worn_delta(numeric, numeric) is
  '0158 (S13): THE one rule of a worn unit''s effect (a buy × public.wear_factor while gear_wear_bite). Read by '
  'world.ship_stats (both branches). Server-only.';
revoke all on function public.worn_delta(numeric, numeric) from public, anon, authenticated;

create or replace function public.unit_wear_card(p_item text, p_wear numeric)
returns jsonb
language plpgsql
stable
set search_path = public, pg_temp
as $$
begin
  -- 0158 (S13): WHAT THE SHIP PANEL PRINTS OF ONE UNIT'S WEAR — the figure, how well it works, and the
  -- server's words ("12% worn · works at 94%", or "New"). Null for a piece that never wears (no trigger:
  -- the figurehead, a refit). Read by world.ship_racks while gear_wear_bite is on.
  if not exists (select 1 from public.item_use iu where iu.item_code = p_item and iu.trigger is not null) then
    return null;
  end if;
  return jsonb_build_object(
    'wear', round(coalesce(p_wear, 0), 2),
    'works_pct', round(public.wear_factor(p_wear) * 100),
    'wear_words', case when coalesce(p_wear, 0) <= 0 then 'New'
                       else format('%s%% worn · works at %s%%', round(p_wear), round(public.wear_factor(p_wear) * 100)) end);
end $$;
comment on function public.unit_wear_card(text, numeric) is
  '0158 (S13): one unit''s wear as world.ship_racks serves it (wear, works_pct, wear_words). Server-only.';
revoke all on function public.unit_wear_card(text, numeric) from public, anon, authenticated;

create or replace function public.wear_units_for(p_fleet uuid, p_voyage uuid)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_nm     numeric;
  v_storms int;
  v_fights int;
  v_n      int;
begin
  -- 0158 (S13, §6.5): WHAT ONE PASSAGE WORE — THE ONE WRITER OF WEAR. Every unit of the fleet whose item
  -- answers to MILES gains total_nm / 1,000 × gear_wear_per_1000nm; to PIRATES, its PIRATES days ×
  -- gear_wear_per_fight; to STORM, its STORM days × gear_wear_per_storm; held at 100. A unit whose item
  -- never wears (no trigger) is not touched. Called by voyage.settle's arrival arm for a PLAYER's fleet only
  -- (inside 0127's one merchant test); it asks no such question of its own. Returns the units it wore.
  select vo.total_nm into v_nm from public.voyages vo where vo.id = p_voyage and vo.fleet_id = p_fleet;
  if v_nm is null then
    return 0;
  end if;
  select count(*) filter (where ve.kind = 'STORM'), count(*) filter (where ve.kind = 'PIRATES')
    into v_storms, v_fights
    from public.voyage_events ve where ve.voyage_id = p_voyage;
  update public.fitted_units u
     set wear = least(100, round(u.wear + w.gain, 2))
    from (select fu.id,
                 case iu.trigger
                   when 'MILES'   then v_nm / 1000 * public.wc_num('gear_wear_per_1000nm')
                   when 'PIRATES' then v_fights * public.wc_num('gear_wear_per_fight')
                   when 'STORM'   then v_storms * public.wc_num('gear_wear_per_storm')
                   else 0 end as gain
            from public.ships s
            join public.fitted_units fu on fu.ship_id = s.id
            join public.item_use iu on iu.item_code = fu.item_code
           where s.fleet_id = p_fleet and iu.trigger is not null) w
   where u.id = w.id and w.gain > 0 and u.wear < 100;
  get diagnostics v_n = row_count;
  return v_n;
end $$;
comment on function public.wear_units_for(uuid, uuid) is
  '0158 (S13): THE one writer of a unit''s wear — what one passage wore (item_use.trigger × the three knobs). '
  'Called only by voyage.settle''s arrival arm, for players. Server-only.';
revoke all on function public.wear_units_for(uuid, uuid) from public, anon, authenticated;

create or replace function public.item_recipe_value(p_item text)
returns numeric
language plpgsql
stable
set search_path = public, pg_temp
as $$
begin
  -- 0158 (S13, §6.5): WHAT AN ITEM IS MADE OF, IN COIN — Σ recipe qty × the good's base value (0068's
  -- recipe, 0002's value; §6.4's prices are this figure). Read by public.unit_repair_cost.
  return (select coalesce(sum(ir.qty * g.base_value), 0)
            from public.item_recipes ir join public.goods g on g.id = ir.good_id
           where ir.item_code = p_item);
end $$;
comment on function public.item_recipe_value(text) is
  '0158 (S13): an item''s recipe value (Σ qty × goods.base_value). Read by public.unit_repair_cost. Server-only.';
revoke all on function public.item_recipe_value(text) from public, anon, authenticated;

create or replace function public.unit_repair_cost(p_item text, p_wear numeric)
returns bigint
language plpgsql
stable
set search_path = public, pg_temp
as $$
begin
  -- 0158 (S13, §6.5): THE ONE PRICE OF REPAIRING ONE UNIT — recipe value × wear % × gear_repair_pct,
  -- rounded to the coin. A G1 suit of sails at 100 wear ≈ 220. Read by public.gear_repair_quote (the
  -- repair door) and public.unmount_fitting (a worn piece's way off).
  return round(public.item_recipe_value(p_item) * least(greatest(coalesce(p_wear, 0), 0), 100) / 100
               * public.wc_num('gear_repair_pct'))::bigint;
end $$;
comment on function public.unit_repair_cost(text, numeric) is
  '0158 (S13): THE price of repairing one unit (recipe value × wear % × gear_repair_pct). Server-only.';
revoke all on function public.unit_repair_cost(text, numeric) from public, anon, authenticated;

create or replace function public.gear_repair_quote(p_fleet uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_n    int;
  v_cost bigint;
begin
  -- 0158 (S13): WHAT REPAIRING A FLEET'S GEAR COSTS — every worn unit of her ships, through
  -- public.unit_repair_cost. Null when nothing is worn. Read by cmd.do_repair while gear_wear_bite is on.
  select count(*), coalesce(sum(public.unit_repair_cost(u.item_code, u.wear)), 0)
    into v_n, v_cost
    from public.ships s join public.fitted_units u on u.ship_id = s.id
   where s.fleet_id = p_fleet and u.wear > 0;
  if v_n = 0 then
    return null;
  end if;
  return jsonb_build_object('units', v_n, 'cost', v_cost,
    'words', format('%s worn fitting%s repaired too', v_n, case when v_n = 1 then '' else 's' end));
end $$;
comment on function public.gear_repair_quote(uuid) is
  '0158 (S13): a fleet''s worn gear and what repairing it costs ({units, cost, words}; null when none). Server-only.';
revoke all on function public.gear_repair_quote(uuid) from public, anon, authenticated;

create or replace function public.repair_units_for(p_fleet uuid)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_n int;
begin
  -- 0158 (S13): THE ONE REPAIRER — every worn unit of the fleet's ships back to wear 0. Called by
  -- cmd.do_repair, after the charge, while gear_wear_bite is on.
  update public.fitted_units u set wear = 0
    from public.ships s
   where s.id = u.ship_id and s.fleet_id = p_fleet and u.wear > 0;
  get diagnostics v_n = row_count;
  return v_n;
end $$;
comment on function public.repair_units_for(uuid) is
  '0158 (S13): THE one writer that repairs gear (a fleet''s worn units → 0). Called by cmd.do_repair. Server-only.';
revoke all on function public.repair_units_for(uuid) from public, anon, authenticated;

-- ── 6. THE HUNKS (old → new), sliced from the live bodies ──────────────────────────────────────
create temp table hunks_0158 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0158 values
-- voyage.settle: the one wear writer, inside 0127's players-only block
('voyage.settle(uuid, timestamp with time zone)', 1,
$h$      on conflict (ship_id) do update set xp = public.ship_xp.xp + excluded.xp;
$h$,
$h$      on conflict (ship_id) do update set xp = public.ship_xp.xp + excluded.xp;
      -- 0158 (S13): WHAT THE VOYAGE WORE — public.wear_units_for, the one writer of wear (miles, pirates
      -- days, storm days, by what works each item). Players only: this block; a merchant's gear never wears.
      perform public.wear_units_for(p_fleet, v.id);
$h$),
-- world.ship_stats, skills lit: a worn unit's buys through public.worn_delta
('world.ship_stats(uuid)', 1,
$h$        from (select e.stat, e.delta, null::numeric as pct
$h$,
$h$        from (select e.stat,
                     -- 0158 (S13): a WORN unit's buys through public.worn_delta (the one rule); unworn, the delta
                     case when f.wear > 0 and e.delta > 0 then public.worn_delta(e.delta, f.wear) else e.delta end as delta,
                     null::numeric as pct
$h$),
-- world.ship_stats, skills dark: the same
('world.ship_stats(uuid)', 2,
$h$    -- 0132: ONE ROW PER MOUNTED UNIT (public.fitted_units). A unit counts whole — its wear factor is 1
    -- until S13 makes wear bite — so sum(delta) over units is 0124's sum(delta × qty), to the digit.
    select e.stat, sum(e.delta) as delta
$h$,
$h$    -- 0132: ONE ROW PER MOUNTED UNIT (public.fitted_units). 0158 (S13): a WORN unit's buys count through
    -- public.worn_delta (the one rule: × its wear factor while gear_wear_bite is on); an unworn unit, or a
    -- stat it spends, counts whole without the call — so, dark, sum over units is 0132's, to the digit.
    select e.stat, sum(case when f.wear > 0 and e.delta > 0 then public.worn_delta(e.delta, f.wear) else e.delta end) as delta
$h$),
-- world.ship_racks: each unit's wear card, while the switch is on (one read of it per call)
('world.ship_racks(uuid, jsonb)', 1,
$h$begin
  -- 0132: A HULL'S RACKS, AS SERVED — every rack$h$,
$h$declare
  v_wear boolean := public.gear_wear_on();   -- 0158 (S13): read once a call
begin
  -- 0132: A HULL'S RACKS, AS SERVED — every rack$h$),
('world.ship_racks(uuid, jsonb)', 2,
$h$                                                           'deck', ip.deck, 'hands', ip.hands)
$h$,
$h$                                                           'deck', ip.deck, 'hands', ip.hands)
                                         -- 0158 (S13): its wear, in the server's words, while wear bites
                                         || case when v_wear then coalesce(public.unit_wear_card(u.item_code, u.wear), '{}'::jsonb)
                                                 else '{}'::jsonb end
$h$),
-- cmd.do_repair: the gear with the hull, while the switch is on
('cmd.do_repair(uuid, jsonb)', 1,
$h$  r        record;
begin
$h$,
$h$  r        record;
  v_gear   jsonb;    -- 0158 (S13): the fleet's worn gear and its price, while wear bites
begin
$h$),
('cmd.do_repair(uuid, jsonb)', 2,
$h$  if v_points <= 0 then
    raise exception 'E_UNAVAILABLE: nothing aboard needs repair' using errcode = 'P0001';
  end if;
$h$,
$h$  -- 0158 (S13): THE GEAR. While gear_wear_bite is on, a repair also repairs every worn fitting of the fleet
  -- (public.gear_repair_quote: public.unit_repair_cost, the one price). Off, nothing is read.
  if public.gear_wear_on() then
    v_gear := public.gear_repair_quote(p_fleet);
  end if;
  if v_points <= 0 and v_gear is null then
    raise exception 'E_UNAVAILABLE: nothing aboard needs repair' using errcode = 'P0001';
  end if;
$h$),
('cmd.do_repair(uuid, jsonb)', 3,
$h$                  * public.running_cost_mult(f.player_id))::bigint;   -- 0114
$h$,
$h$                  * public.running_cost_mult(f.player_id))::bigint;   -- 0114
  v_cost := v_cost + coalesce((v_gear->>'cost')::bigint, 0);   -- 0158: and the gear's, in the same payment
$h$),
('cmd.do_repair(uuid, jsonb)', 4,
$h$    from public.ship_classes c where c.id = s.class_id and s.fleet_id = p_fleet;
$h$,
$h$    from public.ship_classes c where c.id = s.class_id and s.fleet_id = p_fleet;
  if v_gear is not null then
    perform public.repair_units_for(p_fleet);   -- 0158: the one repairer
  end if;
$h$),
('cmd.do_repair(uuid, jsonb)', 5,
$h$      'fleet', f.name, 'points', round(v_points, 1), 'cost', v_cost, 'sim_hours', round(v_hours, 1))));
$h$,
$h$      'fleet', f.name, 'points', round(v_points, 1), 'cost', v_cost, 'sim_hours', round(v_hours, 1))
      -- 0158: the gear repaired with the hull, when there was any
      || case when v_gear is null then '{}'::jsonb else jsonb_build_object('gear', v_gear) end));
$h$),
('cmd.do_repair(uuid, jsonb)', 6,
$h$  return jsonb_build_object('points', round(v_points, 1), 'cost', v_cost, 'sim_hours', round(v_hours, 1));
$h$,
$h$  return jsonb_build_object('points', round(v_points, 1), 'cost', v_cost, 'sim_hours', round(v_hours, 1))
         || case when v_gear is null then '{}'::jsonb else jsonb_build_object('gear', v_gear) end;   -- 0158
$h$),
-- public.mount_fitting: a refit only at a build yard
('public.mount_fitting(uuid, text)', 1,
$h$    from public.item_profile ip join public.gear_racks gr on gr.code = ip.rack
   where ip.item_code = k.code;
$h$,
$h$    from public.item_profile ip join public.gear_racks gr on gr.code = ip.rack
   where ip.item_code = k.code;
  -- 0158 (S13, §6.8): A REFIT IS FITTED ONLY AT A BUILD YARD — the port her fleet is docked at has a
  -- `building_yard` row (the one reading of a building, 0067). A merchant's loadout carries no refit.
  if v_rack = 'refit'
     and not exists (select 1 from public.fleets fl
                       join public.port_buildings b on b.port_id = fl.port_id and b.kind = 'building_yard'
                      where fl.id = v_ship.fleet_id and fl.status = 'DOCKED') then
    perform cmd.refuse('E_NO_YARD',
      format('%s is a refit, fitted only at a build yard, and %s has none', k.name,
             coalesce((select p.name from public.fleets fl join public.ports p on p.id = fl.port_id
                        where fl.id = v_ship.fleet_id), 'this place')));
  end if;
$h$),
-- public.unmount_fitting: a worn piece is repaired (and paid for) on its way off, while wear bites
('public.unmount_fitting(uuid, text)', 1,
$h$  v_n     int;
begin
$h$,
$h$  v_n     int;
  v_wear  numeric;   -- 0158 (S13): the unit's wear, and the repair it costs on its way off
  v_cost  bigint;
  v_purse bigint;
begin
$h$),
('public.unmount_fitting(uuid, text)', 2,
$h$  select u.id, ip.rack into v_unit, v_rack
$h$,
$h$  select u.id, ip.rack, u.wear into v_unit, v_rack, v_wear
$h$),
('public.unmount_fitting(uuid, text)', 3,
$h$  delete from public.fitted_units where id = v_unit;
$h$,
$h$  -- 0158 (S13, §6.2): A WORN PIECE IS REPAIRED ON ITS WAY OFF, so the store only ever holds pristine gear —
  -- public.unit_repair_cost (the one price), paid to the city it comes off in (REPAIR, 0122), while
  -- gear_wear_bite is on. Off, unworn, or a refit (it never wears): nothing is read or charged.
  if v_wear > 0 and coalesce(v_rack, '') <> 'refit' and public.gear_wear_on() then
    v_cost := public.unit_repair_cost(k.code, v_wear);
    select pl.ducats into v_purse from public.players pl where pl.id = v_ship.player_id;
    if v_purse < v_cost then
      perform cmd.refuse('E_INSUFFICIENT_FUNDS',
        format('%s is %s%% worn and is repaired before it comes off', k.name, round(v_wear)),
        cmd.figures(v_purse, v_cost, 'ducats'));
    end if;
    if v_cost > 0 then
      perform public.pay_city(v_ship.player_id, (select fl.port_id from public.fleets fl where fl.id = v_ship.fleet_id),
                              'REPAIR', v_cost);
    end if;
  end if;
  delete from public.fitted_units where id = v_unit;
$h$);

create or replace function pg_temp.recut_0158(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := replace(pg_get_functiondef(p_fn::regprocedure), E'\r', '');
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0158 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0158(v_def, h.old);
    if v_n <> 1 then
      raise exception '0158 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0158(fn) from defs_before_0158 order by fn;

comment on function public.mount_fitting(uuid, text) is
  '0126/0132/0158: THE one core that puts a fitting on a hull — the house lock, the requirements, her slots of '
  'the item''s RACK, a refit only at a build yard (E_NO_YARD), the two budgets on FIT only, one row into '
  'public.fitted_units. Called by cmd.do_fit and public.npc_fit_loadout. Server-only.';
comment on function public.unmount_fitting(uuid, text) is
  '0132/0158: THE one core that takes a fitting off a hull (one unit, counted; refits destroyed; while '
  'gear_wear_bite, a worn piece''s repair charged on its way off). Called by cmd.do_unfit. With '
  'public.mount_fitting, public.wear_units_for and public.repair_units_for, the only writers of '
  'public.fitted_units. Server-only.';

-- after: the same merchant reads, through the new bodies
select pg_temp.time_reads_0158('after');

-- ── 7. DARK, EVERY HULL: stats and the whole ship = the pre-image (old bodies vs new, one statement) ──
create temp table hulls_0158 on commit drop as
select s.id as ship_id,
       world.ship_stats(s.id)::text as new_stats, pg_temp.world_ship_stats_b0158(s.id)::text as old_stats,
       world.ship_view(s.id)::text as new_view, pg_temp.ship_view_b0158(s.id)::text as old_view
  from public.ships s;

-- ── 8. THE PROBE (its own companies, which build their own state; rolled back whole) ─────────────
create or replace function pg_temp.passage_0158(p_fleet uuid, p_from uuid, p_to uuid)
returns uuid
language plpgsql
as $$
declare
  v_leg jsonb;
begin
  select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
    into v_leg from public.sea_reaches a, public.sea_reaches b where a.port_id = p_from and b.port_id = p_to;
  return voyage.depart(p_fleet, voyage.segments_from_course(v_leg), p_from, p_to, now() - interval '30 days');
end $$;

-- one passage settled (by the old body or the new), and what it left — everything but the gear's wear
create or replace function pg_temp.settle_0158(p_voyage uuid, p_fleet uuid, p_old boolean)
returns jsonb
language plpgsql
as $$
declare
  v_p  uuid := (select player_id from public.fleets where id = p_fleet);
  v_t0 timestamptz := clock_timestamp();
  v_ms numeric;
begin
  if p_old then
    perform pg_temp.voyage_settle_b0158(p_fleet, now());
  else
    perform voyage.settle(p_fleet, now());
  end if;
  v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
  return jsonb_build_object(
    'nm', (select v.total_nm from public.voyages v where v.id = p_voyage),
    'voyage', (select jsonb_build_object('status', v.status, 'eta', v.eta, 'delay_hours', v.delay_hours, 'days', v.last_settled_day)
                 from public.voyages v where v.id = p_voyage),
    'events', (select coalesce(jsonb_agg(jsonb_build_object('day', ve.day_index, 'kind', ve.kind, 'payload', ve.payload) order by ve.day_index), '[]'::jsonb)
                 from public.voyage_events ve where ve.voyage_id = p_voyage),
    'ships', (select coalesce(jsonb_agg(jsonb_build_object('d', s.durability, 'crew', s.crew, 'water', s.water_t, 'food', s.food_t) order by s.id), '[]'::jsonb)
                from public.ships s where s.fleet_id = p_fleet),
    'fleet', (select jsonb_build_object('status', f.status, 'port', f.port_id) from public.fleets f where f.id = p_fleet),
    'report', (select e.payload from public.events e
                where e.player_id = v_p and e.kind = 'VOYAGE_REPORT' and e.payload->>'voyage_id' = p_voyage::text),
    'xp', (select coalesce(jsonb_agg(jsonb_build_object('ship', x.ship_id, 'xp', x.xp) order by x.ship_id), '[]'::jsonb)
             from public.ship_xp x join public.ships s on s.id = x.ship_id where s.fleet_id = p_fleet),
    'ducats', (select ducats from public.players where id = v_p),
    'units', (select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'item', u.item_code, 'wear', u.wear) order by u.id), '[]'::jsonb)
                from public.fitted_units u join public.ships s on s.id = u.ship_id where s.fleet_id = p_fleet),
    'ms', v_ms);
end $$;

-- a unit's wear, by ship name and item
create or replace function pg_temp.wear_0158(p_fleet uuid, p_ship text, p_item text)
returns numeric
language sql
as $$
  select u.wear from public.fitted_units u join public.ships s on s.id = u.ship_id
   where s.fleet_id = p_fleet and s.name = p_ship and u.item_code = p_item
   order by u.mounted_at, u.id limit 1
$$;

create or replace function pg_temp.probe_0158()
returns jsonb
language plpgsql
as $$
declare
  c_p     constant uuid := '00000000-0158-4000-8000-000000000001';
  v_lis   uuid := (select id from public.ports where code = 'LIS');
  v_fnc   uuid := (select id from public.ports where code = 'FNC');
  v_bare  uuid;
  v_p     uuid;
  v_pf    uuid;
  v_barca uuid;
  v_carl  uuid;
  v_m     uuid;
  v_mf    uuid;
  v_voy   uuid;
  v_out   jsonb := '{}'::jsonb;
  v_r     jsonb;
  v_x     jsonb;
  v_before jsonb;
  v_d0    bigint;
  v_t0    bigint;
  v_n     int;
begin
  begin
    -- OWN PRECONDITIONS: wear dark, skills dark, the city purses lit (so a REPAIR payment is a row)
    update public.world_config set value = 'false'::jsonb where key = 'gear_wear_bite';
    update public.world_config set value = 'false'::jsonb where key = 'skills_bite';
    update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled';
    if not public.port_has_shipyard(v_lis)
       or not exists (select 1 from public.port_buildings b where b.port_id = v_lis and b.kind = 'building_yard') then
      raise exception '0158 self-assert FAIL: the probe needs Lisbon to repair and to build ships';
    end if;
    -- a harbour with no build yard (the first by code — a place, not a subject)
    select p.id into v_bare from public.ports p
     where p.kind = 'HARBOUR' and not exists (select 1 from public.port_buildings b where b.port_id = p.id and b.kind = 'building_yard')
     order by p.code limit 1;

    -- P: a company at Lisbon — the barca it was founded with and a carlat; sails + guns on the barca, sails +
    -- an anchor on the carlat (one unit of each trigger: MILES, PIRATES, STORM), fitted through the door
    v_p := public.new_house(c_p, 'Casa do Desgaste 0158', 'PRT', 'LIS');
    select id into v_pf from public.fleets where player_id = v_p;
    perform public.credit(v_p, 'PROBE_0158', 10000000);
    select id into v_barca from public.ships where fleet_id = v_pf;
    v_carl := public.commission_ship(v_p, v_pf, 'carlat', 'Prova Carlat', false, true);
    insert into public.player_items (player_id, port_id, item_code, qty) values
      (v_p, v_lis, 'suit-of-sails', 3), (v_p, v_lis, 'broadside-guns', 1), (v_p, v_lis, 'anchor-and-cable', 1),
      (v_p, v_lis, 'fine-lines-1', 1), (v_p, v_bare, 'extended-hold-1', 1)
    on conflict (player_id, port_id, item_code) do update set qty = excluded.qty;
    perform cmd.do_fit(v_pf, jsonb_build_object('item', 'suit-of-sails', 'ship', 'Gaivota'));
    perform cmd.do_fit(v_pf, jsonb_build_object('item', 'broadside-guns', 'ship', 'Gaivota'));
    perform cmd.do_fit(v_pf, jsonb_build_object('item', 'suit-of-sails', 'ship', 'Prova Carlat'));
    perform cmd.do_fit(v_pf, jsonb_build_object('item', 'anchor-and-cable', 'ship', 'Prova Carlat'));
    v_before := jsonb_build_object('barca', world.ship_stats(v_barca), 'carlat', world.ship_stats(v_carl),
                                   'view', world.ship_view(v_barca));

    -- (D1) DARK ARRIVAL: one departure settled by the old body and by the new from the same start — the same
    --      passage, report, hulls, experience and coin; the new one wore the units, the old did not
    v_voy := pg_temp.passage_0158(v_pf, v_lis, v_fnc);
    v_out := v_out || jsonb_build_object('dark', jsonb_build_object(
      'new', pg_temp.rb_0158(format('select pg_temp.settle_0158(%L, %L, false)', v_voy, v_pf)),
      'old', pg_temp.rb_0158(format('select pg_temp.settle_0158(%L, %L, true)', v_voy, v_pf))));
    perform voyage.settle(v_pf, now());   -- for real: she lies at Funchal, worn
    select jsonb_build_object(
             'nm', vo.total_nm,
             'storms', (select count(*) from public.voyage_events ve where ve.voyage_id = vo.id and ve.kind = 'STORM'),
             'fights', (select count(*) from public.voyage_events ve where ve.voyage_id = vo.id and ve.kind = 'PIRATES'))
      into v_x from public.voyages vo where vo.id = v_voy;
    v_out := v_out || jsonb_build_object('passage', v_x, 'worn', jsonb_build_object(
      'barca_sails', pg_temp.wear_0158(v_pf, 'Gaivota', 'suit-of-sails'),
      'barca_guns', pg_temp.wear_0158(v_pf, 'Gaivota', 'broadside-guns'),
      'carlat_sails', pg_temp.wear_0158(v_pf, 'Prova Carlat', 'suit-of-sails'),
      'carlat_anchor', pg_temp.wear_0158(v_pf, 'Prova Carlat', 'anchor-and-cable')),
      'dark_after', jsonb_build_object('barca', world.ship_stats(v_barca), 'carlat', world.ship_stats(v_carl),
                                       'view', world.ship_view(v_barca),
                                       'old_barca', pg_temp.world_ship_stats_b0158(v_barca),
                                       'old_view', pg_temp.ship_view_b0158(v_barca)),
      'before', v_before);

    -- (D2) THE WRITER, EVERY TRIGGER (the passage's own days may hold no storm or fight): two days added to
    --      the probe's own voyage (a STORM and a PIRATES), then the one writer asked again
    insert into public.voyage_events (voyage_id, day_index, kind, payload, resolved_at) values
      (v_voy, 900, 'STORM', '{}'::jsonb, now()), (v_voy, 901, 'PIRATES', '{}'::jsonb, now());
    v_x := jsonb_build_object(
      'sails', pg_temp.wear_0158(v_pf, 'Gaivota', 'suit-of-sails'), 'guns', pg_temp.wear_0158(v_pf, 'Gaivota', 'broadside-guns'),
      'anchor', pg_temp.wear_0158(v_pf, 'Prova Carlat', 'anchor-and-cable'));
    v_n := public.wear_units_for(v_pf, v_voy);
    v_out := v_out || jsonb_build_object('writer', jsonb_build_object('n', v_n, 'before', v_x, 'after', jsonb_build_object(
      'sails', pg_temp.wear_0158(v_pf, 'Gaivota', 'suit-of-sails'), 'guns', pg_temp.wear_0158(v_pf, 'Gaivota', 'broadside-guns'),
      'anchor', pg_temp.wear_0158(v_pf, 'Prova Carlat', 'anchor-and-cable')),
      'storms', (select count(*) from public.voyage_events ve where ve.voyage_id = v_voy and ve.kind = 'STORM'),
      'fights', (select count(*) from public.voyage_events ve where ve.voyage_id = v_voy and ve.kind = 'PIRATES'),
      'nm', (select total_nm from public.voyages where id = v_voy)));
    -- capped at 100
    update public.fitted_units u set wear = 99.9 from public.ships s
     where s.id = u.ship_id and s.fleet_id = v_pf and u.item_code = 'broadside-guns';
    perform public.wear_units_for(v_pf, v_voy);
    v_out := v_out || jsonb_build_object('capped', pg_temp.wear_0158(v_pf, 'Gaivota', 'broadside-guns'));

    -- (D3) DARK REPAIR AND UNFIT: home to Lisbon; a worn fleet's repair and a worn piece's unfit are the old
    --      bodies' answers, and charge nothing for the gear
    perform pg_temp.settle_0158(pg_temp.passage_0158(v_pf, v_fnc, v_lis), v_pf, false);
    update public.ships s set durability = c.durability - 40 from public.ship_classes c
     where c.id = s.class_id and s.id = v_barca;
    update public.fitted_units u set wear = 50 from public.ships s
     where s.id = u.ship_id and s.fleet_id = v_pf and u.item_code in ('suit-of-sails', 'broadside-guns');
    v_out := v_out || jsonb_build_object('dark_repair', jsonb_build_object(
      'new', pg_temp.rb_0158(format('select cmd.do_repair(%L, ''{}''::jsonb)', v_pf)),
      'old', pg_temp.rb_0158(format('select pg_temp.cmd_do_repair_b0158(%L, ''{}''::jsonb)', v_pf))),
      'dark_unfit', pg_temp.rb_0158(format(
        'select jsonb_build_object(''r'', cmd.do_unfit(%L, ''{"item": "suit-of-sails", "ship": "Gaivota"}''::jsonb) - ''hold'' - ''speed'', ''ducats'', (select ducats from public.players where id = %L))',
        v_pf, v_p)),
      'ducats_now', (select ducats from public.players where id = v_p));

    -- (L) LIT (inside this rolled-back block)
    update public.world_config set value = 'true'::jsonb where key = 'gear_wear_bite';
    -- (L1) a worn unit's BUYS work at 1 − wear / 200 and its spends whole: the barca at sails 50 and guns 50
    --      reads exactly what she would with pristine units whose buys were × 0.75 (the catalogue bent, rolled
    --      back) — in both branches of ship_stats (skills dark, then lit with a ship skill)
    v_r := jsonb_build_object('worn', world.ship_stats(v_barca), 'racks', world.ship_view(v_barca)->'racks');
    -- the pristine-bent reading (pg_temp.bent_stats_0158, rolled back)
    v_out := v_out || jsonb_build_object('lit', pg_temp.rb_0158(format($q$
      select pg_temp.bent_stats_0158(%L)$q$, v_barca)), 'lit_worn', v_r);
    -- (L1b) skills lit, a ship skill (Portuguese Small Hulls I: the line's traits on a PRT small hull) — same law
    insert into public.player_skills (player_id, skill_id, level)
    select v_p, sk.id, 1 from public.skills sk where sk.code = 'PRT_SMALL'
    on conflict do nothing;
    update public.world_config set value = 'true'::jsonb where key = 'skills_bite';
    v_out := v_out || jsonb_build_object('lit_skill', jsonb_build_object(
      'worn', world.ship_stats(v_barca),
      'bent', pg_temp.rb_0158(format('select pg_temp.bent_stats_0158(%L)', v_barca)),
      'branch', 'ship' = any(public.house_skill_scopes(null, v_barca))));
    update public.world_config set value = 'false'::jsonb where key = 'skills_bite';

    -- (L2) REPAIR CHARGES AND PAYS THE CITY: the hull part is the old body's; the gear's is Σ unit_repair_cost;
    --      one REPAIR flow to Lisbon of the whole; every unit back to 0
    v_d0 := (select ducats from public.players where id = v_p);
    v_t0 := (select coalesce(sum(tf.ducats), 0) from public.treasury_flows tf where tf.port_id = v_lis and tf.player_id = v_p and tf.kind = 'REPAIR');
    v_x := jsonb_build_object(
      'quote', public.gear_repair_quote(v_pf),
      'sum', (select sum(public.unit_repair_cost(u.item_code, u.wear)) from public.fitted_units u join public.ships s on s.id = u.ship_id
               where s.fleet_id = v_pf and u.wear > 0),
      'old', pg_temp.rb_0158(format('select pg_temp.cmd_do_repair_b0158(%L, ''{}''::jsonb)', v_pf)),
      'sails_value', public.item_recipe_value('suit-of-sails'));
    v_r := cmd.do_repair(v_pf, '{}'::jsonb);
    v_out := v_out || jsonb_build_object('repair', v_x || jsonb_build_object(
      'r', v_r,
      'paid', v_d0 - (select ducats from public.players where id = v_p),
      'city', (select coalesce(sum(tf.ducats), 0) from public.treasury_flows tf where tf.port_id = v_lis and tf.player_id = v_p and tf.kind = 'REPAIR') - v_t0,
      'worn_left', (select count(*) from public.fitted_units u join public.ships s on s.id = u.ship_id where s.fleet_id = v_pf and u.wear > 0),
      'event', (select e.payload->'gear' from public.events e where e.player_id = v_p and e.kind = 'REPAIRING' and e.payload ? 'gear' order by e.created_at desc limit 1)));
    update public.fleets set status = 'DOCKED', busy_until = null where id = v_pf;   -- the repair's hours, skipped

    -- (L3) A WORN PIECE IS PAID FOR ON ITS WAY OFF: the carlat's anchor at 40 comes off at Lisbon
    update public.fitted_units u set wear = 40 from public.ships s
     where s.id = u.ship_id and s.id = v_carl and u.item_code = 'anchor-and-cable';
    v_d0 := (select ducats from public.players where id = v_p);
    v_t0 := (select coalesce(sum(tf.ducats), 0) from public.treasury_flows tf where tf.port_id = v_lis and tf.player_id = v_p and tf.kind = 'REPAIR');
    perform cmd.do_unfit(v_pf, '{"item": "anchor-and-cable", "ship": "Prova Carlat"}'::jsonb);
    v_out := v_out || jsonb_build_object('unfit', jsonb_build_object(
      'cost', public.unit_repair_cost('anchor-and-cable', 40),
      'paid', v_d0 - (select ducats from public.players where id = v_p),
      'city', (select coalesce(sum(tf.ducats), 0) from public.treasury_flows tf where tf.port_id = v_lis and tf.player_id = v_p and tf.kind = 'REPAIR') - v_t0,
      'store', (select qty from public.player_items where player_id = v_p and port_id = v_lis and item_code = 'anchor-and-cable')));
    -- … and refused with its figures when the coin is not there
    update public.fitted_units u set wear = 80 from public.ships s
     where s.id = u.ship_id and s.id = v_carl and u.item_code = 'suit-of-sails';
    update public.players set ducats = 1 where id = v_p;
    v_out := v_out || jsonb_build_object('unfit_broke', pg_temp.rb_0158(format(
      'select cmd.do_unfit(%L, ''{"item": "suit-of-sails", "ship": "Prova Carlat"}''::jsonb)', v_pf)));
    perform public.credit(v_p, 'PROBE_0158', 10000000);

    -- (R) A REFIT: Refitting I, skills lit; Fine Lines I on the carlat at Lisbon's build yard; a refit refused at a
    --     port with no build yard; the one fitted comes off there and is GONE (not in any store)
    insert into public.player_skills (player_id, skill_id, level)
    select v_p, sk.id, 1 from public.skills sk where sk.code = 'REFITTING'
    on conflict do nothing;
    update public.world_config set value = 'true'::jsonb where key = 'skills_bite';
    v_x := world.ship_stats(v_carl);
    perform cmd.do_fit(v_pf, '{"item": "fine-lines-1", "ship": "Prova Carlat"}'::jsonb);
    v_out := v_out || jsonb_build_object('refit', jsonb_build_object(
      'units', (select count(*) from public.fitted_units where ship_id = v_carl and item_code = 'fine-lines-1'),
      'speed_before', v_x->'speed', 'speed_after', world.ship_stats(v_carl)->'speed',
      'rack', (select r->'fitted' from jsonb_array_elements(world.ship_view(v_carl)->'racks') r where r->>'rack' = 'refit'),
      'store_lis', (select coalesce(sum(qty), 0) from public.player_items where player_id = v_p and item_code = 'fine-lines-1')));
    update public.fleets set port_id = v_bare where id = v_pf;   -- her own fleet, docked at a port with no build yard
    v_out := v_out || jsonb_build_object('refit_no_yard', pg_temp.rb_0158(format(
      'select cmd.do_fit(%L, ''{"item": "extended-hold-1", "ship": "Prova Carlat"}''::jsonb)', v_pf)),
      'bare', (select name from public.ports where id = v_bare));
    perform cmd.do_unfit(v_pf, '{"item": "fine-lines-1", "ship": "Prova Carlat"}'::jsonb);
    v_out := v_out || jsonb_build_object('refit_off', jsonb_build_object(
      'units', (select count(*) from public.fitted_units where ship_id = v_carl and item_code = 'fine-lines-1'),
      'stores', (select coalesce(sum(qty), 0) from public.player_items where player_id = v_p and item_code = 'fine-lines-1'),
      'speed', world.ship_stats(v_carl)->'speed'));
    update public.world_config set value = 'false'::jsonb where key = 'skills_bite';
    update public.world_config set value = 'false'::jsonb where key = 'gear_wear_bite';

    -- (M) A MERCHANT'S ARRIVAL WRITES NO WEAR: her own company, her fleet's loadout mounted through the same
    --     core, a passage — her units are what they were, row for row
    v_m := public.new_house(null, 'Companhia Gasta 0158', 'PRT', 'LIS', 'Prova', 'barca', 'Prova', null, true);
    select id into v_mf from public.fleets where player_id = v_m;
    perform public.npc_fit_loadout(s.id) from public.ships s where s.fleet_id = v_mf;
    v_x := (select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'item', u.item_code, 'wear', u.wear) order by u.id), '[]'::jsonb)
              from public.fitted_units u join public.ships s on s.id = u.ship_id where s.fleet_id = v_mf);
    v_r := pg_temp.settle_0158(pg_temp.passage_0158(v_mf, v_lis, v_fnc), v_mf, false);
    v_out := v_out || jsonb_build_object('merchant', jsonb_build_object(
      'arrived', v_r->'voyage'->>'status', 'nm', v_r->'nm', 'before', v_x, 'after', v_r->'units', 'ms', v_r->'ms'));

    raise exception 'PROBE_ROLLBACK_0158';
  exception when others then
    if sqlerrm <> 'PROBE_ROLLBACK_0158' then raise; end if;
  end;
  return v_out;
end $$;

-- the pristine-but-bent reading: the barca's units at wear 0 and the two items' buys × 0.75 (run rolled back)
create or replace function pg_temp.bent_stats_0158(p_ship uuid)
returns jsonb
language plpgsql
as $$
begin
  update public.fitted_units set wear = 0 where ship_id = p_ship;
  update public.item_effects set delta = round(delta * 0.75, 2)
   where item_code in ('suit-of-sails', 'broadside-guns') and delta > 0;
  return world.ship_stats(p_ship);
end $$;

create temp table probe_0158 (j jsonb) on commit drop;
do $$
declare
  v_try   int := 0;
  v_state text;
  v_msg   text;
begin
  loop
    v_try := v_try + 1;
    begin
      insert into probe_0158 select pg_temp.probe_0158();
      exit;
    exception when lock_not_available or deadlock_detected then
      get stacked diagnostics v_msg = message_text, v_state = returned_sqlstate;
    end;
    if v_try >= 5 then
      raise exception '0158 self-assert FAIL: LOCK CONTENTION, not a result — the probe could not get its locks in 5 tries (%: %). Re-run the push.',
        v_state, v_msg;
    end if;
    perform pg_sleep(0.2);
  end loop;
end $$;

-- ── 9. SELF-ASSERT ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  b       record;
  d       record;
  h       record;
  v_pp    record;
  r       record;
  v_def   text;
  v_pr    jsonb := (select j from probe_0158);
  v_bad   bigint;
  v_n     bigint;
  v_w     jsonb;
  v_nm    numeric;
  v_exp   numeric;
  v_writers text[];
  v_notes text := '';
  v_fac   numeric;
begin
  select * into b from before_0158;
  if public.wc('gear_wear_bite') is distinct from 'false'::jsonb or public.wc_num('gear_wear_per_1000nm') <> 1
     or public.wc_num('gear_wear_per_fight') <> 4 or public.wc_num('gear_wear_per_storm') <> 3
     or public.wc_num('gear_repair_pct') <> 0.30 then
    raise exception '0158 self-assert FAIL: the knobs are not as shipped — or one was already set';
  end if;

  -- (a) DARK, EVERY HULL: ship_stats and the whole ship_view = the old bodies' (one statement, as text)
  select count(*), count(*) filter (where new_stats is distinct from old_stats or new_view is distinct from old_view)
    into v_n, v_bad from hulls_0158;
  if v_n = 0 or v_bad <> 0 then
    raise exception '0158 self-assert FAIL: dark, % of % hull(s) read a different ship_stats or ship_view', v_bad, v_n;
  end if;

  -- (b) THE CATALOGUE: the 115 items unmoved; 14 refits added whole; every item has exactly one use row
  if (select md5(string_agg(to_jsonb(k)::text, '|' order by k.code)) from public.item_kinds k where k.code in (select item_code from public.item_profile where rack <> 'refit')) <> b.kinds_hash
     or (select md5(string_agg(to_jsonb(ip)::text, '|' order by ip.item_code)) from public.item_profile ip where ip.rack <> 'refit') <> b.profile_hash
     or (select md5(string_agg(to_jsonb(e)::text, '|' order by e.item_code, e.stat)) from public.item_effects e where e.item_code not in (select item_code from public.item_profile where rack = 'refit')) <> b.effects_hash
     or (select md5(string_agg(format('%s/%s/%s', ir.item_code, ir.good_id, ir.qty), '|' order by ir.item_code, ir.good_id)) from public.item_recipes ir where ir.item_code not in (select item_code from public.item_profile where rack = 'refit')) <> b.recipes_hash then
    raise exception '0158 self-assert FAIL: a live item''s kind, profile, effects or recipe moved';
  end if;
  if (select count(*) from public.item_kinds) <> b.kinds + 14
     or (select count(*) from public.item_profile where rack = 'refit') <> 14
     or exists (select 1 from public.item_profile where rack = 'refit' and (deck <> 0 or hands <> 0 or active))
     or (select count(*) from public.item_effects e join public.item_profile ip on ip.item_code = e.item_code where ip.rack = 'refit') <> 28
     or (select count(*) from public.item_recipes e join public.item_profile ip on ip.item_code = e.item_code where ip.rack = 'refit') <> 28
     or (select count(*) from public.skill_requirements where subject_kind = 'item' and subject_code in (select item_code from public.item_profile where rack = 'refit')) <> 14
     or (select count(*) from public.skill_requirements) <> b.requirements + 14
     or exists (select 1 from public.skill_requirements sr join public.item_profile ip on ip.item_code = sr.subject_code
                 where sr.subject_kind = 'item' and ip.rack = 'refit'
                   and (sr.skill_code <> 'REFITTING' or sr.level <> case ip.grade when 1 then 1 else 5 end)) then
    raise exception '0158 self-assert FAIL: the fourteen refits are not whole (kinds %, refit profiles %)',
      (select count(*) from public.item_kinds), (select count(*) from public.item_profile where rack = 'refit');
  end if;
  -- every refit buys one stat and spends another (0074's rule)
  if exists (select 1 from public.item_profile ip where ip.rack = 'refit'
              and not (exists (select 1 from public.item_effects e where e.item_code = ip.item_code and e.delta > 0)
                   and exists (select 1 from public.item_effects e where e.item_code = ip.item_code and e.delta < 0))) then
    raise exception '0158 self-assert FAIL: a refit buys a stat without spending one';
  end if;
  if (select count(*) from public.item_use) <> (select count(*) from public.item_kinds)
     or exists (select 1 from public.item_kinds k where not exists (select 1 from public.item_use u where u.item_code = k.code))
     or exists (select 1 from public.item_use u join public.item_profile ip on ip.item_code = u.item_code
                 where (ip.active and coalesce(u.trigger, '') not in ('PIRATES', 'STORM'))
                    or (not ip.active and jsonb_array_length(u.consumes) > 0)
                    or (ip.rack in ('refit', 'flourish') and u.trigger is not null))
     or exists (select 1 from public.item_use u cross join lateral jsonb_array_elements(u.consumes) c
                 where not exists (select 1 from public.goods g where g.code = c->>'good') or (c->>'qty')::numeric <= 0) then
    raise exception '0158 self-assert FAIL: what works an item is not one row per item, or breaks §6.1 (an active on MILES, a passive that consumes, a refit that wears, a good that does not exist)';
  end if;

  -- (c) DARK ARRIVAL: the same passage, report, hulls, experience and coin as the old body; the new one wore
  --     the units by miles / 1,000 (sails), PIRATES days × 4 (guns), STORM days × 3 (anchor); stats unmoved
  if ((v_pr->'dark'->'new') - 'units' - 'ms') is distinct from ((v_pr->'dark'->'old') - 'units' - 'ms')
     or v_pr->'dark'->'new'->'voyage'->>'status' <> 'ARRIVED' or v_pr->'dark'->'new' ? 'refused' then
    raise exception '0158 self-assert FAIL: dark, the passage moved beyond the gear''s wear: new % / old %',
      (v_pr->'dark'->'new') - 'events', (v_pr->'dark'->'old') - 'events';
  end if;
  if exists (select 1 from jsonb_array_elements(v_pr->'dark'->'old'->'units') u where (u->>'wear')::numeric <> 0) then
    raise exception '0158 self-assert FAIL: the old body wore a unit — the probe did not start pristine';
  end if;
  v_nm := (v_pr->'passage'->>'nm')::numeric;
  -- (the view's `speed` is what she makes with the hull she has — 0124's voyage.ship_speed — and is compared
  --  old builder against new above, not before against after)
  if v_nm < 300
     or (v_pr->'worn'->>'barca_sails')::numeric <> round(v_nm / 1000, 2)
     or (v_pr->'worn'->>'carlat_sails')::numeric <> round(v_nm / 1000, 2)
     or (v_pr->'worn'->>'barca_guns')::numeric <> least(100, (v_pr->'passage'->>'fights')::numeric * 4)
     or (v_pr->'worn'->>'carlat_anchor')::numeric <> least(100, (v_pr->'passage'->>'storms')::numeric * 3) then
    raise exception '0158 self-assert FAIL: the arrival did not wear the units as the passage says: %', jsonb_build_object('passage', v_pr->'passage', 'worn', v_pr->'worn');
  end if;
  if v_pr->'dark_after'->'barca' is distinct from v_pr->'before'->'barca'
     or v_pr->'dark_after'->'carlat' is distinct from v_pr->'before'->'carlat'
     or v_pr->'dark_after'->'barca' is distinct from v_pr->'dark_after'->'old_barca'
     or v_pr->'dark_after'->'view' is distinct from v_pr->'dark_after'->'old_view'
     or ((v_pr->'dark_after'->'view') - 'water_t' - 'food_t' - 'durability' - 'crew' - 'speed' - 'xp' - 'level' - 'xp_from' - 'next_level_at')
        is distinct from ((v_pr->'before'->'view') - 'water_t' - 'food_t' - 'durability' - 'crew' - 'speed' - 'xp' - 'level' - 'xp_from' - 'next_level_at') then
    raise exception '0158 self-assert FAIL: dark, worn units moved a stat or the ship view: before %, after % (carlat % → %); view keys that moved: % (old builder: %)',
      v_pr->'before'->'barca', v_pr->'dark_after'->'barca', v_pr->'before'->'carlat', v_pr->'dark_after'->'carlat',
      (select jsonb_object_agg(e.key, jsonb_build_array(v_pr->'before'->'view'->e.key, e.value))
         from jsonb_each(v_pr->'dark_after'->'view') e where e.value is distinct from v_pr->'before'->'view'->e.key),
      (select jsonb_object_agg(e.key, e.value)
         from jsonb_each(v_pr->'dark_after'->'old_view') e where e.value is distinct from v_pr->'dark_after'->'view'->e.key);
  end if;

  -- (d) THE WRITER, every trigger: + miles / 1,000, + 4 a PIRATES day, + 3 a STORM day (the probe's added days
  --     counted), held at 100
  v_w := v_pr->'writer';
  if (v_w->>'n')::int < 3
     or (v_w->'after'->>'sails')::numeric <> round((v_w->'before'->>'sails')::numeric + (v_w->>'nm')::numeric / 1000, 2)
     or (v_w->'after'->>'guns')::numeric <> least(100, (v_w->'before'->>'guns')::numeric + 4 * (v_w->>'fights')::numeric)
     or (v_w->'after'->>'anchor')::numeric <> least(100, (v_w->'before'->>'anchor')::numeric + 3 * (v_w->>'storms')::numeric)
     or (v_w->>'fights')::int < 1 or (v_w->>'storms')::int < 1
     or (v_pr->>'capped')::numeric <> 100 then
    raise exception '0158 self-assert FAIL: the one writer did not wear by trigger, or past 100: %', v_w || jsonb_build_object('capped', v_pr->'capped');
  end if;

  -- (e) DARK REPAIR AND UNFIT: the old body's answer exactly (nothing charged for the gear)
  if v_pr->'dark_repair'->'new' is distinct from v_pr->'dark_repair'->'old' or v_pr->'dark_repair'->'new' ? 'refused'
     or v_pr->'dark_repair'->'new' ? 'gear' then
    raise exception '0158 self-assert FAIL: dark, cmd.do_repair moved: new % / old %', v_pr->'dark_repair'->'new', v_pr->'dark_repair'->'old';
  end if;
  if v_pr->'dark_unfit' ? 'refused' or (v_pr->'dark_unfit'->>'ducats')::bigint <> (v_pr->>'ducats_now')::bigint then
    raise exception '0158 self-assert FAIL: dark, taking a worn piece off charged for it: %', v_pr->'dark_unfit';
  end if;

  -- (f) LIT: a worn unit = a pristine one whose buys are × (1 − 50 / 200), spends whole — both ship_stats branches
  if (v_pr->'lit') ? 'refused' or v_pr->'lit' is distinct from v_pr->'lit_worn'->'worn'
     or v_pr->'lit_worn'->'worn' is not distinct from v_pr->'before'->'barca' then
    raise exception '0158 self-assert FAIL: lit, the worn barca % is not the pristine-bent barca % (or did not move from %)',
      v_pr->'lit_worn'->'worn', v_pr->'lit', v_pr->'before'->'barca';
  end if;
  if not coalesce((v_pr->'lit_skill'->>'branch')::boolean, false)
     or v_pr->'lit_skill'->'worn' is distinct from v_pr->'lit_skill'->'bent' then
    raise exception '0158 self-assert FAIL: lit with a ship skill, the worn barca % is not the pristine-bent % (skill branch: %)',
      v_pr->'lit_skill'->'worn', v_pr->'lit_skill'->'bent', v_pr->'lit_skill'->'branch';
  end if;
  -- the panel's words for a unit at 50: "50% worn · works at 75%"; the figurehead and refits carry none
  if not exists (select 1 from jsonb_array_elements(v_pr->'lit_worn'->'racks') rk, jsonb_array_elements(rk->'fitted') u
                  where u->>'code' = 'suit-of-sails' and u->>'wear_words' = '50% worn · works at 75%' and (u->>'works_pct')::int = 75) then
    raise exception '0158 self-assert FAIL: the ship panel was not served the worn sails'' words: %', v_pr->'lit_worn'->'racks';
  end if;

  -- (g) REPAIR CHARGES AND PAYS THE CITY: cost = the old body's hull cost + Σ unit_repair_cost; Lisbon is paid
  --     the whole in one REPAIR flow; the purse pays it; no unit is worn after; a G1 suit at 100 ≈ 220
  if (v_pr->'repair'->'r'->>'cost')::bigint <> (v_pr->'repair'->'old'->>'cost')::bigint + (v_pr->'repair'->>'sum')::bigint
     or (v_pr->'repair'->>'sum')::bigint <= 0
     or (v_pr->'repair'->'quote'->>'cost')::bigint <> (v_pr->'repair'->>'sum')::bigint
     or v_pr->'repair'->'r'->'gear' is distinct from v_pr->'repair'->'quote'
     or v_pr->'repair'->'event' is distinct from v_pr->'repair'->'quote'
     or (v_pr->'repair'->>'paid')::bigint <> (v_pr->'repair'->'r'->>'cost')::bigint
     or (v_pr->'repair'->>'city')::bigint <> (v_pr->'repair'->'r'->>'cost')::bigint
     or (v_pr->'repair'->>'worn_left')::int <> 0
     or round((v_pr->'repair'->>'sails_value')::numeric * 0.30) not between 150 and 300 then
    raise exception '0158 self-assert FAIL: the repair did not charge the hull and the gear, pay the city and repair every unit: %', v_pr->'repair';
  end if;
  -- (h) A WORN PIECE IS PAID FOR ON ITS WAY OFF, back in the store pristine; refused with figures when broke
  if (v_pr->'unfit'->>'paid')::bigint <> (v_pr->'unfit'->>'cost')::bigint or (v_pr->'unfit'->>'cost')::bigint <= 0
     or (v_pr->'unfit'->>'city')::bigint <> (v_pr->'unfit'->>'cost')::bigint or (v_pr->'unfit'->>'store')::int <> 1 then
    raise exception '0158 self-assert FAIL: a worn piece came off without its repair paid to the city: %', v_pr->'unfit';
  end if;
  if coalesce(v_pr->'unfit_broke'->>'refused', '') not like 'E_INSUFFICIENT_FUNDS: Suit of Sails is 80% worn and is repaired before it comes off%' then
    raise exception '0158 self-assert FAIL: an unpayable worn piece was not refused in its words: %', v_pr->'unfit_broke';
  end if;

  -- (i) A REFIT: fitted at a build yard (its rack, its effect), refused where there is none in words, and
  --     GONE when removed — in no store, its effect gone
  if (v_pr->'refit'->>'units')::int <> 1 or (v_pr->'refit'->>'store_lis')::int <> 0
     or (v_pr->'refit'->>'speed_after')::numeric <> (v_pr->'refit'->>'speed_before')::numeric + 0.2
     or jsonb_array_length(coalesce(v_pr->'refit'->'rack', '[]'::jsonb)) <> 1
     or (v_pr->'refit'->'rack'->0) ? 'wear' then
    raise exception '0158 self-assert FAIL: the refit did not go on at the build yard: %', v_pr->'refit';
  end if;
  if coalesce(v_pr->'refit_no_yard'->>'refused', '') <>
       format('E_NO_YARD: Extended Hold I is a refit, fitted only at a build yard, and %s has none', v_pr->>'bare') then
    raise exception '0158 self-assert FAIL: a refit away from a build yard was not refused in its words: %', v_pr->'refit_no_yard';
  end if;
  if (v_pr->'refit_off'->>'units')::int <> 0 or (v_pr->'refit_off'->>'stores')::int <> 0
     or (v_pr->'refit_off'->>'speed')::numeric <> (v_pr->'refit'->>'speed_before')::numeric then
    raise exception '0158 self-assert FAIL: a removed refit is not gone: %', v_pr->'refit_off';
  end if;

  -- (j) A MERCHANT'S ARRIVAL WRITES NO WEAR: her units, row for row, as before — and she had some
  if v_pr->'merchant'->>'arrived' <> 'ARRIVED' or jsonb_array_length(v_pr->'merchant'->'before') = 0
     or v_pr->'merchant'->'before' is distinct from v_pr->'merchant'->'after' then
    raise exception '0158 self-assert FAIL: a merchant''s arrival wore her gear, or she had none to wear: %', v_pr->'merchant';
  end if;

  -- (k) THE PROBE WORLD IS GONE
  if exists (select 1 from public.players where auth_uid = '00000000-0158-4000-8000-000000000001'
                                            or company_name = 'Companhia Gasta 0158')
     or public.wc('gear_wear_bite') is distinct from 'false'::jsonb
     or exists (select 1 from public.fitted_units u join public.item_profile ip on ip.item_code = u.item_code where ip.rack = 'refit') then
    raise exception '0158 self-assert FAIL: the probe world was not rolled back';
  end if;

  -- (l) THE WRITERS of fitted_units: mount (insert), unmount (delete), the wear writer and the repairer (update)
  --     — every live body scanned; POSITIVE CONTROL: a planted writer (rolled back) is seen by the same scan
  create or replace function pg_temp.fitted_writers_0158()
  returns text[]
  language sql
  stable
  as $f$
    select coalesce(array_agg(w.entry order by w.entry), '{}')
      from (select n.nspname || '.' || p.proname || ':' ||
                   case when p.prosrc ~* 'insert\s+into\s+public\.fitted_units' then 'insert' else '' end ||
                   case when p.prosrc ~* 'delete\s+from\s+public\.fitted_units' then 'delete' else '' end ||
                   case when p.prosrc ~* 'update\s+public\.fitted_units' then 'update' else '' end as entry
              from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where n.nspname not in ('pg_catalog', 'information_schema') and n.nspname not like 'pg\_%'
               and p.prosrc ~* '(insert\s+into|delete\s+from|update|truncate)\s+(table\s+)?public\.fitted_units') w
  $f$;
  v_writers := pg_temp.fitted_writers_0158();
  if v_writers is distinct from array['public.mount_fitting:insert', 'public.repair_units_for:update',
                                      'public.unmount_fitting:delete', 'public.wear_units_for:update'] then
    raise exception '0158 self-assert FAIL: the live writers of fitted_units are %', v_writers;
  end if;
  begin
    execute $planted$create function public.zz_planted_writer_0158() returns void language sql as
      'update public.fitted_units set wear = wear where false'$planted$;
    if cardinality(pg_temp.fitted_writers_0158()) <> 5 then
      raise exception '0158 self-assert FAIL: the writer scan did not see a planted writer — it proves nothing';
    end if;
    raise exception 'CONTROL_ROLLBACK_0158';
  exception when others then
    if sqlerrm <> 'CONTROL_ROLLBACK_0158' then raise; end if;
  end;
  if exists (select 1 from pg_proc where proname = 'zz_planted_writer_0158') then
    raise exception '0158 self-assert FAIL: the planted writer was not rolled back';
  end if;
  -- the wear writer is called by settle only, inside the players-only block; no core reads is_npc
  select string_agg(ns.nspname || '.' || pp.proname, ', ' order by ns.nspname, pp.proname) into v_def
    from pg_proc pp join pg_namespace ns on ns.oid = pp.pronamespace
   where ns.nspname not like 'pg\_%' and pp.prosrc ~ 'wear_units_for\(' and pp.proname <> 'wear_units_for';
  if v_def is distinct from 'voyage.settle' then
    raise exception '0158 self-assert FAIL: the wear writer is called by %, not by voyage.settle alone', v_def;
  end if;
  v_def := pg_get_functiondef('voyage.settle(uuid, timestamp with time zone)'::regprocedure);
  if strpos(v_def, 'perform public.wear_units_for(p_fleet, v.id)')
       < strpos(v_def, 'if not (select p.is_npc from public.players p where p.id = f.player_id) then')
     or strpos(v_def, 'if not (select p.is_npc from public.players p where p.id = f.player_id) then') = 0
     or strpos(v_def, 'perform public.wear_units_for(p_fleet, v.id)') > strpos(v_def, 'perform cmd.run_standing_provision(p_fleet);')
     or pg_temp.occurs_0158(v_def, 'select p.is_npc from') <> 1 then
    raise exception '0158 self-assert FAIL: voyage.settle does not wear the units inside its one players-only block';
  end if;
  select string_agg(f.fn, ', ') into v_def
    from unnest(array['public.wear_units_for(uuid, uuid)', 'public.repair_units_for(uuid)', 'public.gear_repair_quote(uuid)',
                      'public.mount_fitting(uuid, text)', 'public.unmount_fitting(uuid, text)', 'world.ship_racks(uuid, jsonb)',
                      'world.ship_stats(uuid)', 'cmd.do_repair(uuid, jsonb)']) f(fn)
   where strpos(pg_get_functiondef(f.fn::regprocedure), 'is_npc') > 0;
  if v_def is not null then
    raise exception '0158 self-assert FAIL: a gear core reads is_npc: %', v_def;
  end if;

  -- (m) THE RE-CUTS reverse to their pre-images; ACL / volatility / definer / config unmoved; the rest untouched
  for d in select * from defs_before_0158 order by fn loop
    v_def := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0158 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0158(v_def, h.new) <> 1 then
        raise exception '0158 self-assert FAIL: hunk % of % is not in the new body exactly once', h.n, d.fn;
      end if;
      v_def := replace(v_def, h.new, h.old);
    end loop;
    if v_def <> d.def then
      raise exception '0158 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef, coalesce(pr.proconfig::text, '') as cfg
      into v_pp from pg_proc pr where pr.oid = d.fn::regprocedure;
    if v_pp.acl <> d.acl or v_pp.vol <> d.vol or v_pp.secdef <> d.secdef or v_pp.cfg <> d.cfg then
      raise exception '0158 self-assert FAIL: % changed its ACL, volatility, definer or config', d.fn;
    end if;
  end loop;
  for d in select * from untouched_before_0158 loop
    if replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '') <> d.def
       or coalesce((select pr.proacl::text from pg_proc pr where pr.oid = d.fn::regprocedure), '') <> d.acl then
      raise exception '0158 self-assert FAIL: % moved — it was to be left untouched', d.fn;
    end if;
  end loop;

  -- (n) THE WALL: no new entry point; the new functions and the new table server-only; no client write
  if (select count(*) from public.client_rpc_entry_points()) <> b.entry_points
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0
     or exists (select 1 from unnest(array['public.gear_wear_on()', 'public.wear_factor(numeric)', 'public.worn_delta(numeric, numeric)',
                                           'public.unit_wear_card(text, numeric)', 'public.wear_units_for(uuid, uuid)',
                                           'public.item_recipe_value(text)', 'public.unit_repair_cost(text, numeric)',
                                           'public.gear_repair_quote(uuid)', 'public.repair_units_for(uuid)']) f(fn),
                       unnest(array['anon', 'authenticated']) rl(role)
                 where has_function_privilege(rl.role, f.fn, 'execute'))
     or has_table_privilege('anon', 'public.item_use', 'select,insert,update,delete')
     or has_table_privilege('authenticated', 'public.item_use', 'select,insert,update,delete') then
    raise exception '0158 self-assert FAIL: the registry, the grant wall or the read wall moved, or a client can reach a new function or table';
  end if;

  for r in select bf.what, bf.ms as before_ms, af.ms as after_ms, bf.hulls
             from reads_0158 bf join reads_0158 af on af.what = bf.what and af.phase = 'after'
            where bf.phase = 'before' order by bf.what loop
    v_notes := v_notes || format('%s over %s merchant hull(s) %s ms → %s ms; ', r.what, r.hulls, r.before_ms, r.after_ms);
  end loop;
  v_fac := public.wear_factor(50);

  raise notice '0158 self-assert ok: GEAR WEARS, AND IS REPAIRED (dark: gear_wear_bite false; 1 a 1,000 miles, 4 a pirates day, 3 a storm day, repair 30%%). DARK: % hull(s) — ship_stats and ship_view = the old bodies''; a % mile passage (% storm day(s), % pirates day(s)) wore the sails %, the guns %, the anchor % and moved no stat, report, hull, experience or coin (old body vs new; settle % ms → % ms); a worn fleet''s repair and a worn piece''s unfit = the old bodies''. THE WRITER: + miles / 1,000, + 4 a pirates day, + 3 a storm day, held at 100. LIT (rolled back): a unit at 50 works at % (= pristine with its buys × 0.75, both ship_stats branches; "50%% worn · works at 75%%" served); repair charged % = hull % + gear % (% units) and paid Lisbon % in one REPAIR flow, every unit repaired; an anchor at 40 came off for % paid to the city, back in the store; an unpayable worn piece refused with figures. REFIT: Fine Lines I on at Lisbon''s build yard (+0.2 knots), "%" at %, and gone when removed. MERCHANT: an arrival wrote no wear (% unit(s) unmoved; settle % ms). CATALOGUE: 14 refits, % item uses, the live items unmoved. WRITERS: mount (insert), unmount (delete), wear_units_for and repair_units_for (update) — a planted writer seen. 6 bodies reverse, 10 untouched, no entry point. READS: %',
    v_n, round(v_nm), v_pr->'passage'->>'storms', v_pr->'passage'->>'fights',
    v_pr->'worn'->>'barca_sails', v_pr->'worn'->>'barca_guns', v_pr->'worn'->>'carlat_anchor',
    v_pr->'dark'->'old'->>'ms', v_pr->'dark'->'new'->>'ms',
    round(v_fac * 100) || '%', v_pr->'repair'->'r'->>'cost', v_pr->'repair'->'old'->>'cost', v_pr->'repair'->>'sum', v_pr->'repair'->'quote'->>'units',
    v_pr->'repair'->>'city', v_pr->'unfit'->>'cost',
    v_pr->'refit_no_yard'->>'refused', v_pr->>'bare', jsonb_array_length(v_pr->'merchant'->'before'), v_pr->'merchant'->>'ms',
    (select count(*) from public.item_use), v_notes;
end $$;
