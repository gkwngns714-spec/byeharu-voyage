-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0159 — THE IMPROVED SHIPS AND THE NAMED GEAR  (S15 Wave C: 22 T2 hulls, 22 T2 modules, 12 Named
--        items — generated, guarded, and closed until the specialisations count)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY NOW ─────────────────────────────────────────────────────────────────────────────────────
-- docs/SHIPS_AND_SKILLS.md §8 row S15 (§4.1 the T2 tech, §4.3 Wave C, §4.4 the T2 requirements, §6.2
-- the meta ladder's T2 and Named rungs; docs/SKILLS_AND_CAPTAINS.md §9: hulls and gear unchanged, the
-- specialisations' support-V and second bonus already authored by K1 / 0151). 0135 put the T1 core and
-- five grades into the world, 0138 the capitals and flagships, 0158 the refits; the four role
-- specialisations (Armed Merchantmen, Privateers, Survey Ships, Convoy Escorts) and the six module
-- specialisations gate nothing yet.
--
-- ── WHAT SAYS THE OPPOSITE TODAY, NAMED ─────────────────────────────────────────────────────────
--   * No class_profile row has tech 'T2' (0130's check admits it); no item has meta > 0 (0132).
--   * The ten specialisation skills (0131 / 0151) appear in no skill_requirements row.
--   * A workshop makes whatever its tier allows: nothing says "made only in this city".
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) THE 22 T2 HULLS — scripts/build-ships.mjs (the SAME generator as 0135 / 0138: archetype × line ×
--     ONE T2 uplift by role — trade hold × 1.15, hull × 1.10, armour +4, +1 Low; combat attack × 1.25,
--     hull × 1.10, armour +6, accuracy +4, +1 High; explorer speed × 1.06, handling +6, sighting +3,
--     +1 Mid; support hull × 1.20, +1 Low; deck + the added rack's deck × size; labour × 2.5; goods
--     × 1.6 + copper sheet — and two support archetypes solved from §4.3). `--sql C`, pasted.
--     Where §4.3's drafted table disagrees with the one rule (15 of 594 cells: the four heavies' goods
--     and labour, which the SHED rule of 0072 (d) scales as it did Wave B's flagships; the six light
--     combat decks; one labour rounding) the generator is the authority and the table is re-cut from it.
-- (2) THE REQUIREMENTS (§4.4): a T2 hull needs the line's ⟨size⟩ Hulls V + the role's T2
--     specialisation I (44 rows). A T2 module needs its module skill V + its specialisation I (+ the
--     base type's second skill); a Named item what its grade needs (59 item rows).
-- (3) THE GEAR — scripts/build-gear.mjs: 22 T2 modules (one per base type but the figurehead; buys ×
--     2.60, speed and cargo space × 1.80, spends × 1.25; Deck and Hands × 1.5; grade 5, meta 5; made at
--     a tier-3 workshop) and 12 NAMED items (a city's own pattern of one grade: its buys × 1.10, Deck − 1,
--     the grade's recipe + one good of the city; meta 1) — item_kinds, item_profile, item_effects,
--     item_recipes, item_use (0158's: what works each, by its base type). `--sql-0159`, pasted.
-- (4) A NAMED ITEM IS MADE ONLY IN ITS CITY: public.item_city (item, port) — the one home of it, 12
--     rows, held by the world guard — read by ONE sentence, public.made_only_in(item, port) ("Lisbon-cast
--     Brass Guns is made only in Lisbon", or null): cmd.do_make refuses with it (E_NOT_MADE_HERE) and
--     world.workstation folds it into `makeable` and serves it as `made_only_in` (only where it applies).
-- (5) world.building_yard serves a hull's `tech` where it is not T1 (the yard's T2 badge); a T1 hull's
--     entry is its pre-image.
--
-- ── WHAT IT DELIBERATELY DOES NOT DO ────────────────────────────────────────────────────────────
-- No row already in the world moves (hashed); no knob, no entry point, no client write, no cron, no FK,
-- no ALTER. Dark (skills_bite false): every new hull and every new item HAS requirements, so public.
-- requirements_unmet (0135's dark rule) closes all 56 to everyone — refused E_NEEDS_SKILL with " — ship
-- skills are not in use yet". Merchants: nothing (they sail the live three with G1 gear). Country, set
-- and famous gear are S16 / S17. Said plainly, the felt change while dark: the Codex and the build yard
-- list 92 hulls (the 22 T2 badged and refused with their needs), the workshop lists 185 items (the 34 new
-- refused with their needs; a Named item away from its city also says where it is made).
--
-- ── LOCKS ───────────────────────────────────────────────────────────────────────────────────────
-- Heavy reads first. Then only ROW EXCLUSIVE on catalogue tables nothing live writes (ship_classes,
-- class_profile, class_slots, class_cabins, hull_recipes(+goods), item_kinds, item_profile, item_effects,
-- item_recipes, item_use, skill_requirements) and a new table; their FK checks take KEY SHARE on goods /
-- skills / ship_lines rows. ANALYZE takes SHARE UPDATE EXCLUSIVE. CREATE OR REPLACE FUNCTION locks no
-- table. Probe writes are rolled back; a probe that meets a lock is retried 5 × 0.2 s, then LOCK
-- CONTENTION. No top-level LOCK / SET LOCAL / BEGIN / SET ROLE.
--
-- SUPERSEDES, by hunks sliced from the LIVE bodies (LF-normalised), each asserted to occur exactly once
-- and to reverse to its pre-image, ACL / volatility / definer / config unchanged: cmd.do_make (0135),
-- world.workstation (0135), world.building_yard (0154).
--
-- ROLLBACK (forward migration): reverse the three bodies' hunks (old text in hunks_0159); drop
-- public.made_only_in and public.item_city; delete the rows of the 22 hull codes and the 34 item codes
-- (skill_requirements, item_use, item_recipes, item_effects, item_profile, item_kinds; hull_recipe_goods,
-- hull_recipes, class_cabins, class_slots, class_profile, ship_classes) after asserting no ship,
-- fitted_units or player_items row names one (dark, none can).
-- VERSION: 0159 (provisional; renumbered to head + 1 at deploy). Applies on 0158 (S13).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  perform set_config('random_page_cost', '1.1', true);   -- prod's planner page cost (0149's header)
end $guard$;

-- ── 0. HELPERS (pg_temp, gone at commit) ───────────────────────────────────────────────────────
create or replace function pg_temp.occurs_0159(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- One verb through its door, undone at once: 'ok:<ducats paid>' or 'E_CODE: sentence|<detail>'. A lock
-- the live world holds is not an answer: retried, then LOCK CONTENTION.
create or replace function pg_temp.try_0159(p_player uuid, p_sql text)
returns text
language plpgsql
as $$
declare
  v_msg   text;
  v_det   text;
  v_state text;
  v_try   int := 0;
  v_paid  bigint;
begin
  loop
    v_try := v_try + 1;
    v_msg := null; v_det := null; v_state := null;
    begin
      v_paid := (select ducats from public.players where id = p_player);
      execute p_sql;
      v_paid := v_paid - (select ducats from public.players where id = p_player);
      raise exception 'PROBE_UNDO_0159:%', v_paid;
    exception when others then
      get stacked diagnostics v_msg = message_text, v_state = returned_sqlstate, v_det = pg_exception_detail;
    end;
    exit when v_state not in ('55P03', '40P01');
    if v_try >= 5 then
      raise exception '0159 self-assert FAIL: LOCK CONTENTION, not a result — % could not get its locks in 5 tries (%: %). Re-run the push.',
        p_sql, v_state, v_msg;
    end if;
    perform pg_sleep(0.2);
  end loop;
  return case when v_msg like 'PROBE_UNDO_0159:%' then 'ok:' || split_part(v_msg, ':', 2)
              else v_msg || case when coalesce(v_det, '') <> '' then '|' || v_det else '' end end;
end $$;

-- act as a company's signed-in user (a workshop serves what YOU may make) — or as nobody
create or replace function pg_temp.as_0159(p_uid uuid)
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  perform set_config('request.jwt.claims', case when p_uid is null then '' else json_build_object('sub', p_uid)::text end, true);
end $$;

create temp table reads_0159 (phase text, what text, hulls bigint, ms numeric) on commit drop;
create or replace function pg_temp.time_reads_0159(p_phase text)
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
  insert into reads_0159 values (p_phase, 'speed+hold', coalesce(cardinality(v_ids), 0), round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
  v_t0 := clock_timestamp();
  perform world.ship_view(x) from unnest(v_ids) x;
  insert into reads_0159 values (p_phase, 'ship_view', coalesce(cardinality(v_ids), 0), round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
end $$;

-- ── 1. THE PRE-IMAGES (every heavy read happens here, before any write) ─────────────────────────
create temp table defs_before_0159 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('cmd.do_make(uuid, jsonb)'), ('world.workstation(uuid, uuid)'), ('world.building_yard(uuid)')) f(fn);

create temp table live_classes_0159 on commit drop as select code from public.ship_classes;
create temp table live_items_0159 on commit drop as select code from public.item_kinds;

create temp table before_0159 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from public.ship_classes) as classes,
       (select count(*) from public.class_slots) as slots,
       (select count(*) from public.hull_recipe_goods) as recipe_goods,
       (select count(*) from public.item_kinds) as kinds,
       (select count(*) from public.item_effects) as effects,
       (select count(*) from public.item_recipes) as item_recipes,
       (select count(*) from public.item_use) as uses,
       (select count(*) from public.skill_requirements where subject_kind = 'hull') as hull_requirements,
       (select count(*) from public.skill_requirements where subject_kind = 'item') as item_requirements,
       (select md5(string_agg(to_jsonb(c)::text, '|' order by c.code)) from public.ship_classes c) as classes_hash,
       (select md5(string_agg(to_jsonb(c)::text, '|' order by c.class_code)) from public.class_profile c) as profile_hash,
       (select md5(string_agg(to_jsonb(c)::text, '|' order by c.class_code, c.slot)) from public.class_slots c) as slots_hash,
       (select md5(string_agg(to_jsonb(c)::text, '|' order by c.class_code)) from public.class_cabins c) as cabins_hash,
       (select md5(string_agg(to_jsonb(c)::text, '|' order by c.class_code)) from public.hull_recipes c) as recipes_hash,
       (select md5(string_agg(to_jsonb(c)::text, '|' order by c.class_code, c.good_id)) from public.hull_recipe_goods c) as recipe_goods_hash,
       (select md5(string_agg(to_jsonb(c)::text, '|' order by c.subject_kind, c.subject_code, c.skill_code)) from public.skill_requirements c) as requirements_hash,
       (select md5(string_agg(to_jsonb(c)::text, '|' order by c.code)) from public.item_kinds c) as kinds_hash,
       (select md5(string_agg(to_jsonb(c)::text, '|' order by c.item_code)) from public.item_profile c) as iprofile_hash,
       (select md5(string_agg(to_jsonb(c)::text, '|' order by c.item_code, c.stat)) from public.item_effects c) as effects_hash,
       (select md5(string_agg(format('%s/%s/%s', c.item_code, c.good_id, c.qty), '|' order by c.item_code, c.good_id)) from public.item_recipes c) as item_recipes_hash,
       (select md5(string_agg(to_jsonb(c)::text, '|' order by c.item_code)) from public.item_use c) as use_hash;

-- what the build yards and the workshops serve, as found (no company: the migration has no auth.uid())
create temp table yards_before_0159 on commit drop as
select b.port_id, h.value->>'class' as class, h.value as entry
  from public.port_buildings b
 cross join lateral jsonb_array_elements(world.building_yard(b.port_id)->'hulls') h
 where b.kind = 'building_yard';
create temp table shops_before_0159 on commit drop as
select b.port_id, i.value->>'code' as code, i.value as entry
  from public.port_buildings b
 cross join lateral jsonb_array_elements(world.workstation(b.port_id)->'items') i
 where b.kind = 'workstation';

select pg_temp.time_reads_0159('before');

-- ── 2. THE 22 T2 HULLS (scripts/build-ships.mjs --sql C, verbatim) ──────────────────────────────
insert into public.ship_classes
  (code, name, family, rig, hold, crew_required, crew_max, speed_kn, durability, guns, draft,
   build_hours, build_cost, tier, handling, armour, attack, accuracy, reach, sighting) values
  ('carvarm', 'Caravela de armada', 'Western', 'mixed', 70, 28, 90, 6.60, 530, 6, 1, 40.00, 80000.00, 2, 88, 14, 60, 42, 30, 11.0),
  ('nauguerra', 'Nau de guerra', 'Western', 'square', 280, 70, 180, 4.80, 2040, 10, 3, 96.00, 300000.00, 3, 52, 34, 100, 55, 60, 14.0),
  ('galplata', 'Galeón de la Plata', 'Western', 'square', 690, 92, 230, 4.20, 3040, 13, 4, 144.00, 544000.00, 4, 36, 42, 130, 50, 69, 13.0),
  ('dunkirk', 'Fragata de Dunquerque', 'Western', 'square', 70, 32, 103, 6.30, 610, 7, 1, 40.00, 88000.00, 2, 84, 20, 70, 42, 34, 11.0),
  ('armfluit', 'Gewapende fluit', 'Western', 'square', 575, 45, 105, 4.30, 1780, 9, 2, 96.00, 256000.00, 3, 47, 30, 90, 55, 70, 14.0),
  ('kaper', 'Kaperschip', 'Western', 'square', 90, 21, 68, 6.50, 480, 5, 1, 40.00, 68000.00, 2, 90, 10, 50, 42, 30, 11.0),
  ('qpinnace', 'Queen''s Pinnace', 'Western', 'mixed', 32, 6, 16, 7.10, 280, 0, 1, 24.00, 26000.00, 1, 98, 2, 0, 0, 28, 13.0),
  ('armmerch', 'Armed Merchantman', 'Western', 'square', 425, 60, 140, 4.60, 1880, 13, 3, 96.00, 316000.00, 3, 51, 32, 130, 63, 78, 14.0),
  ('fregcourse', 'Frégate de course', 'Western', 'square', 70, 28, 90, 6.90, 530, 7, 1, 40.00, 84000.00, 2, 92, 14, 70, 46, 30, 12.0),
  ('fluteroy', 'Flûte royale', 'Western', 'square', 460, 60, 140, 4.60, 1980, 13, 3, 96.00, 316000.00, 3, 49, 34, 130, 59, 70, 15.0),
  ('galbast', 'Galea bastarda', 'Mediterranean', 'oared', 270, 122, 297, 4.80, 2090, 24, 2, 96.00, 374000.00, 3, 58, 40, 240, 64, 62, 14.0),
  ('carcarm', 'Caracca armata', 'Mediterranean', 'square', 620, 108, 270, 4.40, 2510, 13, 3, 144.00, 546000.00, 4, 48, 36, 130, 52, 55, 13.0),
  ('korsan', 'Korsan şebeği', 'Mediterranean', 'lateen', 65, 35, 112, 6.50, 580, 7, 1, 40.00, 80000.00, 2, 90, 18, 70, 42, 26, 11.0),
  ('mavna', 'Mavna', 'Mediterranean', 'oared', 455, 125, 325, 4.40, 3560, 18, 4, 144.00, 532000.00, 4, 46, 48, 180, 60, 66, 14.0),
  ('batil', 'Batil', 'Indian Ocean', 'lateen', 38, 5, 14, 7.10, 320, 0, 1, 24.00, 20000.00, 1, 96, 2, 0, 0, 10, 14.0),
  ('ghurabj', 'Ghurab-i-jang', 'Indian Ocean', 'lateen', 75, 24, 76, 6.90, 550, 4, 1, 40.00, 68000.00, 2, 92, 12, 40, 32, 20, 12.0),
  ('zhanchuan', 'Zhanchuan', 'East Asian', 'lateen', 345, 90, 220, 4.60, 2640, 19, 3, 96.00, 306000.00, 3, 42, 46, 190, 58, 72, 14.0),
  ('haicang', 'Haicang', 'East Asian', 'lateen', 795, 80, 200, 4.20, 3170, 10, 4, 144.00, 442000.00, 4, 32, 42, 100, 46, 65, 13.0),
  ('murakami', 'Murakami kobaya', 'East Asian', 'oared', 27, 16, 46, 6.20, 370, 3, 1, 24.00, 36000.00, 1, 88, 14, 30, 40, 22, 10.0),
  ('oshuin', 'Ō-shuinsen', 'East Asian', 'square', 415, 69, 161, 4.40, 1880, 13, 3, 96.00, 300000.00, 3, 49, 36, 130, 61, 62, 15.0),
  ('tamang', 'Tamangseon', 'East Asian', 'oared', 32, 7, 18, 6.60, 330, 0, 1, 24.00, 24000.00, 1, 94, 14, 0, 0, 20, 13.0),
  ('bangpae', 'Bangpaeseon', 'East Asian', 'oared', 270, 99, 242, 4.70, 2420, 23, 3, 96.00, 340000.00, 3, 52, 50, 230, 66, 72, 14.0)
on conflict (code) do nothing;

insert into public.class_profile (class_code, line_code, size, role, tech, deck, any_yard) values
  ('carvarm', 'PRT', 2, 'combat', 'T2', 34, false),
  ('nauguerra', 'PRT', 3, 'support', 'T2', 66, false),
  ('galplata', 'ESP', 4, 'trade', 'T2', 84, false),
  ('dunkirk', 'ESP', 2, 'combat', 'T2', 34, false),
  ('armfluit', 'NLD', 3, 'trade', 'T2', 65, false),
  ('kaper', 'NLD', 2, 'combat', 'T2', 34, false),
  ('qpinnace', 'ENG', 1, 'explorer', 'T2', 12, false),
  ('armmerch', 'ENG', 3, 'trade', 'T2', 65, false),
  ('fregcourse', 'FRA', 2, 'combat', 'T2', 34, false),
  ('fluteroy', 'FRA', 3, 'trade', 'T2', 65, false),
  ('galbast', 'ITA', 3, 'combat', 'T2', 71, false),
  ('carcarm', 'ITA', 4, 'trade', 'T2', 84, false),
  ('korsan', 'OTT', 2, 'combat', 'T2', 34, false),
  ('mavna', 'OTT', 4, 'support', 'T2', 89, false),
  ('batil', 'IND', 1, 'explorer', 'T2', 12, false),
  ('ghurabj', 'IND', 2, 'combat', 'T2', 34, false),
  ('zhanchuan', 'CHN', 3, 'combat', 'T2', 71, false),
  ('haicang', 'CHN', 4, 'trade', 'T2', 84, false),
  ('murakami', 'JPN', 1, 'combat', 'T2', 18, false),
  ('oshuin', 'JPN', 3, 'trade', 'T2', 65, false),
  ('tamang', 'KOR', 1, 'explorer', 'T2', 12, false),
  ('bangpae', 'KOR', 3, 'combat', 'T2', 71, false)
on conflict (class_code) do nothing;

insert into public.class_slots (class_code, slot, count) values
  ('carvarm', 'high', 3),
  ('carvarm', 'mid', 4),
  ('carvarm', 'refit', 1),
  ('nauguerra', 'high', 3),
  ('nauguerra', 'mid', 5),
  ('nauguerra', 'low', 3),
  ('nauguerra', 'refit', 2),
  ('nauguerra', 'flourish', 1),
  ('galplata', 'high', 3),
  ('galplata', 'mid', 6),
  ('galplata', 'low', 3),
  ('galplata', 'refit', 2),
  ('galplata', 'flourish', 1),
  ('dunkirk', 'high', 3),
  ('dunkirk', 'mid', 4),
  ('dunkirk', 'refit', 1),
  ('armfluit', 'high', 3),
  ('armfluit', 'mid', 5),
  ('armfluit', 'low', 2),
  ('armfluit', 'refit', 2),
  ('armfluit', 'flourish', 1),
  ('kaper', 'high', 3),
  ('kaper', 'mid', 4),
  ('kaper', 'refit', 1),
  ('qpinnace', 'high', 1),
  ('qpinnace', 'mid', 4),
  ('armmerch', 'high', 3),
  ('armmerch', 'mid', 5),
  ('armmerch', 'low', 2),
  ('armmerch', 'refit', 2),
  ('armmerch', 'flourish', 1),
  ('fregcourse', 'high', 3),
  ('fregcourse', 'mid', 4),
  ('fregcourse', 'refit', 1),
  ('fluteroy', 'high', 3),
  ('fluteroy', 'mid', 5),
  ('fluteroy', 'low', 2),
  ('fluteroy', 'refit', 2),
  ('fluteroy', 'flourish', 1),
  ('galbast', 'high', 5),
  ('galbast', 'mid', 5),
  ('galbast', 'low', 1),
  ('galbast', 'refit', 2),
  ('galbast', 'flourish', 1),
  ('carcarm', 'high', 3),
  ('carcarm', 'mid', 6),
  ('carcarm', 'low', 3),
  ('carcarm', 'refit', 2),
  ('carcarm', 'flourish', 1),
  ('korsan', 'high', 3),
  ('korsan', 'mid', 4),
  ('korsan', 'refit', 1),
  ('mavna', 'high', 4),
  ('mavna', 'mid', 6),
  ('mavna', 'low', 3),
  ('mavna', 'refit', 2),
  ('mavna', 'flourish', 1),
  ('batil', 'high', 1),
  ('batil', 'mid', 4),
  ('ghurabj', 'high', 3),
  ('ghurabj', 'mid', 4),
  ('ghurabj', 'refit', 1),
  ('zhanchuan', 'high', 5),
  ('zhanchuan', 'mid', 5),
  ('zhanchuan', 'low', 1),
  ('zhanchuan', 'refit', 2),
  ('zhanchuan', 'flourish', 1),
  ('haicang', 'high', 3),
  ('haicang', 'mid', 6),
  ('haicang', 'low', 3),
  ('haicang', 'refit', 2),
  ('haicang', 'flourish', 1),
  ('murakami', 'high', 3),
  ('murakami', 'mid', 2),
  ('oshuin', 'high', 3),
  ('oshuin', 'mid', 5),
  ('oshuin', 'low', 2),
  ('oshuin', 'refit', 2),
  ('oshuin', 'flourish', 1),
  ('tamang', 'high', 1),
  ('tamang', 'mid', 4),
  ('bangpae', 'high', 5),
  ('bangpae', 'mid', 5),
  ('bangpae', 'low', 1),
  ('bangpae', 'refit', 2),
  ('bangpae', 'flourish', 1)
on conflict (class_code, slot) do nothing;

insert into public.class_cabins (class_code, cabins) values
  ('carvarm', 4),
  ('nauguerra', 5),
  ('galplata', 6),
  ('dunkirk', 4),
  ('armfluit', 5),
  ('kaper', 4),
  ('qpinnace', 3),
  ('armmerch', 5),
  ('fregcourse', 4),
  ('fluteroy', 5),
  ('galbast', 5),
  ('carcarm', 6),
  ('korsan', 4),
  ('mavna', 6),
  ('batil', 3),
  ('ghurabj', 4),
  ('zhanchuan', 5),
  ('haicang', 6),
  ('murakami', 3),
  ('oshuin', 5),
  ('tamang', 3),
  ('bangpae', 5)
on conflict (class_code) do nothing;

insert into public.hull_recipes (class_code, yard_tier, ducats, note) values
  ('carvarm', 2, 20000, 'The armed caravel of the Portuguese fleets, sheathed in copper and given a heavier battery.'),
  ('nauguerra', 3, 75000, 'A nau built for the fleet rather than the cargo: stout, well armed and able to keep a convoy together.'),
  ('galplata', 3, 136000, 'The silver galleon of the treasure fleets, built to carry bullion home under heavy guns.'),
  ('dunkirk', 2, 22000, 'The fast Dunkirk frigate of the Flanders privateers, built for the chase.'),
  ('armfluit', 3, 64000, 'A fluit with a proper gun deck for the dangerous routes, keeping most of its cargo space.'),
  ('kaper', 2, 17000, 'A Dutch privateer, fast and lightly built, with more hold than most fighting hulls.'),
  ('qpinnace', 1, 6500, 'A royal pinnace of the English navy, the fastest small scout afloat.'),
  ('armmerch', 3, 79000, 'An English merchant built to fight its way through, with a stout hull and a full broadside.'),
  ('fregcourse', 2, 21000, 'A French privateer frigate from Saint-Malo, quick and handy with a sharp battery.'),
  ('fluteroy', 3, 79000, 'The royal store ship of the French navy, a roomy hull built to naval standards.'),
  ('galbast', 3, 93500, 'The heavy Mediterranean war galley: more oars, more soldiers and a heavier bow battery than the sottile.'),
  ('carcarm', 3, 136500, 'An armed Genoese carrack, built to carry a rich cargo through pirate waters.'),
  ('korsan', 2, 20000, 'The Barbary corsair xebec: a fast lateen raider with a heavier battery than the common şebek.'),
  ('mavna', 3, 133000, 'The great Ottoman mahone, a heavy oared hull that carries guns, troops and stores for the fleet.'),
  ('batil', 1, 5000, 'A fast Arabian batil, a long sharp hull for scouting and the pearl banks.'),
  ('ghurabj', 2, 17000, 'The war ghurab of the Malabar fleets, with a heavier bow gun and copper below the waterline.'),
  ('zhanchuan', 3, 76500, 'The Ming war junk proper, built heavier and gunned harder than the coastal patrol ships.'),
  ('haicang', 3, 110500, 'The great ocean trader of the Zhangzhou junks, deep in the hold and hard to sink.'),
  ('murakami', 1, 9000, 'The war boat of the Murakami sea lords of the Inland Sea, fast and crowded with fighters.'),
  ('oshuin', 3, 75000, 'A great red-seal ship for the long runs to Siam and Luzon, built bigger and stouter.'),
  ('tamang', 1, 6000, 'The Joseon scout boat of the coastal watch, fast under oars with a sharp lookout.'),
  ('bangpae', 3, 85000, 'A Joseon warship with a shielded upper deck, the forerunner of the panokseon.')
on conflict (class_code) do nothing;

create temp table hull_goods_0159 (class_code text, good_code text, qty numeric) on commit drop;
insert into hull_goods_0159 values
  ('carvarm', 'timber', 112),
  ('carvarm', 'naval-timber', 32),
  ('carvarm', 'tar', 19),
  ('carvarm', 'cordage', 16),
  ('carvarm', 'ships-nails', 29),
  ('carvarm', 'copper-sheet', 10),
  ('nauguerra', 'live-oak', 144),
  ('nauguerra', 'naval-timber', 64),
  ('nauguerra', 'timber', 96),
  ('nauguerra', 'tar', 40),
  ('nauguerra', 'ships-nails', 64),
  ('nauguerra', 'copper-sheet', 10),
  ('galplata', 'live-oak', 184),
  ('galplata', 'naval-timber', 82),
  ('galplata', 'timber', 122),
  ('galplata', 'tar', 51),
  ('galplata', 'ships-nails', 82),
  ('galplata', 'copper-sheet', 11),
  ('dunkirk', 'timber', 112),
  ('dunkirk', 'naval-timber', 32),
  ('dunkirk', 'tar', 19),
  ('dunkirk', 'cordage', 16),
  ('dunkirk', 'ships-nails', 29),
  ('dunkirk', 'copper-sheet', 10),
  ('armfluit', 'timber', 240),
  ('armfluit', 'memel-fir', 64),
  ('armfluit', 'stockholm-tar', 40),
  ('armfluit', 'ships-nails', 64),
  ('armfluit', 'copper-sheet', 10),
  ('kaper', 'timber', 112),
  ('kaper', 'memel-fir', 32),
  ('kaper', 'stockholm-tar', 19),
  ('kaper', 'cordage', 16),
  ('kaper', 'ships-nails', 29),
  ('kaper', 'copper-sheet', 10),
  ('qpinnace', 'timber', 64),
  ('qpinnace', 'tar', 13),
  ('qpinnace', 'cordage', 10),
  ('qpinnace', 'ships-nails', 16),
  ('qpinnace', 'copper-sheet', 10),
  ('armmerch', 'timber', 240),
  ('armmerch', 'naval-timber', 64),
  ('armmerch', 'tar', 40),
  ('armmerch', 'ships-nails', 64),
  ('armmerch', 'copper-sheet', 10),
  ('fregcourse', 'timber', 112),
  ('fregcourse', 'naval-timber', 32),
  ('fregcourse', 'tar', 19),
  ('fregcourse', 'canvas-duck', 16),
  ('fregcourse', 'ships-nails', 29),
  ('fregcourse', 'copper-sheet', 10),
  ('fluteroy', 'timber', 240),
  ('fluteroy', 'naval-timber', 64),
  ('fluteroy', 'tar', 40),
  ('fluteroy', 'ships-nails', 64),
  ('fluteroy', 'copper-sheet', 10),
  ('galbast', 'timber', 240),
  ('galbast', 'naval-timber', 64),
  ('galbast', 'tar', 40),
  ('galbast', 'ships-nails', 64),
  ('galbast', 'copper-sheet', 10),
  ('carcarm', 'timber', 307),
  ('carcarm', 'naval-timber', 82),
  ('carcarm', 'tar', 51),
  ('carcarm', 'ships-nails', 82),
  ('carcarm', 'copper-sheet', 11),
  ('korsan', 'timber', 112),
  ('korsan', 'cedar', 32),
  ('korsan', 'tar', 19),
  ('korsan', 'cordage', 16),
  ('korsan', 'ships-nails', 29),
  ('korsan', 'copper-sheet', 10),
  ('mavna', 'timber', 307),
  ('mavna', 'cedar', 82),
  ('mavna', 'tar', 51),
  ('mavna', 'ships-nails', 82),
  ('mavna', 'copper-sheet', 11),
  ('batil', 'teak', 64),
  ('batil', 'coir', 23),
  ('batil', 'coco-fibre', 16),
  ('batil', 'copper-sheet', 10),
  ('ghurabj', 'teak', 144),
  ('ghurabj', 'coir', 35),
  ('ghurabj', 'coco-fibre', 29),
  ('ghurabj', 'copper-sheet', 10),
  ('zhanchuan', 'timber', 304),
  ('zhanchuan', 'tar', 40),
  ('zhanchuan', 'ships-nails', 64),
  ('zhanchuan', 'copper-sheet', 10),
  ('haicang', 'timber', 390),
  ('haicang', 'tar', 51),
  ('haicang', 'ships-nails', 82),
  ('haicang', 'copper-sheet', 11),
  ('murakami', 'timber', 64),
  ('murakami', 'tar', 13),
  ('murakami', 'cordage', 10),
  ('murakami', 'iron', 16),
  ('murakami', 'copper-sheet', 10),
  ('oshuin', 'timber', 304),
  ('oshuin', 'tar', 40),
  ('oshuin', 'iron', 64),
  ('oshuin', 'copper-sheet', 10),
  ('tamang', 'timber', 64),
  ('tamang', 'tar', 13),
  ('tamang', 'cordage', 10),
  ('tamang', 'iron', 16),
  ('tamang', 'copper-sheet', 10),
  ('bangpae', 'timber', 304),
  ('bangpae', 'tar', 40),
  ('bangpae', 'iron', 64),
  ('bangpae', 'copper-sheet', 10);
insert into public.hull_recipe_goods (class_code, good_id, qty)
select w.class_code, g.id, w.qty from hull_goods_0159 w join public.goods g on g.code = w.good_code
on conflict (class_code, good_id) do nothing;

insert into public.skill_requirements (subject_kind, subject_code, skill_code, level) values
  ('hull', 'carvarm', 'PRT_LIGHT', 5),
  ('hull', 'carvarm', 'PRIVATEERS', 1),
  ('hull', 'nauguerra', 'PRT_MEDIUM', 5),
  ('hull', 'nauguerra', 'CONVOY_ESCORTS', 1),
  ('hull', 'galplata', 'ESP_HEAVY', 5),
  ('hull', 'galplata', 'ARMED_MERCHANT', 1),
  ('hull', 'dunkirk', 'ESP_LIGHT', 5),
  ('hull', 'dunkirk', 'PRIVATEERS', 1),
  ('hull', 'armfluit', 'NLD_MEDIUM', 5),
  ('hull', 'armfluit', 'ARMED_MERCHANT', 1),
  ('hull', 'kaper', 'NLD_LIGHT', 5),
  ('hull', 'kaper', 'PRIVATEERS', 1),
  ('hull', 'qpinnace', 'ENG_SMALL', 5),
  ('hull', 'qpinnace', 'SURVEY_SHIPS', 1),
  ('hull', 'armmerch', 'ENG_MEDIUM', 5),
  ('hull', 'armmerch', 'ARMED_MERCHANT', 1),
  ('hull', 'fregcourse', 'FRA_LIGHT', 5),
  ('hull', 'fregcourse', 'PRIVATEERS', 1),
  ('hull', 'fluteroy', 'FRA_MEDIUM', 5),
  ('hull', 'fluteroy', 'ARMED_MERCHANT', 1),
  ('hull', 'galbast', 'ITA_MEDIUM', 5),
  ('hull', 'galbast', 'PRIVATEERS', 1),
  ('hull', 'carcarm', 'ITA_HEAVY', 5),
  ('hull', 'carcarm', 'ARMED_MERCHANT', 1),
  ('hull', 'korsan', 'OTT_LIGHT', 5),
  ('hull', 'korsan', 'PRIVATEERS', 1),
  ('hull', 'mavna', 'OTT_HEAVY', 5),
  ('hull', 'mavna', 'CONVOY_ESCORTS', 1),
  ('hull', 'batil', 'IND_SMALL', 5),
  ('hull', 'batil', 'SURVEY_SHIPS', 1),
  ('hull', 'ghurabj', 'IND_LIGHT', 5),
  ('hull', 'ghurabj', 'PRIVATEERS', 1),
  ('hull', 'zhanchuan', 'CHN_MEDIUM', 5),
  ('hull', 'zhanchuan', 'PRIVATEERS', 1),
  ('hull', 'haicang', 'CHN_HEAVY', 5),
  ('hull', 'haicang', 'ARMED_MERCHANT', 1),
  ('hull', 'murakami', 'JPN_SMALL', 5),
  ('hull', 'murakami', 'PRIVATEERS', 1),
  ('hull', 'oshuin', 'JPN_MEDIUM', 5),
  ('hull', 'oshuin', 'ARMED_MERCHANT', 1),
  ('hull', 'tamang', 'KOR_SMALL', 5),
  ('hull', 'tamang', 'SURVEY_SHIPS', 1),
  ('hull', 'bangpae', 'KOR_MEDIUM', 5),
  ('hull', 'bangpae', 'PRIVATEERS', 1)
on conflict (subject_kind, subject_code, skill_code) do nothing;

-- ── 3. THE 34 ITEMS (scripts/build-gear.mjs --sql-0159, verbatim) ───────────────────────────────
insert into public.item_kinds (code, name, slot, buys, spends, note, volume, ws_tier) values
  ('long-eighteens', 'Long Eighteens', 'weapon', 'Attack, Reach', 'Hold, Handling', 'Long guns bored for an eighteen-pound ball: the heaviest broadside a trader can mount, and it costs more cargo space and handling.', 6, 3),
  ('gunnades', 'Gunnades', 'weapon', 'Attack at close range', 'Reach, Cargo space, Handling', 'A cross between a gun and a carronade: it smashes at close range and keeps a little more reach.', 5, 3),
  ('long-nines', 'Long Nines', 'weapon', 'Reach, Accuracy', 'Cargo space', 'Nine-pounder chase guns of the longest pattern: they reach and aim further than any broadside piece.', 4, 3),
  ('pateraros', 'Pateraros', 'weapon', 'Attack, Accuracy', 'Handling', 'Breech-loading swivels with spare chambers: they fire faster and truer than a plain swivel.', 2, 3),
  ('grenadoes-and-cutlasses', 'Grenadoes & Cutlasses', 'weapon', 'Attack at close quarters', 'Reach', 'Grenades, cutlasses and a falconet in the top: a boarding party that clears a deck before it crosses.', 3, 3),
  ('hanging-magazine', 'Hanging Magazine', 'weapon', 'Attack sustain, Accuracy', 'Hold, Durability', 'A powder room hung clear of the hull on iron knees and lined in copper: dry powder and a steadier rate of fire.', 4, 3),
  ('racing-courses', 'Racing Courses', 'rig', 'Speed', 'Handling', 'Courses and topsails cut flat and full for speed: the fastest suit a ship can carry, and a handful to work.', 4, 3),
  ('flying-jib', 'Flying Jib & Jibboom', 'rig', 'Handling, and a little Speed', 'Durability', 'A jibboom run out beyond the bowsprit with a flying jib on it: the ship turns quicker and gains a little way.', 3, 3),
  ('royal-stunsails', 'Royal Stunsails', 'rig', 'Speed', 'Handling, Hull', 'Studding sails set right up to the royals: a great deal more speed in fair weather, and a great deal more to tear.', 4, 3),
  ('storm-trysails', 'Storm Trysails', 'rig', 'Hull, Handling', 'Speed', 'Small trysails on their own gaffs, cut from the heaviest cloth: the ship lies to in the worst weather and loses a little speed.', 3, 3),
  ('wheel-steered-rudder', 'Wheel-steered Rudder', 'steering', 'Handling', 'Hold', 'A ship''s wheel and tiller ropes on a greenheart rudder: the helmsman has more purchase and the ship answers at once.', 3, 3),
  ('geared-whipstaff', 'Rowle-geared Whipstaff', 'steering', 'Handling', 'Cargo space', 'A whipstaff turning in a brass rowle with iron gearing: more rudder for the same push.', 2, 3),
  ('admiralty-anchor', 'Admiralty-pattern Anchor', 'ground-tackle', 'Weather-holding, and a faster turnaround in port', 'Hold', 'An anchor of the improved pattern with a longer shank and curved arms: it bites in any ground and weighs a little more.', 4, 3),
  ('bower-and-sheet-anchors', 'Bower & Sheet Anchors', 'ground-tackle', 'Hull in a storm, Handling', 'Cargo space', 'A sheet anchor and a best bower carried together: the ship rides out almost any night, at a cost in cargo space.', 5, 3),
  ('geared-capstan', 'Geared Capstan', 'ground-tackle', 'Handling, a little Speed', 'Cargo space', 'A capstan geared so one crew heaves like two: the anchor comes up fast and the yards faster.', 3, 3),
  ('night-glass', 'Night Glass & Royal Mast', 'lookout', 'Sighting', 'Handling', 'A royal mast with a night glass at its head: the lookout sees further by day and something by night.', 2, 3),
  ('azimuth-compass', 'Azimuth Compass & Rutter', 'lookout', 'Sighting, Handling', 'Cargo space', 'An azimuth compass and a written rutter of every coast: the ship knows its bearing and what lies ahead.', 2, 3),
  ('trimmed-kentledge', 'Trimmed Kentledge', 'hull', 'Handling, Armour', 'Speed', 'Kentledge cast to the hull and trimmed by a shipwright: the stiffest ship afloat, and a slower one.', 2, 3),
  ('copper-bolted-sheathing', 'Copper-bolted Sheathing', 'hull', 'Armour, Durability', 'Speed', 'Copper sheathing fastened with copper bolts over greenheart, so the iron below does not rot away: the hardest bottom made.', 5, 3),
  ('diagonal-planking', 'Diagonal Planking', 'hull', 'Armour, Hull', 'Speed, Cargo space', 'A second skin of greenheart laid diagonally over the frames: the hull stops working in a sea and takes far more shot.', 4, 3),
  ('bentinck-pumps', 'Bentinck Chain Pumps', 'hull', 'Hull', 'Cargo space', 'Chain pumps of the improved pattern, worked by fewer hands and moving far more water.', 3, 3),
  ('orlop-stowage', 'Orlop Stowage', 'hull', 'Hold', 'Speed, Handling', 'An orlop deck laid over greenheart frames so cargo stows on two levels: the most cargo space a hull can give, and a slower ship.', 3, 3),
  ('lisbon-cast-brass-guns', 'Lisbon-cast Brass Guns', 'weapon', 'Attack, Reach', 'Hold, Handling', 'Brass guns cast in the Lisbon foundry and proved with slow-match: a little more weight of fire than other brass guns.', 6, 3),
  ('arsenale-rudder', 'Arsenale Rudder & Helm', 'steering', 'Handling', 'Hold', 'A teak rudder hung on brass pintles in the Venetian Arsenale way: the ship turns a little sharper.', 3, 3),
  ('genoese-anchor', 'Genoese Anchor & Cable', 'ground-tackle', 'Weather-holding, and a faster turnaround in port', 'Hold', 'A bar-iron anchor on a cable laid from Ligurian hemp as well as Manila: the ship rides easier and swings quicker.', 4, 3),
  ('antwerp-duck-canvas', 'Antwerp Duck Canvas', 'rig', 'Speed', 'Handling', 'Duck canvas lined with Flemish linen at the seams, as the Antwerp sailmakers cut it: a little more speed from the same wind.', 4, 3),
  ('elbe-frames', 'Elbe Frames', 'hull', 'Hold', 'Speed, Handling', 'Live-oak frames with Memel fir ceiling between them, Hamburg fashion: a little more cargo space in the same hull.', 3, 3),
  ('hanseatic-capstan', 'Hanseatic Capstan', 'ground-tackle', 'Handling, a little Speed', 'Cargo space', 'A teak capstan with osmund-iron pawls, as the Lubeck yards fit it: the anchor and yards come up a little faster.', 3, 3),
  ('danzig-oak-planking', 'Danzig Oak Planking', 'hull', 'Armour, Hull', 'Speed, Cargo space', 'Doubled planking of the straight Polish oak Gdansk ships, payed with pine pitch: a little stronger than other oak.', 4, 3),
  ('london-pattern-chasers', 'London-pattern Chasers', 'weapon', 'Reach, Accuracy', 'Cargo space', 'Brass chasers bored to the London pattern and proved with English powder: they reach and aim a little further.', 4, 3),
  ('provencal-headsails', 'Provencal Jib & Staysail', 'rig', 'Handling, and a little Speed', 'Durability', 'A duck jib and staysail dressed with linseed oil, as the Marseille sailmakers do: the ship answers the helm a little quicker.', 3, 3),
  ('surat-teak-sheathing', 'Surat Teak Sheathing', 'hull', 'Armour, Durability', 'Speed', 'Teak and copper over a bed of coir caulking, as the Surat yards lay it: a little more armour and hull from the same bottom.', 5, 3),
  ('malabar-chain-pumps', 'Malabar Chain Pumps', 'hull', 'Hull', 'Cargo space', 'Teak chain pumps with coco-fibre packing, Kochi fashion: they keep a little more water down.', 3, 3),
  ('callao-copper-ballast', 'Callao Copper-pig Ballast', 'hull', 'Handling, Armour', 'Speed', 'Pig-iron ballast topped with copper pigs from the Callao quay: a little stiffer and steadier than plain pig iron.', 2, 3)
on conflict (code) do nothing;

insert into public.item_profile (item_code, base_type, rack, grade, meta, deck, hands, active) values
  ('long-eighteens', 'Long Guns', 'high', 5, 5, 9, 12, true),
  ('gunnades', 'Carronades', 'high', 5, 5, 8, 11, true),
  ('long-nines', 'Chase Guns', 'high', 5, 5, 6, 6, true),
  ('pateraros', 'Swivel Guns', 'high', 5, 5, 3, 5, true),
  ('grenadoes-and-cutlasses', 'Boarding Gear', 'high', 5, 5, 3, 8, true),
  ('hanging-magazine', 'Powder Magazine', 'high', 5, 5, 5, 3, false),
  ('racing-courses', 'Sails', 'mid', 5, 5, 5, 6, false),
  ('flying-jib', 'Headsails', 'mid', 5, 5, 3, 3, false),
  ('royal-stunsails', 'Studding Sails', 'mid', 5, 5, 6, 8, false),
  ('storm-trysails', 'Storm Canvas', 'mid', 5, 5, 5, 5, true),
  ('wheel-steered-rudder', 'Rudder', 'mid', 5, 5, 3, 3, false),
  ('geared-whipstaff', 'Whipstaff', 'mid', 5, 5, 3, 2, false),
  ('admiralty-anchor', 'Anchor', 'mid', 5, 5, 5, 3, false),
  ('bower-and-sheet-anchors', 'Sheet Anchor', 'mid', 5, 5, 8, 5, true),
  ('geared-capstan', 'Capstan', 'mid', 5, 5, 5, 5, false),
  ('night-glass', 'Lookout', 'mid', 5, 5, 2, 2, false),
  ('azimuth-compass', 'Binnacle & Charts', 'mid', 5, 5, 3, 2, false),
  ('trimmed-kentledge', 'Ballast', 'low', 5, 5, 3, 0, false),
  ('copper-bolted-sheathing', 'Sheathing', 'low', 5, 5, 5, 0, false),
  ('diagonal-planking', 'Planking', 'low', 5, 5, 6, 0, false),
  ('bentinck-pumps', 'Bilge Pumps', 'low', 5, 5, 5, 6, true),
  ('orlop-stowage', 'Hold Frames', 'low', 5, 5, 3, 0, false),
  ('lisbon-cast-brass-guns', 'Long Guns', 'high', 3, 1, 6, 10, true),
  ('arsenale-rudder', 'Rudder', 'mid', 3, 1, 1, 2, false),
  ('genoese-anchor', 'Anchor', 'mid', 3, 1, 3, 2, false),
  ('antwerp-duck-canvas', 'Sails', 'mid', 3, 1, 3, 5, false),
  ('elbe-frames', 'Hold Frames', 'low', 3, 1, 1, 0, false),
  ('hanseatic-capstan', 'Capstan', 'mid', 3, 1, 3, 4, false),
  ('danzig-oak-planking', 'Planking', 'low', 2, 1, 3, 0, false),
  ('london-pattern-chasers', 'Chase Guns', 'high', 3, 1, 4, 5, true),
  ('provencal-headsails', 'Headsails', 'mid', 3, 1, 1, 2, false),
  ('surat-teak-sheathing', 'Sheathing', 'low', 3, 1, 3, 0, false),
  ('malabar-chain-pumps', 'Bilge Pumps', 'low', 3, 1, 3, 5, true),
  ('callao-copper-ballast', 'Ballast', 'low', 3, 1, 1, 0, false)
on conflict (item_code) do nothing;

insert into public.item_effects (item_code, stat, delta) values
  ('long-eighteens', 'attack', 156),
  ('long-eighteens', 'reach', 39),
  ('long-eighteens', 'hold', -25),
  ('long-eighteens', 'handling', -8),
  ('gunnades', 'attack', 234),
  ('gunnades', 'reach', -19),
  ('gunnades', 'hold', -18),
  ('gunnades', 'handling', -5),
  ('long-nines', 'reach', 52),
  ('long-nines', 'accuracy', 26),
  ('long-nines', 'hold', -10),
  ('pateraros', 'attack', 52),
  ('pateraros', 'accuracy', 21),
  ('pateraros', 'handling', -3),
  ('grenadoes-and-cutlasses', 'attack', 91),
  ('grenadoes-and-cutlasses', 'reach', -25),
  ('hanging-magazine', 'attack', 65),
  ('hanging-magazine', 'accuracy', 31),
  ('hanging-magazine', 'hold', -13),
  ('hanging-magazine', 'durability', -75),
  ('racing-courses', 'speed', 1.08),
  ('racing-courses', 'handling', -10),
  ('flying-jib', 'handling', 26),
  ('flying-jib', 'speed', 0.36),
  ('flying-jib', 'durability', -50),
  ('royal-stunsails', 'speed', 1.62),
  ('royal-stunsails', 'handling', -18),
  ('royal-stunsails', 'durability', -38),
  ('storm-trysails', 'durability', 130),
  ('storm-trysails', 'handling', 10),
  ('storm-trysails', 'speed', -0.31),
  ('wheel-steered-rudder', 'handling', 36),
  ('wheel-steered-rudder', 'hold', -8),
  ('geared-whipstaff', 'handling', 18),
  ('geared-whipstaff', 'hold', -3),
  ('admiralty-anchor', 'handling', 10),
  ('admiralty-anchor', 'hold', -10),
  ('bower-and-sheet-anchors', 'durability', 156),
  ('bower-and-sheet-anchors', 'handling', 5),
  ('bower-and-sheet-anchors', 'hold', -13),
  ('geared-capstan', 'handling', 16),
  ('geared-capstan', 'speed', 0.18),
  ('geared-capstan', 'hold', -6),
  ('night-glass', 'sighting', 13),
  ('night-glass', 'handling', -5),
  ('azimuth-compass', 'sighting', 8),
  ('azimuth-compass', 'handling', 13),
  ('azimuth-compass', 'hold', -4),
  ('trimmed-kentledge', 'handling', 21),
  ('trimmed-kentledge', 'armour', 16),
  ('trimmed-kentledge', 'speed', -0.5),
  ('copper-bolted-sheathing', 'armour', 36),
  ('copper-bolted-sheathing', 'durability', 312),
  ('copper-bolted-sheathing', 'speed', -0.38),
  ('diagonal-planking', 'armour', 26),
  ('diagonal-planking', 'durability', 416),
  ('diagonal-planking', 'speed', -0.56),
  ('diagonal-planking', 'hold', -15),
  ('bentinck-pumps', 'durability', 234),
  ('bentinck-pumps', 'hold', -6),
  ('orlop-stowage', 'hold', 45),
  ('orlop-stowage', 'speed', -0.44),
  ('orlop-stowage', 'handling', -6),
  ('lisbon-cast-brass-guns', 'attack', 106),
  ('lisbon-cast-brass-guns', 'reach', 26),
  ('lisbon-cast-brass-guns', 'hold', -20),
  ('lisbon-cast-brass-guns', 'handling', -6),
  ('arsenale-rudder', 'handling', 24),
  ('arsenale-rudder', 'hold', -6),
  ('genoese-anchor', 'handling', 7),
  ('genoese-anchor', 'hold', -8),
  ('antwerp-duck-canvas', 'speed', 0.86),
  ('antwerp-duck-canvas', 'handling', -8),
  ('elbe-frames', 'hold', 36),
  ('elbe-frames', 'speed', -0.35),
  ('elbe-frames', 'handling', -5),
  ('hanseatic-capstan', 'handling', 11),
  ('hanseatic-capstan', 'speed', 0.14),
  ('hanseatic-capstan', 'hold', -5),
  ('danzig-oak-planking', 'armour', 14),
  ('danzig-oak-planking', 'durability', 229),
  ('danzig-oak-planking', 'speed', -0.45),
  ('danzig-oak-planking', 'hold', -12),
  ('london-pattern-chasers', 'reach', 35),
  ('london-pattern-chasers', 'accuracy', 18),
  ('london-pattern-chasers', 'hold', -8),
  ('provencal-headsails', 'handling', 18),
  ('provencal-headsails', 'speed', 0.29),
  ('provencal-headsails', 'durability', -40),
  ('surat-teak-sheathing', 'armour', 24),
  ('surat-teak-sheathing', 'durability', 211),
  ('surat-teak-sheathing', 'speed', -0.3),
  ('malabar-chain-pumps', 'durability', 158),
  ('malabar-chain-pumps', 'hold', -5),
  ('callao-copper-ballast', 'handling', 14),
  ('callao-copper-ballast', 'armour', 11),
  ('callao-copper-ballast', 'speed', -0.4)
on conflict (item_code, stat) do nothing;

create temp table item_goods_0159 (item_code text, good_code text, qty numeric) on commit drop;
insert into item_goods_0159 values
  ('long-eighteens', 'swedish-iron', 10),
  ('long-eighteens', 'culverin', 12),
  ('long-eighteens', 'falconet', 4),
  ('long-eighteens', 'gunpowder', 4),
  ('gunnades', 'copper', 12),
  ('gunnades', 'tin-ingots', 8),
  ('gunnades', 'falconet', 4),
  ('gunnades', 'gunpowder', 4),
  ('long-nines', 'copper', 10),
  ('long-nines', 'tin-ingots', 6),
  ('long-nines', 'culverin', 8),
  ('long-nines', 'falconet', 3),
  ('long-nines', 'gunpowder', 2),
  ('pateraros', 'copper', 6),
  ('pateraros', 'tin-ingots', 4),
  ('pateraros', 'swivel-gun', 2),
  ('pateraros', 'falconet', 1),
  ('pateraros', 'gunpowder', 2),
  ('grenadoes-and-cutlasses', 'swedish-iron', 5),
  ('grenadoes-and-cutlasses', 'abaca', 4),
  ('grenadoes-and-cutlasses', 'gunpowder', 3),
  ('grenadoes-and-cutlasses', 'falconet', 1),
  ('grenadoes-and-cutlasses', 'slow-match', 1),
  ('hanging-magazine', 'gunpowder', 12),
  ('hanging-magazine', 'greenheart', 5),
  ('hanging-magazine', 'copper-sheet', 8),
  ('hanging-magazine', 'swedish-iron', 2),
  ('racing-courses', 'sailcloth', 18),
  ('racing-courses', 'abaca', 10),
  ('racing-courses', 'whale-bone-stays', 6),
  ('racing-courses', 'canvas-duck', 6),
  ('flying-jib', 'riga-mast', 3),
  ('flying-jib', 'sailcloth', 8),
  ('flying-jib', 'abaca', 5),
  ('flying-jib', 'whale-bone-stays', 3),
  ('royal-stunsails', 'sailcloth', 14),
  ('royal-stunsails', 'abaca', 8),
  ('royal-stunsails', 'riga-mast', 3),
  ('royal-stunsails', 'whale-bone-stays', 3),
  ('storm-trysails', 'sailcloth', 10),
  ('storm-trysails', 'abaca', 8),
  ('storm-trysails', 'whale-bone-stays', 3),
  ('storm-trysails', 'tar', 2),
  ('wheel-steered-rudder', 'greenheart', 8),
  ('wheel-steered-rudder', 'lignum-vitae', 4),
  ('wheel-steered-rudder', 'copper-sheet', 4),
  ('wheel-steered-rudder', 'swedish-iron', 2),
  ('geared-whipstaff', 'greenheart', 5),
  ('geared-whipstaff', 'lignum-vitae', 3),
  ('geared-whipstaff', 'brass-ingots', 2),
  ('geared-whipstaff', 'copper-sheet', 1),
  ('geared-whipstaff', 'swedish-iron', 1),
  ('admiralty-anchor', 'swedish-iron', 6),
  ('admiralty-anchor', 'copper', 3),
  ('admiralty-anchor', 'abaca', 6),
  ('admiralty-anchor', 'lodestone', 1),
  ('bower-and-sheet-anchors', 'swedish-iron', 8),
  ('bower-and-sheet-anchors', 'copper', 4),
  ('bower-and-sheet-anchors', 'abaca', 8),
  ('bower-and-sheet-anchors', 'lodestone', 1),
  ('geared-capstan', 'greenheart', 5),
  ('geared-capstan', 'swedish-iron', 4),
  ('geared-capstan', 'copper', 2),
  ('geared-capstan', 'abaca', 3),
  ('geared-capstan', 'lodestone', 1),
  ('night-glass', 'riga-mast', 4),
  ('night-glass', 'lodestone', 1),
  ('night-glass', 'sea-charts', 2),
  ('night-glass', 'brass-ingots', 3),
  ('azimuth-compass', 'lodestone', 3),
  ('azimuth-compass', 'sea-charts', 4),
  ('azimuth-compass', 'brass-ingots', 3),
  ('azimuth-compass', 'lignum-vitae', 1),
  ('trimmed-kentledge', 'lead', 10),
  ('trimmed-kentledge', 'swedish-iron', 4),
  ('trimmed-kentledge', 'copper', 2),
  ('trimmed-kentledge', 'copper-sheet', 2),
  ('copper-bolted-sheathing', 'greenheart', 10),
  ('copper-bolted-sheathing', 'copper-sheet', 16),
  ('copper-bolted-sheathing', 'lignum-vitae', 3),
  ('copper-bolted-sheathing', 'swedish-iron', 2),
  ('copper-bolted-sheathing', 'oakum', 2),
  ('diagonal-planking', 'greenheart', 24),
  ('diagonal-planking', 'lignum-vitae', 12),
  ('diagonal-planking', 'copper-sheet', 10),
  ('diagonal-planking', 'swedish-iron', 4),
  ('bentinck-pumps', 'greenheart', 4),
  ('bentinck-pumps', 'copper', 5),
  ('bentinck-pumps', 'brass-ingots', 3),
  ('bentinck-pumps', 'copper-sheet', 2),
  ('bentinck-pumps', 'swedish-iron', 1),
  ('orlop-stowage', 'naval-timber', 10),
  ('orlop-stowage', 'greenheart', 20),
  ('orlop-stowage', 'copper-sheet', 10),
  ('orlop-stowage', 'swedish-iron', 2),
  ('lisbon-cast-brass-guns', 'brass-ingots', 8),
  ('lisbon-cast-brass-guns', 'culverin', 6),
  ('lisbon-cast-brass-guns', 'live-oak', 3),
  ('lisbon-cast-brass-guns', 'slow-match', 1),
  ('arsenale-rudder', 'teak', 4),
  ('arsenale-rudder', 'ships-nails', 3),
  ('arsenale-rudder', 'lignum-vitae', 1),
  ('arsenale-rudder', 'brass-ingots', 1),
  ('genoese-anchor', 'bar-iron', 4),
  ('genoese-anchor', 'abaca', 4),
  ('genoese-anchor', 'tar', 1),
  ('genoese-anchor', 'hemp', 1),
  ('antwerp-duck-canvas', 'canvas-duck', 20),
  ('antwerp-duck-canvas', 'hemp', 6),
  ('antwerp-duck-canvas', 'cordage', 3),
  ('antwerp-duck-canvas', 'tar', 1),
  ('antwerp-duck-canvas', 'holland-linen', 1),
  ('elbe-frames', 'live-oak', 10),
  ('elbe-frames', 'teak', 4),
  ('elbe-frames', 'ships-nails', 5),
  ('elbe-frames', 'oakum', 4),
  ('elbe-frames', 'memel-fir', 1),
  ('hanseatic-capstan', 'teak', 3),
  ('hanseatic-capstan', 'bar-iron', 2),
  ('hanseatic-capstan', 'abaca', 2),
  ('hanseatic-capstan', 'tallow', 1),
  ('hanseatic-capstan', 'osmund-iron', 1),
  ('danzig-oak-planking', 'timber', 12),
  ('danzig-oak-planking', 'ships-nails', 5),
  ('danzig-oak-planking', 'oakum', 3),
  ('danzig-oak-planking', 'tar', 1),
  ('danzig-oak-planking', 'pine-pitch', 1),
  ('london-pattern-chasers', 'brass-ingots', 6),
  ('london-pattern-chasers', 'culverin', 4),
  ('london-pattern-chasers', 'shot-and-ball', 2),
  ('london-pattern-chasers', 'gunpowder', 1),
  ('provencal-headsails', 'naval-timber', 3),
  ('provencal-headsails', 'canvas-duck', 8),
  ('provencal-headsails', 'cordage', 3),
  ('provencal-headsails', 'linseed', 1),
  ('surat-teak-sheathing', 'teak', 4),
  ('surat-teak-sheathing', 'copper-sheet', 8),
  ('surat-teak-sheathing', 'ships-nails', 4),
  ('surat-teak-sheathing', 'coir', 1),
  ('malabar-chain-pumps', 'teak', 3),
  ('malabar-chain-pumps', 'bar-iron', 2),
  ('malabar-chain-pumps', 'hides', 1),
  ('malabar-chain-pumps', 'coco-fibre', 1),
  ('callao-copper-ballast', 'bar-iron', 4),
  ('callao-copper-ballast', 'iron', 4),
  ('callao-copper-ballast', 'timber', 2),
  ('callao-copper-ballast', 'chilean-copper', 1);
insert into public.item_recipes (item_code, good_id, qty)
select w.item_code, g.id, w.qty from item_goods_0159 w join public.goods g on g.code = w.good_code
on conflict (item_code, good_id) do nothing;

insert into public.skill_requirements (subject_kind, subject_code, skill_code, level) values
  ('item', 'long-eighteens', 'GUNNERY', 5),
  ('item', 'long-eighteens', 'GUNNERY_SPEC', 1),
  ('item', 'gunnades', 'GUNNERY', 5),
  ('item', 'gunnades', 'GUNNERY_SPEC', 1),
  ('item', 'gunnades', 'SHORT_GUNS', 1),
  ('item', 'long-nines', 'GUNNERY', 5),
  ('item', 'long-nines', 'GUNNERY_SPEC', 1),
  ('item', 'long-nines', 'LONG_GUNS', 1),
  ('item', 'pateraros', 'GUNNERY', 5),
  ('item', 'pateraros', 'GUNNERY_SPEC', 1),
  ('item', 'grenadoes-and-cutlasses', 'BOARDING', 5),
  ('item', 'grenadoes-and-cutlasses', 'GUNNERY_SPEC', 1),
  ('item', 'hanging-magazine', 'GUNNERY', 5),
  ('item', 'hanging-magazine', 'GUNNERY_SPEC', 1),
  ('item', 'racing-courses', 'RIGGING', 5),
  ('item', 'racing-courses', 'RIGGING_SPEC', 1),
  ('item', 'flying-jib', 'RIGGING', 5),
  ('item', 'flying-jib', 'RIGGING_SPEC', 1),
  ('item', 'royal-stunsails', 'RIGGING', 5),
  ('item', 'royal-stunsails', 'RIGGING_SPEC', 1),
  ('item', 'storm-trysails', 'RIGGING', 5),
  ('item', 'storm-trysails', 'RIGGING_SPEC', 1),
  ('item', 'wheel-steered-rudder', 'SEAMANSHIP', 5),
  ('item', 'wheel-steered-rudder', 'HANDLING_SPEC', 1),
  ('item', 'geared-whipstaff', 'SEAMANSHIP', 5),
  ('item', 'geared-whipstaff', 'HANDLING_SPEC', 1),
  ('item', 'admiralty-anchor', 'SEAMANSHIP', 5),
  ('item', 'admiralty-anchor', 'HANDLING_SPEC', 1),
  ('item', 'bower-and-sheet-anchors', 'SEAMANSHIP', 5),
  ('item', 'bower-and-sheet-anchors', 'HANDLING_SPEC', 1),
  ('item', 'geared-capstan', 'SEAMANSHIP', 5),
  ('item', 'geared-capstan', 'HANDLING_SPEC', 1),
  ('item', 'night-glass', 'LOOKOUTS', 5),
  ('item', 'night-glass', 'INSTRUMENT_SPEC', 1),
  ('item', 'azimuth-compass', 'INSTRUMENTS', 5),
  ('item', 'azimuth-compass', 'INSTRUMENT_SPEC', 1),
  ('item', 'trimmed-kentledge', 'SHIPWRIGHT', 5),
  ('item', 'trimmed-kentledge', 'SHIPWRIGHT_SPEC', 1),
  ('item', 'copper-bolted-sheathing', 'SHIPWRIGHT', 5),
  ('item', 'copper-bolted-sheathing', 'SHIPWRIGHT_SPEC', 1),
  ('item', 'diagonal-planking', 'SHIPWRIGHT', 5),
  ('item', 'diagonal-planking', 'SHIPWRIGHT_SPEC', 1),
  ('item', 'bentinck-pumps', 'SHIPWRIGHT', 5),
  ('item', 'bentinck-pumps', 'SHIPWRIGHT_SPEC', 1),
  ('item', 'orlop-stowage', 'CARGO_STOWAGE', 5),
  ('item', 'orlop-stowage', 'STOWAGE_SPEC', 1),
  ('item', 'lisbon-cast-brass-guns', 'GUNNERY', 3),
  ('item', 'arsenale-rudder', 'SEAMANSHIP', 3),
  ('item', 'genoese-anchor', 'SEAMANSHIP', 3),
  ('item', 'antwerp-duck-canvas', 'RIGGING', 3),
  ('item', 'elbe-frames', 'CARGO_STOWAGE', 3),
  ('item', 'hanseatic-capstan', 'SEAMANSHIP', 3),
  ('item', 'danzig-oak-planking', 'SHIPWRIGHT', 2),
  ('item', 'london-pattern-chasers', 'GUNNERY', 3),
  ('item', 'london-pattern-chasers', 'LONG_GUNS', 1),
  ('item', 'provencal-headsails', 'RIGGING', 3),
  ('item', 'surat-teak-sheathing', 'SHIPWRIGHT', 3),
  ('item', 'malabar-chain-pumps', 'SHIPWRIGHT', 3),
  ('item', 'callao-copper-ballast', 'SHIPWRIGHT', 3)
on conflict (subject_kind, subject_code, skill_code) do nothing;

insert into public.item_use (item_code, trigger, consumes) values
  ('admiralty-anchor', 'STORM', '[]'),
  ('antwerp-duck-canvas', 'MILES', '[]'),
  ('arsenale-rudder', 'STORM', '[]'),
  ('azimuth-compass', 'MILES', '[]'),
  ('bentinck-pumps', 'STORM', '[]'),
  ('bower-and-sheet-anchors', 'STORM', '[]'),
  ('callao-copper-ballast', 'STORM', '[]'),
  ('copper-bolted-sheathing', 'STORM', '[]'),
  ('danzig-oak-planking', 'STORM', '[]'),
  ('diagonal-planking', 'STORM', '[]'),
  ('elbe-frames', 'STORM', '[]'),
  ('flying-jib', 'MILES', '[]'),
  ('geared-capstan', 'STORM', '[]'),
  ('geared-whipstaff', 'STORM', '[]'),
  ('genoese-anchor', 'STORM', '[]'),
  ('grenadoes-and-cutlasses', 'PIRATES', '[]'),
  ('gunnades', 'PIRATES', '[{"good":"shot-and-ball","qty":1},{"good":"gunpowder","qty":1}]'),
  ('hanging-magazine', 'PIRATES', '[]'),
  ('hanseatic-capstan', 'STORM', '[]'),
  ('lisbon-cast-brass-guns', 'PIRATES', '[{"good":"shot-and-ball","qty":1},{"good":"gunpowder","qty":1}]'),
  ('london-pattern-chasers', 'PIRATES', '[{"good":"shot-and-ball","qty":1},{"good":"gunpowder","qty":1}]'),
  ('long-eighteens', 'PIRATES', '[{"good":"shot-and-ball","qty":1},{"good":"gunpowder","qty":1}]'),
  ('long-nines', 'PIRATES', '[{"good":"shot-and-ball","qty":1},{"good":"gunpowder","qty":1}]'),
  ('malabar-chain-pumps', 'STORM', '[]'),
  ('night-glass', 'MILES', '[]'),
  ('orlop-stowage', 'STORM', '[]'),
  ('pateraros', 'PIRATES', '[{"good":"shot-and-ball","qty":1},{"good":"gunpowder","qty":1}]'),
  ('provencal-headsails', 'MILES', '[]'),
  ('racing-courses', 'MILES', '[]'),
  ('royal-stunsails', 'MILES', '[]'),
  ('storm-trysails', 'STORM', '[]'),
  ('surat-teak-sheathing', 'STORM', '[]'),
  ('trimmed-kentledge', 'STORM', '[]'),
  ('wheel-steered-rudder', 'STORM', '[]')
on conflict (item_code) do nothing;

-- ── 4. A NAMED ITEM'S CITY ─────────────────────────────────────────────────────────────────────
create table if not exists public.item_city (
  item_code text primary key,
  port_id   uuid not null
);
comment on table public.item_city is
  '0159 (S15, docs/SHIPS_AND_SKILLS.md §6.2): a NAMED item is a city''s own pattern and is made ONLY in that '
  'city''s workshop — one row per Named item. Read only by public.made_only_in. Generated (scripts/build-gear.mjs '
  'NAMED), held by the world guard. Server-only.';
alter table public.item_city enable row level security;
revoke all on table public.item_city from public, anon, authenticated;

create temp table item_city_0159 (item_code text, port_code text) on commit drop;
insert into item_city_0159 values
  ('lisbon-cast-brass-guns', 'LIS'),
  ('arsenale-rudder', 'VEN'),
  ('genoese-anchor', 'GOA'),
  ('antwerp-duck-canvas', 'ARP'),
  ('elbe-frames', 'HAM'),
  ('hanseatic-capstan', 'LUB'),
  ('danzig-oak-planking', 'GDA'),
  ('london-pattern-chasers', 'LON'),
  ('provencal-headsails', 'MRS'),
  ('surat-teak-sheathing', 'SRT'),
  ('malabar-chain-pumps', 'KOC'),
  ('callao-copper-ballast', 'CLL');
insert into public.item_city (item_code, port_id)
select w.item_code, p.id from item_city_0159 w join public.ports p on p.code = w.port_code
on conflict (item_code) do nothing;

create or replace function public.made_only_in(p_item text, p_port uuid)
returns text
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  -- 0159 (S15): THE ONE SENTENCE OF "MADE ONLY THERE" — null where this port may make the item (it has no
  -- city, or this is its city); else "Lisbon-cast Brass Guns is made only in Lisbon". Read by cmd.do_make
  -- (E_NOT_MADE_HERE) and world.workstation (`makeable`, `made_only_in`).
  return (select format('%s is made only in %s', k.name, p.name)
            from public.item_city ic
            join public.item_kinds k on k.code = ic.item_code
            join public.ports p on p.id = ic.port_id
           where ic.item_code = p_item and ic.port_id is distinct from p_port);
end $$;
comment on function public.made_only_in(text, uuid) is
  '0159 (S15): the "made only in <city>" sentence of a Named item away from its city, or null. Server-only.';
revoke all on function public.made_only_in(text, uuid) from public, anon, authenticated;

-- ── 5. THE HUNKS (old → new), sliced from the live bodies ──────────────────────────────────────
create temp table hunks_0159 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0159 values
('cmd.do_make(uuid, jsonb)', 1,
$h$    raise exception 'E_WORKSTATION_TOO_SMALL: % needs a tier % workstation and this one is tier %',
      k.name, k.ws_tier, v_tier using errcode = 'P0001';
  end if;
$h$,
$h$    raise exception 'E_WORKSTATION_TOO_SMALL: % needs a tier % workstation and this one is tier %',
      k.name, k.ws_tier, v_tier using errcode = 'P0001';
  end if;
  -- 0159 (S15, §6.2): A NAMED ITEM IS MADE ONLY IN ITS OWN CITY — public.made_only_in, the one sentence
  -- (the workshop screen serves the same one).
  if public.made_only_in(k.code, f.port_id) is not null then
    perform cmd.refuse('E_NOT_MADE_HERE', public.made_only_in(k.code, f.port_id));
  end if;
$h$),
('world.workstation(uuid, uuid)', 1,
$h$                    and kn.needs is null,                                   -- 0135: and its skills (cmd.do_make)
$h$,
$h$                    and kn.needs is null                                    -- 0135: and its skills (cmd.do_make)
                    and kn.made_in is null,                                 -- 0159: and, a Named item, its city
$h$),
('world.workstation(uuid, uuid)', 2,
$h$         where ir.item_code = k.code))
        order by k.ws_tier, k.name), '[]'::jsonb)
$h$,
$h$         where ir.item_code = k.code))
        -- 0159: a Named item away from its city says where it is made (public.made_only_in), only then
        || case when kn.made_in is null then '{}'::jsonb else jsonb_build_object('made_only_in', kn.made_in) end
        order by k.ws_tier, k.name), '[]'::jsonb)
