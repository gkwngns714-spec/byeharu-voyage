-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0425 - MORE SHIPS AT SEA, 2  (a navy ship's lie written under the old six-hour knob ends now, not hours from now; a cargo ship carries a
--        quarter of a load, so the same funds go out on four times as many ships)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-15: "why are there still ships that are laid up, or in port this much? make it so that it fixes and have as much as ships
-- available at sea possible." (row 344; 0423 was the first half.)
--
-- WHY (prod, read-only, 2026-11-14 20:03 UTC, head 0423, 41 minutes after 0423; docs/dev-log/2026-11-15-at-sea-2.md;
--      scripts/ops/harness/at-sea-2/measure.sql):
--   NAVY 43: at sea 10, LYING 30 (mission HUNT, hunt_until ahead), elsewhere 3. EVERY ONE of the 30 lies has more left than navy_hunt_hours
--     (0.0625 h, 225 s) allows: median 218 minutes left, the longest 338; 12 at their own station, 18 at another sea's harbour. 0423 moved the
--     knob, not the rows: public.navy_hunt_step keeps a ship in port while hunt_until is ahead, and every hunt_until was written under the old
--     six-hour knob (her lie at her station, now + 6 h; a far hunt, her arrival + 6 h). 0423's own-sea patrol (its hunk 8) is reached only
--     when a lie ENDS, so those ships would lie on to their old deadlines, the last ~01:40 UTC. A ship bound for a hunt when 0423 landed carries
--     the same stale deadline in her row and would lie six hours on arrival.
--   CARGO SHIPS 372 (361 in service): at sea 70 (37 with funds, 13.29 M aboard; 33 sailing home empty), idle at home 289, laid up 11.
--     Their cities' need now 18.23 M (85 cities); aboard 13.29 M; need less aboard 5.41 M, and 4.29 M of that is Joseon's, whose idle ships'
--     homes may give 51,598 this run (its donors are poor: 0307's share). Every other realm's need less aboard is at most 0.33 M. One run
--     could send 7 ships. So the 289 are idle because there is honestly little left to carry: the need is already aboard 37 ships (0423's
--     10 loads a run and 1 M a ship did that). The one lever inside the rules is the size of a load: the same need on smaller loads is more
--     ships under sail, each sailing her whole circuit.
--
-- WHAT THIS FILE DOES:
--   N3. A LIE IS NEVER LONGER THAN THE KNOB SAYS NOW (one hunk in public.navy_hunt_step): lying at her hunt harbour, a hunt_until more than
--       navy_hunt_hours from now is cut to now + navy_hunt_hours; at her OWN station with navy_own_sea_patrol on, the lie ends now and she
--       picks again (her own sea: her patrol under sail, 0423; another: she sails for it). A lie written under the live knob is never shortened
--       (her arrival + 225 s is not more than now + 225 s). Healing, not a one-off: whatever the knob is moved to, a longer old lie follows it.
--       Every lying ship is stepped each minute (tick_navy, navy_steps_per_run 40, 43 ships), so the 30 are cut within a minute or two.
--   C2. A LOAD IS A QUARTER (knobs): convoy_load_max 1,000,000 -> 250,000 and convoy_loads_per_run 10 -> 20. As the 37 loaded ships deliver,
--       their realms' need is loaded again hourly in 250,000 shares on up to 20 ships a capital a run. Nothing else about a load moves (the same
--       public.cargo_ships_load, room once a run a home, money only through public.convoy_book).
--
-- NOT DONE (in the dev-log as proposals for the owner): a cargo ship with nothing to carry sails her circuit in ballast; a poor realm's
--   cities aided from a richer realm's purse; navy_hunt_per_day (the owner's, 0), navy upkeep and money are unmoved; nothing is minted.
-- LOAD: navy +~20 at sea (patrol legs at 0422's speed): ~+50 rows a minute; cargo +~25 to 35 at sea, more DELIVERED rows as four ships share
--   what one carried: ~+25 rows a minute. About +75 rows a minute, ~+1 s of work a minute; no job is added or rescheduled, no table is made.
-- LOCKS: CREATE OR REPLACE x1 by a hunk; two knobs. TIME: milliseconds; the probe steps one navy ship four times, rolled back: under 5 s.
--   BUDGET: statement_timeout 30 s, lock_timeout 5 s; fails above 20 s.
-- ROLLBACK (forward, owner only): scripts/ops/harness/at-sea-2/rollback-0425.sql (a draft). With no file: convoy_load_max 1000000,
--   convoy_loads_per_run 10 (the hunk stays harmless: it only ever shortens a lie to the knob's own length).
-- SELF-ASSERT: the hunk once and reversing; grants, volatility, definer, search path, owner unmoved; no other function moved; then the probe.
-- VERSION: 0425 = 0424 (starter gear, #699, live) + 1. 0424 touches neither this body nor these knobs.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_fn        constant text := 'public.navy_hunt_step(uuid,uuid,uuid,boolean,timestamp with time zone)';
  v_t0        timestamptz := clock_timestamp();
  v_pre       text;
  v_meta      text;
  v_old       text;
  v_new       text;
  v_def       text;
  v_n         int;
  v_fn_before text;
  v_kept      text := '';
  v_fleet     uuid;
  v_port      uuid;
  v_other     uuid;
  v_t         timestamptz := now();
  v_s         text;
  v_u         timestamptz;
  v_note      text := 'no docked navy ship in this world to probe: proof 126 steps one';
begin
  perform set_config('statement_timeout', '30s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure(c_fn) is null or not exists (select 1 from public.world_config where key = 'navy_own_sea_patrol')
     or not exists (select 1 from public.world_config where key = 'convoy_load_max') or to_regprocedure('public.news_update(text,text,text)') is null then
    raise exception '0425 refuses: the hunt (0340), 0423''s knobs or the news are not all in this world';
  end if;
  if position('-- 0425:' in pg_get_functiondef(c_fn::regprocedure)) > 0 then
    raise exception '0425 refuses: it has been applied once';
  end if;

  -- ── 1. THE PRE-IMAGE ──
  v_pre := replace(pg_get_functiondef(c_fn::regprocedure), E'\r', '');
  select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
    into v_meta from pg_proc p where p.oid = c_fn::regprocedure;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> c_fn::regprocedure;

  -- ── 2. THE KNOBS. Each moves only from the value this file was written against (prod's at 20:03 UTC 2026-11-14).
  update public.world_config set value = to_jsonb(250000),
         description = description || ' 0425: 1,000,000 -> 250,000 (the same need on four times as many ships; 13.3 M was aboard 37 ships).'
   where key = 'convoy_load_max' and value = to_jsonb(1000000);
  if not found then v_kept := v_kept || 'convoy_load_max '; end if;
  update public.world_config set value = to_jsonb(20),
         description = description || ' 0425: 10 -> 20 (with a quarter load a ship, a capital still sends its need in one run).'
   where key = 'convoy_loads_per_run' and value = to_jsonb(10);
  if not found then v_kept := v_kept || 'convoy_loads_per_run '; end if;

  -- ── 3. THE HUNK ──
  v_old :=
$h$  if n.mission = 'HUNT' and n.hunt_port = p_port then
    if n.hunt_until is not null and n.hunt_until > p_now then
      return 'HUNTING';
$h$;
  v_new :=
$h$  if n.mission = 'HUNT' and n.hunt_port = p_port then
    -- 0425: A LIE IS NEVER LONGER THAN THE KNOB SAYS NOW. One written under an older, longer navy_hunt_hours (0423 moved 6 h to 225 s and left
    -- the rows) is cut to now + navy_hunt_hours; at her own station with navy_own_sea_patrol on it ends now, and she picks again below (her own
    -- sea: her patrol, under sail). A lie written under the live knob is never shortened.
    if n.hunt_until is not null and n.hunt_until > p_now
       and ((p_port = p_home and public.wc('navy_own_sea_patrol') = 'true'::jsonb)
            or n.hunt_until > p_now + make_interval(secs => (v_hours * 3600)::double precision)) then
      n.hunt_until := case when p_port = p_home and public.wc('navy_own_sea_patrol') = 'true'::jsonb then p_now
                           else p_now + make_interval(secs => (v_hours * 3600)::double precision) end;
      update public.navy_ships x set hunt_until = n.hunt_until where x.fleet_id = p_fleet;
    end if;
    if n.hunt_until is not null and n.hunt_until > p_now then
      return 'HUNTING';
$h$;
  v_n := (length(v_pre) - length(replace(v_pre, v_old, ''))) / length(v_old);
  if v_n <> 1 then
    raise exception '0425 self-assert FAIL: the hunk occurs % time(s) in %, not once: the deployed body is not what this file was written against', v_n, c_fn;
  end if;
  execute replace(v_pre, v_old, v_new);
  v_def := replace(pg_get_functiondef(c_fn::regprocedure), E'\r', '');
  if (length(v_def) - length(replace(v_def, v_new, ''))) / length(v_new) <> 1 then
    raise exception '0425 self-assert FAIL: the hunk is not in the new body once';
  end if;
  if replace(v_def, v_new, v_old) <> v_pre then
    raise exception '0425 self-assert FAIL: % does not reverse to its pre-image', c_fn;
  end if;
  if (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
        from pg_proc p where p.oid = c_fn::regprocedure) <> v_meta then
    raise exception '0425 self-assert FAIL: the grants, volatility, definer, search path or owner of % moved', c_fn;
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> c_fn::regprocedure) <> v_fn_before then
    raise exception '0425 self-assert FAIL: another function moved';
  end if;

  -- ── 4. THE NEWS (0347's law) ──
  perform public.news_update('0425', 'The navy leaves port; cargo ships carry smaller loads on more ships',
                             '해군이 항구를 떠나고, 화물선은 더 많은 배에 나눠 싣는다');

  -- ── 5. THE PROBE, rolled back by a raised sentinel: ONE docked navy ship (her row only), the hunt step alone (no voyage is written):
  --   (a) at another harbour with a six-hour lie: HUNTING, her lie cut to navy_hunt_hours from now;
  --   (b) the same with a lie of 100 s (under the knob): HUNTING, the lie unmoved;
  --   (c) at her own station with a five-hour lie and navy_own_sea_patrol off: HUNTING, the lie unmoved (0340's lie, as written).
  select x.fleet_id, f.port_id into v_fleet, v_port
    from public.navy_ships x join public.fleets f on f.id = x.fleet_id
   where f.status = 'DOCKED' and f.port_id is not null
   order by x.nation_id, x.ord limit 1;
  if v_fleet is not null then
    select p.id into v_other from public.ports p where p.kind = 'HARBOUR' and p.id <> v_port order by p.code limit 1;
    begin
      update public.world_config set value = 'true'::jsonb where key in ('navy_enabled', 'pirates_bite', 'city_treasury_enabled') and value is distinct from 'true'::jsonb;
      if not public.navy_hunts_on() then
        v_note := 'the hunt cannot be lit in this world: proof 126 steps one';
        raise exception sqlstate 'BV425';
      end if;
      update public.navy_ships x set mission = 'HUNT', hunt_port = v_port, hunt_until = v_t + interval '6 hours' where x.fleet_id = v_fleet;
      v_s := public.navy_hunt_step(v_fleet, v_port, v_other, true, v_t);
      v_u := (select x.hunt_until from public.navy_ships x where x.fleet_id = v_fleet);
      if v_s is distinct from 'HUNTING' or v_u <> v_t + make_interval(secs => (public.wc_num('navy_hunt_hours') * 3600)::double precision) then
        raise exception '0425 self-assert FAIL: a six-hour lie away from home: % until % (wanted HUNTING until now + % h)', v_s, v_u, public.wc_num('navy_hunt_hours');
      end if;
      update public.navy_ships x set hunt_until = v_t + interval '100 seconds' where x.fleet_id = v_fleet;
      v_s := public.navy_hunt_step(v_fleet, v_port, v_other, true, v_t);
      if v_s is distinct from 'HUNTING' or (select x.hunt_until from public.navy_ships x where x.fleet_id = v_fleet) <> v_t + interval '100 seconds' then
        raise exception '0425 self-assert FAIL: a lie under the knob was moved: %', v_s;
      end if;
      update public.world_config set value = 'false'::jsonb where key = 'navy_own_sea_patrol';
      update public.navy_ships x set hunt_until = v_t + interval '5 hours' where x.fleet_id = v_fleet;
      update public.world_config set value = to_jsonb(6) where key = 'navy_hunt_hours';
      v_s := public.navy_hunt_step(v_fleet, v_port, v_port, true, v_t);
      if v_s is distinct from 'HUNTING' or (select x.hunt_until from public.navy_ships x where x.fleet_id = v_fleet) <> v_t + interval '5 hours' then
        raise exception '0425 self-assert FAIL: the old rule (six hours, her own-sea lie) did not stand as written: %', v_s;
      end if;
      v_note := 'one navy ship: a six-hour lie cut to the knob, a lie under it kept, the old rule as written';
      raise exception sqlstate 'BV425';
    exception when sqlstate 'BV425' then null;
    end;
    if v_note not like 'one navy ship%' and v_note not like 'the hunt cannot%' then
      raise exception '0425 self-assert FAIL: the navy probe did not run to its end';
    end if;
  end if;
  if public.wc('navy_own_sea_patrol') <> 'true'::jsonb or public.wc_num('navy_hunt_hours') = 6
     or (v_kept = '' and (public.wc_int('convoy_load_max') <> 250000 or public.wc_int('convoy_loads_per_run') <> 20)) then
    raise exception '0425 self-assert FAIL: the knobs are not this file''s (or the probe was not rolled back)';
  end if;
  if clock_timestamp() - v_t0 > interval '20 seconds' then
    raise exception '0425 self-assert FAIL: the file took % (budget 20 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0425 self-assert ok: MORE SHIPS AT SEA, 2. One hunk in public.navy_hunt_step, once and reversing; grants and volatility unmoved; no other function moved. Knobs: convoy_load_max %, convoy_loads_per_run %.% Probe: %; % ms.',
    public.wc_int('convoy_load_max'), public.wc_int('convoy_loads_per_run'),
    case when v_kept = '' then '' else ' Left at the owner''s value: ' || v_kept || '.' end, v_note,
    round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
