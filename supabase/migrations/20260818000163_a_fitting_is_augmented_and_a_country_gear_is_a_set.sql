-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0163 — A FITTING IS AUGMENTED, AND A COUNTRY'S GEAR IS A SET  (S16 Gear III: perks, Country gear,
--        sets — closed until Augmentation and the line skills count)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY NOW ─────────────────────────────────────────────────────────────────────────────────────
-- docs/SHIPS_AND_SKILLS.md §8 row S16 (§6.2 the Country rung, §6.6 perks, §6.7 sets; docs/SKILLS_AND_
-- CAPTAINS.md §9: S16 unchanged by v2). The owner: *"the gear should be like eve too, plus rs3"* — RS3's
-- augments (a perk the player CHOOSES, paid in kits, lost with the piece) and its sets (2- and 4-piece
-- bonuses), on EVE's meta ladder's Country rung. 0132 gave every mounted unit a `perks` column (≤ 2) that
-- nothing writes; the Augmentation skill (0131) gates nothing.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) KNOB perks_max_per_unit 2 (only where absent).
-- (2) THE CATALOGUE (data/gear.json `perks`, `sets`; held by the world guard):
--       public.perks (10) — a perk's word, the racks (and, for Swift / Roomy, the item type / base type)
--         it may sit on, what one rank does (flat on a stat; a per cent of the unit's own stat; wear;
--         Deck; Hands) and the kit it costs (Seasoned: any kit).
--       public.gear_set_bonuses (24 rows) — each line's set: what 2 pieces give, and what 4 add.
-- (3) THE GEAR (scripts/build-gear.mjs `--sql-0163`): 44 Country items (a line's four set pieces —
--     High, Mid, Low, Figurehead; buys × 2.40, speed / cargo × 1.70, + one line-flavoured second buy;
--     Deck / Hands × 1.3; grade 4, meta 6; need the module skill IV + the line's Medium Hulls I; a tier-2
--     workshop) and 4 kits (rack `kit`, a rack no hull has places in — kits are never fitted). Their
--     item_use rows; public.item_line (44) — a Country item's line, the one home of BOTH "it is a piece of
--     that line's set" and "it is made only where that line's ships are built".
-- (4) THE READINGS:
--       public.perk_ranks(perks)                 the unit's perks as (code, rank) — 'SWIFT:2' on the row
--       public.unit_perk_deltas(item, perks)     what a unit's perks add to the ship's stats
--       public.perk_wear_mult(perks)             Seasoned: × 0.75 / 0.50 / 0.25 of the wear a passage brings
--       public.perk_unit_cost(cost, kind, perks) Light (Deck − rank, never below 1) / Handy (Hands − 10 % a rank)
--       public.ship_set_bonus(ship)              each line's pieces aboard (distinct racks) → its bonuses, as
--                                                flat deltas (a per cent is of the class base + what is mounted)
--       public.ship_set_hands_pct(ship)          the VOC set's "fitted items need −10 % hands"
--       world.ship_set_card(ship)                the ship panel's set progress (served only where a piece is)
--       public.unit_perk_card(item, perks)       the panel's words for a unit's perks and, for a unit that
--                                                may be augmented (grade ≥ 3, T2, Country, Famous), its options
-- (5) THE DOOR: cmd.augment_fitting(ship, item, perk, rank) (+1 entry point) → THE CORE
--     public.augment_fitting_for(player, ship, item, perk, rank, kit): docked at a tier-3 workshop, a unit
--     that may be augmented, a perk for its rack, rank ≤ ⌈Augmentation / 2⌉, a second perk only at
--     Augmentation V (and never more than perks_max_per_unit), `rank` kits from the store in this city —
--     each refused in its own words. The perk is CHOSEN (no lottery, 0126:30); choosing a perk the unit
--     already has replaces it. Dark (skills_bite off) no level counts: closed to everyone, said so.
-- (6) THE HUNKS (sliced from the LIVE bodies): world.ship_stats (both branches: the units' perks and the
--     sets join the units' deltas), world.ship_budget (Light / Handy per unit; the VOC set's Hands),
--     world.ship_racks (each unit's perk card), world.ship_view (the set card), public.wear_units_for
--     (Seasoned), public.made_only_in (a Country item only where its line builds), public.client_rpc_
--     entry_points (+ cmd.augment_fitting). public.unmount_fitting needs nothing: the perks live on the
--     unit's row and go with it.
--
-- ── WHAT IT DELIBERATELY DOES NOT DO ────────────────────────────────────────────────────────────
-- No row already in the world moves; no ALTER; no FK; no cron; no client write. Dark (skills_bite false):
-- every Country item needs skills, so no set piece can be made or fitted, and Augmentation counts 0, so no
-- perk can be chosen — every stat, budget, rack and ship view is the pre-image for every hull (proven old
-- body vs new, one statement). Merchants: nothing (G1 gear, no perks, no set pieces; no exemption in any core).
--
-- ── LOCKS ───────────────────────────────────────────────────────────────────────────────────────
-- Heavy reads first. Then ROW EXCLUSIVE on catalogue tables nothing live writes (gear_racks, item_kinds,
-- item_profile, item_effects, item_recipes, item_use, skill_requirements), five new tables and one knob.
-- CREATE OR REPLACE FUNCTION locks no table. Probe writes are rolled back; a probe that meets a lock is
-- retried 5 × 0.2 s, then LOCK CONTENTION. No top-level LOCK / SET LOCAL / BEGIN / SET ROLE.
--
-- SUPERSEDES, by hunks sliced from the LIVE bodies (LF-normalised), each asserted to occur exactly once and
-- to reverse to its pre-image, ACL / volatility / definer / config unchanged: world.ship_stats (0158),
-- world.ship_budget (0151), world.ship_racks (0158), world.ship_view (0157), public.wear_units_for (0158),
-- public.made_only_in (0159), public.client_rpc_entry_points (0157 and after).
--
-- ROLLBACK (forward migration): reverse the seven bodies' hunks (old text in hunks_0163); drop the door,
-- the core, the readings and the five tables; delete the knob and the 48 items' rows (skill_requirements,
-- item_use, item_recipes, item_effects, item_profile, item_kinds) and the `kit` rack, after asserting no
-- fitted_units / player_items row names one; set fitted_units.perks to '{}' (the perks die with the slice —
-- §6.6: they are bound to the unit).
-- VERSION: 0163 (provisional; renumbered to head + 1 at deploy). Applies on 0159 (S15) — K6–K8 (0160–0162)
-- re-cut none of the bodies above but client_rpc_entry_points, whose hunk here sits at the list's HEAD.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  perform set_config('random_page_cost', '1.1', true);   -- prod's planner page cost (0149's header)
end $guard$;

-- ── 0. HELPERS (pg_temp, gone at commit) ───────────────────────────────────────────────────────
create or replace function pg_temp.occurs_0163(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

create or replace function pg_temp.as_0163(p_uid uuid)
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  perform set_config('request.jwt.claims', case when p_uid is null then '' else json_build_object('sub', p_uid)::text end, true);
end $$;

create temp table reads_0163 (phase text, what text, hulls bigint, ms numeric) on commit drop;
create or replace function pg_temp.time_reads_0163(p_phase text)
returns void
language plpgsql
as $$
declare
  v_t0  timestamptz;
  v_ids uuid[];
begin
  select array_agg(s.id order by s.id) into v_ids from public.ships s join public.players p on p.id = s.player_id where p.is_npc;
  v_t0 := clock_timestamp();
  perform voyage.ship_speed(x), public.ship_hold_capacity(x) from unnest(v_ids) x;
  insert into reads_0163 values (p_phase, 'speed+hold', coalesce(cardinality(v_ids), 0), round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
  v_t0 := clock_timestamp();
  perform world.ship_stats(x) from unnest(v_ids) x;
  insert into reads_0163 values (p_phase, 'ship_stats', coalesce(cardinality(v_ids), 0), round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
  v_t0 := clock_timestamp();
  perform world.ship_view(x) from unnest(v_ids) x;
  insert into reads_0163 values (p_phase, 'ship_view', coalesce(cardinality(v_ids), 0), round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
end $$;

-- ── 1. THE PRE-IMAGES ──────────────────────────────────────────────────────────────────────────
create temp table defs_before_0163 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('world.ship_stats(uuid)'), ('world.ship_budget(uuid)'), ('world.ship_racks(uuid, jsonb)'),
               ('world.ship_view(uuid)'), ('public.wear_units_for(uuid, uuid)'), ('public.made_only_in(text, uuid)'),
               ('public.client_rpc_entry_points()')) f(fn);

create temp table untouched_before_0163 on commit drop as
select f.fn, replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def
  from (values ('public.mount_fitting(uuid, text)'), ('public.unmount_fitting(uuid, text)'), ('cmd.do_fit(uuid, jsonb)'),
               ('cmd.do_unfit(uuid, jsonb)'), ('cmd.do_make(uuid, jsonb)'), ('world.workstation(uuid, uuid)'),
               ('voyage.settle(uuid, timestamp with time zone)')) f(fn);

create temp table live_items_0163 on commit drop as select code from public.item_kinds;
create temp table before_0163 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from public.item_kinds) as kinds,
       (select count(*) from public.skill_requirements) as requirements,
       (select count(*) from public.fitted_units where cardinality(perks) > 0) as perked_units,
       (select md5(string_agg(to_jsonb(c)::text, '|' order by c.code)) from public.item_kinds c) as kinds_hash,
       (select md5(string_agg(to_jsonb(c)::text, '|' order by c.item_code)) from public.item_profile c) as profile_hash,
       (select md5(string_agg(to_jsonb(c)::text, '|' order by c.item_code, c.stat)) from public.item_effects c) as effects_hash,
       (select md5(string_agg(to_jsonb(c)::text, '|' order by c.item_code)) from public.item_use c) as use_hash,
       (select md5(string_agg(to_jsonb(c)::text, '|' order by c.code)) from public.gear_racks c) as racks_hash;

-- the old bodies under pg_temp names (the dark comparisons run old against new in one statement); the old
-- ship_view composes the old stats, racks and budget
do $$
declare
  d     record;
  v_def text;
  v_new text;
begin
  for d in select * from defs_before_0163 where fn in ('world.ship_stats(uuid)', 'world.ship_budget(uuid)', 'world.ship_racks(uuid, jsonb)',
                                                       'world.ship_view(uuid)', 'public.wear_units_for(uuid, uuid)') loop
    v_new := 'CREATE OR REPLACE FUNCTION pg_temp.' || replace(split_part(d.fn, '(', 1), '.', '_') || '_b0163(';
    v_def := replace(d.def, 'CREATE OR REPLACE FUNCTION ' || split_part(d.fn, '(', 1) || '(', v_new);
    if pg_temp.occurs_0163(v_def, v_new) <> 1 then
      raise exception '0163 self-assert FAIL: could not rename the pre-image of %', d.fn;
    end if;
    if d.fn = 'world.ship_view(uuid)' then
      if pg_temp.occurs_0163(v_def, 'world.ship_stats(s.id)') <> 1 or pg_temp.occurs_0163(v_def, 'world.ship_racks(s.id, y.sl)') <> 1
         or pg_temp.occurs_0163(v_def, 'world.ship_budget(s.id)') <> 1 then
        raise exception '0163 self-assert FAIL: world.ship_view does not read ship_stats, ship_racks and ship_budget once each where expected';
      end if;
      v_def := replace(replace(replace(v_def, 'world.ship_stats(s.id)', 'pg_temp.world_ship_stats_b0163(s.id)'),
                               'world.ship_racks(s.id, y.sl)', 'pg_temp.world_ship_racks_b0163(s.id, y.sl)'),
                       'world.ship_budget(s.id)', 'pg_temp.world_ship_budget_b0163(s.id)');
    end if;
    execute v_def;
  end loop;
end $$;

select pg_temp.time_reads_0163('before');

-- ── 2. THE KNOB, THE RACK, THE CATALOGUE ───────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('perks_max_per_unit', '2'::jsonb,
   '0163 (S16, docs/SHIPS_AND_SKILLS.md §6.6): the most perks one mounted unit carries (a second needs Augmentation V). '
   'Read by public.augment_fitting_for.')
on conflict (key) do nothing;

insert into public.gear_racks (code, word, ord) values ('kit', 'Kits', 6) on conflict (code) do nothing;

create table if not exists public.perks (
  code     text primary key check (code ~ '^[A-Z_]+$'),
  word     text not null,
  racks    text[] not null,
  slot     text,                 -- only items of this TYPE word (Swift: canvas, 'rig')
  base     text,                 -- only items of this base type (Roomy: 'Hold Frames')
  mode     text not null check (mode in ('flat', 'unit_pct', 'wear', 'deck', 'hands')),
  stat     text,                 -- what a flat / unit_pct perk moves (a ship_stats stat)
  per_rank numeric not null check (per_rank > 0),
  kit      text,                 -- the kit it costs (null: any kit)
  ord      int not null unique
);
comment on table public.perks is
  '0163 (S16, §6.6): THE perks a mounted unit may be augmented with — chosen, never rolled. Ranks 1-3; a rank r '
  'costs r kits. Read by public.unit_perk_deltas / perk_wear_mult / perk_unit_cost / unit_perk_card and the '
  'augment core. data/gear.json `perks`, held by the world guard. Server-only.';
alter table public.perks enable row level security;
revoke all on table public.perks from public, anon, authenticated;

insert into public.perks (code, word, racks, slot, base, mode, stat, per_rank, kit, ord) values
  ('WEATHERLY', 'Weatherly', array['mid'], null, null, 'flat', 'handling', 3, 'sailmakers-kit', 1),
  ('SWIFT', 'Swift', array['mid'], 'rig', null, 'flat', 'speed', 0.05, 'sailmakers-kit', 2),
  ('PRECISE', 'Precise', array['high'], null, null, 'flat', 'accuracy', 3, 'gunsmiths-kit', 3),
  ('FAR_REACHING', 'Far-reaching', array['high'], null, null, 'flat', 'reach', 4, 'gunsmiths-kit', 4),
  ('HARD_HITTING', 'Hard-hitting', array['high'], null, null, 'unit_pct', 'attack', 5, 'gunsmiths-kit', 5),
  ('STOUT', 'Stout', array['low'], null, null, 'unit_pct', 'durability', 4, 'shipwrights-kit', 6),
  ('ROOMY', 'Roomy', array['low'], null, 'Hold Frames', 'flat', 'hold', 2, 'shipwrights-kit', 7),
  ('SEASONED', 'Seasoned', array['high', 'mid', 'low'], null, null, 'wear', null, 25, null, 8),
  ('LIGHT', 'Light', array['high', 'mid', 'low'], null, null, 'deck', null, 1, 'shipwrights-kit', 9),
  ('HANDY', 'Handy', array['high'], null, null, 'hands', null, 10, 'navigators-kit', 10)
on conflict (code) do nothing;

create table if not exists public.gear_set_bonuses (
  line_code text not null,
  pieces    int  not null check (pieces in (2, 4)),
  stat      text not null,         -- a ship_stats stat, or 'hands' (what fitted items need of Hands)
  pct       numeric,
  flat      numeric,
  primary key (line_code, pieces, stat),
  check ((pct is null) <> (flat is null))
);
comment on table public.gear_set_bonuses is
  '0163 (S16, §6.7): what a line''s set gives a hull that carries 2 of its pieces, and what 4 add (a per cent of '
  'the class base + what is mounted, or a flat amount; `hands` = what her fitted items need of Hands). Read by '
  'public.ship_set_bonus, ship_set_hands_pct and world.ship_set_card. data/gear.json `sets`. Server-only.';
alter table public.gear_set_bonuses enable row level security;
revoke all on table public.gear_set_bonuses from public, anon, authenticated;

insert into public.gear_set_bonuses (line_code, pieces, stat, pct, flat) values
  ('PRT', 2, 'hold', 3, null),
  ('PRT', 4, 'sighting', 5, null),
  ('PRT', 4, 'durability', 3, null),
  ('ESP', 2, 'armour', null, 5),
  ('ESP', 4, 'attack', 8, null),
  ('ESP', 4, 'durability', 5, null),
  ('NLD', 2, 'hold', 4, null),
  ('NLD', 4, 'hands', -10, null),
  ('NLD', 4, 'handling', null, 5),
  ('ENG', 2, 'accuracy', null, 5),
  ('ENG', 4, 'reach', null, 8),
  ('ENG', 4, 'speed', 2, null),
  ('FRA', 2, 'handling', null, 4),
  ('FRA', 4, 'reach', null, 6),
  ('FRA', 4, 'durability', 4, null),
  ('ITA', 2, 'attack', 5, null),
  ('ITA', 4, 'handling', null, 8),
  ('OTT', 2, 'armour', null, 5),
  ('OTT', 4, 'attack', 8, null),
  ('IND', 2, 'hold', 3, null),
  ('IND', 4, 'speed', 2, null),
  ('IND', 4, 'handling', null, 5),
  ('CHN', 2, 'durability', 5, null),
  ('CHN', 4, 'hold', 4, null),
  ('JPN', 2, 'accuracy', null, 5),
  ('JPN', 4, 'attack', 6, null),
  ('KOR', 2, 'armour', null, 6),
  ('KOR', 4, 'armour', null, 10),
  ('KOR', 4, 'accuracy', null, 4)
on conflict (line_code, pieces, stat) do nothing;

-- ── 3. THE 48 ITEMS (scripts/build-gear.mjs --sql-0163, verbatim) ───────────────────────────────
insert into public.item_kinds (code, name, slot, buys, spends, note, volume, ws_tier) values
  ('bombardas-de-caca', 'Bombardas de Caça', 'weapon', 'Reach, Accuracy, Attack', 'Cargo space', 'Bow and stern chasers of the India run, wadded with Portuguese cork: they reach further, aim truer and hit harder too.', 4, 2),
  ('gavea-da-carreira', 'Gávea da Carreira', 'lookout', 'Sighting, Speed', 'Handling', 'A high fighting top with a Portuguese portolan and compass in it: the lookout sees further and the ship finds the wind sooner.', 2, 2),
  ('lastro-de-sal', 'Lastro de Sal', 'hull', 'Handling, Armour, Cargo space', 'Speed', 'Setúbal salt packed over iron kentledge: a stiff, steady ship, and the salt sells at the far end, so it counts as a little cargo space.', 2, 2),
  ('armillary-figurehead', 'Armillary Sphere Figurehead', 'flourish', 'Crew morale, and fame', 'Nothing but ducats', 'An armillary sphere at the bow, the mark of the Portuguese crown. It moves no number; it completes the set.', 2, 2),
  ('armas-del-tercio', 'Armas del Tercio', 'weapon', 'Attack at close quarters, Armour', 'Reach', 'Toledo blades, pikes and breastplates for a boarding party of soldiers: a harder blow across the rail, and the breastplates count on deck too.', 3, 2),
  ('ancla-de-la-esperanza', 'Ancla de la Esperanza', 'ground-tackle', 'Hull in a storm, Handling, Armour', 'Cargo space', 'The great anchor of the treasure fleets, chained along an iron-bound side: the ship rides out the worst night and the chain plates stop a little shot.', 5, 2),
  ('tablazon-de-galeon', 'Tablazón de Galeón', 'hull', 'Armour, Hull, Sighting', 'Speed, Cargo space', 'Doubled live-oak planking carried up into high sides: far more hull and armour, a slower ship, and a lookout a little higher above the water.', 4, 2),
  ('castile-lion-figurehead', 'León de Castilla Figurehead', 'flourish', 'Crew morale, and fame', 'Nothing but ducats', 'A crowned lion of Castile in red and gold. It moves no number; it completes the set.', 2, 2),
  ('voc-swivels', 'VOC Draaibassen', 'weapon', 'Attack, Accuracy, Cargo space', 'Handling', 'Light rail guns of the Dutch East India Company with linen cartridges made up in advance: they sweep a deck and leave a little more cargo space than heavier metal would.', 2, 2),
  ('fluit-kaapstander', 'Fluit Kaapstander', 'ground-tackle', 'Handling, a little Speed, Hull', 'Cargo space', 'A geared capstan built for a small crew: the anchor and yards come up fast with few hands, and the ship meets a squall with sail already off.', 3, 2),
  ('voc-frames', 'VOC Frames', 'hull', 'Hold', 'Speed, Handling', 'Light fir frames and ceiling in the Dutch way: nearly the most cargo space a hull can give, at half the usual cost in speed.', 3, 2),
  ('holland-lion-figurehead', 'Leeuw van Holland Figurehead', 'flourish', 'Crew morale, and fame', 'Nothing but ducats', 'The lion of Holland in red and gold paint. It moves no number; it completes the set.', 2, 2),
  ('sea-dogs-culverins', 'Sea Dogs'' Culverin Battery', 'weapon', 'Attack, Reach, Accuracy', 'Hold, Handling', 'A full battery of English culverins on truck carriages: they hit hard, reach far and shoot straighter than any plain battery.', 6, 2),
  ('race-built-headsails', 'Race-built Headsails', 'rig', 'Handling, and a little Speed, Accuracy', 'Durability', 'Headsails cut for a race-built hull: the ship turns smartly, gains a little way, and keeps a steadier gun platform through the turn.', 3, 2),
  ('admiralty-copper', 'Admiralty Copper', 'hull', 'Armour, Durability, Handling', 'Speed', 'Copper sheathing to the Admiralty pattern over a clean bottom: more armour and hull, and a ship that answers the helm a little quicker.', 5, 2),
  ('sea-dog-figurehead', 'Sea Dog Figurehead', 'flourish', 'Crew morale, and fame', 'Nothing but ducats', 'A carved and painted sea dog at the bow. It moves no number; it completes the set.', 2, 2),
  ('sainte-barbe-du-ponant', 'Sainte-Barbe du Ponant', 'weapon', 'Attack sustain, Accuracy, Reach', 'Hold, Durability', 'A copper-lined powder room stocked with fine French powder: steadier and more accurate fire, and the charge carries a little further.', 4, 2),
  ('toiles-de-bretagne', 'Toiles de Bretagne', 'rig', 'Speed', 'Handling', 'Breton duck canvas cut full and flat: a great deal more speed from the same wind, and the suit costs only half the usual handling.', 4, 2),
  ('pompes-du-ponant', 'Pompes du Ponant', 'hull', 'Hull, Handling', 'Cargo space', 'Chain pumps with canvas hoses that keep the bilge dry: the hull takes far more punishment, and a dry ship answers the helm a little quicker.', 3, 2),
  ('fleur-de-lis-figurehead', 'Fleur-de-lis Figurehead', 'flourish', 'Crew morale, and fame', 'Nothing but ducats', 'A gilded fleur-de-lis on a blue ground. It moves no number; it completes the set.', 2, 2),
  ('petrieri', 'Petrieri dell''Arsenale', 'weapon', 'Attack at close range, Accuracy', 'Reach, Cargo space, Handling', 'Short brass stone-throwers of the Venetian Arsenal, bored true: they smash at close range and aim better than most short guns.', 5, 2),
  ('agghiaccio', 'Agghiaccio dell''Arsenale', 'steering', 'Handling, Speed', 'Cargo space', 'A long steering lever in the Venetian pattern: the ship answers the helm at once and wanders less, so it keeps a little more way on.', 2, 2),
  ('zavorra-dell-arsenale', 'Zavorra dell''Arsenale', 'hull', 'Handling, Armour, Attack', 'Speed', 'Lead and marble ballast trimmed by the Arsenal for a steady gun platform: a stiffer ship, and the bow guns tell harder.', 2, 2),
  ('san-marco-lion-figurehead', 'Leone di San Marco Figurehead', 'flourish', 'Crew morale, and fame', 'Nothing but ducats', 'The winged lion of St Mark in gilt, with glass eyes from Murano. It moves no number; it completes the set.', 2, 2),
  ('sahi-guns', 'Şahi Guns', 'weapon', 'Attack, Reach, Armour', 'Hold, Handling', 'Heavy bronze guns of the Tersane-i Amire behind stout bulwarks: a hard-hitting broadside, and the gun deck takes a little more shot.', 6, 2),
  ('tersane-anchor', 'Tersane Anchor & Cable', 'ground-tackle', 'Weather-holding, and a faster turnaround in port, Hull', 'Hold', 'Ground tackle from the Imperial Arsenal on a cedar-stocked anchor: the ship turns around quicker in port and rides easier at anchor, which spares the hull.', 4, 2),
  ('cedar-planking', 'Cedar Planking', 'hull', 'Armour, Hull, Handling', 'Speed, Cargo space', 'Doubled planking of Anatolian cedar, lighter than oak: far more hull and armour for a slower ship, and the lighter wood leaves it a little handier.', 4, 2),
  ('crescent-figurehead', 'Kapudan''s Crescent Figurehead', 'flourish', 'Crew morale, and fame', 'Nothing but ducats', 'A gilded crescent and star over Iznik tilework at the bow. It moves no number; it completes the set.', 2, 2),
  ('malabar-boarding-gear', 'Malabar Boarding Gear', 'weapon', 'Attack at close quarters, Handling', 'Reach', 'Talwars, coir grapnel lines and boarding ladders in the Malabar way: a hard blow across the rail from a light, handy ship.', 3, 2),
  ('rahmani-and-kamal', 'Rahmani & Kamal', 'lookout', 'Sighting, Handling, Speed', 'Cargo space', 'An Arab pilot book and a kamal for the star heights beside a lodestone compass: the ship knows where it is, answers the helm well and picks the better wind.', 2, 2),
  ('monsoon-teak-sheathing', 'Monsoon Teak Sheathing', 'hull', 'Armour, Durability, Cargo space', 'Speed', 'Teak and copper over coir caulking, sewn and nailed as the monsoon yards do it: more armour and hull, and the lighter build leaves a little more cargo space.', 5, 2),
  ('makara-figurehead', 'Monsoon Makara Figurehead', 'flourish', 'Crew morale, and fame', 'Nothing but ducats', 'A carved makara, the sea creature of the monsoon coasts, in sandalwood and red. It moves no number; it completes the set.', 2, 2),
  ('fire-lance-magazine', 'Fire-lance Magazine', 'weapon', 'Attack sustain, Accuracy, Armour', 'Hold, Durability', 'A powder room stocked with rockets and fire-lances behind a watertight bulkhead: steadier and more accurate fire, and the bulkhead counts as armour.', 4, 2),
  ('fenestrated-rudder', 'Fenestrated Rudder', 'steering', 'Handling, Hull', 'Hold', 'A deep junk rudder pierced with holes, raised and lowered on tackles: the ship turns sharply and the rudder shrugs off seas that would unship another.', 3, 2),
  ('treasure-junk-bulkheads', 'Treasure Junk Bulkheads', 'hull', 'Hold, Hull', 'Speed, Handling', 'Watertight bulkheads in the Ming way: the cargo stows in sealed compartments, so there is more room for it and one leak never sinks the ship.', 3, 2),
  ('dragon-eye-figurehead', 'Dragon-eye Figurehead', 'flourish', 'Crew morale, and fame', 'Nothing but ducats', 'Painted eyes on the bow in red lacquer, as every junk carries. It moves no number; it completes the set.', 2, 2),
  ('ozutsu-swivels', 'Ōzutsu Swivels', 'weapon', 'Attack, Accuracy, Reach', 'Handling', 'Heavy Japanese hand cannon on the rails, served by matchlock men: they sweep a deck, shoot straight and reach a little further than a plain swivel.', 2, 2),
  ('typhoon-canvas', 'Typhoon Canvas', 'rig', 'Hull, Handling, Accuracy', 'Speed', 'Small, heavy sails of cotton and sailcloth for typhoon weather: the ship rides out the storm, gives up a little speed and keeps a steadier gun platform.', 3, 2),
  ('red-seal-ballast', 'Red Seal Ballast', 'hull', 'Handling, Armour, Accuracy', 'Speed', 'Copper pigs from the Japanese mines stowed low as ballast: a stiff, steady ship, and the guns shoot straighter for it.', 2, 2),
  ('red-seal-figurehead', 'Red Seal Figurehead', 'flourish', 'Crew morale, and fame', 'Nothing but ducats', 'The red seal of the shogunate in lacquer and gold leaf at the bow. It moves no number; it completes the set.', 2, 2),
  ('cheonja-chongtong', 'Cheonja Chongtong', 'weapon', 'Reach, Accuracy, Attack', 'Cargo space', 'Heavy Korean bronze cannon in the bows that fire great arrows as well as shot: they reach and aim further than a broadside gun and hit harder than most chasers.', 4, 2),
  ('ramie-sails', 'Ramie Sails', 'rig', 'Speed, Hull', 'Handling', 'Battened sails of Korean ramie and hemp cloth: more speed from the same wind, harder to handle, and the cloth stands weather that tears flax.', 4, 2),
  ('turtle-back-plating', 'Turtle-back Plating', 'hull', 'Armour, Hull', 'Speed, Cargo space', 'Iron plates spiked over a timber deck in the turtle-ship way: the best armour afloat and a far stronger hull, for a slower ship with less cargo space.', 4, 2),
  ('dragon-head-figurehead', 'Dragon-head Figurehead', 'flourish', 'Crew morale, and fame', 'Nothing but ducats', 'The dragon head of the turtle ship, carved and painted red. It moves no number; it completes the set.', 2, 2),
  ('gunsmiths-kit', 'Gunsmith''s Kit', 'kit', 'Augments a fitting', 'Used up', 'A gunsmith''s tools and stores for augmenting a High-rack fitting at a tier-3 workshop; the kit is used up by it.', 1, 3),
  ('sailmakers-kit', 'Sailmaker''s Kit', 'kit', 'Augments a fitting', 'Used up', 'A sailmaker''s cloth, stays and twine for augmenting a Mid-rack fitting at a tier-3 workshop; the kit is used up by it.', 1, 3),
  ('shipwrights-kit', 'Shipwright''s Kit', 'kit', 'Augments a fitting', 'Used up', 'A shipwright''s blocks, copper and oakum for augmenting a Low-rack fitting at a tier-3 workshop; the kit is used up by it.', 1, 3),
  ('navigators-kit', 'Navigator''s Kit', 'kit', 'Augments a fitting', 'Used up', 'A navigator''s charts and lodestone for augmenting a fitting at a tier-3 workshop; the kit is used up by it.', 1, 3)
on conflict (code) do nothing;

insert into public.item_profile (item_code, base_type, rack, grade, meta, deck, hands, active) values
  ('bombardas-de-caca', 'Chase Guns', 'high', 4, 6, 5, 5, true),
  ('gavea-da-carreira', 'Lookout', 'mid', 4, 6, 1, 1, false),
  ('lastro-de-sal', 'Ballast', 'low', 4, 6, 3, 0, false),
  ('armillary-figurehead', 'Figurehead', 'flourish', 4, 6, 0, 0, false),
  ('armas-del-tercio', 'Boarding Gear', 'high', 4, 6, 3, 7, true),
  ('ancla-de-la-esperanza', 'Sheet Anchor', 'mid', 4, 6, 7, 4, true),
  ('tablazon-de-galeon', 'Planking', 'low', 4, 6, 5, 0, false),
  ('castile-lion-figurehead', 'Figurehead', 'flourish', 4, 6, 0, 0, false),
  ('voc-swivels', 'Swivel Guns', 'high', 4, 6, 3, 4, true),
  ('fluit-kaapstander', 'Capstan', 'mid', 4, 6, 4, 4, false),
  ('voc-frames', 'Hold Frames', 'low', 4, 6, 3, 0, false),
  ('holland-lion-figurehead', 'Figurehead', 'flourish', 4, 6, 0, 0, false),
  ('sea-dogs-culverins', 'Long Guns', 'high', 4, 6, 8, 10, true),
  ('race-built-headsails', 'Headsails', 'mid', 4, 6, 3, 3, false),
  ('admiralty-copper', 'Sheathing', 'low', 4, 6, 4, 0, false),
  ('sea-dog-figurehead', 'Figurehead', 'flourish', 4, 6, 0, 0, false),
  ('sainte-barbe-du-ponant', 'Powder Magazine', 'high', 4, 6, 4, 3, false),
  ('toiles-de-bretagne', 'Sails', 'mid', 4, 6, 4, 5, false),
  ('pompes-du-ponant', 'Bilge Pumps', 'low', 4, 6, 4, 5, true),
  ('fleur-de-lis-figurehead', 'Figurehead', 'flourish', 4, 6, 0, 0, false),
  ('petrieri', 'Carronades', 'high', 4, 6, 7, 9, true),
  ('agghiaccio', 'Whipstaff', 'mid', 4, 6, 3, 1, false),
  ('zavorra-dell-arsenale', 'Ballast', 'low', 4, 6, 3, 0, false),
  ('san-marco-lion-figurehead', 'Figurehead', 'flourish', 4, 6, 0, 0, false),
  ('sahi-guns', 'Long Guns', 'high', 4, 6, 8, 10, true),
  ('tersane-anchor', 'Anchor', 'mid', 4, 6, 4, 3, false),
  ('cedar-planking', 'Planking', 'low', 4, 6, 5, 0, false),
  ('crescent-figurehead', 'Figurehead', 'flourish', 4, 6, 0, 0, false),
  ('malabar-boarding-gear', 'Boarding Gear', 'high', 4, 6, 3, 7, true),
  ('rahmani-and-kamal', 'Binnacle & Charts', 'mid', 4, 6, 3, 1, false),
  ('monsoon-teak-sheathing', 'Sheathing', 'low', 4, 6, 4, 0, false),
  ('makara-figurehead', 'Figurehead', 'flourish', 4, 6, 0, 0, false),
  ('fire-lance-magazine', 'Powder Magazine', 'high', 4, 6, 4, 3, false),
  ('fenestrated-rudder', 'Rudder', 'mid', 4, 6, 3, 3, false),
  ('treasure-junk-bulkheads', 'Hold Frames', 'low', 4, 6, 3, 0, false),
  ('dragon-eye-figurehead', 'Figurehead', 'flourish', 4, 6, 0, 0, false),
  ('ozutsu-swivels', 'Swivel Guns', 'high', 4, 6, 3, 4, true),
  ('typhoon-canvas', 'Storm Canvas', 'mid', 4, 6, 4, 4, true),
  ('red-seal-ballast', 'Ballast', 'low', 4, 6, 3, 0, false),
  ('red-seal-figurehead', 'Figurehead', 'flourish', 4, 6, 0, 0, false),
  ('cheonja-chongtong', 'Chase Guns', 'high', 4, 6, 5, 5, true),
  ('ramie-sails', 'Sails', 'mid', 4, 6, 4, 5, false),
  ('turtle-back-plating', 'Planking', 'low', 4, 6, 5, 0, false),
  ('dragon-head-figurehead', 'Figurehead', 'flourish', 4, 6, 0, 0, false),
  ('gunsmiths-kit', 'Kit', 'kit', 1, 0, 0, 0, false),
  ('sailmakers-kit', 'Kit', 'kit', 1, 0, 0, 0, false),
  ('shipwrights-kit', 'Kit', 'kit', 1, 0, 0, 0, false),
  ('navigators-kit', 'Kit', 'kit', 1, 0, 0, 0, false)
on conflict (item_code) do nothing;

insert into public.item_effects (item_code, stat, delta) values
  ('bombardas-de-caca', 'reach', 48),
  ('bombardas-de-caca', 'accuracy', 24),
  ('bombardas-de-caca', 'hold', -8),
  ('bombardas-de-caca', 'attack', 20),
  ('gavea-da-carreira', 'sighting', 12),
  ('gavea-da-carreira', 'handling', -4),
  ('gavea-da-carreira', 'speed', 0.1),
  ('lastro-de-sal', 'handling', 19),
  ('lastro-de-sal', 'armour', 14),
  ('lastro-de-sal', 'speed', -0.4),
  ('lastro-de-sal', 'hold', 5),
  ('armas-del-tercio', 'attack', 84),
  ('armas-del-tercio', 'reach', -20),
  ('armas-del-tercio', 'armour', 4),
  ('ancla-de-la-esperanza', 'durability', 144),
  ('ancla-de-la-esperanza', 'handling', 5),
  ('ancla-de-la-esperanza', 'hold', -10),
  ('ancla-de-la-esperanza', 'armour', 4),
  ('tablazon-de-galeon', 'armour', 24),
  ('tablazon-de-galeon', 'durability', 384),
  ('tablazon-de-galeon', 'speed', -0.45),
  ('tablazon-de-galeon', 'hold', -12),
  ('tablazon-de-galeon', 'sighting', 2),
  ('voc-swivels', 'attack', 48),
  ('voc-swivels', 'accuracy', 19),
  ('voc-swivels', 'handling', -2),
  ('voc-swivels', 'hold', 5),
  ('fluit-kaapstander', 'handling', 14),
  ('fluit-kaapstander', 'speed', 0.17),
  ('fluit-kaapstander', 'hold', -5),
  ('fluit-kaapstander', 'durability', 40),
  ('voc-frames', 'hold', 43),
  ('voc-frames', 'speed', -0.18),
  ('voc-frames', 'handling', -5),
  ('sea-dogs-culverins', 'attack', 144),
  ('sea-dogs-culverins', 'reach', 36),
  ('sea-dogs-culverins', 'hold', -20),
  ('sea-dogs-culverins', 'handling', -6),
  ('sea-dogs-culverins', 'accuracy', 10),
  ('race-built-headsails', 'handling', 24),
  ('race-built-headsails', 'speed', 0.34),
  ('race-built-headsails', 'durability', -40),
  ('race-built-headsails', 'accuracy', 6),
  ('admiralty-copper', 'armour', 34),
  ('admiralty-copper', 'durability', 288),
  ('admiralty-copper', 'speed', -0.3),
  ('admiralty-copper', 'handling', 4),
  ('sainte-barbe-du-ponant', 'attack', 60),
  ('sainte-barbe-du-ponant', 'accuracy', 29),
  ('sainte-barbe-du-ponant', 'hold', -10),
  ('sainte-barbe-du-ponant', 'durability', -60),
  ('sainte-barbe-du-ponant', 'reach', 6),
  ('toiles-de-bretagne', 'speed', 1.02),
  ('toiles-de-bretagne', 'handling', -4),
  ('pompes-du-ponant', 'durability', 216),
  ('pompes-du-ponant', 'hold', -5),
  ('pompes-du-ponant', 'handling', 4),
  ('petrieri', 'attack', 216),
  ('petrieri', 'reach', -15),
  ('petrieri', 'hold', -14),
  ('petrieri', 'handling', -4),
  ('petrieri', 'accuracy', 6),
  ('agghiaccio', 'handling', 17),
  ('agghiaccio', 'hold', -2),
  ('agghiaccio', 'speed', 0.1),
  ('zavorra-dell-arsenale', 'handling', 19),
  ('zavorra-dell-arsenale', 'armour', 14),
  ('zavorra-dell-arsenale', 'speed', -0.4),
  ('zavorra-dell-arsenale', 'attack', 15),
  ('sahi-guns', 'attack', 144),
  ('sahi-guns', 'reach', 36),
  ('sahi-guns', 'hold', -20),
  ('sahi-guns', 'handling', -6),
  ('sahi-guns', 'armour', 4),
  ('tersane-anchor', 'handling', 10),
  ('tersane-anchor', 'hold', -8),
  ('tersane-anchor', 'durability', 40),
  ('cedar-planking', 'armour', 24),
  ('cedar-planking', 'durability', 384),
  ('cedar-planking', 'speed', -0.45),
  ('cedar-planking', 'hold', -12),
  ('cedar-planking', 'handling', 4),
  ('malabar-boarding-gear', 'attack', 84),
  ('malabar-boarding-gear', 'reach', -20),
  ('malabar-boarding-gear', 'handling', 4),
  ('rahmani-and-kamal', 'sighting', 7),
  ('rahmani-and-kamal', 'handling', 12),
  ('rahmani-and-kamal', 'hold', -3),
  ('rahmani-and-kamal', 'speed', 0.1),
  ('monsoon-teak-sheathing', 'armour', 34),
  ('monsoon-teak-sheathing', 'durability', 288),
  ('monsoon-teak-sheathing', 'speed', -0.3),
  ('monsoon-teak-sheathing', 'hold', 6),
  ('fire-lance-magazine', 'attack', 60),
  ('fire-lance-magazine', 'accuracy', 29),
  ('fire-lance-magazine', 'hold', -10),
  ('fire-lance-magazine', 'durability', -60),
  ('fire-lance-magazine', 'armour', 4),
  ('fenestrated-rudder', 'handling', 34),
  ('fenestrated-rudder', 'hold', -6),
  ('fenestrated-rudder', 'durability', 40),
  ('treasure-junk-bulkheads', 'hold', 43),
  ('treasure-junk-bulkheads', 'speed', -0.35),
  ('treasure-junk-bulkheads', 'handling', -5),
  ('treasure-junk-bulkheads', 'durability', 50),
  ('ozutsu-swivels', 'attack', 48),
  ('ozutsu-swivels', 'accuracy', 19),
  ('ozutsu-swivels', 'handling', -2),
  ('ozutsu-swivels', 'reach', 6),
  ('typhoon-canvas', 'durability', 120),
  ('typhoon-canvas', 'handling', 10),
  ('typhoon-canvas', 'speed', -0.25),
  ('typhoon-canvas', 'accuracy', 6),
  ('red-seal-ballast', 'handling', 19),
  ('red-seal-ballast', 'armour', 14),
  ('red-seal-ballast', 'speed', -0.4),
  ('red-seal-ballast', 'accuracy', 6),
  ('cheonja-chongtong', 'reach', 48),
  ('cheonja-chongtong', 'accuracy', 24),
  ('cheonja-chongtong', 'hold', -8),
  ('cheonja-chongtong', 'attack', 20),
  ('ramie-sails', 'speed', 1.02),
  ('ramie-sails', 'handling', -8),
  ('ramie-sails', 'durability', 40),
  ('turtle-back-plating', 'armour', 30),
  ('turtle-back-plating', 'durability', 384),
  ('turtle-back-plating', 'speed', -0.45),
  ('turtle-back-plating', 'hold', -12)
on conflict (item_code, stat) do nothing;

create temp table item_goods_0163 (item_code text, good_code text, qty numeric) on commit drop;
insert into item_goods_0163 values
  ('bombardas-de-caca', 'culverin', 6),
  ('bombardas-de-caca', 'swedish-iron', 6),
  ('bombardas-de-caca', 'shot-and-ball', 4),
  ('bombardas-de-caca', 'cork', 4),
  ('gavea-da-carreira', 'riga-mast', 3),
  ('gavea-da-carreira', 'portolan-charts', 2),
  ('gavea-da-carreira', 'lodestone', 1),
  ('gavea-da-carreira', 'cordage', 4),
  ('lastro-de-sal', 'salt', 20),
  ('lastro-de-sal', 'iron', 6),
  ('lastro-de-sal', 'timber', 2),
  ('armillary-figurehead', 'timber', 4),
  ('armillary-figurehead', 'armillary-spheres', 1),
  ('armillary-figurehead', 'gold', 1),
  ('armas-del-tercio', 'toledo-blades', 6),
  ('armas-del-tercio', 'swedish-iron', 4),
  ('armas-del-tercio', 'abaca', 4),
  ('armas-del-tercio', 'armour', 2),
  ('ancla-de-la-esperanza', 'swedish-iron', 8),
  ('ancla-de-la-esperanza', 'abaca', 8),
  ('ancla-de-la-esperanza', 'tar', 2),
  ('tablazon-de-galeon', 'live-oak', 16),
  ('tablazon-de-galeon', 'naval-timber', 6),
  ('tablazon-de-galeon', 'ships-nails', 8),
  ('tablazon-de-galeon', 'oakum', 4),
  ('tablazon-de-galeon', 'pine-pitch', 2),
  ('castile-lion-figurehead', 'timber', 4),
  ('castile-lion-figurehead', 'vermilion', 1),
  ('castile-lion-figurehead', 'gold', 1),
  ('voc-swivels', 'swedish-iron', 5),
  ('voc-swivels', 'brass-ingots', 3),
  ('voc-swivels', 'shot-and-ball', 2),
  ('voc-swivels', 'holland-linen', 2),
  ('fluit-kaapstander', 'live-oak', 4),
  ('fluit-kaapstander', 'swedish-iron', 3),
  ('fluit-kaapstander', 'abaca', 3),
  ('fluit-kaapstander', 'stockholm-tar', 1),
  ('voc-frames', 'memel-fir', 30),
  ('voc-frames', 'norway-spruce', 20),
  ('voc-frames', 'oakum', 6),
  ('holland-lion-figurehead', 'timber', 4),
  ('holland-lion-figurehead', 'ochre', 1),
  ('holland-lion-figurehead', 'lead', 1),
  ('sea-dogs-culverins', 'culverin', 14),
  ('sea-dogs-culverins', 'tin-ingots', 6),
  ('sea-dogs-culverins', 'oakum', 4),
  ('race-built-headsails', 'sailcloth', 8),
  ('race-built-headsails', 'riga-mast', 2),
  ('race-built-headsails', 'abaca', 4),
  ('race-built-headsails', 'tar', 1),
  ('admiralty-copper', 'copper-sheet', 14),
  ('admiralty-copper', 'tin-ingots', 4),
  ('admiralty-copper', 'ships-nails', 6),
  ('admiralty-copper', 'tar', 2),
  ('sea-dog-figurehead', 'timber', 4),
  ('sea-dog-figurehead', 'tallow', 1),
  ('sea-dog-figurehead', 'lead-white', 1),
  ('sainte-barbe-du-ponant', 'gunpowder', 10),
  ('sainte-barbe-du-ponant', 'live-oak', 4),
  ('sainte-barbe-du-ponant', 'copper-sheet', 4),
  ('sainte-barbe-du-ponant', 'lead', 2),
  ('toiles-de-bretagne', 'canvas-duck', 30),
  ('toiles-de-bretagne', 'sailcloth', 8),
  ('toiles-de-bretagne', 'hemp', 6),
  ('pompes-du-ponant', 'live-oak', 4),
  ('pompes-du-ponant', 'copper', 3),
  ('pompes-du-ponant', 'hides', 2),
  ('pompes-du-ponant', 'canvas-duck', 4),
  ('fleur-de-lis-figurehead', 'timber', 4),
  ('fleur-de-lis-figurehead', 'gold-thread', 1),
  ('fleur-de-lis-figurehead', 'ultramarine', 1),
  ('petrieri', 'culverin', 6),
  ('petrieri', 'brass-ingots', 6),
  ('petrieri', 'gunpowder', 3),
  ('petrieri', 'marble', 4),
  ('agghiaccio', 'live-oak', 4),
  ('agghiaccio', 'naval-timber', 1),
  ('agghiaccio', 'swedish-iron', 1),
  ('agghiaccio', 'hemp', 1),
  ('zavorra-dell-arsenale', 'lead', 8),
  ('zavorra-dell-arsenale', 'iron', 6),
  ('zavorra-dell-arsenale', 'marble', 4),
  ('zavorra-dell-arsenale', 'oakum', 2),
  ('san-marco-lion-figurehead', 'timber', 4),
  ('san-marco-lion-figurehead', 'gold', 1),
  ('san-marco-lion-figurehead', 'murano-glass', 1),
  ('sahi-guns', 'bombard', 2),
  ('sahi-guns', 'culverin', 8),
  ('sahi-guns', 'copper', 8),
  ('sahi-guns', 'tin-ingots', 4),
  ('tersane-anchor', 'swedish-iron', 5),
  ('tersane-anchor', 'abaca', 5),
  ('tersane-anchor', 'hemp', 3),
  ('tersane-anchor', 'cedar', 2),
  ('cedar-planking', 'cedar', 16),
  ('cedar-planking', 'naval-timber', 4),
  ('cedar-planking', 'ships-nails', 8),
  ('cedar-planking', 'oakum', 4),
  ('crescent-figurehead', 'cedar', 4),
  ('crescent-figurehead', 'gold-thread', 1),
  ('crescent-figurehead', 'iznik-tiles', 1),
  ('malabar-boarding-gear', 'talwar', 4),
  ('malabar-boarding-gear', 'swedish-iron', 3),
  ('malabar-boarding-gear', 'coir', 4),
  ('malabar-boarding-gear', 'teak', 2),
  ('rahmani-and-kamal', 'lodestone', 2),
  ('rahmani-and-kamal', 'sea-charts', 3),
  ('rahmani-and-kamal', 'teak', 2),
  ('rahmani-and-kamal', 'brass-ingots', 1),
  ('monsoon-teak-sheathing', 'teak', 10),
  ('monsoon-teak-sheathing', 'copper-sheet', 8),
  ('monsoon-teak-sheathing', 'coir', 6),
  ('monsoon-teak-sheathing', 'coco-fibre', 4),
  ('makara-figurehead', 'teak', 4),
  ('makara-figurehead', 'sandalwood-carving', 1),
  ('makara-figurehead', 'vermilion', 1),
  ('fire-lance-magazine', 'gunpowder', 10),
  ('fire-lance-magazine', 'rocket-tubes', 4),
  ('fire-lance-magazine', 'fire-lance', 4),
  ('fire-lance-magazine', 'copper-sheet', 4),
  ('fenestrated-rudder', 'live-oak', 6),
  ('fenestrated-rudder', 'teak', 2),
  ('fenestrated-rudder', 'iron', 4),
  ('fenestrated-rudder', 'abaca', 2),
  ('treasure-junk-bulkheads', 'live-oak', 14),
  ('treasure-junk-bulkheads', 'teak', 6),
  ('treasure-junk-bulkheads', 'iron', 6),
  ('treasure-junk-bulkheads', 'oakum', 6),
  ('dragon-eye-figurehead', 'timber', 4),
  ('dragon-eye-figurehead', 'lacquerware', 1),
  ('dragon-eye-figurehead', 'vermilion', 1),
  ('ozutsu-swivels', 'swedish-iron', 4),
  ('ozutsu-swivels', 'culverin', 2),
  ('ozutsu-swivels', 'matchlocks', 2),
  ('ozutsu-swivels', 'shot-and-ball', 2),
  ('typhoon-canvas', 'sailcloth', 8),
  ('typhoon-canvas', 'cotton-cloth', 6),
  ('typhoon-canvas', 'hemp', 4),
  ('typhoon-canvas', 'tar', 2),
  ('red-seal-ballast', 'japan-copper', 8),
  ('red-seal-ballast', 'iron', 4),
  ('red-seal-ballast', 'timber', 2),
  ('red-seal-figurehead', 'timber', 4),
  ('red-seal-figurehead', 'lacquerware', 1),
  ('red-seal-figurehead', 'gold', 1),
  ('cheonja-chongtong', 'culverin', 8),
  ('cheonja-chongtong', 'copper', 6),
  ('cheonja-chongtong', 'tin-ingots', 4),
  ('cheonja-chongtong', 'rocket-tubes', 2),
  ('ramie-sails', 'ramie-korea', 20),
  ('ramie-sails', 'hemp-cloth', 8),
  ('ramie-sails', 'cordage', 4),
  ('turtle-back-plating', 'iron', 20),
  ('turtle-back-plating', 'copper-sheet', 10),
  ('turtle-back-plating', 'timber', 10),
  ('dragon-head-figurehead', 'timber', 4),
  ('dragon-head-figurehead', 'iron', 2),
  ('dragon-head-figurehead', 'vermilion', 1),
  ('gunsmiths-kit', 'swivel-gun', 1),
  ('gunsmiths-kit', 'slow-match', 2),
  ('gunsmiths-kit', 'gunpowder', 2),
  ('sailmakers-kit', 'sailcloth', 4),
  ('sailmakers-kit', 'whale-bone-stays', 2),
  ('sailmakers-kit', 'abaca', 3),
  ('shipwrights-kit', 'lignum-vitae', 2),
  ('shipwrights-kit', 'copper-sheet', 3),
  ('shipwrights-kit', 'oakum', 3),
  ('navigators-kit', 'sea-charts', 1),
  ('navigators-kit', 'lodestone', 1);
insert into public.item_recipes (item_code, good_id, qty)
select w.item_code, g.id, w.qty from item_goods_0163 w join public.goods g on g.code = w.good_code
on conflict (item_code, good_id) do nothing;

insert into public.skill_requirements (subject_kind, subject_code, skill_code, level) values
  ('item', 'bombardas-de-caca', 'GUNNERY', 4),
  ('item', 'bombardas-de-caca', 'PRT_MEDIUM', 1),
  ('item', 'bombardas-de-caca', 'LONG_GUNS', 1),
  ('item', 'gavea-da-carreira', 'LOOKOUTS', 4),
  ('item', 'gavea-da-carreira', 'PRT_MEDIUM', 1),
  ('item', 'lastro-de-sal', 'SHIPWRIGHT', 4),
  ('item', 'lastro-de-sal', 'PRT_MEDIUM', 1),
  ('item', 'armillary-figurehead', 'PRT_MEDIUM', 1),
  ('item', 'armas-del-tercio', 'BOARDING', 4),
  ('item', 'armas-del-tercio', 'ESP_MEDIUM', 1),
  ('item', 'ancla-de-la-esperanza', 'SEAMANSHIP', 4),
  ('item', 'ancla-de-la-esperanza', 'ESP_MEDIUM', 1),
  ('item', 'tablazon-de-galeon', 'SHIPWRIGHT', 4),
  ('item', 'tablazon-de-galeon', 'ESP_MEDIUM', 1),
  ('item', 'castile-lion-figurehead', 'ESP_MEDIUM', 1),
  ('item', 'voc-swivels', 'GUNNERY', 4),
  ('item', 'voc-swivels', 'NLD_MEDIUM', 1),
  ('item', 'fluit-kaapstander', 'SEAMANSHIP', 4),
  ('item', 'fluit-kaapstander', 'NLD_MEDIUM', 1),
  ('item', 'voc-frames', 'CARGO_STOWAGE', 4),
  ('item', 'voc-frames', 'NLD_MEDIUM', 1),
  ('item', 'holland-lion-figurehead', 'NLD_MEDIUM', 1),
  ('item', 'sea-dogs-culverins', 'GUNNERY', 4),
  ('item', 'sea-dogs-culverins', 'ENG_MEDIUM', 1),
  ('item', 'race-built-headsails', 'RIGGING', 4),
  ('item', 'race-built-headsails', 'ENG_MEDIUM', 1),
  ('item', 'admiralty-copper', 'SHIPWRIGHT', 4),
  ('item', 'admiralty-copper', 'ENG_MEDIUM', 1),
  ('item', 'sea-dog-figurehead', 'ENG_MEDIUM', 1),
  ('item', 'sainte-barbe-du-ponant', 'GUNNERY', 4),
  ('item', 'sainte-barbe-du-ponant', 'FRA_MEDIUM', 1),
  ('item', 'toiles-de-bretagne', 'RIGGING', 4),
  ('item', 'toiles-de-bretagne', 'FRA_MEDIUM', 1),
  ('item', 'pompes-du-ponant', 'SHIPWRIGHT', 4),
  ('item', 'pompes-du-ponant', 'FRA_MEDIUM', 1),
  ('item', 'fleur-de-lis-figurehead', 'FRA_MEDIUM', 1),
  ('item', 'petrieri', 'GUNNERY', 4),
  ('item', 'petrieri', 'ITA_MEDIUM', 1),
  ('item', 'petrieri', 'SHORT_GUNS', 1),
  ('item', 'agghiaccio', 'SEAMANSHIP', 4),
  ('item', 'agghiaccio', 'ITA_MEDIUM', 1),
  ('item', 'zavorra-dell-arsenale', 'SHIPWRIGHT', 4),
  ('item', 'zavorra-dell-arsenale', 'ITA_MEDIUM', 1),
  ('item', 'san-marco-lion-figurehead', 'ITA_MEDIUM', 1),
  ('item', 'sahi-guns', 'GUNNERY', 4),
  ('item', 'sahi-guns', 'OTT_MEDIUM', 1),
  ('item', 'tersane-anchor', 'SEAMANSHIP', 4),
  ('item', 'tersane-anchor', 'OTT_MEDIUM', 1),
  ('item', 'cedar-planking', 'SHIPWRIGHT', 4),
  ('item', 'cedar-planking', 'OTT_MEDIUM', 1),
  ('item', 'crescent-figurehead', 'OTT_MEDIUM', 1),
  ('item', 'malabar-boarding-gear', 'BOARDING', 4),
  ('item', 'malabar-boarding-gear', 'IND_MEDIUM', 1),
  ('item', 'rahmani-and-kamal', 'INSTRUMENTS', 4),
  ('item', 'rahmani-and-kamal', 'IND_MEDIUM', 1),
  ('item', 'monsoon-teak-sheathing', 'SHIPWRIGHT', 4),
  ('item', 'monsoon-teak-sheathing', 'IND_MEDIUM', 1),
  ('item', 'makara-figurehead', 'IND_MEDIUM', 1),
  ('item', 'fire-lance-magazine', 'GUNNERY', 4),
  ('item', 'fire-lance-magazine', 'CHN_MEDIUM', 1),
  ('item', 'fenestrated-rudder', 'SEAMANSHIP', 4),
  ('item', 'fenestrated-rudder', 'CHN_MEDIUM', 1),
  ('item', 'treasure-junk-bulkheads', 'CARGO_STOWAGE', 4),
  ('item', 'treasure-junk-bulkheads', 'CHN_MEDIUM', 1),
  ('item', 'dragon-eye-figurehead', 'CHN_MEDIUM', 1),
  ('item', 'ozutsu-swivels', 'GUNNERY', 4),
  ('item', 'ozutsu-swivels', 'JPN_MEDIUM', 1),
  ('item', 'typhoon-canvas', 'RIGGING', 4),
  ('item', 'typhoon-canvas', 'JPN_MEDIUM', 1),
  ('item', 'red-seal-ballast', 'SHIPWRIGHT', 4),
  ('item', 'red-seal-ballast', 'JPN_MEDIUM', 1),
  ('item', 'red-seal-figurehead', 'JPN_MEDIUM', 1),
  ('item', 'cheonja-chongtong', 'GUNNERY', 4),
  ('item', 'cheonja-chongtong', 'KOR_MEDIUM', 1),
  ('item', 'cheonja-chongtong', 'LONG_GUNS', 1),
  ('item', 'ramie-sails', 'RIGGING', 4),
  ('item', 'ramie-sails', 'KOR_MEDIUM', 1),
  ('item', 'turtle-back-plating', 'SHIPWRIGHT', 4),
  ('item', 'turtle-back-plating', 'KOR_MEDIUM', 1),
  ('item', 'dragon-head-figurehead', 'KOR_MEDIUM', 1)
on conflict (subject_kind, subject_code, skill_code) do nothing;

insert into public.item_use (item_code, trigger, consumes) values
  ('admiralty-copper', 'STORM', '[]'),
  ('agghiaccio', 'STORM', '[]'),
  ('ancla-de-la-esperanza', 'STORM', '[]'),
  ('armas-del-tercio', 'PIRATES', '[]'),
  ('armillary-figurehead', null, '[]'),
  ('bombardas-de-caca', 'PIRATES', '[{"good":"shot-and-ball","qty":1},{"good":"gunpowder","qty":1}]'),
  ('castile-lion-figurehead', null, '[]'),
  ('cedar-planking', 'STORM', '[]'),
  ('cheonja-chongtong', 'PIRATES', '[{"good":"shot-and-ball","qty":1},{"good":"gunpowder","qty":1}]'),
  ('crescent-figurehead', null, '[]'),
  ('dragon-eye-figurehead', null, '[]'),
  ('dragon-head-figurehead', null, '[]'),
  ('fenestrated-rudder', 'STORM', '[]'),
  ('fire-lance-magazine', 'PIRATES', '[]'),
  ('fleur-de-lis-figurehead', null, '[]'),
  ('fluit-kaapstander', 'STORM', '[]'),
  ('gavea-da-carreira', 'MILES', '[]'),
  ('gunsmiths-kit', null, '[]'),
  ('holland-lion-figurehead', null, '[]'),
  ('lastro-de-sal', 'STORM', '[]'),
  ('makara-figurehead', null, '[]'),
  ('malabar-boarding-gear', 'PIRATES', '[]'),
  ('monsoon-teak-sheathing', 'STORM', '[]'),
  ('navigators-kit', null, '[]'),
  ('ozutsu-swivels', 'PIRATES', '[{"good":"shot-and-ball","qty":1},{"good":"gunpowder","qty":1}]'),
  ('petrieri', 'PIRATES', '[{"good":"shot-and-ball","qty":1},{"good":"gunpowder","qty":1}]'),
  ('pompes-du-ponant', 'STORM', '[]'),
  ('race-built-headsails', 'MILES', '[]'),
  ('rahmani-and-kamal', 'MILES', '[]'),
  ('ramie-sails', 'MILES', '[]'),
  ('red-seal-ballast', 'STORM', '[]'),
  ('red-seal-figurehead', null, '[]'),
  ('sahi-guns', 'PIRATES', '[{"good":"shot-and-ball","qty":1},{"good":"gunpowder","qty":1}]'),
  ('sailmakers-kit', null, '[]'),
  ('sainte-barbe-du-ponant', 'PIRATES', '[]'),
  ('san-marco-lion-figurehead', null, '[]'),
  ('sea-dog-figurehead', null, '[]'),
  ('sea-dogs-culverins', 'PIRATES', '[{"good":"shot-and-ball","qty":1},{"good":"gunpowder","qty":1}]'),
  ('shipwrights-kit', null, '[]'),
  ('tablazon-de-galeon', 'STORM', '[]'),
  ('tersane-anchor', 'STORM', '[]'),
  ('toiles-de-bretagne', 'MILES', '[]'),
  ('treasure-junk-bulkheads', 'STORM', '[]'),
  ('turtle-back-plating', 'STORM', '[]'),
  ('typhoon-canvas', 'STORM', '[]'),
  ('voc-frames', 'STORM', '[]'),
  ('voc-swivels', 'PIRATES', '[{"good":"shot-and-ball","qty":1},{"good":"gunpowder","qty":1}]'),
  ('zavorra-dell-arsenale', 'STORM', '[]')
on conflict (item_code) do nothing;

create table if not exists public.item_line (
  item_code text primary key,
  line_code text not null
);
comment on table public.item_line is
  '0163 (S16, §6.2 / §6.7): a COUNTRY item''s line — the one home of both facts: it is a piece of that line''s '
  'set (public.ship_set_bonus) and it is made only where that line''s ships are built (public.made_only_in: a '
  'port of one of ship_lines.builder_nations). data: scripts/build-gear.mjs COUNTRY. Server-only.';
alter table public.item_line enable row level security;
revoke all on table public.item_line from public, anon, authenticated;
insert into public.item_line (item_code, line_code) values
  ('bombardas-de-caca', 'PRT'),
  ('gavea-da-carreira', 'PRT'),
  ('lastro-de-sal', 'PRT'),
  ('armillary-figurehead', 'PRT'),
  ('armas-del-tercio', 'ESP'),
  ('ancla-de-la-esperanza', 'ESP'),
  ('tablazon-de-galeon', 'ESP'),
  ('castile-lion-figurehead', 'ESP'),
  ('voc-swivels', 'NLD'),
  ('fluit-kaapstander', 'NLD'),
  ('voc-frames', 'NLD'),
  ('holland-lion-figurehead', 'NLD'),
  ('sea-dogs-culverins', 'ENG'),
  ('race-built-headsails', 'ENG'),
  ('admiralty-copper', 'ENG'),
  ('sea-dog-figurehead', 'ENG'),
  ('sainte-barbe-du-ponant', 'FRA'),
  ('toiles-de-bretagne', 'FRA'),
  ('pompes-du-ponant', 'FRA'),
  ('fleur-de-lis-figurehead', 'FRA'),
  ('petrieri', 'ITA'),
  ('agghiaccio', 'ITA'),
  ('zavorra-dell-arsenale', 'ITA'),
  ('san-marco-lion-figurehead', 'ITA'),
  ('sahi-guns', 'OTT'),
  ('tersane-anchor', 'OTT'),
  ('cedar-planking', 'OTT'),
  ('crescent-figurehead', 'OTT'),
  ('malabar-boarding-gear', 'IND'),
  ('rahmani-and-kamal', 'IND'),
  ('monsoon-teak-sheathing', 'IND'),
  ('makara-figurehead', 'IND'),
  ('fire-lance-magazine', 'CHN'),
  ('fenestrated-rudder', 'CHN'),
  ('treasure-junk-bulkheads', 'CHN'),
  ('dragon-eye-figurehead', 'CHN'),
  ('ozutsu-swivels', 'JPN'),
  ('typhoon-canvas', 'JPN'),
  ('red-seal-ballast', 'JPN'),
  ('red-seal-figurehead', 'JPN'),
  ('cheonja-chongtong', 'KOR'),
  ('ramie-sails', 'KOR'),
  ('turtle-back-plating', 'KOR'),
  ('dragon-head-figurehead', 'KOR')
on conflict (item_code) do nothing;

-- ── 4. THE READINGS ────────────────────────────────────────────────────────────────────────────
create or replace function public.perk_ranks(p_perks text[])
returns table (code text, rank int)
language sql
immutable
as $$
  -- 0163 (S16): A UNIT'S PERKS, as (code, rank) — the row carries 'CODE:RANK' (≤ 2, 0132's check).
  select split_part(x, ':', 1), split_part(x, ':', 2)::int from unnest(coalesce(p_perks, '{}')) x
$$;
revoke all on function public.perk_ranks(text[]) from public, anon, authenticated;

create or replace function public.unit_perk_deltas(p_item text, p_perks text[])
returns table (stat text, delta numeric)
language plpgsql
stable
set search_path = public, pg_temp
as $$
begin
  -- 0163 (S16, §6.6): WHAT ONE UNIT'S PERKS ADD TO HER SHIP — a flat perk its per-rank × rank on its stat
  -- (Swift +0.05 knots a rank); a unit_pct perk that per cent × rank of the unit's OWN figure of the stat
  -- (Hard-hitting: +5 % a rank of what this unit adds to attack). Wear, Deck and Hands perks add no stat.
  -- Read by world.ship_stats (both branches), only for a unit that has perks.
  return query
  select pk.stat,
         case pk.mode when 'flat' then pk.per_rank * r.rank
              else round(coalesce((select e.delta from public.item_effects e where e.item_code = p_item and e.stat = pk.stat), 0)
                         * pk.per_rank * r.rank / 100, 2) end
    from public.perk_ranks(p_perks) r join public.perks pk on pk.code = r.code
   where pk.mode in ('flat', 'unit_pct');
end $$;
revoke all on function public.unit_perk_deltas(text, text[]) from public, anon, authenticated;

create or replace function public.perk_wear_mult(p_perks text[])
returns numeric
language plpgsql
stable
set search_path = public, pg_temp
as $$
begin
  -- 0163 (S16, §6.6): SEASONED — the wear a passage brings this unit × (1 − 0.25 × rank): 0.75 / 0.50 / 0.25.
  -- 1 for a unit without it. Read by public.wear_units_for (the one writer of wear).
  return coalesce((select greatest(0, 1 - pk.per_rank * r.rank / 100)
                     from public.perk_ranks(p_perks) r join public.perks pk on pk.code = r.code
                    where pk.mode = 'wear' limit 1), 1);
end $$;
revoke all on function public.perk_wear_mult(text[]) from public, anon, authenticated;

create or replace function public.perk_unit_cost(p_cost int, p_kind text, p_perks text[])
returns int
language plpgsql
stable
set search_path = public, pg_temp
as $$
declare
  v_r int;
begin
  -- 0163 (S16, §6.6): WHAT ONE UNIT NEEDS OF A BUDGET UNDER ITS PERKS — Light: Deck − rank (never below 1;
  -- a piece that needs none still needs none); Handy: Hands − 10 % a rank, rounded. The cost itself for a
  -- unit without them. Read by world.ship_budget (what is mounted).
  select r.rank into v_r from public.perk_ranks(p_perks) r join public.perks pk on pk.code = r.code
   where pk.mode = p_kind limit 1;
  if v_r is null or coalesce(p_cost, 0) = 0 then
    return p_cost;
  end if;
  if p_kind = 'deck' then
    return greatest(1, p_cost - (select pk.per_rank from public.perks pk where pk.mode = 'deck' limit 1)::int * v_r);
  end if;
  return round(p_cost * (100 - (select pk.per_rank from public.perks pk where pk.mode = 'hands' limit 1) * v_r) / 100.0)::int;
end $$;
revoke all on function public.perk_unit_cost(int, text, text[]) from public, anon, authenticated;

create or replace function public.ship_set_pieces(p_ship uuid)
returns table (line_code text, pieces int)
language plpgsql
stable
set search_path = public, pg_temp
as $$
begin
  -- 0163 (S16, §6.7): A HULL'S SET PIECES — for each line, how many of its four pieces she carries (distinct
  -- racks of that line's Country units: High, Mid, Low, Flourish). The one count every set reading uses.
  return query
  select il.line_code, count(distinct ip.rack)::int
    from public.fitted_units fu
    join public.item_line il on il.item_code = fu.item_code
    join public.item_profile ip on ip.item_code = fu.item_code
   where fu.ship_id = p_ship
   group by il.line_code;
end $$;
revoke all on function public.ship_set_pieces(uuid) from public, anon, authenticated;

create or replace function public.ship_set_bonus(p_ship uuid)
returns table (stat text, delta numeric)
language plpgsql
stable
set search_path = public, pg_temp
as $$
begin
  -- 0163 (S16, §6.7): WHAT HER SETS GIVE HER STATS — every bonus of a line whose pieces she carries (2, and 4),
  -- as a flat delta; a per cent is of the class base + what is mounted (the pristine unit deltas), rounded
  -- to the stat's scale (speed 0.01, every other stat whole). Nothing for a hull with no set piece — every
  -- merchant, and every hull today — which leaves at the first, indexed read. Read by world.ship_stats.
  if not exists (select 1 from public.fitted_units fu join public.item_line il on il.item_code = fu.item_code
                  where fu.ship_id = p_ship) then
    return;
  end if;
  return query
  with base as (
    select v.stat, v.base + coalesce((select sum(e.delta) from public.fitted_units fu join public.item_effects e on e.item_code = fu.item_code
                                       where fu.ship_id = p_ship and e.stat = v.stat), 0) as total
      from public.ships s join public.ship_classes c on c.id = s.class_id
     cross join lateral (values ('hold', c.hold::numeric), ('speed', c.speed_kn::numeric), ('handling', c.handling::numeric),
                                ('durability', c.durability::numeric), ('armour', c.armour::numeric), ('attack', c.attack::numeric),
                                ('accuracy', c.accuracy::numeric), ('reach', c.reach::numeric), ('sighting', c.sighting::numeric)) v(stat, base)
     where s.id = p_ship)
  select gb.stat,
         case when gb.flat is not null then gb.flat
              else round(coalesce(b.total, 0) * gb.pct / 100, case when gb.stat = 'speed' then 2 else 0 end) end
    from public.ship_set_pieces(p_ship) sp
    join public.gear_set_bonuses gb on gb.line_code = sp.line_code and gb.pieces <= sp.pieces
    left join base b on b.stat = gb.stat
   where gb.stat <> 'hands';
end $$;
revoke all on function public.ship_set_bonus(uuid) from public, anon, authenticated;

create or replace function public.ship_set_hands_pct(p_ship uuid)
returns numeric
language plpgsql
stable
set search_path = public, pg_temp
as $$
begin
  -- 0163 (S16, §6.7): WHAT HER SETS TAKE OFF WHAT HER FITTINGS NEED OF HANDS (the VOC set's four pieces:
  -- −10 %). 0 for a hull with no set piece, at the first, indexed read. Read by world.ship_budget.
  if not exists (select 1 from public.fitted_units fu join public.item_line il on il.item_code = fu.item_code
                  where fu.ship_id = p_ship) then
    return 0;
  end if;
  return coalesce((select sum(gb.pct) from public.ship_set_pieces(p_ship) sp
                     join public.gear_set_bonuses gb on gb.line_code = sp.line_code and gb.pieces <= sp.pieces
                    where gb.stat = 'hands'), 0);
end $$;
revoke all on function public.ship_set_hands_pct(uuid) from public, anon, authenticated;

create or replace function public.stat_words(p_stat text, p_amount numeric, p_pct boolean)
returns text
language sql
immutable
as $$
  -- 0163 (S16): one bonus in the panel's words — "+3% cargo space", "+0.05 knots", "+5 armour", "−10% hands".
  select case when p_amount >= 0 then '+' else '−' end
         || case when p_pct then trim(to_char(abs(p_amount), 'FM999990.##')) || '% '
                 when p_stat = 'speed' then trim(to_char(abs(p_amount), 'FM999990.00')) || ' '
                 else trim(to_char(abs(p_amount), 'FM999990.##')) || ' ' end
         || case p_stat when 'hold' then case when p_pct then 'cargo space' else 'tons' end
                        when 'speed' then case when p_pct then 'speed' else 'knots' end
                        when 'durability' then 'hull' when 'hands' then 'hands' when 'deck' then 'deck'
                        else p_stat end
$$;
revoke all on function public.stat_words(text, numeric, boolean) from public, anon, authenticated;

create or replace function world.ship_set_card(p_ship uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  -- 0163 (S16, §6.7): THE SHIP PANEL'S SET PROGRESS — for each line whose pieces she carries: the set's name,
  -- pieces / 4, and each bonus with whether it is in force, in the server's words. '{}' for a hull with no set
  -- piece (so every ship view today is its pre-image). Read by world.ship_view.
  if not exists (select 1 from public.fitted_units fu join public.item_line il on il.item_code = fu.item_code
                  where fu.ship_id = p_ship) then
    return '{}'::jsonb;
  end if;
  return jsonb_build_object('sets', (select coalesce(jsonb_agg(jsonb_build_object(
           'line', sp.line_code, 'name', (select x.set_name from public.gear_set_names x where x.line_code = sp.line_code),
           'pieces', sp.pieces, 'of', 4,
           'bonuses', (select jsonb_agg(jsonb_build_object('pieces', gb.pieces, 'in_force', gb.pieces <= sp.pieces,
                                                           'words', public.stat_words(gb.stat, coalesce(gb.pct, gb.flat), gb.pct is not null)
                                                                    || case when gb.stat = 'hands' then ' needed' else '' end)
                                       order by gb.pieces, gb.stat)
                         from public.gear_set_bonuses gb where gb.line_code = sp.line_code))
           order by sp.line_code), '[]'::jsonb)
         from public.ship_set_pieces(p_ship) sp));
end $$;
revoke all on function world.ship_set_card(uuid) from public, anon, authenticated;

create table if not exists public.gear_set_names (
  line_code text primary key,
  set_name  text not null
);
comment on table public.gear_set_names is
  '0163 (S16, §6.7): the name of each line''s set (Carreira da Índia, Sea Dogs …). data/gear.json `sets`. Server-only.';
alter table public.gear_set_names enable row level security;
revoke all on table public.gear_set_names from public, anon, authenticated;
insert into public.gear_set_names (line_code, set_name) values
  ('PRT', 'Carreira da Índia'),
  ('ESP', 'Flota de Indias'),
  ('NLD', 'VOC Return Fleet'),
  ('ENG', 'Sea Dogs'),
  ('FRA', 'Ponant'),
  ('ITA', 'Arsenale'),
  ('OTT', 'Kapudan'),
  ('IND', 'Monsoon'),
  ('CHN', 'Ming Treasure'),
  ('JPN', 'Red Seal'),
  ('KOR', 'Yi Sun-sin')
on conflict (line_code) do nothing;

create or replace function public.unit_augmentable(p_item text)
returns boolean
language sql
stable
as $$
  -- 0163 (S16, §6.6): a unit of grade ≥ 3, or T2 / Country / Famous (meta ≥ 5), in a rack a perk can reach.
  select coalesce((select (ip.grade >= 3 or ip.meta >= 5) and ip.rack in ('high', 'mid', 'low')
                     from public.item_profile ip where ip.item_code = p_item), false)
$$;
revoke all on function public.unit_augmentable(text) from public, anon, authenticated;

create or replace function public.perk_fits(p_perk text, p_item text)
returns boolean
language sql
stable
as $$
  -- 0163 (S16, §6.6): THE ONE RULE OF WHERE A PERK MAY SIT — its racks, and (Swift / Roomy) the item's type or base.
  select coalesce((select ip.rack = any(pk.racks)
                          and (pk.slot is null or pk.slot = ik.slot)
                          and (pk.base is null or pk.base = ip.base_type)
                     from public.perks pk, public.item_profile ip join public.item_kinds ik on ik.code = ip.item_code
                    where pk.code = p_perk and ip.item_code = p_item), false)
$$;
revoke all on function public.perk_fits(text, text) from public, anon, authenticated;

create or replace function public.perk_rank_words(p_perk text, p_rank int)
returns text
language sql
stable
as $$
  -- 0163 (S16): one perk at one rank in the server's words — "Swift II · +0.10 knots".
  select pk.word || ' ' || public.skill_level_word(p_rank) || ' · ' ||
         case pk.mode when 'flat' then public.stat_words(pk.stat, pk.per_rank * p_rank, false)
                      when 'unit_pct' then public.stat_words(pk.stat, pk.per_rank * p_rank, true) || ' of its own'
                      when 'wear' then 'wears ' || (pk.per_rank * p_rank)::int || '% slower'
                      when 'deck' then '−' || (pk.per_rank * p_rank)::int || ' deck'
                      else '−' || (pk.per_rank * p_rank)::int || '% hands' end
    from public.perks pk where pk.code = p_perk
$$;
revoke all on function public.perk_rank_words(text, int) from public, anon, authenticated;

create or replace function public.unit_perk_card(p_item text, p_perks text[])
returns jsonb
language plpgsql
stable
set search_path = public, pg_temp
as $$
begin
  -- 0163 (S16): WHAT THE SHIP PANEL PRINTS OF A UNIT'S PERKS — the ones it has (code, rank, words) and, for
  -- a unit that may be augmented, the perks that fit it (code, word, kit, each rank's words). '{}' for any
  -- other unit, so a G1 / G2 unit's entry is its pre-image. Read by world.ship_racks.
  if cardinality(coalesce(p_perks, '{}')) = 0 and not public.unit_augmentable(p_item) then
    return '{}'::jsonb;
  end if;
  return jsonb_strip_nulls(jsonb_build_object(
    'perks', (select jsonb_agg(jsonb_build_object('code', r.code, 'rank', r.rank, 'words', public.perk_rank_words(r.code, r.rank)))
                from public.perk_ranks(p_perks) r),
    'perk_options', case when public.unit_augmentable(p_item) then
      (select jsonb_agg(jsonb_build_object('code', pk.code, 'word', pk.word,
                                           'kit', coalesce((select k.name from public.item_kinds k where k.code = pk.kit), 'any kit'),
                                           'ranks', (select jsonb_agg(public.perk_rank_words(pk.code, n) order by n) from generate_series(1, 3) n))
                        order by pk.ord)
         from public.perks pk where public.perk_fits(pk.code, p_item)) end));
end $$;
revoke all on function public.unit_perk_card(text, text[]) from public, anon, authenticated;

-- ── 5. THE CORE AND THE DOOR ───────────────────────────────────────────────────────────────────
create or replace function public.augment_fitting_for(p_player uuid, p_ship uuid, p_item text, p_perk text, p_rank int, p_kit text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $af$
-- 0163 (S16, §6.6): THE ONE CORE OF AUGMENTING — a perk the player CHOOSES put on one mounted unit, paid in
-- kits from the store in this city. Every refusal in its own words ({ok false, error_code, error_message}).
declare
  v_ship  record;
  v_unit  record;
  v_perk  public.perks%rowtype;
  v_level int;
  v_kit   text;
  v_have  int;
  v_rows  int;
  v_perks text[];
  v_words text;
  v_max   int;     -- how many perks this unit may carry (Augmentation V: 2; the knob caps it)
begin
  select s.id, s.name, s.player_id, s.fleet_id, f.status, f.port_id, f.name as fleet into v_ship
    from public.ships s join public.fleets f on f.id = s.fleet_id where s.id = p_ship;
  if v_ship.id is null or v_ship.player_id is distinct from p_player then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_YOUR_SHIP', 'error_message', 'That ship is not yours.');
  end if;
  perform public.fitting_lock(p_player);
  if v_ship.status <> 'DOCKED' then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_DOCKED',
      'error_message', format('%s is at sea. Fittings are augmented in port.', v_ship.name));
  end if;
  if coalesce((select b.tier from public.port_buildings b where b.port_id = v_ship.port_id and b.kind = 'workstation'), 0) < 3 then
    return jsonb_build_object('ok', false, 'error_code', 'E_WORKSTATION_TOO_SMALL',
      'error_message', 'Fittings are augmented at a level 3 workshop. This port has none.');
  end if;
  select * into v_perk from public.perks where code = upper(coalesce(p_perk, ''));
  if v_perk.code is null or coalesce(p_rank, 0) not between 1 and 3 then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_SUCH_PERK', 'error_message', 'There is no such perk or rank.');
  end if;
  -- the unit: of this item on this ship, the one with the fewest perks, then the oldest
  select u.id, u.perks, k.name into v_unit
    from public.fitted_units u join public.item_kinds k on k.code = u.item_code
   where u.ship_id = v_ship.id and u.item_code = p_item
   order by cardinality(u.perks), u.mounted_at, u.id limit 1;
  if v_unit.id is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_FITTED',
      'error_message', format('%s carries no such fitting.', v_ship.name));
  end if;
  if not public.unit_augmentable(p_item) then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_AUGMENTABLE',
      'error_message', format('%s cannot be augmented: only grade III and better, T2, Country and Famous fittings can.', v_unit.name));
  end if;
  if not public.perk_fits(v_perk.code, p_item) then
    return jsonb_build_object('ok', false, 'error_code', 'E_PERK_DOES_NOT_FIT',
      'error_message', format('%s does not fit %s.', v_perk.word, v_unit.name));
  end if;
  -- the skill: Augmentation L allows rank ≤ ⌈L / 2⌉ and a second perk at V. Dark, no level counts (0135's rule).
  v_level := case when public.skills_bite_on() then coalesce(public.skill_level(p_player, 'AUGMENTATION'), 0) else 0 end;
  if p_rank > (v_level + 1) / 2 then
    return jsonb_build_object('ok', false, 'error_code', 'E_NEEDS_SKILL',
      'error_message', format('%s %s needs Augmentation %s', v_perk.word, public.skill_level_word(p_rank),
                              public.skill_level_word(p_rank * 2 - 1))
                       || case when public.skills_bite_on() then '' else ' — ship skills are not in use yet' end,
      'figures', cmd.figures(v_level, p_rank * 2 - 1, 'level'));
  end if;
  v_perks := array(select x from unnest(v_unit.perks) x where split_part(x, ':', 1) <> v_perk.code);
  v_max := least(case when v_level >= 5 then 2 else 1 end, public.wc_num('perks_max_per_unit')::int);
  if cardinality(v_perks) >= v_max then
    return jsonb_build_object('ok', false, 'error_code', 'E_PERKS_FULL',
      'error_message', format('%s already carries %s', v_unit.name,
                              (select string_agg(public.perk_rank_words(r.code, r.rank), ' and ') from public.perk_ranks(v_perks) r))
                       || case when v_level >= 5 then '.' else '. A second perk needs Augmentation V.' end);
  end if;
  -- the kits: the perk's own kit, or (any kit) the one named, else the first this store holds enough of
  v_kit := coalesce(v_perk.kit, p_kit,
                    (select pi.item_code from public.player_items pi join public.item_profile ip on ip.item_code = pi.item_code
                      where pi.player_id = p_player and pi.port_id = v_ship.port_id and ip.rack = 'kit' and pi.qty >= p_rank
                      order by pi.item_code limit 1));
  v_have := coalesce((select pi.qty from public.player_items pi
                       where pi.player_id = p_player and pi.port_id = v_ship.port_id and pi.item_code = v_kit), 0);
  if v_kit is null or v_have < p_rank then
    return jsonb_build_object('ok', false, 'error_code', 'E_NONE_HERE',
      'error_message', format('%s %s takes %s %s; you keep %s in this city.', v_perk.word, public.skill_level_word(p_rank),
                              p_rank, coalesce((select k.name from public.item_kinds k where k.code = v_kit), 'kit(s)'), v_have),
      'figures', cmd.figures(v_have, p_rank, 'kits'));
  end if;
  update public.player_items set qty = qty - p_rank
   where player_id = p_player and port_id = v_ship.port_id and item_code = v_kit and qty >= p_rank;
  get diagnostics v_rows = row_count;
  if v_rows <> 1 then
    return jsonb_build_object('ok', false, 'error_code', 'E_NONE_HERE', 'error_message', 'The kits are no longer in this city.');
  end if;
  delete from public.player_items where player_id = p_player and port_id = v_ship.port_id and item_code = v_kit and qty <= 0;
  update public.fitted_units set perks = v_perks || (v_perk.code || ':' || p_rank) where id = v_unit.id;
  v_words := format('%s on %s now carries %s.', v_unit.name, v_ship.name, public.perk_rank_words(v_perk.code, p_rank));
  perform public.emit_event(p_player, 'AUGMENTED', jsonb_build_object(
    'fleet', v_ship.fleet, 'ship', v_ship.name, 'item', v_unit.name, 'perk', v_perk.code, 'rank', p_rank, 'kit', v_kit, 'words', v_words));
  return jsonb_build_object('ok', true, 'ship', v_ship.name, 'item', p_item, 'perk', v_perk.code, 'rank', p_rank, 'sentence', v_words);
end $af$;
comment on function public.augment_fitting_for(uuid, uuid, text, text, int, text) is
  '0163 (S16): THE one core that augments a mounted unit (a chosen perk, paid in kits). With mount_fitting, '
  'unmount_fitting, wear_units_for and repair_units_for, the only writers of public.fitted_units. Server-only.';
revoke all on function public.augment_fitting_for(uuid, uuid, text, text, int, text) from public, anon, authenticated;

create or replace function cmd.augment_fitting(p_ship uuid, p_item text, p_perk text, p_rank int)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $ca$
declare
  v_player uuid := public.current_player_id();
begin
  -- 0163 (S16): THE DOOR — augment one of your fittings with a perk you choose (§6.6). The work is
  -- public.augment_fitting_for's.
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_SIGNED_IN', 'error_message', 'Nobody is signed in.');
  end if;
  return public.augment_fitting_for(v_player, p_ship, p_item, p_perk, p_rank);
end $ca$;
comment on function cmd.augment_fitting(uuid, text, text, int) is
  '0163 (S16): augment a fitting with a chosen perk (the core: public.augment_fitting_for). An entry point.';
revoke all on function cmd.augment_fitting(uuid, text, text, int) from public, anon;
grant execute on function cmd.augment_fitting(uuid, text, text, int) to authenticated;

-- ── 6. THE HUNKS (old → new), sliced from the live bodies ──────────────────────────────────────
create temp table hunks_0163 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0163 values
('world.ship_stats(uuid)', 1,
$h$               where f.ship_id = p_ship
              union all
              select sb.stat, null, sb.pct
$h$,
$h$               where f.ship_id = p_ship
              union all
              -- 0163 (S16): what her units' perks add (public.unit_perk_deltas), and her sets (public.ship_set_bonus)
              select pd.stat, pd.delta, null
                from public.fitted_units f
               cross join lateral public.unit_perk_deltas(f.item_code, f.perks) pd
               where f.ship_id = p_ship and cardinality(f.perks) > 0
              union all
              select sd.stat, sd.delta, null from public.ship_set_bonus(p_ship) sd
              union all
              select sb.stat, null, sb.pct
$h$),
('world.ship_stats(uuid)', 2,
$h$    select e.stat, sum(case when f.wear > 0 and e.delta > 0 then public.worn_delta(e.delta, f.wear) else e.delta end) as delta
      from public.fitted_units f
      join public.item_effects e on e.item_code = f.item_code
     where f.ship_id = p_ship
     group by e.stat
$h$,
$h$    select x.stat, sum(x.delta) as delta from (
      select e.stat, case when f.wear > 0 and e.delta > 0 then public.worn_delta(e.delta, f.wear) else e.delta end as delta
        from public.fitted_units f
        join public.item_effects e on e.item_code = f.item_code
       where f.ship_id = p_ship
      union all
      -- 0163 (S16): what her units' perks add (only a unit that has perks), and her sets (none: one indexed read)
      select pd.stat, pd.delta
        from public.fitted_units f
       cross join lateral public.unit_perk_deltas(f.item_code, f.perks) pd
       where f.ship_id = p_ship and cardinality(f.perks) > 0
      union all
      select sd.stat, sd.delta from public.ship_set_bonus(p_ship) sd) x
     group by x.stat
$h$),
('world.ship_budget(uuid)', 1,
$h$    left join lateral (select sum(ip.deck)::int as deck, sum(ip.hands)::int as hands
$h$,
$h$    -- 0163 (S16): a unit's perks may lower what it needs (public.perk_unit_cost: Light, Handy), and her sets
    -- what her fittings need of Hands (public.ship_set_hands_pct: the VOC set); a unit without perks, a hull
    -- without set pieces, exactly as before
    left join lateral (select sum(case when cardinality(fu.perks) = 0 then ip.deck
                                       else public.perk_unit_cost(ip.deck, 'deck', fu.perks) end)::int as deck,
                              (case when x.hp = 0 then sum(case when cardinality(fu.perks) = 0 then ip.hands
                                                                else public.perk_unit_cost(ip.hands, 'hands', fu.perks) end)
                                    else round(sum(case when cardinality(fu.perks) = 0 then ip.hands
                                                        else public.perk_unit_cost(ip.hands, 'hands', fu.perks) end)
                                               * (100 + x.hp) / 100.0) end)::int as hands
$h$),
('world.ship_budget(uuid)', 2,
$h$                        where fu.ship_id = s.id) u on true
   where s.id = p_ship
$h$,
$h$                        cross join (select public.ship_set_hands_pct(s.id) as hp) x
                        where fu.ship_id = s.id
                        group by x.hp) u on true
   where s.id = p_ship
$h$),
('world.ship_budget(uuid)', 3,
$h$           'hands', jsonb_build_object('used', (select coalesce(sum(public.drilled_hands(ip.hands, ip.rack, v_drill)), 0)::int
$h$,
$h$           'hands', jsonb_build_object('used', (select coalesce(sum(public.drilled_hands(
                                                    case when cardinality(fu.perks) = 0 then ip.hands
                                                         else public.perk_unit_cost(ip.hands, 'hands', fu.perks) end,   -- 0163: Handy
                                                    ip.rack, v_drill)), 0)::int
$h$),
('world.ship_racks(uuid, jsonb)', 1,
$h$                                                 else '{}'::jsonb end
                                        order by ik.slot, ik.name, u.mounted_at, u.id) as fitted
$h$,
$h$                                                 else '{}'::jsonb end
                                         -- 0163 (S16): its perks and, if it may be augmented, the perks that fit it
                                         || public.unit_perk_card(u.item_code, u.perks)
                                        order by ik.slot, ik.name, u.mounted_at, u.id) as fitted
$h$),
('world.ship_view(uuid)', 1,
$h$   where s.id = p_ship
  );
  -- 0133: … plus `bonuses`$h$,
$h$   where s.id = p_ship
  );
  -- 0163 (S16): … plus `sets` — her set progress (world.ship_set_card), only where she carries a set piece
  v_view := v_view || world.ship_set_card(p_ship);
  -- 0133: … plus `bonuses`$h$),
('public.wear_units_for(uuid, uuid)', 1,
$h$                   else 0 end as gain
$h$,
$h$                   else 0 end
                 -- 0163 (S16): Seasoned wears slower (public.perk_wear_mult); a unit without perks, × 1
                 * case when cardinality(fu.perks) = 0 then 1 else public.perk_wear_mult(fu.perks) end as gain
$h$),
('public.made_only_in(text, uuid)', 1,
$h$  return (select format('%s is made only in %s', k.name, p.name)
            from public.item_city ic
            join public.item_kinds k on k.code = ic.item_code
            join public.ports p on p.id = ic.port_id
           where ic.item_code = p_item and ic.port_id is distinct from p_port);
$h$,
$h$  return coalesce(
         (select format('%s is made only in %s', k.name, p.name)
            from public.item_city ic
            join public.item_kinds k on k.code = ic.item_code
            join public.ports p on p.id = ic.port_id
           where ic.item_code = p_item and ic.port_id is distinct from p_port),
         -- 0163 (S16, §6.2): a COUNTRY item is made only in a port of its line's builder nations
         (select format('%s is made only where %s builds its ships', k.name, sl.name)
            from public.item_line il
            join public.item_kinds k on k.code = il.item_code
            join public.ship_lines sl on sl.code = il.line_code
           where il.item_code = p_item
             and not exists (select 1 from public.ports p join public.nations n on n.id = p.nation_id
                              where p.id = p_port and n.code = any(sl.builder_nations))));
$h$),
('public.client_rpc_entry_points()', 1,
$h$      ('world'::text, 'port_merchants'::text,  'uuid'::text),
$h$,
$h$      ('world'::text, 'port_merchants'::text,  'uuid'::text),
      -- 0163 (S16): augment a fitting with a chosen perk (public.augment_fitting_for). At the head, as above.
      ('cmd',         'augment_fitting',       'uuid, text, text, int'),
$h$);

create or replace function pg_temp.recut_0163(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := replace(pg_get_functiondef(p_fn::regprocedure), E'\r', '');
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0163 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0163(v_def, h.old);
    if v_n <> 1 then
      raise exception '0163 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0163(fn) from defs_before_0163 order by fn;

select pg_temp.time_reads_0163('after');

-- ── 7. DARK, EVERY HULL: stats, budget, racks and the whole ship = the old bodies' (one statement) ─────
create temp table hulls_0163 on commit drop as
select s.id as ship_id,
       world.ship_stats(s.id)::text as new_stats, pg_temp.world_ship_stats_b0163(s.id)::text as old_stats,
       world.ship_budget(s.id)::text as new_budget, pg_temp.world_ship_budget_b0163(s.id)::text as old_budget,
       world.ship_view(s.id)::text as new_view, pg_temp.world_ship_view_b0163(s.id)::text as old_view
  from public.ships s;

-- ── 8. THE PROBE (its own company, rolled back whole) ──────────────────────────────────────────
create or replace function pg_temp.probe_0163()
returns jsonb
language plpgsql
as $$
declare
  c_uid   constant uuid := '00000000-0163-4000-8000-000000000001';
  v_lis   uuid := (select id from public.ports where code = 'LIS');
  v_lon   uuid := (select id from public.ports where code = 'LON');
  v_p     uuid;
  v_f     uuid;
  v_nau   uuid;
  v_out   jsonb := '{}'::jsonb;
  v_x     jsonb;
  v_r     jsonb;
  v_items text[];
  v_eng   record;
begin
  begin
    update public.world_config set value = 'false'::jsonb where key = 'skills_bite';
    update public.world_config set value = 'false'::jsonb where key = 'gear_wear_bite';
    v_p := public.new_house(c_uid, 'Casa do Engenho 0163', 'PRT', 'LIS');
    select id into v_f from public.fleets where player_id = v_p;
    perform public.credit(v_p, 'PROBE_0163', 100000000);
    -- a nau (High 3 / Mid 5 / Low 1 / Flourish 1): the four ENG set pieces fit her, through the one core
    v_nau := public.commission_ship(v_p, v_f, 'nau', 'Prova Nau', false, true);
    select max(il.item_code) filter (where ip.rack = 'high') as high, max(il.item_code) filter (where ip.rack = 'mid') as mid,
           max(il.item_code) filter (where ip.rack = 'low') as low, max(il.item_code) filter (where ip.rack = 'flourish') as fig
      into v_eng
      from public.item_line il join public.item_profile ip on ip.item_code = il.item_code where il.line_code = 'ENG';

    -- (D) DARK: a Country piece cannot be made, fitted, nor a perk chosen — said so
    insert into public.player_items (player_id, port_id, item_code, qty) values (v_p, v_lis, v_eng.high, 1), (v_p, v_lis, 'brass-guns', 1),
      (v_p, v_lis, 'gunsmiths-kit', 6), (v_p, v_lis, 'sailmakers-kit', 6), (v_p, v_lis, 'shipwrights-kit', 6), (v_p, v_lis, 'navigators-kit', 6)
    on conflict (player_id, port_id, item_code) do update set qty = excluded.qty;
    v_out := v_out || jsonb_build_object('dark_fit', pg_temp.rb_0163(format(
      'select cmd.do_fit(%L, %L::jsonb)', v_f, jsonb_build_object('item', v_eng.high, 'ship', 'Prova Nau'))));

    -- (L) LIT (rolled back): the skills that open the pieces and Augmentation V
    update public.world_config set value = 'true'::jsonb where key = 'skills_bite';
    insert into public.player_skills (player_id, skill_id, level)
    select v_p, sk.id, 5 from public.skills sk
     where sk.code in ('ENG_MEDIUM', 'GUNNERY', 'RIGGING', 'SEAMANSHIP', 'SHIPWRIGHT', 'CARGO_STOWAGE', 'LOOKOUTS', 'INSTRUMENTS',
                       'BOARDING', 'SHORT_GUNS', 'LONG_GUNS', 'AUGMENTATION')
    on conflict (player_id, skill_id) do update set level = excluded.level;
    -- (L1) A COUNTRY ITEM IS MADE ONLY WHERE ITS LINE BUILDS: London says nothing, Lisbon says where
    v_out := v_out || jsonb_build_object('made_lis', public.made_only_in(v_eng.high, v_lis), 'made_lon', public.made_only_in(v_eng.high, v_lon));
    -- (L2) SETS: the four ENG pieces mounted one by one; the bonuses appear at 2 and at 4 pieces only
    insert into public.player_items (player_id, port_id, item_code, qty) values
      (v_p, v_lis, v_eng.mid, 1), (v_p, v_lis, v_eng.low, 1), (v_p, v_lis, v_eng.fig, 1)
    on conflict (player_id, port_id, item_code) do update set qty = excluded.qty;
    v_x := jsonb_build_object('p0', pg_temp.dark_stats_0163(v_nau));
    perform cmd.do_fit(v_f, jsonb_build_object('item', v_eng.high, 'ship', 'Prova Nau'));
    v_x := v_x || jsonb_build_object('p1', pg_temp.dark_stats_0163(v_nau), 'p1_old', pg_temp.dark_old_stats_0163(v_nau),
                                     'card1', world.ship_view(v_nau)->'sets');
    perform cmd.do_fit(v_f, jsonb_build_object('item', v_eng.mid, 'ship', 'Prova Nau'));
    v_x := v_x || jsonb_build_object('p2', pg_temp.dark_stats_0163(v_nau), 'p2_old', pg_temp.dark_old_stats_0163(v_nau),
                                     'bonus2', (select jsonb_object_agg(stat, delta) from public.ship_set_bonus(v_nau)));
    perform cmd.do_fit(v_f, jsonb_build_object('item', v_eng.low, 'ship', 'Prova Nau'));
    v_x := v_x || jsonb_build_object('p3', pg_temp.dark_stats_0163(v_nau), 'p3_old', pg_temp.dark_old_stats_0163(v_nau),
                                     'bonus3', (select jsonb_object_agg(stat, delta) from public.ship_set_bonus(v_nau)));
    perform cmd.do_fit(v_f, jsonb_build_object('item', v_eng.fig, 'ship', 'Prova Nau'));
    v_x := v_x || jsonb_build_object('p4', pg_temp.dark_stats_0163(v_nau), 'p4_old', pg_temp.dark_old_stats_0163(v_nau),
                                     'bonus4', (select jsonb_object_agg(stat, delta) from public.ship_set_bonus(v_nau)),
                                     'card4', world.ship_view(v_nau)->'sets',
                                     'want4', (select jsonb_object_agg(stat, coalesce(pct, flat)) from public.gear_set_bonuses where line_code = 'ENG'));
    v_out := v_out || jsonb_build_object('sets', v_x);

    -- (L3) A PERK, CHOSEN: Brass Guns (G3) on the nau; Precise II for 2 Gunsmith's Kits; the ship reads +6 accuracy
    v_x := jsonb_build_object('acc_bare', pg_temp.dark_stats_0163(v_nau)->'accuracy');
    perform cmd.do_fit(v_f, '{"item": "brass-guns", "ship": "Prova Nau"}'::jsonb);
    v_x := v_x || jsonb_build_object('acc0', pg_temp.dark_stats_0163(v_nau)->'accuracy',
                              'card0', (select u from jsonb_array_elements(world.ship_view(v_nau)->'racks') rk, jsonb_array_elements(rk->'fitted') u
                                         where u->>'code' = 'brass-guns'),
                              'kits0', (select qty from public.player_items where player_id = v_p and port_id = v_lis and item_code = 'gunsmiths-kit'));
    v_r := public.augment_fitting_for(v_p, v_nau, 'brass-guns', 'PRECISE', 2);
    v_x := v_x || jsonb_build_object('r', v_r, 'acc1', pg_temp.dark_stats_0163(v_nau)->'accuracy',
                                     'kits1', (select qty from public.player_items where player_id = v_p and port_id = v_lis and item_code = 'gunsmiths-kit'),
                                     'perks', (select u.perks from public.fitted_units u where u.ship_id = v_nau and u.item_code = 'brass-guns'),
                                     'card1', (select u->'perks' from jsonb_array_elements(world.ship_view(v_nau)->'racks') rk, jsonb_array_elements(rk->'fitted') u
                                                where u->>'code' = 'brass-guns'));
    -- refusals in their own words: a G1 unit; a perk for another rack; rank III with Augmentation IV; a third perk
    v_x := v_x || jsonb_build_object(
      'hard', public.augment_fitting_for(v_p, v_nau, 'brass-guns', 'HARD_HITTING', 1),
      'third', public.augment_fitting_for(v_p, v_nau, 'brass-guns', 'FAR_REACHING', 1),
      'wrong_rack', public.augment_fitting_for(v_p, v_nau, 'brass-guns', 'SWIFT', 1));
    update public.player_skills set level = 4 where player_id = v_p and skill_id = (select id from public.skills where code = 'AUGMENTATION');
    v_x := v_x || jsonb_build_object('rank3', public.augment_fitting_for(v_p, v_nau, 'brass-guns', 'PRECISE', 3));
    v_out := v_out || jsonb_build_object('perk', v_x);
    -- (L4) THE PERKS GO WITH THE UNIT: off, back in the store, and a fresh unit carries none
    perform cmd.do_unfit(v_f, '{"item": "brass-guns", "ship": "Prova Nau"}'::jsonb);
    v_out := v_out || jsonb_build_object('off', jsonb_build_object(
      'acc', pg_temp.dark_stats_0163(v_nau)->'accuracy',
      'units', (select count(*) from public.fitted_units u where u.ship_id = v_nau and u.item_code = 'brass-guns'),
      'store', (select qty from public.player_items where player_id = v_p and port_id = v_lis and item_code = 'brass-guns')));
    perform cmd.do_fit(v_f, '{"item": "brass-guns", "ship": "Prova Nau"}'::jsonb);
    v_out := v_out || jsonb_build_object('refit_perks', (select u.perks from public.fitted_units u where u.ship_id = v_nau and u.item_code = 'brass-guns'));
    -- (L5) SEASONED halves the wear a passage brings (rank II); LIGHT and HANDY lower the budget
    update public.player_skills set level = 5 where player_id = v_p and skill_id = (select id from public.skills where code = 'AUGMENTATION');
    v_x := jsonb_build_object('budget0', world.ship_budget(v_nau),
                              'season', public.augment_fitting_for(v_p, v_nau, 'brass-guns', 'SEASONED', 2, 'shipwrights-kit'),
                              'light', public.augment_fitting_for(v_p, v_nau, 'brass-guns', 'LIGHT', 2));
    v_x := v_x || jsonb_build_object('budget1', world.ship_budget(v_nau), 'mult', public.perk_wear_mult(
               (select u.perks from public.fitted_units u where u.ship_id = v_nau and u.item_code = 'brass-guns')),
             'deck', (select ip.deck from public.item_profile ip where ip.item_code = 'brass-guns'));
    v_out := v_out || jsonb_build_object('budget', v_x);
    update public.world_config set value = 'false'::jsonb where key = 'skills_bite';
    raise exception 'PROBE_ROLLBACK_0163';
  exception when others then
    if sqlerrm <> 'PROBE_ROLLBACK_0163' then raise; end if;
  end;
  return v_out;
end $$;

-- a hull's stats read with skills off (the lit probe's pieces stay on; only the read is dark), so a set or a
-- perk is compared without a skill's per cent scaling it
create or replace function pg_temp.dark_stats_0163(p_ship uuid)
returns jsonb
language plpgsql
as $$
declare
  v_on  boolean := public.skills_bite_on();
  v     jsonb;
begin
  update public.world_config set value = 'false'::jsonb where key = 'skills_bite';
  v := world.ship_stats(p_ship);
  update public.world_config set value = to_jsonb(v_on) where key = 'skills_bite';
  return v;
end $$;

create or replace function pg_temp.dark_old_stats_0163(p_ship uuid)
returns jsonb
language plpgsql
as $$
declare
  v_on  boolean := public.skills_bite_on();
  v     jsonb;
begin
  update public.world_config set value = 'false'::jsonb where key = 'skills_bite';
  v := pg_temp.world_ship_stats_b0163(p_ship);
  update public.world_config set value = to_jsonb(v_on) where key = 'skills_bite';
  return v;
end $$;

-- run one statement with its writes rolled back; its jsonb answer, or the refusal it raised
create or replace function pg_temp.rb_0163(p_sql text)
returns jsonb
language plpgsql
as $$
declare
  r jsonb;
begin
  begin
    execute p_sql into r;
    raise exception 'RB_0163';
  exception when others then
    if sqlerrm <> 'RB_0163' then r := jsonb_build_object('refused', sqlerrm); end if;
  end;
  return r;
end $$;

create temp table probe_0163 (j jsonb) on commit drop;
do $$
declare
  v_try   int := 0;
  v_state text;
  v_msg   text;
begin
  loop
    v_try := v_try + 1;
    begin
      insert into probe_0163 select pg_temp.probe_0163();
      exit;
    exception when lock_not_available or deadlock_detected then
      get stacked diagnostics v_msg = message_text, v_state = returned_sqlstate;
    end;
    if v_try >= 5 then
      raise exception '0163 self-assert FAIL: LOCK CONTENTION, not a result — the probe could not get its locks in 5 tries (%: %). Re-run the push.',
        v_state, v_msg;
    end if;
    perform pg_sleep(0.2);
  end loop;
end $$;

-- ── 9. SELF-ASSERT ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_b     record;
  v_d     record;
  v_h     record;
  v_pp    record;
  v_rd    record;
  v_bad   bigint;
  v_n     bigint;
  v_def   text;
  v_list  text;
  v_pr    jsonb := (select j from probe_0163);
  v_s     jsonb;
  v_writers text[];
  v_notes text := '';
  v_k     text;
begin
  select * into v_b from before_0163;

  -- (a) DARK, EVERY HULL: ship_stats, ship_budget and the whole ship_view = the old bodies' (one statement)
  select count(*), count(*) filter (where new_stats is distinct from old_stats or new_budget is distinct from old_budget
                                       or new_view is distinct from old_view)
    into v_n, v_bad from hulls_0163;
  if v_n = 0 or v_bad <> 0 then
    raise exception '0163 self-assert FAIL: % of % hull(s) read a different ship_stats, ship_budget or ship_view', v_bad, v_n;
  end if;
  if v_b.perked_units <> 0 then
    raise exception '0163 self-assert FAIL: % unit(s) carried a perk before any door could write one', v_b.perked_units;
  end if;

  -- (b) THE CATALOGUE: old rows unmoved; 48 items whole; perks, sets, lines and the knob as the data
  if (select md5(string_agg(to_jsonb(c)::text, '|' order by c.code)) from public.item_kinds c where c.code in (select code from live_items_0163)) <> v_b.kinds_hash
     or (select md5(string_agg(to_jsonb(c)::text, '|' order by c.item_code)) from public.item_profile c where c.item_code in (select code from live_items_0163)) <> v_b.profile_hash
     or (select md5(string_agg(to_jsonb(c)::text, '|' order by c.item_code, c.stat)) from public.item_effects c where c.item_code in (select code from live_items_0163)) <> v_b.effects_hash
     or (select md5(string_agg(to_jsonb(c)::text, '|' order by c.item_code)) from public.item_use c where c.item_code in (select code from live_items_0163)) <> v_b.use_hash
     or (select md5(string_agg(to_jsonb(c)::text, '|' order by c.code)) from public.gear_racks c where c.code <> 'kit') <> v_b.racks_hash then
    raise exception '0163 self-assert FAIL: a live item or rack moved';
  end if;
  if (select count(*) from public.item_kinds) <> v_b.kinds + 48
     or (select count(*) from public.item_line) <> 44
     or exists (select line_code from public.item_line group by line_code having count(*) <> 4)
     or (select count(distinct line_code) from public.item_line) <> 11
     or exists (select 1 from public.item_line il join public.item_profile ip on ip.item_code = il.item_code
                 group by il.line_code having count(distinct ip.rack) <> 4)
     or exists (select 1 from public.item_line il join public.item_profile ip on ip.item_code = il.item_code where ip.meta <> 6)
     or exists (select 1 from public.item_profile ip where ip.meta = 6 and not exists (select 1 from public.item_line il where il.item_code = ip.item_code))
     or (select count(*) from public.item_profile where rack = 'kit') <> 4
     or exists (select 1 from public.item_profile ip where ip.rack = 'kit' and (ip.deck <> 0 or ip.hands <> 0))
     or exists (select 1 from public.class_slots where slot = 'kit')
     or (select count(*) from public.item_use) <> (select count(*) from public.item_kinds)
     or (select count(*) from public.perks) <> 10 or (select count(distinct line_code) from public.gear_set_bonuses) <> 11
     or (select count(*) from public.gear_set_names) <> 11
     or exists (select 1 from public.gear_set_bonuses gb where gb.stat not in ('hold', 'speed', 'handling', 'durability', 'armour', 'attack', 'accuracy', 'reach', 'sighting', 'hands'))
     or exists (select 1 from public.perks pk where pk.kit is not null and not exists (select 1 from public.item_profile ip where ip.item_code = pk.kit and ip.rack = 'kit'))
     or public.wc_num('perks_max_per_unit') <> 2 then
    raise exception '0163 self-assert FAIL: the Country gear, kits, perks or sets are not whole (items %, lines %)',
      (select count(*) from public.item_kinds), (select count(*) from public.item_line);
  end if;
  -- every Country piece but the figurehead buys one and spends one (0074); every one needs its line's Medium Hulls I;
  -- every recipe good is sold somewhere
  if exists (select 1 from public.item_line il join public.item_profile ip on ip.item_code = il.item_code
              where ip.base_type <> 'Figurehead'
                and not (exists (select 1 from public.item_effects e where e.item_code = il.item_code and e.delta > 0)
                     and exists (select 1 from public.item_effects e where e.item_code = il.item_code and e.delta < 0)))
     or exists (select 1 from public.item_line il where not exists (select 1 from public.skill_requirements r
                 where r.subject_kind = 'item' and r.subject_code = il.item_code and r.skill_code = il.line_code || '_MEDIUM' and r.level = 1))
     or exists (select 1 from public.item_recipes ir join public.item_profile ip on ip.item_code = ir.item_code
                 where (ip.meta = 6 or ip.rack = 'kit')
                   and not exists (select 1 from public.port_goods pg join public.ports p on p.id = pg.port_id
                                    where pg.good_id = ir.good_id and public.port_offers(p.id, ir.good_id))) then
    raise exception '0163 self-assert FAIL: a Country piece breaks buys-one-spends-one, lacks its line''s Medium Hulls I, or a recipe good is sold nowhere';
  end if;
  -- every line can make its pieces somewhere: a tier-2 workshop in a port of its builders
  select count(*), string_agg(il.line_code, ',') into v_bad, v_list from (select distinct line_code from public.item_line) il
   where not exists (select 1 from public.ports p join public.nations n on n.id = p.nation_id
                       join public.ship_lines sl on sl.code = il.line_code
                       join public.port_buildings b on b.port_id = p.id and b.kind = 'workstation' and b.tier >= 2
                      where n.code = any(sl.builder_nations));
  if v_bad <> 0 then
    raise exception '0163 self-assert FAIL: % line(s) have no tier-2 workshop in a port of their builders: %', v_bad, v_list;
  end if;

  -- (c) DARK THROUGH THE DOOR: a Country piece is refused for its skills, with the dark reason
  if coalesce(v_pr->'dark_fit'->>'refused', '') not like 'E_NEEDS_SKILL:%ship skills are not in use yet%' then
    raise exception '0163 self-assert FAIL: dark, a Country piece was not refused for its skills: %', v_pr->'dark_fit';
  end if;

  -- (d) MADE ONLY WHERE ITS LINE BUILDS
  if v_pr->>'made_lon' is not null or coalesce(v_pr->>'made_lis', '') not like '% is made only where England builds its ships' then
    raise exception '0163 self-assert FAIL: a Country item''s making rule: London %, Lisbon %', v_pr->'made_lon', v_pr->'made_lis';
  end if;

  -- (e) SETS AT 2 AND 4 PIECES ONLY: one piece — the old body's stats exactly, no bonus row, a card 1 / 4; two —
  --     the 2-piece bonus; three — the same; four — the 2- and the 4-piece; each = old body + the set bonus
  v_s := v_pr->'sets';
  if (v_s->'p1') is distinct from (v_s->'p1_old')
     or (v_s->'card1'->0->>'pieces')::int <> 1 or (v_s->'card1'->0->>'line') <> 'ENG'
     or v_s->'bonus2' is null or v_s->'bonus3' is distinct from v_s->'bonus2'
     or (select count(*) from jsonb_object_keys(v_s->'bonus4')) <= (select count(*) from jsonb_object_keys(v_s->'bonus2'))
     or exists (select 1 from jsonb_each(v_s->'bonus2') e where not exists (select 1 from public.gear_set_bonuses gb
                 where gb.line_code = 'ENG' and gb.pieces = 2 and gb.stat = e.key))
     or (v_s->'card4'->0->>'pieces')::int <> 4
     or exists (select 1 from jsonb_array_elements(v_s->'card4'->0->'bonuses') bb where not (bb->>'in_force')::boolean) then
    raise exception '0163 self-assert FAIL: the ENG set did not bite at 2 and 4 pieces only: %', v_s;
  end if;
  for v_k in select unnest(array['p2', 'p3', 'p4']) loop
    if exists (select 1 from jsonb_each(v_s->v_k) e
                where (e.value)::text::numeric is distinct from
                      ((v_s->(v_k || '_old')->>e.key)::numeric
                       + coalesce((v_s->('bonus' || substr(v_k, 2))->>e.key)::numeric, 0))) then
      raise exception '0163 self-assert FAIL: with % piece(s), a stat is not the old body''s + the set bonus: % vs % + %',
        substr(v_k, 2), v_s->v_k, v_s->(v_k || '_old'), v_s->('bonus' || substr(v_k, 2));
    end if;
  end loop;

  -- (f) A PERK, CHOSEN: Precise II costs 2 Gunsmith's Kits and gives +6 accuracy, said in the server's words;
  --     refused in their own words for another rack, a second perk below V and rank III below Augmentation V;
  --     taken off with the unit, and a fresh unit carries none
  v_s := v_pr->'perk';
  if not coalesce((v_s->'r'->>'ok')::boolean, false)
     or (v_s->>'acc1')::numeric <> (v_s->>'acc0')::numeric + 6
     or (v_s->>'kits1')::int <> (v_s->>'kits0')::int - 2
     or v_s->'perks' is distinct from '["PRECISE:2"]'::jsonb
     or v_s->'card1'->0->>'words' is distinct from 'Precise II · +6 accuracy'
     or jsonb_array_length(coalesce(v_s->'card0'->'perk_options', '[]'::jsonb)) = 0 then
    raise exception '0163 self-assert FAIL: Precise II was not chosen, paid and read: %', v_s;
  end if;
  if v_s->'wrong_rack'->>'error_code' is distinct from 'E_PERK_DOES_NOT_FIT'
     or v_s->'rank3'->>'error_code' is distinct from 'E_NEEDS_SKILL'
     or v_s->'rank3'->>'error_message' is distinct from 'Precise III needs Augmentation V'
     or v_s->'rank3'->'figures' is distinct from '{"have": 4, "need": 5, "unit": "level"}'::jsonb then
    raise exception '0163 self-assert FAIL: a perk refusal is not in its own words: %', jsonb_build_object('wrong_rack', v_s->'wrong_rack', 'rank3', v_s->'rank3');
  end if;
  -- at Augmentation V a second perk is taken (Hard-hitting I), and a third is refused
  if not coalesce((v_s->'hard'->>'ok')::boolean, false) or v_s->'third'->>'error_code' is distinct from 'E_PERKS_FULL' then
    raise exception '0163 self-assert FAIL: the second perk at V or the cap on a third: %', jsonb_build_object('hard', v_s->'hard', 'third', v_s->'third');
  end if;
  if (v_pr->'off'->>'acc')::numeric is distinct from (v_s->>'acc_bare')::numeric
     or (v_pr->'off'->>'units')::int <> 0 or (v_pr->'off'->>'store')::int <> 1
     or v_pr->'refit_perks' is distinct from '[]'::jsonb then
    raise exception '0163 self-assert FAIL: the perks did not go with the unit: %', jsonb_build_object('off', v_pr->'off', 'again', v_pr->'refit_perks');
  end if;
  -- (g) SEASONED II halves the wear; LIGHT II takes 2 Deck off the unit (never below 1)
  v_s := v_pr->'budget';
  if not coalesce((v_s->'season'->>'ok')::boolean, false) or (v_s->>'mult')::numeric <> 0.50
     or not coalesce((v_s->'light'->>'ok')::boolean, false)
     or ((v_s->'budget0'->'deck'->>'used')::int - (v_s->'budget1'->'deck'->>'used')::int)
        <> (v_s->>'deck')::int - greatest(1, (v_s->>'deck')::int - 2) then
    raise exception '0163 self-assert FAIL: Seasoned or Light did not do what they say: %', v_s;
  end if;
  if exists (select 1 from public.players where auth_uid = '00000000-0163-4000-8000-000000000001') or public.skills_bite_on()
     or exists (select 1 from public.fitted_units where cardinality(perks) > 0) then
    raise exception '0163 self-assert FAIL: the probe world was not rolled back';
  end if;

  -- (h) THE WRITERS of fitted_units: mount (insert), unmount (delete), the wear writer, the repairer and the
  --     augment core (update); POSITIVE CONTROL: a planted writer is seen
  create or replace function pg_temp.fitted_writers_0163()
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
  v_writers := pg_temp.fitted_writers_0163();
  if v_writers is distinct from array['public.augment_fitting_for:update', 'public.mount_fitting:insert', 'public.repair_units_for:update',
                                      'public.unmount_fitting:delete', 'public.wear_units_for:update'] then
    raise exception '0163 self-assert FAIL: the live writers of fitted_units are %', v_writers;
  end if;
  begin
    execute $planted$create function public.zz_planted_writer_0163() returns void language sql as
      'update public.fitted_units set perks = perks where false'$planted$;
    if cardinality(pg_temp.fitted_writers_0163()) <> 6 then
      raise exception '0163 self-assert FAIL: the writer scan did not see a planted writer — it proves nothing';
    end if;
    raise exception 'CONTROL_ROLLBACK_0163';
  exception when others then
    if sqlerrm <> 'CONTROL_ROLLBACK_0163' then raise; end if;
  end;
  select string_agg(f.fn, ', ') into v_list
    from unnest(array['public.augment_fitting_for(uuid, uuid, text, text, integer, text)', 'public.unit_perk_deltas(text, text[])',
                      'public.ship_set_bonus(uuid)', 'world.ship_set_card(uuid)', 'public.unit_perk_card(text, text[])',
                      'world.ship_stats(uuid)', 'world.ship_budget(uuid)', 'world.ship_racks(uuid, jsonb)']) f(fn)
   where strpos(pg_get_functiondef(f.fn::regprocedure), 'is_npc') > 0;
  if v_list is not null then
    raise exception '0163 self-assert FAIL: a gear core or reading reads is_npc: %', v_list;
  end if;

  -- (i) THE RE-CUTS reverse to their pre-images; ACL / volatility / definer / config unmoved; the rest untouched
  for v_d in select * from defs_before_0163 order by fn loop
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    for v_h in select * from hunks_0163 where fn = v_d.fn order by n desc loop
      if pg_temp.occurs_0163(v_def, v_h.new) <> 1 then
        raise exception '0163 self-assert FAIL: hunk % of % is not in the new body exactly once', v_h.n, v_d.fn;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0163 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef, coalesce(pr.proconfig::text, '') as cfg
      into v_pp from pg_proc pr where pr.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0163 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;
  for v_d in select * from untouched_before_0163 loop
    if replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '') <> v_d.def then
      raise exception '0163 self-assert FAIL: % moved — it was to be left untouched', v_d.fn;
    end if;
  end loop;

  -- (j) THE WALL: +1 entry point exactly (cmd.augment_fitting, callable by a signed-in client); everything else server-only
  if (select count(*) from public.client_rpc_entry_points()) <> v_b.entry_points + 1
     or not exists (select 1 from public.client_rpc_entry_points() e where e.fn = 'cmd.augment_fitting(uuid, text, text, integer)'::regprocedure)
     or exists (select 1 from public.client_rpc_entry_points() e where e.fn is null or not has_function_privilege('authenticated', e.fn, 'execute'))
     or has_function_privilege('anon', 'cmd.augment_fitting(uuid, text, text, integer)', 'execute')
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0
     or exists (select 1 from unnest(array['public.augment_fitting_for(uuid, uuid, text, text, integer, text)', 'public.unit_perk_deltas(text, text[])',
                                           'public.perk_wear_mult(text[])', 'public.perk_unit_cost(integer, text, text[])', 'public.ship_set_pieces(uuid)',
                                           'public.ship_set_bonus(uuid)', 'public.ship_set_hands_pct(uuid)', 'world.ship_set_card(uuid)',
                                           'public.unit_perk_card(text, text[])', 'public.perk_ranks(text[])']) f(fn),
                       unnest(array['anon', 'authenticated']) rl(role)
                 where has_function_privilege(rl.role, f.fn, 'execute'))
     or exists (select 1 from unnest(array['public.perks', 'public.gear_set_bonuses', 'public.gear_set_names', 'public.item_line']) t(tbl),
                       unnest(array['anon', 'authenticated']) rl(role)
                 where has_table_privilege(rl.role, t.tbl, 'select,insert,update,delete')) then
    raise exception '0163 self-assert FAIL: the registry, the grant wall or the read wall is not the old one + cmd.augment_fitting';
  end if;

  for v_rd in select bf.what, bf.ms as before_ms, af.ms as after_ms, bf.hulls
             from reads_0163 bf join reads_0163 af on af.what = bf.what and af.phase = 'after'
            where bf.phase = 'before' order by bf.what loop
    v_notes := v_notes || format('%s over %s merchant hull(s) %s ms → %s ms; ', v_rd.what, v_rd.hulls, v_rd.before_ms, v_rd.after_ms);
  end loop;

  raise notice '0163 self-assert ok: A FITTING IS AUGMENTED, AND A COUNTRY''S GEAR IS A SET. DARK: % hull(s) — ship_stats, ship_budget and ship_view = the old bodies''; a Country piece refused for its skills (the dark reason). CATALOGUE: 44 Country items (four a line, a set each), 4 kits (rack Kits, which no hull has), 10 perks, 11 sets; the live items unmoved. LIT (rolled back): an ENG piece made only where England builds ("%"); the Sea Dogs set added nothing at 1 piece, its 2-piece bonus at 2 and 3, and the 4-piece too at 4 (each = old body + the bonus); Precise II chosen for 2 Gunsmith''s Kits, +6 accuracy ("%"); another rack, rank III below Augmentation V ("%") and a third perk refused in their own words; the perks went with the unit; Seasoned II wears × 0.50; Light lowers Deck. WRITERS: mount, unmount, wear, repair, augment — a planted writer seen. 7 bodies reverse; +1 entry point (cmd.augment_fitting). READS: %',
    v_n, v_pr->>'made_lis', v_pr->'perk'->'card1'->0->>'words', v_pr->'perk'->'rank3'->>'error_message', v_notes;
end $$;