$h$),
('world.workstation(uuid, uuid)', 3,
$h$     cross join lateral (select public.requirements_refusal(v_player, 'item', k.code) as needs) kn));   -- 0135: once per item
$h$,
$h$     cross join lateral (select public.requirements_refusal(v_player, 'item', k.code) as needs,
                                public.made_only_in(k.code, p_port) as made_in) kn));   -- 0135: once per item (0159: and its city)
$h$),
('world.building_yard(uuid)', 1,
$h$         where hi.class_code = h.class_code))
        order by h.yard_tier, c.name), '[]'::jsonb)
$h$,
$h$         where hi.class_code = h.class_code))
        -- 0159: a hull's tech where it is not T1 (the yard's T2 badge); a T1 hull's entry is as before
        || case when cp.tech is distinct from 'T1' then jsonb_build_object('tech', cp.tech) else '{}'::jsonb end
        order by h.yard_tier, c.name), '[]'::jsonb)
$h$);

create or replace function pg_temp.recut_0159(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := replace(pg_get_functiondef(p_fn::regprocedure), E'\r', '');
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0159 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0159(v_def, h.old);
    if v_n <> 1 then
      raise exception '0159 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0159(fn) from defs_before_0159 order by fn;

-- one item of a workshop, as the company's own user sees it
create or replace function pg_temp.shop_item_0159(p_uid uuid, p_port uuid, p_fleet uuid, p_item text)
returns jsonb
language plpgsql
as $$
declare
  v jsonb;
begin
  perform pg_temp.as_0159(p_uid);
  select i into v from jsonb_array_elements(world.workstation(p_port, p_fleet)->'items') i where i->>'code' = p_item;
  perform pg_temp.as_0159(null);
  return v;
end $$;

-- ── 6. THE PROBE (its own company, which builds its own state; rolled back whole) ─────────────────
create or replace function pg_temp.probe_0159()
returns jsonb
language plpgsql
as $$
declare
  c_uid    constant uuid := '00000000-0159-4000-8000-000000000001';
  v_player uuid;
  v_fleet  uuid;
  v_barca  uuid;
  v_lis    uuid := (select id from public.ports where code = 'LIS');
  v_ven    uuid := (select id from public.ports where code = 'VEN');
  v_out    jsonb := '{}'::jsonb;
  v_dark   jsonb := '{}'::jsonb;
  v_lit0   jsonb := '{}'::jsonb;
  v_lit    jsonb := '{}'::jsonb;
  h        record;
  v_cargo  jsonb;
begin
  begin
    update public.world_config set value = 'false'::jsonb where key = 'skills_bite';   -- own precondition
    v_player := public.new_house(c_uid, 'Casa da Prova 0159', 'PRT', 'LIS');
    select id into v_fleet from public.fleets where player_id = v_player;
    select id into v_barca from public.ships where fleet_id = v_fleet;
    perform public.credit(v_player, 'PROBE_0159', 100000000);
    -- every new hull at a build yard of its line (the first by tier, then code), its goods ashore there
    create temp table if not exists probe_yards_0159 (class text primary key, yard uuid, ducats bigint) on commit drop;
    delete from probe_yards_0159;
    insert into probe_yards_0159
    select c.code,
           (select b.port_id from public.port_buildings b join public.ports p on p.id = b.port_id
             where b.kind = 'building_yard' and b.tier >= hr.yard_tier
               and public.yard_wrong_country(b.port_id, c.code) is null
             order by b.tier desc, p.code limit 1),
           hr.ducats
      from public.ship_classes c join public.hull_recipes hr on hr.class_code = c.code
     where c.code not in (select code from live_classes_0159);
    insert into public.player_storage (player_id, port_id, good_id, qty)
    select v_player, y.yard, hg.good_id, max(hg.qty)
      from probe_yards_0159 y join public.hull_recipe_goods hg on hg.class_code = y.class
     where y.yard is not null
     group by y.yard, hg.good_id
    on conflict (player_id, port_id, good_id) do update set qty = excluded.qty;

    -- (H1) DARK: every one refused
    for h in select * from probe_yards_0159 where yard is not null order by class loop
      update public.fleets set port_id = h.yard, status = 'DOCKED' where id = v_fleet;
      v_dark := v_dark || jsonb_build_object(h.class, pg_temp.try_0159(v_player,
        format('select cmd.do_build(%L, %L::jsonb)', v_fleet, jsonb_build_object('class', h.class, 'name', 'Prova ' || h.class))));
    end loop;
    -- (H2) LIT, the hull skills at V but no specialisation: refused naming the specialisation, with figures
    update public.world_config set value = 'true'::jsonb where key = 'skills_bite';
    insert into public.player_skills (player_id, skill_id, level)
    select v_player, sk.id, 5 from public.skills sk join public.skill_profile pr on pr.skill_id = sk.id
     where pr.group_code = 'HULLS'
    on conflict (player_id, skill_id) do update set level = excluded.level;
    for h in select * from probe_yards_0159 where yard is not null order by class loop
      update public.fleets set port_id = h.yard, status = 'DOCKED' where id = v_fleet;
      v_lit0 := v_lit0 || jsonb_build_object(h.class, pg_temp.try_0159(v_player,
        format('select cmd.do_build(%L, %L::jsonb)', v_fleet, jsonb_build_object('class', h.class, 'name', 'Prova ' || h.class))));
    end loop;
    -- (H3) LIT, with the four role specialisations: every one BUILT for its labour
    insert into public.player_skills (player_id, skill_id, level)
    select v_player, sk.id, 1 from public.skills sk
     where sk.code in ('ARMED_MERCHANT', 'PRIVATEERS', 'SURVEY_SHIPS', 'CONVOY_ESCORTS')
    on conflict (player_id, skill_id) do update set level = excluded.level;
    for h in select * from probe_yards_0159 where yard is not null order by class loop
      update public.fleets set port_id = h.yard, status = 'DOCKED' where id = v_fleet;
      v_lit := v_lit || jsonb_build_object(h.class, pg_temp.try_0159(v_player,
        format('select cmd.do_build(%L, %L::jsonb)', v_fleet, jsonb_build_object('class', h.class, 'name', 'Prova ' || h.class))));
    end loop;
    v_out := v_out || jsonb_build_object('dark', v_dark, 'lit0', v_lit0, 'lit', v_lit,
                                         'yards', (select jsonb_object_agg(class, yard) from probe_yards_0159));

    -- (G) THE GEAR at Lisbon's tier-3 workshop, the materials on board: a T2 module (Long Eighteens) needs
    --     Gunnery V and Gunnery Specialisation I; the Named Lisbon-cast Brass Guns (Gunnery III) is made in
    --     Lisbon and refused in Venice
    update public.fleets set port_id = v_lis, status = 'DOCKED' where id = v_fleet;
    select jsonb_object_agg(g.code, ir.qty * 2) into v_cargo
      from public.item_recipes ir join public.goods g on g.id = ir.good_id
     where ir.item_code in ('long-eighteens', 'lisbon-cast-brass-guns');
    update public.ships set cargo = v_cargo where id = v_barca;
    update public.world_config set value = 'false'::jsonb where key = 'skills_bite';
    v_out := v_out || jsonb_build_object('t2_dark', pg_temp.try_0159(v_player,
      format('select cmd.do_make(%L, ''{"item": "long-eighteens"}''::jsonb)', v_fleet)));
    update public.world_config set value = 'true'::jsonb where key = 'skills_bite';
    insert into public.player_skills (player_id, skill_id, level)
    select v_player, sk.id, 5 from public.skills sk where sk.code = 'GUNNERY'
    on conflict (player_id, skill_id) do update set level = excluded.level;
    v_out := v_out || jsonb_build_object('t2_nospec', pg_temp.try_0159(v_player,
      format('select cmd.do_make(%L, ''{"item": "long-eighteens"}''::jsonb)', v_fleet)));
    insert into public.player_skills (player_id, skill_id, level)
    select v_player, sk.id, 1 from public.skills sk where sk.code = 'GUNNERY_SPEC'
    on conflict (player_id, skill_id) do update set level = excluded.level;
    v_out := v_out || jsonb_build_object('t2_made', pg_temp.try_0159(v_player,
      format('select cmd.do_make(%L, ''{"item": "long-eighteens"}''::jsonb)', v_fleet)));
    v_out := v_out || jsonb_build_object('named_lis', pg_temp.try_0159(v_player,
      format('select cmd.do_make(%L, ''{"item": "lisbon-cast-brass-guns"}''::jsonb)', v_fleet)),
      'shop_lis', pg_temp.shop_item_0159(c_uid, v_lis, v_fleet, 'lisbon-cast-brass-guns'));
    update public.fleets set port_id = v_ven where id = v_fleet;
    v_out := v_out || jsonb_build_object('named_ven', pg_temp.try_0159(v_player,
      format('select cmd.do_make(%L, ''{"item": "lisbon-cast-brass-guns"}''::jsonb)', v_fleet)),
      'shop_ven', pg_temp.shop_item_0159(c_uid, v_ven, v_fleet, 'lisbon-cast-brass-guns'));
    update public.world_config set value = 'false'::jsonb where key = 'skills_bite';
    raise exception 'PROBE_ROLLBACK_0159';
  exception when others then
    if sqlerrm <> 'PROBE_ROLLBACK_0159' then raise; end if;
  end;
  return v_out;
end $$;

create temp table probe_0159 on commit drop as select pg_temp.probe_0159() as j;

-- ── 7. THE COMPARISONS ─────────────────────────────────────────────────────────────────────────
create temp table yards_after_0159 on commit drop as
select b.port_id, h.value->>'class' as class, h.value as entry
  from public.port_buildings b
 cross join lateral jsonb_array_elements(world.building_yard(b.port_id)->'hulls') h
 where b.kind = 'building_yard';
create temp table shops_after_0159 on commit drop as
select b.port_id, i.value->>'code' as code, i.value as entry
  from public.port_buildings b
 cross join lateral jsonb_array_elements(world.workstation(b.port_id)->'items') i
 where b.kind = 'workstation';

analyze public.ship_classes, public.class_profile, public.class_slots, public.class_cabins, public.hull_recipes,
        public.hull_recipe_goods, public.skill_requirements, public.item_kinds, public.item_profile,
        public.item_effects, public.item_recipes, public.item_use, public.item_city;
select pg_temp.time_reads_0159('after');

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_b     record;
  d       record;
  h       record;
  v_pp    record;
  v_rd    record;
  v_bad   int;
  v_list  text;
  v_def   text;
  v_p     jsonb := (select j from probe_0159);
  v_notes text := '';
begin
  select * into v_b from before_0159;

  -- (a) NOTHING ALREADY IN THE WORLD MOVED: every old hull's and item's rows hash as before
  if (select md5(string_agg(to_jsonb(c)::text, '|' order by c.code)) from public.ship_classes c where c.code in (select code from live_classes_0159)) <> v_b.classes_hash
     or (select md5(string_agg(to_jsonb(c)::text, '|' order by c.class_code)) from public.class_profile c where c.class_code in (select code from live_classes_0159)) <> v_b.profile_hash
     or (select md5(string_agg(to_jsonb(c)::text, '|' order by c.class_code, c.slot)) from public.class_slots c where c.class_code in (select code from live_classes_0159)) <> v_b.slots_hash
     or (select md5(string_agg(to_jsonb(c)::text, '|' order by c.class_code)) from public.class_cabins c where c.class_code in (select code from live_classes_0159)) <> v_b.cabins_hash
     or (select md5(string_agg(to_jsonb(c)::text, '|' order by c.class_code)) from public.hull_recipes c where c.class_code in (select code from live_classes_0159)) <> v_b.recipes_hash
     or (select md5(string_agg(to_jsonb(c)::text, '|' order by c.class_code, c.good_id)) from public.hull_recipe_goods c where c.class_code in (select code from live_classes_0159)) <> v_b.recipe_goods_hash
     or (select md5(string_agg(to_jsonb(c)::text, '|' order by c.subject_kind, c.subject_code, c.skill_code)) from public.skill_requirements c
          where c.subject_code in (select code from live_classes_0159) or c.subject_code in (select code from live_items_0159)) <> v_b.requirements_hash
     or (select md5(string_agg(to_jsonb(c)::text, '|' order by c.code)) from public.item_kinds c where c.code in (select code from live_items_0159)) <> v_b.kinds_hash
     or (select md5(string_agg(to_jsonb(c)::text, '|' order by c.item_code)) from public.item_profile c where c.item_code in (select code from live_items_0159)) <> v_b.iprofile_hash
     or (select md5(string_agg(to_jsonb(c)::text, '|' order by c.item_code, c.stat)) from public.item_effects c where c.item_code in (select code from live_items_0159)) <> v_b.effects_hash
     or (select md5(string_agg(format('%s/%s/%s', c.item_code, c.good_id, c.qty), '|' order by c.item_code, c.good_id)) from public.item_recipes c where c.item_code in (select code from live_items_0159)) <> v_b.item_recipes_hash
     or (select md5(string_agg(to_jsonb(c)::text, '|' order by c.item_code)) from public.item_use c where c.item_code in (select code from live_items_0159)) <> v_b.use_hash then
    raise exception '0159 self-assert FAIL: a row of a hull or an item already in the world moved';
  end if;

  -- (b) EXACTLY THE GENERATED ROWS LANDED (counts; the world guard holds every column to the generators)
  if (select count(*) from public.ship_classes) <> v_b.classes + 22
     or (select count(*) from public.class_profile p where p.tech = 'T2') <> 22
     or (select count(*) from public.class_slots) <> v_b.slots + 86
     or (select count(*) from public.hull_recipe_goods) <> v_b.recipe_goods + 111
     or (select count(*) from public.skill_requirements where subject_kind = 'hull') <> v_b.hull_requirements + 44
     or (select count(*) from public.item_kinds) <> v_b.kinds + 34
     or (select count(*) from public.item_effects) <> v_b.effects + 97
     or (select count(*) from public.item_recipes) <> v_b.item_recipes + 147
     or (select count(*) from public.skill_requirements where subject_kind = 'item') <> v_b.item_requirements + 59
     or (select count(*) from public.item_use) <> v_b.uses + 34
     or (select count(*) from public.item_use) <> (select count(*) from public.item_kinds)
     or (select count(*) from public.item_profile where meta = 5) <> 22
     or (select count(*) from public.item_profile where meta = 1) <> 12
     or (select count(*) from public.item_city) <> 12 then
    raise exception '0159 self-assert FAIL: the catalogue counts are not the pre-image plus the generated rows (classes %, items %, cities %)',
      (select count(*) from public.ship_classes), (select count(*) from public.item_kinds), (select count(*) from public.item_city);
  end if;
  select count(*) into v_bad from public.ship_classes c
   where not exists (select 1 from public.class_profile p where p.class_code = c.code)
      or not exists (select 1 from public.class_cabins x where x.class_code = c.code)
      or not exists (select 1 from public.hull_recipes x where x.class_code = c.code)
      or not exists (select 1 from public.hull_recipe_goods x where x.class_code = c.code)
      or not exists (select 1 from public.class_slots x where x.class_code = c.code);
  if v_bad <> 0 then
    raise exception '0159 self-assert FAIL: % hull(s) lack a profile, cabins, recipe, materials or racks', v_bad;
  end if;

  -- (c) THE HULL RULES over every class: guns = attack / 10, tier = least(size, 5), Hands ≥ 0, the yard tier
  --     by size; the new hulls T2, own-country, sizes 1-4; two per line
  select count(*), string_agg(c.code, ',' order by c.code) into v_bad, v_list
    from public.ship_classes c join public.class_profile p on p.class_code = c.code
    join public.hull_recipes hr on hr.class_code = c.code
   where c.guns * 10 <> c.attack or c.tier <> least(p.size, 5)
      or c.crew_max - (c.crew_required + 1) / 2 < 0
      or hr.yard_tier <> case p.size when 1 then 1 when 2 then 2 else 3 end
      or (c.code not in (select code from live_classes_0159) and (p.tech <> 'T2' or p.any_yard or p.size > 4));
  if v_bad <> 0 then
    raise exception '0159 self-assert FAIL: % class(es) break guns = attack / 10, tier, Hands, the yard tier by size, or T2 / own-country / sizes 1-4: %', v_bad, v_list;
  end if;
  if exists (select 1 from public.class_profile p where p.tech = 'T2' group by p.line_code having count(*) <> 2)
     or (select count(distinct p.line_code) from public.class_profile p where p.tech = 'T2') <> 11 then
    raise exception '0159 self-assert FAIL: the T2 hulls are not two per line, eleven lines';
  end if;
  -- a T2 hull carries more places than the T1 of its line, size and role where one exists
  select count(*), string_agg(t2.class_code, ',') into v_bad, v_list
    from public.class_profile t2 join public.class_profile t1
      on t1.line_code = t2.line_code and t1.size = t2.size and t1.role = t2.role and t1.tech = 'T1'
   where t2.tech = 'T2'
     and (select sum(count) from public.class_slots where class_code = t2.class_code)
         <> (select sum(count) from public.class_slots where class_code = t1.class_code) + 1;
  if v_bad <> 0 then
    raise exception '0159 self-assert FAIL: % T2 hull(s) do not carry exactly one place more than their T1: %', v_bad, v_list;
  end if;

  -- (d) 0072 (b)(d) OVER EVERY HULL: every material sold somewhere; every hull's goods fit a storage where it
  --     can be built (THE SHED, not loosened); and every hull buildable at ≥ 1 yard of its line
  select count(*), string_agg(distinct g.code, ',') into v_bad, v_list
    from public.hull_recipe_goods hg join public.goods g on g.id = hg.good_id
   where not exists (select 1 from public.port_goods pg join public.ports p on p.id = pg.port_id
                      where pg.good_id = hg.good_id and public.port_offers(p.id, hg.good_id));
  if v_bad <> 0 then
    raise exception '0159 self-assert FAIL: % hull material(s) are sold in NO city: %', v_bad, v_list;
  end if;
  select count(*), string_agg(x.class_code || ' ' || x.tons || ' t', ', ') into v_bad, v_list from (
    select hr.class_code, sum(hg.qty * g.bulk) as tons
      from public.hull_recipes hr
      join public.hull_recipe_goods hg on hg.class_code = hr.class_code
      join public.goods g on g.id = hg.good_id
     group by hr.class_code) x
   where x.tons > coalesce((select max(public.storage_cap(b.port_id)) from public.port_buildings b
                             join public.hull_recipes hr on hr.class_code = x.class_code
                            where b.kind = 'building_yard' and b.tier >= hr.yard_tier
                              and public.yard_wrong_country(b.port_id, x.class_code) is null), 0);
  if v_bad <> 0 then
    raise exception '0159 self-assert FAIL: % hull(s) want more than any storage where they can be built holds: %', v_bad, v_list;
  end if;
  select count(*), string_agg(c.code, ',') into v_bad, v_list
    from public.ship_classes c join public.hull_recipes hr on hr.class_code = c.code
   where not exists (select 1 from public.port_buildings b
                      where b.kind = 'building_yard' and b.tier >= hr.yard_tier
                        and public.yard_wrong_country(b.port_id, c.code) is null);
  if v_bad <> 0 then
    raise exception '0159 self-assert FAIL: % hull(s) can be built at no yard of their line: %', v_bad, v_list;
  end if;

  -- (e) THE T2 HULL REQUIREMENTS (§4.4): the line's ⟨size⟩ Hulls V + the role's specialisation I, nothing else
  select count(*), string_agg(c.class_code, ',') into v_bad, v_list
    from public.class_profile c
   where c.tech = 'T2'
     and (select string_agg(r.skill_code || ':' || r.level, ',' order by r.skill_code)
            from public.skill_requirements r where r.subject_kind = 'hull' and r.subject_code = c.class_code)
         is distinct from
         (select string_agg(x.s || ':' || x.l, ',' order by x.s) from (values
            (c.line_code || '_' || case c.size when 1 then 'SMALL' when 2 then 'LIGHT' when 3 then 'MEDIUM' else 'HEAVY' end, 5),
            (case c.role when 'trade' then 'ARMED_MERCHANT' when 'combat' then 'PRIVATEERS'
                         when 'explorer' then 'SURVEY_SHIPS' else 'CONVOY_ESCORTS' end, 1)) x(s, l));
  if v_bad <> 0 then
    raise exception '0159 self-assert FAIL: % T2 hull(s) do not carry §4.4''s requirements: %', v_bad, v_list;
  end if;

  -- (f) THE GEAR RULES over every item: buys one and spends one (0074; the figurehead none); every recipe good
  --     sold somewhere; every T2 needs a skill at V and a specialisation at I; a Named item what its grade
  --     needs; every Named item has exactly one city, with a tier-3 workshop, one per city; nothing else does
  select count(*) into v_bad from public.item_kinds k join public.item_profile ip on ip.item_code = k.code
   where ip.base_type <> 'Figurehead'
     and not (exists (select 1 from public.item_effects e where e.item_code = k.code and e.delta > 0)
          and exists (select 1 from public.item_effects e where e.item_code = k.code and e.delta < 0));
  if v_bad <> 0 then
    raise exception '0159 self-assert FAIL: % item(s) buy a stat without spending one', v_bad;
  end if;
  select count(*), string_agg(distinct g.code, ',') into v_bad, v_list
    from public.item_recipes ir join public.goods g on g.id = ir.good_id
   where not exists (select 1 from public.port_goods pg join public.ports p on p.id = pg.port_id
                      where pg.good_id = ir.good_id and public.port_offers(p.id, ir.good_id));
  if v_bad <> 0 then
    raise exception '0159 self-assert FAIL: % item material(s) are sold in NO city: %', v_bad, v_list;
  end if;
  if exists (select 1 from public.item_profile ip where ip.meta = 5
              and (ip.grade <> 5
                   or (select count(*) from public.skill_requirements r where r.subject_kind = 'item' and r.subject_code = ip.item_code and r.level = 5) < 1
                   or (select count(*) from public.skill_requirements r where r.subject_kind = 'item' and r.subject_code = ip.item_code
                        and r.level = 1 and r.skill_code like '%\_SPEC' escape '\') <> 1
                   or (select k.ws_tier from public.item_kinds k where k.code = ip.item_code) <> 3))
     or exists (select 1 from public.item_profile ip where ip.meta in (1, 5) and ip.item_code not in (select item_code from public.item_use where trigger is not null))
     or exists (select 1 from public.item_city ic where not exists (select 1 from public.item_profile ip where ip.item_code = ic.item_code and ip.meta = 1))
     or exists (select 1 from public.item_profile ip where ip.meta = 1 and not exists (select 1 from public.item_city ic where ic.item_code = ip.item_code))
     or (select count(distinct port_id) from public.item_city) <> 12
     or exists (select 1 from public.item_city ic where not exists (select 1 from public.port_buildings b
                 where b.port_id = ic.port_id and b.kind = 'workstation' and b.tier >= (select k.ws_tier from public.item_kinds k where k.code = ic.item_code))) then
    raise exception '0159 self-assert FAIL: a T2 module''s grade / requirements / workshop, a Named item''s city, or what works a new item is not as §6.2 says';
  end if;

  -- (g) DARK = WHAT A COMPANY SEES AND DOES TODAY. Every old hull's yard entry and every old item's workshop
  --     entry is its pre-image, to the byte; every new one is closed with its needs (dark reason)
  select count(*) into v_bad from yards_before_0159 yb
   where (select ya.entry from yards_after_0159 ya where ya.port_id = yb.port_id and ya.class = yb.class) is distinct from yb.entry;
  if v_bad <> 0 or (select count(*) from yards_before_0159) = 0 then
    raise exception '0159 self-assert FAIL: % old yard entr(ies) moved (or none was read)', v_bad;
  end if;
  select count(*) into v_bad from shops_before_0159 sb
   where (select sa.entry from shops_after_0159 sa where sa.port_id = sb.port_id and sa.code = sb.code) is distinct from sb.entry;
  if v_bad <> 0 or (select count(*) from shops_before_0159) = 0 then
    raise exception '0159 self-assert FAIL: % old workshop entr(ies) moved (or none was read)', v_bad;
  end if;
  select count(*) into v_bad from yards_after_0159 ya
   where ya.class not in (select code from live_classes_0159)
     and ((ya.entry->>'buildable')::boolean or ya.entry->>'tech' is distinct from 'T2'
          or position('ship skills are not in use yet' in coalesce(ya.entry->>'needs', '')) = 0);
  if v_bad <> 0 then
    raise exception '0159 self-assert FAIL: % new yard entr(ies) are open, unbadged or without the dark reason', v_bad;
  end if;
  select count(*) into v_bad from shops_after_0159 sa
   where sa.code not in (select code from live_items_0159)
     and ((sa.entry->>'makeable')::boolean
          or position('ship skills are not in use yet' in coalesce(sa.entry->>'needs', '')) = 0
          or (sa.code in (select item_code from public.item_city)) <> (sa.entry ? 'made_only_in'
               or sa.port_id = (select ic.port_id from public.item_city ic where ic.item_code = sa.code)));
  if v_bad <> 0 then
    raise exception '0159 self-assert FAIL: % new workshop entr(ies) are open, without the dark reason, or say "made only in" wrongly', v_bad;
  end if;
  -- through the door: dark, every new hull refused E_NEEDS_SKILL with the dark reason
  select count(*), string_agg(e.key || ' ' || e.value, '; ') into v_bad, v_list
    from jsonb_each_text(v_p->'dark') e
   where split_part(e.value, ':', 1) <> 'E_NEEDS_SKILL' or position('ship skills are not in use yet' in e.value) = 0;
  if v_bad <> 0 or (select count(*) from jsonb_object_keys(v_p->'dark')) <> 22 then
    raise exception '0159 self-assert FAIL: dark, % new hull(s) were not refused: %', v_bad, v_list;
  end if;

  -- (h) LIT (rolled back): the hull skills at V but no specialisation — every T2 refused naming its
  --     specialisation I, with the figures have 0 / need 1; with them — every T2 BUILT for its labour
  select count(*), string_agg(e.key || ' ' || e.value, '; ') into v_bad, v_list
    from jsonb_each_text(v_p->'lit0') e join public.class_profile c on c.class_code = e.key
   where e.value not like 'E_NEEDS_SKILL: % needs ' || (select sk.name from public.skills sk where sk.code =
           case c.role when 'trade' then 'ARMED_MERCHANT' when 'combat' then 'PRIVATEERS'
                       when 'explorer' then 'SURVEY_SHIPS' else 'CONVOY_ESCORTS' end) || ' I|%'
      or (split_part(e.value, '|', 2))::jsonb is distinct from '{"have": 0, "need": 1, "unit": "level"}'::jsonb;
  if v_bad <> 0 or (select count(*) from jsonb_object_keys(v_p->'lit0')) <> 22 then
    raise exception '0159 self-assert FAIL: lit without the specialisation, % T2 hull(s) not refused with its figures: %', v_bad, v_list;
  end if;
  select count(*), string_agg(e.key || ' ' || e.value, '; ') into v_bad, v_list
    from jsonb_each_text(v_p->'lit') e join public.hull_recipes hr on hr.class_code = e.key
   where e.value <> 'ok:' || public.hull_labour(hr.class_code);
  if v_bad <> 0 or (select count(*) from jsonb_object_keys(v_p->'lit')) <> 22 then
    raise exception '0159 self-assert FAIL: lit with the skills, % T2 hull(s) were not built for their labour: %', v_bad, v_list;
  end if;

  -- (i) THE GEAR THROUGH THE WORKSHOP: a T2 module dark refused; lit with Gunnery V but no specialisation
  --     refused naming it with figures; with it, made. The Named guns made in Lisbon, refused in Venice in the
  --     one sentence the Venice workshop serves; Lisbon's serves none
  if split_part(v_p->>'t2_dark', ':', 1) <> 'E_NEEDS_SKILL' or position('ship skills are not in use yet' in v_p->>'t2_dark') = 0
     or v_p->>'t2_nospec' not like 'E_NEEDS_SKILL: Long Eighteens needs Gunnery Specialisation I|%'
     or (split_part(v_p->>'t2_nospec', '|', 2))::jsonb is distinct from '{"have": 0, "need": 1, "unit": "level"}'::jsonb
     or v_p->>'t2_made' not like 'ok:%' then
    raise exception '0159 self-assert FAIL: the T2 module''s requirements did not hold at the workshop: %',
      jsonb_build_object('dark', v_p->'t2_dark', 'nospec', v_p->'t2_nospec', 'made', v_p->'t2_made');
  end if;
  if v_p->>'named_lis' not like 'ok:%'
     or v_p->>'named_ven' <> 'E_NOT_MADE_HERE: Lisbon-cast Brass Guns is made only in Lisbon'
     or v_p->'shop_ven'->>'made_only_in' is distinct from 'Lisbon-cast Brass Guns is made only in Lisbon'
     or (v_p->'shop_ven'->>'makeable')::boolean
     or v_p->'shop_lis' ? 'made_only_in' or not (v_p->'shop_lis'->>'makeable')::boolean then
    raise exception '0159 self-assert FAIL: the Named item was not made only in its city: %',
      jsonb_build_object('lis', v_p->'named_lis', 'ven', v_p->'named_ven', 'shop_lis', v_p->'shop_lis', 'shop_ven', v_p->'shop_ven');
  end if;
  if public.skills_bite_on() or exists (select 1 from public.players where auth_uid = '00000000-0159-4000-8000-000000000001') then
    raise exception '0159 self-assert FAIL: the probe world was not rolled back';
  end if;

  -- (j) THE RE-CUTS reverse to their pre-images; ACL / volatility / definer / config unmoved
  for d in select * from defs_before_0159 order by fn loop
    v_def := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0159 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0159(v_def, h.new) <> 1 then
        raise exception '0159 self-assert FAIL: hunk % of % is not in the new body exactly once', h.n, d.fn;
      end if;
      v_def := replace(v_def, h.new, h.old);
    end loop;
    if v_def <> d.def then
      raise exception '0159 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef, coalesce(pr.proconfig::text, '') as cfg
      into v_pp from pg_proc pr where pr.oid = d.fn::regprocedure;
    if v_pp.acl <> d.acl or v_pp.vol <> d.vol or v_pp.secdef <> d.secdef or v_pp.cfg <> d.cfg then
      raise exception '0159 self-assert FAIL: % changed its ACL, volatility, definer or config', d.fn;
    end if;
  end loop;

  -- (k) THE WALL
  if (select count(*) from public.client_rpc_entry_points()) <> v_b.entry_points
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0
     or has_function_privilege('anon', 'public.made_only_in(text, uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.made_only_in(text, uuid)', 'execute')
     or has_table_privilege('anon', 'public.item_city', 'select,insert,update,delete')
     or has_table_privilege('authenticated', 'public.item_city', 'select,insert,update,delete') then
    raise exception '0159 self-assert FAIL: the registry, the grant wall or the read wall moved, or a client can reach the new function or table';
  end if;

  for v_rd in select bf.what, bf.ms as before_ms, af.ms as after_ms, bf.hulls
             from reads_0159 bf join reads_0159 af on af.what = bf.what and af.phase = 'after'
            where bf.phase = 'before' order by bf.what loop
    v_notes := v_notes || format('%s over %s merchant hull(s) %s ms → %s ms; ', v_rd.what, v_rd.hulls, v_rd.before_ms, v_rd.after_ms);
  end loop;

  raise notice '0159 self-assert ok: THE IMPROVED SHIPS AND THE NAMED GEAR. UNTOUCHED: every hull and item already in the world. LANDED: +22 T2 hulls (two a line, one place more than their T1), +44 hull requirements (⟨size⟩ Hulls V + the role''s specialisation I), +34 items (22 T2 modules: grade 5, a skill V + its specialisation I, tier-3 workshop; 12 Named, one a city), +item use and item cities. RULES: guns = attack / 10, tier, Hands, yard tier, T2 own-country; every material sold somewhere; every hull fits a shed where it is built and is buildable at ≥ 1 yard of its line; every item buys one and spends one. DARK: % old yard entries and % old workshop entries as before; every new hull and item closed with its needs; 22 refused through the door. LIT (rolled back): without the specialisation 22 refused with its figures (have 0 / need 1); with it 22 BUILT for their labour; Long Eighteens refused "%", then made; Lisbon-cast Brass Guns made in Lisbon and refused in Venice ("%"). 3 bodies reverse, no entry point. READS: %',
    (select count(*) from yards_before_0159), (select count(*) from shops_before_0159),
    split_part(v_p->>'t2_nospec', '|', 1), v_p->>'named_ven', v_notes;
end $$;
