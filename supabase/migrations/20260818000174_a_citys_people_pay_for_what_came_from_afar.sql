-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0174 — A CITY'S PEOPLE PAY FOR WHAT CAME FROM AFAR  (the purse pays the base; the distance premium
--        is the townsfolk's; the bid reads the live purse; merchants give their surplus back every hour)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER'S WORDS ───────────────────────────────────────────────────────────────────────────
-- 2026-10-17 ~23:50 UTC: *"Cities are powerful, and they should have some millions of gold as a start
-- … and then make the economy circulate."* 2026-10-17 (0173): *"the distance ratio should make kimchi
-- higher for cash … you bought for 100, it should sell for like 50k each."* The distance factor is the
-- owner's explicit order and is NOT touched here (world.haul_at / port_goods.haul unchanged).
-- The shape of (1) is the coordinator's (2026-10-18 01:25 UTC, after the watch's alert): "the premium
-- is paid by the city's people, not its purse".
--
-- ── WHAT THE WATCH MEASURED (prod, read-only, head 0173; docs/dev-log/2026-10-18-circulation-watch.md)
-- * After 0172's grant (00:32 UTC) and 0173's haul (00:55) the city purses ran ONE WAY: live
--   659.7 M (00:58) → 656.9 M (01:12) → 653.7 M (01:20), −8.4 M an hour and rising, while merchant
--   purses went 39.5 → 42.2 → 45.4 M. Callao fell from 2.00 M to 0.23 M in 43 minutes, under its
--   244 k reserve: one merchant sold Mace and Bird-of-Paradise Plumes there at ~27 k/t that she had
--   bought at ~1.2 k/t (three lines of ~590 k at 01:07).
-- * The cause is structural: a city SELLS its own goods at the maker's price (haul 1) and BUYS a far
--   good at up to 600×. Of the 27.45 M the cities paid for cargo between the 00:37 roll and 01:24,
--   10.23 M (37 %) was the distance premium (Σ total − round(total / haul) over 1,814 SELL flows,
--   every one matched to its port_goods row). The return paths that hour were 10× too small: TAX
--   0.95 M, SHARE 1.38 M, DONATION 0.16 M, WAGES 0.37 M.
-- * The purse alone (the base, Σ round(total / haul)) paid 17.23 M against BUY ≈ 16 M taken in — the
--   own-trade swing the 2 M / 10 M purses were sized for.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) THE BASE AND THE PREMIUM. public.cargo_haul(port, good) — THE one reader of the stored haul a
--     sale is priced with (port_goods.haul, 0173; 1 where none). When a city buys cargo
--     (cmd.do_sell, the one SELL body), its PURSE pays the base, round(total / haul); the premium,
--     total − base, is paid by the city's people: posted through public.treasury_post as its own
--     flow, kind `IMPORT_DEMAND` (+), immediately before the SELL (−total) — so the seller is paid in
--     full, the books show both halves, and at a maker (haul 1) nothing changes. The empty-purse
--     rule (0122) judges the BASE against the purse: a partial fill shrinks to the steps the purse's
--     share covers, and E_CITY_BROKE is refused only when the purse cannot pay the base of one step.
--     Five hunks in cmd.do_sell.
-- (2) THE RESERVE COUNTS WHAT THE PURSE PAID. public.city_sell_outflow — the mean game-day cargo
--     outflow that sizes the reserve (3 ×) — counts SELL net of IMPORT_DEMAND, so a far city's
--     reserve is sized by its purse's own trade, not by money its people paid. One hunk.
-- (3) THE BID READS THE LIVE PURSE. public.city_bid_factor read the purse as ROLLED at :37, so a city
--     could pay out its whole purse inside an hour while still bidding 1 (Callao, above). It now reads
--     public.treasury_balance (rolled + this hour's flows). Measured on prod (EXPLAIN ANALYZE of the
--     stable reads, 4,760 calls): 0.224 ms a call rolled, ~0.30 ms live (+0.07 ms). One hunk.
-- (4) MERCHANTS GIVE BACK EVERY HOUR. npc_invest_max_per_hour 50 → 1000: every merchant above
--     npc_invest_above × capital invests (or gives, 0145) at the hourly reconcile, instead of the 50
--     longest-waiting. Measured: 76 houses above the cap at 00:58, 89 at 01:20 (11.7 M over it) — the
--     50 a hour bottleneck left most of them holding. npc_upkeep_spent (0114's deadline, 60 s) still
--     defers what the hour cannot fit. A knob; the code is unchanged.
-- (5) The Town Hall's "Yesterday" names the new kind (client: src/features/map/CityTownHall.tsx).
--
-- ── MONEY IN AND OUT (stated; the owner decides on a sink) ─────────────────────────────────────
-- (1) MINTS the premium (10.2 M in the 47 minutes measured, rising as the longer laps 0173 planned
--     come in; 0173 planned +575 k a loop). It lands in the sellers' purses — merchants, and players
--     who haul far — and returns to cities only through TAX, SHARE, DONATION, WAGES and the services.
--     Share supply on prod is finite (29.5 M offered at today's works levels), so merchants' money
--     will grow without bound once the shares are bought: see the dev-log for the figures.
--
-- ── NOT THE OWNER'S — CONFIRM (stated, not hidden) ──────────────────────────────────────────────
-- * (1) itself: the premium is minted (townsfolk demand), not taken from the purse.
-- * (2) the reserve counts the purse's net outflow; (3) the live bid; (4) 1000 a hour.
-- * No sink is added. Options for the owner, none built: a cap on a merchant's purse above which the
--   surplus is given to the cities of her loop; the premium paid only up to a city's standing purse;
--   a share of the premium as the city's (the townsfolk pay the city, not the seller).
--
-- ── LOCKS AND TIME ──────────────────────────────────────────────────────────────────────────────
-- CREATE OR REPLACE FUNCTION (cmd.do_sell, city_sell_outflow, city_bid_factor), CREATE FUNCTION
-- cargo_haul, one world_config UPDATE. The probes sell on a docked fleet inside a sub-transaction
-- rolled back whole (asserted). No LOCK TABLE, no set role, no set local, no begin. Deploy with the
-- clock unwound.
-- SUPERSEDES, by hunks sliced from the LIVE bodies (prod head 0173, LF-normalised, each asserted to
-- occur exactly once and to reverse to its pre-image, ACL unchanged): cmd.do_sell (0161/0172 line),
-- public.city_sell_outflow (0122), public.city_bid_factor (0122).
-- ROLLBACK: a forward slice restores the three bodies (each hunk's OLD text is here verbatim);
-- npc_invest_max_per_hour back to 50. IMPORT_DEMAND paid is money: it stays.
-- VERSION: 0174 (provisional; renumbered to head + 1 at deploy). Applies on prod head 0173.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

-- ── 0. HELPERS (pg_temp, gone at commit) ───────────────────────────────────────────────────────
create or replace function pg_temp.occurs_0174(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 1. THE PRE-IMAGES ──────────────────────────────────────────────────────────────────────────
create temp table defs_before_0174 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg,
       (select p.proowner from pg_proc p where p.oid = f.fn::regprocedure) as owner
  from (values ('cmd.do_sell(uuid,jsonb)'),
               ('public.city_sell_outflow(uuid)'),
               ('public.city_bid_factor(uuid)')) f(fn);

create temp table before_0174 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select coalesce(max(id), 0) from public.treasury_flows) as max_flow,
       (select count(*) from public.treasury_flows where kind = 'IMPORT_DEMAND') as n_demand,
       (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
         and p.proname = 'cargo_haul') as n_found,
       public.wc('npc_invest_max_per_hour') as invest_max;

do $$
begin
  if (select count(*) from defs_before_0174 where def is not null) <> 3 then
    raise exception '0174 self-assert FAIL: % of the 3 bodies found', (select count(*) from defs_before_0174 where def is not null);
  end if;
  if (select n_found from before_0174) <> 0 then
    raise exception '0174 self-assert FAIL: public.cargo_haul already exists';
  end if;
  if (select n_demand from before_0174) <> 0 then
    raise exception '0174 self-assert FAIL: an IMPORT_DEMAND flow exists before this file';
  end if;
  if exists (select 1 from public.port_goods where haul is null or haul < 1) then
    raise exception '0174 self-assert FAIL: a port_goods row has no haul or a haul under 1';
  end if;
end $$;

-- ── 2. THE KNOB ────────────────────────────────────────────────────────────────────────────────
update public.world_config set value = to_jsonb(1000)
 where key = 'npc_invest_max_per_hour';

-- ── 3. THE READER ──────────────────────────────────────────────────────────────────────────────
create or replace function public.cargo_haul(p_port uuid, p_good uuid)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0174: THE haul a sale at this quay is priced with (port_goods.haul, 0173 — 1 at a maker, up to
  -- haul_max far away; 1 where the quay keeps no row). A city's purse pays round(total / haul) of a
  -- sale; its people pay the rest (IMPORT_DEMAND, cmd.do_sell).
  select greatest(1::numeric, coalesce((select pg.haul from public.port_goods pg
                                         where pg.port_id = p_port and pg.good_id = p_good), 1::numeric))
$$;
comment on function public.cargo_haul(uuid, uuid) is
  '0174: the stored haul a sale at this quay is priced with (>= 1). The purse pays round(total / haul); the rest is IMPORT_DEMAND.';
revoke all on function public.cargo_haul(uuid, uuid) from public, anon, authenticated;

-- ── 4. THE RE-CUTS (hunks: old = verbatim from the live bodies; new = what replaces it) ─────────
create temp table hunks_0174 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0174 values
('cmd.do_sell(uuid,jsonb)', 1,
$h$  v_wages   bigint := 0;   -- 0128: the wages this sale pays out of its profit
begin$h$,
$h$  v_wages   bigint := 0;   -- 0128: the wages this sale pays out of its profit
  v_haul    numeric;       -- 0174: the haul this quay prices the good with (public.cargo_haul)
  v_demand  bigint;        -- 0174: the premium the city's people pay (IMPORT_DEMAND)
begin$h$),
('cmd.do_sell(uuid,jsonb)', 2,
$h$    v_bal := public.treasury_balance(f.port_id);
    if q.total > v_bal then
      v_need := q.total;
      v_fit  := floor(greatest(v_bal, 0) / nullif(q.avg_price, 0) / public.wc_num('trade_step_tuns'))$h$,
$h$    v_bal := public.treasury_balance(f.port_id);
    -- 0174: the purse pays the BASE of a sale, round(total / haul); the city's people pay the rest.
    v_haul := public.cargo_haul(f.port_id, g.id);
    if round(q.total / v_haul) > v_bal then
      v_need := round(q.total / v_haul);
      v_fit  := floor(greatest(v_bal, 0) * v_haul / nullif(q.avg_price, 0) / public.wc_num('trade_step_tuns'))$h$),
('cmd.do_sell(uuid,jsonb)', 3,
$h$        exit when q.total <= v_bal;$h$,
$h$        exit when round(q.total / v_haul) <= v_bal;   -- 0174: the base$h$),
('cmd.do_sell(uuid,jsonb)', 4,
$h$      if coalesce(v_fit, 0) < public.wc_num('trade_step_tuns') or q.units <= 0 or q.total > v_bal then$h$,
$h$      if coalesce(v_fit, 0) < public.wc_num('trade_step_tuns') or q.units <= 0 or round(q.total / v_haul) > v_bal then$h$),
('cmd.do_sell(uuid,jsonb)', 5,
$h$  perform public.city_pays(f.port_id, f.player_id, 'SELL', q.total,$h$,
$h$  -- 0174: THE PREMIUM IS THE TOWNSFOLK'S. Lit, the city's people pay total − round(total / haul)
  -- into its purse (IMPORT_DEMAND) just before the purse pays the seller the whole total (SELL), so
  -- the purse's own share is the base. At a maker (haul 1) it is 0 and nothing is posted.
  if v_haul is not null then
    v_demand := q.total - round(q.total / v_haul)::bigint;
    if v_demand > 0 then
      perform public.treasury_post(f.port_id, 'IMPORT_DEMAND', v_demand, null, null);
    end if;
  end if;
  perform public.city_pays(f.port_id, f.player_id, 'SELL', q.total,$h$),
('public.city_sell_outflow(uuid)', 1,
$h$  select coalesce(round(-sum(d.ducats) filter (where d.kind = 'SELL')$h$,
$h$  -- 0174: net of IMPORT_DEMAND — what the PURSE paid for cargo, not what the city's people paid.
  select coalesce(round(-sum(d.ducats) filter (where d.kind in ('SELL', 'IMPORT_DEMAND'))$h$),
('public.city_bid_factor(uuid)', 1,
$h$  -- reserve yet), falling linearly to city_bid_floor at an empty purse. Rolled figures only.
  select case when not public.city_treasury_on() then 1::numeric
              else coalesce((select case when t.reserve <= 0 then 1::numeric
                                         else public.wc_num('city_bid_floor')
                                              + (1 - public.wc_num('city_bid_floor'))
                                                * least(1::numeric, t.ducats::numeric / t.reserve) end$h$,
$h$  -- reserve yet), falling linearly to city_bid_floor at an empty purse. 0174: the LIVE purse
  -- (public.treasury_balance — rolled + this hour's flows) against the rolled reserve.
  select case when not public.city_treasury_on() then 1::numeric
              else coalesce((select case when t.reserve <= 0 then 1::numeric
                                         else public.wc_num('city_bid_floor')
                                              + (1 - public.wc_num('city_bid_floor'))
                                                * least(1::numeric, greatest(0, public.treasury_balance(p_port))::numeric
                                                                    / t.reserve) end$h$);

do $$
declare
  d     record;
  h     record;
  v_def text;
  v_n   int;
begin
  for d in select * from defs_before_0174 order by fn loop
    v_def := d.def;
    for h in select * from hunks_0174 where fn = d.fn order by n loop
      v_n := pg_temp.occurs_0174(v_def, h.old);
      if v_n <> 1 then
        raise exception '0174 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
          h.n, d.fn, v_n;
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    execute v_def;
  end loop;
end $$;

-- ── 5. THE PROOFS (own state only; the probe world is rolled back whole) ───────────────────────
create temp table proven_0174 (k text primary key, v text) on commit drop;

-- (a) THE RESERVE'S OUTFLOW over every harbour equals the one expression, as of now.
do $$
declare
  v_n int;
begin
  select count(*) into v_n
    from public.ports p
   where p.kind = 'HARBOUR'
     and public.city_sell_outflow(p.id) is distinct from
         (select coalesce(round(-sum(d.ducats) filter (where d.kind in ('SELL', 'IMPORT_DEMAND'))
                                / nullif(count(distinct d.game_day), 0)), 0)::bigint
            from public.treasury_daybook d
           where d.port_id = p.id and d.kind <> 'CARRIED'
             and d.game_day >= world.game_day() - public.wc_int('treasury_days_kept')
             and d.game_day < world.game_day());
  if v_n <> 0 then
    raise exception '0174 self-assert FAIL: city_sell_outflow differs from the one expression at % harbour(s)', v_n;
  end if;
  insert into proven_0174 values ('outflow', (select count(*) from public.ports where kind = 'HARBOUR')::text || ' harbours');
end $$;

-- (b)-(e) THE PROBE SALE (lit inside the sub-block, rolled back whole).
do $$
declare
  v_fleet  uuid;
  v_player uuid;
  v_port   uuid;
  v_good   uuid;
  v_code   text;
  v_haul   numeric;
  v_step   numeric := public.wc_num('trade_step_tuns');
  v_max    bigint := (select max_flow from before_0174);
  v_r      jsonb;
  v_q      record;
  v_base   bigint;
  v_bal    bigint;
  v_p0     bigint;
  v_dem    bigint;
  v_sell   bigint;
  v_msg    text := null;
  v_ok     text := null;
  v_floor  numeric;
begin
  -- THE PROBE FLEET: docked at a harbour, and a good that quay prices from afar (haul > 2) that it
  -- does not refuse, with a day's allowance for 30 t and the hold for it.
  select f.id, f.player_id, f.port_id, g.id, g.code, g.haul into v_fleet, v_player, v_port, v_good, v_code, v_haul
    from (select f0.* from public.fleets f0
            join public.players p0 on p0.id = f0.player_id
            join public.ports po on po.id = f0.port_id and po.kind = 'HARBOUR'
           where f0.status = 'DOCKED'
           order by p0.is_npc desc, f0.id limit 40) f
    cross join lateral (
      select g1.id, g1.code, pg.haul from public.port_goods pg
        join public.goods g1 on g1.id = pg.good_id
        join public.ports pr on pr.id = pg.port_id
       where pg.port_id = f.port_id and pg.haul > 2
         and (select sum(public.ship_hold_capacity(s.id)) from public.ships s where s.fleet_id = f.id) >= 40 * g1.bulk
         and not public.culture_refuses(pr.culture, g1.culture_mask)
         and world.daily_cap_remaining(f.player_id, f.port_id, g1.id) >= 40
       order by pg.haul desc, g1.code limit 1) g
   limit 1;
  if v_fleet is null then
    raise exception '0174 self-assert FAIL: no docked fleet and far-priced good to probe';
  end if;
  if public.cargo_haul(v_port, v_good) <> v_haul then
    raise exception '0174 self-assert FAIL: cargo_haul % is not the stored haul %', public.cargo_haul(v_port, v_good), v_haul;
  end if;

  begin
    update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled';
    insert into public.port_treasury (port_id, ducats, reserve) values (v_port, 0, 0)
    on conflict (port_id) do update set reserve = 0;
    update public.ships set cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb, water_t = 0, food_t = 0
     where fleet_id = v_fleet;
    perform public.fleet_load(v_fleet, v_code, 40, 1);
    perform public.treasury_post(v_port, 'PROBE_0174', 50000000, null, null);

    -- (b) A FULL PURSE: the seller is paid the whole total; the people pay the premium; the purse the base.
    v_bal := public.treasury_balance(v_port);
    select ducats into v_p0 from public.players where id = v_player;
    v_r := cmd.do_sell(v_fleet, jsonb_build_object('good', v_good, 'qty', 10));
    select coalesce(sum(ducats) filter (where kind = 'IMPORT_DEMAND'), 0), coalesce(sum(ducats) filter (where kind = 'SELL'), 0)
      into v_dem, v_sell
      from public.treasury_flows where id > v_max and port_id = v_port;
    if v_dem <> (v_r->>'total')::bigint - round((v_r->>'total')::bigint / v_haul)::bigint or v_dem <= 0
       or v_sell <> -(v_r->>'total')::bigint
       or (select ducats from public.players where id = v_player) <> v_p0 + (v_r->>'net')::bigint
       or public.treasury_balance(v_port) <> v_bal
            + coalesce((select sum(ducats) from public.treasury_flows where id > v_max and port_id = v_port
                          and kind <> 'PROBE_0174'), 0) then
      raise exception '0174 self-assert FAIL: a far sale % posted IMPORT_DEMAND % and SELL % (haul %), or paid the seller wrongly',
        v_r, v_dem, v_sell, v_haul;
    end if;
    v_ok := format('sold %s t for %s: people paid %s, purse %s (haul %s)', v_r->>'qty', v_r->>'total', v_dem,
                   (v_r->>'total')::bigint - v_dem, round(v_haul, 2));

    -- (c) A PURSE OF EXACTLY THE BASE: the whole 10 t sells (the old rule refused, total > purse).
    select * into v_q from world.quote(v_port, v_good, 10, 'sell', null, v_fleet);
    v_base := round(v_q.total / v_haul);
    perform public.treasury_post(v_port, 'PROBE_0174', v_base - public.treasury_balance(v_port), null, null);
    v_r := cmd.do_sell(v_fleet, jsonb_build_object('good', v_good, 'qty', 10));
    if (v_r->>'qty')::numeric <> 10 or (v_r->>'total')::bigint <> v_q.total then
      raise exception '0174 self-assert FAIL: a purse of the base (% of total %) did not buy the 10 t: %', v_base, v_q.total, v_r;
    end if;
    v_ok := v_ok || format('; a purse of the base %s bought all 10 t (total %s)', v_base, v_q.total);

    -- (d) A PURSE ONE DUCAT SHORT OF ONE STEP'S BASE: refused E_CITY_BROKE, nothing moves.
    select * into v_q from world.quote(v_port, v_good, v_step, 'sell', null, v_fleet);
    perform public.treasury_post(v_port, 'PROBE_0174', round(v_q.total / v_haul)::bigint - 1 - public.treasury_balance(v_port), null, null);
    v_bal := public.treasury_balance(v_port);
    begin
      perform cmd.do_sell(v_fleet, jsonb_build_object('good', v_good, 'qty', v_step));
      raise exception '0174 self-assert FAIL: a purse short of the base bought cargo';
    exception when others then
      if sqlerrm not like 'E_CITY_BROKE%' then raise; end if;
    end;
    if public.fleet_cargo_qty(v_fleet, v_code) <> 40 - 20 or public.treasury_balance(v_port) <> v_bal then
      raise exception '0174 self-assert FAIL: a refused sale moved cargo or money';
    end if;
    v_ok := v_ok || '; one ducat short of a step''s base refused E_CITY_BROKE';

    -- (e) THE LIVE BID: reserve 1000, live purse 500 (rolled purse untouched) → floor + (1 − floor) / 2.
    update public.port_treasury set reserve = 1000 where port_id = v_port;
    perform public.treasury_post(v_port, 'PROBE_0174', 500 - public.treasury_balance(v_port), null, null);
    v_floor := public.wc_num('city_bid_floor');
    if public.city_bid_factor(v_port) <> v_floor + (1 - v_floor) * 0.5 then
      raise exception '0174 self-assert FAIL: the bid at a live purse of half the reserve is % (rolled %)',
        public.city_bid_factor(v_port), (select ducats from public.port_treasury where port_id = v_port);
    end if;
    v_ok := v_ok || format('; the bid at half the reserve (live) is %s', public.city_bid_factor(v_port));

    raise exception 'PROBE_0174_DONE';
  exception when others then
    v_msg := sqlerrm;
  end;
  if v_msg <> 'PROBE_0174_DONE' then
    raise exception '%', v_msg;
  end if;
  if exists (select 1 from public.treasury_flows where id > v_max and kind in ('PROBE_0174', 'IMPORT_DEMAND')) then
    raise exception '0174 self-assert FAIL: the probe did not roll back';
  end if;
  insert into proven_0174 values ('sale', v_ok);
end $$;

-- (f) the bodies, the doors, the receipt
do $$
declare
  d      record;
  h      record;
  v_def  text;
  v_back text;
  v_rev  int := 0;
  q      record;
begin
  for d in select * from defs_before_0174 order by fn loop
    v_def  := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    v_back := v_def;
    for h in select * from hunks_0174 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0174(v_back, h.new) <> 1 then
        raise exception '0174 self-assert FAIL: hunk % of % is not in the live body once', h.n, d.fn;
      end if;
      v_back := replace(v_back, h.new, h.old);
    end loop;
    if v_back is distinct from d.def then
      raise exception '0174 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    v_rev := v_rev + 1;
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef, pr.proowner as owner,
           coalesce(pr.proconfig::text, '') as cfg
      into q from pg_proc pr where pr.oid = d.fn::regprocedure;
    if q.acl <> d.acl or q.vol <> d.vol or q.secdef <> d.secdef or q.cfg <> d.cfg or q.owner <> d.owner then
      raise exception '0174 self-assert FAIL: % changed its ACL, owner, volatility, definer or config', d.fn;
    end if;
  end loop;
  if v_rev <> 3 then
    raise exception '0174 self-assert FAIL: % bodies checked, not 3', v_rev;
  end if;
  select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol into q
    from pg_proc pr where pr.oid = 'public.cargo_haul(uuid,uuid)'::regprocedure;
  if q.acl ~ '(^|[{,])=X' or q.acl ~ 'anon=' or q.acl ~ 'authenticated=' or q.vol <> 's' then
    raise exception '0174 self-assert FAIL: public.cargo_haul is not a server-only stable read (acl %, vol %)', q.acl, q.vol;
  end if;
  if public.wc_int('npc_invest_max_per_hour') <> 1000 then
    raise exception '0174 self-assert FAIL: npc_invest_max_per_hour is %', public.wc('npc_invest_max_per_hour');
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> (select entry_points from before_0174)
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0 then
    raise exception '0174 self-assert FAIL: the client doors moved (entry points % → %, write grants %, executable writers %)',
      (select entry_points from before_0174), (select count(*) from public.client_rpc_entry_points()),
      (select count(*) from public.client_write_grants()), (select count(*) from public.client_executable_writers());
  end if;

  raise notice '0174 self-assert ok: A CITY''S PEOPLE PAY FOR WHAT CAME FROM AFAR. THE SALE (rolled back): %. THE RESERVE: city_sell_outflow is SELL net of IMPORT_DEMAND at %. THE BID reads the live purse. MERCHANTS: npc_invest_max_per_hour % → 1000. BODIES: cmd.do_sell, city_sell_outflow and city_bid_factor reverse to their pre-images hunk by hunk, ACL / owner / volatility / definer / config unmoved; cargo_haul is a server-only stable read; no client door moved.',
    (select v from proven_0174 where k = 'sale'), (select v from proven_0174 where k = 'outflow'),
    (select invest_max from before_0174);
end $$;
