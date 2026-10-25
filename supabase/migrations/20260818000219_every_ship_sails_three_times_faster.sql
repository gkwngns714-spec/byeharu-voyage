-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0219 — EVERY SHIP SAILS THREE TIMES FASTER
--        (one knob, speed_scale 3, applied to the rows the one speed formula reads; no body changes)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER, VERBATIM (2026-10-20, docs/OWNER_REQUESTS.md row 169, part a) ────────────────────
--   "I want the ship speed to be faster for all ships including npcs. About 3 times faster."
--   (part b, smooth movement, shipped as PR #287, client only.)
--
-- ── THE ONE AUTHORITY, AND WHERE THE KNOB GOES ──────────────────────────────────────────────────
-- "How fast does she sail" has ONE formula in this chain (0006, re-cut 0074, carried into its fill
-- form by 0203):
--     voyage.ship_speed_at(ship, fill) = round(world.ship_stat(ship, 'speed') × M_hull × M_load × M_crew × wind_mult_v0, 4)
-- voyage.ship_speed reads it with null; voyage.fleet_speed_at takes the slowest hull × formation × the
-- captains' speed % × the house's NAVIGATION; voyage.fleet_speed reads that at the fill she carries.
-- Every duration in the game is miles ÷ (that speed × 24): the departure's eta and speed_profile (0006,
-- 0047, 0104), the leg she is on (0075), the helm at sea (0037), the desk's reach board and its days
-- (0188), the passage gate's "can she reach it on her stores" (0216 through voyage.endurance_days and
-- 0188's days), the merchants' planner (0203: fleet_speed_at(fleet, 1) — laden — and 0209's leg lines),
-- the provisions a lap needs (0203:540, days × endurance_margin), the wages and stores a lap pays (0197,
-- 0210: per DAY at sea, the days being closed_at − started_at of a lap that is now a third as long).
-- None of them keeps a speed of its own; they ask. So nothing is re-cut here: no hunk, no body moves.
--
-- The base the formula reads is world.ship_stats' 'speed' row: ship_classes.speed_kn (the hull's RATED
-- speed, the figure the yard and every ship card print as `speed_rated`) + Σ item_effects.delta (stat
-- 'speed', flat knots per mounted unit) + flat perks (perks.per_rank, mode 'flat', stat 'speed') + a
-- line's set bonus (gear_set_bonuses.flat, stat 'speed'; its pct rows are a per cent of the base and
-- follow by themselves), × (1 + skill %) where skills bite, floored at 0.5 kn. Exactly as 0208 did for
-- the hold (hold_scale 3), this file multiplies EVERY flat speed quantity by one knob, speed_scale (3),
-- when it writes the rows — so the rated speed on a card, the fitted speed, the speed she makes and
-- every duration agree, and a +0.6 kn suit of sails is still the same share of a hull. The data files
-- keep the design figures; scripts/db/world-guard.mjs holds the rows = data × speed_scale. Changing the
-- knob alone moves nothing (as with hold_scale): it is the record of what the rows are multiples of.
--
-- ── WHAT MOVES, AND WHAT DOES NOT ───────────────────────────────────────────────────────────────
-- MOVES: every ship's speed, player and merchant alike, from the next reading: every departure after
--   this file quotes a third of the days, consumes a third of the stores, pays a third of the wages at
--   sea, and a lap closes in a third of the real time — so ducats per real hour rise about three-fold
--   for players AND merchants (docs/dev-log/2026-10-25-speed-x3.md measures it, paired, before/after).
-- DOES NOT MOVE (stated, decided by default; the owner may reverse each):
--   · A voyage already at sea keeps the speed frozen in its speed_profile at departure (0006: "v_fleet
--     per leg is FROZEN") and arrives at its old eta; she sails at ×3 from her next departure. Nothing
--     is rewritten under a moving hull. The main session's prod check counts how many are at sea.
--   · time: game_day_seconds (2880) and the 15-second arrivals tick. A game day is as long as it was;
--     a day at sea costs what it did; there are simply fewer of them per passage.
--   · the 0.5-kn floor in world.ship_stats (a floor, not a clamp; reached only by fittings that spend
--     more speed than a hull has — 0074's reason stands at any scale).
--   · wind_mult_v0 (1.00, reserved for wind, DESIGN K.1), hull_speed_floor, load_speed_penalty,
--     crew_short_speed_mult, the formation penalty, the captains' and the house's speed %: all ratios.
--   · pct perks and pct set bonuses (a per cent of a base that tripled), skills (a per cent).
--
-- ── WHAT IT SELF-ASSERTS (own probe rows; every selection was run read-only on prod first) ──────
-- (a) the knob reads 3; wind_mult_v0 still reads what it did.
-- (b) every ship class's speed_kn = its pre-image × 3 exactly (numeric(4,2) × 3 is exact); every speed
--     item effect, every flat speed perk and every flat speed set bonus = pre-image × 3; pct ones unmoved.
-- (c) on a probe set of 60 fleets (by md5(id || '0219'), player and merchant), voyage.fleet_speed and
--     voyage.fleet_speed_at(fleet, 1) read pre-image × 3 within 0.05 kn (world.ship_stats rounds a
--     SKILLED stat to its base's 2 places, which does not commute with × 3 — see (c) below).
-- (d) the five bodies — voyage.ship_speed_at, ship_speed, fleet_speed_at, fleet_speed, world.ship_stat —
--     have the definition md5, ACL, volatility, definer flag and config they had; the formula line
--     occurs exactly once in ship_speed_at; the walls (client_write_grants / client_executable_writers /
--     caller_evaluated_functions) are 0.
-- (e) timings (notice only): voyage.fleet_speed and fleet_speed_at(fleet, 1), 8 calls each in one session.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
declare
  v_def text;
begin
  perform set_config('statement_timeout', '10min', true);
  perform set_config('lock_timeout', '5s', true);
  if exists (select 1 from public.world_config where key = 'speed_scale') then
    raise exception '0219 refuses: speed_scale already exists — this has been applied once';
  end if;
  if not exists (select 1 from public.world_config where key = 'hold_scale') then
    raise exception '0219 refuses: 0208 (hold_scale) is not in this world';
  end if;
  if to_regprocedure('voyage.ship_speed_at(uuid, numeric)') is null or to_regprocedure('world.ship_stat(uuid, text)') is null
     or to_regprocedure('world.ship_stats(uuid)') is null or to_regprocedure('voyage.fleet_speed_at(uuid, numeric)') is null then
    raise exception '0219 refuses: the speed authorities of 0203 / 0124 are not in this world';
  end if;
  v_def := replace(pg_get_functiondef('voyage.ship_speed_at(uuid, numeric)'::regprocedure), E'\r', '');
  if (length(v_def) - length(replace(v_def, $n$return round(world.ship_stat(p_ship, 'speed') * v_hull * v_load * v_crew * public.wc_num('wind_mult_v0'), 4);$n$, '')))
     / length($n$return round(world.ship_stat(p_ship, 'speed') * v_hull * v_load * v_crew * public.wc_num('wind_mult_v0'), 4);$n$) <> 1 then
    raise exception '0219 refuses: voyage.ship_speed_at is not the one formula this file was written against';
  end if;
  v_def := replace(pg_get_functiondef('world.ship_stats(uuid)'::regprocedure), E'\r', '');
  if position($n$('speed',      c.speed_kn::numeric)$n$ in v_def) = 0 then
    raise exception '0219 refuses: world.ship_stats does not read ship_classes.speed_kn as the speed base';
  end if;
  if (select max(speed_kn) * 3 from public.ship_classes) > 99.99 then
    raise exception '0219 refuses: a class speed × 3 would not fit numeric(4,2)';
  end if;
end $guard$;

-- ── 1. THE KNOB ─────────────────────────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('speed_scale', to_jsonb(3),
   '0219 (owner, 2026-10-20: "ship speed ... about 3 times faster ... including npcs"): every flat speed quantity in '
   'the world as a multiple of the design figure in the data files — ship_classes.speed_kn, item_effects.delta (stat '
   'speed), perks.per_rank (flat speed), gear_set_bonuses.flat (speed). Applied when those rows are WRITTEN (0219 '
   'wrote them at 3); the world guard holds them = data × this. Changing it alone moves nothing.');

-- ── 2. LOCK, THEN THE PRE-IMAGES ────────────────────────────────────────────────────────────────
do $lock$
begin
  perform 1 from public.ship_classes for update;
  perform 1 from public.item_effects where stat = 'speed' for update;
  perform 1 from public.perks where stat = 'speed' for update;
  perform 1 from public.gear_set_bonuses where stat = 'speed' for update;
end $lock$;

create temp table classes_0219 on commit drop as
select id, code, speed_kn from public.ship_classes;

create temp table effects_0219 on commit drop as
select item_code, delta from public.item_effects where stat = 'speed';

create temp table perks_0219 on commit drop as
select code, mode, per_rank from public.perks where stat = 'speed';

create temp table gear_0219 on commit drop as
select line_code, pieces, pct, flat from public.gear_set_bonuses where stat = 'speed';

create temp table defs_before_0219 on commit drop as
select f.fn,
       md5(replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '')) as def_md5,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('voyage.ship_speed_at(uuid, numeric)'), ('voyage.ship_speed(uuid)'),
               ('voyage.fleet_speed_at(uuid, numeric)'), ('voyage.fleet_speed(uuid)'),
               ('world.ship_stat(uuid, text)'), ('world.ship_stats(uuid)')) f(fn);

-- The probe fleets: 60 by md5, player and merchant, any that has a hull. Their speeds BEFORE.
create temp table fleets_0219 on commit drop as
select f.id, voyage.fleet_speed(f.id) as kn_before, voyage.fleet_speed_at(f.id, 1) as laden_before
  from public.fleets f
 where exists (select 1 from public.ships s where s.fleet_id = f.id)
 order by md5(f.id::text || '0219')
 limit 60;

-- ── 3. THE ROWS: every flat speed quantity × speed_scale ────────────────────────────────────────
update public.ship_classes set speed_kn = speed_kn * public.wc_num('speed_scale');
update public.item_effects set delta = delta * public.wc_num('speed_scale') where stat = 'speed';
update public.perks set per_rank = per_rank * public.wc_num('speed_scale') where stat = 'speed' and mode = 'flat';
update public.gear_set_bonuses set flat = flat * public.wc_num('speed_scale') where stat = 'speed' and flat is not null;

-- ── 4. SELF-ASSERT ──────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_n      int;
  v_bad    int;
  v_fl     int;
  v_maxdev numeric;
  v_d      record;
  v_pp     record;
  v_def    text;
  v_fleet  uuid;
  v_t      timestamptz;
  v_ms     numeric[] := '{}';
  v_lms    numeric[] := '{}';
  i        int;
begin
  -- (a) the knob
  if public.wc_num('speed_scale') <> 3 then
    raise exception '0219 self-assert FAIL: speed_scale reads %, not 3', public.wc_num('speed_scale');
  end if;
  if public.wc_num('wind_mult_v0') <> 1 then
    raise exception '0219 self-assert FAIL: wind_mult_v0 reads %, it was 1 (this file does not touch it)', public.wc_num('wind_mult_v0');
  end if;

  -- (b) the rows: every pre-image row × 3, to the digit; nothing else moved
  select count(*) into v_bad from classes_0219 b join public.ship_classes c on c.id = b.id where c.speed_kn <> b.speed_kn * 3;
  if v_bad <> 0 or (select count(*) from classes_0219) <> (select count(*) from public.ship_classes) then
    raise exception '0219 self-assert FAIL: % class(es) whose speed_kn is not the pre-image × 3', v_bad;
  end if;
  select count(*) into v_bad from effects_0219 b join public.item_effects e on e.item_code = b.item_code and e.stat = 'speed' where e.delta <> b.delta * 3;
  if v_bad <> 0 or (select count(*) from effects_0219) <> (select count(*) from public.item_effects where stat = 'speed') then
    raise exception '0219 self-assert FAIL: % speed item effect(s) not the pre-image × 3', v_bad;
  end if;
  select count(*) into v_bad from perks_0219 b join public.perks p on p.code = b.code
   where p.per_rank <> case when b.mode = 'flat' then b.per_rank * 3 else b.per_rank end;
  if v_bad <> 0 or (select count(*) from perks_0219) <> (select count(*) from public.perks where stat = 'speed') then
    raise exception '0219 self-assert FAIL: % speed perk(s) not the pre-image × 3 (flat) or unmoved (pct)', v_bad;
  end if;
  select count(*) into v_bad from gear_0219 b join public.gear_set_bonuses g on g.line_code = b.line_code and g.pieces = b.pieces and g.stat = 'speed'
   where g.pct is distinct from b.pct or g.flat is distinct from b.flat * 3;
  if v_bad <> 0 or (select count(*) from gear_0219) <> (select count(*) from public.gear_set_bonuses where stat = 'speed') then
    raise exception '0219 self-assert FAIL: % speed set bonus(es) not the pre-image × 3 (flat) or unmoved (pct)', v_bad;
  end if;
  if exists (select 1 from public.ship_classes where speed_kn <= 0) then
    raise exception '0219 self-assert FAIL: a class has no speed';
  end if;

  -- (c) the probe fleets sail three times as fast, empty and laden. The tolerance is 0.05 kn, not the
  -- formula's 4-dp rounding: where skills bite (0133), world.ship_stats rounds the skilled stat to the
  -- SCALE of its base (speed_kn: 2 places), and that rounding does not commute with × 3 — a barca at
  -- 5.00 × 1.075 reads 5.38, at 15.00 it reads 16.13, not 16.14 (the disposable chain found 0.0114 kn
  -- on one of 60). The bound: 3 × 0.005 + 0.005, times the fleet multipliers (< 2), is under 0.04.
  select count(*), count(*) filter (where abs(voyage.fleet_speed(id) - kn_before * 3) > 0.05
                                        or abs(voyage.fleet_speed_at(id, 1) - laden_before * 3) > 0.05),
         max(greatest(abs(voyage.fleet_speed(id) - kn_before * 3), abs(voyage.fleet_speed_at(id, 1) - laden_before * 3)))
    into v_n, v_bad, v_maxdev
    from fleets_0219;
  if v_bad <> 0 then
    raise exception '0219 self-assert FAIL: % of % probe fleet(s) do not sail at 3 × their pre-image speed (max deviation % kn)', v_bad, v_n, v_maxdev;
  end if;
  select count(*) into v_fl from fleets_0219 where kn_before <= 0 or laden_before <= 0;
  if v_fl <> 0 then
    raise exception '0219 self-assert FAIL: % probe fleet(s) read a speed of 0 before the change', v_fl;
  end if;

  -- (d) no body moved: the six definitions, their ACL / volatility / definer / config; the formula once
  for v_d in select * from defs_before_0219 loop
    select md5(replace(pg_get_functiondef(pr.oid), E'\r', '')) as def_md5, coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol,
           pr.prosecdef as secdef, coalesce(pr.proconfig::text, '') as cfg
      into v_pp from pg_proc pr where pr.oid = v_d.fn::regprocedure;
    if v_pp.def_md5 <> v_d.def_md5 or v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0219 self-assert FAIL: % changed its body, ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;
  v_def := replace(pg_get_functiondef('voyage.ship_speed_at(uuid, numeric)'::regprocedure), E'\r', '');
  if (length(v_def) - length(replace(v_def, $n$return round(world.ship_stat(p_ship, 'speed') * v_hull * v_load * v_crew * public.wc_num('wind_mult_v0'), 4);$n$, '')))
     / length($n$return round(world.ship_stat(p_ship, 'speed') * v_hull * v_load * v_crew * public.wc_num('wind_mult_v0'), 4);$n$) <> 1 then
    raise exception '0219 self-assert FAIL: the one formula does not occur exactly once in voyage.ship_speed_at';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0219 self-assert FAIL: a wall moved';
  end if;

  -- (e) TIMINGS (notice only): the speed path, 8 calls each in this session on the first probe fleet
  select id into v_fleet from fleets_0219 order by id limit 1;
  if v_fleet is not null then
    for i in 1..8 loop
      v_t := clock_timestamp();
      perform voyage.fleet_speed(v_fleet);
      v_ms := v_ms || round(extract(epoch from clock_timestamp() - v_t) * 1000, 2);
      v_t := clock_timestamp();
      perform voyage.fleet_speed_at(v_fleet, 1);
      v_lms := v_lms || round(extract(epoch from clock_timestamp() - v_t) * 1000, 2);
    end loop;
  end if;

  raise notice '0219 self-assert ok: EVERY SHIP SAILS THREE TIMES FASTER. speed_scale 3; % classes (% → % kn … % → % kn), % speed effects, % flat speed perk(s), % speed set bonus row(s) (% flat) × 3; % probe fleets at 3 × (max deviation % kn; slowest % → % kn empty, % → % kn laden); six bodies unmoved; walls 0; fleet_speed ms %, fleet_speed_at(1) ms %',
    (select count(*) from classes_0219), (select min(speed_kn) from classes_0219), (select min(speed_kn) from public.ship_classes),
    (select max(speed_kn) from classes_0219), (select max(speed_kn) from public.ship_classes),
    (select count(*) from effects_0219), (select count(*) from perks_0219 where mode = 'flat'),
    (select count(*) from gear_0219), (select count(*) from gear_0219 where flat is not null),
    v_n, v_maxdev,
    (select min(kn_before) from fleets_0219), (select min(voyage.fleet_speed(id)) from fleets_0219),
    (select min(laden_before) from fleets_0219), (select min(voyage.fleet_speed_at(id, 1)) from fleets_0219),
    v_ms, v_lms;
end $$;
