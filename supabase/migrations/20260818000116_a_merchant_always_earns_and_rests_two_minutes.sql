-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0116 — A MERCHANT ALWAYS EARNS, AND RESTS TWO MINUTES
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER'S WORDS ───────────────────────────────────────────────────────────────────────────
-- 2026-10-14: merchants should ALWAYS earn; *"for resting reduce it to 2 min."*
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) A MERCHANT'S RUNNING COSTS ARE NOUGHT. `npc_cost_mult` goes from 0.25 to 0. Merchant
--     companies are off Rank and their money never reaches a player, so their wages, supplies and
--     repairs are cosmetic. The one reader is public.running_cost_mult (0114), which voyage.settle,
--     cmd.do_provision, cmd.do_repair and npc_plan already compose. With costs at nought and the
--     sell floor at what she paid + npc_sell_margin (0114), no trade of hers loses money.
-- (2) A LAP COUNTS ITS OWN CARGO — the close-before-the-home-sale artefact is fixed in the ONE
--     closer. cmd.standing_route_close_lap closes a lap on ARRIVAL at the first stop, before that
--     stop's SELL runs, so cargo bought on the last leg was charged to lap N and sold in lap N+1.
--     A lap now records `stock_out`, the cargo aboard at its close at what it cost (ships.cargo ×
--     cargo_basis, the basis fleet_cargo_basis reads). Its net is
--       sold − bought − supplies − repairs − wages + stock_out − stock_in
--     where stock_in is the previous closed lap's stock_out. That is cost of goods SOLD, not
--     goods bought: a parcel carried over is charged to the lap that sells it. This is ONE rule for
--     every route, a player's included, because it is the same lap and the same closer. It moves a
--     player's loss guard only where a lap ended holding cargo it had paid for — which was never a
--     loss.
--     The first lap to close under this file has no stock_in to read (earlier laps hold 0), so it
--     books its carried-in cargo at nought, once.
-- (3) TWO REAL MINUTES AT HOME. `route_rest_voyage_days` is set from the live compression so the
--     rest is 120 real seconds (1.333333 voyage-days at 960x; 0115 made it 600). The pacing
--     interval (a lap may START game_day_seconds / npc_laps_per_game_day = 480 s after the last
--     one STARTED) binds only on a lap shorter than 6 minutes. Merchant laps run for hours, so the
--     rest a merchant sees is the two minutes, and the pace is left alone.
--
-- SUPERSEDES: cmd.standing_route_close_lap (0092, 0093/0094 callers unchanged) — two hunks
-- sliced from its LIVE body. The knobs are values, not rules.
-- Self-asserts hold AS FOUND (0113); every probe rolls back.

do $guard$ begin perform set_config('statement_timeout', '20min', true); end $guard$;

-- ── 1. THE KNOBS ───────────────────────────────────────────────────────────────────────────────
update public.world_config set value = to_jsonb(0),
       description = '0116: what a merchant company pays of a lap''s running costs (wages, supplies, repairs) as a '
                     'fraction of what a player pays (public.running_cost_mult). 0: merchants are off Rank and their '
                     'money never reaches a player, so their costs are cosmetic. Players pay 1.'
 where key = 'npc_cost_mult';
update public.world_config
   set value = to_jsonb(round(120 * public.wc_num('time_compression') / 86400, 6)),
       description = '0116: a merchant''s rest at her home stop between laps, in VOYAGE-days (cmd.run_standing_route '
                     'converts through time_compression). Set so the rest is 120 real seconds — two minutes — at the '
                     'compression of the day it was written (960: 1.333333).'
 where key = 'route_rest_voyage_days';

-- ── 2. A LAP'S CLOSING STOCK ───────────────────────────────────────────────────────────────────
alter table public.standing_route_laps add column if not exists stock_out bigint not null default 0;
comment on column public.standing_route_laps.stock_out is
  '0116: the cargo aboard when the lap closed, at what it cost (ships.cargo × cargo_basis). The next '
  'lap''s net subtracts it as its stock_in, so a parcel is charged to the lap that sells it.';

create or replace function pg_temp.slice_0116(p_fn text, p_old text, p_new text)
returns void
language plpgsql
as $$
declare
  v_def text := replace(pg_get_functiondef(p_fn::regprocedure), E'\r', '');
  v_n   int  := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
begin
  if v_n <> 1 then
    raise exception '0116 self-assert FAIL: a hunk of % occurs % time(s), not once — the live body is not what this file was cut against: %',
      p_fn, v_n, left(p_old, 120);
  end if;
  execute replace(v_def, p_old, p_new);
end $$;

