-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0165 — A FAMOUS SHIP IS ONE TO A HOUSE  (S17 Wave D: 11 famous ships and their 11 pieces of famous
--        gear — generated, guarded, and closed until Famous Ships counts)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY NOW ─────────────────────────────────────────────────────────────────────────────────────
-- docs/SHIPS_AND_SKILLS.md §8 row S17 ("rows; famous gear as hull_recipe_items; one-per-house check in
-- the do_build door | a second famous of the same code refused for a probe house | delete rows | "Famous"
-- badge and the ship's history line"), §4.1 the famous tech, §4.3 Wave D, §4.4 the famous requirements,
-- §6.2 the Famous rung (docs/SKILLS_AND_CAPTAINS.md §9: S17 unchanged). 0135 / 0138 / 0159 put Waves A-C
-- into the world; the Famous Ships skill (0131) gates nothing yet, and class_profile's check (0130) has
-- admitted tech 'F' since it was made.
--
-- ── WHAT SAYS THE OPPOSITE TODAY, NAMED ─────────────────────────────────────────────────────────
--   * No class_profile row has tech 'F'; no item has meta 8; FAMOUS_SHIPS is in no skill_requirements row.
--   * cmd.do_build lays down as many of one class as a house can pay for: nothing says "one of each".
--   * No generated hull has a fitting in its recipe (only the live three do, 0072).
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) THE 11 FAMOUS SHIPS — scripts/build-ships.mjs Wave D (the SAME generator as 0135 / 0138 / 0159:
--     archetype × line × ONE famous uplift by role — every famous hull speed × 1.03; trade hold × 1.25,
--     hull × 1.15, attack × 1.10, handling +2, armour +6, sighting +1, +1 Low; combat attack × 1.40, hull ×
--     1.20, handling +4, armour +10, accuracy +8, sighting +1, +1 High; explorer speed × 1.06 more, hull ×
--     1.10, handling +10, armour +2, accuracy +4, sighting +5, +1 Mid; deck by T2's one rule; labour × 4;
--     goods × 2.2 + lignum vitae + sea charts, then THE SHED of 0072 (d), not loosened — and the heavy
--     explorer archetype solved from the San Juan Bautista row). `--sql D`, pasted. The hull's note is
--     its history line (the build yard serves it, 0072).
-- (2) THE FAMOUS GEAR — scripts/build-gear.mjs FAMOUS: one piece per famous ship (the Famous rung, meta 8,
--     grade 5: the G1's buys × 3.00, speed and cargo space × 2.00, spends × 1.00, Drake's Culverins'
--     accuracy +12; Deck and Hands × 1.6; needs the module skill V + Famous Ships I; made at a tier-3
--     workshop of its base type's T2 recipe × 1.5) — item_kinds, item_profile, item_effects, item_recipes,
--     item_use. `--sql-0165`, pasted. Each is its hull's ONE fitting: hull_recipe_items (11 rows) — spent
--     from the yard city's store when she is laid down, as the live three's fittings are (0072 (b): every
--     hull fitting is makeable somewhere, which is why it is made and not handed out).
-- (3) THE REQUIREMENTS (§4.4): a famous hull needs the line's ⟨size⟩ Hulls V + Famous Ships I + the role's
--     T2 specialisation III (33 rows); a famous piece its module skill V + Famous Ships I (24 rows).
-- (4) ONE OF EACH TO A HOUSE: public.famous_held(player, class) — the one sentence ("Golden Hind is a famous
--     ship, and a company keeps only one of each: yours is the Pelican.", or null) — read by cmd.do_build
--     (E_FAMOUS_HELD, after the skills, the house's row taken first so two orders of one house cannot both
--     pass) and world.building_yard (folded into `buildable`, served as `famous_held` only where it applies).
--
-- ── WHAT IT DELIBERATELY DOES NOT DO ────────────────────────────────────────────────────────────
-- No row already in the world moves (hashed); no knob, no entry point, no client write, no cron, no FK,
-- no ALTER, no index. Dark (skills_bite false): every new hull and item HAS requirements, so public.
-- requirements_unmet (0135's dark rule) closes all 22 to everyone — refused E_NEEDS_SKILL with " — ship
-- skills are not in use yet" — and nobody can hold a famous ship, so famous_held is null for every house
-- and every yard entry already in the world is its pre-image to the byte. Merchants: nothing. Said plainly,
-- the felt change while dark: the Codex and the build yard list 11 more hulls, badged Famous and refused
-- with their needs (the yard tray prints each one's history line); the workshop lists 11 more items, refused.
--
-- ── LOCKS ───────────────────────────────────────────────────────────────────────────────────────
-- Heavy reads first. Then only ROW EXCLUSIVE on catalogue tables nothing live writes (ship_classes,
-- class_profile, class_slots, class_cabins, hull_recipes(+goods, +items), item_kinds, item_profile,
-- item_effects, item_recipes, item_use, skill_requirements); their FK checks take KEY SHARE on goods /
-- skills / ship_lines / item_kinds rows. ANALYZE takes SHARE UPDATE EXCLUSIVE. CREATE OR REPLACE FUNCTION
-- locks no table. Probe writes are rolled back; a probe that meets a lock is retried 5 × 0.2 s, then LOCK
-- CONTENTION. No top-level LOCK / SET LOCAL / BEGIN / SET ROLE.
--
-- SUPERSEDES, by hunks sliced from the LIVE bodies (LF-normalised, read from production with
-- pg_get_functiondef), each asserted to occur exactly once and to reverse to its pre-image, ACL /
-- volatility / definer / config unchanged: cmd.do_build (0154), world.building_yard (0159).
--
-- ROLLBACK (forward migration): reverse the two bodies' hunks (old text in hunks_0165); drop
-- public.famous_held; delete the rows of the 11 hull codes and the 11 item codes (skill_requirements,
-- hull_recipe_items, item_use, item_recipes, item_effects, item_profile, item_kinds; hull_recipe_goods,
-- hull_recipes, class_cabins, class_slots, class_profile, ship_classes) after asserting no ship,
-- fitted_units or player_items row names one (dark, none can).
-- VERSION: 0165 (head 0164 + K9 at 0165). Applies on 0165 (K9); S16 (0163) and
-- K9 (0165) touch neither body nor any row here.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  perform set_config('random_page_cost', '1.1', true);   -- prod's planner page cost (0149's header)
end $guard$;

-- ── 0. HELPERS (pg_temp, gone at commit) ───────────────────────────────────────────────────────
create or replace function pg_temp.occurs_0165(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- One verb through its door, undone at once: 'ok:<ducats paid>' or 'E_CODE: sentence|<detail>'. A lock
-- the live world holds is not an answer: retried, then LOCK CONTENTION.
create or replace function pg_temp.try_0165(p_player uuid, p_sql text)
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
      raise exception 'PROBE_UNDO_0165:%', v_paid;
    exception when others then
      get stacked diagnostics v_msg = message_text, v_state = returned_sqlstate, v_det = pg_exception_detail;
    end;
    exit when v_state not in ('55P03', '40P01');
    if v_try >= 5 then
      raise exception '0165 self-assert FAIL: LOCK CONTENTION, not a result — % could not get its locks in 5 tries (%: %). Re-run the push.',
        p_sql, v_state, v_msg;
    end if;
    perform pg_sleep(0.2);
  end loop;
  return case when v_msg like 'PROBE_UNDO_0165:%' then 'ok:' || split_part(v_msg, ':', 2)
              else v_msg || case when coalesce(v_det, '') <> '' then '|' || v_det else '' end end;
end $$;

-- act as a company's signed-in user (a yard serves what YOU may build) — or as nobody
create or replace function pg_temp.as_0165(p_uid uuid)
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  perform set_config('request.jwt.claims', case when p_uid is null then '' else json_build_object('sub', p_uid)::text end, true);
end $$;

create temp table reads_0165 (phase text, what text, hulls bigint, ms numeric) on commit drop;
create or replace function pg_temp.time_reads_0165(p_phase text)
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
  insert into reads_0165 values (p_phase, 'speed+hold', coalesce(cardinality(v_ids), 0), round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
  v_t0 := clock_timestamp();
  perform world.ship_view(x) from unnest(v_ids) x;
  insert into reads_0165 values (p_phase, 'ship_view', coalesce(cardinality(v_ids), 0), round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
end $$;

-- ── 1. THE PRE-IMAGES (every heavy read happens here, before any write) ─────────────────────────
create temp table defs_before_0165 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('cmd.do_build(uuid, jsonb)'), ('world.building_yard(uuid)')) f(fn);

-- THIS FILE'S OWN CODES — every count below is of these rows, never of a whole table (0163's lesson: a
-- whole-table count meets whatever another migration added and fails a correct file)
create temp table own_hulls_0165 (code text primary key) on commit drop;
insert into own_hulls_0165 values ('madre'), ('sanmartin'), ('batavia'), ('goldenhind'), ('couronne'), ('duodo'), ('turgut'), ('rahimi'), ('baochuan'), ('sjb'), ('geobuk');
create temp table own_items_0165 (code text primary key) on commit drop;
insert into own_items_0165 values ('batavia-double-planking'), ('couronne-battery'), ('date-masamune-charts'), ('dragon-head-cannon'), ('drakes-culverins'), ('duodo-bow-guns'), ('madre-de-deus-holds'), ('rahimi-pilgrim-holds'), ('san-martin-tercio'), ('turgut-reis-swivels'), ('zheng-he-bulkheads');

do $pre$
begin
  if exists (select 1 from public.ship_classes where code in (select code from own_hulls_0165))
     or exists (select 1 from public.item_kinds where code in (select code from own_items_0165)) then
    raise exception '0165 self-assert FAIL: a famous hull or item code is already in the world — this file was cut against a world without them';
  end if;
end $pre$;

create temp table live_classes_0165 on commit drop as select code from public.ship_classes;
create temp table live_items_0165 on commit drop as select code from public.item_kinds;

create temp table before_0165 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select md5(string_agg(to_jsonb(c)::text, '|' order by c.code)) from public.ship_classes c) as classes_hash,
       (select md5(string_agg(to_jsonb(c)::text, '|' order by c.class_code)) from public.class_profile c) as profile_hash,
       (select md5(string_agg(to_jsonb(c)::text, '|' order by c.class_code, c.slot)) from public.class_slots c) as slots_hash,
       (select md5(string_agg(to_jsonb(c)::text, '|' order by c.class_code)) from public.class_cabins c) as cabins_hash,
       (select md5(string_agg(to_jsonb(c)::text, '|' order by c.class_code)) from public.hull_recipes c) as recipes_hash,
       (select md5(string_agg(to_jsonb(c)::text, '|' order by c.class_code, c.good_id)) from public.hull_recipe_goods c) as recipe_goods_hash,
       (select md5(string_agg(to_jsonb(c)::text, '|' order by c.class_code, c.item_code)) from public.hull_recipe_items c) as recipe_items_hash,
       (select md5(string_agg(to_jsonb(c)::text, '|' order by c.subject_kind, c.subject_code, c.skill_code)) from public.skill_requirements c) as requirements_hash,
       (select md5(string_agg(to_jsonb(c)::text, '|' order by c.code)) from public.item_kinds c) as kinds_hash,
       (select md5(string_agg(to_jsonb(c)::text, '|' order by c.item_code)) from public.item_profile c) as iprofile_hash,
       (select md5(string_agg(to_jsonb(c)::text, '|' order by c.item_code, c.stat)) from public.item_effects c) as effects_hash,
       (select md5(string_agg(format('%s/%s/%s', c.item_code, c.good_id, c.qty), '|' order by c.item_code, c.good_id)) from public.item_recipes c) as item_recipes_hash,
       (select md5(string_agg(to_jsonb(c)::text, '|' order by c.item_code)) from public.item_use c) as use_hash;

-- what the build yards and the workshops serve, as found (no company: the migration has no auth.uid())
create temp table yards_before_0165 on commit drop as
select b.port_id, h.value->>'class' as class, h.value as entry
  from public.port_buildings b
 cross join lateral jsonb_array_elements(world.building_yard(b.port_id)->'hulls') h
 where b.kind = 'building_yard';
create temp table shops_before_0165 on commit drop as
select b.port_id, i.value->>'code' as code, i.value as entry
  from public.port_buildings b
 cross join lateral jsonb_array_elements(world.workstation(b.port_id)->'items') i
 where b.kind = 'workstation';

select pg_temp.time_reads_0165('before');

-- ── 2. THE 11 FAMOUS SHIPS (scripts/build-ships.mjs --sql D, verbatim) ──────────────────────────
insert into public.ship_classes
  (code, name, family, rig, hold, crew_required, crew_max, speed_kn, durability, guns, draft,
   build_hours, build_cost, tier, handling, armour, attack, accuracy, reach, sighting) values
  ('madre', 'Madre de Deus', 'Western', 'square', 1875, 200, 500, 4.00, 5750, 24, 5, 360.00, 2766000.00, 5, 32, 48, 240, 50, 65, 14.0),
  ('sanmartin', 'San Martín', 'Western', 'square', 800, 368, 862, 4.00, 7730, 77, 5, 360.00, 3358000.00, 5, 32, 71, 770, 72, 89, 16.0),
  ('batavia', 'Batavia', 'Western', 'square', 940, 60, 150, 4.40, 2480, 9, 3, 144.00, 700000.00, 4, 44, 34, 90, 50, 65, 14.0),
  ('goldenhind', 'Golden Hind', 'Western', 'mixed', 85, 12, 30, 6.90, 570, 2, 1, 40.00, 118000.00, 2, 91, 12, 20, 52, 53, 15.0),
  ('couronne', 'La Couronne', 'Western', 'square', 600, 200, 480, 4.60, 4800, 50, 5, 240.00, 1798000.00, 5, 44, 58, 500, 74, 82, 16.0),
  ('duodo', 'Galeazza di Duodo', 'Mediterranean', 'oared', 540, 270, 648, 4.40, 4560, 55, 4, 240.00, 1874000.00, 5, 48, 58, 550, 72, 72, 15.0),
  ('turgut', 'Turgut Reis''s Kadırga', 'Mediterranean', 'oared', 285, 112, 275, 4.80, 2640, 27, 3, 96.00, 560000.00, 3, 56, 48, 270, 66, 68, 15.0),
  ('rahimi', 'Rahimi', 'Indian Ocean', 'mixed', 2025, 170, 425, 4.20, 6040, 15, 4, 360.00, 2450000.00, 5, 36, 46, 150, 40, 55, 15.0),
  ('baochuan', 'Baochuan (treasure ship)', 'East Asian', 'lateen', 2155, 200, 500, 3.80, 6900, 22, 5, 360.00, 2392000.00, 5, 24, 54, 220, 46, 65, 14.0),
  ('sjb', 'San Juan Bautista', 'East Asian', 'square', 360, 80, 207, 5.50, 2300, 11, 3, 144.00, 792000.00, 4, 64, 32, 110, 60, 57, 23.0),
  ('geobuk', 'Geobukseon (turtle ship)', 'East Asian', 'oared', 270, 99, 242, 4.80, 2640, 26, 3, 96.00, 552000.00, 3, 56, 54, 260, 70, 72, 15.0)
on conflict (code) do nothing;

insert into public.class_profile (class_code, line_code, size, role, tech, deck, any_yard) values
  ('madre', 'PRT', 6, 'trade', 'F', 156, false),
  ('sanmartin', 'ESP', 6, 'combat', 'F', 168, false),
  ('batavia', 'NLD', 4, 'trade', 'F', 84, false),
  ('goldenhind', 'ENG', 2, 'explorer', 'F', 24, false),
  ('couronne', 'FRA', 5, 'combat', 'F', 130, false),
  ('duodo', 'ITA', 5, 'combat', 'F', 130, false),
  ('turgut', 'OTT', 3, 'combat', 'F', 71, false),
  ('rahimi', 'IND', 6, 'trade', 'F', 156, false),
  ('baochuan', 'CHN', 6, 'trade', 'F', 156, false),
  ('sjb', 'JPN', 4, 'explorer', 'F', 78, false),
  ('geobuk', 'KOR', 3, 'combat', 'F', 71, false)
on conflict (class_code) do nothing;

insert into public.class_slots (class_code, slot, count) values
  ('madre', 'high', 4),
  ('madre', 'mid', 7),
  ('madre', 'low', 5),
  ('madre', 'refit', 3),
  ('madre', 'flourish', 1),
  ('sanmartin', 'high', 8),
  ('sanmartin', 'mid', 6),
  ('sanmartin', 'low', 2),
  ('sanmartin', 'refit', 3),
  ('sanmartin', 'flourish', 1),
  ('batavia', 'high', 3),
  ('batavia', 'mid', 6),
  ('batavia', 'low', 3),
  ('batavia', 'refit', 2),
  ('batavia', 'flourish', 1),
  ('goldenhind', 'high', 2),
  ('goldenhind', 'mid', 4),
  ('goldenhind', 'refit', 1),
  ('couronne', 'high', 7),
  ('couronne', 'mid', 6),
  ('couronne', 'low', 2),
  ('couronne', 'refit', 3),
  ('couronne', 'flourish', 1),
  ('duodo', 'high', 7),
  ('duodo', 'mid', 6),
  ('duodo', 'low', 2),
  ('duodo', 'refit', 3),
  ('duodo', 'flourish', 1),
  ('turgut', 'high', 5),
  ('turgut', 'mid', 5),
  ('turgut', 'low', 1),
  ('turgut', 'refit', 2),
  ('turgut', 'flourish', 1),
  ('rahimi', 'high', 4),
  ('rahimi', 'mid', 7),
  ('rahimi', 'low', 5),
  ('rahimi', 'refit', 3),
  ('rahimi', 'flourish', 1),
  ('baochuan', 'high', 4),
  ('baochuan', 'mid', 7),
  ('baochuan', 'low', 5),
  ('baochuan', 'refit', 3),
  ('baochuan', 'flourish', 1),
  ('sjb', 'high', 2),
  ('sjb', 'mid', 8),
  ('sjb', 'low', 2),
  ('sjb', 'refit', 2),
  ('sjb', 'flourish', 1),
  ('geobuk', 'high', 5),
  ('geobuk', 'mid', 5),
  ('geobuk', 'low', 1),
  ('geobuk', 'refit', 2),
  ('geobuk', 'flourish', 1)
on conflict (class_code, slot) do nothing;

insert into public.class_cabins (class_code, cabins) values
  ('madre', 8),
  ('sanmartin', 8),
  ('batavia', 6),
  ('goldenhind', 4),
  ('couronne', 7),
  ('duodo', 7),
  ('turgut', 5),
  ('rahimi', 8),
  ('baochuan', 8),
  ('sjb', 6),
  ('geobuk', 5)
on conflict (class_code) do nothing;

insert into public.hull_recipes (class_code, yard_tier, ducats, note) values
  ('madre', 3, 691500, 'The great Portuguese carrack taken by the English off the Azores in 1592, the richest prize ever brought into an English port.'),
  ('sanmartin', 3, 839500, 'The flagship of the Duke of Medina Sidonia in the Armada of 1588, which fought through the Channel and came home.'),
  ('batavia', 3, 175000, 'The Dutch East India Company ship wrecked on the Abrolhos reefs off Australia on her maiden voyage in 1629.'),
  ('goldenhind', 2, 29500, 'The galleon in which Francis Drake sailed round the world between 1577 and 1580, the second ship ever to do it.'),
  ('couronne', 3, 449500, 'The first great French ship of the line, built at La Roche-Bernard for Richelieu in 1636.'),
  ('duodo', 3, 468500, 'The Venetian galleass of Francesco Duodo''s squadron, whose guns broke the Ottoman line at Lepanto in 1571.'),
  ('turgut', 3, 140000, 'The war galley of Turgut Reis, the corsair admiral who raided the Christian coasts and fell at the siege of Malta in 1565.'),
  ('rahimi', 3, 612500, 'The great pilgrim ship of the Mughal queen mother, the largest ship of the Red Sea trade until the Portuguese burned it in 1614.'),
  ('baochuan', 3, 598000, 'A treasure ship of Zheng He''s fleets, which sailed from Nanjing to India, Arabia and Africa between 1405 and 1433.'),
  ('sjb', 3, 198000, 'The galleon Date Masamune built in 1613 to carry Hasekura Tsunenaga across the Pacific to Acapulco, and on to Rome.'),
  ('geobuk', 3, 138000, 'Yi Sun-sin''s turtle ship, its back plated and spiked against boarders, which led the Joseon fleet against Japan in 1592.')
on conflict (class_code) do nothing;

create temp table hull_goods_0165 (class_code text, good_code text, qty numeric) on commit drop;
insert into hull_goods_0165 values
  ('madre', 'live-oak', 182),
  ('madre', 'naval-timber', 81),
  ('madre', 'timber', 121),
  ('madre', 'tar', 50),
  ('madre', 'ships-nails', 81),
  ('madre', 'lignum-vitae', 18),
  ('madre', 'sea-charts', 1),
  ('sanmartin', 'live-oak', 182),
  ('sanmartin', 'naval-timber', 81),
  ('sanmartin', 'timber', 121),
  ('sanmartin', 'tar', 50),
  ('sanmartin', 'ships-nails', 81),
  ('sanmartin', 'lignum-vitae', 18),
  ('sanmartin', 'sea-charts', 1),
  ('batavia', 'timber', 304),
  ('batavia', 'memel-fir', 81),
  ('batavia', 'stockholm-tar', 50),
  ('batavia', 'ships-nails', 81),
  ('batavia', 'lignum-vitae', 18),
  ('batavia', 'sea-charts', 1),
  ('goldenhind', 'timber', 154),
  ('goldenhind', 'naval-timber', 44),
  ('goldenhind', 'tar', 26),
  ('goldenhind', 'cordage', 22),
  ('goldenhind', 'ships-nails', 40),
  ('goldenhind', 'lignum-vitae', 20),
  ('goldenhind', 'sea-charts', 2),
  ('couronne', 'timber', 304),
  ('couronne', 'naval-timber', 81),
  ('couronne', 'tar', 50),
  ('couronne', 'ships-nails', 81),
  ('couronne', 'lignum-vitae', 18),
  ('couronne', 'sea-charts', 1),
  ('duodo', 'timber', 304),
  ('duodo', 'naval-timber', 81),
  ('duodo', 'tar', 50),
  ('duodo', 'ships-nails', 81),
  ('duodo', 'lignum-vitae', 18),
  ('duodo', 'sea-charts', 1),
  ('turgut', 'timber', 304),
  ('turgut', 'cedar', 81),
  ('turgut', 'tar', 50),
  ('turgut', 'ships-nails', 81),
  ('turgut', 'lignum-vitae', 18),
  ('turgut', 'sea-charts', 1),
  ('rahimi', 'teak', 390),
  ('rahimi', 'coir', 51),
  ('rahimi', 'coco-fibre', 82),
  ('rahimi', 'lignum-vitae', 18),
  ('rahimi', 'sea-charts', 1),
  ('baochuan', 'timber', 385),
  ('baochuan', 'tar', 50),
  ('baochuan', 'ships-nails', 81),
  ('baochuan', 'lignum-vitae', 18),
  ('baochuan', 'sea-charts', 1),
  ('sjb', 'timber', 411),
  ('sjb', 'tar', 54),
  ('sjb', 'iron', 86),
  ('sjb', 'lignum-vitae', 19),
  ('sjb', 'sea-charts', 1),
  ('geobuk', 'timber', 411),
  ('geobuk', 'tar', 54),
  ('geobuk', 'iron', 86),
  ('geobuk', 'lignum-vitae', 19),
  ('geobuk', 'sea-charts', 1);
insert into public.hull_recipe_goods (class_code, good_id, qty)
select w.class_code, g.id, w.qty from hull_goods_0165 w join public.goods g on g.code = w.good_code
on conflict (class_code, good_id) do nothing;

insert into public.skill_requirements (subject_kind, subject_code, skill_code, level) values
  ('hull', 'madre', 'PRT_CAPITAL', 5),
  ('hull', 'madre', 'FAMOUS_SHIPS', 1),
  ('hull', 'madre', 'ARMED_MERCHANT', 3),
  ('hull', 'sanmartin', 'ESP_CAPITAL', 5),
  ('hull', 'sanmartin', 'FAMOUS_SHIPS', 1),
  ('hull', 'sanmartin', 'PRIVATEERS', 3),
  ('hull', 'batavia', 'NLD_HEAVY', 5),
  ('hull', 'batavia', 'FAMOUS_SHIPS', 1),
  ('hull', 'batavia', 'ARMED_MERCHANT', 3),
  ('hull', 'goldenhind', 'ENG_LIGHT', 5),
  ('hull', 'goldenhind', 'FAMOUS_SHIPS', 1),
  ('hull', 'goldenhind', 'SURVEY_SHIPS', 3),
  ('hull', 'couronne', 'FRA_CAPITAL', 5),
  ('hull', 'couronne', 'FAMOUS_SHIPS', 1),
  ('hull', 'couronne', 'PRIVATEERS', 3),
  ('hull', 'duodo', 'ITA_CAPITAL', 5),
  ('hull', 'duodo', 'FAMOUS_SHIPS', 1),
  ('hull', 'duodo', 'PRIVATEERS', 3),
  ('hull', 'turgut', 'OTT_MEDIUM', 5),
  ('hull', 'turgut', 'FAMOUS_SHIPS', 1),
  ('hull', 'turgut', 'PRIVATEERS', 3),
  ('hull', 'rahimi', 'IND_CAPITAL', 5),
  ('hull', 'rahimi', 'FAMOUS_SHIPS', 1),
  ('hull', 'rahimi', 'ARMED_MERCHANT', 3),
  ('hull', 'baochuan', 'CHN_CAPITAL', 5),
  ('hull', 'baochuan', 'FAMOUS_SHIPS', 1),
  ('hull', 'baochuan', 'ARMED_MERCHANT', 3),
  ('hull', 'sjb', 'JPN_HEAVY', 5),
  ('hull', 'sjb', 'FAMOUS_SHIPS', 1),
  ('hull', 'sjb', 'SURVEY_SHIPS', 3),
  ('hull', 'geobuk', 'KOR_MEDIUM', 5),
  ('hull', 'geobuk', 'FAMOUS_SHIPS', 1),
  ('hull', 'geobuk', 'PRIVATEERS', 3)
on conflict (subject_kind, subject_code, skill_code) do nothing;

-- ── 3. THE 11 PIECES OF FAMOUS GEAR (scripts/build-gear.mjs --sql-0165, verbatim) ───────────────
insert into public.item_kinds (code, name, slot, buys, spends, note, volume, ws_tier) values
  ('madre-de-deus-holds', 'Madre de Deus Holds', 'hull', 'Hold', 'Speed, Handling', 'The deep cargo space of the great carrack taken off the Azores in 1592, whose pepper, silks and jewels filled a London custom house.', 3, 3),
  ('san-martin-tercio', 'San Martín Tercio Arms', 'weapon', 'Attack at close quarters', 'Reach', 'The pikes, grapnels and breastplates of the soldiers Medina Sidonia carried in his flagship in 1588, ready to board.', 3, 3),
  ('batavia-double-planking', 'Batavia Double Planking', 'hull', 'Armour, Hull', 'Speed, Cargo space', 'The doubled planking of the Dutch East India ship lost on the Abrolhos in 1629, laid two skins deep for the long voyage east.', 4, 3),
  ('drakes-culverins', 'Drake''s Culverins', 'weapon', 'Attack, Reach, Accuracy', 'Hold, Handling', 'The culverins Francis Drake carried round the world in 1577-1580: they hit harder, reach further and shoot straighter than any battery.', 6, 3),
  ('couronne-battery', 'La Couronne Battery', 'weapon', 'Attack, Reach', 'Hold, Handling', 'The great battery of the first French ship of the line, launched at La Roche-Bernard in 1636.', 6, 3),
  ('duodo-bow-guns', 'Duodo Bow Guns', 'weapon', 'Reach, Accuracy', 'Cargo space', 'The heavy bow guns of the Venetian galleasses Francesco Duodo led at Lepanto in 1571, which broke the Ottoman line before it closed.', 4, 3),
  ('turgut-reis-swivels', 'Turgut Reis Swivels', 'weapon', 'Attack, Accuracy', 'Handling', 'The rail swivels of the corsair admiral Turgut Reis, which swept a Christian deck before his men went over the side.', 2, 3),
  ('rahimi-pilgrim-holds', 'Rahimi Pilgrim Holds', 'hull', 'Hold', 'Speed, Handling', 'The vast cargo space of the Mughal queen mother''s pilgrim ship, the largest in the Red Sea trade until the Portuguese burned it in 1614.', 3, 3),
  ('zheng-he-bulkheads', 'Zheng He Bulkheads', 'hull', 'Armour, Hull', 'Speed, Cargo space', 'The watertight bulkheads and layered planking of Zheng He''s treasure ships, which sailed as far as Africa between 1405 and 1433.', 4, 3),
  ('date-masamune-charts', 'Date Masamune Charts', 'lookout', 'Sighting, Handling', 'Cargo space', 'The binnacle and Pacific charts of the galleon Date Masamune sent to Acapulco in 1613 with Hasekura Tsunenaga on board.', 2, 3),
  ('dragon-head-cannon', 'Dragon-head Cannon', 'weapon', 'Attack at close range', 'Reach, Cargo space, Handling', 'The cannon fired through the dragon''s mouth of Yi Sun-sin''s turtle ship, which smashed Japanese hulls at close range in 1592.', 5, 3)
on conflict (code) do nothing;

insert into public.item_profile (item_code, base_type, rack, grade, meta, deck, hands, active) values
  ('madre-de-deus-holds', 'Hold Frames', 'low', 5, 8, 3, 0, false),
  ('san-martin-tercio', 'Boarding Gear', 'high', 5, 8, 3, 8, true),
  ('batavia-double-planking', 'Planking', 'low', 5, 8, 6, 0, false),
  ('drakes-culverins', 'Long Guns', 'high', 5, 8, 10, 13, true),
  ('couronne-battery', 'Long Guns', 'high', 5, 8, 10, 13, true),
  ('duodo-bow-guns', 'Chase Guns', 'high', 5, 8, 6, 6, true),
  ('turgut-reis-swivels', 'Swivel Guns', 'high', 5, 8, 3, 5, true),
  ('rahimi-pilgrim-holds', 'Hold Frames', 'low', 5, 8, 3, 0, false),
  ('zheng-he-bulkheads', 'Planking', 'low', 5, 8, 6, 0, false),
  ('date-masamune-charts', 'Binnacle & Charts', 'mid', 5, 8, 3, 2, false),
  ('dragon-head-cannon', 'Carronades', 'high', 5, 8, 8, 11, true)
on conflict (item_code) do nothing;

insert into public.item_effects (item_code, stat, delta) values
  ('madre-de-deus-holds', 'hold', 50),
  ('madre-de-deus-holds', 'speed', -0.35),
  ('madre-de-deus-holds', 'handling', -5),
  ('san-martin-tercio', 'attack', 105),
  ('san-martin-tercio', 'reach', -20),
  ('batavia-double-planking', 'armour', 30),
  ('batavia-double-planking', 'durability', 480),
  ('batavia-double-planking', 'speed', -0.45),
  ('batavia-double-planking', 'hold', -12),
  ('drakes-culverins', 'attack', 180),
  ('drakes-culverins', 'reach', 45),
  ('drakes-culverins', 'hold', -20),
  ('drakes-culverins', 'handling', -6),
  ('drakes-culverins', 'accuracy', 12),
  ('couronne-battery', 'attack', 180),
  ('couronne-battery', 'reach', 45),
  ('couronne-battery', 'hold', -20),
  ('couronne-battery', 'handling', -6),
  ('duodo-bow-guns', 'reach', 60),
  ('duodo-bow-guns', 'accuracy', 30),
  ('duodo-bow-guns', 'hold', -8),
  ('turgut-reis-swivels', 'attack', 60),
  ('turgut-reis-swivels', 'accuracy', 24),
  ('turgut-reis-swivels', 'handling', -2),
  ('rahimi-pilgrim-holds', 'hold', 50),
  ('rahimi-pilgrim-holds', 'speed', -0.35),
  ('rahimi-pilgrim-holds', 'handling', -5),
  ('zheng-he-bulkheads', 'armour', 30),
  ('zheng-he-bulkheads', 'durability', 480),
  ('zheng-he-bulkheads', 'speed', -0.45),
  ('zheng-he-bulkheads', 'hold', -12),
  ('date-masamune-charts', 'sighting', 9),
  ('date-masamune-charts', 'handling', 15),
  ('date-masamune-charts', 'hold', -3),
  ('dragon-head-cannon', 'attack', 270),
  ('dragon-head-cannon', 'reach', -15),
  ('dragon-head-cannon', 'hold', -14),
  ('dragon-head-cannon', 'handling', -4)
on conflict (item_code, stat) do nothing;

create temp table item_goods_0165 (item_code text, good_code text, qty numeric) on commit drop;
insert into item_goods_0165 values
  ('madre-de-deus-holds', 'naval-timber', 15),
  ('madre-de-deus-holds', 'greenheart', 30),
  ('madre-de-deus-holds', 'copper-sheet', 15),
  ('madre-de-deus-holds', 'swedish-iron', 3),
  ('san-martin-tercio', 'swedish-iron', 8),
  ('san-martin-tercio', 'abaca', 6),
  ('san-martin-tercio', 'gunpowder', 5),
  ('san-martin-tercio', 'falconet', 2),
  ('san-martin-tercio', 'slow-match', 2),
  ('batavia-double-planking', 'greenheart', 36),
  ('batavia-double-planking', 'lignum-vitae', 18),
  ('batavia-double-planking', 'copper-sheet', 15),
  ('batavia-double-planking', 'swedish-iron', 6),
  ('drakes-culverins', 'swedish-iron', 15),
  ('drakes-culverins', 'culverin', 18),
  ('drakes-culverins', 'falconet', 6),
  ('drakes-culverins', 'gunpowder', 6),
  ('couronne-battery', 'swedish-iron', 15),
  ('couronne-battery', 'culverin', 18),
  ('couronne-battery', 'falconet', 6),
  ('couronne-battery', 'gunpowder', 6),
  ('duodo-bow-guns', 'copper', 15),
  ('duodo-bow-guns', 'tin-ingots', 9),
  ('duodo-bow-guns', 'culverin', 12),
  ('duodo-bow-guns', 'falconet', 5),
  ('duodo-bow-guns', 'gunpowder', 3),
  ('turgut-reis-swivels', 'copper', 9),
  ('turgut-reis-swivels', 'tin-ingots', 6),
  ('turgut-reis-swivels', 'swivel-gun', 3),
  ('turgut-reis-swivels', 'falconet', 2),
  ('turgut-reis-swivels', 'gunpowder', 3),
  ('rahimi-pilgrim-holds', 'naval-timber', 15),
  ('rahimi-pilgrim-holds', 'greenheart', 30),
  ('rahimi-pilgrim-holds', 'copper-sheet', 15),
  ('rahimi-pilgrim-holds', 'swedish-iron', 3),
  ('zheng-he-bulkheads', 'greenheart', 36),
  ('zheng-he-bulkheads', 'lignum-vitae', 18),
  ('zheng-he-bulkheads', 'copper-sheet', 15),
  ('zheng-he-bulkheads', 'swedish-iron', 6),
  ('date-masamune-charts', 'lodestone', 5),
  ('date-masamune-charts', 'sea-charts', 6),
  ('date-masamune-charts', 'brass-ingots', 5),
  ('date-masamune-charts', 'lignum-vitae', 2),
  ('dragon-head-cannon', 'copper', 18),
  ('dragon-head-cannon', 'tin-ingots', 12),
  ('dragon-head-cannon', 'falconet', 6),
  ('dragon-head-cannon', 'gunpowder', 6);
insert into public.item_recipes (item_code, good_id, qty)
select w.item_code, g.id, w.qty from item_goods_0165 w join public.goods g on g.code = w.good_code
on conflict (item_code, good_id) do nothing;

insert into public.skill_requirements (subject_kind, subject_code, skill_code, level) values
  ('item', 'madre-de-deus-holds', 'CARGO_STOWAGE', 5),
  ('item', 'madre-de-deus-holds', 'FAMOUS_SHIPS', 1),
  ('item', 'san-martin-tercio', 'BOARDING', 5),
  ('item', 'san-martin-tercio', 'FAMOUS_SHIPS', 1),
  ('item', 'batavia-double-planking', 'SHIPWRIGHT', 5),
  ('item', 'batavia-double-planking', 'FAMOUS_SHIPS', 1),
  ('item', 'drakes-culverins', 'GUNNERY', 5),
  ('item', 'drakes-culverins', 'FAMOUS_SHIPS', 1),
  ('item', 'couronne-battery', 'GUNNERY', 5),
  ('item', 'couronne-battery', 'FAMOUS_SHIPS', 1),
  ('item', 'duodo-bow-guns', 'GUNNERY', 5),
  ('item', 'duodo-bow-guns', 'FAMOUS_SHIPS', 1),
  ('item', 'duodo-bow-guns', 'LONG_GUNS', 1),
  ('item', 'turgut-reis-swivels', 'GUNNERY', 5),
  ('item', 'turgut-reis-swivels', 'FAMOUS_SHIPS', 1),
  ('item', 'rahimi-pilgrim-holds', 'CARGO_STOWAGE', 5),
  ('item', 'rahimi-pilgrim-holds', 'FAMOUS_SHIPS', 1),
  ('item', 'zheng-he-bulkheads', 'SHIPWRIGHT', 5),
  ('item', 'zheng-he-bulkheads', 'FAMOUS_SHIPS', 1),
  ('item', 'date-masamune-charts', 'INSTRUMENTS', 5),
  ('item', 'date-masamune-charts', 'FAMOUS_SHIPS', 1),
  ('item', 'dragon-head-cannon', 'GUNNERY', 5),
  ('item', 'dragon-head-cannon', 'FAMOUS_SHIPS', 1),
  ('item', 'dragon-head-cannon', 'SHORT_GUNS', 1)
on conflict (subject_kind, subject_code, skill_code) do nothing;

insert into public.item_use (item_code, trigger, consumes) values
  ('batavia-double-planking', 'STORM', '[]'),
  ('couronne-battery', 'PIRATES', '[{"good":"shot-and-ball","qty":1},{"good":"gunpowder","qty":1}]'),
  ('date-masamune-charts', 'MILES', '[]'),
  ('dragon-head-cannon', 'PIRATES', '[{"good":"shot-and-ball","qty":1},{"good":"gunpowder","qty":1}]'),
  ('drakes-culverins', 'PIRATES', '[{"good":"shot-and-ball","qty":1},{"good":"gunpowder","qty":1}]'),
  ('duodo-bow-guns', 'PIRATES', '[{"good":"shot-and-ball","qty":1},{"good":"gunpowder","qty":1}]'),
  ('madre-de-deus-holds', 'STORM', '[]'),
  ('rahimi-pilgrim-holds', 'STORM', '[]'),
  ('san-martin-tercio', 'PIRATES', '[]'),
  ('turgut-reis-swivels', 'PIRATES', '[{"good":"shot-and-ball","qty":1},{"good":"gunpowder","qty":1}]'),
  ('zheng-he-bulkheads', 'STORM', '[]')
on conflict (item_code) do nothing;

-- ── 4. EACH FAMOUS SHIP'S ONE FITTING IS HER FAMOUS GEAR (scripts/build-ships.mjs --sql D) ───────
insert into public.hull_recipe_items (class_code, item_code, qty) values
  ('madre', 'madre-de-deus-holds', 1),
  ('sanmartin', 'san-martin-tercio', 1),
  ('batavia', 'batavia-double-planking', 1),
  ('goldenhind', 'drakes-culverins', 1),
  ('couronne', 'couronne-battery', 1),
  ('duodo', 'duodo-bow-guns', 1),
  ('turgut', 'turgut-reis-swivels', 1),
  ('rahimi', 'rahimi-pilgrim-holds', 1),
  ('baochuan', 'zheng-he-bulkheads', 1),
  ('sjb', 'date-masamune-charts', 1),
  ('geobuk', 'dragon-head-cannon', 1)
on conflict (class_code, item_code) do nothing;

-- ── 5. ONE OF EACH TO A HOUSE — the one sentence ────────────────────────────────────────────────
create or replace function public.famous_held(p_player uuid, p_class text)
returns text
language sql
stable
set search_path = public, pg_temp
as $fh$
  -- 0165 (S17, §4.1 "unique per house (one of each)"): THE ONE SENTENCE OF "YOU KEEP HER ALREADY" — null
  -- unless p_class is a famous hull (class_profile.tech 'F') and this house keeps a ship of that class; else
  -- "Golden Hind is a famous ship, and a company keeps only one of each: yours is the Pelican." Read by
  -- cmd.do_build (E_FAMOUS_HELD) and world.building_yard (`buildable`, `famous_held`).
  select format('%s is a famous ship, and a company keeps only one of each: yours is the %s.', c.name, s.name)
    from public.class_profile cp
    join public.ship_classes c on c.code = cp.class_code
    join public.ships s on s.class_id = c.id and s.player_id = p_player
   where cp.class_code = p_class and cp.tech = 'F'
   order by s.created_at, s.id
   limit 1
$fh$;
comment on function public.famous_held(uuid, text) is
  '0165 (S17): the "a company keeps only one of each" sentence of a famous hull the house already keeps, or null. Server-only.';
revoke all on function public.famous_held(uuid, text) from public, anon, authenticated;

-- ── 6. THE HUNKS (old → new), sliced from the live bodies ──────────────────────────────────────
create temp table hunks_0165 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0165 values
('cmd.do_build(uuid, jsonb)', 1,
$h$  if not public.requirements_met(f.player_id, 'hull', c.code) then
    perform cmd.refuse('E_NEEDS_SKILL', public.requirements_refusal(f.player_id, 'hull', c.code),
      (select cmd.figures(u.have, u.need, 'level')
         from public.requirements_unmet(f.player_id, 'hull', c.code) u order by u.skill_name limit 1));
  end if;
$h$,
$h$  if not public.requirements_met(f.player_id, 'hull', c.code) then
    perform cmd.refuse('E_NEEDS_SKILL', public.requirements_refusal(f.player_id, 'hull', c.code),
      (select cmd.figures(u.have, u.need, 'level')
         from public.requirements_unmet(f.player_id, 'hull', c.code) u order by u.skill_name limit 1));
  end if;
  -- 0165 (S17): ONE OF EACH FAMOUS SHIP TO A HOUSE — public.famous_held, the one sentence (the build yard
  -- serves the same one). A famous hull takes the house's row first, so two orders of one house wait on
  -- each other and the second meets the first one's ship.
  if exists (select 1 from public.class_profile cp where cp.class_code = c.code and cp.tech = 'F') then
    perform 1 from public.players where id = f.player_id for update;
    if public.famous_held(f.player_id, c.code) is not null then
      perform cmd.refuse('E_FAMOUS_HELD', public.famous_held(f.player_id, c.code));
    end if;
  end if;
$h$),
('world.building_yard(uuid)', 1,
$h$                     and yw.needs is null,                                               -- 0133: and its skills
$h$,
$h$                     and yw.needs is null                                                -- 0133: and its skills
                     and yw.held is null,                                                -- 0165: and, a famous ship, not one it keeps
$h$),
('world.building_yard(uuid)', 2,
$h$        || case when cp.tech is distinct from 'T1' then jsonb_build_object('tech', cp.tech) else '{}'::jsonb end
$h$,
$h$        || case when cp.tech is distinct from 'T1' then jsonb_build_object('tech', cp.tech) else '{}'::jsonb end
        -- 0165: a famous ship the company keeps already says so (public.famous_held), only then
        || case when yw.held is null then '{}'::jsonb else jsonb_build_object('famous_held', yw.held) end
$h$),
('world.building_yard(uuid)', 3,
$h$                                 public.requirements_refusal(v_player, 'hull', c.code) as needs) yw));   -- 0133
$h$,
$h$                                 public.requirements_refusal(v_player, 'hull', c.code) as needs,         -- 0133
                                 public.famous_held(v_player, c.code) as held) yw));                     -- 0165
