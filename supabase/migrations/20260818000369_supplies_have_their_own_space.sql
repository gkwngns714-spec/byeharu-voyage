-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0369 — SUPPLIES HAVE THEIR OWN SPACE: world_config `ship_stores_separate` false -> true. One knob row is written and one news row is posted. No function, no table, no job.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- WHY. Owner, 2026-10-26 (row 221): "separate cargo space so that provision is set differently by ship." 0345 built it dark behind this one switch and left the light to "the owner".
--   Owner, 2026-11-13 (row 324): "do all, make everything work. open them if everything is built and is workable." This file is that one light, and nothing else
--   (the form of 0178, which threw skills_bite, and 0179, crew_bite).
-- WHAT THE SWITCH TURNS ON (every reader is live already, 0345; none is touched here):
--   * a ship's hold is all cargo: public.fleet_free_hold, public.fleet_load and the board's units_fit stop counting water and food;
--   * every top-up of supplies (a SAIL's own purchase, PROVISION, a merchant's and a crown's) fills her own supply room, public.ship_stores_space, whatever her cargo;
--   * world.ship_view serves `stores_cap`, so the Fleets page shows "Supply room 8/26 tons" and the hold bars count goods only;
--   * a leg too long for her supply room is refused with "her stores space carries ..." (the desk words it "Supplies short: can carry X, crossing needs Y");
--   * world.trip_cost (0360) and Trade's board row (0361) read the same room through public.ship_stores_room, so the price they name is the price the SAIL charges
--     (scripts/db/proofs/70_supplies_have_their_own_space_lit.sql sails both and compares).
-- GUARD (the file refuses, and nothing is written, when any of these is not so):
--   * 0345's five readers, 0360's world.trip_cost and 0347's news exist;
--   * the switch row exists and reads exactly false (a world where it is already lit, or missing, is not the world this file was written for);
--   * THE PRECONDITION READ: no fleet with a leg under way or a stop on a standing route would be unable to carry its longest leg in its supply room. This is the read of
--     scripts/ops/harness/ship-stores/impact.sql (`short_lit`), spelt with the live public.ship_stores_space. Prod, read only, 2026-11-10: 0 human, 0 merchant (6 merchants were short DARK).
-- AFTER THE WRITE, on the real authority: for every human fleet and the first 20 merchant fleets by id that have such a leg, public.supply_reach (lit) carries the leg.
-- SELF-ASSERT, on a probe house of this file's own, rolled back: her hold brimmed with cargo, casks empty: the cargo room is the hold less the cargo; PROVISION FULL fills her supply
--   room to the tun; her view serves stores_cap; THE ROLLBACK PLAYED inside the probe (the switch set false) gives the dark figures back. The catalog: no function moved; exactly one
--   world_config row moved; the news row is one row.
-- WHO IS TOUCHED AT ONCE: every company and every merchant. Nobody loses anything aboard: a hull that carries more supplies than her room keeps them until they are eaten (0345, no backfill).
-- ALTERS LIVE PLAY: its own window, a 30-minute after-check (scripts/ops/harness/ship-stores/after-light.sql, impact.sql, scripts/ops/health.sh).
-- ROLLBACK (forward; a draft is scripts/ops/harness/ship-stores/rollback-0369.sql): the same row set back to false. The world is the world before 0345 at once.
--   The one-line form (owner only): update public.world_config set value = 'false'::jsonb where key = 'ship_stores_separate';
-- BUDGET: ONE DO block, statement_timeout 60 s, lock_timeout 5 s; it fails above 30 s. Each part's time is printed in a notice.
-- NEWS: this file posts its own UPDATE row, public.news_update('0369', 'Supply room: the hold is all cargo', '보급 창고: 선창은 전부 화물') (0347's law, tests/news.lint.spec.ts).
-- VERSION: 0369 - deploys after 0364, 0366 and 0367. It names no function of those three.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0          timestamptz := clock_timestamp();
  v_t           timestamptz;
  v_n           int;
  v_short       int;
  v_legs        int;
  v_short_h     int;
  v_real_n      int;
  v_real_short  int;
  v_fn_before   text;
  v_cfg_before  text;
  v_lived       boolean := false;
  v_pl          uuid;
  v_fl          uuid;
  v_sh          uuid;
  v_gcode       text;
  v_hold        numeric;
  v_cargo       numeric;
  v_space       numeric;
  v_st          numeric;
  v_view        jsonb;
  v_r           jsonb;
  v_ms_pre      numeric;
  v_ms_real     numeric;
  v_ms_probe    numeric;
  c_key         constant text := 'ship_stores_separate';
  c_uid         constant uuid := '00000000-0369-4000-8000-000000000001';
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from unnest(array['public.ship_stores_separate()', 'public.ship_stores_space(uuid)', 'public.ship_stores_room(uuid,numeric)', 'public.stores_in_hold(numeric)',
                                        'public.ship_stores_card(uuid)', 'public.supply_reach(uuid)', 'public.fleet_free_hold(uuid)', 'world.ship_view(uuid)', 'world.trip_cost(uuid,jsonb)',
                                        'cmd.do_provision(uuid,jsonb)', 'public.fleet_load(uuid,text,numeric,numeric)', 'public.news_update(text,text,text)']) f where to_regprocedure(f) is null) then
    raise exception '0369 refuses: the supply room (0345), the trip''s price (0360) or the news (0347) are not in this world';
  end if;
  if (select c.value from public.world_config c where c.key = c_key) is distinct from 'false'::jsonb or public.ship_stores_separate() then
    raise exception '0369 refuses: % is not false in this world (it reads %): this file lights it once, from dark', c_key, (select c.value from public.world_config c where c.key = c_key);
  end if;

  -- ── 1. THE PRECONDITION READ: no fleet that cannot carry its longest leg in its supply room (impact.sql's `short_lit`, with the live reader of the room) ──
  v_t := clock_timestamp();
  with k as (
    select public.wc_num('water_per_crew_day') + public.wc_num('food_per_crew_day') as per_day
  ), legs as (
    select x.fleet_id, max(x.nm) as nm
      from (select v.fleet_id, v.total_nm as nm from public.voyages v where v.status = 'SAILING'
            union all
            select r.fleet_id, st.course_nm from public.standing_routes r join public.standing_route_stops st on st.route_id = r.id) x
     where x.fleet_id is not null group by x.fleet_id
  ), fl as (
    select l.fleet_id, l.nm, bool_or(p.is_npc) as is_npc,
           min(case when s.crew > 0 then public.ship_stores_space(s.id) / (s.crew * k.per_day) end) * voyage.endurance_mult(l.fleet_id) as lit_days
      from legs l join public.ships s on s.fleet_id = l.fleet_id join public.players p on p.id = s.player_id cross join k
     group by l.fleet_id, l.nm
  ), judged as (
    select fl.*, voyage.stores_need_days(fl.nm, greatest(voyage.fleet_speed(fl.fleet_id), 0.1)) as need from fl
  )
  select count(*), count(*) filter (where j.lit_days < j.need - 0.01), count(*) filter (where j.lit_days < j.need - 0.01 and not j.is_npc)
    into v_legs, v_short, v_short_h from judged j;
  if v_short > 0 then
    raise exception '0369 refuses: % fleet(s) (% of them a company''s) could not carry their longest leg in their supply room; run scripts/ops/harness/ship-stores/impact.sql and read `short_lit`', v_short, v_short_h;
  end if;
  v_ms_pre := round(extract(epoch from clock_timestamp() - v_t) * 1000);

  -- ── 2. BEFORE: the catalog and every OTHER knob ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p');
  select md5(string_agg(c.key || ':' || c.value::text || ':' || c.description || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before from public.world_config c where c.key <> c_key;

  -- ── 3. THE LIGHT ──
  update public.world_config
     set value = 'true'::jsonb, updated_at = now(),
         description = description || ' LIT by 0369 (owner row 324, 2026-11-13).'
   where key = c_key and value = 'false'::jsonb;
  get diagnostics v_n = row_count;
  if v_n <> 1 or not public.ship_stores_separate() then
    raise exception '0369 self-assert FAIL: % row(s) written, and the reader says %', v_n, public.ship_stores_separate();
  end if;

  -- ── 4. LIT, ON THE REAL AUTHORITY: every company's fleet and the first 20 merchant fleets with a leg asked carry it (public.supply_reach, lit) ──
  v_t := clock_timestamp();
  with legs as (
    select x.fleet_id, max(x.nm) as nm
      from (select v.fleet_id, v.total_nm as nm from public.voyages v where v.status = 'SAILING'
            union all
            select r.fleet_id, st.course_nm from public.standing_routes r join public.standing_route_stops st on st.route_id = r.id) x
     where x.fleet_id is not null group by x.fleet_id
  ), sel as (
    select l.* from legs l join public.fleets f on f.id = l.fleet_id join public.players p on p.id = f.player_id where not p.is_npc
    union all
    select y.fleet_id, y.nm from (select l.* from legs l join public.fleets f on f.id = l.fleet_id join public.players p on p.id = f.player_id where p.is_npc order by l.fleet_id limit 20) y
  )
  select count(*), count(*) filter (where (select r.carry_days from public.supply_reach(s.fleet_id) r) < voyage.stores_need_days(s.nm, greatest(voyage.fleet_speed(s.fleet_id), 0.1)) - 0.01)
    into v_real_n, v_real_short
    from sel s
   where exists (select 1 from public.ships h where h.fleet_id = s.fleet_id and h.crew > 0);
  if v_real_short > 0 then
    raise exception '0369 self-assert FAIL: lit, % of % fleet(s) read cannot carry their longest leg by public.supply_reach', v_real_short, v_real_n;
  end if;
  v_ms_real := round(extract(epoch from clock_timestamp() - v_t) * 1000);

  -- ── 5. THE SELF-ASSERT: a probe house of this file's own, rolled back ──
  v_t := clock_timestamp();
  begin
    v_pl := public.new_house(c_uid, 'Casa da Prova 0369', 'PRT');
    select f.id into v_fl from public.fleets f where f.player_id = v_pl;
    select s.id into v_sh from public.ships s where s.fleet_id = v_fl;
    update public.players set ducats = 10000000 where id = v_pl;
    update public.ships set water_t = 0, food_t = 0 where id = v_sh;
    v_gcode := (select g.code from public.goods g where g.bulk = 1 order by g.code limit 1);
    perform public.fleet_load(v_fl, v_gcode, 100000, 1);
    v_hold  := public.ship_hold_capacity(v_sh);
    v_cargo := public.ship_cargo_tuns(v_sh);
    v_space := public.ship_stores_space(v_sh);
    if v_cargo <= 0 or v_space < 1 or public.fleet_free_hold(v_fl) <> greatest(0, v_hold - v_cargo) then
      raise exception '0369 self-assert FAIL: lit, the probe''s cargo room is % with a hold of % and % of cargo (supply room %)', public.fleet_free_hold(v_fl), v_hold, v_cargo, v_space;
    end if;
    -- PROVISION FULL fills her supply room to the tun, whatever her cargo
    v_r := cmd.do_provision(v_fl, '{"mode": "FULL"}'::jsonb);
    select s.water_t + s.food_t into v_st from public.ships s where s.id = v_sh;
    if abs(v_st - v_space) > 0.01 or public.ship_cargo_tuns(v_sh) <> v_cargo then
      raise exception '0369 self-assert FAIL: lit, FULL put % t into a supply room of % t (cargo % -> %): %', v_st, v_space, v_cargo, public.ship_cargo_tuns(v_sh), v_r;
    end if;
    v_view := world.ship_view(v_sh);
    if (v_view ->> 'stores_cap')::numeric is distinct from v_space or public.fleet_free_hold(v_fl) <> greatest(0, v_hold - v_cargo) then
      raise exception '0369 self-assert FAIL: lit, her view serves stores_cap % against a supply room of %, or the supplies took cargo room', v_view -> 'stores_cap', v_space;
    end if;
    -- THE ROLLBACK, PLAYED: the row set back to false is the world before 0345
    update public.world_config set value = 'false'::jsonb where key = c_key;
    if public.ship_stores_separate() or world.ship_view(v_sh) ? 'stores_cap' or public.fleet_free_hold(v_fl) <> greatest(0, v_hold - v_cargo - v_st) then
      raise exception '0369 self-assert FAIL: with the switch set back, the view still serves stores_cap or the cargo room does not count the supplies again';
    end if;
    raise exception using errcode = 'ZX369', message = 'PROBE_ROLLBACK_0369';
  exception when sqlstate 'ZX369' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0369 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players pl where pl.auth_uid = c_uid) then
    raise exception '0369 self-assert FAIL: the probe house outlived the probe';
  end if;
  v_ms_probe := round(extract(epoch from clock_timestamp() - v_t) * 1000);

  -- ── 6. AFTER: lit, and nothing else moved ──
  if not public.ship_stores_separate() or (select c.value from public.world_config c where c.key = c_key) is distinct from 'true'::jsonb then
    raise exception '0369 self-assert FAIL: the switch is not lit after the probe';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) <> v_fn_before then
    raise exception '0369 self-assert FAIL: a function moved: this file edits none';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || c.description || ':' || c.updated_at::text, ',' order by c.key)) from public.world_config c where c.key <> c_key) <> v_cfg_before then
    raise exception '0369 self-assert FAIL: another world_config row moved: this file writes one';
  end if;

  -- THIS FILE'S OWN UPDATE ROW (0347's news law, tests/news.lint.spec.ts), counted by its own key; outside the rolled-back probe
  perform public.news_update('0369', 'Supply room: the hold is all cargo', '보급 창고: 선창은 전부 화물');
  if (select count(*) from public.world_news w where w.key = 'update:0369') <> 1 then
    raise exception '0369 self-assert FAIL: this file''s UPDATE row is not one row';
  end if;
  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0369 self-assert FAIL: the file ran % s, over its 30 s budget', round(extract(epoch from clock_timestamp() - v_t0));
  end if;
  raise notice '0369 timings: the precondition read (% fleet(s) with a leg asked) % ms; lit on public.supply_reach (% fleet(s)) % ms; the probe % ms', v_legs, v_ms_pre, v_real_n, v_ms_real, v_ms_probe;
  raise notice '0369 self-assert ok: SUPPLIES HAVE THEIR OWN SPACE. ship_stores_separate was false and is true. Before the write, none of % fleet(s) with a leg under way or a standing route was short of its longest leg in its supply room; after it, none of the % read on public.supply_reach is. A probe house, her % t hold brimmed with % t of cargo and her casks empty: cargo room is the hold less the cargo, PROVISION FULL filled her % t supply room to the tun, her view serves stores_cap; with the switch set back (the rollback, played and rolled back) the dark figures return. No function moved, no other knob moved, its UPDATE row is one row. % ms.',
    v_legs, v_real_n, v_hold, v_cargo, v_space, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
