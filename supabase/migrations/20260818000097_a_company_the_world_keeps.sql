-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0097 — A COMPANY THE WORLD KEEPS
--        docs/NPC_TRADERS.md §1, §3.2, §4, §5, §6, §9, §11 "0097". The merchant machinery: the
--        switch and its knobs, what the world knows about a merchant company and fleet, the ONE
--        founding (npc_found), the ONE planner (npc_plan), the upkeep (npc_tend), the retention
--        (npc_compact), the earnings reading, and Rank's exclusion. DARK: npc_traders_enabled =
--        false, and no merchant company exists after this file (0098 founds them).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE ONE PREDICATE ──────────────────────────────────────────────────────────────────────────
-- "Is this a merchant?" is `players.is_npc` (0096) and nothing else. `npc_houses` / `npc_fleets`
-- are WORLD DATA about a merchant (its ink, master, blurb, capital, patience, wares, roster order,
-- which route is which fleet's, its alternate loop) — never a predicate: every reader below joins
-- `players p … and p.is_npc`, and a trigger refuses a row for a company that is not one.
-- `npc_fleets` is one row per merchant FLEET (the plan's `npc_houses.alt_loop` and roster order are
-- per fleet, because a company sails up to two loops; docs/NPC_TRADERS.md §14 records the split).
--
-- ── COMPOSED, NEVER FORKED ─────────────────────────────────────────────────────────────────────
--   * A merchant trades through the ONE executor, by standing routes: tick_arrivals ->
--     voyage.settle -> cmd.advance -> cmd.run_standing_route -> do_sail/do_buy/do_sell/… No
--     function in this file moves a ship, fills an order, prices a good or touches a voyage.
--   * npc_found composes the 0096 cores (new_house, form_fleet, commission_ship, raise_skill,
--     sign_officer, the preset and route cores) and inserts only its own world data.
--   * npc_plan ranks with THE ranking (world.trade_routes, 0019:676, server-only since 0071:176),
--     filters its rows (the house's wares; one merchant buyer per (port, good)), sizes each parcel
--     with the quote authority's OWN p_limit walk at the sink (world.quote … 'sell', p_limit), and
--     writes lines only through cmd.standing_route_save_for.
--   * npc_tend uses only the route cores, cmd.clear_for + cmd.advance (the release a repaired
--     fleet gets), public.credit for a refound, and cmd.standing_route_set_paused's events.
--
-- ── WHAT THIS FILE SUPERSEDES (sliced from pg_get_functiondef, hunks once each, reverse parity) ─
--   public.settle_standings(timestamptz)  one hunk: `where not p.is_npc` — merchants are off Rank,
--                                          and player_progress's whole-ledger scans stay off them.
--   public.forbid_mutation()              one hunk: DELETE is allowed only when the transaction-
--                                          local GUC byeharu.npc_compact = 'on' (set by npc_compact
--                                          alone) AND the row's company is a merchant. Clients hold
--                                          no DELETE grant on events/ledger (0001), so the GUC alone
--                                          opens nothing; the second test means even the compactor
--                                          cannot touch a player's row.
--   public.tick_reconcile()               two hunks: UPKEEP FIRST (npc_tend, npc_plan, npc_compact,
--                                          each in its own subtransaction, lock_timeout 2 s), THEN
--                                          its unchanged invariant asserts — which therefore judge
--                                          the world after upkeep. 0010's header said the reconcile
--                                          "reads only"; that is superseded here and said again in
--                                          the function's comment.
--   world_config.standing_route_lap_keep  30 -> 200 (a 6-laps-a-game-day merchant keeps a real day).
--
-- ── WHO READS public.players WITHOUT A KEY (the next reader added is a visible decision) ───────
--   tick_reconcile (0010:144)       KEEP — merchants must reconcile too (the carried row is how).
--   settle_standings (0025:247)     FILTER — re-cut here.
--   npc_* (this file)               FILTER by is_npc, by construction.
--   probes and RLS policies         n/a.
--
-- ── DARK FIRST ─────────────────────────────────────────────────────────────────────────────────
-- npc_traders_enabled = false. Every merchant path asks public.npc_traders_on() and nothing else;
-- off, npc_plan does nothing and npc_tend pauses every assigned merchant route 'dark'. The owner's
-- one action, after the soak numbers are in DEV_LOG: `select public.npc_traders_switch(true);`
--
-- Depends on: 0004, 0005, 0010, 0019, 0025, 0034, 0092-0096.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── 1. THE SWITCH AND ITS KNOBS ────────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('npc_traders_enabled', 'false'::jsonb,
   '0097: the dark-first switch for merchant companies (docs/NPC_TRADERS.md §9). false = merchant routes '
   'are paused dark, world.sea_traffic / world.npc_fleet_card answer nothing. Flip with '
   'public.npc_traders_switch(true), never by hand: the switch also tends at once.'),
  ('npc_fleet_max', to_jsonb(120),
   '0097: how many merchant fleets may sail, in roster order; the rest stay dark. The live lever if the sea looks crowded. '
   'Raised from 40 to 120 on 2026-10-10: the owner read the map and said the sea must look busy, so the roster was grown '
   'threefold (docs/NPC_TRADERS.md §3.2) and a cap of 40 would have left two thirds of it dark.'),
  ('npc_laps_per_game_day', to_jsonb(6),
   '0097: the pace every merchant route is saved with (an interval of game_day_seconds / N between lap starts).'),
  ('npc_lines_per_stop', to_jsonb(3),
   '0097: how many goods the planner buys at one stop, at most.'),
  ('npc_min_return_pct', to_jsonb(2),
   '0097: a floor against noise — a kept good must return at least this % on its outlay.'),
  ('npc_sell_margin', to_jsonb(0.05),
   '0097: the parcel is what the SINK takes above the probe''s cost × (1 + this).'),
  ('npc_min_net_to_wages', to_jsonb(0.2),
   '0097: the build step''s steady-state trim: mean lap net ≥ this × mean lap wages.'),
  ('npc_price_patience_max', to_jsonb(0.30),
   '0097: the highest patience a company may carry (its BUY ceiling = normal ask × (1 + patience)).'),
  ('npc_purse_floor_pct', to_jsonb(0.20),
   '0097: below capital × this, a company is refounded (bounded by the cooldown and the weekly cap).'),
  ('npc_refound_cooldown_game_days', to_jsonb(30),
   '0097: game-days between refounds of one company (30 = one real day).'),
  ('npc_refound_max_per_week', to_jsonb(3),
   '0097: refounds a company may take in 7 real days; at the cap it is laid up and changes to its alternate loop.'),
  ('npc_laid_up_hours', to_jsonb(6),
   '0097: real hours a laid-up merchant route waits before the upkeep tries it again.'),
  ('npc_retention_hours', to_jsonb(6),
   '0097: merchant books (voyages, ledger, events, orders, trade_daily) are compacted past this window.'),
  ('npc_row_budget', to_jsonb(100000),
   '0097: the retained merchant rows proof 12 and the soak must stay under.'),
  ('npc_crew_pool_floor', to_jsonb(25),
   '0097: hands a merchant leaves standing in a port. She hires only out of ports.crew_pool ABOVE this, '
   'so a player always finds this many whatever the merchants have done — the pool is regenerated by no '
   'tick (docs/NPC_TRADERS.md §13), and every merchant stop carries crew_up. A player''s HIRE is untouched.');

update public.world_config set value = to_jsonb(200)
 where key = 'standing_route_lap_keep';

create or replace function public.npc_traders_on()
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select public.wc('npc_traders_enabled') = 'true'::jsonb and public.standing_routes_on()
$$;
comment on function public.npc_traders_on() is
  '0097: THE one reading of the merchant switch. A merchant needs routes, so routes must be on too.';

-- ── 2. WHAT THE WORLD KNOWS ABOUT A MERCHANT ───────────────────────────────────────────────────
create table public.npc_houses (
  player_id    uuid primary key references public.players(id) on delete cascade,
  roster_ord   int not null unique,
  ink          text not null check (ink in ('prt', 'esp', 'nld', 'eng', 'han', 'ita', 'ott', 'east')),
  blurb        text not null check (length(btrim(blurb)) between 8 and 240),
  master       text not null check (length(btrim(master)) between 3 and 60),
  home_port_id uuid not null references public.ports(id),
  capital      bigint not null check (capital > 0),
  patience     numeric not null check (patience >= 0.05 and patience <= 0.30),
  wares        text[] not null default '{}',
  created_at   timestamptz not null default now()
);
comment on table public.npc_houses is
  '0097: world data about a merchant company (docs/NPC_TRADERS.md §3.2). NEVER a predicate: '
  '"is this a merchant?" is players.is_npc.';

create table public.npc_fleets (
  fleet_id   uuid primary key references public.fleets(id) on delete cascade,
  player_id  uuid not null references public.npc_houses(player_id) on delete cascade,
  route_id   uuid unique references public.standing_routes(id) on delete set null,
  roster_ord int not null unique,
  alt_loop   jsonb check (alt_loop is null or jsonb_typeof(alt_loop) = 'array')
);
comment on table public.npc_fleets is
  '0097: world data about a merchant FLEET: which standing route is hers, her roster order '
  '(npc_fleet_max counts in it) and the runner-up loop she changes to at the refound cap.';

create or replace function public.tg_npc_is_a_merchant()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not exists (select 1 from public.players p where p.id = new.player_id and p.is_npc) then
    raise exception 'E_NOT_A_MERCHANT: % rows describe merchant companies only', tg_table_name using errcode = '23514';
  end if;
  return new;
end $$;
create trigger npc_houses_are_merchants before insert or update on public.npc_houses
  for each row execute function public.tg_npc_is_a_merchant();
create trigger npc_fleets_are_merchants before insert or update on public.npc_fleets
  for each row execute function public.tg_npc_is_a_merchant();

-- World data the server reads; no client reads or writes these tables (the reads are 0099's).
alter table public.npc_houses enable row level security;
alter table public.npc_fleets enable row level security;
revoke all on public.npc_houses from public, anon, authenticated;
revoke all on public.npc_fleets from public, anon, authenticated;

-- ── 3. THE MARKET BOUND: a BUY ceiling anchored to the port's NORMAL price (§4.3) ──────────────
create or replace function public.npc_buy_ceiling(p_port uuid, p_good uuid, p_patience numeric)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- The ask now, carried to the stock the port is SUPPOSED to hold, times (1 + patience). Composed of
-- the two price authorities' own answers (world.quote for the ask with its spread and tax,
-- world.mid_price for the stock term); no spread, tax or elasticity is restated. At stock = target
-- the ceiling IS the ask × (1 + patience), to the cent (asserted below). Null = no honest ceiling
-- (nothing to quote), and the planner then does not buy that good.
declare
  q        record;
  v_stock  numeric;
  v_target numeric;
  v_now    numeric;
  v_norm   numeric;
begin
  select pg.stock, pg.stock_target into v_stock, v_target
    from public.port_goods pg where pg.port_id = p_port and pg.good_id = p_good;
  if v_target is null then return null; end if;
  select * into q from world.quote(p_port, p_good, 1, 'buy', null, null);
  v_now  := world.mid_price(p_port, p_good, v_stock);
  v_norm := world.mid_price(p_port, p_good, v_target);
  if q.units is null or q.units <= 0 or q.avg_price is null or v_now is null or v_now <= 0 then
    return null;
  end if;
  return round(q.avg_price * v_norm / v_now * (1 + coalesce(p_patience, 0)), 2);
end $$;

-- ── 4. EARNINGS — the laps' own sums, per fleet (§7.4) ─────────────────────────────────────────
create or replace function public.route_earnings(p_route uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- THE ONE earnings reading. Laps, never the ledger: a lap is per fleet and holds the executor's
  -- own sums (sold, bought, supplies, repairs, wages OWED, net); the ledger is per company and is
  -- compacted for merchants. `day` = Σ net of laps closed in the last 24 real hours; `day_full`
  -- says whether a whole real day of laps is held (the card prints "so far today" until it is).
  --
  -- WHY `lap` NEEDS TWO CLOSED LAPS, which is a fact about the lap boundary and not a nicety.
  -- A lap closes on arrival at the home stop (0092's one closer), BEFORE that stop's own SELL
  -- lines run — so the cargo a leg buys on lap N is sold on lap N+1. Lap 1 therefore holds a
  -- purchase and no sale and is a large loss by construction (a probe merchant read −116,690 on a
  -- lap whose cargo fetched +139,165 the next lap), lap 2..N each hold one sale and one purchase
  -- and are the honest figure, and the open leg's cargo is in no lap at all. One closed lap can
  -- say what that lap's books did; it cannot say what a lap EARNS. So LAP 1 IS NOT AVERAGED AT ALL —
  -- moving the threshold to two laps was not enough, because the poisoned lap stayed inside the
  -- seven-lap window and dragged the figure with it (a probe route with nets [-10397, +7532]
  -- printed -1433 a lap for a steady +7532: the 2026-10-10 review). `lap` is the mean of the closed
  -- laps FROM THE SECOND ONWARDS, null until one of those exists, and `lap_basis` says how many it
  -- stands on. Shifting the boundary
  -- itself would change what every PLAYER's route history means and is not this slice's to do —
  -- recorded in docs/NPC_TRADERS.md §7.4 and docs/OWNER_REQUESTS.md.
  select jsonb_build_object(
    'day',       coalesce((select sum(x.net) from public.standing_route_laps x
                            where x.route_id = p_route and x.closed_at > now() - interval '24 hours'), 0),
    'day_laps',  (select count(*) from public.standing_route_laps x
                   where x.route_id = p_route and x.closed_at > now() - interval '24 hours'),
    'day_since', (select min(x.closed_at) from public.standing_route_laps x
                   where x.route_id = p_route and x.closed_at > now() - interval '24 hours'),
    'day_full',  exists (select 1 from public.standing_route_laps x
                          where x.route_id = p_route and x.closed_at <= now() - interval '24 hours'),
    'lap',       (select case when count(*) >= 1 then round(avg(y.net)) end
                    from (select x.net from public.standing_route_laps x
                   where x.route_id = p_route and x.closed_at is not null and x.lap_no >= 2
                   order by x.lap_no desc limit 7) y),
    'lap_basis', (select count(*) from (select 1 from public.standing_route_laps x
                   where x.route_id = p_route and x.closed_at is not null and x.lap_no >= 2
                   order by x.lap_no desc limit 7) y),
    'laps_recent', coalesce((select jsonb_agg(y.net order by y.lap_no desc) from (select x.net, x.lap_no
                   from public.standing_route_laps x where x.route_id = p_route and x.closed_at is not null
                   order by x.lap_no desc limit 7) y), '[]'::jsonb),
    'laps_done', coalesce((select max(x.lap_no) from public.standing_route_laps x
                            where x.route_id = p_route and x.closed_at is not null), 0))
$$;

-- ── 5. THE FOUNDING — composed of the 0096 cores (§3, §11 "0098") ───────────────────────────────
create or replace function public.npc_found(p_spec jsonb)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- ONE merchant company, founded through the authorities a player's company is made by. The spec
-- (0098's generated literal) names: company (+ alt_company), nation, ink, master, blurb, capital,
-- patience, wares, skills {code: level}, roster_ord, and fleets [{name, roster_ord, home, days,
-- ships [{class, name}] (the first is her flagship), officers [codes], stops [{port, course}],
-- alt_stops}]. Purse after founding = capital: the house is founded with capital + every officer's
-- wage + every level's tuition, and those are then PAID through the same credit calls the player
-- verbs make. The ships are endowed, as every player's Gaivota is (0004:308). The route is saved
-- with its stops, courses, crew_up, repair at stop 0 and the merchant pace — and NO lines, and is
-- NOT assigned (assigning sails): npc_tend assigns it when the switch is on.
-- This body inserts into no table but npc_houses and npc_fleets (asserted).
declare
  v_name    text;
  v_player  uuid;
  v_fleet   uuid;
  v_route   uuid;
  v_preset  uuid;
  v_fl      jsonb;
  v_sh      jsonb;
  v_off     text;
  v_stops   jsonb;
  v_st      jsonb;
  v_res     jsonb;
  v_wages   bigint := 0;
  v_tuition bigint := 0;
  v_skill   record;
  v_lvl     int;
  v_k       int;
  v_i       int;
  v_home    text;
begin
  -- THE NAME: the first spelling that is free, said which; both taken is a raise, never silence.
  v_name := p_spec->>'company';
  if exists (select 1 from public.players where company_name = v_name) then
    v_name := p_spec->>'alt_company';
    if v_name is null or exists (select 1 from public.players where company_name = v_name) then
      raise exception 'E_NAME_TAKEN: both spellings of "%" are taken', p_spec->>'company' using errcode = 'P0001';
    end if;
    raise notice 'npc_found: "%" is taken; founded as "%"', p_spec->>'company', v_name;
  end if;

  select coalesce(sum(o.wage_ducats), 0) into v_wages
    from public.officers o
   where o.code in (select jsonb_array_elements_text(f->'officers') from jsonb_array_elements(p_spec->'fleets') f);
  for v_skill in select key as code, value::text::int as level from jsonb_each(coalesce(p_spec->'skills', '{}'::jsonb)) loop
    v_tuition := v_tuition + public.wc_int('skill_study_base_cost') * (v_skill.level * (v_skill.level + 1) / 2);
  end loop;

  v_fl := p_spec->'fleets'->0;
  v_home := v_fl->'stops'->0->>'port';
  v_player := public.new_house(null, v_name, p_spec->>'nation', v_home, v_fl->>'name',
                               v_fl->'ships'->0->>'class', v_fl->'ships'->0->>'name',
                               (p_spec->>'capital')::bigint + v_wages + v_tuition, true);

  insert into public.npc_houses (player_id, roster_ord, ink, blurb, master, home_port_id, capital, patience, wares)
  values (v_player, (p_spec->>'roster_ord')::int, p_spec->>'ink', p_spec->>'blurb', p_spec->>'master',
          (select id from public.ports where code = v_home), (p_spec->>'capital')::bigint,
          (p_spec->>'patience')::numeric,
          coalesce((select array_agg(x) from jsonb_array_elements_text(p_spec->'wares') x), '{}'));

  -- SKILLS: the company's levels, paid level by level through the academy's core.
  for v_skill in select key as code, value::text::int as level from jsonb_each(coalesce(p_spec->'skills', '{}'::jsonb)) loop
    for v_lvl in 1 .. v_skill.level loop
      v_res := public.raise_skill(v_player, v_skill.code, v_home);
      if not coalesce((v_res->>'ok')::boolean, false) then
        raise exception 'npc_found: % could not study %: %', v_name, v_skill.code, v_res;
      end if;
    end loop;
  end loop;

  for v_k in 0 .. jsonb_array_length(p_spec->'fleets') - 1 loop
    v_fl := p_spec->'fleets'->v_k;
    if v_k = 0 then
      select id into v_fleet from public.fleets where player_id = v_player;
    else
      v_fleet := public.form_fleet(v_player, v_fl->>'name',
                                   (select id from public.ports where code = v_fl->'stops'->0->>'port'));
      perform public.commission_ship(v_player, v_fleet, v_fl->'ships'->0->>'class', v_fl->'ships'->0->>'name', true, true);
    end if;
    for v_i in 1 .. jsonb_array_length(v_fl->'ships') - 1 loop
      v_sh := v_fl->'ships'->v_i;
      perform public.commission_ship(v_player, v_fleet, v_sh->>'class', v_sh->>'name', false, true);
    end loop;

    -- OFFICERS: signed and posted to this fleet, paid through the one mover.
    for v_off in select jsonb_array_elements_text(coalesce(v_fl->'officers', '[]'::jsonb)) loop
      v_res := public.sign_officer(v_player, v_off, v_fleet);
      if not coalesce((v_res->>'ok')::boolean, false) then
        raise exception 'npc_found: % could not sign %: %', v_name, v_off, v_res;
      end if;
    end loop;

    -- SUPPLIES: the fleet's standing order, through the preset cores.
    v_res := cmd.provision_preset_save_for(v_player, null, left(v_fl->>'name', 24), (v_fl->>'days')::int);
    v_preset := (v_res->>'id')::uuid;
    if v_preset is null then
      raise exception 'npc_found: % could not keep supplies: %', v_fl->>'name', v_res;
    end if;
    perform cmd.provision_preset_apply_for(v_player, v_fleet, v_preset);

    -- THE ROUTE: stops and courses, crew_up everywhere, repair at home, the merchant pace, no lines.
    v_stops := '[]'::jsonb;
    for v_i in 0 .. jsonb_array_length(v_fl->'stops') - 1 loop
      v_st := v_fl->'stops'->v_i;
      v_stops := v_stops || jsonb_build_object('port', v_st->>'port', 'course', v_st->'course',
                                               'repair', v_i = 0, 'crew_up', true, 'lines', '[]'::jsonb);
    end loop;
    v_res := cmd.standing_route_save_for(v_player, null, left(v_fl->>'name', 24), v_stops, 0, null,
                                         public.wc_int('npc_laps_per_game_day'));
    v_route := (v_res->>'id')::uuid;
    if v_route is null then
      raise exception 'npc_found: the route of % was refused: %', v_fl->>'name', v_res;
    end if;

    insert into public.npc_fleets (fleet_id, player_id, route_id, roster_ord, alt_loop)
    values (v_fleet, v_player, v_route, (v_fl->>'roster_ord')::int, v_fl->'alt_stops');
  end loop;

  if (select ducats from public.players where id = v_player) <> (p_spec->>'capital')::bigint then
    raise exception 'npc_found: % ends with % in its purse, not its capital %', v_name,
      (select ducats from public.players where id = v_player), p_spec->>'capital';
  end if;
  return v_player;
end $$;

-- ── 6. THE ONE PLANNER (§4.1) ──────────────────────────────────────────────────────────────────
create or replace function public.npc_plan(p_now timestamptz default now(), p_route uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- Writes each merchant route's LINES from the market, through cmd.standing_route_save_for with the
-- SAME stops and courses. For every stop i bound for stop j:
--   1. RANK with THE ranking (world.trade_routes, port_i to port_j, twelve rows) — priced end to end
--      through world.quote. Server-only since 0071:176; this is its only live caller.
--   2. FILTER its rows: the house's authored wares first (all rows only when no listed good
--      passes), and ONE MERCHANT BUYER PER (port, good) — in an hourly pass, the routes planned
--      EARLIER IN THIS PASS (a temp table, so the previous hour's lines of a later route never
--      block an earlier one); for one route re-planned alone, every other merchant route's lines.
--   3. SIZE each kept good with the quote authority's own answer: how many units the SINK takes
--      above the probe's cost × (1 + npc_sell_margin) — a sell-side world.quote at port_j for cap units WITH a limit,
--      the p_limit walk (0005:442-448) — cap = the cap authority at both ends and the hold left.
--      KEEP it only if the two quotes at that size pay more than the leg's wages (crew_wages × the
--      leg's sea-days) and return ≥ npc_min_return_pct on the outlay. The first npc_lines_per_stop.
--   4. WRITE: SELL everything above cost; SELL <good> ALL for a good refused E_PRICE_LIMIT on a
--      SELL here in BOTH of the last two closed laps (the cut-loss); BUY <good> <q> AT <ceiling>.
-- A route with no paying good on ANY leg is laid up (the upkeep tries again after
-- npc_laid_up_hours). The hourly pass starts at roster index (hour mod n), so no house is
-- structurally last. Routes paused 'error' or 'laid_up' are SKIPPED by the hourly pass (the save
-- door bumps updated_at, which dates the pause); npc_tend re-plans one alone before it resumes it.
-- Locks fleet then route, NOWAIT: a busy route is skipped this hour, never waited for.
declare
  v_k       int     := public.wc_int('npc_lines_per_stop');
  v_margin  numeric := public.wc_num('npc_sell_margin');
  v_minret  numeric := public.wc_num('npc_min_return_pct');
  v_pace    int     := public.wc_int('npc_laps_per_game_day');
  v_hour    bigint  := floor(extract(epoch from p_now) / 3600)::bigint;
  r         record;
  st        record;
  e         jsonb;
  sr        public.standing_routes%rowtype;
  h         public.npc_houses%rowtype;
  v_n       int;
  v_stops   jsonb;
  v_lines   jsonb;
  v_rows    jsonb;
  v_hold    numeric;
  v_left    numeric;
  v_crew    int;
  v_speed   numeric;
  v_wages   numeric;
  v_good    uuid;
  v_bulk    numeric;
  v_cap     numeric;
  v_q       numeric;
  v_ceiling numeric;
  q_size    record;
  q_sell    record;
  q_buy     record;
  v_kept    int;
  v_any     boolean;
  v_pass    int;
  v_cut     text;
  v_res     jsonb;
  v_planned int := 0;
  v_laid    int := 0;
  v_busy    int := 0;
  v_failed  int := 0;
  v_notes   jsonb := '[]'::jsonb;
begin
  if not public.npc_traders_on() then
    return jsonb_build_object('enabled', false);
  end if;
  -- (checked first, so the hourly pass does not print "already exists" once per route)
  if to_regclass('pg_temp.npc_plan_buyers') is null then
    create temporary table npc_plan_buyers (port_id uuid, good_id uuid, primary key (port_id, good_id))
      on commit drop;
  end if;
  if p_route is null then
    delete from npc_plan_buyers;
  end if;

  for r in
    with m as (
      select nf.fleet_id, nf.route_id, nf.roster_ord,
             row_number() over (order by nf.roster_ord) - 1 as k,
             count(*) over () as n
        from public.npc_fleets nf
        join public.players p on p.id = nf.player_id and p.is_npc
        join public.standing_routes sr0 on sr0.id = nf.route_id
       where (p_route is null and coalesce(sr0.paused_reason, '') not in ('error', 'laid_up'))
          or nf.route_id = p_route)
    select * from m order by (m.k - (v_hour % greatest(m.n, 1)) + m.n) % greatest(m.n, 1)
  loop
    begin
      -- FLEET BEFORE ROUTE, and never wait (§4.5).
      perform 1 from public.fleets where id = r.fleet_id for update nowait;
      select * into sr from public.standing_routes where id = r.route_id for update nowait;
      select * into h from public.npc_houses where player_id = sr.player_id;
      select count(*) into v_n from public.standing_route_stops where route_id = sr.id;
      select coalesce(sum(c.crew_required), 0), coalesce(sum(public.ship_cargo_tuns(s.id)), 0)
        into v_crew, v_hold
        from public.ships s join public.ship_classes c on c.id = s.class_id
       where s.fleet_id = r.fleet_id;
      v_hold  := v_hold + public.fleet_free_hold(r.fleet_id);
      v_speed := greatest(coalesce(voyage.fleet_speed(r.fleet_id), 0), 0.1);
      v_stops := '[]'::jsonb;
      v_any   := false;

      for st in select s.ord, s.port_id, p.code, s.course,
                       (select s2.port_id from public.standing_route_stops s2
                         where s2.route_id = s.route_id and s2.ord = (s.ord + 1) % v_n) as next_port
                  from public.standing_route_stops s join public.ports p on p.id = s.port_id
                 where s.route_id = sr.id order by s.ord loop
        v_lines := jsonb_build_array(jsonb_build_object('kind', 'SELL', 'at_profit', true));

        -- THE CUT-LOSS: refused E_PRICE_LIMIT on a SELL here in BOTH of the last two closed laps.
        for v_cut in
          select z.g from (
            select split_part(x.e->>'line', ' ', 2) as g, count(distinct x.lap_no) as laps
              from (select l.lap_no, jsonb_array_elements(l.skipped) as e
                      from (select lp.lap_no, lp.skipped from public.standing_route_laps lp
                             where lp.route_id = sr.id and lp.closed_at is not null
                             order by lp.lap_no desc limit 2) l) x
             where x.e->>'port' = st.code and x.e->>'verb' = 'SELL' and x.e->>'code' = 'E_PRICE_LIMIT'
             group by 1) z
           where z.laps = 2 and exists (select 1 from public.goods g where g.code = z.g)
           order by z.g limit 2 loop
          v_lines := v_lines || jsonb_build_object('kind', 'SELL', 'good', v_cut);
        end loop;

        -- RANK, FILTER, SIZE, KEEP.
        v_rows  := coalesce(world.trade_routes(st.port_id, null, null, 12, st.next_port)->'routes', '[]'::jsonb);
        v_left  := v_hold;
        v_kept  := 0;
        v_wages := public.crew_wages(v_crew, false)
                   * coalesce((v_rows->0->>'nm')::numeric, 0) / (v_speed * 24);
        for v_pass in 1 .. 2 loop
          exit when v_pass = 2 and v_kept > 0;
          for e in select x from jsonb_array_elements(v_rows) x loop
            exit when v_kept >= v_k;
            v_good := (e->>'good_id')::uuid;
            continue when v_pass = 1 and not ((e->>'code') = any(h.wares));
            continue when v_lines @> jsonb_build_array(jsonb_build_object('kind', 'BUY', 'good', e->>'code'));
            continue when p_route is null and exists (select 1 from npc_plan_buyers b where b.port_id = st.port_id and b.good_id = v_good);
            continue when p_route is not null and exists (
              select 1 from public.standing_route_lines l
                join public.standing_route_stops s3 on s3.route_id = l.route_id and s3.ord = l.stop_ord
                join public.standing_routes sr3 on sr3.id = l.route_id
                join public.players p3 on p3.id = sr3.player_id and p3.is_npc
               where l.route_id <> sr.id and l.kind = 'BUY' and l.good_id = v_good and s3.port_id = st.port_id);
            select g.bulk into v_bulk from public.goods g where g.id = v_good;
            v_cap := floor(least(world.daily_cap_remaining(sr.player_id, st.port_id, v_good),
                                 world.daily_cap_remaining(sr.player_id, st.next_port, v_good),
                                 v_left / greatest(v_bulk, 0.001)));
            continue when v_cap is null or v_cap < 1;
            -- THE SIZE is the sink's own answer: units it takes above the probe's cost plus the margin.
            select * into q_size from world.quote(st.next_port, v_good, v_cap, 'sell',
                                                  round((e->>'buy_price')::numeric * (1 + v_margin), 2), null);
            v_q := floor(coalesce(q_size.units, 0));
            continue when v_q < 1;
            select * into q_buy from world.quote(st.port_id, v_good, v_q, 'buy', null, null);
            continue when q_buy.units is null or q_buy.units < v_q or q_buy.total <= 0;
            select * into q_sell from world.quote(st.next_port, v_good, v_q, 'sell', null, null);
            continue when q_sell.total - q_buy.total - v_wages <= 0
                       or (q_sell.total - q_buy.total) * 100 < v_minret * q_buy.total;
            v_ceiling := public.npc_buy_ceiling(st.port_id, v_good, h.patience);
            continue when v_ceiling is null;
            v_lines := v_lines || jsonb_build_object('kind', 'BUY', 'good', e->>'code', 'qty', v_q,
                                                     'price_limit', v_ceiling);
            insert into npc_plan_buyers (port_id, good_id) values (st.port_id, v_good) on conflict do nothing;
            v_left := v_left - v_q * v_bulk;
            v_kept := v_kept + 1;
            v_any  := true;
          end loop;
        end loop;

        v_stops := v_stops || jsonb_build_object('port', st.code, 'course', st.course,
                                                 'repair', st.ord = 0, 'crew_up', true, 'lines', v_lines);
      end loop;

      if not v_any then
        -- (re)laid up, which also re-dates the pause: the upkeep tries again npc_laid_up_hours on.
        perform cmd.standing_route_pause_for(sr.player_id, sr.id, true, 'laid_up',
          'No cargo pays on any leg of this route at present.');
        v_laid := v_laid + 1;
      else
        v_res := cmd.standing_route_save_for(sr.player_id, sr.id, null, v_stops, null, null, v_pace);
        if not coalesce((v_res->>'ok')::boolean, false) then
          raise exception 'npc_plan: the save door refused % — %', sr.name, v_res->>'error_message';
        end if;
        v_planned := v_planned + 1;
      end if;
    exception
      when lock_not_available then
        v_busy := v_busy + 1;
      when others then
        v_failed := v_failed + 1;
        v_notes := v_notes || jsonb_build_object('route', r.route_id, 'error', sqlerrm);
    end;
  end loop;

  return jsonb_build_object('enabled', true, 'planned', v_planned, 'laid_up', v_laid,
                            'busy', v_busy, 'failed', v_failed, 'notes', v_notes, 'start', v_hour);
end $$;

-- ── 7. THE UPKEEP (§4.5) ───────────────────────────────────────────────────────────────────────
create or replace function public.npc_tend(p_now timestamptz default now(), p_route uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- What the world does for a merchant that a player would do by hand — through the route cores,
-- cmd.clear_for + cmd.advance, and public.credit; nothing else. Per route, fleet then route locked
-- NOWAIT inside its own subtransaction (a busy route is skipped, counted, never waited for):
--   switch OFF, or beyond npc_fleet_max in roster order -> paused 'dark' (fleets at sea finish
--     their leg and lie in port).
--   ADRIFT / UNABLE_TO_SAIL -> laid up (there is no RECALL or salvage verb for anybody).
--   not started -> planned, then assigned where she lies (assigning starts the loop).
--   paused dark/losing/reserve/edited -> planned, then resumed. laid_up -> the same after
--     npc_laid_up_hours, and whether THIS call re-planned her is read off the plan's receipt, not
--     off updated_at (the save bumps it). error -> the same after 6 h (the pause is dated by updated_at, which the
--     hourly plan does not touch: it skips error routes). off_route -> re-assigned if she lies at
--     a stop; otherwise reported.
--   a FAILED order at the head of her queue (the halt law) -> cmd.clear_for, then cmd.advance —
--     COUNTED: the third clear with no lap closed between lays the route up, the code in the
--     sentence, so a merchant that cannot crew or sail stops burning the tick.
-- Then per company: purse below capital × npc_purse_floor_pct -> refounded (NPC_REFOUND through
-- the one mover; at most once per cooldown and npc_refound_max_per_week a week). At the weekly cap
-- the company is laid up and each fleet's route is re-cut to its alternate loop instead.
declare
  v_on      boolean := public.npc_traders_on();
  v_max     int     := public.wc_int('npc_fleet_max');
  v_laid    interval := make_interval(hours => public.wc_int('npc_laid_up_hours'));
  r         record;
  hh        record;
  sr        public.standing_routes%rowtype;
  f         public.fleets%rowtype;
  fo        public.orders%rowtype;
  v_res     jsonb;
  v_clears  int;
  v_last    timestamptz;
  v_week    int;
  v_alt     jsonb;
  v_stops   jsonb;
  v_n       int;
  v_dark    int := 0;
  v_started int := 0;
  v_resumed int := 0;
  v_cleared int := 0;
  v_laid_n  int := 0;
  v_refound int := 0;
  v_busy    int := 0;
  v_failed  int := 0;
  v_notes   jsonb := '[]'::jsonb;
begin
  for r in select nf.fleet_id, nf.route_id, nf.player_id, nf.alt_loop,
                  row_number() over (order by nf.roster_ord) as k
             from public.npc_fleets nf
             join public.players p on p.id = nf.player_id and p.is_npc
            where nf.route_id is not null
            order by nf.roster_ord loop
    continue when p_route is not null and r.route_id <> p_route;
    begin
      perform 1 from public.fleets where id = r.fleet_id for update nowait;
      select * into sr from public.standing_routes where id = r.route_id for update nowait;
      select * into f from public.fleets where id = r.fleet_id;

      if not v_on or r.k > v_max then
        if sr.fleet_id is not null and sr.paused_reason is distinct from 'dark' then
          perform cmd.standing_route_pause_for(sr.player_id, sr.id, true, 'dark', 'The merchants keep to port.');
          v_dark := v_dark + 1;
        end if;
        continue;
      end if;

      if f.status in ('ADRIFT', 'UNABLE_TO_SAIL') then
        if sr.paused_reason is distinct from 'laid_up' then
          perform cmd.standing_route_pause_for(sr.player_id, sr.id, true, 'laid_up',
            format('%s cannot sail on.', f.name));
          v_laid_n := v_laid_n + 1;
        end if;
        continue;
      end if;

      -- A PAUSE THE WORLD MAY LIFT, and only when it may: dark/losing/reserve/edited at once;
      -- laid_up after npc_laid_up_hours; error after 6 h (updated_at dates the pause — the hourly
      -- plan skips error routes, so it cannot keep the date fresh). off_route re-assigns where she
      -- lies, if that is a stop. 'player' is never a merchant's.
      --
      -- updated_at DATES A PAUSE ONLY WHILE NOTHING HAS WRITTEN THE ROUTE SINCE. That holds for
      -- 'error' (the plan skips those) and it is what the ageing test below reads; it does NOT hold
      -- after the plan has saved — see the receipt test further down.
      if sr.paused_reason = 'off_route' then
        if f.status = 'DOCKED'
           and exists (select 1 from public.standing_route_stops s where s.route_id = sr.id and s.port_id = f.port_id) then
          v_res := cmd.standing_route_assign_for(sr.player_id, sr.id, r.fleet_id);
          v_resumed := v_resumed + 1;
        else
          v_notes := v_notes || jsonb_build_object('route', sr.name, 'off_route', f.status);
        end if;
        continue;
      end if;
      if sr.paused_reason is not null
         and not (sr.paused_reason in ('dark', 'losing', 'reserve', 'edited')
                  or (sr.paused_reason = 'laid_up' and sr.updated_at < p_now - v_laid)
                  or (sr.paused_reason = 'error' and sr.updated_at < p_now - interval '6 hours')) then
        continue;
      end if;

      -- NOT STARTED, OR A PAUSE TO LIFT: plan first (the lines are the market's NOW), then start
      -- her where she lies, or resume her. The plan may lay her up (nothing pays): then she waits.
      if sr.fleet_id is null or sr.paused_reason is not null then
        if sr.paused_reason = 'error' then
          v_notes := v_notes || jsonb_build_object('route', sr.name, 'resumed_after_error', true);
        end if;
        v_res := public.npc_plan(p_now, sr.id);
        select * into sr from public.standing_routes where id = r.route_id;
        -- DID THIS PLAN LAY HER UP? THE PLAN'S OWN RECEIPT SAYS SO — NEVER updated_at. The save
        -- door (cmd.standing_route_save_for) sets updated_at = now(), so after a SUCCESSFUL plan an
        -- `updated_at >= p_now - v_laid` test is always true at p_now = now(): it skipped every
        -- laid-up route it had just re-planned, the resume and start branches below were
        -- unreachable for that reason, and every merchant laid up for want of cargo stayed laid up
        -- for ever (found by the 2026-10-08 review; the ageing test above still gates WHEN she is
        -- re-planned at all). `planned` is this call's own count, and p_route pins the call to this
        -- one route, so planned = 0 means she was NOT re-planned — laid up again (nothing pays),
        -- busy, or failed — and she waits. Both arms are acceptable outcomes (NO_SPAGHETTI §7C):
        -- resume on fresh lines, or wait; she is never resumed on stale ones.
        --
        -- AND THAT HOLDS FOR EVERY PAUSE, not only 'laid_up' (the 2026-10-10 review): a dark or
        -- losing route whose plan RAISED would otherwise have been resumed on week-old lines, which
        -- is the very thing the sentence above claims never happens. Counted in the notes, so a
        -- route that is never planned is visible in the receipt rather than silently stuck.
        if coalesce((v_res->>'planned')::int, 0) = 0 then
          v_notes := v_notes || jsonb_build_object('route', sr.name, 'not_planned', coalesce(sr.paused_reason, 'unstarted'));
          continue;
        end if;
        if sr.fleet_id is null then
          if f.status = 'DOCKED' then
            v_res := cmd.standing_route_assign_for(sr.player_id, sr.id, r.fleet_id);
            if coalesce((v_res->>'ok')::boolean, false) then
              v_started := v_started + 1;
            else
              v_notes := v_notes || jsonb_build_object('route', sr.name, 'start', v_res->>'error_code');
            end if;
          end if;
        elsif sr.paused_reason is not null then
          v_res := cmd.standing_route_pause_for(sr.player_id, sr.id, false);
          v_resumed := v_resumed + 1;
        end if;
        continue;
      end if;

      -- THE HALT LAW'S RELEASE, counted: clears with no lap closed between share her lap number.
      select * into fo from public.orders where fleet_id = r.fleet_id and status = 'failed' order by seq limit 1;
      if fo.id is not null then
        select count(*) + 1 into v_clears from public.events ev
         where ev.player_id = sr.player_id and ev.kind = 'NPC_CLEARED'
           and ev.payload->>'route_id' = sr.id::text and (ev.payload->>'lap_no')::int = sr.lap_no;
        perform public.emit_event(sr.player_id, 'NPC_CLEARED', jsonb_build_object(
          'route', sr.name, 'route_id', sr.id, 'lap_no', sr.lap_no, 'fleet', f.name,
          'code', fo.error_code, 'line', fo.raw_text, 'n', v_clears));
        if v_clears >= 3 then
          perform cmd.standing_route_pause_for(sr.player_id, sr.id, true, 'laid_up',
            format('%s stopped three times running (%s).', f.name, fo.error_code));
          v_laid_n := v_laid_n + 1;
        else
          perform cmd.clear_for(sr.player_id, r.fleet_id, false);
          perform cmd.advance(r.fleet_id, p_now);
          v_cleared := v_cleared + 1;
        end if;
      end if;
    exception
      when lock_not_available then
        v_busy := v_busy + 1;
      when others then
        v_failed := v_failed + 1;
        v_notes := v_notes || jsonb_build_object('route', r.route_id, 'error', sqlerrm);
    end;
  end loop;

  -- REFOUNDS, per company, only while the switch is on.
  if v_on and p_route is null then
    for hh in select h.player_id, h.capital, pl.ducats, pl.company_name
                from public.npc_houses h join public.players pl on pl.id = h.player_id and pl.is_npc
               where pl.ducats < h.capital * public.wc_num('npc_purse_floor_pct')
               order by h.roster_ord loop
      begin
        select max(ev.created_at), count(*) filter (where ev.created_at > p_now - interval '7 days')
          into v_last, v_week
          from public.events ev where ev.player_id = hh.player_id and ev.kind = 'NPC_REFOUNDED';
        continue when v_last is not null
          and v_last > p_now - make_interval(secs => (public.wc_num('npc_refound_cooldown_game_days')
                                                       * public.wc_num('game_day_seconds'))::double precision);
        if coalesce(v_week, 0) >= public.wc_int('npc_refound_max_per_week') then
          -- AT THE CAP: the market has stopped paying this loop. Laid up, and re-cut to the
          -- alternate loop (the same door, the same courses authority); the old loop becomes the
          -- alternate, so the next cap swaps back.
          for r in select nf.fleet_id, nf.route_id, nf.alt_loop from public.npc_fleets nf
                    where nf.player_id = hh.player_id and nf.route_id is not null loop
            select * into sr from public.standing_routes where id = r.route_id;
            if r.alt_loop is not null and jsonb_array_length(r.alt_loop) >= 2 then
              select jsonb_agg(jsonb_build_object('port', p.code, 'course', s.course) order by s.ord)
                into v_alt from public.standing_route_stops s join public.ports p on p.id = s.port_id
               where s.route_id = sr.id;
              select jsonb_agg(jsonb_build_object('port', a->>'port', 'course', a->'course',
                                                  'repair', i = 1, 'crew_up', true, 'lines', '[]'::jsonb) order by i)
                into v_stops from jsonb_array_elements(r.alt_loop) with ordinality t(a, i);
              v_res := cmd.standing_route_save_for(hh.player_id, sr.id, null, v_stops, null, null, null);
              if coalesce((v_res->>'ok')::boolean, false) then
                update public.npc_fleets set alt_loop = v_alt where fleet_id = r.fleet_id;
              end if;
            end if;
            perform cmd.standing_route_pause_for(hh.player_id, sr.id, true, 'laid_up',
              'Refounded too often this week; the company changes its loop.');
            v_laid_n := v_laid_n + 1;
          end loop;
        else
          perform public.credit(hh.player_id, 'NPC_REFOUND', hh.capital - hh.ducats,
            public.emit_event(hh.player_id, 'NPC_REFOUNDED', jsonb_build_object(
              'company', hh.company_name, 'amount', hh.capital - hh.ducats, 'week', coalesce(v_week, 0) + 1)));
          v_refound := v_refound + 1;
        end if;
      exception when others then
        v_failed := v_failed + 1;
        v_notes := v_notes || jsonb_build_object('company', hh.company_name, 'error', sqlerrm);
      end;
    end loop;
  end if;

  return jsonb_build_object('enabled', v_on, 'dark', v_dark, 'started', v_started, 'resumed', v_resumed,
                            'cleared', v_cleared, 'laid_up', v_laid_n, 'refounded', v_refound,
                            'busy', v_busy, 'failed', v_failed, 'notes', v_notes);
end $$;

-- ── 8. RETENTION — merchant books only (§5.2) ──────────────────────────────────────────────────
create or replace function public.npc_compact(p_now timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- Players' books stay append-only for ever. A merchant's are compacted to a rolling window:
--   voyages (not SAILING, ended before the window, not read by the fleet's OPEN lap; their
--   voyage_events cascade), ledger (rolled into ONE `NPC_CARRIED` row per company — THE ONE PLACE
--   a ledger row is written other than public.credit; assert_ledger_reconciles runs right after,
--   so a wrong roll-up raises and rolls back), events (not of a kept kind, not referenced by a
--   remaining ledger row), trade_daily (past game-days), orders (done/skipped, past the window).
-- The append-only trigger lets the deletes through ONLY with byeharu.npc_compact = 'on'
-- (transaction-local, set here and nowhere else) AND only for a merchant's row (0097's
-- forbid_mutation hunk).
declare
  v_cut     timestamptz := p_now - make_interval(hours => public.wc_int('npc_retention_hours'));
  hh        record;
  v_n       int;
  v_sum     bigint;
  v_bal     bigint;
  v_at      timestamptz;
  v_voy     int := 0;
  v_led     int := 0;
  v_ev      int := 0;
  v_td      int := 0;
  v_ord     int := 0;
begin
  -- OFF IS INERT (§9 "Off: nothing moves"), AND THE COMPACTOR IS NOT AN EXCEPTION. It is gated
  -- exactly like npc_plan and npc_tend. Without this gate tick_reconcile called it every hour from
  -- the moment 0098 landed, so six hours after the deploy — while npc_traders_enabled was still
  -- false — it would have rolled the 23 seeded companies' FOUNDING / OFFICER_WAGE / TUITION rows
  -- into one NPC_CARRIED row each, exercising the append-only ledger's DELETE exemption on
  -- production before the owner had flipped anything (found by the 2026-10-08 review). Residual
  -- un-compacted rows after a switch-off are bounded: off means nothing moves, so nothing is
  -- written to compact, and the next ON resumes the rolling window.
  if not public.npc_traders_on() then
    return jsonb_build_object('enabled', false);
  end if;
  perform set_config('byeharu.npc_compact', 'on', true);

  delete from public.voyages v
   using public.fleets f, public.players p
   where v.fleet_id = f.id and f.player_id = p.id and p.is_npc
     and v.status <> 'SAILING' and v.eta < v_cut
     and not exists (select 1 from public.orders o
                       join public.standing_routes sr on sr.lap_id = o.route_lap_id
                      where o.verb = 'SAIL' and o.status = 'done'
                        and (o.result->>'voyage_id')::uuid = v.id);
  get diagnostics v_voy = row_count;

  delete from public.orders o
   using public.players p
   where o.player_id = p.id and p.is_npc
     and o.status in ('done', 'skipped', 'cancelled') and coalesce(o.executed_at, o.issued_at) < v_cut
     and not exists (select 1 from public.standing_routes sr where sr.lap_id = o.route_lap_id);
  get diagnostics v_ord = row_count;

  delete from public.trade_daily td
   using public.players p
   where td.player_id = p.id and p.is_npc and td.game_day < world.game_day(p_now);
  get diagnostics v_td = row_count;

  for hh in select p.id from public.players p where p.is_npc order by p.id loop
    select count(*), coalesce(sum(l.ducats_delta), 0), max(l.created_at)
      into v_n, v_sum, v_at
      from public.ledger l where l.player_id = hh.id and l.created_at < v_cut;
    if v_n >= 2 then
      -- THE CARRIED ROW'S RUNNING BALANCE IS COMPUTED, NOT PICKED. Every row written inside one
      -- tick shares created_at (= the transaction's now()), so `order by created_at desc` has no
      -- tie-break that means "last": picking the highest balance_after among the last tick's rows
      -- returned the wrong running balance (+500 then -700 in one transaction carried 104,500 on a
      -- purse of 103,800), and assert_ledger_reconciles checks only Σ delta, so nothing raised
      -- (found by the 2026-10-08 review). The balance after the LAST collapsed row is the purse
      -- now, less every delta booked after the cut — exact by construction, whatever the order
      -- inside a tick.
      select p.ducats - coalesce((select sum(l2.ducats_delta) from public.ledger l2
                                   where l2.player_id = hh.id and l2.created_at >= v_cut), 0)
        into v_bal from public.players p where p.id = hh.id;
      delete from public.ledger l where l.player_id = hh.id and l.created_at < v_cut;
      insert into public.ledger (player_id, kind, ducats_delta, balance_after, ref_event_id, created_at)
      values (hh.id, 'NPC_CARRIED', v_sum, v_bal, null, v_at);
      perform public.assert_ledger_reconciles(hh.id);
      v_led := v_led + v_n;
    end if;
    delete from public.events ev
     where ev.player_id = hh.id and ev.created_at < v_cut
       and ev.kind not in ('FOUNDED', 'NPC_REFOUNDED', 'SIGNED_OFFICER', 'STUDIED')
       and not exists (select 1 from public.ledger l where l.ref_event_id = ev.id);
    get diagnostics v_n = row_count;
    v_ev := v_ev + v_n;
  end loop;

  perform set_config('byeharu.npc_compact', 'off', true);
  return jsonb_build_object('voyages', v_voy, 'ledger_rolled', v_led, 'events', v_ev,
                            'trade_daily', v_td, 'orders', v_ord, 'before', v_cut);
end $$;

-- ── 9. THE ONE SWITCH (§9) ─────────────────────────────────────────────────────────────────────
create or replace function public.npc_traders_switch(p_on boolean)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- THE switch: writes the flag, then plans and tends at once, so merchants put to sea within the
-- minute (the arrivals job takes them from there). false is the reverse, and is how an incident is
-- stopped: one statement. Server-only — the owner runs it in the SQL editor.
declare
  v_plan jsonb;
begin
  update public.world_config set value = to_jsonb(coalesce(p_on, false)) where key = 'npc_traders_enabled';
  if public.npc_traders_on() then
    v_plan := public.npc_plan(now());
  end if;
  return jsonb_build_object('enabled', public.npc_traders_on(), 'plan', v_plan, 'tend', public.npc_tend(now()));
end $$;

-- ── 10. THE RE-CUTS ────────────────────────────────────────────────────────────────────────────
create temporary table hunks_0097 (fn text not null, n int not null, old text not null, new text not null,
                                   primary key (fn, n));
insert into hunks_0097 values
('public.settle_standings(timestamptz)', 1,
$h$        from public.players p
       cross join lateral (select public.player_fame(p.id) as j) fm$h$,
$h$        from public.players p
       cross join lateral (select public.player_fame(p.id) as j) fm
       where not p.is_npc   -- 0097: merchant companies are not ranked (docs/NPC_TRADERS.md §6)$h$),
('public.forbid_mutation()', 1,
$h$begin
  raise exception '% is append-only: % is not permitted', tg_table_name, tg_op$h$,
$h$begin
  -- 0097: THE ONE EXEMPTION. A merchant's row may be DELETED by npc_compact alone: the GUC is set
  -- transaction-locally by that function and nowhere else, and the row must be a merchant's.
  if tg_op = 'DELETE'
     and current_setting('byeharu.npc_compact', true) = 'on'
     and exists (select 1 from public.players p where p.id = old.player_id and p.is_npc) then
    return old;
  end if;
  raise exception '% is append-only: % is not permitted', tg_table_name, tg_op$h$),
('cmd.do_hire(uuid, jsonb)', 1,
$h$  select crew_pool into v_pool from public.ports where id = f.port_id;
  v_norm := least(v_count, v_pool);$h$,
$h$  select crew_pool into v_pool from public.ports where id = f.port_id;
  -- 0097: A MERCHANT NEVER TAKES THE LAST HANDS OFF A QUAY — AND IS NEVER STRANDED FOR WANT OF
  -- THEM. The rule lives HERE, where the pool is drawn, and nowhere else. Only the hands ABOVE
  -- npc_crew_pool_floor are drawn from the quay for a merchant company; the rest of her ask is
  -- recruited at the URGENT rate, which costs crew_urgent_multiplier times as much and takes
  -- NOTHING off the quay — exactly what already happens to anyone hiring beyond the pool. So the
  -- quays players hire from cannot be drained by 32 merchant fleets re-crewing after raid losses
  -- (no tick regenerates crew_pool), and a merchant at a drained quay still sails, poorer.
  -- `v_pool` itself is left alone, so E_CREW_POOL below still means "this port has no hands at
  -- all" for everyone. A player''s HIRE is untouched.
  v_norm := least(v_count, case when exists (select 1 from public.players p where p.id = f.player_id and p.is_npc)
                                then greatest(0, v_pool - public.wc_int('npc_crew_pool_floor'))
                                else v_pool end);$h$),
('public.tick_reconcile()', 1,
$h$  v_grants int;
begin
  for r in select id from public.players loop$h$,
$h$  v_grants int;
  v_upkeep jsonb := '{}'::jsonb;   -- 0097
begin
  -- 0097: UPKEEP FIRST, each step in its own subtransaction, never waiting on a lock the minute
  -- tick holds (lock_timeout; the steps themselves lock NOWAIT) — and THEN the invariants below,
  -- unchanged, which therefore judge the world after upkeep touched it. A failed step is REPORTED
  -- in the receipt and rolled back alone; it cannot abort the reconcile or hide a broken purse.
  perform set_config('lock_timeout', '2s', true);
  begin
    v_upkeep := v_upkeep || jsonb_build_object('tend', public.npc_tend(now()));
  exception when others then
    v_upkeep := v_upkeep || jsonb_build_object('tend_error', sqlerrm);
  end;
  begin
    v_upkeep := v_upkeep || jsonb_build_object('plan', public.npc_plan(now()));
  exception when others then
    v_upkeep := v_upkeep || jsonb_build_object('plan_error', sqlerrm);
  end;
  begin
    v_upkeep := v_upkeep || jsonb_build_object('compact', public.npc_compact(now()));
  exception when others then
    v_upkeep := v_upkeep || jsonb_build_object('compact_error', sqlerrm);
  end;
  for r in select id from public.players loop$h$),
('public.tick_reconcile()', 2,
$h$  return jsonb_build_object('players_checked', v_n, 'sailing_invariant', 'ok', 'client_write_grants', 0);$h$,
$h$  return jsonb_build_object('players_checked', v_n, 'sailing_invariant', 'ok', 'client_write_grants', 0,
                            'merchant_upkeep', v_upkeep);   -- 0097$h$);

create temporary table defs_before_0097 as
  select f.fn, replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
         coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl
    from (select distinct fn from hunks_0097) as f(fn);

create or replace function pg_temp.recut_0097(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := replace(pg_get_functiondef(p_fn::regprocedure), E'\r', '');
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0097 where fn = p_fn order by n loop
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0097 slice: hunk % of % occurs % time(s), expected exactly 1 — the deployed body is not what this migration was generated against.',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0097(fn) from (select distinct fn from hunks_0097) x order by fn;

comment on function public.tick_reconcile() is
  '0097: no longer "reads only" (0010): it runs the merchant upkeep first (npc_tend, npc_plan, '
  'npc_compact), each contained, then asserts every purse, the sailing invariant and the grant wall.';

-- ── 11. THE TABLES THE COMPACTOR CHURNS ARE SWEPT AT ANY SIZE (the 0095 shape) ────────────────
alter table public.ledger        set (autovacuum_vacuum_scale_factor = 0, autovacuum_vacuum_threshold = 2000);
alter table public.events        set (autovacuum_vacuum_scale_factor = 0, autovacuum_vacuum_threshold = 2000);
alter table public.voyage_events set (autovacuum_vacuum_scale_factor = 0, autovacuum_vacuum_threshold = 2000);
alter table public.voyages       set (autovacuum_vacuum_scale_factor = 0, autovacuum_vacuum_threshold = 2000);
alter table public.trade_daily   set (autovacuum_vacuum_scale_factor = 0, autovacuum_vacuum_threshold = 2000);

-- ── 12. GRANTS: none of this is a client's ─────────────────────────────────────────────────────
revoke all on function public.npc_traders_on()                       from public, anon, authenticated;
revoke all on function public.tg_npc_is_a_merchant()                 from public, anon, authenticated;
revoke all on function public.npc_buy_ceiling(uuid, uuid, numeric)   from public, anon, authenticated;
revoke all on function public.route_earnings(uuid)                   from public, anon, authenticated;
revoke all on function public.npc_found(jsonb)                       from public, anon, authenticated;
revoke all on function public.npc_plan(timestamptz, uuid)            from public, anon, authenticated;
revoke all on function public.npc_tend(timestamptz, uuid)            from public, anon, authenticated;
revoke all on function public.npc_compact(timestamptz)               from public, anon, authenticated;
revoke all on function public.npc_traders_switch(boolean)            from public, anon, authenticated;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_auth    constant uuid := '00000000-0097-4000-8000-000000000001';
  c_fns     constant text[] := array['public.npc_traders_on()', 'public.npc_buy_ceiling(uuid, uuid, numeric)',
    'public.route_earnings(uuid)', 'public.npc_found(jsonb)', 'public.npc_plan(timestamptz, uuid)',
    'public.npc_tend(timestamptz, uuid)', 'public.npc_compact(timestamptz)', 'public.npc_traders_switch(boolean)'];
  v_fn      text;
  v_def     text;
  v_back    text;
  h         record;
  v_n       int;
  v_hits    text[];
  v_pc      text[];
  v_base    int;
  v_lis     uuid;
  v_fnc     uuid;
  v_good    uuid;
  v_code    text;
  v_good2   uuid;
  v_code2   text;
  v_leg     jsonb;
  v_back_c  jsonb;
  v_spec    jsonb;
  v_m1      uuid;
  v_m2      uuid;
  v_player  uuid;
  v_fleet   uuid;
  v_route   uuid;
  v_route2  uuid;
  v_q       numeric;
  v_exp     numeric;
  v_ceiling numeric;
  v_ask     numeric;
  v_stock   numeric;
  v_target  numeric;
  v_floor   numeric;
  v_res     jsonb;
  v_lines   jsonb;
  v_sum     bigint;
  v_purse   bigint;
  v_rows    int;
  v_led0    int;
  v_unlim   numeric;
  v_short   int;
  v_pfleet  uuid;
  v_ok      boolean;
begin
  -- (a) PARITY BY REVERSE SUBSTITUTION, ACLs unmoved.
  for v_fn in select distinct fn from hunks_0097 loop
    v_def := replace(pg_get_functiondef(v_fn::regprocedure), E'\r', '');
    v_back := v_def;
    for h in select * from hunks_0097 where fn = v_fn order by n desc loop
      v_n := (length(v_back) - length(replace(v_back, h.new, ''))) / length(h.new);
      if v_n <> 1 then
        raise exception '0097 self-assert FAIL: hunk % of % is in the new body % time(s), not once', h.n, v_fn, v_n;
      end if;
      v_back := replace(v_back, h.new, h.old);
    end loop;
    if v_back <> (select def from defs_before_0097 where fn = v_fn) or v_def = v_back then
      raise exception '0097 self-assert FAIL: % is not its pre-image plus only 0097''s hunks', v_fn;
    end if;
    if coalesce((select p.proacl::text from pg_proc p where p.oid = v_fn::regprocedure), '')
       is distinct from (select acl from defs_before_0097 where fn = v_fn) then
      raise exception '0097 self-assert FAIL: the re-cut moved the ACL of %', v_fn;
    end if;
  end loop;

  -- (b) NOTHING HERE IS A CLIENT'S.
  foreach v_fn in array c_fns loop
    if has_function_privilege('anon', v_fn, 'execute') or has_function_privilege('authenticated', v_fn, 'execute') then
      raise exception '0097 self-assert FAIL: a client role may execute %', v_fn;
    end if;
  end loop;
  if has_table_privilege('authenticated', 'public.npc_houses', 'select')
     or has_table_privilege('authenticated', 'public.npc_fleets', 'select') then
    raise exception '0097 self-assert FAIL: a client may read the merchant world data directly';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0097 self-assert FAIL: a client write grant, a client-executable writer or a read-wall gap';
  end if;

  -- (c) THE BODY SCANS, each after a positive control proves it can see.
  --   c1 upkeep and planner never write the executor's tables, and lock only NOWAIT;
  --   c2 the planner restates no price (no world.mid_price) and sizes with ONE limited 'sell' quote;
  --   c3 no live function spells "merchant" any other way than players.is_npc.
  create or replace function pg_temp.carrier_0097() returns void language plpgsql as
    'begin insert into public.orders select * from public.orders where false; perform 1 from public.fleets for update; end';
  select array_agg(x.f) into v_pc from (select 'pg_temp.carrier_0097()' as f,
         pg_get_functiondef('pg_temp.carrier_0097()'::regprocedure) as d) x
   where x.d ~ '(insert into public\.orders|update public\.voyages|update public\.port_goods|update public\.ships|insert into public\.ledger)'
     and x.d ~ 'for update(?! nowait)';
  if coalesce(array_length(v_pc, 1), 0) <> 1 then
    raise exception '0097 self-assert FAIL: the upkeep scan cannot see its own positive control';
  end if;
  drop function pg_temp.carrier_0097();
  select array_agg(x.f) into v_hits from (
    select fn as f, pg_get_functiondef(fn::regprocedure) as d
      from unnest(array['public.npc_tend(timestamptz, uuid)', 'public.npc_plan(timestamptz, uuid)']) fn) x
   where x.d ~ '(insert into public\.orders|update public\.voyages|update public\.port_goods|update public\.ships|insert into public\.ledger)'
      or x.d ~ 'for update(?! nowait)';
  if v_hits is not null then
    raise exception '0097 self-assert FAIL: the upkeep writes an executor table or waits on a lock: %', v_hits;
  end if;
  v_def := pg_get_functiondef('public.npc_plan(timestamptz, uuid)'::regprocedure);
  if strpos(v_def, 'world.mid_price') > 0
     or (length(v_def) - length(replace(v_def, '''sell'',', ''))) / length('''sell'',') <> 2
     or (length(v_def) - length(replace(v_def, 'world.trade_routes(', ''))) / length('world.trade_routes(') <> 1
     or v_def !~ 'world\.quote\(st\.next_port, v_good, v_cap, ''sell'',\s+round\(' then
    raise exception '0097 self-assert FAIL: npc_plan is a second ranking or a second price rule';
  end if;
  create or replace function pg_temp.carrier2_0097() returns boolean language sql as
    'select exists (select 1 from public.players where auth_uid is null)';
  select array_agg(p.oid::regprocedure::text) into v_pc
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where (n.nspname in ('cmd', 'world', 'public', 'voyage') or p.oid = 'pg_temp.carrier2_0097()'::regprocedure)
     and pg_get_functiondef(p.oid) ~* 'auth_uid\s+is\s+null' and p.prokind = 'f';
  if not exists (select 1 from unnest(coalesce(v_pc, '{}')) x where x like '%carrier2_0097%') then
    raise exception '0097 self-assert FAIL: the merchant-spelling scan cannot see its own positive control (%)', v_pc;
  end if;
  drop function pg_temp.carrier2_0097();
  select array_agg(p.oid::regprocedure::text) into v_hits
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('cmd', 'world', 'public', 'voyage') and p.prokind = 'f'
     and pg_get_functiondef(p.oid) ~* 'auth_uid\s+is\s+null';
  if v_hits is not null then
    raise exception '0097 self-assert FAIL: a live function spells "merchant" as auth_uid is null: %', v_hits;
  end if;

  -- (d) THE PROBES — merchants founded through npc_found, the real ticks; then rolled back.
  select count(*) into v_base from public.players;
  begin
    update public.world_config set value = to_jsonb(0.0) where key = 'hazard_p_max';
    update public.world_config set value = 'true'::jsonb where key = 'standing_routes_enabled';
    select id into v_lis from public.ports where code = 'LIS';
    select id into v_fnc from public.ports where code = 'FNC';
    select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
      into v_leg from public.sea_reaches a, public.sea_reaches b where a.code = 'LIS' and b.code = 'FNC';
    v_back_c := jsonb_build_array(v_leg->1, v_leg->0);

    -- THE BOUND, to the cent: at stock = target the ceiling is the ask × (1 + patience).
    select pg.good_id, g.code into v_good, v_code
      from public.port_goods pg join public.goods g on g.id = pg.good_id
     where pg.port_id = v_lis and public.port_offers(v_lis, pg.good_id) and pg.stock_target >= 100
       and exists (select 1 from public.port_goods q where q.port_id = v_fnc and q.good_id = pg.good_id)
       and not public.culture_refuses((select culture from public.ports where id = v_fnc), g.culture_mask)
     order by g.code limit 1;
    select pg.good_id, g.code into v_good2, v_code2
      from public.port_goods pg join public.goods g on g.id = pg.good_id
     where pg.port_id = v_lis and public.port_offers(v_lis, pg.good_id) and pg.stock_target >= 100 and pg.good_id <> v_good
       and exists (select 1 from public.port_goods q where q.port_id = v_fnc and q.good_id = pg.good_id)
       and not public.culture_refuses((select culture from public.ports where id = v_fnc), g.culture_mask)
     order by g.code limit 1;
    if v_good is null or v_good2 is null then
      raise exception '0097 self-assert FAIL: no two goods to probe Lisbon → Funchal with';
    end if;
    update public.port_goods set stock = stock_target where port_id = v_lis and good_id in (v_good, v_good2);
    select (world.quote(v_lis, v_good, 1, 'buy', null, null)).avg_price into v_ask;
    v_ceiling := public.npc_buy_ceiling(v_lis, v_good, 0.30);
    if v_ceiling is null or v_ceiling <> round(v_ask * 1.30, 2) then
      raise exception '0097 self-assert FAIL: at target stock the ceiling is %, not the ask % × 1.30', v_ceiling, v_ask;
    end if;

    -- A MERCHANT, founded through the one founding, on Lisbon ⇄ Funchal; FNC made a hungry sink.
    update public.port_goods set stock = greatest(1, round(stock_target * 0.15)) where port_id = v_fnc and good_id in (v_good, v_good2);
    -- precondition, set by the probe and checked: THE RANKING now names both goods Lisbon → Funchal.
    v_lines := world.trade_routes(v_lis, null, null, 12, v_fnc)->'routes';
    if not (v_lines @> jsonb_build_array(jsonb_build_object('code', v_code))
            and v_lines @> jsonb_build_array(jsonb_build_object('code', v_code2))) then
      raise exception '0097 self-assert FAIL: the probe market did not put % and % on the ranking: %', v_code, v_code2, v_lines;
    end if;
    v_spec := jsonb_build_object(
      'company', 'Casa de Ensaio', 'alt_company', 'Casa de Ensaio II', 'nation', 'PRT', 'ink', 'prt',
      'master', 'Capitão Probo', 'blurb', 'A probe company that exists for one transaction.',
      'capital', 60000, 'patience', 0.30, 'wares', jsonb_build_array(v_code2), 'roster_ord', 9001,
      'skills', jsonb_build_object('SEAMANSHIP', 2, 'NAVIGATION', 1),
      'fleets', jsonb_build_array(jsonb_build_object(
         'name', 'Ensaio Atlântico', 'roster_ord', 9001, 'days', 12,
         'ships', jsonb_build_array(jsonb_build_object('class', 'carlat', 'name', 'Prova Uma'),
                                    jsonb_build_object('class', 'carlat', 'name', 'Prova Duas')),
         'officers', jsonb_build_array((select code from public.officers order by bonus_pct desc, code limit 1)),
         'stops', jsonb_build_array(jsonb_build_object('port', 'LIS', 'course', v_leg),
                                    jsonb_build_object('port', 'FNC', 'course', v_back_c)),
         'alt_stops', jsonb_build_array(jsonb_build_object('port', 'LIS', 'course', v_leg),
                                        jsonb_build_object('port', 'FNC', 'course', v_back_c)))));
    v_m1 := public.npc_found(v_spec);
    select fleet_id, route_id into v_fleet, v_route from public.npc_fleets where player_id = v_m1;
    if not (select is_npc from public.players where id = v_m1)
       or (select ducats from public.players where id = v_m1) <> 60000
       or public.ledger_sum(v_m1) <> 60000
       or (select count(*) from public.ships where fleet_id = v_fleet) <> 2
       or (select count(*) from public.ships where fleet_id = v_fleet and is_flagship) <> 1
       or (select count(*) from public.player_officers where player_id = v_m1 and fleet_id = v_fleet) <> 1
       or (select level from public.player_skills ps join public.skills s on s.id = ps.skill_id
            where ps.player_id = v_m1 and s.code = 'SEAMANSHIP') <> 2
       or (select fleet_id from public.standing_routes where id = v_route) is not null
       or (select count(*) from public.standing_route_lines where route_id = v_route) <> 0
       or (select laps_per_game_day from public.standing_routes where id = v_route) <> public.wc_int('npc_laps_per_game_day') then
      raise exception '0097 self-assert FAIL: npc_found did not make the company it was asked for';
    end if;
    v_def := pg_get_functiondef('public.npc_found(jsonb)'::regprocedure);
    if (select count(*) from regexp_matches(v_def, 'insert into public\.([a-z_]+)', 'g') m where m[1] not in ('npc_houses', 'npc_fleets')) > 0 then
      raise exception '0097 self-assert FAIL: npc_found writes a game table by hand';
    end if;
    begin
      insert into public.npc_houses (player_id, roster_ord, ink, blurb, master, home_port_id, capital, patience)
      select id, 9999, 'prt', 'not a merchant at all', 'Nobody', v_lis, 1, 0.1 from public.players where not is_npc limit 1;
      raise exception '0097 self-assert FAIL: a player company was described as a merchant';
    exception when sqlstate '23514' then null;
    end;

    -- DARK: off, the planner plans nothing, the upkeep starts nothing, AND THE COMPACTOR ROLLS
    -- NOTHING. The third one is here because it was missing: tick_reconcile calls npc_compact every
    -- hour whether or not the switch is on, so an ungated compactor would have collapsed these
    -- companies' FOUNDING / OFFICER_WAGE / TUITION rows into one carried row each — on production,
    -- six hours after the deploy, while the merchants were still dark (§9 "Off: nothing moves").
    -- The row count is read FIRST so the claim cannot pass vacuously on an empty ledger.
    select count(*) into v_led0 from public.ledger l join public.players p on p.id = l.player_id where p.is_npc;
    if v_led0 < 2 then
      raise exception '0097 self-assert FAIL: no merchant ledger rows to keep while dark (%)', v_led0;
    end if;
    if (public.npc_plan(now())->>'enabled')::boolean or public.npc_tend(now())->>'started' <> '0'
       or (select fleet_id from public.standing_routes where id = v_route) is not null
       or coalesce((public.npc_compact(now() + interval '7 hours')->>'enabled')::boolean, true)
       or (select count(*) from public.ledger l join public.players p on p.id = l.player_id where p.is_npc) <> v_led0
       or exists (select 1 from public.ledger where kind = 'NPC_CARRIED') then
      raise exception '0097 self-assert FAIL: the merchant machinery moved while dark';
    end if;

    -- THE SWITCH flips and tends in one call: planned, assigned, at sea.
    v_res := public.npc_traders_switch(true);
    select jsonb_agg(jsonb_build_object('stop', l.stop_ord, 'kind', l.kind, 'good', g.code, 'qty', l.qty,
                                        'limit', l.price_limit) order by l.stop_ord, l.ord)
      into v_lines from public.standing_route_lines l left join public.goods g on g.id = l.good_id
     where l.route_id = v_route;
    if not public.npc_traders_on() or (v_res->'tend'->>'started')::int <> 1
       or (select fleet_id from public.standing_routes where id = v_route) is distinct from v_fleet
       or (select status from public.fleets where id = v_fleet) <> 'SAILING' then
      raise exception '0097 self-assert FAIL: the switch did not plan and start the merchant: % / lines %', v_res, v_lines;
    end if;
    -- THE WARES FILTER kept the listed good (v_code2) although the unlisted one may rank higher,
    -- and THE SIZE is the sink's own p_limit answer.
    if not (v_lines @> jsonb_build_array(jsonb_build_object('stop', 0, 'kind', 'BUY', 'good', v_code2))) then
      raise exception '0097 self-assert FAIL: the listed ware % was not bought at Lisbon: %', v_code2, v_lines;
    end if;
    if v_lines @> jsonb_build_array(jsonb_build_object('stop', 0, 'kind', 'BUY', 'good', v_code)) then
      raise exception '0097 self-assert FAIL: the planner bought an unlisted good while a listed one paid: %', v_lines;
    end if;
    select (l->>'qty')::numeric into v_q from jsonb_array_elements(v_lines) l
     where l->>'kind' = 'BUY' and l->>'good' = v_code2 and (l->>'stop')::int = 0;
    if v_q is null or v_q < 1 then
      raise exception '0097 self-assert FAIL: no sized parcel for %: %', v_code2, v_lines;
    end if;

    -- THE CEILING BINDS — PROVEN AT THE AUTHORITY THAT SIZES EVERY PARCEL, WITH ITS CONTROL.
    -- What stood here was a claim about a stock floor (target / (1 + patience)², less a step) that
    -- could not fail for the reason it gave: the planner's parcel is capped by
    -- world.daily_cap_remaining at daily_cap_fraction · target per company per game-day, so stock
    -- cannot reach that floor whether or not the BUY ceiling does anything, and nothing in it ever
    -- asked the ceiling a question (NO_SPAGHETTI §4; found by the 2026-10-08 review). The planner
    -- sizes with world.quote's own p_limit answer, so that is what is put under test: at target
    -- stock, a BUY for the whole target fills FEWER units with the ceiling than without it, and
    -- what it does fill was never dearer than the ceiling.
    update public.port_goods set stock = stock_target where port_id = v_lis and good_id = v_good2;
    select stock_target into v_target from public.port_goods where port_id = v_lis and good_id = v_good2;
    v_ceiling := public.npc_buy_ceiling(v_lis, v_good2, 0.30);
    select q.units into v_q    from world.quote(v_lis, v_good2, greatest(2, v_target), 'buy', v_ceiling, null) q;
    select q.units into v_unlim from world.quote(v_lis, v_good2, greatest(2, v_target), 'buy', null, null) q;
    if v_ceiling is null or v_q is null or v_unlim is null or v_q < 1 or v_q >= v_unlim
       or (select q.avg_price from world.quote(v_lis, v_good2, v_q, 'buy', null, null) q) > v_ceiling then
      raise exception '0097 self-assert FAIL: the BUY ceiling % did not bound the fill of % (% units at the ceiling, % without one, avg %)',
        v_ceiling, v_code2, v_q, v_unlim,
        (select q.avg_price from world.quote(v_lis, v_good2, greatest(1, v_q), 'buy', null, null) q);
    end if;
    -- AND THE CAP BOUNDS THE PARCEL THE PLANNER ACTUALLY WROTE, which is the other half of §4.3.
    -- (Asserting `daily_cap_remaining <= fraction × target` would restate that function's own
    -- definition and read no parcel at all — the same vacuity under a new name, caught by the
    -- 2026-10-10 review.) The probe route's own BUY line at Lisbon is measured against what the
    -- company could still take there when it was planned.
    select sum(l.qty) into v_q from public.standing_route_lines l
      join public.standing_route_stops s on s.route_id = l.route_id and s.ord = l.stop_ord
     where l.route_id = v_route and l.kind = 'BUY' and s.port_id = v_lis;
    if v_q is null or v_q < 1
       or v_q > public.wc_num('daily_cap_fraction') * v_target + 0.001 then
      raise exception '0097 self-assert FAIL: the planner wrote a parcel of % at Lisbon against a cap of % × %',
        v_q, public.wc_num('daily_cap_fraction'), v_target;
    end if;

    -- ONE MERCHANT BUYER PER (port, good): a second merchant on the same pair buys something else.
    v_spec := jsonb_set(jsonb_set(jsonb_set(jsonb_set(v_spec, '{company}', '"Casa de Prova Dois"'), '{alt_company}', '"Casa de Prova III"'),
                        '{roster_ord}', '9002'), '{fleets,0,roster_ord}', '9002');
    v_spec := jsonb_set(v_spec, '{fleets,0,name}', '"Ensaio Dois"');
    v_spec := jsonb_set(v_spec, '{fleets,0,ships}', jsonb_build_array(jsonb_build_object('class', 'carlat', 'name', 'Prova Tres')));
    v_m2 := public.npc_found(v_spec);
    select route_id into v_route2 from public.npc_fleets where player_id = v_m2;
    perform public.npc_plan(now());
    if exists (select 1 from public.standing_route_lines a join public.standing_route_lines b
                 on a.good_id = b.good_id and a.kind = 'BUY' and b.kind = 'BUY' and a.stop_ord = b.stop_ord
                where a.route_id = v_route and b.route_id = v_route2) then
      raise exception '0097 self-assert FAIL: two merchant routes buy one good at one port';
    end if;
    -- the hourly start index moves with the hour
    if (public.npc_plan(now())->>'start')::bigint = (public.npc_plan(now() + interval '1 hour')->>'start')::bigint then
      raise exception '0097 self-assert FAIL: the planning start does not move with the hour';
    end if;

    -- A LAP, AFK: the arrivals tick alone (passages rewound as the cron would see them).
    for v_n in 1 .. 4 loop
      update public.voyages set departed_at = departed_at - (eta - now()) - interval '1 minute', eta = now() - interval '1 minute'
       where fleet_id = v_fleet and status = 'SAILING';
      update public.standing_routes set hold_until = now() - interval '1 second' where id = v_route and hold_until is not null;
      perform public.tick_arrivals(now());
    end loop;
    if (select count(*) from public.standing_route_laps where route_id = v_route and closed_at is not null) < 1
       or exists (select 1 from public.events ev where ev.player_id = v_m1 and ev.kind in ('BOUGHT', 'SOLD')
                    and not exists (select 1 from public.orders o where o.fleet_id = v_fleet and o.route_lap_id is not null))
       or (public.route_earnings(v_route)->>'laps_done')::int < 1 then
      raise exception '0097 self-assert FAIL: the merchant closed no lap through the shared executor (laps %, earnings %)',
        (select count(*) from public.standing_route_laps where route_id = v_route), public.route_earnings(v_route);
    end if;
    if (public.route_earnings(v_route)->>'day')::bigint
       <> (select sum(net) from public.standing_route_laps where route_id = v_route and closed_at is not null) then
      raise exception '0097 self-assert FAIL: the day''s earnings are not the laps'' own sum';
    end if;

    -- RANK: a merchant more famous than a player is not on the board; the player is.
    v_player := public.new_house(c_auth, 'Casa do Jogador', 'PRT');
    delete from public.standings;
    if public.player_fame(v_m1)->>'total' is null then
      raise exception '0097 self-assert FAIL: no fame to compare';
    end if;
    perform public.settle_standings(now());
    if exists (select 1 from public.standings s join public.players p on p.id = s.player_id where p.is_npc)
       or not exists (select 1 from public.standings where player_id = v_player)
       or not exists (select 1 from public.players p where p.is_npc
                       and (public.player_fame(p.id)->>'total')::int >= (public.player_fame(v_player)->>'total')::int) then
      raise exception '0097 self-assert FAIL: Rank holds a merchant, lost the player, or the control was not famous';
    end if;

    -- THE COMPACTOR: cannot touch a player's row even with the GUC on; cannot touch a merchant's
    -- without it; rolls a merchant's old ledger into one carried row that still reconciles.
    perform set_config('byeharu.npc_compact', 'on', true);
    begin
      delete from public.ledger where player_id = v_player;
      raise exception '0097 self-assert FAIL: the compactor''s GUC opened a player''s ledger';
    exception when sqlstate '42501' then null;
    end;
    perform set_config('byeharu.npc_compact', 'off', true);
    begin
      delete from public.events where player_id = v_m1;
      raise exception '0097 self-assert FAIL: a merchant''s events were deleted without the compactor';
    exception when sqlstate '42501' then null;
    end;
    select ducats into v_purse from public.players where id = v_m1;
    v_res := public.npc_compact(now() + interval '7 hours');
    if (select count(*) from public.ledger where player_id = v_m1 and kind = 'NPC_CARRIED') <> 1
       or public.ledger_sum(v_m1) <> v_purse
       or (select ducats from public.players where id = v_m1) <> v_purse
       or (select balance_after from public.ledger where player_id = v_m1 and kind = 'NPC_CARRIED') <> v_purse
       or exists (select 1 from public.ledger where player_id = v_player and kind = 'NPC_CARRIED') then
      raise exception '0097 self-assert FAIL: the roll-up broke the books: % (purse %, ledger %, carried balance %)',
        v_res, v_purse, public.ledger_sum(v_m1),
        (select balance_after from public.ledger where player_id = v_m1 and kind = 'NPC_CARRIED');
    end if;
    -- THE CASE THAT USED TO GET IT WRONG, run on purpose: a CREDIT and a DEBIT inside ONE
    -- transaction. Both rows carry the same created_at (it is the transaction's now()), so the old
    -- `order by created_at desc, balance_after desc` picked the HIGHER balance — the +500 row —
    -- rather than the last one, and carried a running balance 700 above the purse. Nothing raised,
    -- because assert_ledger_reconciles only ever checked Σ delta. Computed from the purse, the
    -- carried balance cannot depend on an order that does not exist.
    perform public.credit(v_m1, 'PROBE', 500);
    perform public.credit(v_m1, 'PROBE', -700);
    select ducats into v_purse from public.players where id = v_m1;
    if (select max(balance_after) from public.ledger where player_id = v_m1) <= v_purse then
      raise exception '0097 self-assert FAIL: the probe did not leave a higher balance earlier in the tick (max %, purse %)',
        (select max(balance_after) from public.ledger where player_id = v_m1), v_purse;
    end if;
    v_res := public.npc_compact(now() + interval '14 hours');
    if (select balance_after from public.ledger where player_id = v_m1 and kind = 'NPC_CARRIED') <> v_purse
       or public.ledger_sum(v_m1) <> v_purse then
      raise exception '0097 self-assert FAIL: the carried balance is % and the purse is % (ledger %)',
        (select balance_after from public.ledger where player_id = v_m1 and kind = 'NPC_CARRIED'),
        v_purse, public.ledger_sum(v_m1);
    end if;

    -- ERROR IS LEFT ALONE BY THE PLAN, AND RESUMED ONCE BY THE UPKEEP AFTER SIX HOURS.
    perform cmd.standing_route_set_paused(v_route2, 'error', 'E_TEST', 'A probe error.');
    update public.standing_routes set updated_at = now() - interval '1 hour' where id = v_route2;
    perform public.npc_plan(now());
    if (select paused_reason from public.standing_routes where id = v_route2) <> 'error'
       or (select updated_at from public.standing_routes where id = v_route2) > now() - interval '50 minutes' then
      raise exception '0097 self-assert FAIL: the hourly plan touched a route paused in error';
    end if;
    perform public.npc_tend(now());
    if (select paused_reason from public.standing_routes where id = v_route2) <> 'error' then
      raise exception '0097 self-assert FAIL: the upkeep resumed an error before six hours';
    end if;
    update public.standing_routes set updated_at = now() - interval '7 hours' where id = v_route2;
    v_res := public.npc_tend(now());
    if (select paused_reason from public.standing_routes where id = v_route2) = 'error' then
      raise exception '0097 self-assert FAIL: the upkeep did not take up an error after seven hours: %', v_res;
    end if;

    -- LAID UP IS A PAUSE THE WORLD LIFTS AGAIN, WITH ITS POSITIVE CONTROL. This is the regression
    -- the 2026-10-08 review found: the upkeep decided "the plan laid her up just now" from
    -- updated_at, which the plan's own save had just set to now(), so a laid-up route was skipped
    -- for ever and the resume below was unreachable. Pinned to one route (p_route), so the counts
    -- read are this route's. The probe sets its own market both ways.
    if (select status from public.fleets where id = v_fleet) in ('ADRIFT', 'UNABLE_TO_SAIL') then
      raise exception '0097 self-assert FAIL: the probe fleet is %, which cannot test a lay-up that lifts',
        (select status from public.fleets where id = v_fleet);
    end if;
    -- NEGATIVE ARM FIRST: BOTH harbours are emptied, so no BUY can be quoted on either leg and the
    -- plan lays her up again. A route the world cannot pay for STAYS laid up. (Emptying only
    -- Lisbon is not enough, and the first run of this probe proved it: a port with no stock is a
    -- desperate SINK, so the Funchal → Lisbon leg still paid and she was rightly taken up. The
    -- planner needs something to BUY, and neither quay now has any.)
    update public.port_goods set stock = 0 where port_id in (v_lis, v_fnc);
    perform cmd.standing_route_set_paused(v_route, 'laid_up', null, 'A probe lay-up.');
    update public.standing_routes set updated_at = now() - interval '7 hours' where id = v_route;
    v_res := public.npc_tend(now(), v_route);
    if (select paused_reason from public.standing_routes where id = v_route) <> 'laid_up'
       or (v_res->>'resumed')::int <> 0 or (v_res->>'started')::int <> 0 then
      raise exception '0097 self-assert FAIL: the upkeep took up a route nothing pays for: % (reason %)',
        v_res, (select paused_reason from public.standing_routes where id = v_route);
    end if;
    -- POSITIVE ARM: the same route, the probe market put back — and the ranking is CHECKED, not
    -- assumed — is taken up by ONE pass, although the plan's save re-dates the pause.
    update public.port_goods set stock = stock_target where port_id in (v_lis, v_fnc);
    update public.port_goods set stock = greatest(1, round(stock_target * 0.15))
     where port_id = v_fnc and good_id in (v_good, v_good2);
    v_lines := world.trade_routes(v_lis, null, null, 12, v_fnc)->'routes';
    if not (v_lines @> jsonb_build_array(jsonb_build_object('code', v_code2))
            or v_lines @> jsonb_build_array(jsonb_build_object('code', v_code))) then
      raise exception '0097 self-assert FAIL: the probe market pays nothing Lisbon → Funchal, so the resume cannot be tested: %', v_lines;
    end if;
    update public.standing_routes set updated_at = now() - interval '7 hours' where id = v_route;
    v_res := public.npc_tend(now(), v_route);
    if (select paused_reason from public.standing_routes where id = v_route) is not null
       or (v_res->>'resumed')::int + (v_res->>'started')::int < 1 then
      raise exception '0097 self-assert FAIL: a laid-up route on a paying market was not taken up: % (reason %, updated %s ago)',
        v_res, (select paused_reason from public.standing_routes where id = v_route),
        round(extract(epoch from now() - (select updated_at from public.standing_routes where id = v_route)));
    end if;

    -- THREE CONSECUTIVE CLEARS LAY A ROUTE UP (a fleet that cannot sail stops burning the tick).
    -- Her route is held (so the release cannot start a lap and move her lap number): only the
    -- counting is under test.
    update public.standing_routes set hold_until = now() + interval '1 day' where id = v_route;
    for v_n in 1 .. 3 loop
      update public.orders set status = 'cancelled' where fleet_id = v_fleet and status in ('pending', 'failed');
      insert into public.orders (fleet_id, player_id, seq, raw_text, verb, args, status, error_code, route_lap_id)
      select v_fleet, v_m1, coalesce(max(seq), 0) + 1, 'SAIL TO FNC', 'SAIL', '{}'::jsonb, 'failed', 'E_CREW_SHORT', null
        from public.orders where fleet_id = v_fleet;
      update public.standing_routes set paused_reason = null where id = v_route;
      perform public.npc_tend(now());
    end loop;
    if (select paused_reason from public.standing_routes where id = v_route) <> 'laid_up'
       or (select count(*) from public.events where player_id = v_m1 and kind = 'NPC_CLEARED') <> 3 then
      raise exception '0097 self-assert FAIL: three clears did not lay the route up (reason %, % clear(s))',
        (select paused_reason from public.standing_routes where id = v_route),
        (select count(*) from public.events where player_id = v_m1 and kind = 'NPC_CLEARED');
    end if;

    -- THE REFOUND CAP: three in a week (a day apart, past the cooldown), then the fourth is not
    -- paid: the company is laid up and its loop changes to the alternate.
    update public.orders set status = 'cancelled' where fleet_id = v_fleet and status in ('pending', 'failed');
    update public.npc_fleets set alt_loop = jsonb_build_array(jsonb_build_object('port', 'LIS', 'course', v_leg),
                                                              jsonb_build_object('port', 'FNC', 'course', v_back_c))
     where fleet_id = v_fleet;
    for v_n in 1 .. 4 loop
      perform public.credit(v_m1, 'PROBE', -((select ducats from public.players where id = v_m1) - 100));
      v_res := public.npc_tend(now() + make_interval(days => v_n, mins => 1));
      if v_n <= 3 and (v_res->>'refounded')::int <> 1 then
        raise exception '0097 self-assert FAIL: refound % of the week did not happen: %', v_n, v_res;
      end if;
    end loop;
    if (select count(*) from public.events where player_id = v_m1 and kind = 'NPC_REFOUNDED') <> 3
       or (select paused_reason from public.standing_routes where id = v_route) <> 'laid_up' then
      raise exception '0097 self-assert FAIL: the fourth refound in a week was paid, or the company was not laid up (% refounds, %)',
        (select count(*) from public.events where player_id = v_m1 and kind = 'NPC_REFOUNDED'),
        (select paused_reason from public.standing_routes where id = v_route);
    end if;

    -- RECONCILE RUNS THE UPKEEP AND STILL ASSERTS.
    v_res := public.tick_reconcile();
    if v_res->'merchant_upkeep' is null or v_res->'merchant_upkeep'->'tend' is null
       or v_res->'merchant_upkeep'->'compact' is null then
      raise exception '0097 self-assert FAIL: reconcile did not run the upkeep: %', v_res;
    end if;
    begin
      update public.players set ducats = ducats + 1 where id = v_m1;
      perform public.tick_reconcile();
      raise exception '0097 self-assert FAIL: reconcile passed a falsified merchant purse';
    exception when others then
      if sqlerrm like '0097 self-assert FAIL%' then raise; end if;
    end;

    -- A MERCHANT LEAVES HANDS ON THE QUAY, AND IS NEVER STRANDED FOR WANT OF THEM (§13), WITH THE
    -- PLAYER AS THE CONTROL. The rule lives in cmd.do_hire, where the pool is drawn, so that is
    -- what is asked — three times, with Lisbon's pool moved under it. An earlier cut of this rule
    -- capped the HIRE line instead, which protected the quay and left a crew-short merchant unable
    -- to sail for ever (no tick regenerates crew_pool): the 2026-10-10 review.
    select id into v_pfleet from public.fleets where player_id = v_player order by created_at limit 1;
    update public.fleets set port_id = v_lis, status = 'DOCKED' where id in (v_fleet, v_pfleet);
    update public.ships set crew = greatest(0, crew - 10) where fleet_id in (v_fleet, v_pfleet);
    perform public.credit(v_m1, 'PROBE', 100000);
    perform public.credit(v_player, 'PROBE', 100000);
    if v_pfleet is null or public.fleet_crew_shortfall(v_fleet) < 5
       or public.fleet_crew_shortfall(v_pfleet) < 5 then
      raise exception '0097 self-assert FAIL: the crew probe has no room to hire (merchant %, player %)',
        public.fleet_crew_shortfall(v_fleet), public.fleet_crew_shortfall(v_pfleet);
    end if;

    -- (1) AT THE FLOOR: a merchant hires her five, the quay keeps every hand, and she pays the
    -- urgent rate for all five.
    update public.ports set crew_pool = public.wc_int('npc_crew_pool_floor') where id = v_lis;
    select ducats into v_purse from public.players where id = v_m1;
    v_res := cmd.do_hire(v_fleet, jsonb_build_object('count', 5));
    if (v_res->>'urgent')::int <> 5
       or (select crew_pool from public.ports where id = v_lis) <> public.wc_int('npc_crew_pool_floor')
       or (select ducats from public.players where id = v_m1)
          <> v_purse - round(5 * public.wc_num('hire_crew_rate') * public.wc_num('crew_urgent_multiplier'))::bigint then
      raise exception '0097 self-assert FAIL: at the floor a merchant took % hand(s) off the quay (pool %, receipt %)',
        5 - (v_res->>'urgent')::int, (select crew_pool from public.ports where id = v_lis), v_res;
    end if;

    -- (2) THREE HANDS ABOVE THE FLOOR: exactly those three come off the quay and the other two are
    -- urgent — so the floor is a floor, not a ban.
    update public.ports set crew_pool = public.wc_int('npc_crew_pool_floor') + 3 where id = v_lis;
    v_res := cmd.do_hire(v_fleet, jsonb_build_object('count', 5));
    if (v_res->>'urgent')::int <> 2
       or (select crew_pool from public.ports where id = v_lis) <> public.wc_int('npc_crew_pool_floor') then
      raise exception '0097 self-assert FAIL: three hands above the floor gave % urgent and left the pool at %',
        (v_res->>'urgent')::int, (select crew_pool from public.ports where id = v_lis);
    end if;

    -- (3) THE CONTROL: a PLAYER at the same quay, at the floor, draws from the pool as she always
    -- did and pays the ordinary rate. This is a merchant rule and nobody else's.
    update public.ports set crew_pool = public.wc_int('npc_crew_pool_floor') where id = v_lis;
    select ducats into v_purse from public.players where id = v_player;
    v_res := cmd.do_hire(v_pfleet, jsonb_build_object('count', 5));
    if (v_res->>'urgent')::int <> 0
       or (select crew_pool from public.ports where id = v_lis) <> public.wc_int('npc_crew_pool_floor') - 5
       or (select ducats from public.players where id = v_player)
          <> v_purse - round(5 * public.wc_num('hire_crew_rate'))::bigint then
      raise exception '0097 self-assert FAIL: the merchant crew rule reached a player: % (pool %)',
        v_res, (select crew_pool from public.ports where id = v_lis);
    end if;
    -- OFF AGAIN: every assigned merchant route is dark.
    v_res := public.npc_traders_switch(false);
    if public.npc_traders_on() or exists (select 1 from public.standing_routes sr join public.players p on p.id = sr.player_id
                                            where p.is_npc and sr.fleet_id is not null and sr.paused_reason is distinct from 'dark') then
      raise exception '0097 self-assert FAIL: switching off left a merchant route running: %', v_res;
    end if;

    raise exception using errcode = 'P0970', message = '0097 probe rollback';
  exception when sqlstate 'P0970' then
    null;
  end;

  if (select count(*) from public.players) <> v_base or exists (select 1 from public.players where is_npc)
     or exists (select 1 from public.npc_houses) or public.npc_traders_on() then
    raise exception '0097 self-assert FAIL: the probe leaked a company, or the switch is on';
  end if;
  if public.wc_int('standing_route_lap_keep') <> 200 then
    raise exception '0097 self-assert FAIL: the lap keep is %', public.wc_int('standing_route_lap_keep');
  end if;
  select count(*) into v_rows from pg_class c
   where c.oid in ('public.ledger'::regclass, 'public.events'::regclass, 'public.voyage_events'::regclass,
                   'public.voyages'::regclass, 'public.trade_daily'::regclass)
     and 'autovacuum_vacuum_scale_factor=0' = any(c.reloptions) and 'autovacuum_vacuum_threshold=2000' = any(c.reloptions);
  if v_rows <> 5 then
    raise exception '0097 self-assert FAIL: % of the five churned tables carry the sweep', v_rows;
  end if;

  raise notice '0097 self-assert ok: A COMPANY THE WORLD KEEPS. settle_standings, forbid_mutation and tick_reconcile reverse to their pre-images hunk by hunk, ACLs unmoved; every npc_* function, the ceiling and the earnings reading are server-only and the world data is unreadable to clients; the upkeep scan saw its positive control and found no executor write and no waiting lock in npc_tend or npc_plan; npc_plan names no mid_price, one ranking call and one limited sell quote; no live function spells a merchant as auth_uid is null (positive control seen). On probe merchants founded by npc_found (purse = capital, ships, flagship, officer, skills, a route with no lines): dark, nothing moved; the switch planned and started one in a call; the ceiling at target stock was the ask × 1.30 to the cent; the listed ware was bought over an unlisted one, sized by the sink; the BUY ceiling bound the fill where no limit did and the planner''s parcel stayed inside the daily cap; a merchant hired at the quay''s floor without taking a hand off it while a player drew from the pool as always; a laid-up route on a dead market stayed laid up and was taken up again the moment the market paid; the compactor rolled nothing while dark and carried an exact running balance; a second merchant took no shared (port, good); the planning start moved with the hour; the arrivals tick alone closed a lap whose net is the day''s earnings; Rank kept the player and not the merchant; the compactor could not open a player''s ledger with its GUC nor a merchant''s without it, and rolled the books into one carried row that reconciles; an error route was left by the plan and resumed once after seven hours; three clears laid a route up; three refounds a week were paid and the fourth laid the company up on its alternate loop; reconcile ran the upkeep and still caught a falsified purse; off made every merchant route dark. Rolled back; the switch ships OFF.';
end $$;
