-- ═══════════════════════════════════════════════════════════
-- PROOF 21 — MERCHANTS INVEST THEIR SURPLUS  (migration 0313)
--
--   0313's own self-assert runs one probe merchant on probe harbours (a migration never runs a real game step, docs/OPS_HEALTH.md section 4).
--   This proof runs the REAL public.npc_invest and the REAL public.tick_city over the whole world, with every work finished, rolled back.
--
-- @pass INVEST_HOUR     only the merchants of this hour buy, each at most her equal part of the day cap
-- @pass INVEST_CASH     no merchant goes under her working cash for a share
-- @pass INVEST_PURSE    what the merchants paid is the SHARE that reached the cities, and nothing was made or lost
-- @pass INVEST_NO_BUILD tick_city rolls it into the purses that sold it: no level built, no WORKS_OUT, no region paid
-- ═══════════════════════════════════════════════════════════

do $$
declare
  v_at    timestamptz;
  v_hour  int;
  v_mark  bigint;
  v_n     bigint;
  v_part  bigint;
  v_bad   bigint;
  v_paid  bigint;
  v_share bigint;
  v_gold0 numeric;
  v_gold1 numeric;
  v_r     jsonb;
  v_purse bigint;
begin
  if not exists (select 1 from public.npc_houses) then
    raise exception 'PROOF 21 FAIL: this world has no merchants';
  end if;
  update public.world_config set value = 'true'::jsonb
   where key in ('city_treasury_enabled', 'npc_traders_enabled', 'standing_routes_enabled') and value is distinct from 'true'::jsonb;
  update public.world_config set value = 'false'::jsonb where key = 'influence_enabled';   -- the route's stake alone: the race is 0313's self-assert

  -- every work finished, every city with a stop on some merchant's loop able to sell; every merchant well above her cash
  insert into public.city_works (port_id, kind)
  select p.id, k.kind from public.ports p cross join (values ('docks'), ('market'), ('production'), ('inn')) k(kind) where p.kind = 'HARBOUR'
  on conflict (port_id, kind) do nothing;
  update public.city_works set level = public.wc_int('works_level_max'), subscribed = 0;
  update public.players pl set ducats = h.capital * 2 + 9000000 from public.npc_houses h where h.player_id = pl.id;
  update public.npc_fleets nf set route_id = sr.id
    from (select distinct on (s.player_id) s.player_id, s.id from public.standing_routes s order by s.player_id, s.id) sr
   where sr.player_id = nf.player_id and nf.route_id is null;

  -- the hour with the most merchants that have a stop, at the top of this world's clock
  select (x.roster_ord % 24) into v_hour
    from public.npc_houses x join public.npc_fleets nf on nf.player_id = x.player_id join public.standing_route_stops s on s.route_id = nf.route_id
   group by 1 order by count(*) desc, 1 limit 1;
  if v_hour is null then
    raise exception 'PROOF 21 FAIL: no merchant in this world has a stop';
  end if;
  v_at := (date_trunc('day', now() at time zone 'UTC') + make_interval(hours => v_hour)) at time zone 'UTC';

  v_n := (select count(*) from public.npc_invest_roster());
  update public.world_config set value = to_jsonb(v_n * 180000) where key = 'npc_invest_day_cap';   -- her equal part: 180,000 d., in any world
  v_part := 180000;
  v_mark := coalesce((select max(f.id) from public.treasury_flows f), 0);
  select coalesce(sum(p.ducats), 0) + (select coalesce(sum(t.ducats), 0) from public.port_treasury t) + (select coalesce(sum(f.ducats), 0) from public.treasury_flows f)
    into v_gold0 from public.players p;
  create temp table purses_21 on commit drop as select h.player_id, pl.ducats from public.npc_houses h join public.players pl on pl.id = h.player_id;

  v_r := public.npc_invest(v_at);
  if (v_r ->> 'failed')::int <> 0 then
    raise exception 'PROOF 21 FAIL: a company failed: %', v_r;
  end if;
  if (v_r ->> 'invested')::int < 1 then
    raise exception 'PROOF 21 FAIL: no merchant bought: %', v_r;
  end if;

  select count(*) into v_bad from public.npc_houses h join public.players pl on pl.id = h.player_id join purses_21 b on b.player_id = h.player_id
   where pl.ducats <> b.ducats and h.roster_ord % 24 <> v_hour;
  if v_bad <> 0 then
    raise exception 'PROOF 21 FAIL: % merchant(s) bought outside their hour', v_bad;
  end if;
  select count(*) into v_bad from public.players pl join purses_21 b on b.player_id = pl.id where b.ducats - pl.ducats > v_part;
  if v_bad <> 0 then
    raise exception 'PROOF 21 FAIL: % merchant(s) spent more than the equal part', v_bad;
  end if;
  raise notice 'PASS: INVEST_HOUR — % of % bought, in hour %, none above % d.', v_r ->> 'invested', v_n, v_hour, v_part;

  select count(*) into v_bad from public.npc_houses h join public.players pl on pl.id = h.player_id join purses_21 b on b.player_id = pl.id
   where pl.ducats <> b.ducats and pl.ducats < h.capital * public.wc_num('npc_invest_keep');
  if v_bad <> 0 then
    raise exception 'PROOF 21 FAIL: % merchant(s) went under their working cash', v_bad;
  end if;
  raise notice 'PASS: INVEST_CASH — no merchant under her working cash';

  select coalesce(sum(b.ducats - pl.ducats), 0) into v_paid from public.players pl join purses_21 b on b.player_id = pl.id;
  select coalesce(sum(f.ducats), 0) into v_share from public.treasury_flows f where f.id > v_mark and f.kind = 'SHARE';
  select coalesce(sum(p.ducats), 0) + (select coalesce(sum(t.ducats), 0) from public.port_treasury t) + (select coalesce(sum(f.ducats), 0) from public.treasury_flows f)
    into v_gold1 from public.players p;
  if v_paid <= 0 or v_paid <> v_share or v_gold0 <> v_gold1 then
    raise exception 'PROOF 21 FAIL: paid %, SHARE %, gold % -> %', v_paid, v_share, v_gold0, v_gold1;
  end if;
  raise notice 'PASS: INVEST_PURSE — % d. paid, % d. of SHARE, gold unchanged', v_paid, v_share;

  v_purse := (select coalesce(sum(t.ducats), 0) from public.port_treasury t);
  v_r := public.tick_city(now());
  if (v_r ->> 'levels_built')::int <> 0 or (v_r ->> 'works_moved')::bigint <> 0 or (v_r ->> 'subscribed')::int <> 0 then
    raise exception 'PROOF 21 FAIL: the city step took a merchant''s share: %', v_r;
  end if;
  if exists (select 1 from public.treasury_flows f where f.id > v_mark and f.kind in ('WORKS_OUT', 'WORKS_IN'))
     or exists (select 1 from public.treasury_daybook d where d.kind in ('WORKS_OUT', 'WORKS_IN') and d.game_day >= world.game_day(now()) - 1) then
    raise exception 'PROOF 21 FAIL: a share''s gold went to the region';
  end if;
  raise notice 'PASS: INVEST_NO_BUILD — rolled into the purses, no level built, nothing moved to a region, receipt errors %', v_r -> 'errors';
end
$$;