$h$);

create or replace function pg_temp.recut_0165(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := replace(pg_get_functiondef(p_fn::regprocedure), E'\r', '');
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0165 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0165(v_def, h.old);
    if v_n <> 1 then
      raise exception '0165 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0165(fn) from defs_before_0165 order by fn;

-- one hull of a build yard, as the company's own user sees it
create or replace function pg_temp.yard_hull_0165(p_uid uuid, p_port uuid, p_class text)
returns jsonb
language plpgsql
as $$
declare
  v jsonb;
begin
  perform pg_temp.as_0165(p_uid);
  select h into v from jsonb_array_elements(world.building_yard(p_port)->'hulls') h where h->>'class' = p_class;
  perform pg_temp.as_0165(null);
  return v;
end $$;

-- ── 7. THE PROBE (its own company, which builds its own state; rolled back whole) ─────────────────
create or replace function pg_temp.probe_0165()
returns jsonb
language plpgsql
as $$
declare
  c_uid    constant uuid := '00000000-0165-4000-8000-000000000001';
  v_player uuid;
  v_fleet  uuid;
  v_barca  uuid;
  v_lis    uuid := (select id from public.ports where code = 'LIS');
  v_out    jsonb := '{}'::jsonb;
  v_dark   jsonb := '{}'::jsonb;
  v_lit    jsonb := '{}'::jsonb;
  v_gh     uuid;
  v_tg     uuid;
  h        record;
  v_cargo  jsonb;
begin
  begin
    update public.world_config set value = 'false'::jsonb where key = 'skills_bite';   -- own precondition
    v_player := public.new_house(c_uid, 'Casa da Prova 0165', 'PRT', 'LIS');
    select id into v_fleet from public.fleets where player_id = v_player;
    select id into v_barca from public.ships where fleet_id = v_fleet;
    perform public.credit(v_player, 'PROBE_0165', 100000000);
    -- a fleet of two hulls is the SEAMANSHIP-0 cap (0107); the probe keeps a famous ship beside its barca and
    -- lays down a third, so it holds SEAMANSHIP III (a live skill, read whatever skills_bite says)
    insert into public.player_skills (player_id, skill_id, level)
    select v_player, sk.id, 3 from public.skills sk where sk.code = 'SEAMANSHIP'
    on conflict (player_id, skill_id) do update set level = excluded.level;
    -- every famous hull at a build yard of its line (the first by tier, then code), its goods and its famous
    -- gear ashore there
    create temp table if not exists probe_yards_0165 (class text primary key, yard uuid) on commit drop;
    delete from probe_yards_0165;
    insert into probe_yards_0165
    select c.code,
           (select b.port_id from public.port_buildings b join public.ports p on p.id = b.port_id
             where b.kind = 'building_yard' and b.tier >= hr.yard_tier
               and public.yard_wrong_country(b.port_id, c.code) is null
             order by b.tier desc, p.code limit 1)
      from public.ship_classes c join public.hull_recipes hr on hr.class_code = c.code
     where c.code in (select code from own_hulls_0165);
    insert into public.player_storage (player_id, port_id, good_id, qty)
    select v_player, y.yard, hg.good_id, 2 * max(hg.qty)
      from probe_yards_0165 y join public.hull_recipe_goods hg on hg.class_code = y.class
     where y.yard is not null
     group by y.yard, hg.good_id
    on conflict (player_id, port_id, good_id) do update set qty = excluded.qty;
    insert into public.player_items (player_id, port_id, item_code, qty)
    select v_player, y.yard, hi.item_code, 2 * hi.qty
      from probe_yards_0165 y join public.hull_recipe_items hi on hi.class_code = y.class
     where y.yard is not null
    on conflict (player_id, port_id, item_code) do update set qty = excluded.qty;

    -- (H1) DARK: every one refused
    for h in select * from probe_yards_0165 where yard is not null order by class loop
      update public.fleets set port_id = h.yard, status = 'DOCKED' where id = v_fleet;
      v_dark := v_dark || jsonb_build_object(h.class, pg_temp.try_0165(v_player,
        format('select cmd.do_build(%L, %L::jsonb)', v_fleet, jsonb_build_object('class', h.class, 'name', 'Prova ' || h.class))));
    end loop;
    -- (H2) LIT, with every hull skill at V, Famous Ships I and the four role specialisations III: every one
    --      BUILT for its labour (each undone at once)
    update public.world_config set value = 'true'::jsonb where key = 'skills_bite';
    insert into public.player_skills (player_id, skill_id, level)
    select v_player, sk.id, 5 from public.skills sk join public.skill_profile pr on pr.skill_id = sk.id
     where pr.group_code = 'HULLS'
    on conflict (player_id, skill_id) do update set level = excluded.level;
    insert into public.player_skills (player_id, skill_id, level)
    select v_player, sk.id, case when sk.code = 'FAMOUS_SHIPS' then 1 else 3 end from public.skills sk
     where sk.code in ('FAMOUS_SHIPS', 'ARMED_MERCHANT', 'PRIVATEERS', 'SURVEY_SHIPS', 'CONVOY_ESCORTS')
    on conflict (player_id, skill_id) do update set level = excluded.level;
    for h in select * from probe_yards_0165 where yard is not null order by class loop
      update public.fleets set port_id = h.yard, status = 'DOCKED' where id = v_fleet;
      v_lit := v_lit || jsonb_build_object(h.class, pg_temp.try_0165(v_player,
        format('select cmd.do_build(%L, %L::jsonb)', v_fleet, jsonb_build_object('class', h.class, 'name', 'Prova ' || h.class))));
    end loop;
    v_out := v_out || jsonb_build_object('dark', v_dark, 'lit', v_lit,
                                         'yards', (select jsonb_object_agg(class, yard) from probe_yards_0165));

    -- (F) ONE OF EACH: the Golden Hind laid down and KEPT (inside this probe); a second Golden Hind refused in
    --     the one sentence, which the yard serves too (and closes the entry); a Turgut Reis's Kadırga still
    --     built (one of EACH, not one in all); a second barca still built (a hull that is not famous is
    --     untouched); and the Golden Hind's spent gear was spent from the store
    select yard into v_gh from probe_yards_0165 where class = 'goldenhind';
    select yard into v_tg from probe_yards_0165 where class = 'turgut';
    update public.fleets set port_id = v_gh, status = 'DOCKED' where id = v_fleet;
    -- a barca's own materials ashore there too (the control: a hull that is not famous)
    insert into public.player_storage (player_id, port_id, good_id, qty)
    select v_player, v_gh, hg.good_id, hg.qty from public.hull_recipe_goods hg where hg.class_code = 'barca'
    on conflict (player_id, port_id, good_id) do update set qty = public.player_storage.qty + excluded.qty;
    insert into public.player_items (player_id, port_id, item_code, qty)
    select v_player, v_gh, hi.item_code, hi.qty from public.hull_recipe_items hi where hi.class_code = 'barca'
    on conflict (player_id, port_id, item_code) do update set qty = public.player_items.qty + excluded.qty;
    v_out := v_out || jsonb_build_object('gear_before', (select qty from public.player_items
      where player_id = v_player and port_id = v_gh and item_code = 'drakes-culverins'));
    perform cmd.do_build(v_fleet, '{"class": "goldenhind", "name": "Pelican"}'::jsonb);
    v_out := v_out || jsonb_build_object(
      'gear_after', (select qty from public.player_items where player_id = v_player and port_id = v_gh and item_code = 'drakes-culverins'),
      'held', public.famous_held(v_player, 'goldenhind'),
      'held_other', public.famous_held(v_player, 'turgut'),
      'held_barca', public.famous_held(v_player, 'barca'),
      'second', pg_temp.try_0165(v_player, format('select cmd.do_build(%L, %L::jsonb)', v_fleet,
                  '{"class": "goldenhind", "name": "Second Hind"}')),
      'yard_held', pg_temp.yard_hull_0165(c_uid, v_gh, 'goldenhind'),
      'barca_again', pg_temp.try_0165(v_player, format('select cmd.do_build(%L, %L::jsonb)', v_fleet,
                  '{"class": "barca", "name": "Second Barca"}')));
    update public.fleets set port_id = v_tg, status = 'DOCKED' where id = v_fleet;
    v_out := v_out || jsonb_build_object(
      'other', pg_temp.try_0165(v_player, format('select cmd.do_build(%L, %L::jsonb)', v_fleet,
                 '{"class": "turgut", "name": "Prova turgut"}')),
      'yard_other', pg_temp.yard_hull_0165(c_uid, v_tg, 'turgut'));

    -- (G) THE GEAR AT A WORKSHOP: Drake's Culverins at Lisbon's tier-3 workshop, the materials on board —
    --     dark refused; lit with Gunnery V but no Famous Ships refused naming it, with figures; with it, made
    update public.fleets set port_id = v_lis, status = 'DOCKED' where id = v_fleet;
    select jsonb_object_agg(g.code, ir.qty * 2) into v_cargo
      from public.item_recipes ir join public.goods g on g.id = ir.good_id
     where ir.item_code = 'drakes-culverins';
    update public.ships set cargo = v_cargo where id = v_barca;
    delete from public.player_skills where player_id = v_player
       and skill_id = (select id from public.skills where code = 'FAMOUS_SHIPS');
    update public.world_config set value = 'false'::jsonb where key = 'skills_bite';
    v_out := v_out || jsonb_build_object('gear_dark', pg_temp.try_0165(v_player,
      format('select cmd.do_make(%L, ''{"item": "drakes-culverins"}''::jsonb)', v_fleet)));
    update public.world_config set value = 'true'::jsonb where key = 'skills_bite';
    insert into public.player_skills (player_id, skill_id, level)
    select v_player, sk.id, 5 from public.skills sk where sk.code = 'GUNNERY'
    on conflict (player_id, skill_id) do update set level = excluded.level;
    v_out := v_out || jsonb_build_object('gear_nofamous', pg_temp.try_0165(v_player,
      format('select cmd.do_make(%L, ''{"item": "drakes-culverins"}''::jsonb)', v_fleet)));
    insert into public.player_skills (player_id, skill_id, level)
    select v_player, sk.id, 1 from public.skills sk where sk.code = 'FAMOUS_SHIPS'
    on conflict (player_id, skill_id) do update set level = excluded.level;
    v_out := v_out || jsonb_build_object('gear_made', pg_temp.try_0165(v_player,
      format('select cmd.do_make(%L, ''{"item": "drakes-culverins"}''::jsonb)', v_fleet)));
    update public.world_config set value = 'false'::jsonb where key = 'skills_bite';
    raise exception 'PROBE_ROLLBACK_0165';
  exception when others then
    if sqlerrm <> 'PROBE_ROLLBACK_0165' then raise; end if;
  end;
  return v_out;
end $$;

create temp table probe_0165 on commit drop as select pg_temp.probe_0165() as j;

-- ── 8. THE COMPARISONS ─────────────────────────────────────────────────────────────────────────
create temp table yards_after_0165 on commit drop as
select b.port_id, h.value->>'class' as class, h.value as entry
  from public.port_buildings b
 cross join lateral jsonb_array_elements(world.building_yard(b.port_id)->'hulls') h
 where b.kind = 'building_yard';
create temp table shops_after_0165 on commit drop as
select b.port_id, i.value->>'code' as code, i.value as entry
  from public.port_buildings b
 cross join lateral jsonb_array_elements(world.workstation(b.port_id)->'items') i
 where b.kind = 'workstation';

analyze public.ship_classes, public.class_profile, public.class_slots, public.class_cabins, public.hull_recipes,
        public.hull_recipe_goods, public.hull_recipe_items, public.skill_requirements, public.item_kinds,
        public.item_profile, public.item_effects, public.item_recipes, public.item_use;
select pg_temp.time_reads_0165('after');

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
  v_p     jsonb := (select j from probe_0165);
  v_notes text := '';
  v_held  text;
begin
  select * into v_b from before_0165;

  -- (a) NOTHING ALREADY IN THE WORLD MOVED: every old hull's and item's rows hash as before
  if (select md5(string_agg(to_jsonb(c)::text, '|' order by c.code)) from public.ship_classes c where c.code in (select code from live_classes_0165)) <> v_b.classes_hash
     or (select md5(string_agg(to_jsonb(c)::text, '|' order by c.class_code)) from public.class_profile c where c.class_code in (select code from live_classes_0165)) <> v_b.profile_hash
     or (select md5(string_agg(to_jsonb(c)::text, '|' order by c.class_code, c.slot)) from public.class_slots c where c.class_code in (select code from live_classes_0165)) <> v_b.slots_hash
     or (select md5(string_agg(to_jsonb(c)::text, '|' order by c.class_code)) from public.class_cabins c where c.class_code in (select code from live_classes_0165)) <> v_b.cabins_hash
     or (select md5(string_agg(to_jsonb(c)::text, '|' order by c.class_code)) from public.hull_recipes c where c.class_code in (select code from live_classes_0165)) <> v_b.recipes_hash
     or (select md5(string_agg(to_jsonb(c)::text, '|' order by c.class_code, c.good_id)) from public.hull_recipe_goods c where c.class_code in (select code from live_classes_0165)) <> v_b.recipe_goods_hash
     or (select md5(string_agg(to_jsonb(c)::text, '|' order by c.class_code, c.item_code)) from public.hull_recipe_items c where c.class_code in (select code from live_classes_0165)) <> v_b.recipe_items_hash
     or (select md5(string_agg(to_jsonb(c)::text, '|' order by c.subject_kind, c.subject_code, c.skill_code)) from public.skill_requirements c
          where c.subject_code not in (select code from own_hulls_0165) and c.subject_code not in (select code from own_items_0165)) <> v_b.requirements_hash
     or (select md5(string_agg(to_jsonb(c)::text, '|' order by c.code)) from public.item_kinds c where c.code in (select code from live_items_0165)) <> v_b.kinds_hash
     or (select md5(string_agg(to_jsonb(c)::text, '|' order by c.item_code)) from public.item_profile c where c.item_code in (select code from live_items_0165)) <> v_b.iprofile_hash
     or (select md5(string_agg(to_jsonb(c)::text, '|' order by c.item_code, c.stat)) from public.item_effects c where c.item_code in (select code from live_items_0165)) <> v_b.effects_hash
     or (select md5(string_agg(format('%s/%s/%s', c.item_code, c.good_id, c.qty), '|' order by c.item_code, c.good_id)) from public.item_recipes c where c.item_code in (select code from live_items_0165)) <> v_b.item_recipes_hash
     or (select md5(string_agg(to_jsonb(c)::text, '|' order by c.item_code)) from public.item_use c where c.item_code in (select code from live_items_0165)) <> v_b.use_hash then
    raise exception '0165 self-assert FAIL: a row of a hull or an item already in the world moved';
  end if;

  -- (b) EXACTLY THE GENERATED ROWS LANDED — counted by THIS file's own codes only (the world guard holds
  --     every column to the generators)
  if (select count(*) from public.ship_classes where code in (select code from own_hulls_0165)) <> 11
     or (select count(*) from public.class_profile where class_code in (select code from own_hulls_0165) and tech = 'F') <> 11
     or (select count(*) from public.class_slots where class_code in (select code from own_hulls_0165)) <> 53
     or (select count(*) from public.class_cabins where class_code in (select code from own_hulls_0165)) <> 11
     or (select count(*) from public.hull_recipes where class_code in (select code from own_hulls_0165)) <> 11
     or (select count(*) from public.hull_recipe_goods where class_code in (select code from own_hulls_0165)) <> 65
     or (select count(*) from public.hull_recipe_items where class_code in (select code from own_hulls_0165)) <> 11
     or (select count(*) from public.skill_requirements where subject_kind = 'hull' and subject_code in (select code from own_hulls_0165)) <> 33
     or (select count(*) from public.item_kinds where code in (select code from own_items_0165)) <> 11
     or (select count(*) from public.item_profile where item_code in (select code from own_items_0165) and meta = 8 and grade = 5) <> 11
     or (select count(*) from public.item_effects where item_code in (select code from own_items_0165)) <> 38
     or (select count(*) from public.item_recipes where item_code in (select code from own_items_0165)) <> 47
     or (select count(*) from public.skill_requirements where subject_kind = 'item' and subject_code in (select code from own_items_0165)) <> 24
     or (select count(*) from public.item_use where item_code in (select code from own_items_0165)) <> 11 then
    raise exception '0165 self-assert FAIL: the famous rows are not exactly the generated ones (hulls %, items %)',
      (select count(*) from public.ship_classes where code in (select code from own_hulls_0165)),
      (select count(*) from public.item_kinds where code in (select code from own_items_0165));
  end if;

  -- (c) THE HULL RULES over the 11: guns = attack / 10, tier = least(size, 5), Hands ≥ 0, the yard tier by
  --     size; famous, own-country; one a line, eleven lines; each one place more than the T1 of its line,
  --     size and role where one exists
  select count(*), string_agg(c.code, ',' order by c.code) into v_bad, v_list
    from public.ship_classes c join public.class_profile p on p.class_code = c.code
    join public.hull_recipes hr on hr.class_code = c.code
   where c.code in (select code from own_hulls_0165)
     and (c.guns * 10 <> c.attack or c.tier <> least(p.size, 5)
          or c.crew_max - (c.crew_required + 1) / 2 < 0
          or hr.yard_tier <> case p.size when 1 then 1 when 2 then 2 else 3 end
          or p.tech <> 'F' or p.any_yard or length(hr.note) < 40);
  if v_bad <> 0 then
    raise exception '0165 self-assert FAIL: % famous hull(s) break guns = attack / 10, tier, Hands, the yard tier by size, famous / own-country, or carry no history line: %', v_bad, v_list;
  end if;
  if (select count(distinct p.line_code) from public.class_profile p where p.class_code in (select code from own_hulls_0165)) <> 11 then
    raise exception '0165 self-assert FAIL: the famous ships are not one a line, eleven lines';
  end if;
  select count(*), string_agg(f.class_code, ',') into v_bad, v_list
    from public.class_profile f join public.class_profile t1
      on t1.line_code = f.line_code and t1.size = f.size and t1.role = f.role and t1.tech = 'T1'
   where f.class_code in (select code from own_hulls_0165)
     and (select sum(count) from public.class_slots where class_code = f.class_code)
         <> (select sum(count) from public.class_slots where class_code = t1.class_code) + 1;
  if v_bad <> 0 then
    raise exception '0165 self-assert FAIL: % famous hull(s) do not carry exactly one place more than their T1: %', v_bad, v_list;
  end if;

  -- (d) 0072 (b)(d) OVER THE 11: every material sold somewhere; every fitting makeable somewhere — and it is
  --     the hull's own famous piece; every hull's goods fit a storage where it can be built (THE SHED, not
  --     loosened); every hull buildable at ≥ 1 yard of its line
  select count(*), string_agg(distinct g.code, ',') into v_bad, v_list
    from public.hull_recipe_goods hg join public.goods g on g.id = hg.good_id
   where hg.class_code in (select code from own_hulls_0165)
     and not exists (select 1 from public.port_goods pg join public.ports p on p.id = pg.port_id
                      where pg.good_id = hg.good_id and public.port_offers(p.id, hg.good_id));
  if v_bad <> 0 then
    raise exception '0165 self-assert FAIL: % famous hull material(s) are sold in NO city: %', v_bad, v_list;
  end if;
  select count(*), string_agg(hi.class_code || ':' || hi.item_code, ',') into v_bad, v_list
    from public.hull_recipe_items hi join public.item_kinds k on k.code = hi.item_code
   where hi.class_code in (select code from own_hulls_0165)
     and (hi.qty <> 1 or hi.item_code not in (select code from own_items_0165)
          or not exists (select 1 from public.port_buildings b where b.kind = 'workstation' and b.tier >= k.ws_tier)
          or not exists (select 1 from public.item_recipes ir where ir.item_code = hi.item_code));
  if v_bad <> 0
     or (select count(distinct item_code) from public.hull_recipe_items where class_code in (select code from own_hulls_0165)) <> 11
     or exists (select 1 from public.hull_recipe_items where item_code in (select code from own_items_0165)
                 and class_code not in (select code from own_hulls_0165)) then
    raise exception '0165 self-assert FAIL: a famous hull''s fitting is not its own one famous piece, made somewhere: %', v_list;
  end if;
  select count(*), string_agg(x.class_code || ' ' || x.tons || ' t', ', ') into v_bad, v_list from (
    select hr.class_code, sum(hg.qty * g.bulk) as tons
      from public.hull_recipes hr
      join public.hull_recipe_goods hg on hg.class_code = hr.class_code
      join public.goods g on g.id = hg.good_id
     where hr.class_code in (select code from own_hulls_0165)
     group by hr.class_code) x
   where x.tons > coalesce((select max(public.storage_cap(b.port_id)) from public.port_buildings b
                             join public.hull_recipes hr on hr.class_code = x.class_code
                            where b.kind = 'building_yard' and b.tier >= hr.yard_tier
                              and public.yard_wrong_country(b.port_id, x.class_code) is null), 0);
  if v_bad <> 0 then
    raise exception '0165 self-assert FAIL: % famous hull(s) want more than any storage where they can be built holds: %', v_bad, v_list;
  end if;
  select count(*), string_agg(c.code, ',') into v_bad, v_list
    from public.ship_classes c join public.hull_recipes hr on hr.class_code = c.code
   where c.code in (select code from own_hulls_0165)
     and not exists (select 1 from public.port_buildings b
                      where b.kind = 'building_yard' and b.tier >= hr.yard_tier
                        and public.yard_wrong_country(b.port_id, c.code) is null);
  if v_bad <> 0 then
    raise exception '0165 self-assert FAIL: % famous hull(s) can be built at no yard of their line: %', v_bad, v_list;
  end if;

  -- (e) THE FAMOUS REQUIREMENTS (§4.4): the line's ⟨size⟩ Hulls V + Famous Ships I + the role's T2
  --     specialisation III, nothing else (a flagship's size is trained under Capital Hulls)
  select count(*), string_agg(c.class_code, ',') into v_bad, v_list
    from public.class_profile c
   where c.class_code in (select code from own_hulls_0165)
     and (select string_agg(r.skill_code || ':' || r.level, ',' order by r.skill_code)
            from public.skill_requirements r where r.subject_kind = 'hull' and r.subject_code = c.class_code)
         is distinct from
         (select string_agg(x.s || ':' || x.l, ',' order by x.s) from (values
            (c.line_code || '_' || case c.size when 1 then 'SMALL' when 2 then 'LIGHT' when 3 then 'MEDIUM'
                                               when 4 then 'HEAVY' else 'CAPITAL' end, 5),
            ('FAMOUS_SHIPS', 1),
            (case c.role when 'trade' then 'ARMED_MERCHANT' when 'combat' then 'PRIVATEERS'
                         when 'explorer' then 'SURVEY_SHIPS' else 'CONVOY_ESCORTS' end, 3)) x(s, l));
  if v_bad <> 0 then
    raise exception '0165 self-assert FAIL: % famous hull(s) do not carry §4.4''s requirements: %', v_bad, v_list;
  end if;

  -- (f) THE GEAR RULES over the 11 pieces: buys one and spends one (0074); every recipe good sold somewhere;
  --     a module skill at V and Famous Ships I; a tier-3 workshop; what works each answers its base type
  select count(*) into v_bad from public.item_kinds k
   where k.code in (select code from own_items_0165)
     and not (exists (select 1 from public.item_effects e where e.item_code = k.code and e.delta > 0)
          and exists (select 1 from public.item_effects e where e.item_code = k.code and e.delta < 0));
  if v_bad <> 0 then
    raise exception '0165 self-assert FAIL: % famous piece(s) buy a stat without spending one', v_bad;
  end if;
  select count(*), string_agg(distinct g.code, ',') into v_bad, v_list
    from public.item_recipes ir join public.goods g on g.id = ir.good_id
   where ir.item_code in (select code from own_items_0165)
     and not exists (select 1 from public.port_goods pg join public.ports p on p.id = pg.port_id
                      where pg.good_id = ir.good_id and public.port_offers(p.id, ir.good_id));
  if v_bad <> 0 then
    raise exception '0165 self-assert FAIL: % famous gear material(s) are sold in NO city: %', v_bad, v_list;
  end if;
  if exists (select 1 from public.item_kinds k where k.code in (select code from own_items_0165)
              and (k.ws_tier <> 3
                   or (select count(*) from public.skill_requirements r where r.subject_kind = 'item' and r.subject_code = k.code
                        and r.skill_code = 'FAMOUS_SHIPS' and r.level = 1) <> 1
                   or (select count(*) from public.skill_requirements r where r.subject_kind = 'item' and r.subject_code = k.code
                        and r.level = 5) <> 1
                   or not exists (select 1 from public.item_use u where u.item_code = k.code and u.trigger is not null))) then
    raise exception '0165 self-assert FAIL: a famous piece''s workshop, requirements or what works it is not as §6.2 says';
  end if;

  -- (g) DARK = WHAT A COMPANY SEES AND DOES TODAY. Every old hull's yard entry and every old item's workshop
  --     entry is its pre-image, to the byte; every new one is closed with its needs (the dark reason)
  select count(*) into v_bad from yards_before_0165 yb
   where (select ya.entry from yards_after_0165 ya where ya.port_id = yb.port_id and ya.class = yb.class) is distinct from yb.entry;
  if v_bad <> 0 or (select count(*) from yards_before_0165) = 0 then
    raise exception '0165 self-assert FAIL: % old yard entr(ies) moved (or none was read)', v_bad;
  end if;
  select count(*) into v_bad from shops_before_0165 sb
   where (select sa.entry from shops_after_0165 sa where sa.port_id = sb.port_id and sa.code = sb.code) is distinct from sb.entry;
  if v_bad <> 0 or (select count(*) from shops_before_0165) = 0 then
    raise exception '0165 self-assert FAIL: % old workshop entr(ies) moved (or none was read)', v_bad;
  end if;
  select count(*) into v_bad from yards_after_0165 ya
   where ya.class in (select code from own_hulls_0165)
     and ((ya.entry->>'buildable')::boolean or ya.entry->>'tech' is distinct from 'F' or ya.entry ? 'famous_held'
          or position('ship skills are not in use yet' in coalesce(ya.entry->>'needs', '')) = 0
          or jsonb_array_length(ya.entry->'items') <> 1);
  if v_bad <> 0 or (select count(distinct class) from yards_after_0165 where class in (select code from own_hulls_0165)) <> 11 then
    raise exception '0165 self-assert FAIL: % famous yard entr(ies) are open, unbadged, without the dark reason or without their gear (or not every famous ship is listed)', v_bad;
  end if;
  select count(*) into v_bad from shops_after_0165 sa
   where sa.code in (select code from own_items_0165)
     and ((sa.entry->>'makeable')::boolean
          or position('ship skills are not in use yet' in coalesce(sa.entry->>'needs', '')) = 0);
  if v_bad <> 0 then
    raise exception '0165 self-assert FAIL: % famous workshop entr(ies) are open or without the dark reason', v_bad;
  end if;
  -- through the door: dark, every famous hull refused E_NEEDS_SKILL with the dark reason
  select count(*), string_agg(e.key || ' ' || e.value, '; ') into v_bad, v_list
    from jsonb_each_text(v_p->'dark') e
   where split_part(e.value, ':', 1) <> 'E_NEEDS_SKILL' or position('ship skills are not in use yet' in e.value) = 0;
  if v_bad <> 0 or (select count(*) from jsonb_object_keys(v_p->'dark')) <> 11 then
    raise exception '0165 self-assert FAIL: dark, % famous hull(s) were not refused: %', v_bad, v_list;
  end if;

  -- (h) LIT (rolled back), the skills held: every famous ship BUILT for its labour
  select count(*), string_agg(e.key || ' ' || e.value, '; ') into v_bad, v_list
    from jsonb_each_text(v_p->'lit') e join public.hull_recipes hr on hr.class_code = e.key
   where e.value <> 'ok:' || public.hull_labour(hr.class_code);
  if v_bad <> 0 or (select count(*) from jsonb_object_keys(v_p->'lit')) <> 11 then
    raise exception '0165 self-assert FAIL: lit with the skills, % famous hull(s) were not built for their labour: %', v_bad, v_list;
  end if;

  -- (i) ONE OF EACH TO A HOUSE (the row's assert): with the Golden Hind kept, a second is refused E_FAMOUS_HELD
  --     in the one sentence; the yard serves the same sentence and closes the entry; another famous ship and
  --     a second barca are still built; a non-famous class and an un-kept famous class say nothing; the
  --     first Hind spent her one piece of famous gear
  v_held := 'Golden Hind is a famous ship, and a company keeps only one of each: yours is the Pelican.';
  if v_p->>'held' is distinct from v_held
     or v_p->>'second' is distinct from 'E_FAMOUS_HELD: ' || v_held
     or v_p->'yard_held'->>'famous_held' is distinct from v_held
     or (v_p->'yard_held'->>'buildable')::boolean is distinct from false
     or v_p->>'held_other' is not null or v_p->>'held_barca' is not null
     or v_p->>'other' is distinct from 'ok:' || public.hull_labour('turgut')
     or v_p->'yard_other' ? 'famous_held' or (v_p->'yard_other'->>'buildable')::boolean is distinct from true
     or v_p->>'barca_again' not like 'ok:%'
     or (v_p->>'gear_before')::int is distinct from 2 or (v_p->>'gear_after')::int is distinct from 1 then
    raise exception '0165 self-assert FAIL: one of each famous ship to a house did not hold: %',
      jsonb_build_object('held', v_p->'held', 'second', v_p->'second', 'yard_held', v_p->'yard_held', 'other', v_p->'other',
                         'yard_other', v_p->'yard_other', 'barca_again', v_p->'barca_again', 'held_other', v_p->'held_other',
                         'held_barca', v_p->'held_barca', 'gear', jsonb_build_array(v_p->'gear_before', v_p->'gear_after'));
  end if;

  -- (j) THE GEAR THROUGH THE WORKSHOP: dark refused; lit with Gunnery V but no Famous Ships refused naming
  --     it, with figures; with it, made
  if split_part(v_p->>'gear_dark', ':', 1) <> 'E_NEEDS_SKILL' or position('ship skills are not in use yet' in v_p->>'gear_dark') = 0
     or v_p->>'gear_nofamous' not like 'E_NEEDS_SKILL: Drake''s Culverins needs Famous Ships I|%'
     or (split_part(v_p->>'gear_nofamous', '|', 2))::jsonb is distinct from '{"have": 0, "need": 1, "unit": "level"}'::jsonb
     or v_p->>'gear_made' not like 'ok:%' then
    raise exception '0165 self-assert FAIL: the famous gear''s requirements did not hold at the workshop: %',
      jsonb_build_object('dark', v_p->'gear_dark', 'nofamous', v_p->'gear_nofamous', 'made', v_p->'gear_made');
  end if;
  if public.skills_bite_on() or exists (select 1 from public.players where auth_uid = '00000000-0165-4000-8000-000000000001') then
    raise exception '0165 self-assert FAIL: the probe world was not rolled back';
  end if;

  -- (k) THE RE-CUTS reverse to their pre-images; ACL / volatility / definer / config unmoved
  for d in select * from defs_before_0165 order by fn loop
    v_def := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0165 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0165(v_def, h.new) <> 1 then
        raise exception '0165 self-assert FAIL: hunk % of % is not in the new body exactly once', h.n, d.fn;
      end if;
      v_def := replace(v_def, h.new, h.old);
    end loop;
    if v_def <> d.def then
      raise exception '0165 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef, coalesce(pr.proconfig::text, '') as cfg
      into v_pp from pg_proc pr where pr.oid = d.fn::regprocedure;
    if v_pp.acl <> d.acl or v_pp.vol <> d.vol or v_pp.secdef <> d.secdef or v_pp.cfg <> d.cfg then
      raise exception '0165 self-assert FAIL: % changed its ACL, volatility, definer or config', d.fn;
    end if;
  end loop;

  -- (l) THE WALL
  if (select count(*) from public.client_rpc_entry_points()) <> v_b.entry_points
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0
     or has_function_privilege('anon', 'public.famous_held(uuid, text)', 'execute')
     or has_function_privilege('authenticated', 'public.famous_held(uuid, text)', 'execute') then
    raise exception '0165 self-assert FAIL: the registry, the grant wall or the read wall moved, or a client can reach public.famous_held';
  end if;

  for v_rd in select bf.what, bf.ms as before_ms, af.ms as after_ms, bf.hulls
             from reads_0165 bf join reads_0165 af on af.what = bf.what and af.phase = 'after'
            where bf.phase = 'before' order by bf.what loop
    v_notes := v_notes || format('%s over %s merchant hull(s) %s ms → %s ms; ', v_rd.what, v_rd.hulls, v_rd.before_ms, v_rd.after_ms);
  end loop;

  raise notice '0165 self-assert ok: A FAMOUS SHIP IS ONE TO A HOUSE. UNTOUCHED: every hull and item already in the world. LANDED (counted by its own codes): +11 famous hulls (one a line, one place more than their T1, each with its history line), +33 hull requirements (⟨size⟩ Hulls V + Famous Ships I + the role''s specialisation III), +11 pieces of famous gear (grade 5, meta 8, a skill V + Famous Ships I, tier-3 workshop), each its hull''s one fitting. RULES: guns = attack / 10, tier, Hands, yard tier, own-country; every material sold somewhere; every fitting made somewhere; every hull fits a shed where it is built and is buildable at ≥ 1 yard of its line. DARK: % old yard entries and % old workshop entries as before; every famous hull and piece closed with its needs; 11 refused through the door. LIT (rolled back): 11 BUILT for their labour; a second Golden Hind refused "%" (the yard says the same and closes her), a Turgut Reis''s Kadırga and a second barca still built; Drake''s Culverins refused "%", then made. 2 bodies reverse, no entry point. READS: %',
    (select count(*) from yards_before_0165), (select count(*) from shops_before_0165),
    substr(v_p->>'second', length('E_FAMOUS_HELD: ') + 1), split_part(v_p->>'gear_nofamous', '|', 1), v_notes;
end $$;
