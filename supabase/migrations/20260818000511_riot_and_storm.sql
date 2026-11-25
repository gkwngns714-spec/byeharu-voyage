-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none (dark: nothing changes for a player until the owner lights happenings_bite)
-- 0511 - RIOT AND STORM  (dark: the owner's switch happenings_bite, false)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-25: "IF NO FOOD or WATER is given, crews may cause RIOT - causing dramatic decrease in crew numbers. IF crew numbers are below MIN, the ship
--   speed will decrease dramatically"; "if you meet a storm ... your crewmates will die ... lose your trade goods too (1~2% per happening)"; answer 2: "riot does not
--   cause losing all cargo, but some." docs/design/owner-spec-plan-2026-11-25.md 0.5; the deck's slide 11. SICKNESS, FIRE, LEAK and RATS are NOT approved: not here.
-- WHAT (lit; a player's voyage only, decided by default: the world's merchants, crown and pirate ships sail as they did, so no market moves):
--   THE TERMS ARE FROZEN AS SHE LEAVES, on her path's first segment (`hap`, voyage.freeze_happenings, read by voyage.depart): a voyage under way when the switch
--     turns, or when a figure is changed, is settled as she left, late or on time (the day's own rolls, voyage.rng).
--   RIOT    a settled sea-day that ends with a hull out of food or water, before port (the very test of 0279's ran-dry day, 0314's arrival kept): 15 % of the crew of
--           each hull die (rounded up, at least 1, never the last hand) and 5 % of each good is lost (some, never all: voyage.happening_takes); one RIOT row for the
--           day and she SAILS ON (no other hazard that day, as a ran-dry day rolled none). Three such days leave 61 % of the crew and 86 % of the cargo.
--   BROKEN  when her hands are under a quarter of her hulls' minimum: voyage.forced_home, as a ran-dry day does today (hulls hurt, the nearest city, its donation),
--           but WITH THE CARGO SHE STILL HOLDS: "all cargo lost" goes. The day's row is RIOT_HOME.
--   STORM   the STORM arm as it is, and: 2 to 5 % of the crew die (the day's magnitude; the surgeon saves his share; a fraction of a hand is the day's own roll) and
--           1 to 2 % of each good is lost.
--   SLOW    below the minimum crew a hull's speed is crew / minimum, never under 0.30 (today a flat 0.70): in voyage.ship_speed_parts (every quote and departure), and
--           for hands lost AT SEA, whose voyage's speed is frozen, as hours added to the day (24 x (1 / share - 1)) on the one row the day writes.
--   THE RECORD  cargo_lost {good: units}, cargo_lost_pct, cargo_lost_cost (what 0501's public.cargo_rate_for reads: her cargo at cost before less after), crew_lost,
--           and the voyage's insurance pays for what it covers (public.insurance_claim, 0213). voyage.report_line says " Cargo -n%." (1 hunk).
-- NOT TOUCHED: which day a hazard falls on, how often, the hull's loss, CALM, pirates, navy, any price or knob, a voyage already at sea.
-- voyage.arrival_at (what where_now draws while a late voyage waits for its settle) rolls storms and calms only, as it never counted a ran-dry day either.
-- ROWS: two world_config rows, two voyage_event_kinds rows. No table, index or cron. One voyage_events row a sea-day, as today: 0 new rows a minute.
-- budget: no table, no cron job, no autovacuum or fillfactor change. Tick: dark, one knob read a PLAYER's departure and nothing a settled day but a jsonb key on a
--   storm or dry day (0.02 ms); lit, a storm or riot day 2 ms (measured in proof 216); a merchant's departure and day: nothing.
-- LOCKS: CREATE FUNCTION x4; CREATE OR REPLACE x5 by hunks (voyage.settle, voyage.forced_home, voyage.depart, voyage.ship_speed_parts, voyage.report_line). A second.
-- WITH 0501 AND 0504 (before it in the chain): both cut other lines of voyage.settle and voyage.forced_home; every hunk here was applied on both.
-- ROLLBACK (forward, owner only): QUICK, happenings_bite false (voyages that left lit finish as they left). FULL: the hunks reversed, the functions dropped; the two
--   kinds stay (they are catalogue rows with history).
-- SELF-ASSERT: each hunk once and reversing; no other function or knob moved; server only; THE PROBE (rolled back; its own company, its own passage with no hazard,
--   planted hold): dark she is brought home with an empty hold as today; lit, a dry day takes 15 % and 5 %, she sails on, and comes home broken with what she holds.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_hunked constant text[] := array['voyage.settle(uuid,timestamp with time zone)', 'voyage.forced_home(uuid,integer,uuid)', 'voyage.depart(uuid,jsonb,uuid,uuid,timestamp with time zone)', 'voyage.ship_speed_parts(uuid)', 'voyage.report_line(integer,text,jsonb)']::text[];
  c_new    constant text[] := array['voyage.happenings_on()', 'voyage.freeze_happenings(jsonb,boolean)', 'voyage.happening_takes(uuid,integer,uuid,text,numeric,numeric)', 'voyage.crew_share(uuid,jsonb)']::text[];
  c_gone   constant text[] := array[]::text[];   -- dropped and made again with more to answer (the same arguments)
  v_t0        timestamptz := clock_timestamp();
  v_h         record;
  x           record;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_fn_before text;
  v_meta      text;
  v_cfg_before text;
  v_lived     boolean := false;
  v_note      text := '';
  v_me   uuid;
  v_fl   uuid;
  v_lis  uuid;
  v_good text;
  v_lit  boolean;
  v_voy  uuid;
  v_kind text;
  v_pay  jsonb;
begin
  perform set_config('statement_timeout', '90s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from unnest(c_new) u(q) where to_regprocedure(u.q) is not null and not (u.q = any (c_gone))) then
    raise exception '0511 refuses: it has been applied once';
  end if;
  if exists (select 1 from unnest(c_hunked || c_gone) u(q) where to_regprocedure(u.q) is null) then
    raise exception '0511 refuses: a function it cuts is not in this world: %', (select string_agg(u.q, ' ') from unnest(c_hunked || c_gone) u(q) where to_regprocedure(u.q) is null);
  end if;


  -- ── 1. THE PRE-IMAGES ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked || c_gone) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
    into v_cfg_before from public.world_config c;

  -- ── 2. THE RULES ──
  insert into public.world_config (key, value, description) values
    ('happenings_bite', 'false'::jsonb,
     '0511: THE SWITCH (the owner''s). true: a player''s voyage that departs from now on meets riot and storm (happenings_terms, frozen on her path): no food or water costs crew and some cargo a day, a storm kills some hands and loses some goods, below the minimum crew she is slow. false: as before 0511.'),
    ('happenings_terms', '{"riot_crew": 0.15, "riot_cargo": 0.05, "home_crew": 0.25, "storm_crew": [0.02, 0.05], "storm_cargo": [0.01, 0.02], "slow_floor": 0.30}'::jsonb,
     '0511: the figures (the owner''s, 2026-11-25): riot a day, crew and each good; home_crew: the share of the minimum crew under which the voyage ends; storm: least and most; slow_floor: the least speed below the minimum crew.');
  insert into public.voyage_event_kinds (code, ordinal, is_rolled, prose, note) values
    ('RIOT', (select max(k.ordinal) + 1 from public.voyage_event_kinds k), false, 'Riot: no food or water.',
     '0511. A CONDITION, never drawn: voyage.settle''s ran-dry day of a voyage that left with happenings_bite on. Its payload carries crew_lost, cargo_lost, cargo_lost_pct, cargo_lost_cost.'),
    ('RIOT_HOME', (select max(k.ordinal) + 2 from public.voyage_event_kinds k), false, 'Riot: crew broken, back to port.',
     '0511. A CONDITION, never drawn: the riot day that leaves her under home_crew of her minimum crew: voyage.forced_home with the cargo she still holds.');
  execute $f$
create function voyage.happenings_on()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0511: THE SWITCH, read once.
  select coalesce(public.wc('happenings_bite') = 'true'::jsonb, false)
$body$
  $f$;
  revoke all on function voyage.happenings_on() from public, anon, authenticated, service_role;
  comment on function voyage.happenings_on() is
    '0511: the owners switch happenings_bite. Server only.';
  execute $f$
create function voyage.freeze_happenings(p_segments jsonb, p_npc boolean)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0511: THE TERMS SHE LEAVES UNDER, on her path's first segment (`hap`). Dark, or not a player's: p_segments unchanged, byte for byte. Read by voyage.depart only.
  select case when coalesce(p_npc, true) then p_segments
              when not voyage.happenings_on() then p_segments
              else jsonb_set(p_segments, '{0,hap}', public.wc('happenings_terms'), true) end
$body$
  $f$;
  revoke all on function voyage.freeze_happenings(jsonb, boolean) from public, anon, authenticated, service_role;
  comment on function voyage.freeze_happenings(jsonb, boolean) is
    '0511: freezes the happenings terms on a players path as she leaves. Server only.';
  execute $f$
create function voyage.happening_takes(p_voyage uuid, p_day integer, p_fleet uuid, p_cause text, p_crew numeric, p_cargo numeric)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $body$
-- 0511: WHAT A RIOT OR A STORM TAKES, the one writer: p_crew of each hull's hands and p_cargo of each good aboard. RIOT: the hands rounded up (at least 1 a hull);
-- STORM: less the surgeon's share, a fraction of a hand by the day's own roll. NEVER THE LAST HAND of a hull, NEVER ALL of a good (its last unit stays). Goods leave
-- through public.fleet_unload, the one unload, and the voyage's insurance is asked (0213). Every roll is voyage.rng's (the voyage, the day, the stream): a voyage
-- settled late loses what it would have lost on time. Answers the day's keys; cargo_lost_cost is 0501's (her cargo at cost before less after).
declare
  s       record;
  r       record;
  v_lost  int;
  v_dead  int := 0;
  v_crew  int := 0;
  v_take  numeric;
  v_out   jsonb := '{}'::jsonb;
  v_cost  bigint := public.fleet_stock_at_cost(p_fleet);
  v_ins   jsonb;
  v_saved numeric := case when p_cause = 'STORM' then public.crew_pct(p_fleet, null, 'crew_saved') else 0 end;
begin
  for s in select sh.id, sh.crew from public.ships sh where sh.fleet_id = p_fleet and sh.crew > 0 order by sh.id loop
    v_crew := v_crew + s.crew;
    v_lost := case when p_cause = 'RIOT' then s.crew - floor(s.crew * (1 - p_crew))
                   else floor(s.crew * p_crew * (1 - v_saved) + voyage.rng(p_voyage, p_day, 'hap:' || s.id)) end;
    v_lost := greatest(0, least(v_lost, s.crew - 1));
    if v_lost > 0 then
      update public.ships set crew = crew - v_lost where id = s.id;
      v_dead := v_dead + v_lost;
    end if;
  end loop;
  for r in select e.key as code, sum((e.value)::text::numeric) as qty
             from public.ships sh cross join lateral jsonb_each(sh.cargo) e
            where sh.fleet_id = p_fleet and jsonb_typeof(e.value) = 'number'
            group by e.key having sum((e.value)::text::numeric) > 1
            order by e.key loop
    v_take := least(floor(r.qty * p_cargo + voyage.rng(p_voyage, p_day, 'hap:' || r.code)), ceil(r.qty) - 1);
    if v_take > 0 then
      v_out := v_out || jsonb_build_object(r.code, public.fleet_unload(p_fleet, r.code, v_take));
    end if;
  end loop;
  v_ins := public.insurance_claim(p_voyage, p_day, v_out, p_cause);
  return jsonb_build_object('crew_before', v_crew, 'crew_lost', v_dead)
         || case when v_saved > 0 then jsonb_build_object('surgeon_pct', round(v_saved * 100, 2)) else '{}'::jsonb end
         || case when v_out = '{}'::jsonb then '{}'::jsonb
                 else jsonb_build_object('cargo_lost', v_out, 'cargo_lost_pct', round(p_cargo * 100, 1), 'cargo_lost_cost', v_cost - public.fleet_stock_at_cost(p_fleet)) end
         || case when v_ins is null then '{}'::jsonb else jsonb_build_object('insurance', v_ins) end;
end
$body$
  $f$;
  revoke all on function voyage.happening_takes(uuid, integer, uuid, text, numeric, numeric) from public, anon, authenticated, service_role;
  comment on function voyage.happening_takes(uuid, integer, uuid, text, numeric, numeric) is
    '0511: what a riot or a storm takes of crew and cargo (some, never all). Server only.';
  execute $f$
create function voyage.crew_share(p_ship uuid, p_hap jsonb)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0511: A SHORT HULL'S SPEED SHARE: 1 at her minimum crew, else crew / minimum, never under slow_floor. p_hap: the terms (a voyage's own, or the world's).
  select case when s.crew >= c.crew_required or c.crew_required <= 0 then 1.0
              else greatest((p_hap ->> 'slow_floor')::numeric, s.crew::numeric / c.crew_required) end
    from public.ships s join public.ship_classes c on c.id = s.class_id where s.id = p_ship
$body$
  $f$;
  revoke all on function voyage.crew_share(uuid, jsonb) from public, anon, authenticated, service_role;
  comment on function voyage.crew_share(uuid, jsonb) is
    '0511: crew over minimum, never under the floor: a short hulls speed. Server only.';

  -- ── 3. THE HUNKS (each OLD text once in the live body; each reverses) ──
  create temp table hunks_0511 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0511 values
  ('voyage.settle(uuid,timestamp with time zone)', 1,
$h$  v_home    jsonb;     -- 0279: the ran-dry day's forced home (voyage.forced_home); null when she is not dry
$h$,
$h$  v_home    jsonb;     -- 0279: the ran-dry day's forced home (voyage.forced_home); null when she is not dry
  v_hap     jsonb;     -- 0511: the happenings' terms she left under (voyage.freeze_happenings); null dark and for every voyage but a player's
  v_riot    jsonb;     -- 0511: what the dry day's riot took; null when she left without them
  v_slow    numeric;   -- 0511: the speed share of her hands, when they are short at sea
$h$),
  ('voyage.settle(uuid,timestamp with time zone)', 2,
$h$      v_home := voyage.forced_home(v.id, d, p_fleet);
      if v_home is not null then
$h$,
$h$      -- 0511: A RIOT, when she left with the happenings' terms: she loses hands and some cargo and sails on; only with her hands under home_crew of her
      -- hulls' minimum is she brought home, with what she still holds. Without them, the ran-dry day as it was.
      v_hap := v.path->0->'hap';
      v_riot := case when v_hap is not null then voyage.happening_takes(v.id, d, p_fleet, 'RIOT', (v_hap->>'riot_crew')::numeric, (v_hap->>'riot_cargo')::numeric) end;
      v_home := case when v_hap is null
                       or (select sum(sh.crew) < (v_hap->>'home_crew')::numeric * sum(c.crew_required)
                             from public.ships sh join public.ship_classes c on c.id = sh.class_id where sh.fleet_id = p_fleet)
                     then voyage.forced_home(v.id, d, p_fleet) end;
      if v_hap is not null and v_home is null then
        v_slow := (select min(voyage.crew_share(sh.id, v_hap)) from public.ships sh where sh.fleet_id = p_fleet);
        v_delay := case when v_slow < 1 then round(24 * (1 / v_slow - 1), 2) else 0 end;
        insert into public.voyage_events (voyage_id, day_index, kind, payload, resolved_at)
        values (v.id, d, 'RIOT', jsonb_build_object('short_rations', v_short, 'wages', v_wages) || v_riot
                                 || case when v_delay > 0 then jsonb_build_object('delay_hours', v_delay, 'slow', round(v_slow, 2)) else '{}'::jsonb end, v_bound)
        on conflict (voyage_id, day_index) do nothing;
        update public.voyages set last_settled_day = d where id = v.id;
        if v_delay <> 0 then perform voyage.recompute_eta(v.id); end if;
        select * into v from public.voyages where id = v.id;
        v_resolved := v_resolved + 1;
        continue;
      end if;
      if v_home is not null then
$h$),
  ('voyage.settle(uuid,timestamp with time zone)', 3,
$h$        values (v.id, d, 'FORCED_HOME',
                jsonb_build_object('short_rations', v_short, 'wages', v_wages) || v_home, v_bound)
$h$,
$h$        values (v.id, d, case when v_riot is null then 'FORCED_HOME' else 'RIOT_HOME' end,   -- 0511
                jsonb_build_object('short_rations', v_short, 'wages', v_wages) || v_home || coalesce(v_riot, '{}'::jsonb), v_bound)
$h$),
  ('voyage.settle(uuid,timestamp with time zone)', 4,
$h$      v_payload := v_payload || jsonb_build_object('hull_lost', v_hull, 'delay_hours', v_delay);
$h$,
$h$      v_payload := v_payload || jsonb_build_object('hull_lost', v_hull, 'delay_hours', v_delay);
      v_hap := v.path->0->'hap';
      if v_hap is not null then   -- 0511: a storm kills some hands and loses some goods (the day's magnitude between least and most)
        v_payload := v_payload || voyage.happening_takes(v.id, d, p_fleet, 'STORM',
                       (v_hap->'storm_crew'->>0)::numeric + ((v_hap->'storm_crew'->>1)::numeric - (v_hap->'storm_crew'->>0)::numeric) * h.magnitude,
                       (v_hap->'storm_cargo'->>0)::numeric + ((v_hap->'storm_cargo'->>1)::numeric - (v_hap->'storm_cargo'->>0)::numeric) * h.magnitude);
      end if;
$h$),
  ('voyage.settle(uuid,timestamp with time zone)', 5,
$h$    -- resolved_at is the DETERMINISTIC day boundary, never now(). This is what makes a lazily
$h$,
$h$    -- 0511: SHORT OF HANDS AT SEA: her speed is frozen, so what she loses is hours on the day (never on a day clamped at her ETA: she is at the harbour)
    if v.path->0 ? 'hap' and v_bound < v.eta then
      v_slow := (select min(voyage.crew_share(sh.id, v.path->0->'hap')) from public.ships sh where sh.fleet_id = p_fleet);
      if v_slow < 1 then
        v_delay := v_delay + round(24 * (1 / v_slow - 1), 2);
        v_payload := v_payload || jsonb_build_object('delay_hours', v_delay, 'slow', round(v_slow, 2));
      end if;
    end if;

    -- resolved_at is the DETERMINISTIC day boundary, never now(). This is what makes a lazily
$h$),
  ('voyage.forced_home(uuid,integer,uuid)', 1,
$h$voyage.lose_hold(p_fleet);   -- 0322: the same loop, lifted$h$,
$h$case when v.path->0 ? 'hap' then '{}'::jsonb else voyage.lose_hold(p_fleet) end;   -- 0322: the same loop, lifted; 0511: a riot keeps what she still holds$h$),
  ('voyage.depart(uuid,jsonb,uuid,uuid,timestamp with time zone)', 1,
$h$voyage.freeze_order(voyage.freeze_raiders(voyage.freeze_danger(p_segments, p_at), p_fleet), p_fleet), v_total,$h$,
$h$voyage.freeze_happenings(voyage.freeze_order(voyage.freeze_raiders(voyage.freeze_danger(p_segments, p_at), p_fleet), p_fleet), v_npc), v_total,$h$),
  ('voyage.ship_speed_parts(uuid)', 1,
$h$         * (case when s.crew >= c.crew_required then 1.0 else public.wc_num('crew_short_speed_mult') end)
$h$,
$h$         * (case when s.crew >= c.crew_required then 1.0
                 -- 0511: lit, a player's hull short of hands sails at crew / minimum, never under the floor
                 when voyage.happenings_on() and exists (select 1 from public.fleets f join public.players pl on pl.id = f.player_id and not pl.is_npc where f.id = s.fleet_id)
                   then voyage.crew_share(s.id, public.wc('happenings_terms'))
                 else public.wc_num('crew_short_speed_mult') end)
$h$),
  ('voyage.report_line(integer,text,jsonb)', 1,
$h$             then ' No crew lost (surgeon).'
           else ''
         end;$h$,
$h$             then ' No crew lost (surgeon).'
           else ''
         end
      -- 0511: the share of her goods a riot or a storm took
      || case when p_payload ? 'cargo_lost_pct' then format(' Cargo −%s%%.', p_payload->>'cargo_lost_pct') else '' end
      || case when p_payload ? 'slow' then format(' Short of hands: speed %s%%.', round((p_payload->>'slow')::numeric * 100)) else '' end;$h$);

  for v_h in select h.fn from hunks_0511 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0511 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0511 refuses: hunk % of % is found % times in the live body, not once', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0511 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0511 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0511 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 4. SELF-ASSERT: the catalog, the grants, the knobs ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked || c_new) u(q)))) <> v_fn_before then
    raise exception '0511 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0511 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if exists (select 1 from unnest(c_new) u(q)
              where has_function_privilege('authenticated', u.q::regprocedure, 'execute') or has_function_privilege('anon', u.q::regprocedure, 'execute')
                 or has_function_privilege('service_role', u.q::regprocedure, 'execute'))
     or (select count(*) from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_new) u(q))) and p.prosecdef
                                          and p.provolatile = case when p.proname = 'happening_takes' then 'v' else 's' end) <> cardinality(c_new)
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0511 self-assert FAIL: a new function is reachable by a client or service_role, or is not of its declared kind';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key)) from public.world_config c
       where c.key <> all (array['happenings_bite', 'happenings_terms']::text[])) <> v_cfg_before then
    raise exception '0511 self-assert FAIL: a knob this file does not add moved';
  end if;

  -- ── 5. THE PROBE (its own company and passage; rolled back) ──
  begin
    v_me := public.new_house('00000000-0511-4000-8000-000000000001', 'Casa do Motim 0511', 'PRT');
    select f.id, f.port_id into v_fl, v_lis from public.fleets f where f.player_id = v_me;
    select g.code into v_good from public.goods g order by g.code limit 1;
    for v_lit in select * from unnest(array[false, true]) loop
      begin
        update public.world_config set value = to_jsonb(v_lit) where key = 'happenings_bite';
        update public.ships s set cargo = jsonb_build_object(v_good, 100), cargo_basis = jsonb_build_object(v_good, 50), crew = 100, water_t = 0, food_t = 0,
               durability = (select b.durability from public.ship_base(s.id) b) where s.fleet_id = v_fl;
        v_voy := voyage.depart(v_fl, (select jsonb_agg(jsonb_build_object('a', jsonb_build_array(38.5, -9.6 - (d - 1)), 'b', jsonb_build_array(38.5, -9.6 - d),
                   'nm', voyage.fleet_speed(v_fl) * 24, 'hazard_mult', 0, 'sea_id', (select p.sea_id from public.ports p where p.id = v_lis)) order by d)
                   from generate_series(1, 30) d), v_lis, v_lis, now() - interval '1 second');
        if (v_lit and not (select vo.path->0 ? 'hap' from public.voyages vo where vo.id = v_voy))
           or (not v_lit and (select vo.path->0 ? 'hap' from public.voyages vo where vo.id = v_voy)) then
          raise exception '0511 self-assert FAIL: the terms are not frozen as she leaves (lit %)', v_lit;
        end if;
        perform voyage.settle(v_fl, voyage.day_ends_at(v_voy, 1) + interval '1 millisecond');
        select ve.kind, ve.payload into v_kind, v_pay from public.voyage_events ve where ve.voyage_id = v_voy and ve.day_index = 1;
        if not v_lit then
          if v_kind <> 'FORCED_HOME' or public.fleet_stock_at_cost(v_fl) <> 0 or (select sum(s.crew) from public.ships s where s.fleet_id = v_fl) <> 100
             or (select f.status from public.fleets f where f.id = v_fl) <> 'DOCKED' then
            raise exception '0511 self-assert FAIL: dark, the ran-dry day is not 0279''s: % %', v_kind, v_pay;
          end if;
        else
          if v_kind <> 'RIOT' or (select sum(s.crew) from public.ships s where s.fleet_id = v_fl) <> 85 or public.fleet_cargo_qty(v_fl, v_good) <> 95
             or (v_pay->>'crew_lost')::int <> 15 or (v_pay->>'cargo_lost_cost')::int <> 250 or (v_pay->'cargo_lost'->>v_good)::numeric <> 5
             or (select f.status from public.fleets f where f.id = v_fl) <> 'SAILING' then
            raise exception '0511 self-assert FAIL: lit, a dry day is not 15 %% of the crew and 5 %% of the goods, sailing on: % %', v_kind, v_pay;
          end if;
          perform voyage.settle(v_fl, voyage.day_ends_at(v_voy, 3) + interval '1 millisecond');
          if (select sum(s.crew) from public.ships s where s.fleet_id = v_fl) <> 61 or public.fleet_cargo_qty(v_fl, v_good) not between 85 and 87 then
            raise exception '0511 self-assert FAIL: three dry days leave % hands and % units', (select sum(s.crew) from public.ships s where s.fleet_id = v_fl), public.fleet_cargo_qty(v_fl, v_good);
          end if;
          update public.ships s set crew = greatest(2, floor(c.crew_required * 0.25)) from public.ship_classes c where c.id = s.class_id and s.fleet_id = v_fl;
          perform voyage.settle(v_fl, voyage.day_ends_at(v_voy, 6) + interval '1 millisecond');
          if not exists (select 1 from public.voyage_events ve where ve.voyage_id = v_voy and ve.kind = 'RIOT_HOME')
             or (select f.status from public.fleets f where f.id = v_fl) <> 'DOCKED' or public.fleet_cargo_qty(v_fl, v_good) not between 78 and 87
             or exists (select 1 from public.ships s where s.fleet_id = v_fl and s.crew < 1) then
            raise exception '0511 self-assert FAIL: broken, she is not home with what she holds: % units, %', public.fleet_cargo_qty(v_fl, v_good),
              (select jsonb_agg(jsonb_build_object('d', ve.day_index, 'k', ve.kind, 'p', ve.payload) order by ve.day_index) from public.voyage_events ve where ve.voyage_id = v_voy);
          end if;
          v_note := format('dark: forced home, hold empty; lit: day 1 100 -> 85 hands, 100 -> 95 units; day 3 61 hands; broken: home with %s units', public.fleet_cargo_qty(v_fl, v_good));
        end if;
        raise exception using errcode = 'ZY511', message = 'SCENE';
      exception when sqlstate 'ZY511' then null;
      end;
    end loop;
    raise exception using errcode = 'ZX511', message = 'PROBE_ROLLBACK_0511';
  exception when sqlstate 'ZX511' then
    v_lived := true;
  end;
  if not v_lived or v_note = '' or exists (select 1 from public.players p where p.company_name = 'Casa do Motim 0511') or voyage.happenings_on() then
    raise exception '0511 self-assert FAIL: the probe did not run to its end, or left something behind';
  end if;

  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0511 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0511 self-assert ok: RIOT AND STORM (dark: happenings_bite false). Every hunk once and reversing; no other function or knob moved; four new functions server only. Probe (rolled back): %. % ms.', v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