select pg_temp.slice_0116('cmd.standing_route_close_lap(uuid, timestamptz)',
$h$  v_wages  bigint;
$h$,
$h$  v_wages  bigint;
  v_out    bigint;   -- 0116: the cargo aboard at close, at cost
  v_in     bigint;   -- 0116: the previous closed lap's v_out
$h$);
select pg_temp.slice_0116('cmd.standing_route_close_lap(uuid, timestamptz)',
$h$  update public.standing_route_laps
     set closed_at = p_now, sold = v_sold, bought = v_bought, supplies = v_supp, repairs = v_rep,
         wages = v_wages, net = v_sold - v_bought - v_supp - v_rep - v_wages
   where id = l.id
$h$,
$h$  -- 0116: COST OF GOODS SOLD, NOT GOODS BOUGHT. The cargo aboard now, at what it cost, is carried
  -- out of this lap (stock_out) and into the next (its stock_in), so a lap that closes on arrival
  -- before its home SELL is not charged for cargo the next lap sells.
  select coalesce(round(sum((e.value)::text::numeric * (s.cargo_basis->>e.key)::numeric)), 0)
    into v_out
    from public.ships s cross join lateral jsonb_each(s.cargo) e
   where s.fleet_id = sr.fleet_id and jsonb_typeof(s.cargo_basis->e.key) = 'number'
     and jsonb_typeof(e.value) = 'number';
  select coalesce((select x.stock_out from public.standing_route_laps x
                    where x.route_id = p_route and x.closed_at is not null and x.lap_no < l.lap_no
                    order by x.lap_no desc limit 1), 0)
    into v_in;
  update public.standing_route_laps
     set closed_at = p_now, sold = v_sold, bought = v_bought, supplies = v_supp, repairs = v_rep,
         wages = v_wages, stock_out = v_out,
         net = v_sold - v_bought - v_supp - v_rep - v_wages + v_out - v_in
   where id = l.id
$h$);

-- ── 3. SELF-ASSERT ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_was_on boolean := public.npc_traders_on();
  v_rest_s numeric;
  v_route  uuid;
  v_fleet  uuid;
  v_lap    public.standing_route_laps%rowtype;
  v_out    bigint;
  v_in     bigint;
  v_good   text;
begin
  -- (a) THE KNOBS, read through their readers.
  if public.wc_num('npc_cost_mult') <> 0 or public.running_cost_mult(gen_random_uuid()) <> 1
     or public.running_cost_mult((select p.id from public.players p where p.is_npc order by p.id limit 1)) <> 0 then
    raise exception '0116 self-assert FAIL: running costs read % for a merchant and % for anyone else',
      public.running_cost_mult((select p.id from public.players p where p.is_npc order by p.id limit 1)),
      public.running_cost_mult(gen_random_uuid());
  end if;
  v_rest_s := public.wc_num('route_rest_voyage_days') * 86400 / public.wc_num('time_compression');
  if abs(v_rest_s - 120) > 1 then
    raise exception '0116 self-assert FAIL: a merchant rests % real seconds, not 120', v_rest_s;
  end if;

  -- (b) THE CLOSER, by behaviour, rolled back: a merchant route given an open lap and a parcel
  --     aboard at a known cost closes with stock_out = that cost, and its net is the identity above.
  select nf.route_id, nf.fleet_id into v_route, v_fleet
    from public.npc_fleets nf join public.standing_routes sr on sr.id = nf.route_id
   where sr.fleet_id = nf.fleet_id
   order by nf.roster_ord, nf.fleet_id limit 1;
  if v_route is null then
    -- A fresh chain: no merchant route is assigned (the switch ships dark). Assign one by hand,
    -- inside the rolled-back block below, so the closer is still asked.
    select nf.route_id, nf.fleet_id into v_route, v_fleet from public.npc_fleets nf
     where nf.route_id is not null order by nf.roster_ord, nf.fleet_id limit 1;
  end if;
  if v_route is null then
    raise exception '0116 self-assert FAIL: no merchant route to probe';
  end if;
  select g.code into v_good from public.goods g order by g.code limit 1;
  begin
    update public.standing_routes set fleet_id = v_fleet where id = v_route;
    -- the previous closed lap carried 700 out; this lap opens now with a 10-unit parcel at 50.
    insert into public.standing_route_laps (route_id, lap_no, started_at, closed_at, stock_out)
    values (v_route, 900000, now() - interval '2 hours', now() - interval '1 hour', 700);
    insert into public.standing_route_laps (route_id, lap_no, started_at)
    values (v_route, 900001, now()) returning * into v_lap;
    update public.standing_routes set lap_id = v_lap.id, lap_no = 900001 where id = v_route;
    update public.ships set cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb where fleet_id = v_fleet;
    update public.ships set cargo = jsonb_build_object(v_good, 10), cargo_basis = jsonb_build_object(v_good, 50)
     where id = (select s.id from public.ships s where s.fleet_id = v_fleet order by s.id limit 1);
    perform cmd.standing_route_close_lap(v_route, now());
    select * into v_lap from public.standing_route_laps where id = v_lap.id;
    if v_lap.closed_at is null or v_lap.stock_out is distinct from 500::bigint
       or v_lap.net is distinct from v_lap.sold - v_lap.bought - v_lap.supplies - v_lap.repairs - v_lap.wages + 500 - 700 then
      raise exception '0116 self-assert FAIL: the closer booked stock_out % and net % (sold % bought % wages %)',
        v_lap.stock_out, v_lap.net, v_lap.sold, v_lap.bought, v_lap.wages;
    end if;
    raise exception 'ROLLBACK_0116';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0116' then raise; end if;
  end;
  if public.npc_traders_on() is distinct from v_was_on
     or exists (select 1 from public.standing_route_laps where lap_no >= 900000) then
    raise exception '0116 self-assert FAIL: the probe world was not rolled back';
  end if;

  raise notice '0116 self-assert ok: A MERCHANT ALWAYS EARNS, AND RESTS TWO MINUTES. Merchant running '
    'costs x0 (players x1); rest % real s; a lap closing with a 10 x 50 parcel aboard booked stock_out '
    '500 and net = sold - bought - costs + 500 - 700 (the previous lap''s 700). Rolled back; switch as found (%).',
    round(v_rest_s), case when v_was_on then 'lit' else 'dark' end;
end $$;
