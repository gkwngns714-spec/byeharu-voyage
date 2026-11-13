-- ═══════════════════════════════════════════════════════════════════════════════════════════════════
-- 0378 - THE SEAS ASK A TITLE AND A HULL: the one guarded step that lights sea_conditions_bite  (owner rows 166 and 324)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER (docs/OWNER_REQUESTS.md row 324, 2026-11-13): "do all, make everything work. open them if everything is built and is workable."
-- Row 166: far seas ask a title and the fleet's wave resistance, a hard wall at plan time and at departure.
--
-- THIS FILE LIGHTS NOTHING. It installs the step that lights, with its guards, and the read of those guards:
--   public.sea_conditions_ready()  -> jsonb   STABLE, server-only. What stands between this world and the light, as figures:
--        lit                    the switch as it stands
--        wall_reads_in          0376 is in (public.far_powers and world.sea_zone_map): the page can say why a sea is shut, and nobody is founded in a far sea
--        fleet_room             fleet_room_bite is on: a company can sail her big ship apart from her small one (a fleet's wave resistance is an AVERAGE)
--        fleets_in_closed_seas  human fleets lying in, or under way to, a harbour whose sea would refuse them (they could not leave it), with the first five
--        capitals_closed        human companies whose country's capital lies in a sea their title does not open
--        route_legs_closed      legs of human standing routes that would be refused
--        queued_sails_closed    queued SAILs to a harbour whose sea would refuse them (told, not a guard: each fails with its reason when it runs)
--        ready                  not lit, and every guard above holds
--   public.sea_conditions_light()  -> jsonb   VOLATILE, server-only, THE STEP. It refuses (raises, so nothing is changed) when the switch is already lit or
--        when any guard fails, naming every one that fails with its figure. Otherwise it sets sea_conditions_bite true and posts the news row
--        public.news_update('0378', ...) (0347's law: the step that lights tells the players), and returns the figures.
-- Every verdict is public.sea_refusal, the one rule, asked with her own title and her fleet's own wave, over public.harbour_zone and public.course_zones as
-- the sail door reads them. Nothing is compared here.
--
-- WHY A STEP AND NOT A SWITCH THROWN BY THIS FILE (decided by default, the lead may reverse): a migration is applied to every world of the chain: CI's, each
-- developer's, the private world in the browser, and a replay from zero. Those worlds hold probe companies lying in far seas and have fleet_room_bite off, so
-- a file that raised on the guards would fail every one of them for ever, and a file that lit without guards would shut every far sail of every existing
-- proof and spec. The guards read LIVE data, so they belong to the moment of lighting, on the world being lit.
--
-- TO LIGHT (the lead, on the owner's word, never an agent; docs/dev-log/2026-11-13-lighting-the-seas.md):
--   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/sea-light/before.sql        (read-only: the figures; wanted ready true)
--   npx --yes supabase@2.120.0 db query --linked "select public.sea_conditions_light()"
--   then scripts/ops/harness/sea-light/after-check.sql at +1, +5 and +30 minutes.
-- ROLLBACK, at once (owner): update public.world_config set value = 'false'::jsonb where key = 'sea_conditions_bite' returning key, value;
--   every passage is then judged as before the light. The news row stays (it is history). Forward removal of the two functions:
--   scripts/ops/harness/sea-light/rollback-0378.sql (a draft).
--
-- NOT TOUCHED: public.sea_gate, public.passage_gate, public.sea_refusal, any switch, any knob, any row. Two new functions and nothing else.
-- ALL OR NOTHING: ONE `do` block; statement_timeout 60 s and lock_timeout 5 s first; BUDGET 30 s (locally under 1 s).
-- SELF-ASSERT (this block; reads, and two probes that roll back): the two functions are server-only, pinned, of the declared volatility; no other function,
-- no knob and no news row moved; the read answers its ten figures and agrees with the switch; THE STEP, CALLED INSIDE A PROBE THAT ROLLS BACK, either refuses
-- naming its guards and leaves the switch dark, or (a world that is ready) lights it and posts exactly one news row; THE WALL, with the switch forced on INSIDE
-- A PROBE THAT ROLLS BACK: for up to twenty human fleets the passage gate's answer to Funchal and to Las Palmas equals the one rule asked directly, and a
-- title-1 fleet of wave 10 or more may sail Funchal and is refused Las Palmas E_SEA_CLOSED by Macaronesia, title 2 asked, 1 held. THE LIVE PATHS (each guard
-- red in turn, the step lighting a ready world, the news row, the rollback line) are proved in CI by scripts/db/proofs/71_the_seas_are_lit_by_one_guarded_step.sql.
-- VERSION: 0378 = 0376 (a wall says what is short) + 0377 (merchants, dark) + 1.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0         timestamptz := clock_timestamp();
  v_fn_before  text;
  v_cfg_before text;
  v_news       bigint;
  v_entry      int;
  v_r          jsonb;
  v_lit        boolean;
  v_refused    boolean;
  v_n          int := 0;
  v_one        int := 0;
  v_lis        record;
  v_fnc        record;
  v_lpa        record;
  v_cf         jsonb;
  v_cl         jsonb;
  v_g          jsonb;
  v_want       jsonb;
  r_x          record;
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD: nothing of this file exists, and what it reads does ──
  if to_regprocedure('public.sea_conditions_ready()') is not null or to_regprocedure('public.sea_conditions_light()') is not null then
    raise exception '0378 refuses: the lighting step is already in this world';
  end if;
  if to_regprocedure('public.sea_conditions_on()') is null or to_regprocedure('public.sea_refusal(integer, numeric, text[])') is null
     or to_regprocedure('public.harbour_zone(uuid)') is null or to_regprocedure('public.course_zones(jsonb)') is null
     or to_regprocedure('public.title_level(uuid)') is null or to_regprocedure('public.fleet_wave(uuid)') is null
     or to_regprocedure('public.fleet_room_on()') is null or to_regprocedure('public.news_update(text, text, text)') is null
     or to_regprocedure('public.passage_gate(uuid, uuid, numeric, uuid, jsonb)') is null
     or not exists (select 1 from public.world_config where key = 'sea_conditions_bite') then
    raise exception '0378 refuses: a function or knob this file reads is not in this world (0215 and 0216 the seas, 0321 fleet room, 0347 the news)';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  v_entry := (select count(*) from public.client_rpc_entry_points());
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p');
  select md5(string_agg(c.key || ':' || c.value::text || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before from public.world_config c;
  select count(*) into v_news from public.world_news;
  v_lit := public.sea_conditions_on();

  -- ── 2. THE READ ──
  execute $f$
create function public.sea_conditions_ready()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0378: WHAT STANDS BETWEEN THIS WORLD AND LIGHTING THE SEA CONDITIONS, as figures (the header of 0378 names each). A read: it judges through the one rule
  -- (public.sea_refusal) with each company's own title and each fleet's own wave, whatever the switch says. public.sea_conditions_light refuses on it.
  with h as materialized (
    select p.id, p.company_name, public.title_level(p.id) as title, cap.id as capital
      from public.players p
      left join public.nations n on n.id = p.nation_id
      left join public.ports cap on cap.code = n.capital_port_code
     where not p.is_npc),
  hf as materialized (
    select f.id, f.name, h.company_name, h.title, public.fleet_wave(f.id) as wave, coalesce(f.port_id, v.dest_port_id) as here
      from public.fleets f join h on h.id = f.player_id
      left join public.voyages v on v.fleet_id = f.id and v.status = 'SAILING'),
  stuck as materialized (
    select hf.company_name, hf.name, p.code
      from hf join public.ports p on p.id = hf.here
     where public.sea_refusal(hf.title, hf.wave, array_remove(array[public.harbour_zone(hf.here)], null)) is not null),
  leg as (
    select st.route_id, st.course, hf.title, hf.wave,
           coalesce(lead(st.port_id) over (partition by st.route_id order by st.ord), first_value(st.port_id) over (partition by st.route_id order by st.ord)) as to_port
      from public.standing_routes sr join hf on hf.id = sr.fleet_id
      join public.standing_route_stops st on st.route_id = sr.id),
  g as (
    select public.sea_conditions_on() as lit,
           to_regprocedure('public.far_powers()') is not null and to_regprocedure('world.sea_zone_map()') is not null as wall_reads_in,
           public.fleet_room_on() as fleet_room,
           (select count(*) from stuck) as fleets_in_closed_seas,
           (select count(*) from h where h.capital is not null
              and public.sea_refusal(h.title, null, array_remove(array[public.harbour_zone(h.capital)], null)) is not null) as capitals_closed,
           (select count(*) from leg l
             where public.sea_refusal(l.title, l.wave, public.course_zones(l.course) || array_remove(array[public.harbour_zone(l.to_port)], null)) is not null) as route_legs_closed,
           (select count(*) from public.orders o join hf on hf.id = o.fleet_id
             where o.verb = 'SAIL' and o.status in ('pending', 'active') and nullif(o.args ->> 'dest', '') is not null
               and public.sea_refusal(hf.title, hf.wave, array_remove(array[public.harbour_zone((o.args ->> 'dest')::uuid)], null)) is not null) as queued_sails_closed)
  select jsonb_build_object(
           'lit', g.lit, 'wall_reads_in', g.wall_reads_in, 'fleet_room', g.fleet_room,
           'fleets_in_closed_seas', g.fleets_in_closed_seas,
           'first_fleets', (select coalesce(jsonb_agg(s.company_name || ' / ' || s.name || ' at ' || s.code), '[]'::jsonb)
                              from (select * from stuck order by company_name, name limit 5) s),
           'capitals_closed', g.capitals_closed, 'route_legs_closed', g.route_legs_closed, 'queued_sails_closed', g.queued_sails_closed,
           'companies', (select count(*) from h), 'fleets', (select count(*) from hf),
           'ready', not g.lit and g.wall_reads_in and g.fleet_room and g.fleets_in_closed_seas = 0 and g.capitals_closed = 0 and g.route_legs_closed = 0)
    from g
$body$
  $f$;
  revoke all on function public.sea_conditions_ready() from public, anon, authenticated;
  comment on function public.sea_conditions_ready() is '0378: the figures that stand between this world and lighting sea_conditions_bite. A read; server-only.';

  -- ── 3. THE STEP ──
  execute $f$
create function public.sea_conditions_light()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0378: THE ONE STEP THAT LIGHTS THE SEA CONDITIONS FOR PLAYERS. It refuses, changing nothing, when the switch is already lit or when a guard of
-- public.sea_conditions_ready fails, and says every guard that fails with its figure. Otherwise: sea_conditions_bite true, and the news row of this step.
-- Server-only: the lead runs it on the owner's word. Its rollback is the switch.
declare
  v   jsonb := public.sea_conditions_ready();
  v_why text[] := '{}';
begin
  if (v ->> 'lit')::boolean then
    raise exception 'sea_conditions_light refuses: the sea conditions are already lit' using errcode = 'P0001';
  end if;
  if not (v ->> 'wall_reads_in')::boolean then
    v_why := v_why || 'the reads that say why a sea is shut are not in (0376)'::text;
  end if;
  if not (v ->> 'fleet_room')::boolean then
    v_why := v_why || 'fleet_room_bite is off: a company cannot sail her big ship apart from her small one'::text;
  end if;
  if (v ->> 'fleets_in_closed_seas')::int > 0 then
    v_why := v_why || format('%s fleet(s) of companies lie in, or sail to, a sea that would refuse them and could not leave it (%s)',
                             v ->> 'fleets_in_closed_seas', (select string_agg(x, ', ') from jsonb_array_elements_text(v -> 'first_fleets') x));
  end if;
  if (v ->> 'capitals_closed')::int > 0 then
    v_why := v_why || format('%s company(ies) have a capital in a sea their title does not open', v ->> 'capitals_closed');
  end if;
  if (v ->> 'route_legs_closed')::int > 0 then
    v_why := v_why || format('%s leg(s) of companies'' standing routes would be refused', v ->> 'route_legs_closed');
  end if;
  if cardinality(v_why) > 0 then
    raise exception 'sea_conditions_light refuses: %. Read scripts/ops/harness/sea-light/before.sql and scripts/ops/harness/sea-conditions/impact.sql', array_to_string(v_why, '; ')
      using errcode = 'P0001';
  end if;
  update public.world_config set value = 'true'::jsonb, updated_at = now() where key = 'sea_conditions_bite';
  perform public.news_update('0378', 'Seas ask a title and a sturdy ship', '바다마다 작위와 내파 필요');
  return v || jsonb_build_object('lit', public.sea_conditions_on(), 'ready', false, 'lit_at', now());
end
$body$
  $f$;
  revoke all on function public.sea_conditions_light() from public, anon, authenticated;
  comment on function public.sea_conditions_light() is '0378: THE guarded step that lights sea_conditions_bite and posts its news. Refuses, changing nothing, while a guard of public.sea_conditions_ready fails. Server-only; the lead runs it on the owner''s word.';

  -- ── 4. THE SELF-ASSERT ──
  -- 4a the two functions, and nothing else
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and not (n.nspname = 'public' and p.proname in ('sea_conditions_ready', 'sea_conditions_light'))) is distinct from v_fn_before then
    raise exception '0378 self-assert FAIL: a function this file does not write moved';
  end if;
  for r_x in select p.proname, p.provolatile, p.prosecdef, coalesce(p.proconfig::text, '') as cfg, p.oid
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname in ('sea_conditions_ready', 'sea_conditions_light') loop
    v_n := v_n + 1;
    if r_x.provolatile <> (case when r_x.proname = 'sea_conditions_light' then 'v' else 's' end)
       or not r_x.prosecdef or r_x.cfg <> '{"search_path=public, pg_temp"}'
       or has_function_privilege('anon', r_x.oid, 'execute') or has_function_privilege('authenticated', r_x.oid, 'execute') then
      raise exception '0378 self-assert FAIL: public.% is not of its declared volatility, definer, pinned and server-only', r_x.proname;
    end if;
  end loop;
  if v_n <> 2 or (select count(*) from public.client_rpc_entry_points()) <> v_entry
     or (select count(*) from public.client_write_grants()) <> 0 or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0378 self-assert FAIL: the two functions are not exactly two, or the registry or a wall moved';
  end if;

  -- 4b the read: its figures, and it agrees with the switch
  v_r := public.sea_conditions_ready();
  if not (v_r ?& array['lit', 'wall_reads_in', 'fleet_room', 'fleets_in_closed_seas', 'first_fleets', 'capitals_closed', 'route_legs_closed', 'queued_sails_closed', 'companies', 'fleets', 'ready'])
     or (v_r ->> 'lit')::boolean is distinct from v_lit
     or ((v_r ->> 'ready')::boolean and ((v_r ->> 'lit')::boolean or (v_r ->> 'fleets_in_closed_seas')::int > 0 or not (v_r ->> 'fleet_room')::boolean)) then
    raise exception '0378 self-assert FAIL: the read does not answer its figures, or calls a world ready that is not: %', v_r;
  end if;

  -- 4c THE STEP, inside a probe that rolls back: it refuses naming its guards and leaves the switch as it was, or (a ready world) lights and posts one row
  begin
    begin
      v_g := public.sea_conditions_light();
      v_refused := false;
    exception when sqlstate 'P0001' then
      if sqlerrm not like 'sea_conditions_light refuses: %' then raise; end if;
      v_refused := true;
    end;
    if v_refused then
      if (v_r ->> 'ready')::boolean or public.sea_conditions_on() is distinct from v_lit or (select count(*) from public.world_news) <> v_news then
        raise exception '0378 self-assert FAIL: the step refused a world its own read calls ready, or refused and still changed something';
      end if;
    else
      if not (v_r ->> 'ready')::boolean or not public.sea_conditions_on() or (select count(*) from public.world_news where key = 'update:0378') <> 1 then
        raise exception '0378 self-assert FAIL: the step lit a world its own read does not call ready, or lit without the switch and one news row';
      end if;
    end if;
    raise exception 'PROBE_ROLLBACK_0378';
  exception when others then
    if sqlerrm <> 'PROBE_ROLLBACK_0378' then raise; end if;
  end;

  -- 4d THE WALL, with the switch forced on inside a probe that rolls back: the gate is the one rule, on real fleets, to an open harbour and to a shut one
  select r.roadstead_lat as lat, r.roadstead_lon as lon, r.port_id into v_lis from public.sea_reaches r where r.code = 'LIS';
  select r.roadstead_lat as lat, r.roadstead_lon as lon, r.port_id into v_fnc from public.sea_reaches r where r.code = 'FNC';
  select r.roadstead_lat as lat, r.roadstead_lon as lon, r.port_id into v_lpa from public.sea_reaches r where r.code = 'LPA';
  if v_lis.port_id is null or v_fnc.port_id is null or v_lpa.port_id is null then
    raise exception '0378 self-assert FAIL: Lisbon, Funchal or Las Palmas has no roadstead in this world';
  end if;
  v_cf := jsonb_build_array(jsonb_build_array(v_lis.lat, v_lis.lon), jsonb_build_array(v_fnc.lat, v_fnc.lon));
  v_cl := jsonb_build_array(jsonb_build_array(v_lis.lat, v_lis.lon), jsonb_build_array(v_lpa.lat, v_lpa.lon));
  v_n := 0;
  begin
    update public.world_config set value = 'true'::jsonb where key = 'sea_conditions_bite';
    for r_x in select f.id, f.player_id, public.title_level(f.player_id) as title, public.fleet_wave(f.id) as wave
                 from public.fleets f join public.players p on p.id = f.player_id and not p.is_npc
                where exists (select 1 from public.ships s where s.fleet_id = f.id)
                order by f.id limit 20 loop
      v_n := v_n + 1;
      v_g := public.passage_gate(r_x.player_id, r_x.id, 1, v_fnc.port_id, v_cf);
      v_want := public.sea_refusal(r_x.title, r_x.wave, public.course_zones(v_cf) || array[public.harbour_zone(v_fnc.port_id)]);
      if v_g is distinct from v_want then
        raise exception '0378 self-assert FAIL: lit, the gate to Funchal answers % and the one rule %', v_g, v_want;
      end if;
      v_g := public.passage_gate(r_x.player_id, r_x.id, 1, v_lpa.port_id, v_cl);
      v_want := public.sea_refusal(r_x.title, r_x.wave, public.course_zones(v_cl) || array[public.harbour_zone(v_lpa.port_id)]);
      if v_g is distinct from v_want then
        raise exception '0378 self-assert FAIL: lit, the gate to Las Palmas answers % and the one rule %', v_g, v_want;
      end if;
      if r_x.title = 1 and r_x.wave >= 10 then
        v_one := v_one + 1;
        if public.passage_gate(r_x.player_id, r_x.id, 1, v_fnc.port_id, v_cf) is not null
           or v_g is null or v_g ->> 'code' <> 'E_SEA_CLOSED' or v_g -> 'figures' ->> 'zone' <> 'NOR-MAC'
           or (v_g -> 'figures' ->> 'needs_title')::int <> 2 or (v_g -> 'figures' ->> 'title')::int <> 1
           or (v_g -> 'figures' ? 'short_title' and (not (v_g -> 'figures' ->> 'short_title')::boolean or (v_g -> 'figures' ->> 'short_wave')::boolean)) then
          raise exception '0378 self-assert FAIL: lit, a title-1 fleet is not free to Funchal and refused Las Palmas by Macaronesia (title 2 asked, 1 held, the title short and the wave not): %', v_g;
        end if;
      end if;
    end loop;
    raise exception 'PROBE_ROLLBACK_0378';
  exception when others then
    if sqlerrm <> 'PROBE_ROLLBACK_0378' then raise; end if;
  end;

  -- 4e nothing moved: the switch, every knob, the news
  if public.sea_conditions_on() is distinct from v_lit
     or (select md5(string_agg(c.key || ':' || c.value::text || ':' || c.updated_at::text, ',' order by c.key)) from public.world_config c) is distinct from v_cfg_before
     or (select count(*) from public.world_news) <> v_news then
    raise exception '0378 self-assert FAIL: the switch, a knob or the news moved (this file lights nothing)';
  end if;
  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0378 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;

  raise notice '0378 NOTE: this file lights nothing. The lead lights with: select public.sea_conditions_light()  (docs/dev-log/2026-11-13-lighting-the-seas.md). The guards as this world stands: %', v_r;
  raise notice '0378 self-assert ok: THE SEAS ASK A TITLE AND A HULL - the read and the step installed, server-only; no other function, knob or news row moved; the step, probed and rolled back, % ; the wall, forced on and rolled back, equal to the one rule on % human fleet(s), % of them title 1 (free to Funchal, refused Las Palmas by Macaronesia); % ms',
    case when v_refused then 'refused naming its guards and changed nothing' else 'lit a ready world with one news row' end, v_n, v_one,
    round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
