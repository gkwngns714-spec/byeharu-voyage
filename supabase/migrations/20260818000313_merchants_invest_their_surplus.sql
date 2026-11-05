-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0313 — MERCHANTS INVEST THEIR SURPLUS: a finished work keeps selling shares, and each merchant buys once a day from what her laps do not need
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Owner, 2026-11-05: merchants should spend and invest their surplus in cities so city purses rise.
--
-- WHY (measured on prod, head 0310, 2026-11-05 ~07:30 UTC; docs/dev-log/2026-11-05-merchants-invest.md):
--   The door is sound and it runs: every hour 556-597 companies are asked, none deferred, none failed. In 24 hours two of them bought a share.
--   THE SHARES RAN OUT. 924 of the 984 works are at works_level_max and offer nothing; 60 works at 26 ports offer the last 2,447 shares (11.8 M d.).
--   Of the 480,853 shares ever subscribed, houses hold 183,215. The rest are the cities' own BUILD step (public.tick_city step 4), which spends a
--   city's purse on its own works and hands the gold to its region (WORKS_OUT).
--   Of 559 companies asked: 425 are sent to a race city with no share for sale (398 of them have also used their day's gift there), 101 have no share
--   at any stop, 30 find only a remainder under invest_min_ducats, 3 can buy.
--
-- WHAT THIS FILE DOES (the existing door: public.invest_for, SHARE, public.city_shares; no second mechanism, nothing forced, nothing minted):
--   1. works_open_shares (100): a fully built work keeps this many shares on offer, at the price the next step of its own curve would have been
--      (works_share_price(works_level_max), 10,486 d.). When they are sold the next lot opens. Its level does not rise, so production, the docks, the
--      inn and a city's earnings are exactly what they are today. 0 = public.city_offered as it was.
--   2. public.tick_city IS NOT TOUCHED AND DOES NOT TAKE THESE SHARES: its BUILD step reads only works under works_level_max. The gold of a share goes
--      through public.pay_city to the purse of the city that sold it. No WORKS_OUT, no region.
--   3. public.npc_share_budget: what one merchant may put into shares. Her one hour of the day (roster_ord % 24, so no merchant is read twice a day and
--      the pass stays the size it is), an equal part of npc_invest_day_cap (100,000,000 d.) among the companies on the roster, and never her working
--      cash: the larger of npc_invest_keep x capital and npc_invest_keep_laps (2) x the dearest lap of each of her routes (its last 20, none older than 3 days).
--      A merchant keeps what she earns beyond that (0184): nothing here takes anything; she buys what she has spare, one stake a day. 0 = no merchant buys.
--   4. public.npc_invest_one: 5 hunks, her stake reads the budget. Her gift to a race city is what it was.
--   5. public.invest_for: 3 hunks, a lot sold in a finished work leaves its level alone. Under works_level_max it decides exactly what it decided.
--   6. world.town_hall, world.holdings: a finished work with shares on offer serves its share price, and the client shows Invest on it.
--   7. public.npc_invest_roster: 2 hunks, its two knobs are read once and not once a row (prod: 25 ms a read -> 3 ms, the same rows). The same companies in the same order.
--
-- WHAT IT WILL DO (estimate, prod's purses of 2026-11-05): 447 of 558 companies have a stake to spare, about 77 M d. a day into city purses; the other 111
--   keep their cash. The day cap holds for the day's roster: its equal part is 179,211 d. today, and raising the knob raises it.
-- WHAT IT COSTS (0312, PR #495): at 9 % a real day, 77 M d. of shares adds 6.9 M d. a day of coupons due, every day it runs: 69 M due on day 10, 208 M on day 30.
--   0312 pays a city's coupons only out of its day's profit and its surplus, so they can never push a city into a daily loss, and at the old rate this file
--   must not run: DO NOT DEPLOY BEFORE 0312 (0.3 % a game day is 432 % a real day). But 0312 counts SHARE as profit, so share gold can leave again as coupons
--   at the next 00:37. Whether it stays in the purse is the owner's one-word choice in public.flow_is_profit: the dev-log has the sum. This file does not touch it.
--
-- LOCKS AND THE BEAT (0266/0267): the stake still runs in npc_invest_one's own transaction under the quay. The new read is short and runs for about 23
--   companies an hour (the other 530 answer at the first test): the house row, 20 laps a route by index (prod, 34 companies: 1.9 s at the very coldest of 100 laps a route,
--   19 ms warm, before the limit of 20), and the roster's count, which 7 makes cheap.
--
-- NOT TOUCHED: public.tick_city, the coupon, public.pay_city, public.treasury_post, public.credit, public.donate_for, mint_guard,
--   every switch. npc_invest_above, npc_invest_keep, npc_invest_max_per_hour, invest_min_ducats, shares_per_level and works_level_max keep their values.
--
-- SELF-ASSERT (rolled-back probe harbours and probe houses; no real city or merchant, no real game step, docs/OPS_HEALTH.md section 4): the hunks occur once
--   and reverse; grants; nothing else moved; knob 0 is the pre-image; a finished work sells at the honest price, its lots roll, its level stands; an unfinished
--   work still completes; the budget's hour, cap and working cash; a stake on a route and in a race, gold conserved, no WORKS_OUT. THE REAL HOURLY PASS AND
--   THE REAL public.tick_city ARE PROVED IN CI: proof 21, scripts/db/proofs/21_merchants_invest.sql. Mutation controls: scripts/ops/harness/merchants-invest/proof-0313.mjs.
--
-- BUDGET (docs/OPS_HEALTH.md section 4): ONE DO block, statement_timeout 45 s, lock_timeout 5 s first. Self-assert fails above 45 s.
-- ROLLBACK (forward, a NEW migration, owner only): update public.world_config set value = '0' where key in ('npc_invest_day_cap', 'works_open_shares');
--   the next hour no merchant buys and no finished work sells. Shares already sold stay held and keep paying; a lot half sold simply stands.
-- VERSION: 0313 - prod head 0312 (0311 and 0312 deploy first).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_fns  text[] := array['public.city_offered(uuid,text)', 'public.invest_for(uuid,uuid,text,integer)', 'public.npc_invest_one(timestamp with time zone,uuid)',
                         'world.town_hall(uuid)', 'world.holdings()', 'public.npc_invest_roster(uuid)'];
  v_oids oid[];
  v_hfn  int[];
  v_old  text[];
  v_new  text[];
  v_defs text[] := '{}';
  v_acls text[] := '{}';
  v_cfgs text[] := '{}';
  v_def  text;
  v_fn_before  text;
  v_cfg_before text;
  v_t0   timestamptz := clock_timestamp();
  v_i    int;
  v_j    int;
  v_n    int;
  v_mark bigint;
  v_res  jsonb := '{}'::jsonb;
  v_at   timestamptz;
  v_off  timestamptz;
  v_m    uuid;
  v_o    uuid;
  v_sr   uuid;
  v_sr2  uuid;
  v_fl   uuid;
  v_ord  int;
  v_a    uuid;
  v_b    uuid;
  v_c    uuid;
  v_price bigint;
  v_ros  bigint;
  v_stake bigint;
  v_x    jsonb;
  v_y    jsonb;
  v_pur  bigint;
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('public.npc_invest_one(timestamp with time zone,uuid)') is null or to_regprocedure('public.city_offered(uuid,text)') is null then
    raise exception '0313 refuses: 0123 / 0267 (a city sells shares, a company acts alone) are not in this world';
  end if;
  if to_regprocedure('public.npc_share_budget(timestamp with time zone,uuid,bigint)') is not null
     or exists (select 1 from public.world_config c where c.key in ('works_open_shares', 'npc_invest_day_cap', 'npc_invest_keep_laps')) then
    raise exception '0313 refuses: it has been applied once';
  end if;

  v_oids := array(select x::regprocedure::oid from unnest(v_fns) x);
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (v_oids);
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before from public.world_config c;
  for v_i in 1 .. array_length(v_fns, 1) loop
    v_defs[v_i] := (select replace(pg_get_functiondef(v_fns[v_i]::regprocedure), E'\r', ''));
    v_acls[v_i] := (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = v_fns[v_i]::regprocedure);
    v_cfgs[v_i] := (select p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') from pg_proc p where p.oid = v_fns[v_i]::regprocedure);
  end loop;

  -- ── 1. THE KNOBS ──
  insert into public.world_config (key, value, description) values
    ('works_open_shares', to_jsonb(100),
     '0313: the shares a fully built work keeps on offer, one lot at a time, at works_share_price(works_level_max). Its level does not rise and public.tick_city does not buy them. 0 = a finished work sells nothing.'),
    ('npc_invest_day_cap', to_jsonb(100000000),
     '0313: the most the merchants put into shares in a day, shared equally among the companies on public.npc_invest_roster (public.npc_share_budget). 0 = no merchant buys a share. Gifts are not counted here.'),
    ('npc_invest_keep_laps', to_jsonb(2),
     '0313: a merchant buys no share out of this many of her dearest laps (each route''s dearest of its last 20, summed; public.npc_share_budget).');

  -- ── 2. WHAT ONE MERCHANT MAY PUT INTO SHARES ──
  execute $f$
create function public.npc_share_budget(p_now timestamptz, p_player uuid, p_ducats bigint)
returns bigint
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0313: THE ducats one merchant may put into shares at p_now: 0 outside her hour of the day (roster_ord % 24, UTC), else her equal part of
-- npc_invest_day_cap among the companies on the roster, never out of her working cash: the larger of npc_invest_keep x capital and npc_invest_keep_laps x
-- the dearest of the last 20 laps of each of her routes (none older than 3 days). Read by public.npc_invest_one, first thing, under the quay: outside her hour it reads her row alone.
declare
  v_cap bigint := public.wc_int('npc_invest_day_cap');
  h     public.npc_houses%rowtype;
  v_lap bigint;
  v_n   bigint;
begin
  if v_cap <= 0 then
    return 0;
  end if;
  select x.* into h from public.npc_houses x where x.player_id = p_player;
  if h.player_id is null or h.roster_ord % 24 <> extract(hour from p_now at time zone 'UTC')::int then
    return 0;
  end if;
  select coalesce(sum(r.dearest), 0) into v_lap
    from (select max(l.spend) as dearest
            from public.npc_fleets nf
            cross join lateral (select x.bought + x.supplies + x.repairs + x.wages + x.taxes + x.insurance as spend
                                  from public.standing_route_laps x
                                 where x.route_id = nf.route_id and x.closed_at > p_now - interval '3 days'
                                 order by x.lap_no desc limit 20) l
           where nf.player_id = p_player
           group by nf.route_id) r;
  select count(*) into v_n from public.npc_invest_roster();
  return greatest(0, least(v_cap / greatest(v_n, 1),
                           floor(p_ducats - greatest(public.wc_num('npc_invest_keep') * h.capital,
                                                     public.wc_num('npc_invest_keep_laps') * v_lap))))::bigint;
end
$body$
  $f$;
  revoke all on function public.npc_share_budget(timestamptz, uuid, bigint) from public, anon, authenticated;

  -- ── 3. THE RE-CUTS: each hunk occurs once, and reverses ──
  v_hfn := array[1, 1,  2, 2, 2,  3, 3, 3, 3, 3,  4,  5,  6, 6];
  v_old := array[
$h$  -- 0123: the shares of the next level still for sale. Nothing dark; nothing past works_level_max.
$h$,
$h$              else coalesce((select case when w.level >= public.wc_int('works_level_max') then 0
$h$,
    -- public.invest_for
$h$  v_per    int := public.wc_int('shares_per_level');
$h$,
$h$               'price', v_price, 'cost', v_cost, 'level', w.level + 1));
$h$,
$h$  if w.subscribed + p_shares >= v_per then
    update public.city_works set level = level + 1, subscribed = 0, updated_at = now()
     where port_id = p_port and kind = p_kind;
    v_done := true;
$h$,
    -- public.npc_invest_one
$h$  v_gave     boolean;
$h$,
$h$      -- 0145 (D12, O2): LIT, she gives where her country is in the closest race on her loop
$h$,
$h$          v_buy := least(v_stake.offered, floor(v_left / v_stake.price))::int;
$h$,
$h$       where public.city_offered(w.port_id, w.kind) > 0
       order by 3 desc, array_position(array['docks', 'market', 'production', 'inn'], w.kind), po.code
$h$,
$h$                       floor((hi.ducats - public.wc_num('npc_invest_keep') * hi.capital) / v_pick.price))::int;
$h$,
    -- world.town_hall
$h$                'share_price', case when coalesce(w.level, 0) < v_max
                                    then public.works_share_price(coalesce(w.level, 0)) end,
$h$,
    -- world.holdings
$h$           'share_price', case when coalesce(w.level, 0) < v_max then public.works_share_price(coalesce(w.level, 0)) end)
$h$,
    -- public.npc_invest_roster
$h$             where pl.ducats > h.capital * public.wc_num('npc_invest_above')
$h$,
$h$             limit public.wc_int('npc_invest_max_per_hour');
$h$];
  v_new := array[
$h$  -- 0123: the shares of the next level still for sale. Nothing dark. 0313: a finished work offers what is left of its lot of works_open_shares.
$h$,
$h$              else coalesce((select case when w.level >= public.wc_int('works_level_max') then greatest(0, public.wc_int('works_open_shares') - w.subscribed)
$h$,
$h$  v_max    int := public.wc_int('works_level_max');   -- 0313
$h$,
$h$               'price', v_price, 'cost', v_cost, 'level', least(w.level + 1, v_max)));
$h$,
$h$  -- 0313: THE LAST OF WHAT IS OFFERED closes the lot. Under works_level_max that is the 100th share and the level rises, as it did; a finished work's level stands.
  if p_shares >= v_offer then
    update public.city_works set level = least(level + 1, v_max), subscribed = 0, updated_at = now()
     where port_id = p_port and kind = p_kind;
    v_done := w.level < v_max;
$h$,
$h$  v_gave     boolean;
  v_budget   bigint;   -- 0313: what she may put into shares this hour
$h$,
$h$      -- 0313: HER STAKE reads public.npc_share_budget, 0 outside her hour of the day. Her gift below is what it was.
      v_budget := public.npc_share_budget(p_now, hi.player_id, hi.ducats);
      -- 0145 (D12, O2): LIT, she gives where her country is in the closest race on her loop
$h$,
$h$          v_buy := least(v_stake.offered, floor(v_budget / v_stake.price))::int;
$h$,
$h$       where v_budget > 0 and public.city_offered(w.port_id, w.kind) > 0
       order by 3 desc, array_position(array['docks', 'market', 'production', 'inn'], w.kind), po.code
$h$,
$h$                       floor(v_budget / v_pick.price))::int;
$h$,
$h$                'share_price', case when coalesce(w.level, 0) < v_max or public.city_offered(p_port, k.kind) > 0   -- 0313: a finished work still selling
                                    then public.works_share_price(coalesce(w.level, 0)) end,
$h$,
$h$           'share_price', case when coalesce(w.level, 0) < v_max or public.city_offered(s.port_id, s.kind) > 0 then public.works_share_price(coalesce(w.level, 0)) end)   -- 0313
$h$,
$h$             where pl.ducats > h.capital * (select public.wc_num('npc_invest_above'))   -- 0313: read once, not once a row
$h$,
$h$             limit (select public.wc_int('npc_invest_max_per_hour'));
$h$];

  for v_j in 1 .. array_length(v_fns, 1) loop
    v_def := v_defs[v_j];
    for v_i in 1 .. array_length(v_old, 1) loop
      continue when v_hfn[v_i] <> v_j;
      v_n := (length(v_def) - length(replace(v_def, v_old[v_i], ''))) / length(v_old[v_i]);
      if v_n <> 1 then
        raise exception '0313 self-assert FAIL: hunk % of % occurs % time(s), not once: the live body is not what this file was cut against', v_i, v_fns[v_j], v_n;
      end if;
      v_def := replace(v_def, v_old[v_i], v_new[v_i]);
    end loop;
    execute v_def;
  end loop;

  -- ── 4. THE SELF-ASSERT: the catalog ──
  for v_j in 1 .. array_length(v_fns, 1) loop
    v_def := replace(pg_get_functiondef(v_fns[v_j]::regprocedure), E'\r', '');
    for v_i in 1 .. array_length(v_old, 1) loop
      continue when v_hfn[v_i] <> v_j;
      if (length(v_def) - length(replace(v_def, v_new[v_i], ''))) / length(v_new[v_i]) <> 1 then
        raise exception '0313 self-assert FAIL: hunk % of % does not stand once', v_i, v_fns[v_j];
      end if;
      v_def := replace(v_def, v_new[v_i], v_old[v_i]);
    end loop;
    if v_def <> v_defs[v_j] then
      raise exception '0313 self-assert FAIL: % does not reverse to its pre-image', v_fns[v_j];
    end if;
    if (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = v_fns[v_j]::regprocedure) <> v_acls[v_j]
       or (select p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') from pg_proc p where p.oid = v_fns[v_j]::regprocedure) <> v_cfgs[v_j] then
      raise exception '0313 self-assert FAIL: % changed its grants or its settings', v_fns[v_j];
    end if;
  end loop;
  if has_function_privilege('anon', 'public.npc_share_budget(timestamptz,uuid,bigint)', 'execute')
     or has_function_privilege('authenticated', 'public.npc_share_budget(timestamptz,uuid,bigint)', 'execute') then
    raise exception '0313 self-assert FAIL: a client can reach public.npc_share_budget';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (v_oids)
         and p.oid <> 'public.npc_share_budget(timestamptz,uuid,bigint)'::regprocedure) <> v_fn_before then
    raise exception '0313 self-assert FAIL: a function outside this file moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key not in ('works_open_shares', 'npc_invest_day_cap', 'npc_invest_keep_laps')) <> v_cfg_before then
    raise exception '0313 self-assert FAIL: a knob outside this file moved';
  end if;

  -- ── 5. THE SELF-ASSERT: probe harbours and houses, every row rolled back ──
  execute replace(v_defs[1], 'FUNCTION public.city_offered(', 'FUNCTION pg_temp.city_offered_old(');
  v_mark := coalesce((select max(f.id) from public.treasury_flows f), 0);
  begin
    update public.world_config set value = 'true'::jsonb
     where key in ('city_treasury_enabled', 'npc_traders_enabled', 'standing_routes_enabled', 'influence_enabled') and value is distinct from 'true'::jsonb;
    insert into public.ports (code, name, country, lat, lon, sea_id, region_id, culture, size_tier, max_draft, kind)
    select x.code, 'Probe ' || x.code, t.country, t.lat, t.lon, t.sea_id, t.region_id, t.culture, t.size_tier, t.max_draft, 'HARBOUR'
      from (values ('QZA'), ('QZB'), ('QZC')) x(code)
     cross join (select * from public.ports where kind = 'HARBOUR' order by code limit 1) t;
    v_a := (select p.id from public.ports p where p.code = 'QZA');   -- every work finished
    v_b := (select p.id from public.ports p where p.code = 'QZB');   -- docks unfinished
    v_c := (select p.id from public.ports p where p.code = 'QZC');   -- every work finished: a race
    insert into public.port_treasury (port_id, ducats, reserve) select p.id, 1000, 0 from public.ports p where p.code like 'QZ_';
    insert into public.city_works (port_id, kind, level, subscribed)
    select p.id, k.kind, public.wc_int('works_level_max'), 0
      from public.ports p cross join (values ('docks'), ('market'), ('production'), ('inn')) k(kind) where p.code like 'QZ_';
    update public.city_works set level = 2, subscribed = 40 where port_id = v_b and kind = 'docks';
    v_price := public.works_share_price(public.wc_int('works_level_max'));

    v_m := public.new_house(null, 'Casa da Parte 0313', 'PRT', 'LIS', p_ducats => 3000000, p_is_npc => true);
    v_o := public.new_house(null, 'Casa de Fora 0313', (select n.code from public.great_powers g join public.nations n on n.id = g.nation_id where n.code <> 'PRT' order by n.code limit 1), 'LIS', p_ducats => 1000, p_is_npc => true);
    v_ord := (select coalesce(max(h.roster_ord), 0) + 1 from public.npc_houses h);
    insert into public.npc_houses (player_id, roster_ord, ink, blurb, master, home_port_id, capital, patience, wares)
    select x.id, x.ord, 'prt', 'A probe house of 0313, rolled back.', 'Mestre da Parte', p.id, 25000, 0.1, '{}'
      from (values (v_m, v_ord), (v_o, v_ord + 1)) x(id, ord) join public.ports p on p.code = 'LIS';
    update public.players set ducats = 100000000 where id = v_o;   -- on the roster too: the equal part is never the whole cap
    v_at  := (date_trunc('day', now() at time zone 'UTC') + make_interval(hours => v_ord % 24)) at time zone 'UTC';
    v_off := v_at + interval '1 hour';
    v_fl := (select f.id from public.fleets f where f.player_id = v_m order by f.id limit 1);
    v_sr := gen_random_uuid();
    insert into public.standing_routes (id, player_id, name, fleet_id) values (v_sr, v_m, 'Parte 0313', null);
    insert into public.standing_route_stops (route_id, ord, port_id, course) values (v_sr, 1, v_a, '[[0,0],[1,1]]'), (v_sr, 2, v_b, '[[1,1],[0,0]]');
    insert into public.npc_fleets (fleet_id, player_id, route_id, roster_ord)
    values (v_fl, v_m, v_sr, (select coalesce(max(n.roster_ord), 0) + 1 from public.npc_fleets n));
    insert into public.standing_route_laps (route_id, lap_no, started_at, closed_at, bought, supplies, repairs, wages, taxes, insurance) values
      (v_sr, 1, v_at - interval '4 days 1 hour', v_at - interval '4 days', 9000000, 0, 0, 0, 0, 0),   -- too old to count
      (v_sr, 2, v_at - interval '2 hours', v_at - interval '1 hour', 300000, 50000, 40000, 30000, 20000, 10000),   -- 450,000: the dearest
      (v_sr, 3, v_at - interval '1 hour', v_at - interval '30 minutes', 100000, 0, 0, 0, 0, 0);
    v_ros := (select count(*) from public.npc_invest_roster());
    update public.world_config set value = to_jsonb(v_ros * 180000) where key = 'npc_invest_day_cap';   -- her equal part: 180,000 d., in any world

    -- WHAT A CITY OFFERS
    v_res := v_res || jsonb_build_object('offer', jsonb_build_object(
      'done', public.city_offered(v_a, 'docks'), 'open', public.city_offered(v_b, 'docks'), 'old_done', pg_temp.city_offered_old(v_a, 'docks'), 'old_open', pg_temp.city_offered_old(v_b, 'docks')));
    v_x := world.town_hall(v_a);
    v_res := v_res || jsonb_build_object('hall', (select w from jsonb_array_elements(v_x -> 'works') w where w ->> 'kind' = 'docks'));
    update public.world_config set value = to_jsonb(0) where key = 'works_open_shares';
    v_x := world.town_hall(v_a);
    v_res := v_res || jsonb_build_object('off', jsonb_build_object(
      'done', public.city_offered(v_a, 'docks'), 'open', public.city_offered(v_b, 'docks'), 'old_done', pg_temp.city_offered_old(v_a, 'docks'), 'old_open', pg_temp.city_offered_old(v_b, 'docks'),
      'hall', (select w from jsonb_array_elements(v_x -> 'works') w where w ->> 'kind' = 'docks')));
    update public.world_config set value = to_jsonb(100) where key = 'works_open_shares';

    -- HER BUDGET
    v_res := v_res || jsonb_build_object('budget', jsonb_build_object(
      'hour', public.npc_share_budget(v_at, v_m, 3000000),
      'off_hour', public.npc_share_budget(v_off, v_m, 3000000),
      'stranger', public.npc_share_budget(v_at, gen_random_uuid(), 3000000),
      'tight', public.npc_share_budget(v_at, v_m, 950000),
      'under', public.npc_share_budget(v_at, v_m, 890000)));
    update public.world_config set value = to_jsonb(0) where key = 'npc_invest_day_cap';
    v_res := v_res || jsonb_build_object('cap0', public.npc_share_budget(v_at, v_m, 3000000));
    update public.world_config set value = to_jsonb(v_ros * 180000) where key = 'npc_invest_day_cap';
    update public.world_config set value = to_jsonb(0) where key = 'npc_invest_keep_laps';
    v_res := v_res || jsonb_build_object('capital', public.npc_share_budget(v_at, v_m, 50000));
    update public.world_config set value = to_jsonb(2) where key = 'npc_invest_keep_laps';

    -- A STAKE ON HER ROUTE: not her hour, nothing; her hour, her budget in whole shares, at the stop offering most
    v_x := public.npc_invest_one(v_off, v_m);
    v_res := v_res || jsonb_build_object('off_turn', jsonb_build_object('r', v_x, 'purse', (select p.ducats from public.players p where p.id = v_m),
      'shares', (select count(*) from public.city_shares s where s.player_id = v_m)));
    v_stake := least(100, floor(public.npc_share_budget(v_at, v_m, 3000000)::numeric / v_price))::bigint * v_price;
    v_pur := public.treasury_balance(v_a);
    v_x := public.npc_invest_one(v_at, v_m);
    perform public.assert_ledger_reconciles(v_m);
    v_res := v_res || jsonb_build_object('turn', jsonb_build_object('r', v_x, 'stake', v_stake,
      'paid', 3000000 - (select p.ducats from public.players p where p.id = v_m),
      'city', public.treasury_balance(v_a) - v_pur,
      'held', (select jsonb_agg(jsonb_build_object('kind', s.kind, 'shares', s.shares, 'paid', s.paid)) from public.city_shares s where s.player_id = v_m and s.port_id = v_a),
      'stamped', (select h.invested_at = v_at from public.npc_houses h where h.player_id = v_m),
      'work', (select jsonb_build_object('level', w.level, 'subscribed', w.subscribed) from public.city_works w where w.port_id = v_a and w.kind = 'docks'),
      'moved', (select jsonb_object_agg(f.kind, f.ducats) from public.treasury_flows f where f.id > v_mark and f.port_id in (v_a, v_b, v_c))));

    -- A LOT SOLD TO THE LAST SHARE: the price holds, the lot rolls, the level stands; one share too many is refused
    v_x := public.invest_for(v_o, v_b, 'market', 100);
    v_y := public.invest_for(v_o, v_b, 'market', 30);
    v_res := v_res || jsonb_build_object('lot', jsonb_build_object('first', v_x, 'second', v_y,
      'work', (select jsonb_build_object('level', w.level, 'subscribed', w.subscribed) from public.city_works w where w.port_id = v_b and w.kind = 'market'),
      'event', (select e.payload -> 'level' from public.events e where e.player_id = v_o and e.kind = 'INVESTED' order by e.created_at desc limit 1)));
    begin
      perform public.invest_for(v_o, v_b, 'market', 71);
      v_res := v_res || jsonb_build_object('over', 'sold');
    exception when others then
      v_res := v_res || jsonb_build_object('over', sqlerrm);
    end;
    -- ...and an unfinished work still completes at its 100th share
    v_x := public.invest_for(v_o, v_b, 'docks', 60);
    v_res := v_res || jsonb_build_object('rise', jsonb_build_object('r', v_x,
      'work', (select jsonb_build_object('level', w.level, 'subscribed', w.subscribed) from public.city_works w where w.port_id = v_b and w.kind = 'docks')));

    -- A RACE: her country trails at a finished harbour on a second route. Outside her hour she gives as she did, and buys nothing; in her hour she buys there too
    update public.players set ducats = 3000000 where id = v_m;
    update public.npc_houses set invested_at = null where player_id = v_m;
    insert into public.port_allegiance (port_id, nation_id) select v_c, p.nation_id from public.players p where p.id = v_o;
    insert into public.port_influence (port_id, nation_id, player_id, points)
    select v_c, p.nation_id, p.id, case when p.id = v_m then 100 else 110 end from public.players p where p.id in (v_m, v_o);
    v_sr2 := gen_random_uuid();
    insert into public.standing_routes (id, player_id, name, fleet_id) values (v_sr2, v_m, 'Corrida 0313', null);
    insert into public.standing_route_stops (route_id, ord, port_id, course) values (v_sr2, 1, v_c, '[[0,0],[1,1]]');
    delete from public.standing_route_stops where route_id = v_sr;
    update public.npc_fleets set route_id = v_sr2 where player_id = v_m;
    v_x := public.npc_invest_one(v_off, v_m);
    v_res := v_res || jsonb_build_object('race_off', jsonb_build_object('r', v_x,
      'race', (select r.port_id = v_c from public.npc_closest_race(v_m) r),
      'paid', 3000000 - (select p.ducats from public.players p where p.id = v_m),
      'shares', (select count(*) from public.city_shares s where s.player_id = v_m and s.port_id = v_c)));
    update public.port_influence set day_given = 0, points = case when player_id = v_m then 100 else 110 end where port_id = v_c;   -- her gift won that race: the same race again
    update public.players set ducats = 3000000 where id = v_m;
    v_x := public.npc_invest_one(v_at, v_m);
    v_res := v_res || jsonb_build_object('race_on', jsonb_build_object('r', v_x,
      'shares', (select sum(s.shares) from public.city_shares s where s.player_id = v_m and s.port_id = v_c),
      'paid', 3000000 - (select p.ducats from public.players p where p.id = v_m)));
    raise exception using errcode = 'ZX313', message = v_res::text;
  exception when sqlstate 'ZX313' then
    v_res := sqlerrm::jsonb;
  end;

  -- what a city offers: finished, the lot; unfinished, what it was; knob 0, the pre-image
  if (v_res #>> '{offer,done}')::int <> 100 or (v_res #>> '{offer,old_done}')::int <> 0
     or (v_res #>> '{offer,open}')::int <> 60 or (v_res #>> '{offer,old_open}')::int <> 60 then
    raise exception '0313 self-assert FAIL: a finished work does not offer its lot, or an unfinished one moved: %', v_res -> 'offer';
  end if;
  if (v_res #>> '{off,done}')::int <> (v_res #>> '{off,old_done}')::int or (v_res #>> '{off,open}')::int <> (v_res #>> '{off,old_open}')::int
     or v_res #> '{off,hall}' ->> 'share_price' is not null then
    raise exception '0313 self-assert FAIL: knob 0 is not the pre-image: %', v_res -> 'off';
  end if;
  if (v_res #>> '{hall,offered}')::int <> 100 or (v_res #>> '{hall,share_price}')::bigint is distinct from public.works_share_price(public.wc_int('works_level_max'))
     or (v_res #>> '{hall,next_cost}') is not null then
    raise exception '0313 self-assert FAIL: the hall does not serve a finished work honestly: %', v_res -> 'hall';
  end if;
  -- her budget: her equal part in her hour, nothing else
  if (v_res #>> '{budget,off_hour}')::bigint <> 0 or (v_res #>> '{budget,stranger}')::bigint <> 0 or (v_res ->> 'cap0')::bigint <> 0 then
    raise exception '0313 self-assert FAIL: a budget outside her hour, for no merchant, or at cap 0: %', v_res;
  end if;
  -- 2 x her dearest lap of 450,000 (the 9,000,000 lap is 4 days old) is 900,000 of working cash
  if (v_res #>> '{budget,hour}')::bigint <> 180000 then
    raise exception '0313 self-assert FAIL: the budget is not her equal part: %', v_res -> 'budget';
  end if;
  if (v_res #>> '{budget,tight}')::bigint <> 50000 or (v_res #>> '{budget,under}')::bigint <> 0 then
    raise exception '0313 self-assert FAIL: the budget touches her working cash: %', v_res -> 'budget';
  end if;
  if (v_res ->> 'capital')::bigint <> 50000 - 37500 then
    raise exception '0313 self-assert FAIL: the budget does not keep npc_invest_keep x capital: %', v_res ->> 'capital';
  end if;
  -- a stake on her route
  if (v_res #>> '{off_turn,r,invested}')::int <> 0 or (v_res #>> '{off_turn,purse}')::bigint <> 3000000 or (v_res #>> '{off_turn,shares}')::int <> 0 then
    raise exception '0313 self-assert FAIL: she bought outside her hour: %', v_res -> 'off_turn';
  end if;
  if (v_res #>> '{turn,r,invested}')::int <> 1 or (v_res #>> '{turn,stake}')::bigint < 1
     or (v_res #>> '{turn,paid}')::bigint <> (v_res #>> '{turn,stake}')::bigint or (v_res #>> '{turn,city}')::bigint <> (v_res #>> '{turn,stake}')::bigint
     or not (v_res #>> '{turn,stamped}')::boolean or (v_res #>> '{turn,work,level}')::int <> public.wc_int('works_level_max')
     or (v_res #> '{turn,moved}') ->> 'SHARE' <> (v_res #>> '{turn,stake}') or (v_res #> '{turn,moved}') ? 'WORKS_OUT' then
    raise exception '0313 self-assert FAIL: the stake is not what her budget bought, or its gold did not land whole in the city: %', v_res -> 'turn';
  end if;
  -- a lot of a finished work: the price of the curve's next step, the lot rolls, the level stands, nothing beyond the lot
  v_price := public.works_share_price(public.wc_int('works_level_max'));
  if (v_res #>> '{lot,first,completed}')::boolean or (v_res #>> '{lot,first,level}')::int <> public.wc_int('works_level_max')
     or (v_res #>> '{lot,first,price}')::bigint <> v_price or (v_res #>> '{lot,first,cost}')::bigint <> 100 * v_price
     or (v_res #>> '{lot,second,price}')::bigint <> v_price or (v_res #>> '{lot,second,subscribed}')::int <> 30
     or (v_res #>> '{lot,work,level}')::int <> public.wc_int('works_level_max') or (v_res #>> '{lot,work,subscribed}')::int <> 30
     or (v_res #>> '{lot,event}')::int <> public.wc_int('works_level_max') then
    raise exception '0313 self-assert FAIL: a lot of a finished work: %', v_res -> 'lot';
  end if;
  if position('E_OVERSUBSCRIBED' in v_res ->> 'over') = 0 then
    raise exception '0313 self-assert FAIL: a lot sold past its end: %', v_res ->> 'over';
  end if;
  -- an unfinished work still rises at its 100th share
  if not (v_res #>> '{rise,r,completed}')::boolean or (v_res #>> '{rise,work,level}')::int <> 3 or (v_res #>> '{rise,work,subscribed}')::int <> 0 then
    raise exception '0313 self-assert FAIL: an unfinished work did not complete: %', v_res -> 'rise';
  end if;
  -- a race: outside her hour her gift is what it was and she buys nothing; in her hour she buys and gives
  if not (v_res #>> '{race_off,race}')::boolean or (v_res #>> '{race_off,r,invested}')::int <> 0 or (v_res #>> '{race_off,r,donated}')::int <> 1
     or (v_res #>> '{race_off,paid}')::bigint <> public.wc_int('influence_day_cap') or (v_res #>> '{race_off,shares}')::int <> 0 then
    raise exception '0313 self-assert FAIL: outside her hour the race is not what it was: %', v_res -> 'race_off';
  end if;
  if (v_res #>> '{race_on,r,invested}')::int <> 1 or (v_res #>> '{race_on,r,donated}')::int <> 1
     or (v_res #>> '{race_on,shares}')::bigint * v_price + public.wc_int('influence_day_cap') <> (v_res #>> '{race_on,paid}')::bigint then
    raise exception '0313 self-assert FAIL: in her hour the race did not take her stake and her gift: %', v_res -> 'race_on';
  end if;

  -- nothing of the probe survives; the knobs stand at their defaults
  if exists (select 1 from public.ports p where p.code like 'QZ_') or exists (select 1 from public.players p where p.company_name like 'Casa % 0313')
     or exists (select 1 from public.treasury_flows f where f.id > v_mark and f.created_at = now()) then
    raise exception '0313 self-assert FAIL: the probe left rows behind';
  end if;
  if public.wc_int('works_open_shares') <> 100 or public.wc_int('npc_invest_day_cap') <> 100000000 or public.wc_int('npc_invest_keep_laps') <> 2 then
    raise exception '0313 self-assert FAIL: a knob is not at its default';
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0313 self-assert FAIL: the self-assert took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0313 self-assert ok: MERCHANTS INVEST THEIR SURPLUS. A finished work offers % shares at % d., its level stands; public.npc_share_budget gives each merchant her hour, an equal part of the day cap, never her working cash; a stake of % d. landed whole in the city, no WORKS_OUT; 6 functions re-cut, each reversed, grants held, nothing else moved. The real hourly pass and tick_city: proof 21, in CI. (% ms)',
    v_res #>> '{hall,offered}', v_res #>> '{hall,share_price}', v_res #>> '{turn,stake}', round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
