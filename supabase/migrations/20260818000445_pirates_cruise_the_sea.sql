-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0445 - PIRATES CRUISE THE SEA  (a pirate spends her time under sail on a long patrol of the stored lanes of her waters, strikes only from the
--        sea, lies in a harbour two minutes instead of twelve hours, and goes home to refit when she is hurt)
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-15: "pirates still in port. too much. fix this please". Standing (row 347, 0432): "pirates' main goal is to attack other npcs,
-- loot them". Stats that day: pirate fleets 121, laid up 0, PORT 118, SEA 0.
--
-- WHY (prod 2026-11-15 14:55 UTC, head 0442, gate green, beat 119 ms; scripts/ops/harness/pirates-at-sea/before.sql and design.sql;
--   docs/dev-log/2026-11-16-pirates-at-sea.md): 121 pirate fleets, 116 at work, 4 wrecked, 1 laid up. Of the 116: 112 DOCKED at their haunt harbour
--   (lying 386 minutes at the median, 407 at most), 2 IN_BATTLE at their haunt, 2 SAILING. At sea: 2 %.
-- ROOT CAUSE:
--   (1) THE LIE. public.pirate_ship_step (0339): a pirate sails ONE stored course from her home to a haunt harbour and then LIES there
--       pirate_haunt_hours = 12 REAL hours, sails home, and at once out again. Since 0422 a pirate sails 4.5 times her speed: her passage is 6 real
--       minutes at the median (1,007 nm at 168 nm a real minute, 38 passages in two hours for 121 fleets). Six minutes at sea, twelve hours at the quay.
--   (2) SHE RAIDS FROM THE QUAY. public.pirate_strike (0427) takes every pirate in public.pirate_ships_cruising, which counts a ship lying DOCKED
--       at her haunt as "in her sea": the 116 raids of the hour (76 different pirates) were opened from a harbour on a merchant up to
--       attack_reach_nm (240) miles off. Both raids being fought at the read had their pirate in port. So the raids ran while nobody sailed.
--   (3) The Stats "port" count is every pirate fleet whose fleets.status is not SAILING (public.stats_fleets_count): it was right.
--
-- WHAT THIS FILE DOES:
--   S1. A PIRATE CRUISES (new public.pirate_cruise_plan, stable; public.pirate_ship_step, 3 hunks). A cruise is ONE voyage along several stored
--       lanes (public.npc_courses) of her waters, laid end to end: from her home out to her haunts, each in turn after the last she left, by the lane
--       between two haunts where one is stored and through her home where none is, until the cruise is pirate_cruise_nm (5,000) long or
--       pirate_cruise_courses (24) lanes: an OUT cruise ends at a haunt, the cruise BACK ends at her home. Her haunts are 0339's and 0414's own rule
--       (public.pirate_haunt_of: one stored course from her home, inside her hub's reach, the way back stored, no pirate home), in its order.
--       5,000 nm is ~30 real minutes at prod's 168 nm a minute. Her sea (pirate_ships.sea_id: who raids, the pressure, the navy's hunt) is the sea
--       of the first haunt on her way, on the cruise back as well: she hunts both ways.
--       NO NEW COURSE IS DRAWN: every piece is a stored lane, as it is sailed today (0440-0442: none crosses the drawn land).
--   S2. PORT TIME IS SHORT. At the end of a cruise she lies pirate_port_minutes (2), not pirate_haunt_hours (12 h; the knob is no longer read),
--       then takes her next cruise from where she lies. At her home she is mended free (as before) and sails at her next step.
--   S3. HURT, SHE GOES HOME TO REFIT (new public.pirate_hurt, stable): her hulls together under pirate_refit_below (0.5) of their best, she sails
--       the one stored course straight home from the harbour she lies in, in no sea (she raids nobody and is not hunted), and is mended there.
--       A fight at sea holds her where she is and she sails on when it ends (0432's hold, unchanged): she resumes her cruise.
--   S4. SHE RAIDS FROM THE SEA (public.pirate_strike, public.pirate_strikes, 1 hunk each): only a pirate UNDER SAIL strikes. A pirate in a
--       harbour opens no raid. The reach (attack_reach_nm), the rest, 0432's flee and peace, no PvP and 0429's "never her own cargo ships" are
--       unmoved. Knob pirate_strike_from_port (false) is the quick way back. More pirates are asked a run (pirate_strike_tries_per_run 8 -> 16,
--       only from prod's 8): a pirate in mid-ocean has nobody in reach more often than one lying beside a harbour had.
--   S5. THE MINUTE JOB KEEPS UP (public.tick_pirates, 3 hunks; public.pirate_trade, 1 hunk; new public.pirate_trader_step). Before, the run
--       stopped at the first ship that traded (0415: nothing runs behind a trade's locks) and left the strikes, the add and the pay to the next
--       minute. With ~4 pirates leaving a harbour a minute that would be one sailing a minute and no raid at all. Now ONE ship a run may trade:
--       the first in the turning order is put aside (only while pirates_trade is lit) and steps LAST, after the strikes, the purses and the joins
--       (public.pirate_trader_step);
--       every other ship of the run sails without trading (byeharu.pirate_trade_hold). 0415's law holds better than before: nothing at all runs
--       behind a trade's locks. At most pirate_sails_per_run (8) ships leave a harbour a run, so the first minutes after the deploy (112 pirates
--       past their two minutes) are spread over ~14 runs.
--   S6. THE JOIN FINDS HER (public.battle_join_near, 1 hunk): 0436's sieve places a sailing ship between the two harbours of her voyage by the
--       clock. A cruise is a chain of lanes and may end where it began, so a pirate is placed where she is (voyage.fleet_point; at most ~110
--       points, only when a live raid's roll lets a pirate join). The navy's sieve is unmoved.
--   KNOBS (new): pirate_cruise_nm 5000, pirate_cruise_courses 24, pirate_port_minutes 2, pirate_refit_below 0.5, pirate_sails_per_run 8,
--       pirate_strike_from_port false. Moved: pirate_strike_tries_per_run 8 -> 16.
--
-- EXPECTED: at sea ~85-90 % of the working pirates within ~30 minutes of the deploy (a cruise is 30-55 real minutes, a harbour 2-4), never under
--   70 %. Raids stay at their ceiling of 2 a minute where merchants sail (the lanes she cruises are the merchants' own).
-- budget: no job, no table, no index. ~3.6 pirate voyages begin a minute (121 fleets, a cruise of 30-55 minutes) against 0.3 today: about
--   +110 rows a minute (a voyage row, its days' events and the fleet, ship and quay rows of a departure and an arrival), inside a per-minute
--   job's 5,000 rows. The pirates' job (never in the beat) lays ~4 cruises a run, at most 9. The arrivals beat lands ~3.6 more ships a minute
--   beside the merchants' own.
-- LOCKS: CREATE OR REPLACE x6 (by hunks: 10), CREATE FUNCTION x3, 6 knobs inserted, 1 moved. TIME: the cut is milliseconds; the probe (one pirate
--   cruised out, lain, cruised back, hurt and sent home, rolled back) under 5 s. BUDGET: statement_timeout 30 s, lock_timeout 5 s; fails above 20 s.
-- ROLLBACK (forward, owner only): quick, no file: pirate_strike_from_port true (raids from the quay again) and pirate_port_minutes 720 (the
--   twelve-hour lie). Whole: scripts/ops/harness/pirates-at-sea/rollback-0445.sql (a draft: the hunks reversed, the three functions and the six
--   knobs dropped, the tries back to 8).
-- SELF-ASSERT: every hunk once and reversing; grants, volatility, definer, search path, owner of the re-cut functions unmoved; no other function
--   moved; the two readers stable, the three new functions definer and server-only. THE PROBE, rolled back, on ANY world (the CI world has no
--   pirate ship and the pirates dark: the probe lights them and builds one roster fleet; prod's own probe takes a pirate lying in a harbour): at
--   her home she SAILS an out cruise of stored lanes, at least pirate_cruise_nm long or pirate_cruise_courses lanes, ending at a haunt, in a
--   sea; under sail she may strike, lying in a harbour she may not (NOT_HUNTING), with the knob she may; at the haunt she lies
--   pirate_port_minutes and then SAILS the cruise back, which ends at her home; hurt, she sails ONE course straight home in no sea; a ship held
--   back from trading trades nothing, and the trader's step lets the hold go.
-- VERSION: 0445 (0443 and 0444 are other branches; prod head 0442 when this was cut). If one of them cuts a line of these hunks this file refuses
--   at "occurs 0 time(s)" and is rebased.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0        timestamptz := clock_timestamp();
  v_now       timestamptz := now();
  v_fn_before text;
  v_meta      text;
  v_h         record;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_pf        uuid;
  v_home      uuid;
  v_hub       uuid;
  v_haunt     uuid;
  v_hsea      uuid;
  v_ord       int;
  v_min       numeric;
  v_cap       int;
  v_port      numeric;
  v_p         record;
  v_b         record;
  v_v         record;
  v_r         text;
  v_bits      jsonb;
  v_note      text;
  v_built     boolean := false;
  c_new       constant text[] := array['public.pirate_cruise_plan(uuid,uuid)', 'public.pirate_hurt(uuid)', 'public.pirate_trader_step(uuid,timestamp with time zone,jsonb)'];
  c_keys      constant text[] := array['pirate_cruise_nm', 'pirate_cruise_courses', 'pirate_port_minutes', 'pirate_refit_below', 'pirate_sails_per_run', 'pirate_strike_from_port'];
  c_hunked    constant text[] := array['public.pirate_ship_step(uuid,timestamp with time zone)', 'public.pirate_strike(uuid,timestamp with time zone)',
                                       'public.pirate_strikes(timestamp with time zone)', 'public.pirate_trade(uuid,uuid,timestamp with time zone)',
                                       'public.tick_pirates(timestamp with time zone)', 'public.battle_join_near(uuid,text,timestamp with time zone)'];
begin
  perform set_config('statement_timeout', '30s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('public.pirate_strikes(timestamp with time zone)') is null or to_regprocedure('public.battle_npc_joins(timestamp with time zone)') is null
     or to_regprocedure('public.pirate_purse_step(timestamp with time zone)') is null or to_regprocedure('public.fleet_peace_until(uuid)') is null
     or to_regprocedure('public.pirate_commission_fleet(integer,uuid,timestamp with time zone)') is null or to_regclass('public.pirate_hubs') is null
     or to_regprocedure('public.news_update(text,text,text)') is null or to_regprocedure('public.battle_join_near(uuid,text,timestamp with time zone)') is null
     or not exists (select 1 from public.world_config where key = 'pirate_strike_tries_per_run') then
    raise exception '0445 refuses: 0414 (homes and grounds), 0427 (the strike), 0429 (the purses), 0432 (the peace), 0436 (the join) or the news are not all in this world';
  end if;
  if to_regprocedure('public.pirate_cruise_plan(uuid,uuid)') is not null or exists (select 1 from public.world_config where key = any (c_keys)) then
    raise exception '0445 refuses: it has been applied once';
  end if;

  -- ── 1. THE PRE-IMAGE ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked) x));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta
    from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_hunked) x));

  -- ── 2. THE KNOBS ──
  insert into public.world_config (key, value, description) values
    ('pirate_cruise_nm', to_jsonb(5000), '0445: how long a pirate''s cruise is at least, in miles of stored lanes laid end to end (public.pirate_cruise_plan). 5,000 is about 30 real minutes at 168 nm a minute. Longer: fewer voyages a minute and fewer calls at a harbour.'),
    ('pirate_cruise_courses', to_jsonb(24), '0445: the most stored lanes one cruise is made of (public.pirate_cruise_plan): a home whose haunts lie a few miles off still makes a bounded voyage.'),
    ('pirate_port_minutes', to_jsonb(2), '0445: how many real minutes a pirate lies in the harbour her cruise ends at before her next cruise (public.pirate_ship_step). It replaces pirate_haunt_hours (12 hours), which is no longer read. 720 is the old lie.'),
    ('pirate_refit_below', to_jsonb(0.5), '0445: a pirate whose hulls together are under this share of their best goes straight home to refit instead of cruising on (public.pirate_hurt). 0: never.'),
    ('pirate_sails_per_run', to_jsonb(8), '0445: the most pirates that leave a harbour in one run of the pirates'' minute job (public.tick_pirates), beside the one ship that may trade.'),
    ('pirate_strike_from_port', 'false'::jsonb, '0445: false: only a pirate under sail opens a raid (public.pirate_strike, public.pirate_strikes). True: a pirate lying in a harbour of her sea raids too, as 0427 had it.');
  update public.world_config set value = to_jsonb(16) where key = 'pirate_strike_tries_per_run' and value = to_jsonb(8);

  -- ── 3. THE NEW FUNCTIONS ──
  execute $f$
create function public.pirate_hurt(p_fleet uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0445: A PIRATE IS HURT when her hulls together are under pirate_refit_below of their own best (public.ship_base, the measure public.fleet_mend
  -- mends to). Hurt, she goes home to refit instead of cruising on (public.pirate_ship_step). No hull, or the knob 0 or missing: false.
  select coalesce((select sum(s.durability) < coalesce(public.wc_num('pirate_refit_below'), 0) * sum((select b.durability from public.ship_base(s.id) b))
                     from public.ships s where s.fleet_id = p_fleet), false)
$body$
  $f$;

  execute $f$
create function public.pirate_cruise_plan(p_fleet uuid, p_from uuid)
returns table (port_id uuid, sea_id uuid, segments jsonb, nm numeric, courses integer)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0445 (the owner, 2026-11-15: "pirates still in port. too much"): THE CRUISE OF A PIRATE LYING AT p_from: one voyage along several STORED lanes
-- (public.npc_courses) laid end to end, so she is under sail for about half an hour instead of six minutes. Her haunts are 0339's and 0414's own
-- (public.pirate_haunt_of's rule and order: one stored course from her home, inside her hub's reach, the way back stored, no pirate home, the most
-- dangerous sea first). From her home she goes out to the haunt after the last she left (pirate_ships.last_port; the first time, the haunt her ord
-- gives, as public.pirate_haunt_of); from a haunt she takes the lane to her next haunt where one is stored and inside her reach, else the lane home.
-- THE END: an OUT cruise (begun at her home) ends at the first haunt reached with pirate_cruise_nm behind her; the cruise BACK (begun anywhere else)
-- turns for home as soon as the lane home completes pirate_cruise_nm, and ends there. Never more than pirate_cruise_courses lanes: then it ends
-- where it is. No new course is drawn: every piece is a stored lane (0440-0442: none crosses the drawn land).
-- Answers the harbour it ends at, her sea (the first haunt's on her way; the harbour's she leaves, when the way is straight home), the segments
-- (voyage.segments_from_course of each lane, in order), the miles and the lanes. No row: no such pirate, no haunt, or no stored lane from p_from.
declare
  v_fleet uuid;
  v_home  uuid;
  v_ord   int;
  v_last  uuid;
  v_min   numeric := coalesce(public.wc_num('pirate_cruise_nm'), 0);
  v_cap   int := greatest(coalesce(public.wc_int('pirate_cruise_courses'), 1), 1);
  v_reach numeric;
  v_h     uuid[];
  v_m     int;
  v_prev  int;
  v_cur   uuid := p_from;
  v_nxt   uuid;
  v_cand  uuid;
  v_out   boolean;
  v_seg   jsonb := '[]'::jsonb;
  v_nm    numeric := 0;
  v_k     int := 0;
  v_sea   uuid;
  v_c     jsonb;
  v_cnm   numeric;
begin
  select x.fleet_id, x.home_port, x.ord, x.last_port into v_fleet, v_home, v_ord, v_last from public.pirate_ships x where x.fleet_id = p_fleet;
  if v_fleet is null or p_from is null then
    return;
  end if;
  v_reach := coalesce((select hb.reach_nm from public.pirate_hubs hb where hb.port_id = v_home), public.wc_num('navy_reach_nm'));
  v_h := array(select h.pid
                 from (select c.to_port as pid, voyage.sea_danger(p.sea_id, null) as danger, p.code
                         from public.npc_courses c join public.ports p on p.id = c.to_port
                        where c.from_port = v_home and p.kind = 'HARBOUR' and c.nm <= v_reach
                          and exists (select 1 from public.npc_courses b where b.from_port = c.to_port and b.to_port = v_home)
                          and not exists (select 1 from public.port_allegiance a join public.great_powers g on g.nation_id = a.nation_id
                                           where a.port_id = p.id and a.home and g.pirate)) h
                order by h.danger desc, h.code);
  v_m := coalesce(array_length(v_h, 1), 0);
  if v_m = 0 then
    return;
  end if;
  v_out := p_from = v_home;
  -- the haunt she was at last: the one she lies at, or (at home) the one she came home from; else the one before her ord's own
  v_prev := coalesce(array_position(v_h, case when v_out then v_last else p_from end), (greatest(v_ord, 1) - 2 + v_m) % v_m + 1);
  loop
    exit when v_k >= v_cap;
    if v_cur = v_home then
      v_prev := v_prev % v_m + 1;
      v_nxt := v_h[v_prev];
    else
      v_nxt := v_home;
      select c.nm into v_cnm from public.npc_courses c where c.from_port = v_cur and c.to_port = v_home;
      if v_out or v_cnm is null or v_nm + v_cnm < v_min then
        v_cand := v_h[v_prev % v_m + 1];
        if v_cand <> v_cur and exists (select 1 from public.npc_courses c where c.from_port = v_cur and c.to_port = v_cand and c.nm <= v_reach) then
          v_nxt := v_cand;
          v_prev := v_prev % v_m + 1;
        end if;
      end if;
    end if;
    v_c := null;
    select c.course, c.nm into v_c, v_cnm from public.npc_courses c where c.from_port = v_cur and c.to_port = v_nxt;
    exit when v_c is null;   -- no stored lane from here (a harbour that is none of her haunts, with no way home)
    v_seg := v_seg || voyage.segments_from_course(v_c);
    v_nm := v_nm + v_cnm;
    v_k := v_k + 1;
    v_cur := v_nxt;
    if v_sea is null and v_cur <> v_home then
      v_sea := (select p.sea_id from public.ports p where p.id = v_cur);
    end if;
    exit when v_nm >= v_min and (v_cur = v_home) = (not v_out);
  end loop;
  if v_k = 0 then
    return;
  end if;
  return query select v_cur, coalesce(v_sea, (select p.sea_id from public.ports p where p.id = p_from)), v_seg, v_nm, v_k;
end
$body$
  $f$;

  execute $f$
create function public.pirate_trader_step(p_fleet uuid, p_now timestamptz, p_steps jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0445: THE ONE SHIP OF A RUN THAT MAY TRADE STEPS LAST. public.tick_pirates puts the first ship of its turning order aside and calls this as the
-- last thing of the run, after the strikes, the purses and the joins: the hold on trading (byeharu.pirate_trade_hold, set by the job for its other
-- ships) is let go, and she takes her step (public.pirate_ship_step), trading as she leaves (public.pirate_trade). So nothing of the run is behind
-- a trade's locks (0415's law), and the other ships of the run did not wait for her. A fault is one warning. Answers {steps: p_steps with her answer counted}.
declare
  v_s text;
begin
  perform set_config('byeharu.pirate_trade_hold', '', true);
  if p_fleet is null then
    return jsonb_build_object('steps', coalesce(p_steps, '{}'::jsonb));
  end if;
  begin
    v_s := public.pirate_ship_step(p_fleet, p_now);
  exception when others then
    raise warning 'tick_pirates: fleet % stayed (SQLSTATE %: %)', p_fleet, sqlstate, sqlerrm;
    v_s := 'ERROR';
  end;
  return jsonb_build_object('steps', coalesce(p_steps, '{}'::jsonb) || jsonb_build_object(v_s, coalesce((p_steps ->> v_s)::int, 0) + 1));
end
$body$
  $f$;

  revoke all on function public.pirate_hurt(uuid) from public, anon, authenticated;
  revoke all on function public.pirate_cruise_plan(uuid, uuid) from public, anon, authenticated;
  revoke all on function public.pirate_trader_step(uuid, timestamptz, jsonb) from public, anon, authenticated;
  comment on function public.pirate_hurt(uuid) is '0445: a pirate whose hulls together are under pirate_refit_below of their best: she goes home to refit. Server-only.';
  comment on function public.pirate_cruise_plan(uuid, uuid) is '0445: the cruise of a pirate lying at a harbour: stored lanes of her waters laid end to end, pirate_cruise_nm long; out to a haunt, back to her home. Server-only.';
  comment on function public.pirate_trader_step(uuid, timestamptz, jsonb) is '0445: the one ship of a run of the pirates'' job that may trade takes her step last. Server-only.';

  -- ── 4. THE HUNKS ──
  create temp table hunks_0445 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0445 values
  -- S2 + S1 + S3. the lie is minutes; then her next cruise from where she lies, unless she is hurt
  ('public.pirate_ship_step(uuid,timestamp with time zone)', 1,
$h$      if p_now < n.haunt_since + make_interval(hours => public.wc_int('pirate_haunt_hours')) then
        return 'HAUNT';
      end if;
    end if;
$h$,
$h$      if p_now < n.haunt_since + make_interval(secs => (coalesce(public.wc_num('pirate_port_minutes'), 0) * 60)::double precision) then   -- 0445: she lies pirate_port_minutes (was pirate_haunt_hours, twelve real hours: the owner, "pirates still in port. too much")
        return 'HAUNT';
      end if;
    end if;
    -- 0445: SHE CRUISES ON. On duty and not hurt, her next cruise begins where she lies (public.pirate_cruise_plan: stored lanes of her waters laid end
    -- to end, ending at her home). Hurt (public.pirate_hurt), off duty, or with no stored lane from here: she sails the one course straight home, below, as before.
    if v_duty and not public.pirate_hurt(p_fleet) then
      select * into h from public.pirate_cruise_plan(p_fleet, f.port_id);
      if h.port_id is not null then
        perform public.pirate_trade(p_fleet, nullif(h.port_id, f.port_id), p_now);
        return public.pirate_sail(p_fleet, f.port_id, h.segments, h.port_id, h.sea_id, h.port_id, 'CRUISE', p_now);
      end if;
    end if;
$h$),
  ('public.pirate_ship_step(uuid,timestamp with time zone)', 2,
$h$  select * into h from public.pirate_haunt_of(n.home_port, n.ord);
$h$,
$h$  select * into h from public.pirate_cruise_plan(p_fleet, f.port_id);   -- 0445: a cruise of stored lanes out to a haunt, pirate_cruise_nm long (was one course to public.pirate_haunt_of's harbour)
$h$),
  ('public.pirate_ship_step(uuid,timestamp with time zone)', 3,
$h$  return public.pirate_sail(p_fleet, f.port_id, voyage.segments_from_course(h.course), h.port_id, h.sea_id, h.port_id, 'CRUISE', p_now);
$h$,
$h$  return public.pirate_sail(p_fleet, f.port_id, h.segments, h.port_id, h.sea_id, h.port_id, 'CRUISE', p_now);   -- 0445: the segments of the whole cruise
$h$),
  -- S4. she raids from the sea
  ('public.pirate_strike(uuid,timestamp with time zone)', 1,
$h$c.fleet_id = p_fleet and f.busy_until is null) then
$h$,
$h$c.fleet_id = p_fleet and f.busy_until is null
                    and (f.status = 'SAILING' or public.wc('pirate_strike_from_port') = 'true'::jsonb)) then   -- 0445: only a pirate under sail strikes: the raid opens where they meet, not from a quay
$h$),
  ('public.pirate_strikes(timestamp with time zone)', 1,
$h$                where f.busy_until is null
$h$,
$h$                where f.busy_until is null
                  and (f.status = 'SAILING' or public.wc('pirate_strike_from_port') = 'true'::jsonb)   -- 0445: only a pirate under sail is asked
$h$),
  -- S5. one ship a run may trade, and she steps last
  ('public.pirate_trade(uuid,uuid,timestamp with time zone)', 1,
$h$  if public.wc('pirates_trade') is distinct from 'true'::jsonb or not public.city_treasury_on() then
$h$,
$h$  if public.wc('pirates_trade') is distinct from 'true'::jsonb or not public.city_treasury_on()
     or current_setting('byeharu.pirate_trade_hold', true) = 'on' then   -- 0445: held back by public.tick_pirates: one ship a run may trade, and she steps last (public.pirate_trader_step)
$h$),
  ('public.tick_pirates(timestamp with time zone)', 1,
$h$  v_paid  bigint := 0;
begin
$h$,
$h$  v_paid  bigint := 0;
  v_trader uuid;   -- 0445: the one ship of this run that may trade; she steps last
  v_sails  int := coalesce(public.wc_int('pirate_sails_per_run'), 1000000);   -- 0445
  v_trades boolean := public.wc('pirates_trade') = 'true'::jsonb and public.city_treasury_on();   -- 0445: public.pirate_trade's own switch: off, no ship is put aside
begin
  perform set_config('byeharu.pirate_trade_hold', 'on', true);   -- 0445: no ship of the loop below trades (public.pirate_trade); public.pirate_trader_step lets it go
$h$),
  ('public.tick_pirates(timestamp with time zone)', 2,
$h$    exit when v_n >= v_max or current_setting('byeharu.pirate_traded', true) = 'on';   -- 0415: a ship that traded holds the market rows and the purse of her harbour until this run commits, so the run steps no more ships after her (the rest go next minute; the order turns)
    v_n := v_n + 1;
$h$,
$h$    exit when v_n >= v_max or coalesce((v_steps ->> 'SAILED')::int, 0) >= v_sails;   -- 0445: at most pirate_sails_per_run leave a harbour a run. No ship of this loop trades (0415's stop at the first trade left one sailing a minute, and no strike that minute)
    if v_trades and v_trader is null then
      v_trader := r.fleet_id;   -- 0445: the first in the turning order is this run's trader: she is put aside and steps last (public.pirate_trader_step), so nothing runs behind her trade's locks
      continue;
    end if;
    v_n := v_n + 1;
$h$),
  ('public.tick_pirates(timestamp with time zone)', 3,
$h$jsonb_build_object('joined', public.battle_npc_joins(p_now)) else '{}'::jsonb end;
end
$h$,
$h$jsonb_build_object('joined', public.battle_npc_joins(p_now)) else '{}'::jsonb end
         -- 0445: LAST, the one ship of this run that may trade takes her step (its `steps` replaces the one above, with her answer counted)
         || public.pirate_trader_step(v_trader, p_now, v_steps);
end
$h$),
  -- S6. the join's sieve places a cruising pirate where she is (her voyage is a chain of lanes, not a line between two harbours)
  ('public.battle_join_near(uuid,text,timestamp with time zone)', 1,
$h$              from (select f.id, voyage.gc_distance_nm(v_lat, v_lon, (a.lat + (z.lat - a.lat) * w.k)::float8, (a.lon + (z.lon - a.lon) * w.k)::float8)::numeric as nm
$h$,
$h$              from (select f.id, case when p_kind = 'PIRATE'   -- 0445: a pirate's cruise is a chain of lanes (it may end where it began), so she is placed where she IS (voyage.fleet_point), not between her voyage's two harbours
                                      then (select voyage.gc_distance_nm(v_lat, v_lon, pt.lat::float8, pt.lon::float8)::numeric from voyage.fleet_point(f.id, p_now) pt)
                                      else voyage.gc_distance_nm(v_lat, v_lon, (a.lat + (z.lat - a.lat) * w.k)::float8, (a.lon + (z.lon - a.lon) * w.k)::float8)::numeric end as nm
$h$);

  for v_h in select h.fn from hunks_0445 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    declare
      x record;
    begin
      for x in select * from hunks_0445 h where h.fn = v_h.fn order by h.ord loop
        v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
        if v_n <> 1 then
          raise exception '0445 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
        end if;
        v_def := replace(v_def, x.old, x.new);
      end loop;
      execute v_def;
      v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
      for x in select * from hunks_0445 h where h.fn = v_h.fn order by h.ord desc loop
        v_n := (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new);
        if v_n <> 1 then
          raise exception '0445 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
        end if;
        v_def := replace(v_def, x.new, x.old);
      end loop;
      if v_def <> v_pre then
        raise exception '0445 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
      end if;
    end;
  end loop;

  -- ── 5. THE SELF-ASSERT: the catalog ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked) x))
         and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_new) x))) <> v_fn_before then
    raise exception '0445 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_hunked) x))) <> v_meta then
    raise exception '0445 self-assert FAIL: the grants, volatility, definer, search path or owner of a re-cut function moved';
  end if;
  if (select count(*) from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_new) x))
        and p.prosecdef and p.proconfig is not null and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')) <> 3
     or (select count(*) from pg_proc p where p.oid in ('public.pirate_cruise_plan(uuid,uuid)'::regprocedure, 'public.pirate_hurt(uuid)'::regprocedure) and p.provolatile = 's') <> 2 then
    raise exception '0445 self-assert FAIL: the new functions are not definer, with their search path and server-only, or the two readers are not stable';
  end if;
  if (select count(*) from public.world_config w where w.key = any (c_keys)) <> 6 then
    raise exception '0445 self-assert FAIL: the six knobs are not all here';
  end if;

  -- ── 6. THE NEWS (0347's law) ──
  perform public.news_update('0445', 'Pirates cruise the sea and raid from it', '해적은 바다를 순항하며 바다에서 습격한다');

  -- ── 7. THE PROBE, rolled back by a raised sentinel. On any world: a world with no pirate ship (the CI world) has the pirates lit and ONE roster
  --   fleet built here; a world with pirates (prod) lends one lying in a harbour. Knobs are read into variables first, never through a wc_* in a
  --   WHERE of this block.
  v_min := (select (w.value #>> '{}')::numeric from public.world_config w where w.key = 'pirate_cruise_nm');
  v_cap := (select (w.value #>> '{}')::int from public.world_config w where w.key = 'pirate_cruise_courses');
  v_port := (select (w.value #>> '{}')::numeric from public.world_config w where w.key = 'pirate_port_minutes');
  v_bits := (select jsonb_object_agg(w.key, w.value) from public.world_config w where w.key in ('pirates_bite', 'pirates_trade', 'attack_reach_nm'));
  begin
    update public.world_config set value = 'true'::jsonb where key in ('pirates_bite', 'city_treasury_enabled') and value is distinct from 'true'::jsonb;
    update public.world_config set value = 'false'::jsonb where key = 'pirates_trade' and value is distinct from 'false'::jsonb;
    update public.world_config set value = to_jsonb(-1) where key = 'attack_reach_nm';   -- nobody is in reach: the probe opens no battle
    if not public.pirates_on() then
      raise exception '0445 self-assert FAIL: the pirates could not be lit in this world';
    end if;
    -- a pirate of this world lying free in a harbour, whose home has a haunt (prod); the lowest ord first
    select n.fleet_id, n.home_port, n.ord into v_pf, v_home, v_ord
      from public.pirate_ships n join public.fleets f on f.id = n.fleet_id
     where n.laid_up_at is null and n.unpaid_since is null and n.wrecked_at is null and f.status = 'DOCKED' and f.busy_until is null
       and public.pirate_ord_wanted(n.ord)
       and exists (select 1 from public.ships s where s.fleet_id = n.fleet_id and s.durability > 0)
       and exists (select 1 from public.pirate_haunt_of(n.home_port, n.ord))
     order by n.ord limit 1;
    if v_pf is null then
      -- none (the CI world): the hoard is filled and one roster fleet is built at her hub, by the Brethren's own hand
      if exists (select 1 from public.pirate_ships) then
        raise exception '0445 self-assert FAIL: this world has pirate ships and none lies free in a harbour with a haunt in reach';
      end if;
      insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
      update public.port_treasury set ducats = 5000000, reserve = 0;
      update public.port_treasury t set ducats = 2000000000 where t.port_id = public.pirate_capital();
      select q.ord, q.hub_port into v_ord, v_hub
        from public.pirate_roster q
       where exists (select 1 from public.pirate_haunt_of(q.hub_port, q.ord)) and public.refit_yard(q.hub_port) is not null
       order by q.ord limit 1;
      if v_ord is null then
        raise exception '0445 self-assert FAIL: no roster fleet of this world has a haunt and a yard';
      end if;
      v_pf := public.pirate_commission_fleet(v_ord, public.refit_yard(v_hub), v_now);
      if v_pf is null then
        raise exception '0445 self-assert FAIL: the probe''s roster fleet (ord %) was not built', v_ord;
      end if;
      select n.home_port into v_home from public.pirate_ships n where n.fleet_id = v_pf;
      v_built := true;
    end if;
    -- she lies at her home, whole, manned, paid, in no sea
    update public.fleets f set status = 'DOCKED', port_id = v_home, ready_at = null, busy_until = null, lat = null, lon = null where f.id = v_pf;
    update public.ships s set durability = (select b.durability from public.ship_base(s.id) b), crew = (select b.crew_max from public.ship_base(s.id) b) where s.fleet_id = v_pf;
    update public.pirate_ships x set mission = 'HOME', sea_id = null, haunt_port = null, haunt_since = null, last_port = v_home where x.fleet_id = v_pf;
    if public.pirate_hurt(v_pf) or not public.pirate_ord_wanted(v_ord) then
      raise exception '0445 self-assert FAIL: the probe''s pirate, mended, is hurt, or her ord % is not wanted', v_ord;
    end if;

    -- (a) THE OUT CRUISE: stored lanes laid end to end, long, ending at a haunt, in a sea; she SAILS it
    select * into v_p from public.pirate_cruise_plan(v_pf, v_home);
    if v_p.port_id is null or v_p.sea_id is null or v_p.courses < 1 or v_p.courses > v_cap
       or not ((v_p.nm >= v_min and v_p.port_id <> v_home) or v_p.courses = v_cap)
       or jsonb_array_length(v_p.segments) < v_p.courses
       or abs((select sum((e ->> 'nm')::numeric) from jsonb_array_elements(v_p.segments) e) - v_p.nm) > 0.01 * v_p.nm + 1 then
      raise exception '0445 self-assert FAIL: the out cruise is not a long chain of stored lanes ending at a haunt: % nm, % lanes, % segments, ends at home %',
        v_p.nm, v_p.courses, jsonb_array_length(v_p.segments), v_p.port_id = v_home;
    end if;
    v_r := public.pirate_ship_step(v_pf, v_now);
    select o.dest_port_id, o.total_nm, o.origin_port_id into v_v from public.voyages o where o.fleet_id = v_pf and o.status = 'SAILING';
    if v_r <> 'SAILED' or (select f.status from public.fleets f where f.id = v_pf) <> 'SAILING' or v_v.dest_port_id is distinct from v_p.port_id
       or v_v.origin_port_id is distinct from v_home or abs(v_v.total_nm - v_p.nm) > 0.01 * v_p.nm + 1
       or not exists (select 1 from public.pirate_ships x where x.fleet_id = v_pf and x.mission = 'CRUISE' and x.sea_id = v_p.sea_id and x.haunt_port = v_p.port_id)
       or not exists (select 1 from public.pirate_ships_cruising c where c.fleet_id = v_pf) then
      raise exception '0445 self-assert FAIL: at her home she answered % and did not sail the out cruise (% nm to sail, % planned)', v_r, v_v.total_nm, v_p.nm;
    end if;
    v_note := format('ord %s out %s nm in %s lanes%s', v_ord, round(v_p.nm), v_p.courses, case when v_p.port_id <> v_home then ' to a haunt' else ' (the most lanes a cruise has)' end);

    -- (b) SHE RAIDS FROM THE SEA: under sail she is asked (nobody is in reach here: NO_TARGET); lying in a harbour she is not; with the knob she is
    if public.attack_on() then
      v_r := public.pirate_strike(v_pf, v_now);
      if v_r <> 'NO_TARGET' then
        raise exception '0445 self-assert FAIL: under sail, with nobody in reach, she answered % (not NO_TARGET)', v_r;
      end if;
    end if;
    -- she lies at the first haunt of her home (public.pirate_haunt_of), come in from a cruise that ended there
    select h.port_id, h.sea_id into v_haunt, v_hsea from public.pirate_haunt_of(v_home, v_ord) h;
    update public.voyages o set status = 'ABORTED' where o.fleet_id = v_pf and o.status = 'SAILING';
    update public.fleets f set status = 'DOCKED', port_id = v_haunt, ready_at = null, lat = null, lon = null where f.id = v_pf;
    update public.pirate_ships x set sea_id = v_hsea, haunt_port = v_haunt, haunt_since = null, mission = 'CRUISE', last_port = v_home where x.fleet_id = v_pf;
    if public.attack_on() and v_hsea is not null then
      v_r := public.pirate_strike(v_pf, v_now);
      if v_r <> 'NOT_HUNTING' then
        raise exception '0445 self-assert FAIL: lying in a harbour she answered % (not NOT_HUNTING): a pirate must raid from the sea', v_r;
      end if;
      update public.world_config set value = 'true'::jsonb where key = 'pirate_strike_from_port';
      v_r := public.pirate_strike(v_pf, v_now);
      update public.world_config set value = 'false'::jsonb where key = 'pirate_strike_from_port';
      if v_r <> 'NO_TARGET' then
        raise exception '0445 self-assert FAIL: with pirate_strike_from_port she answered % in a harbour (not NO_TARGET)', v_r;
      end if;
    end if;

    -- (c) PORT TIME IS SHORT: she lies pirate_port_minutes, then SAILS the cruise back, which ends at her home
    v_r := public.pirate_ship_step(v_pf, v_now);
    if v_r <> 'HAUNT' or (select x.haunt_since from public.pirate_ships x where x.fleet_id = v_pf) is distinct from v_now then
      raise exception '0445 self-assert FAIL: come in from her cruise she answered % (not HAUNT)', v_r;
    end if;
    v_r := public.pirate_ship_step(v_pf, v_now + make_interval(secs => (v_port * 60 - 1)::double precision));
    if v_r <> 'HAUNT' then
      raise exception '0445 self-assert FAIL: inside pirate_port_minutes she answered % (not HAUNT)', v_r;
    end if;
    select * into v_b from public.pirate_cruise_plan(v_pf, v_haunt);
    v_r := public.pirate_ship_step(v_pf, v_now + make_interval(secs => (v_port * 60)::double precision));
    select o.dest_port_id, o.total_nm, o.origin_port_id into v_v from public.voyages o where o.fleet_id = v_pf and o.status = 'SAILING';
    if v_r <> 'SAILED' or v_b.port_id is null or not ((v_b.nm >= v_min and v_b.port_id = v_home) or v_b.courses = v_cap)
       or v_v.dest_port_id is distinct from v_b.port_id or abs(v_v.total_nm - v_b.nm) > 0.01 * v_b.nm + 1
       or not exists (select 1 from public.pirate_ships x where x.fleet_id = v_pf and x.mission = 'CRUISE' and x.last_port = v_haunt) then
      raise exception '0445 self-assert FAIL: after % minutes at her haunt she answered % and did not sail the cruise back (% nm, % lanes, ends at home %)',
        v_port, v_r, v_b.nm, v_b.courses, v_b.port_id = v_home;
    end if;
    v_note := v_note || format(', lay %s min at her haunt, back %s nm in %s lanes%s', v_port, round(v_b.nm), v_b.courses, case when v_b.port_id = v_home then ' to her home' else ' (the most lanes a cruise has)' end);

    -- (d) HURT, SHE GOES HOME TO REFIT: one stored course straight home, in no sea
    update public.voyages o set status = 'ABORTED' where o.fleet_id = v_pf and o.status = 'SAILING';
    update public.fleets f set status = 'DOCKED', port_id = v_haunt, ready_at = null, lat = null, lon = null where f.id = v_pf;
    update public.pirate_ships x set sea_id = v_hsea, haunt_port = v_haunt, haunt_since = v_now - interval '1 day', mission = 'CRUISE' where x.fleet_id = v_pf;
    update public.ships s set durability = greatest(1, floor(0.2 * (select b.durability from public.ship_base(s.id) b))) where s.fleet_id = v_pf;
    if not public.pirate_hurt(v_pf) then
      raise exception '0445 self-assert FAIL: with her hulls at a fifth she is not hurt';
    end if;
    v_r := public.pirate_ship_step(v_pf, v_now);
    select o.dest_port_id, o.total_nm, o.origin_port_id into v_v from public.voyages o where o.fleet_id = v_pf and o.status = 'SAILING';
    if v_r <> 'SAILED' or v_v.dest_port_id is distinct from v_home
       or abs(v_v.total_nm - (select c.nm from public.npc_courses c where c.from_port = v_haunt and c.to_port = v_home)) > 1
       or not exists (select 1 from public.pirate_ships x where x.fleet_id = v_pf and x.mission = 'HOME' and x.sea_id is null) then
      raise exception '0445 self-assert FAIL: hurt at her haunt she answered % and did not sail the one course straight home in no sea (% nm)', v_r, v_v.total_nm;
    end if;
    v_note := v_note || format('; hurt, straight home %s nm', round(v_v.total_nm));

    -- (e) ONE SHIP A RUN MAY TRADE: held back, a ship trades nothing; the trader's step lets the hold go
    update public.world_config set value = 'true'::jsonb where key = 'pirates_trade';
    update public.voyages o set status = 'ABORTED' where o.fleet_id = v_pf and o.status = 'SAILING';
    update public.fleets f set status = 'DOCKED', port_id = v_home, ready_at = null, lat = null, lon = null where f.id = v_pf;
    perform set_config('byeharu.pirate_trade_hold', 'on', true);
    if public.pirate_trade(v_pf, null, v_now) is not null then
      raise exception '0445 self-assert FAIL: a ship held back from trading was let to the doors';
    end if;
    if public.pirate_trader_step(null, v_now, '{"SAILED": 2}'::jsonb) <> '{"steps": {"SAILED": 2}}'::jsonb
       or coalesce(current_setting('byeharu.pirate_trade_hold', true), '') <> '' then
      raise exception '0445 self-assert FAIL: the trader''s step did not let the hold go, or did not hand the steps back';
    end if;
    if public.pirate_trade(v_pf, null, v_now) is null then
      raise exception '0445 self-assert FAIL: with the hold gone a pirate lying in a harbour is still kept from the doors';
    end if;
    raise exception sqlstate 'BV445' using message = v_note || case when v_built then ' (a roster fleet built for the probe)' else ' (a pirate of this world)' end;
  exception when sqlstate 'BV445' then
    get stacked diagnostics v_note = message_text;
  end;
  if (select jsonb_object_agg(w.key, w.value) from public.world_config w where w.key in ('pirates_bite', 'pirates_trade', 'attack_reach_nm')) is distinct from v_bits
     or (v_built and exists (select 1 from public.pirate_ships x where x.fleet_id = v_pf))
     or exists (select 1 from public.voyages o where o.fleet_id = v_pf and o.departed_at = v_now) then
    raise exception '0445 self-assert FAIL: the probe was not rolled back';
  end if;
  perform set_config('byeharu.pirate_trade_hold', '', true);
  if clock_timestamp() - v_t0 > interval '20 seconds' then
    raise exception '0445 self-assert FAIL: the file took % (budget 20 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0445 self-assert ok: PIRATES CRUISE THE SEA. % hunks once each and reversing; grants and volatility unmoved; no other function moved; three new functions server-only. Probe: %. % ms.',
    (select count(*) from hunks_0445), v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0445;
end $m$;
