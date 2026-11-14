-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0424 - A COMBAT SHIP SAILS THREE TIMES AS FAST AS A MERCHANT  (the navy's and the pirates' ships sail 4.5 times their own speed; a player's
--        fleet, a merchant and a cargo ship sail as they did; a combat ship already at sea finishes the stretch she is on and sails the rest faster)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-15, verbatim: "make combat ships(pirates, navy) at least 3 times faster than merchants."
--
-- READ AS (decided by default; docs/dev-log/2026-11-15-combat-speed.md has the reasoning; the owner may reverse any):
--   * COMBAT SHIPS are the computer's navy ships (public.navy_ships, kind NAVY) and pirate ships (public.pirate_ships, the 0339 seven and 0414's
--     roster, kind PIRATE). MERCHANTS are public.npc_fleets (kind MERCHANT, the pirates' own merchants included: public.fleet_kind answers MERCHANT
--     for them) AND the countries' cargo ships (public.cargo_ships, kind CARGO_SHIP): they carry goods and funds, they do not hunt, so they are
--     merchants for this order.
--   * NOT A PLAYER'S FLEET (kind COMPANY): her speed is her ships', her captains', her skills' and her levels'. Speeding the computer's ships
--     changes nothing she has bought or earned; the door below refuses COMPANY outright.
--   * "AT LEAST 3 TIMES" is measured on the TYPICAL ship: the median knots a kind's voyages at sea departed at (voyages.speed_profile, the speed
--     voyage.depart froze), the same course for both, under the one-hour game day (time_compression 192).
--
-- MEASURED (prod, read-only, 2026-11-15, head 0421; the gate green: beat 110 ms mean / 300 ms p95, 903 MB, 0 disk waits;
--   scripts/ops/harness/combat-speed/measure-speeds.sql and measure-duty.sql), knots at departure of the voyages at sea:
--     MERCHANT    617 at sea of 885: median 17.48 (p10 13.95, p90 19.76); a passage 38 real minutes, 2,113 nm.
--     CARGO_SHIP   52 at sea of 372: median 13.11.
--     NAVY         11 at sea of 43:  median 13.43 (p10 11.66, max 14.47); a passage 110 minutes, 4,743 nm.
--     PIRATE        4 at sea of 25:  median 15.73 (p10 11.70, max 16.55); a passage 41 minutes, 1,658 nm.
--   Three times the merchant median is 52.4 kn. A multiplier of 4.5 for both kinds gives NAVY 60.4 kn (3.46 x) and PIRATE 70.8 kn (4.05 x) at
--   the median, and puts each kind's 10th percentile at 3.0 x the merchant median (52.5 and 52.7 kn): the slow combat ship too, not only the
--   typical one. Even the merchants' fast tenth (p90 19.76) is outsailed 3.06 x by the median navy ship. Decided by default: 4.5, both kinds.
--
-- THE ONE AUTHORITY: "how fast does a fleet sail" is voyage.fleet_speed_at (0367; everything reads it: the departure's frozen speed_profile and
--   eta, the stores a leg needs, the passage gate, the navy's call (public.navy_reach_seconds), the quotes). This file multiplies its answer, for a
--   fleet not in an armada (an armada is a player's), by public.fleet_speed_mult(fleet): world_config.fleet_speed_by_kind ->> public.fleet_kind(fleet),
--   1 for any kind it does not name. So every voyage of those kinds, a cruise, a patrol, a hunt, an escort, a call, a sail home, sails at it.
--   NOTHING ELSE MOVES: ship_classes.speed_kn, a ship's roll, world.ship_stats, gear, captains, skills and levels are as they were, so a ship card
--   still says her hull's own speed. (A navy or pirate card prints no speed.)
-- THE ONE DOOR to move it: public.fleet_speed_set(kind, multiplier, at) (owner only, as public.clock_set is for the clock). It writes the knob and
--   RE-TIMES EVERY VOYAGE OF THAT KIND AT SEA, continuously: the stretch of water (segment) she is on at the instant keeps its frozen speed, so she
--   stands where she stood and finishes that stretch on the schedule she had; every LATER stretch's frozen speed is multiplied by new / old, and her
--   arrival is brought forward by exactly the hours those stretches no longer take (the voyage clock's days, delays and holds are untouched: they are
--   counted from her departure, which does not move). No ship jumps. Rollback: the same door with 1.
--
-- RAIDS AND HUNTS (nothing in the fight reads a ship's speed: public.fight_sides and the battle's rounds are hulls, guns and crews):
--   * A RAID is rolled per voyage-day of the ship that is RAIDED (a merchant's or a player's), against the pirate ship cruising that sea when she
--     left (voyage.freeze_raiders) and the sea's pressure (public.sea_pressure). Neither victim's days at sea move. A pirate ship is "at work" in
--     her sea while she sails out and lies at her haunt (12 real hours, pirate_haunt_hours, unchanged), not on her way home. With passages of ~9
--     minutes instead of ~41 a cruise is ~738 minutes instead of ~802, and she is at work 98.8 % of it instead of 94.9 %: the raids' pressure, the
--     owner's "more aggressive" pirates included, is a little STRONGER, never weaker. A wrecked pirate reborn at home (60 minutes, unchanged) is
--     back at work ~32 minutes sooner.
--   * THE HUNT: a navy ship sails to the most dangerous sea in reach, lies there navy_hunt_hours (6), and sails home. With passages of ~25 minutes
--     instead of ~110 she spends ~88 % of a hunt in the hunted sea instead of ~62 %: up to ~1.4 times as many meetings with a pirate there (still at
--     most one fight an hour a ship, navy_hunts_per_run 5 a minute). Each lost fight now costs a pirate ~69 minutes off work instead of ~101 (the
--     reborn hour plus her sail out), so the time pirates lose to the hunt is about what it was (1.4 x 0.68 = 0.97), while their time at work rises.
--   * A NAVY CALL to a battle (0333) arrives sooner: its arrival is the distance at her speed. A player who attacks a cargo ship meets the navy sooner.
--   * The navy's and pirates' OWN passages roll their own weather and dangers per voyage-day: a 4.5 x faster passage has a 4.5th of the days at sea.
--
-- THE LOAD (docs/DATABASE_BUDGET.md; the beat now handles ~137 fleets and ~109 voyage-days a minute, prod 2026-11-14): a voyage-day costs the same
--   real 450 s whatever the speed, so the days settled a minute do not rise (they fall: a faster ship is less of the time at sea). What rises is
--   ARRIVALS AND DEPARTURES: today NAVY 0.11 and PIRATE 0.12 a minute. Bound: at most 4.5 times today's rate for the navy (0.5) and, with the roster
--   at ~200 fleets, at most ~1.3 for the pirates; realistic +0.1 a minute (their lies are in real hours and do not shrink). At ~20 rows an arrival and
--   departure: at most +32 rows a minute (realistic +2), ~1 % more of the beat's work, and ~2 seconds of the pirates' and navy's jobs an hour. The
--   voyages rows of computer houses are cut at npc_retention_hours (3): at most ~290 more standing rows. Far inside half of every limit.
--
-- RE-CUTS (hunks; each occurs exactly once in the live body and reverses to its pre-image; ACL, volatility, definer, search path, owner unmoved):
--   voyage.fleet_speed_at (0367's body; 0422/0423, the at-sea builder's, cut navy and pirate step bodies, not this one). NEW: public.fleet_speed_mult,
--   public.fleet_speed_set; knob fleet_speed_by_kind. No table, no index, no job.
-- LOCKS: CREATE OR REPLACE by one hunk; one knob; one UPDATE of each NAVY and PIRATE voyage at sea (~15 rows on prod): row locks only, with the
--   clock jobs unwound by the deploy. BUDGET: statement_timeout 60 s, lock_timeout 5 s; fails above 30 s.
-- SELF-ASSERT: the hunk once and reversing; no other function moved; then THE PROBE, rolled back by a raised sentinel: three probe houses (a
--   player's, one made a navy ship, one a pirate ship) put to sea Lisbon to Setubal and back; the door moved while they sail; only their rows are read.
-- ROLLBACK (forward, owner only): scripts/ops/harness/combat-speed/rollback-0424.sql, a draft: public.fleet_speed_set('NAVY', 1) and ('PIRATE', 1).
-- PROOF: scripts/db/proofs/119_a_combat_ship_sails_three_times_as_fast_as_a_merchant.sql (a galion and a xebec against the median merchant).
-- VERSION: 0424 = production head 0421 + 0422/0423 (reserved for the at-sea builder) + 1. If those cut this hunk, this file refuses and is rebased.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $g$
begin
  if exists (select 1 from public.world_config where key = 'fleet_speed_by_kind')
     or to_regprocedure('public.fleet_speed_set(text,numeric,timestamp with time zone)') is not null then
    raise exception '0424 refuses: it has been applied once';
  end if;
  if to_regprocedure('voyage.fleet_speed_alone_at(uuid,numeric)') is null or to_regprocedure('public.fleet_kind(uuid)') is null
     or to_regprocedure('public.news_update(text,text,text)') is null then
    raise exception '0424 refuses: the speed of 0367, the kinds of 0339 or the news are not in this world';
  end if;
end $g$;

insert into public.world_config (key, value, description) values
  ('fleet_speed_by_kind', '{}'::jsonb,
   '0424 (the owner, 2026-11-15: "make combat ships(pirates, navy) at least 3 times faster than merchants"): a multiplier of a fleet''s speed by her kind (public.fleet_kind: NAVY, PIRATE, MERCHANT, CARGO_SHIP), read by public.fleet_speed_mult inside voyage.fleet_speed_at. A kind not named sails at 1. A player''s fleet (COMPANY) is never named. Move it ONLY through public.fleet_speed_set, which re-times that kind''s voyages at sea with it.');

create function public.fleet_speed_mult(p_fleet uuid)
returns numeric
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $f$
  -- 0424: THE ONE READER of world_config.fleet_speed_by_kind: what her kind multiplies a fleet's speed by. 1 for a kind the knob does not name (a
  -- player's fleet always), and for no such fleet.
  select coalesce((select (wc.value ->> public.fleet_kind(p_fleet))::numeric from public.world_config wc where wc.key = 'fleet_speed_by_kind'), 1)
$f$;
revoke all on function public.fleet_speed_mult(uuid) from public, anon, authenticated;

create function public.fleet_speed_set(p_kind text, p_mult numeric, p_at timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $f$
-- 0424: THE ONE DOOR TO MOVE A KIND'S SPEED (world_config.fleet_speed_by_kind). Owner only. By f = new / old, in one statement group:
--   the knob (a multiplier of 1 removes the kind from it);
--   EVERY VOYAGE OF THAT KIND AT SEA, re-timed about p_at with no jump: the segment she is on at p_at (voyage.position) keeps its frozen speed, so
--   her mile at p_at and the rest of that segment are as they were; every later segment's frozen speed is multiplied by f (to 4 places, as the
--   departure keeps it), and her eta moves by exactly the hours those segments gain or lose. Her departure, her days, her delays and her holds are
--   not touched. A voyage already due (eta at or before p_at) is left to the arrivals beat.
-- The same multiplier: nothing is written. Returns what it did.
declare
  v_knob jsonb := coalesce((select wc.value from public.world_config wc where wc.key = 'fleet_speed_by_kind'), '{}'::jsonb);
  v_k    numeric := public.wc_num('time_compression');
  v_old  numeric;
  v_f    numeric;
  r      record;
  v_leg  int;
  v_prof jsonb;
  v_cut  numeric;
  v_n    int := 0;
begin
  if p_kind is null or p_kind not in ('NAVY', 'PIRATE', 'MERCHANT', 'CARGO_SHIP') or p_mult is null or p_mult <= 0 or p_mult > 20 or p_at is null then
    raise exception 'E_BAD_SPEED: % x % at % (a kind of the computer''s ships, NAVY, PIRATE, MERCHANT or CARGO_SHIP, never a player''s; a multiplier above 0 and at most 20)',
      p_kind, p_mult, p_at using errcode = 'P0001';
  end if;
  v_old := coalesce((v_knob ->> p_kind)::numeric, 1);
  if p_mult = v_old then
    return jsonb_build_object('moved', false, 'kind', p_kind, 'mult', v_old);
  end if;
  v_f := p_mult / v_old;
  update public.world_config
     set value = case when p_mult = 1 then v_knob - p_kind else v_knob || jsonb_build_object(p_kind, p_mult) end, updated_at = now()
   where key = 'fleet_speed_by_kind';

  for r in select v.id, v.path, v.speed_profile
             from public.voyages v
            where v.status = 'SAILING' and v.eta > p_at and public.fleet_kind(v.fleet_id) = p_kind loop
    select p.seg_index into v_leg from voyage.position(r.id, p_at) p;
    select jsonb_agg(case when e.o - 1 > v_leg then to_jsonb(round((e.s #>> '{}')::numeric * v_f, 4)) else e.s end order by e.o),
           coalesce(sum(case when e.o - 1 > v_leg
                             then (r.path -> (e.o::int - 1) ->> 'nm')::numeric / (e.s #>> '{}')::numeric
                                - (r.path -> (e.o::int - 1) ->> 'nm')::numeric / round((e.s #>> '{}')::numeric * v_f, 4) end), 0)
      into v_prof, v_cut
      from jsonb_array_elements(r.speed_profile) with ordinality e(s, o);
    if v_cut <> 0 then
      update public.voyages v
         set speed_profile = v_prof,
             eta = v.eta - make_interval(secs => (v_cut * 3600 / v_k)::double precision)
       where v.id = r.id;
      v_n := v_n + 1;
    end if;
  end loop;

  return jsonb_build_object('moved', true, 'kind', p_kind, 'was', v_old, 'mult', p_mult, 'at', p_at, 'voyages', v_n);
end
$f$;
revoke all on function public.fleet_speed_set(text, numeric, timestamptz) from public, anon, authenticated;

do $m$
declare
  c_cut   constant text[] := array['voyage.fleet_speed_at(uuid,numeric)'];
  c_uid_a constant uuid := '00000000-0000-4000-8000-00000000424a';
  c_uid_b constant uuid := '00000000-0000-4000-8000-00000000424b';
  c_uid_c constant uuid := '00000000-0000-4000-8000-00000000424c';
  c_mult  constant numeric := 4.5;
  v_t0        timestamptz := clock_timestamp();
  h           record;
  v_z         record;
  v_def       text;
  v_n         int;
  v_fn_before text;
  v_lis       uuid;
  v_set       uuid;
  v_c1        jsonb;
  v_c2        jsonb;
  v_segs      jsonb;
  v_ha        uuid;
  v_hb        uuid;
  v_hc        uuid;
  v_fa        uuid;
  v_fb        uuid;
  v_fc        uuid;
  v_va        uuid;
  v_vb        uuid;
  v_vc        uuid;
  v_dep       timestamptz;
  v_at        timestamptz;
  v_end0      timestamptz;
  v_a0        record;
  v_b0        record;
  v_o         jsonb;
  v_v         record;
  v_ids       uuid[];
  v_pb        numeric;
  v_pc        numeric;
  v_leg       int;
  v_cut       numeric;
  v_x         numeric;
  v_r         jsonb;
  v_note      text := '';
  v_sw        jsonb;
  v_sw2       jsonb;
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0424 (fn text primary key, def text, meta text) on commit drop;
  insert into pre_0424
  select f, replace(pg_get_functiondef(f::regprocedure), E'\r', ''),
         (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
            from pg_proc p where p.oid = f::regprocedure)
    from unnest(c_cut) f;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and not exists (select 1 from unnest(c_cut) f where f::regprocedure = p.oid);

  -- ── 2. THE HUNK: a fleet not in an armada sails at her own speed times her kind's ──
  create temp table hunk_0424 (ord int primary key, fn text, old text, new text) on commit drop;
  insert into hunk_0424 values
  (1, c_cut[1],
$h$    return voyage.fleet_speed_alone_at(p_fleet, p_fill);
  end if;
$h$,
$h$    -- 0424: times her kind's multiplier (public.fleet_speed_mult: the navy's and the pirates' ships 4.5, so a combat ship sails at least three
    -- 0424: times as fast as a merchant; 1 for a player's fleet, a merchant and a cargo ship). An armada is a player's: it is not multiplied.
    return voyage.fleet_speed_alone_at(p_fleet, p_fill) * public.fleet_speed_mult(p_fleet);
  end if;
$h$);
  for h in select * from hunk_0424 order by ord loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0424 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', h.ord, h.fn, v_n;
    end if;
    execute replace(v_def, h.old, h.new);
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    if (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new) <> 1 then
      raise exception '0424 self-assert FAIL: hunk % of % is not in the new body once', h.ord, h.fn;
    end if;
    if (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
          from pg_proc p where p.oid = h.fn::regprocedure) <> (select p.meta from pre_0424 p where p.fn = h.fn) then
      raise exception '0424 self-assert FAIL: the grants, volatility, definer, search path or owner of % moved', h.fn;
    end if;
  end loop;
  for h in select p.fn, p.def from pre_0424 p loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    for v_z in select x.old, x.new from hunk_0424 x where x.fn = h.fn order by x.ord desc loop
      v_def := replace(v_def, v_z.new, v_z.old);
    end loop;
    if v_def <> h.def then
      raise exception '0424 self-assert FAIL: % does not reverse to its pre-image', h.fn;
    end if;
  end loop;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and not exists (select 1 from unnest(c_cut) f where f::regprocedure = p.oid)) <> v_fn_before then
    raise exception '0424 self-assert FAIL: another function moved';
  end if;
  if has_function_privilege('anon', 'public.fleet_speed_set(text,numeric,timestamp with time zone)', 'execute')
     or has_function_privilege('authenticated', 'public.fleet_speed_set(text,numeric,timestamp with time zone)', 'execute')
     or has_function_privilege('authenticated', 'public.fleet_speed_mult(uuid)', 'execute')
     or (select p.provolatile from pg_proc p where p.oid = 'public.fleet_speed_mult(uuid)'::regprocedure) <> 's' then
    raise exception '0424 self-assert FAIL: the door or its reader is open to a player, or the reader is not stable';
  end if;

  -- ── 3. THE PROBE: three houses put to sea Lisbon to Setubal and back, one a player's (A), one made a navy ship (B), one a pirate ship (C); the
  --      kinds moved through the door while they sail, all rolled back. Only these three voyages and the knob are read; the instants are passed in.
  begin
    select id into v_lis from public.ports where code = 'LIS';
    select id into v_set from public.ports where code = 'SET';
    select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(b.roadstead_lat, b.roadstead_lon)),
           jsonb_build_array(jsonb_build_array(b.roadstead_lat, b.roadstead_lon), jsonb_build_array(a.roadstead_lat, a.roadstead_lon))
      into v_c1, v_c2 from public.sea_reaches a, public.sea_reaches b where a.port_id = v_lis and b.port_id = v_set;
    if v_c1 is null then
      raise exception '0424 self-assert FAIL: Lisbon or Setubal has no roadstead to sail between';
    end if;
    v_segs := voyage.segments_from_course(v_c1) || voyage.segments_from_course(v_c2);
    v_dep  := now();
    v_ha := public.new_house(c_uid_a, 'Casa Vagar', 'PRT');
    v_hb := public.new_house(c_uid_b, 'Casa Fragata', 'PRT');
    v_hc := public.new_house(c_uid_c, 'Casa Corsario', 'PRT');
    select f.id into v_fa from public.fleets f where f.player_id = v_ha limit 1;
    select f.id into v_fb from public.fleets f where f.player_id = v_hb limit 1;
    select f.id into v_fc from public.fleets f where f.player_id = v_hc limit 1;
    insert into public.navy_ships (fleet_id, player_id, nation_id, ord, station_port, last_port)
    values (v_fb, v_hb, (select g.nation_id from public.great_powers g order by g.nation_id limit 1), 2000000424, v_lis, v_lis);
    insert into public.pirate_ships (fleet_id, player_id, ord, home_port, last_port) values (v_fc, v_hc, 2000000424, v_lis, v_lis);
    if public.fleet_kind(v_fa) <> 'COMPANY' or public.fleet_kind(v_fb) <> 'NAVY' or public.fleet_kind(v_fc) <> 'PIRATE' then
      raise exception '0424 self-assert FAIL: the probe''s kinds are %, %, %', public.fleet_kind(v_fa), public.fleet_kind(v_fb), public.fleet_kind(v_fc);
    end if;
    -- the knob still empty: every kind sails at her own speed, to the digit
    if voyage.fleet_speed(v_fa)::text <> voyage.fleet_speed_alone_at(v_fa, null)::text or voyage.fleet_speed(v_fb)::text <> voyage.fleet_speed_alone_at(v_fb, null)::text
       or voyage.fleet_speed(v_fc)::text <> voyage.fleet_speed_alone_at(v_fc, null)::text then
      raise exception '0424 self-assert FAIL: with the knob empty a speed moved';
    end if;
    v_va := voyage.depart(v_fa, v_segs, v_lis, v_lis, v_dep);
    v_vb := voyage.depart(v_fb, v_segs, v_lis, v_lis, v_dep);
    v_vc := voyage.depart(v_fc, v_segs, v_lis, v_lis, v_dep);
    select v.eta, v.speed_profile, v.departed_at into v_a0 from public.voyages v where v.id = v_va;
    select v.eta, v.speed_profile, v.path, v.departed_at into v_b0 from public.voyages v where v.id = v_vb;
    select jsonb_object_agg(v.id, jsonb_build_object('eta', v.eta, 'sp', v.speed_profile, 'dep', v.departed_at, 'nm', voyage.progress_nm(v.id, v_dep)))
      into v_o from public.voyages v where v.id in (v_vb, v_vc);
    if jsonb_array_length(v_segs) < 2 then
      raise exception '0424 self-assert FAIL: the probe course has % segment(s); it needs two to re-time one', jsonb_array_length(v_segs);
    end if;
    -- the instant: half way along B's first segment (her second is still to sail)
    v_at := v_dep + make_interval(secs => ((v_segs -> 0 ->> 'nm')::numeric / 2 / (v_b0.speed_profile ->> 0)::numeric * 3600 / public.wc_num('time_compression'))::double precision);
    v_end0 := v_dep + make_interval(secs => ((v_segs -> 0 ->> 'nm')::numeric / (v_b0.speed_profile ->> 0)::numeric * 3600 / public.wc_num('time_compression'))::double precision);
    v_pb := voyage.progress_nm(v_vb, v_at);
    v_pc := voyage.progress_nm(v_vc, v_at);
    v_ids := array[v_vb, v_vc];
    select p.seg_index into v_leg from voyage.position(v_vb, v_at) p;
    if v_leg <> 0 or v_pb <= 0 then
      raise exception '0424 self-assert FAIL: the navy probe is not under way on her first segment at the instant (leg %, % nm)', v_leg, v_pb;
    end if;

    v_r := public.fleet_speed_set('NAVY', c_mult, v_at);
    v_sw := public.fleet_speed_set('PIRATE', c_mult, v_at);
    if not (v_r ->> 'moved')::boolean or (v_r ->> 'voyages')::int < 1 or not (v_sw ->> 'moved')::boolean or (v_sw ->> 'voyages')::int < 1
       or (select value from public.world_config where key = 'fleet_speed_by_kind') <> jsonb_build_object('NAVY', c_mult, 'PIRATE', c_mult) then
      raise exception '0424 self-assert FAIL: the door did not move the kinds with the probe voyages (% / %)', v_r, v_sw;
    end if;
    -- A, the player's: her voyage and her speed as they were, to the digit
    select v.eta, v.speed_profile, v.departed_at into v_v from public.voyages v where v.id = v_va;
    if v_v.eta <> v_a0.eta or v_v.speed_profile <> v_a0.speed_profile or v_v.departed_at <> v_a0.departed_at
       or voyage.fleet_speed(v_fa)::text <> voyage.fleet_speed_alone_at(v_fa, null)::text or public.fleet_speed_mult(v_fa) <> 1 then
      raise exception '0424 self-assert FAIL: the player''s voyage or speed moved (eta % was %; speed % alone %)', v_v.eta, v_a0.eta, voyage.fleet_speed(v_fa), voyage.fleet_speed_alone_at(v_fa, null);
    end if;
    -- B and C: the same mile at the instant; the first segment's speed kept and ended on its old schedule; every later one x 4.5; the eta earlier by exactly that
    foreach v_n in array array[1, 2] loop
      select v.id, v.eta, v.speed_profile, v.departed_at, v.path into v_v from public.voyages v where v.id = v_ids[v_n];
      v_cut := 0;
      for i in 1 .. jsonb_array_length(v_v.path) - 1 loop
        if (v_v.speed_profile ->> i)::numeric <> round((v_o -> v_v.id::text -> 'sp' ->> i)::numeric * c_mult, 4) then
          raise exception '0424 self-assert FAIL: segment % of the % probe sails % kn, not % x %', i, case v_n when 1 then 'navy' else 'pirate' end,
            v_v.speed_profile ->> i, c_mult, v_o -> v_v.id::text -> 'sp' ->> i;
        end if;
        v_cut := v_cut + (v_v.path -> i ->> 'nm')::numeric / (v_o -> v_v.id::text -> 'sp' ->> i)::numeric - (v_v.path -> i ->> 'nm')::numeric / (v_v.speed_profile ->> i)::numeric;
      end loop;
      v_x := case v_n when 1 then v_pb else v_pc end;
      if (v_v.speed_profile ->> 0) <> (v_o -> v_v.id::text -> 'sp' ->> 0) or v_v.departed_at <> (v_o -> v_v.id::text ->> 'dep')::timestamptz
         or abs(voyage.progress_nm(v_v.id, v_at) - v_x) > 0.01
         or abs(extract(epoch from v_v.eta - ((v_o -> v_v.id::text ->> 'eta')::timestamptz - make_interval(secs => (v_cut * 3600 / public.wc_num('time_compression'))::double precision)))) > 0.005
         or v_v.eta >= (v_o -> v_v.id::text ->> 'eta')::timestamptz then
        raise exception '0424 self-assert FAIL: the % probe jumped or was not re-timed (% nm at the instant, was %; eta %, was %, cut % h)',
          case v_n when 1 then 'navy' else 'pirate' end, voyage.progress_nm(v_v.id, v_at), v_x, v_v.eta, v_o -> v_v.id::text ->> 'eta', v_cut;
      end if;
    end loop;
    if abs(voyage.progress_nm(v_vb, v_end0) - (v_segs -> 0 ->> 'nm')::numeric) > 0.01 then
      raise exception '0424 self-assert FAIL: the navy probe did not end her first segment on its old schedule (% nm at %)', voyage.progress_nm(v_vb, v_end0), v_end0;
    end if;
    -- a departure now: the navy and the pirate ship sail at 4.5 times their own speed, so the same course takes a 4.5th as long
    if voyage.fleet_speed(v_fb) <> voyage.fleet_speed_alone_at(v_fb, null) * c_mult or voyage.fleet_speed(v_fc) <> voyage.fleet_speed_alone_at(v_fc, null) * c_mult then
      raise exception '0424 self-assert FAIL: a combat ship''s speed is not 4.5 times her own (% and %)', voyage.fleet_speed(v_fb), voyage.fleet_speed(v_fc);
    end if;
    -- the door refuses a player's fleet, and moves nothing at the same multiplier
    begin
      perform public.fleet_speed_set('COMPANY', 2, v_at);
      raise exception '0424 self-assert FAIL: the door moved a player''s speed';
    exception when sqlstate 'P0001' then
      if sqlerrm not like 'E_BAD_SPEED%' then raise; end if;
    end;
    if (public.fleet_speed_set('NAVY', c_mult, v_at) ->> 'moved')::boolean then
      raise exception '0424 self-assert FAIL: the same multiplier was written again';
    end if;
    -- the rollback through the same door is continuous too: back to 1 at the same instant, B's arrival is what it was
    v_sw2 := public.fleet_speed_set('NAVY', 1, v_at);
    if abs(extract(epoch from (select v.eta from public.voyages v where v.id = v_vb) - v_b0.eta)) > 0.05 or abs(voyage.progress_nm(v_vb, v_at) - v_pb) > 0.01
       or (select value from public.world_config where key = 'fleet_speed_by_kind') <> jsonb_build_object('PIRATE', c_mult)
       or voyage.fleet_speed(v_fb)::text <> voyage.fleet_speed_alone_at(v_fb, null)::text then
      raise exception '0424 self-assert FAIL: moved back to 1 the navy probe is not as she was (eta %, was %)', (select v.eta from public.voyages v where v.id = v_vb), v_b0.eta;
    end if;
    v_note := 'a player''s, a navy and a pirate voyage Lisbon-Setubal-Lisbon, re-timed half way along the first segment: the player''s unmoved; the pirate''s ' ||
              round(extract(epoch from (v_o -> v_vc::text ->> 'eta')::timestamptz - v_at), 2) || ' s left became ' ||
              round(extract(epoch from (select v.eta from public.voyages v where v.id = v_vc) - v_at), 2) ||
              ' s, and the navy''s likewise; the same mile at the instant; the first segment ended on its old schedule; the navy back to 1, as she was';
    raise exception sqlstate 'BV424';
  exception when sqlstate 'BV424' then null;
  end;
  if v_note = '' then
    raise exception '0424 self-assert FAIL: the probe did not run to its end';
  end if;
  if (select value from public.world_config where key = 'fleet_speed_by_kind') <> '{}'::jsonb
     or exists (select 1 from public.players where auth_uid in (c_uid_a, c_uid_b, c_uid_c)) then
    raise exception '0424 self-assert FAIL: the probe was not rolled back';
  end if;

  -- ── 4. THE SWITCH, at this transaction's instant ──
  v_sw  := public.fleet_speed_set('NAVY', c_mult, now());
  v_sw2 := public.fleet_speed_set('PIRATE', c_mult, now());
  if (select value from public.world_config where key = 'fleet_speed_by_kind') <> jsonb_build_object('NAVY', c_mult, 'PIRATE', c_mult) then
    raise exception '0424 self-assert FAIL: the knob is not this file''s';
  end if;

  perform public.news_update('0424', 'Navy and pirate ships now sail three times as fast as merchants',
                             '해군과 해적선이 이제 상선보다 세 배 빠르게 항해합니다');

  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0424 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0424 self-assert ok: A COMBAT SHIP SAILS THREE TIMES AS FAST AS A MERCHANT. One hunk in voyage.fleet_speed_at, once and reversing; grants and volatility unmoved; no other function moved; fleet_speed_by_kind %. Probe: %. The switch re-timed % navy and % pirate voyage(s) at sea; % ms.',
    (select value from public.world_config where key = 'fleet_speed_by_kind'), v_note, v_sw ->> 'voyages', v_sw2 ->> 'voyages', round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
