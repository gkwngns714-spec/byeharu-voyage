-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0123 — A CITY BUILDS WITH OTHER PEOPLE'S MONEY
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER'S WORDS ───────────────────────────────────────────────────────────────────────────
-- 2026-10-15: *"by clicking a city, there should be another building called town hall, where you
-- click and can invest, and see who or what npcs invested."* Decisions (docs/ECONOMY_LOOP.md v3,
-- §3-§5): EVERYONE may invest — players docked at the harbour, merchants at any stop of their
-- loop, through the same door. A city pays coupons only from what it holds above its reserve. NOT
-- built: the mayor (top investor sets the tax), debt, aid, war.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) THE WORKS AND THE SHARES. public.city_works (port, kind) = a level 0..works_level_max and
--     the shares of the NEXT level sold so far; public.city_shares (port, kind, house) = what a
--     house holds and paid, the coupons accrued and not yet collected. Server-only tables.
-- (2) THE READERS. public.city_level(port, kind) — THE one reader of a level; public.works_factor
--     (1 at level 0, so every composed reader is byte-identical until a level is built);
--     public.works_share_price(level); public.city_offered(port, kind) (0 dark).
-- (3) THE DOOR. public.invest_for(house, port, kind, shares) — refuses E_NOT_OFFERED /
--     E_OVERSUBSCRIBED / E_INVEST_MIN / E_INSUFFICIENT_FUNDS with figures, then pay_city(SHARE)
--     through 0122's mover, the share register, subscribed += n, and a 100th share completes the
--     level. Skins cmd.invest / cmd.preview_invest (docked at that harbour, E_NOT_DOCKED); the
--     fulfil pair's envelope; not a queue verb.
-- (4) WHAT A LEVEL DOES — one hunk per reader, sliced from the LIVE body: docks (voyage.sail_refusal
--     admits max_draft + level / docks_draft_per_levels), market (world.daily_cap_remaining ×
--     works_factor; world.spread − spread_per_dev × level), production (public.tick_market_drift's
--     regeneration × works_factor), inn (tick_city step 5 refills crew_pool, never past its cap).
-- (5) tick_city steps 4 BUILD (each harbour subscribes its lowest work from its surplus and the
--     money goes to its REGION's other harbours by size_tier — WORKS_OUT = Σ WORKS_IN to the
--     ducat; a region of one keeps it), 5 INN, 6 COUPONS (per harbour, payable = least(Σ due,
--     surplus), pro rata, one DIVIDEND flow; the shortfall is not owed; accrued_day advances
--     regardless). All three LIT only. The receipt counts them; world_ducats counts the coupons
--     accrued and not collected.
-- (6) THE PAYOUT RIDES AN ARRIVAL. voyage.settle's arrival branch credits the house its accrued
--     coupons at the harbour she makes (credit DIVIDEND) — rows taken SKIP LOCKED, so an arrival
--     never waits on the hourly job. Dark, nothing accrues and the UPDATE matches nothing.
-- (7) MERCHANTS INVEST. npc_tend (inside tick_reconcile at :07, never on the arrivals tick): lit,
--     at most npc_invest_max_per_hour companies whose purse is above npc_invest_above × capital,
--     longest-uninvested first, each buy ONE stake through invest_for at the stop of her loop that
--     offers the most shares, down toward npc_invest_keep × capital. Under the 0114 budget.
--     Counted `invested`. The merchant card serves `company.invested`.
-- (8) world.town_hall(port) restated whole: the purse and the day (0122), the works, the investors
--     by name (merchant or player, paid desc, at most town_hall_investors_max), and `you`
--     (docked here, holdings, owed). Registered: cmd.invest, cmd.preview_invest.
--
-- ── DECISIONS TAKEN HERE (stated, not hidden) ───────────────────────────────────────────────────
-- * DARK, NOTHING IS OFFERED. invest_for refuses E_NOT_OFFERED while city_treasury_enabled is
--   false, tick_city's steps 4-6 do not run, so every level stays 0 and every composed reader is
--   its pre-image (asserted below). The switch (0122) lights investment with everything else.
-- * A merchant buys ONE stake an hour (at most the shares her best stop offers), not "down to
--   npc_invest_keep × capital" in one go: a level is 100 shares, and a loop of buys would be N
--   credit()s inside one company's turn. The hourly budget and the 50-company cap keep her cost
--   bounded; her surplus drains over hours.
-- * A house that buys more of a work it already holds keeps its accrued_day: the new money earns
--   from the last coupon day (≤ one hour's coupon over-accrued). Stated, not worth a second flow.
-- * The client cannot read city_works / city_shares: the Town Hall serves them, names included.
--
-- ── COST ────────────────────────────────────────────────────────────────────────────────────────
-- Arrivals tick: +1 UPDATE on city_shares by its primary-key prefix per arrival at a harbour
-- (matches nothing dark). Prices: +1 PK lookup in world.spread and world.daily_cap_remaining.
-- tick_city: ≤ 1 subscription per harbour (+ its region's WORKS_IN), one UPDATE per harbour with
-- coupons due, one UPDATE for the inns. npc_tend: ≤ 50 buys an hour, budgeted.
--
-- SUPERSEDES, one hunk each from the LIVE body (asserted exactly once): voyage.sail_refusal,
-- world.daily_cap_remaining, world.spread, public.tick_market_drift, public.tick_city,
-- voyage.settle, public.npc_tend, world.npc_fleet_card, public.client_rpc_entry_points;
-- world.town_hall restated whole (0122 said so). Self-asserts hold AS FOUND; every probe rolls back.
-- ROLLBACK: city_treasury_switch(false) stops everything at once; works_level_max 0 offers
-- nothing; works_coupon_pct 0 stops coupons; readers at level 0 are byte parity.

do $guard$ begin perform set_config('statement_timeout', '20min', true); end $guard$;

-- ── 1. THE KNOBS ───────────────────────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('works_cost_base', to_jsonb(20000),
   '0123: what a city''s first level of any work costs; level L costs this × works_cost_growth^(L-1).'),
  ('works_cost_growth', to_jsonb(1.6),
   '0123: each further level of a work costs this much more than the last.'),
  ('works_level_max', to_jsonb(5),
   '0123: the highest level a work reaches. 0 offers nothing anywhere (the rollback lever).'),
  ('shares_per_level', to_jsonb(100),
   '0123: a level is sold as this many shares at cost / this each.'),
  ('works_coupon_pct', to_jsonb(0.003),
   '0123: a share earns this fraction of what was paid per game-day, paid only from a city''s surplus. 0 stops coupons.'),
  ('works_region_share', to_jsonb(1.0),
   '0123: the part of a city''s own subscription paid to its region''s other harbours (by size_tier); the rest stays home.'),
  ('invest_min_ducats', to_jsonb(1000),
   '0123: the smallest stake a house may buy.'),
  ('npc_invest_keep', to_jsonb(1.5),
   '0123: a merchant above npc_invest_above × capital invests what she holds above this × capital.'),
  ('npc_invest_max_per_hour', to_jsonb(50),
   '0123: at most this many merchant companies buy a stake per npc_tend pass.'),
  ('docks_draft_per_levels', to_jsonb(2),
   '0123: a harbour admits one more draft for every this many docks levels.'),
  ('market_cap_per_level', to_jsonb(0.10),
   '0123: each market level raises the daily trade allowance by this fraction, and narrows the spread by spread_per_dev.'),
  ('production_per_level', to_jsonb(0.10),
   '0123: each production level raises a quay''s regeneration by this fraction.'),
  ('inn_hands_per_level', to_jsonb(2),
   '0123: each inn level brings this many hands an hour to the crew pool (tick_city step 5).'),
  ('inn_pool_per_tier', to_jsonb(40),
   '0123: the inn never refills the crew pool past size_tier × this.'),
  ('town_hall_investors_max', to_jsonb(50),
   '0123: the longest investor list world.town_hall serves.')
on conflict (key) do nothing;

-- ── 2. THE WORKS AND THE SHARES ────────────────────────────────────────────────────────────────
create table if not exists public.city_works (
  port_id    uuid not null references public.ports(id) on delete cascade,
  kind       text not null check (kind in ('docks', 'market', 'production', 'inn')),
  level      int  not null default 0 check (level >= 0),
  subscribed int  not null default 0 check (subscribed >= 0),
  updated_at timestamptz not null default now(),
  primary key (port_id, kind)
);
comment on table public.city_works is
  '0123: a city''s works. `level` is built; `subscribed` is the shares of the NEXT level sold so far. '
  'Read through public.city_level alone; written by public.invest_for and tick_city step 4.';

create table if not exists public.city_shares (
  port_id     uuid not null references public.ports(id) on delete cascade,
  kind        text not null check (kind in ('docks', 'market', 'production', 'inn')),
  player_id   uuid not null references public.players(id) on delete cascade,
  shares      int  not null check (shares > 0),
  paid        bigint not null check (paid > 0),
  accrued     bigint not null default 0 check (accrued >= 0),
  accrued_day int  not null,
  primary key (port_id, kind, player_id)
);
comment on table public.city_shares is
  '0123: the share register. `paid` is the coupon''s base; `accrued` the coupons the city has set aside '
  '(DIVIDEND flow at accrual) and the house collects when a fleet of hers makes this harbour.';

insert into public.city_works (port_id, kind)
select p.id, k.kind from public.ports p
 cross join (values ('docks'), ('market'), ('production'), ('inn')) k(kind)
 where p.kind = 'HARBOUR'
on conflict (port_id, kind) do nothing;

alter table public.npc_houses add column if not exists invested_at timestamptz;
comment on column public.npc_houses.invested_at is
  '0123: when this company last bought a stake (npc_tend takes the longest-uninvested first).';

alter table public.city_works  enable row level security;
alter table public.city_shares enable row level security;
revoke all on table public.city_works, public.city_shares from public, anon, authenticated;

-- ── 3. THE READERS ─────────────────────────────────────────────────────────────────────────────
create or replace function public.city_level(p_port uuid, p_kind text)
returns int
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0123: THE one reader of a work's level. 0 where nothing was ever built.
  select coalesce((select w.level from public.city_works w where w.port_id = p_port and w.kind = p_kind), 0)
$$;

create or replace function public.works_factor(p_port uuid, p_kind text, p_knob text)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0123: 1 + knob × level, and EXACTLY 1 (scale 0) at level 0, so a composed reader's figure is
  -- byte-identical to its pre-image until a level is built.
  select case when public.city_level(p_port, p_kind) = 0 then 1::numeric
              else 1 + public.wc_num(p_knob) * public.city_level(p_port, p_kind) end
$$;

create or replace function public.works_share_price(p_level int)
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0123: one share of level p_level + 1 = works_cost_base × works_cost_growth^p_level / shares_per_level.
  select round(public.wc_num('works_cost_base') * power(public.wc_num('works_cost_growth'), p_level)
               / public.wc_int('shares_per_level'))::bigint
$$;

create or replace function public.city_offered(p_port uuid, p_kind text)
returns int
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0123: the shares of the next level still for sale. Nothing dark; nothing past works_level_max.
  select case when not public.city_treasury_on() then 0
              else coalesce((select case when w.level >= public.wc_int('works_level_max') then 0
                                         else greatest(0, public.wc_int('shares_per_level') - w.subscribed) end
                               from public.city_works w where w.port_id = p_port and w.kind = p_kind), 0) end
$$;

-- ── 4. THE DOOR ────────────────────────────────────────────────────────────────────────────────
create or replace function public.invest_for(p_player uuid, p_port uuid, p_kind text, p_shares int)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0123: THE one way a house buys a stake in a city — players (cmd.invest) and merchants (npc_tend)
-- alike. Refuses before anything moves; then the house pays the city (pay_city SHARE), the share
-- register grows, and a 100th share completes the level. Server-only.
declare
  p        public.ports%rowtype;
  w        public.city_works%rowtype;
  v_per    int := public.wc_int('shares_per_level');
  v_offer  int;
  v_price  bigint;
  v_cost   bigint;
  v_have   bigint;
  v_event  uuid;
  v_after  bigint;
  v_done   boolean := false;
begin
  select x.* into p from public.ports x where x.id = p_port;
  if p.id is null or p.kind <> 'HARBOUR' then
    perform cmd.refuse('E_NOT_FOUND', 'there is no such harbour');
  end if;
  if p_kind is null or p_kind not in ('docks', 'market', 'production', 'inn') then
    perform cmd.refuse('E_NOT_OFFERED', format('%s builds no such work', p.name));
  end if;
  if not public.city_treasury_on() then
    perform cmd.refuse('E_NOT_OFFERED', format('%s is not selling shares yet', p.name));
  end if;
  -- 0122's ONE LOCK ORDER: the house's row first, then the city's (the work row, the purse).
  select pl.ducats into v_have from public.players pl where pl.id = p_player for update;
  insert into public.city_works (port_id, kind) values (p_port, p_kind) on conflict (port_id, kind) do nothing;
  select x.* into w from public.city_works x where x.port_id = p_port and x.kind = p_kind for update;
  v_offer := public.city_offered(p_port, p_kind);
  if v_offer <= 0 then
    perform cmd.refuse('E_NOT_OFFERED', format('%s offers no shares in its %s', p.name, p_kind));
  end if;
  if coalesce(p_shares, 0) < 1 or p_shares > v_offer then
    perform cmd.refuse('E_OVERSUBSCRIBED', format('%s offers %s shares in its %s', p.name, v_offer, p_kind),
                       cmd.figures(v_offer, coalesce(p_shares, 0), 'shares'));
  end if;
  v_price := public.works_share_price(w.level);
  v_cost  := v_price * p_shares;
  if v_cost < public.wc_int('invest_min_ducats') then
    perform cmd.refuse('E_INVEST_MIN', format('the smallest stake is %s d.', public.wc_int('invest_min_ducats')),
                       cmd.figures(v_cost, public.wc_int('invest_min_ducats'), 'ducats'));
  end if;
  if coalesce(v_have, 0) < v_cost then
    perform cmd.refuse('E_INSUFFICIENT_FUNDS', format('%s shares cost %s d.', p_shares, v_cost),
                       cmd.figures(coalesce(v_have, 0), v_cost, 'ducats'));
  end if;

  v_event := public.emit_event(p_player, 'INVESTED', jsonb_build_object(
               'port', p.code, 'port_name', p.name, 'kind', p_kind, 'shares', p_shares,
               'price', v_price, 'cost', v_cost, 'level', w.level + 1));
  v_after := public.pay_city(p_player, p_port, 'SHARE', v_cost, v_event);
  insert into public.city_shares (port_id, kind, player_id, shares, paid, accrued_day)
  values (p_port, p_kind, p_player, p_shares, v_cost, world.game_day())
  on conflict (port_id, kind, player_id) do update
     set shares = public.city_shares.shares + excluded.shares,
         paid   = public.city_shares.paid + excluded.paid;
  if w.subscribed + p_shares >= v_per then
    update public.city_works set level = level + 1, subscribed = 0, updated_at = now()
     where port_id = p_port and kind = p_kind;
    v_done := true;
  else
    update public.city_works set subscribed = subscribed + p_shares, updated_at = now()
     where port_id = p_port and kind = p_kind;
  end if;
  return jsonb_build_object('ok', true, 'port', p.code, 'kind', p_kind, 'shares', p_shares,
                            'price', v_price, 'cost', v_cost, 'completed', v_done,
                            'level', public.city_level(p_port, p_kind),
                            'subscribed', (select x.subscribed from public.city_works x where x.port_id = p_port and x.kind = p_kind),
                            'purse', v_after);
end $$;

create or replace function public.collect_coupons(p_player uuid, p_port uuid, p_event uuid default null)
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0123: a house collects what a city set aside for it, when a fleet of hers makes that harbour.
-- The DIVIDEND flow was posted at accrual (tick_city step 6), so this moves the house alone. Rows
-- the hourly job holds are skipped, never waited for: they are collected at the next call.
declare
  v_sum bigint;
begin
  with c as (
    select s.port_id, s.kind, s.player_id, s.accrued from public.city_shares s
     where s.port_id = p_port and s.player_id = p_player and s.accrued > 0
       for update skip locked
  ), x as (
    update public.city_shares s set accrued = 0
      from c where s.port_id = c.port_id and s.kind = c.kind and s.player_id = c.player_id
    returning c.accrued
  )
  select coalesce(sum(x.accrued), 0) into v_sum from x;
  if v_sum > 0 then
    perform public.credit(p_player, 'DIVIDEND', v_sum, p_event);
  end if;
  return v_sum;
end $$;

create or replace function cmd.refused_envelope(p_message text, p_detail text)
returns jsonb
language sql
immutable
as $$
  -- 0123: a caught 'E_CODE: sentence' as the {ok:false} envelope the fulfil pair returns — the
  -- split is cmd.refusal_caught's (0050), never a second one.
  select jsonb_build_object('ok', false, 'error_code', r->>'code', 'error_message', r->>'sentence',
                            'fixes', '[]'::jsonb, 'figures', r->'figures')
    from (select cmd.refusal_caught(p_message, p_detail) as r) x
$$;

create or replace function cmd.invest(p_port uuid, p_kind text, p_shares int)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0123: the caller's house buys p_shares of p_port's next p_kind level — only with a fleet of hers
-- lying DOCKED there (the Town Hall's `you.docked`, the same test). The core is public.invest_for.
declare
  v_player uuid := public.current_player_id();
  v_det    text;
begin
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_HOUSE',
                              'error_message', 'Found a house first.', 'fixes', '[]'::jsonb);
  end if;
  perform voyage.settle(f.id) from public.fleets f where f.player_id = v_player and f.status = 'SAILING';
  begin
    if not exists (select 1 from public.fleets f where f.player_id = v_player and f.status = 'DOCKED' and f.port_id = p_port) then
      perform cmd.refuse('E_NOT_DOCKED', 'dock a fleet here to invest');
    end if;
    return public.invest_for(v_player, p_port, p_kind, p_shares);
  exception when others then
    if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;
    get stacked diagnostics v_det = pg_exception_detail;
    return cmd.refused_envelope(sqlerrm, v_det);
  end;
end $$;

create or replace function cmd.preview_invest(p_port uuid, p_kind text, p_shares int)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0123: cmd.invest's dry run — the real buy, rolled back: {ok, estimate} or the refusal it would give.
declare
  v_out jsonb;
  v_det text;
begin
  begin
    v_out := cmd.invest(p_port, p_kind, p_shares);
    if coalesce((v_out->>'ok')::boolean, false) then
      v_out := jsonb_build_object('ok', true, 'estimate', v_out);
    end if;
    raise exception '__PREVIEW_ROLLBACK__' using errcode = 'P0001';
  exception when others then
    if sqlerrm = '__PREVIEW_ROLLBACK__' then
      return v_out;
    end if;
    if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;
    get stacked diagnostics v_det = pg_exception_detail;
    return cmd.refused_envelope(sqlerrm, v_det);
  end;
end $$;

revoke all on function public.city_level(uuid, text)                  from public, anon, authenticated;
revoke all on function public.works_factor(uuid, text, text)          from public, anon, authenticated;
revoke all on function public.works_share_price(int)                  from public, anon, authenticated;
revoke all on function public.city_offered(uuid, text)                from public, anon, authenticated;
revoke all on function public.invest_for(uuid, uuid, text, int)       from public, anon, authenticated;
revoke all on function public.collect_coupons(uuid, uuid, uuid)       from public, anon, authenticated;
revoke all on function cmd.refused_envelope(text, text)               from public, anon, authenticated;
revoke all on function cmd.invest(uuid, text, int)                    from public, anon;
revoke all on function cmd.preview_invest(uuid, text, int)            from public, anon;
grant execute on function cmd.invest(uuid, text, int)         to authenticated;
grant execute on function cmd.preview_invest(uuid, text, int) to authenticated;

-- ── 5. THE PRE-IMAGES the level-0 parity assert compares against (taken BEFORE any reader slice) ─
create temp table pre_0123_spread as
select p.id as port_id, world.spread(p.id)::text as v from public.ports p where p.kind = 'HARBOUR';
create temp table pre_0123_cap as
select s.player_id, s.port_id, s.good_id, world.daily_cap_remaining(s.player_id, s.port_id, s.good_id)::text as v
  from (select pl.id as player_id, pg.port_id, pg.good_id
          from public.port_goods pg
          join public.ports po on po.id = pg.port_id and po.kind = 'HARBOUR'
          cross join lateral (select x.id from public.players x order by x.is_npc, x.id limit 1) pl
         order by md5(pg.port_id::text || pg.good_id::text) limit 200) s;

-- ── 6. THE SLICES — each hunk asserted to occur EXACTLY ONCE in the LIVE body (LF-normalised) ───
create or replace function pg_temp.slice_0123(p_fn text, p_old text, p_new text)
returns void
language plpgsql
as $$
declare
  v_def text := replace(pg_get_functiondef(p_fn::regprocedure), E'\r', '');
  v_n   int  := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
begin
  if v_n <> 1 then
    raise exception '0123 self-assert FAIL: a hunk of % occurs % time(s), not once — the live body is not what this file was cut against: %',
      p_fn, v_n, left(p_old, 120);
  end if;
  execute replace(v_def, p_old, p_new);
end $$;

-- (a) DOCKS: a harbour admits one more draft per docks_draft_per_levels levels.
select pg_temp.slice_0123('voyage.sail_refusal(uuid, uuid, jsonb, numeric)',
$h$      select max_draft into v_maxd from public.ports where id = p_dest;
$h$,
$h$      select max_draft into v_maxd from public.ports where id = p_dest;
      v_maxd := v_maxd + public.city_level(p_dest, 'docks') / public.wc_int('docks_draft_per_levels');   -- 0123
$h$);

-- (b) MARKET: the daily allowance × the works factor; the spread narrows by spread_per_dev a level.
select pg_temp.slice_0123('world.daily_cap_remaining(uuid, uuid, uuid)',
$h$             * (1 + public.player_skill_bonus(p_player, 'TRADE_CAP'))
$h$,
$h$             * (1 + public.player_skill_bonus(p_player, 'TRADE_CAP'))
             * public.works_factor(p_port, 'market', 'market_cap_per_level')   -- 0123
$h$);
select pg_temp.slice_0123('world.spread(uuid)',
$h$           public.wc_num('spread_base') - public.wc_num('spread_per_dev') * p.dev_commerce
$h$,
$h$           public.wc_num('spread_base') - public.wc_num('spread_per_dev') * p.dev_commerce
             - public.wc_num('spread_per_dev') * public.city_level(p.id, 'market')   -- 0123
$h$);

-- (c) PRODUCTION: a quay regenerates faster by production_per_level a level.
select pg_temp.slice_0123('public.tick_market_drift(timestamptz)',
$h$                   + pg.production_rate * (v_day - pg.last_regen_day)),
$h$,
$h$                   + pg.production_rate * public.works_factor(pg.port_id, 'production', 'production_per_level')   -- 0123
                     * (v_day - pg.last_regen_day)),
$h$);

-- (d0) THE ROLL BOOKS AN HOUR THAT NETS NEGATIVE. 0122's purse CTE was INSERT … ON CONFLICT DO
--      UPDATE, and PostgreSQL checks a CHECK constraint on the PROPOSED row before it looks for the
--      conflict: an hour in which a lit city paid out more than it took (a coupon, a refound, a
--      day of SELLs) proposed a negative `ducats` and failed the whole roll. Dark it never shows
--      (dark, nothing is written). Now every purse row exists before the roll and the roll is
--      an UPDATE. Proven by the coupon probe below, whose second hour is a lone DIVIDEND outflow.
select pg_temp.slice_0123('public.tick_city(timestamptz)',
$h$  perform set_config('byeharu.treasury_roll', 'on', true);
  with f as (
$h$,
$h$  insert into public.port_treasury (port_id)   -- 0123: every purse row exists before the roll
  select distinct tf.port_id from public.treasury_flows tf where tf.created_at <= p_now
  on conflict (port_id) do nothing;
  perform set_config('byeharu.treasury_roll', 'on', true);
  with f as (
$h$);
select pg_temp.slice_0123('public.tick_city(timestamptz)',
$h$  ), b as (
    insert into public.port_treasury (port_id, ducats, rolled_at)
    select f.port_id, sum(f.ducats), p_now from f group by 1
    on conflict (port_id) do update
       set ducats = public.port_treasury.ducats + excluded.ducats, rolled_at = p_now, updated_at = now()
    returning 1
$h$,
$h$  ), b as (
    -- 0123: an UPDATE — a proposed INSERT row with a negative hour failed ducats >= 0 (above).
    update public.port_treasury t
       set ducats = t.ducats + x.s, rolled_at = p_now, updated_at = now()
      from (select f.port_id, sum(f.ducats) as s from f group by 1) x
     where t.port_id = x.port_id
    returning 1
$h$);

-- (d) THE HOURLY JOB gains steps 4 BUILD, 5 INN, 6 COUPONS (lit only) and their receipt.
select pg_temp.slice_0123('public.tick_city(timestamptz)',
$h$  v_bad     int;
$h$,
$h$  v_bad     int;
  -- 0123
  v_lit      boolean := public.city_treasury_on();
  v_max      int := public.wc_int('works_level_max');
  v_per      int := public.wc_int('shares_per_level');
  wb         record;
  rp         record;
  hp         record;
  v_price    bigint;
  v_k        int;
  v_amt      bigint;
  v_out      bigint;
  v_in       bigint;
  v_tiers    bigint;
  v_cum      bigint;
  v_prev     bigint;
  v_pay      bigint;
  v_works_out bigint := 0;
  v_works_in  bigint := 0;
  v_subs     int := 0;
  v_built    int := 0;
  v_inns     int := 0;
  v_paid     bigint := 0;
  v_skipped  bigint := 0;
$h$);
select pg_temp.slice_0123('public.tick_city(timestamptz)',
$h$  -- 7. ASSERT: every purse equals its books; none below zero (the CHECK holds it too).
$h$,
$h$  -- 4. BUILD (0123, lit): each harbour subscribes its lowest work from its surplus; the money goes
  --    to its region's other harbours by size_tier (WORKS_OUT = Σ WORKS_IN); a region of one keeps it.
  v_t := clock_timestamp();
  if v_lit then
    begin
      insert into public.city_works (port_id, kind)
      select p.id, k.kind from public.ports p
       cross join (values ('docks'), ('market'), ('production'), ('inn')) k(kind)
       where p.kind = 'HARBOUR'
      on conflict (port_id, kind) do nothing;
      for wb in select distinct on (w.port_id) w.port_id, w.kind, w.level, w.subscribed, p.region_id,
                       t.ducats as rolled, t.reserve
                  from public.city_works w join public.ports p on p.id = w.port_id and p.kind = 'HARBOUR'
                  join public.port_treasury t on t.port_id = w.port_id
                 where w.level < v_max
                 order by w.port_id, w.level, array_position(array['docks', 'market', 'production', 'inn'], w.kind) loop
        v_price := public.works_share_price(wb.level);
        -- what it held at the roll (never this hour's WORKS_IN — a region's money does not cascade
        -- round the coast inside one hour), and never more than it holds now.
        v_k := least(v_per - wb.subscribed,
                     floor(greatest(0, least(wb.rolled, public.treasury_balance(wb.port_id)) - wb.reserve) / v_price))::int;
        continue when v_k < 1;
        v_amt := v_k * v_price;
        select coalesce(sum(p.size_tier), 0) into v_tiers from public.ports p
         where p.region_id = wb.region_id and p.kind = 'HARBOUR' and p.id <> wb.port_id;
        v_out := case when v_tiers > 0 then round(v_amt * public.wc_num('works_region_share'))::bigint else 0 end;
        if v_out > 0 then
          perform public.treasury_post(wb.port_id, 'WORKS_OUT', -v_out, null, null);
          v_prev := 0;
          for rp in select p.id, sum(p.size_tier) over (order by p.code) as cum from public.ports p
                     where p.region_id = wb.region_id and p.kind = 'HARBOUR' and p.id <> wb.port_id
                     order by p.code loop
            v_cum := round(v_out::numeric * rp.cum / v_tiers)::bigint;
            if v_cum - v_prev > 0 then
              perform public.treasury_post(rp.id, 'WORKS_IN', v_cum - v_prev, null, null);
              v_works_in := v_works_in + (v_cum - v_prev);
            end if;
            v_prev := v_cum;
          end loop;
          v_works_out := v_works_out + v_out;
        end if;
        if wb.subscribed + v_k >= v_per then
          update public.city_works set level = level + 1, subscribed = 0, updated_at = now()
           where port_id = wb.port_id and kind = wb.kind;
          v_built := v_built + 1;
        else
          update public.city_works set subscribed = subscribed + v_k, updated_at = now()
           where port_id = wb.port_id and kind = wb.kind;
        end if;
        v_subs := v_subs + v_k;
      end loop;
    exception when others then
      v_err := v_err || jsonb_build_object('build', sqlerrm);
      v_works_out := 0; v_works_in := 0; v_subs := 0; v_built := 0;
    end;
  end if;
  v_ms := v_ms || jsonb_build_object('build', round(extract(epoch from clock_timestamp() - v_t) * 1000));

  -- 5. INN (0123, lit): an inn brings inn_hands_per_level hands a level an hour, never past the cap.
  v_t := clock_timestamp();
  if v_lit then
    begin
      with x as (
        select p.id, least(p.size_tier * public.wc_int('inn_pool_per_tier'),
                           p.crew_pool + public.wc_int('inn_hands_per_level') * w.level) as pool
          from public.ports p join public.city_works w on w.port_id = p.id and w.kind = 'inn' and w.level > 0
         where p.crew_pool < p.size_tier * public.wc_int('inn_pool_per_tier')
           for update of p skip locked
      )
      update public.ports p set crew_pool = x.pool from x where p.id = x.id;
      get diagnostics v_inns = row_count;
    exception when others then
      v_err := v_err || jsonb_build_object('inn', sqlerrm);
    end;
  end if;
  v_ms := v_ms || jsonb_build_object('inn', round(extract(epoch from clock_timestamp() - v_t) * 1000));

  -- 6. COUPONS (0123, lit): each row's due since its coupon day; a city pays what it holds above
  --    its reserve, pro rata; the shortfall is not owed; accrued_day advances regardless.
  v_t := clock_timestamp();
  if v_lit then
    begin
      for hp in select s.port_id,
                       sum(round(s.paid * public.wc_num('works_coupon_pct') * (v_today - s.accrued_day)))::bigint as due
                  from public.city_shares s where s.accrued_day < v_today
                 group by s.port_id order by s.port_id loop
        v_pay := least(hp.due, greatest(0, public.city_surplus(hp.port_id)));
        with d as (
          select s.kind, s.player_id,
                 round(s.paid * public.wc_num('works_coupon_pct') * (v_today - s.accrued_day))::bigint as due
            from public.city_shares s where s.port_id = hp.port_id and s.accrued_day < v_today
        ), a as (
          select d.kind, d.player_id,
                 case when hp.due > 0 then
                   round(sum(d.due) over w * v_pay::numeric / hp.due)
                   - round((sum(d.due) over w - d.due) * v_pay::numeric / hp.due) else 0 end as pay
            from d window w as (order by d.due, d.player_id, d.kind)
        )
        update public.city_shares s set accrued = s.accrued + a.pay::bigint, accrued_day = v_today
          from a where s.port_id = hp.port_id and s.kind = a.kind and s.player_id = a.player_id;
        if v_pay > 0 then
          perform public.treasury_post(hp.port_id, 'DIVIDEND', -v_pay, null, null);
        end if;
        v_paid := v_paid + v_pay;
        v_skipped := v_skipped + (hp.due - v_pay);
      end loop;
    exception when others then
      v_err := v_err || jsonb_build_object('coupons', sqlerrm);
      v_paid := 0; v_skipped := 0;
    end;
  end if;
  v_ms := v_ms || jsonb_build_object('coupons', round(extract(epoch from clock_timestamp() - v_t) * 1000));
  if v_works_out <> v_works_in then
    raise exception 'TICK_CITY FAIL: this hour''s WORKS_OUT % is not Σ WORKS_IN %', v_works_out, v_works_in
      using errcode = 'P0001';
  end if;

  -- 7. ASSERT: every purse equals its books; none below zero (the CHECK holds it too).
$h$);
select pg_temp.slice_0123('public.tick_city(timestamptz)',
$h$       + coalesce((select sum(f.ducats) from public.treasury_flows f), 0)
    into v_world;
$h$,
$h$       + coalesce((select sum(f.ducats) from public.treasury_flows f), 0)
       + coalesce((select sum(s.accrued) from public.city_shares s), 0)   -- 0123: set aside, not yet collected
    into v_world;
$h$);
select pg_temp.slice_0123('public.tick_city(timestamptz)',
$h$                            'world_ducats', v_world, 'errors', v_err,
$h$,
$h$                            'world_ducats', v_world, 'errors', v_err,
                            'subscribed', v_subs, 'levels_built', v_built, 'works_moved', v_works_out,
                            'inns', v_inns, 'coupons_paid', v_paid, 'coupons_skipped', v_skipped,
$h$);

-- (e) THE PAYOUT rides the arrival, at the harbour she makes, after the wages.
select pg_temp.slice_0123('voyage.settle(uuid, timestamptz)',
$h$      perform public.treasury_post(v.dest_port_id, 'WAGES', v.wages_paid, f.player_id, v_report);
    end if;
$h$,
$h$      perform public.treasury_post(v.dest_port_id, 'WAGES', v.wages_paid, f.player_id, v_report);
    end if;
    -- 0123: the coupons a city set aside for this house are collected at the harbour she makes.
    if v.dest_port_id is not null and public.city_treasury_on() then   -- dark: nothing read, nothing written
      perform public.collect_coupons(f.player_id, v.dest_port_id, v_report);
    end if;
$h$);

-- (f) MERCHANTS INVEST their surplus at a stop of their loop (lit; budgeted; ≤ 50 an hour).
create or replace function public.npc_invest(p_now timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0123: lit and with the merchants on, at most npc_invest_max_per_hour companies above
-- npc_invest_above × capital, longest-uninvested first, each buy ONE stake at the stop of her loop
-- that offers the most shares (ties: kind order, then port code), toward npc_invest_keep × capital,
-- through public.invest_for — the players' door. Budgeted by 0114's deadline. Called by npc_tend.
declare
  hi         record;
  v_pick     record;
  v_buy      int;
  v_invested int := 0;
  v_deferred int := 0;
  v_failed   int := 0;
  v_notes    jsonb := '[]'::jsonb;
begin
  if not public.city_treasury_on() or not public.npc_traders_on() then
    return jsonb_build_object('invested', 0, 'deferred', 0, 'failed', 0, 'notes', v_notes);
  end if;
  for hi in select h.player_id, h.capital, pl.ducats, pl.company_name
              from public.npc_houses h join public.players pl on pl.id = h.player_id and pl.is_npc
             where pl.ducats > h.capital * public.wc_num('npc_invest_above')
             order by h.invested_at nulls first, h.roster_ord
             limit public.wc_int('npc_invest_max_per_hour') loop
    if public.npc_upkeep_spent() then
      v_deferred := v_deferred + 1;
      continue;
    end if;
    begin
      select w.port_id, w.kind, public.city_offered(w.port_id, w.kind) as offered,
             public.works_share_price(w.level) as price
        into v_pick
        from (select distinct s.port_id from public.npc_fleets nf
                join public.standing_route_stops s on s.route_id = nf.route_id
               where nf.player_id = hi.player_id) st
        join public.ports po on po.id = st.port_id and po.kind = 'HARBOUR'
        join public.city_works w on w.port_id = st.port_id
       where public.city_offered(w.port_id, w.kind) > 0
       order by 3 desc, array_position(array['docks', 'market', 'production', 'inn'], w.kind), po.code
       limit 1;
      if v_pick.port_id is not null then
        v_buy := least(v_pick.offered,
                       floor((hi.ducats - public.wc_num('npc_invest_keep') * hi.capital) / v_pick.price))::int;
        if v_buy >= 1 and v_buy * v_pick.price >= public.wc_int('invest_min_ducats') then
          perform public.invest_for(hi.player_id, v_pick.port_id, v_pick.kind, v_buy);
          update public.npc_houses set invested_at = p_now where player_id = hi.player_id;
          v_invested := v_invested + 1;
        end if;
      end if;
    exception when others then
      v_failed := v_failed + 1;
      v_notes := v_notes || jsonb_build_object('company', hi.company_name, 'invest_error', sqlerrm);
    end;
  end loop;
  return jsonb_build_object('invested', v_invested, 'deferred', v_deferred, 'failed', v_failed, 'notes', v_notes);
end $$;
revoke all on function public.npc_invest(timestamptz) from public, anon, authenticated;

select pg_temp.slice_0123('public.npc_tend(timestamptz, uuid)',
$h$  v_unfunded int := 0;                                          -- 0122
$h$,
$h$  v_unfunded int := 0;                                          -- 0122
  v_inv      jsonb := '{}'::jsonb;                              -- 0123
$h$);
select pg_temp.slice_0123('public.npc_tend(timestamptz, uuid)',
$h$  -- REFOUNDS, per company, only while the switch is on.
$h$,
$h$  -- 0123: INVESTMENT — merchants put their surplus into the cities of their loop (public.npc_invest).
  if v_on and p_route is null then
    v_inv := public.npc_invest(p_now);
    v_deferred := v_deferred + coalesce((v_inv->>'deferred')::int, 0);
    v_failed := v_failed + coalesce((v_inv->>'failed')::int, 0);
    v_notes := v_notes || coalesce(v_inv->'notes', '[]'::jsonb);
  end if;

  -- REFOUNDS, per company, only while the switch is on.
$h$);
select pg_temp.slice_0123('public.npc_tend(timestamptz, uuid)',
$h$'refound_unfunded', v_unfunded,$h$,
$h$'refound_unfunded', v_unfunded, 'invested', coalesce((v_inv->>'invested')::int, 0),$h$);

-- (g) THE MERCHANT CARD says where she has invested.
select pg_temp.slice_0123('world.npc_fleet_card(uuid)',
$h$      'refounded_at', (select max(e.created_at) from public.events e where e.player_id = p.id and e.kind = 'NPC_REFOUNDED')),
$h$,
$h$      'refounded_at', (select max(e.created_at) from public.events e where e.player_id = p.id and e.kind = 'NPC_REFOUNDED'),
      -- 0123: her stakes, by harbour — `Invested 24,000 d. at Lisbon`.
      'invested', (select coalesce(jsonb_agg(jsonb_build_object('port', x.code, 'name', x.name, 'paid', x.paid)
                                             order by x.paid desc, x.code), '[]'::jsonb)
                     from (select po.code, po.name, sum(s.paid) as paid from public.city_shares s
                             join public.ports po on po.id = s.port_id
                            where s.player_id = p.id group by po.code, po.name) x)),
$h$);

-- (h) THE REGISTRY: the buy and its dry run.
select pg_temp.slice_0123('public.client_rpc_entry_points()',
$h$      ('world',       'town_hall',             'uuid'),
$h$,
$h$      ('world',       'town_hall',             'uuid'),
      -- 0123: a stake in a city's works, and its dry run (the Town Hall's Invest).
      ('cmd',         'invest',                'uuid, text, int'),
      ('cmd',         'preview_invest',        'uuid, text, int'),
$h$);

-- ── 7. THE READ, restated whole: the purse, the day, the works, the investors, you ──────────────
create or replace function world.town_hall(p_port uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0122: one harbour's purse and its last FULL game-day's book, by kind. 0123: the works (level,
-- what the next level costs, the shares offered), the investors by name (a merchant company or a
-- player's house — names are public: the card serves a merchant's, Rank a player's), and the
-- viewer's own holdings and whether a fleet of hers lies docked here (cmd.invest's one test).
-- Reads the rolled state and the books; writes nothing.
declare
  p        public.ports%rowtype;
  t        public.port_treasury%rowtype;
  v_day    int := world.game_day() - 1;
  v_player uuid := public.current_player_id();
  v_max    int := public.wc_int('works_level_max');
  v_per    int := public.wc_int('shares_per_level');
begin
  select x.* into p from public.ports x where x.id = p_port;
  if p.id is null or p.kind <> 'HARBOUR' then
    raise exception 'E_NOT_FOUND: there is no such harbour' using errcode = 'P0001';
  end if;
  select x.* into t from public.port_treasury x where x.port_id = p_port;
  return jsonb_build_object(
    'port', p.code, 'enabled', public.city_treasury_on(),
    'purse', jsonb_build_object(
       'ducats', public.treasury_balance(p_port), 'reserve', coalesce(t.reserve, 0),
       'bid_factor', round(public.city_bid_factor(p_port), 4),
       'rolled_at', t.rolled_at, 'seeded_at', t.seeded_at,
       'tax_rate', world.tax_rate(p_port)),
    'day', jsonb_build_object(
       'game_day', v_day,
       'in',  coalesce((select jsonb_object_agg(d.kind, d.ducats order by d.kind) from public.treasury_daybook d
                         where d.port_id = p_port and d.game_day = v_day and d.ducats > 0), '{}'::jsonb),
       'out', coalesce((select jsonb_object_agg(d.kind, -d.ducats order by d.kind) from public.treasury_daybook d
                         where d.port_id = p_port and d.game_day = v_day and d.ducats < 0), '{}'::jsonb)),
    'works', (select jsonb_agg(jsonb_build_object(
                'kind', k.kind,
                'level', coalesce(w.level, 0),
                'level_max', v_max,
                'next_cost', case when coalesce(w.level, 0) < v_max
                                  then public.works_share_price(coalesce(w.level, 0)) * v_per end,
                'share_price', case when coalesce(w.level, 0) < v_max
                                    then public.works_share_price(coalesce(w.level, 0)) end,
                'offered', public.city_offered(p_port, k.kind),
                'subscribed', coalesce(w.subscribed, 0)) order by k.ord)
                from (values ('docks', 1), ('market', 2), ('production', 3), ('inn', 4)) k(kind, ord)
                left join public.city_works w on w.port_id = p_port and w.kind = k.kind),
    'investors', coalesce((select jsonb_agg(jsonb_build_object(
                    'name', x.company_name, 'merchant', x.is_npc, 'kind', x.kind,
                    'shares', x.shares, 'paid', x.paid) order by x.paid desc, x.company_name, x.kind)
                    from (select pl.company_name, pl.is_npc, s.kind, s.shares, s.paid
                            from public.city_shares s join public.players pl on pl.id = s.player_id
                           where s.port_id = p_port
                           order by s.paid desc, pl.company_name, s.kind
                           limit public.wc_int('town_hall_investors_max')) x), '[]'::jsonb),
    'you', jsonb_build_object(
       'docked', v_player is not null and exists (select 1 from public.fleets f where f.player_id = v_player
                                                     and f.status = 'DOCKED' and f.port_id = p_port),
       'holdings', coalesce((select jsonb_agg(jsonb_build_object(
                       'kind', s.kind, 'shares', s.shares, 'paid', s.paid, 'owed', s.accrued) order by s.kind)
                       from public.city_shares s where s.port_id = p_port and s.player_id = v_player), '[]'::jsonb)));
end $$;
comment on function world.town_hall(uuid) is
  '0122/0123: one harbour''s Town Hall — its purse, its last full game-day''s book, its works and the '
  'shares they offer, its investors by name, and the viewer''s holdings and whether she lies docked. '
  'Read at a tap. Authenticated only.';
revoke all on function world.town_hall(uuid) from public, anon;
grant execute on function world.town_hall(uuid) to authenticated;

-- ── 8. SELF-ASSERT ─────────────────────────────────────────────────────────────────────────────
create or replace function pg_temp.set_balance_0123(p_port uuid, p_above bigint)
returns void
language plpgsql
as $$
-- A probe's purse: its live balance becomes the reserve tick_city's step 3 will set, plus p_above.
declare
  v_delta bigint := public.treasury_reserve(p_port) + p_above - public.treasury_balance(p_port);
begin
  if v_delta <> 0 then
    perform public.treasury_post(p_port, 'PROBE', v_delta, null, null);
  end if;
end $$;

do $$
declare
  c_probe    constant uuid := '00000000-0123-4000-8000-000000000001';
  v_npc_on   jsonb := public.wc('npc_traders_enabled');
  v_rt_on    jsonb := public.wc('standing_routes_enabled');
  v_fn       text;
  v_n        int;
  v_r        jsonb;
  v_player   uuid;
  v_fleet    uuid;
  v_home     uuid;
  v_other    uuid;
  v_purse    bigint;
  v_bal      bigint;
  v_price    bigint;
  v_x        bigint;
  v_y        bigint;
  v_region   uuid;
  v_solo     uuid;
  v_city     jsonb;
  v_house    record;
  v_best     record;
  v_ev       jsonb;
  v_day      int := world.game_day();
  v_notes    text := '';
  v_draft    int;
  v_stops    uuid[];
begin
  -- (a) THE WALL.
  foreach v_fn in array array[
    'public.city_level(uuid, text)', 'public.works_factor(uuid, text, text)', 'public.works_share_price(integer)',
    'public.city_offered(uuid, text)', 'public.invest_for(uuid, uuid, text, integer)',
    'public.collect_coupons(uuid, uuid, uuid)', 'cmd.refused_envelope(text, text)',
    'public.npc_invest(timestamp with time zone)'] loop
    if has_function_privilege('anon', v_fn, 'execute') or has_function_privilege('authenticated', v_fn, 'execute') then
      raise exception '0123 self-assert FAIL: % is client-callable', v_fn;
    end if;
  end loop;
  foreach v_fn in array array['cmd.invest(uuid, text, integer)', 'cmd.preview_invest(uuid, text, integer)',
                              'world.town_hall(uuid)'] loop
    if not has_function_privilege('authenticated', v_fn, 'execute') or has_function_privilege('anon', v_fn, 'execute') then
      raise exception '0123 self-assert FAIL: % is not exactly authenticated-only', v_fn;
    end if;
  end loop;
  if (select count(*) from public.client_rpc_entry_points() e
       where e.schema_name = 'cmd' and e.function_name in ('invest', 'preview_invest') and e.fn is not null) <> 2 then
    raise exception '0123 self-assert FAIL: cmd.invest / cmd.preview_invest are not registered entry points';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0123 self-assert FAIL: a client write grant exists: %', (select jsonb_agg(to_jsonb(g)) from public.client_write_grants() g);
  end if;
  if has_table_privilege('authenticated', 'public.city_shares', 'select')
     or has_table_privilege('anon', 'public.city_works', 'select') then
    raise exception '0123 self-assert FAIL: the works or the share register is client-readable';
  end if;
  if public.city_treasury_on() then
    raise exception '0123 self-assert FAIL: the city purses are lit at deploy; this file ships them dark';
  end if;
  if exists (select 1 from public.city_works where level <> 0 or subscribed <> 0) or exists (select 1 from public.city_shares) then
    raise exception '0123 self-assert FAIL: a work was built or a share sold at deploy';
  end if;
  if (select count(*) from public.city_works) <> 4 * (select count(*) from public.ports where kind = 'HARBOUR') then
    raise exception '0123 self-assert FAIL: not every harbour has its four works';
  end if;

  -- (b) LEVEL 0 IS BYTE PARITY: the spread of every harbour and 200 allowances equal their pre-images.
  select count(*) into v_n from pre_0123_spread s where world.spread(s.port_id)::text is distinct from s.v;
  if v_n <> 0 then raise exception '0123 self-assert FAIL: at level 0, % spread(s) moved', v_n; end if;
  select count(*) into v_n from pre_0123_cap s
   where world.daily_cap_remaining(s.player_id, s.port_id, s.good_id)::text is distinct from s.v;
  if v_n <> 0 or (select count(*) from pre_0123_cap) < 50 then
    raise exception '0123 self-assert FAIL: at level 0, % of % allowances moved', v_n, (select count(*) from pre_0123_cap);
  end if;

  -- (c) DARK: nothing is offered; the read serves the works with nothing offered.
  select p.id into v_other from public.ports p where p.kind = 'HARBOUR' order by p.code limit 1;
  begin
    perform public.invest_for((select id from public.players order by id limit 1), v_other, 'docks', 10);
    raise exception '0123 self-assert FAIL: a dark city sold a share';
  exception when others then
    if sqlerrm not like 'E_NOT_OFFERED%' then raise; end if;
  end;
  v_r := world.town_hall(v_other);
  if jsonb_array_length(v_r->'works') <> 4 or (v_r->>'enabled')::boolean
     or exists (select 1 from jsonb_array_elements(v_r->'works') e where (e->>'offered')::int <> 0) then
    raise exception '0123 self-assert FAIL: the dark Town Hall read %', v_r;
  end if;

  -- THE PROBE WORLD (rolled back whole).
  begin
    update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled';
    v_player := public.new_house(c_probe, 'Casa dos Probes', 'PRT');
    select f.id, f.port_id into v_fleet, v_home from public.fleets f where f.player_id = v_player limit 1;
    perform public.credit(v_player, 'PROBE_0123', 10000000);
    select p.id into v_other from public.ports p where p.kind = 'HARBOUR' and p.id <> v_home order by p.code limit 1;
    perform cmd.assume_identity(c_probe);

    -- (d) THE SKIN: not docked refuses; the dry run moves nothing; the buy refuses what is not offered.
    v_r := cmd.invest(v_other, 'docks', 10);
    if v_r->>'error_code' is distinct from 'E_NOT_DOCKED' then
      raise exception '0123 self-assert FAIL: an undocked house invested: %', v_r;
    end if;
    if not (world.town_hall(v_home)->'you'->>'docked')::boolean or (world.town_hall(v_other)->'you'->>'docked')::boolean then
      raise exception '0123 self-assert FAIL: the read''s `docked` is not cmd.invest''s test';
    end if;
    select ducats into v_purse from public.players where id = v_player;
    v_r := cmd.preview_invest(v_home, 'docks', 10);
    if not (v_r->>'ok')::boolean or (v_r->'estimate'->>'cost')::bigint <> 10 * public.works_share_price(0)
       or (select ducats from public.players where id = v_player) <> v_purse
       or exists (select 1 from public.city_shares where player_id = v_player) then
      raise exception '0123 self-assert FAIL: the dry run % moved something or priced wrong', v_r;
    end if;
    v_r := cmd.invest(v_home, 'harbour', 10);
    if v_r->>'error_code' is distinct from 'E_NOT_OFFERED' then raise exception '0123 self-assert FAIL: an unknown work sold: %', v_r; end if;
    v_r := cmd.invest(v_home, 'docks', 101);
    if v_r->>'error_code' is distinct from 'E_OVERSUBSCRIBED' or (v_r->'figures'->>'have')::numeric <> 100 then
      raise exception '0123 self-assert FAIL: 101 shares of 100 were not refused with figures: %', v_r;
    end if;
    v_r := cmd.invest(v_home, 'docks', 1);
    if v_r->>'error_code' is distinct from 'E_INVEST_MIN' then raise exception '0123 self-assert FAIL: a dust stake sold: %', v_r; end if;

    -- (e) THE BUY: purse + treasury conserved, the event, subscribed moves; the 100th share builds.
    v_bal := public.treasury_balance(v_home);
    v_price := public.works_share_price(0);
    v_r := cmd.invest(v_home, 'docks', 60);
    if not (v_r->>'ok')::boolean or (v_r->>'cost')::bigint <> 60 * v_price
       or (select ducats from public.players where id = v_player) <> v_purse - 60 * v_price
       or public.treasury_balance(v_home) <> v_bal + 60 * v_price
       or (select subscribed from public.city_works where port_id = v_home and kind = 'docks') <> 60
       or not exists (select 1 from public.events e where e.player_id = v_player and e.kind = 'INVESTED' and (e.payload->>'shares')::int = 60)
       or not exists (select 1 from public.treasury_flows tf where tf.port_id = v_home and tf.kind = 'SHARE' and tf.ducats = 60 * v_price) then
      raise exception '0123 self-assert FAIL: a 60-share buy did not move purse, treasury, register and event as one: %', v_r;
    end if;
    v_r := cmd.invest(v_home, 'docks', 40);
    if not (v_r->>'completed')::boolean or public.city_level(v_home, 'docks') <> 1
       or (select subscribed from public.city_works where port_id = v_home and kind = 'docks') <> 0
       or (select shares from public.city_shares where port_id = v_home and kind = 'docks' and player_id = v_player) <> 100
       or (select paid from public.city_shares where port_id = v_home and kind = 'docks' and player_id = v_player) <> 100 * v_price then
      raise exception '0123 self-assert FAIL: the 100th share did not complete the level: %', v_r;
    end if;
    v_r := world.town_hall(v_home);
    if (v_r->'works'->0->>'level')::int <> 1 or (v_r->'works'->0->>'share_price')::bigint <> public.works_share_price(1)
       or v_r->'investors'->0->>'name' <> 'Casa dos Probes' or (v_r->'investors'->0->>'merchant')::boolean
       or (v_r->'you'->'holdings'->0->>'shares')::int <> 100 then
      raise exception '0123 self-assert FAIL: the Town Hall read %', v_r;
    end if;
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '', true);
    if (world.town_hall(v_home)->'you'->>'docked')::boolean
       or jsonb_array_length(world.town_hall(v_home)->'you'->'holdings') <> 0
       or world.town_hall(v_home)->'investors' <> v_r->'investors' then
      raise exception '0123 self-assert FAIL: a stranger does not see the same investors, or sees holdings';
    end if;
    v_notes := v_notes || format('a house bought 60 + 40 shares at %s d. and built docks level 1; ', v_price);

    -- (f) THE COUPON: paid 10,000 earns 30 a game-day; pro rata from the surplus; payout on arrival.
    --     tick_city's step 3 sets every reserve from the books, so a probe sets the BALANCE against
    --     that reserve (pg_temp.set_balance_0123), never the reserve.
    delete from public.city_shares where port_id = v_home;
    insert into public.city_shares (port_id, kind, player_id, shares, paid, accrued_day)
    values (v_home, 'market', v_player, 50, 10000, v_day - 1);
    select h.player_id into v_house from public.npc_houses h order by h.roster_ord limit 1;
    insert into public.city_shares (port_id, kind, player_id, shares, paid, accrued_day)
    values (v_home, 'market', v_house.player_id, 10, 10000 / 3, v_day - 1);
    -- a harbour holding reserve + 10 with dues 30 and 10 pays 7 and 3, and owes nothing more.
    perform pg_temp.set_balance_0123(v_home, 10);
    v_city := public.tick_city(now());
    if v_city->'errors' <> '{}'::jsonb
       or (select accrued from public.city_shares where port_id = v_home and player_id = v_player) <> 7
       or (select accrued from public.city_shares where port_id = v_home and player_id = v_house.player_id) <> 3
       or exists (select 1 from public.city_shares where port_id = v_home and accrued_day <> v_day)
       or coalesce((select sum(tf.ducats) from public.treasury_flows tf where tf.port_id = v_home and tf.kind = 'DIVIDEND'), 0) <> -10
       or (v_city->>'coupons_skipped')::bigint <> 30 then
      raise exception '0123 self-assert FAIL: reserve + 10 against dues 30 and 10 did not pay 7 and 3 (tick %)', v_city;
    end if;
    -- a harbour holding its reserve exactly pays nothing; accrued_day still advances.
    update public.city_shares set accrued = 0, accrued_day = v_day - 1 where port_id = v_home;
    --   (this hour's only flow at v_home is the DIVIDEND outflow: an hour that nets NEGATIVE, which
    --    0122's roll could not book — the (d0) slice.)
    perform pg_temp.set_balance_0123(v_home, 0);
    v_city := public.tick_city(now());
    if (select sum(accrued) from public.city_shares where port_id = v_home) <> 0
       or exists (select 1 from public.city_shares where port_id = v_home and accrued_day <> v_day)
       or (v_city->>'coupons_skipped')::bigint <> 40 then
      raise exception '0123 self-assert FAIL: a city at its reserve paid a coupon or held the coupon day (tick %)', v_city;
    end if;
    -- a funded harbour pays the whole due: paid 10,000 → 30.
    update public.city_shares set accrued_day = v_day - 1 where port_id = v_home;
    perform pg_temp.set_balance_0123(v_home, 40);
    v_city := public.tick_city(now());
    if (select accrued from public.city_shares where port_id = v_home and player_id = v_player) <> 30
       or (v_city->>'coupons_paid')::bigint <> 40 then
      raise exception '0123 self-assert FAIL: paid 10,000 did not accrue 30 in a game-day (tick %)', v_city;
    end if;
    -- the payout: what an arrival collects — credit DIVIDEND 30, accrued 0, no new flow, once.
    select ducats into v_purse from public.players where id = v_player;
    select count(*) into v_n from public.treasury_flows where port_id = v_home;
    v_x := public.collect_coupons(v_player, v_home, null);
    if v_x <> 30
       or (select ducats from public.players where id = v_player) <> v_purse + 30
       or (select accrued from public.city_shares where port_id = v_home and player_id = v_player) <> 0
       or (select count(*) from public.treasury_flows where port_id = v_home) <> v_n
       or (select l.ducats_delta from public.ledger l where l.player_id = v_player and l.kind = 'DIVIDEND' order by l.id desc limit 1) <> 30 then
      raise exception '0123 self-assert FAIL: the payout did not credit DIVIDEND 30 and zero the row';
    end if;
    if public.collect_coupons(v_player, v_home, null) <> 0 then
      raise exception '0123 self-assert FAIL: a coupon was collected twice';
    end if;
    if (select prosrc from pg_proc where oid = 'voyage.settle(uuid, timestamptz)'::regprocedure) not like '%public.collect_coupons(f.player_id, v.dest_port_id, v_report)%' then
      raise exception '0123 self-assert FAIL: the arrival does not collect the coupons';
    end if;
    delete from public.city_shares where port_id = v_home;
    v_notes := v_notes || 'reserve + 10 paid dues 30 and 10 as 7 and 3, a city at its reserve paid none and still advanced the day, 10,000 accrued 30 and the payout credited it once; ';

    -- (g) THE CITY SUBSCRIBES: reserve + 50 × price buys exactly 50 of its lowest work; WORKS_OUT = Σ WORKS_IN.
    perform public.tick_city(now());   -- every flow so far rolled: the flows below are this probe's
    select p.region_id into v_region from public.ports p where p.kind = 'HARBOUR' and p.id <> v_home
     group by p.region_id having count(*) >= 3 order by p.region_id limit 1;
    select p.id into v_other from public.ports p where p.region_id = v_region and p.kind = 'HARBOUR' order by p.code limit 1;
    update public.city_works set level = 0, subscribed = 0 where port_id = v_other;
    v_price := public.works_share_price(0);
    perform pg_temp.set_balance_0123(v_other, 50 * v_price + v_price / 2);
    v_city := public.tick_city(now());
    select coalesce(sum(tf.ducats) filter (where tf.kind = 'WORKS_OUT' and tf.port_id = v_other), 0),
           coalesce(sum(tf.ducats) filter (where tf.kind = 'WORKS_IN'), 0)
      into v_x, v_y from public.treasury_flows tf;
    if (select subscribed from public.city_works where port_id = v_other and kind = 'docks') <> 50
       or v_x <> -50 * v_price or v_y <> 50 * v_price
       or exists (select 1 from public.treasury_flows tf join public.ports p on p.id = tf.port_id
                   where tf.kind = 'WORKS_IN' and (p.region_id <> v_region or p.id = v_other))
       or (v_city->>'works_moved')::bigint <> 50 * v_price then
      raise exception '0123 self-assert FAIL: reserve + 50 shares did not subscribe 50 and pay the region to the ducat (out %, in %, tick %)', v_x, v_y, v_city;
    end if;
    -- at its reserve: nothing more.
    v_city := public.tick_city(now());
    if (select subscribed from public.city_works where port_id = v_other and kind = 'docks') <> 50 then
      raise exception '0123 self-assert FAIL: a city at its reserve subscribed (tick %)', v_city;
    end if;
    v_notes := v_notes || format('reserve + 50 × %s d. subscribed 50 and paid %s d. to its region to the ducat; ', v_price, v_y);
    -- a region of one keeps it: it builds and posts no works flow.
    select p.id into v_solo from public.ports p where p.kind = 'HARBOUR'
       and (select count(*) from public.ports q where q.region_id = p.region_id and q.kind = 'HARBOUR') = 1
     order by p.code limit 1;
    if v_solo is not null then
      update public.city_works set level = 0, subscribed = 0 where port_id = v_solo;
      perform pg_temp.set_balance_0123(v_solo, 10 * public.works_share_price(0));
      v_city := public.tick_city(now());
      if (select subscribed from public.city_works where port_id = v_solo and kind = 'docks') <> 10
         or exists (select 1 from public.treasury_flows tf where tf.port_id = v_solo and tf.kind in ('WORKS_OUT', 'WORKS_IN'))
         or exists (select 1 from public.treasury_daybook d where d.port_id = v_solo and d.kind in ('WORKS_OUT', 'WORKS_IN')) then
        raise exception '0123 self-assert FAIL: a region of one posted a works flow or did not build (tick %)', v_city;
      end if;
      v_notes := v_notes || 'a region of one built 10 shares and posted no flow; ';
    else
      v_notes := v_notes || 'no region of one harbour exists, so that probe did not run; ';
    end if;

    -- (h) LEVEL 5 COMPOSES: draft + 2, allowance × 1.5, spread − 5 × spread_per_dev, regen × 1.5, the inn + 10.
    update public.city_works set level = 5 where port_id = v_home;
    select max_draft into v_draft from public.ports where id = v_home;
    if world.spread(v_home) <> greatest(public.wc_num('spread_floor'),
                                        public.wc_num('spread_base') - public.wc_num('spread_per_dev') * ((select dev_commerce from public.ports where id = v_home) + 5))
                                * (1 - public.buff_multiplier('PORT', v_home, 'SPREAD', now())) then
      raise exception '0123 self-assert FAIL: a level-5 market did not narrow the spread by 5 × spread_per_dev';
    end if;
    if public.works_factor(v_home, 'market', 'market_cap_per_level') <> 1.5
       or (select prosrc from pg_proc where oid = 'world.daily_cap_remaining(uuid, uuid, uuid)'::regprocedure) not like '%works_factor(p_port, ''market''%'
       or (select prosrc from pg_proc where oid = 'public.tick_market_drift(timestamptz)'::regprocedure) not like '%works_factor(pg.port_id, ''production''%'
       or (select prosrc from pg_proc where oid = 'voyage.sail_refusal(uuid, uuid, jsonb, numeric)'::regprocedure) not like '%city_level(p_dest, ''docks'')%' then
      raise exception '0123 self-assert FAIL: a level-5 reader does not compose its factor';
    end if;
    if v_draft + public.city_level(v_home, 'docks') / public.wc_int('docks_draft_per_levels') <> v_draft + 2 then
      raise exception '0123 self-assert FAIL: docks level 5 does not admit draft + 2';
    end if;
    update public.ports set crew_pool = 0 where id = v_home;
    v_city := public.tick_city(now());
    if (select crew_pool from public.ports where id = v_home)
       <> least((select size_tier from public.ports where id = v_home) * public.wc_int('inn_pool_per_tier'), 10) then
      raise exception '0123 self-assert FAIL: a level-5 inn did not bring 10 hands (tick %)', v_city;
    end if;
    update public.ports set crew_pool = size_tier * public.wc_int('inn_pool_per_tier') where id = v_home;
    perform public.tick_city(now());
    if (select crew_pool from public.ports where id = v_home) <> (select size_tier from public.ports where id = v_home) * public.wc_int('inn_pool_per_tier') then
      raise exception '0123 self-assert FAIL: the inn filled past its cap';
    end if;

    -- (i) A MERCHANT INVESTS her surplus at the stop that offers most; under the line, nothing.
    update public.world_config set value = 'true'::jsonb where key in ('npc_traders_enabled', 'standing_routes_enabled');
    select h.player_id, h.capital, h.company_name into v_house
      from (select h0.player_id, h0.capital, pl.company_name, h0.roster_ord from public.npc_houses h0
              join public.players pl on pl.id = h0.player_id) h
     where exists (select 1 from public.npc_fleets nf join public.standing_route_stops s on s.route_id = nf.route_id
                    join public.ports po on po.id = s.port_id and po.kind = 'HARBOUR'
                   where nf.player_id = h.player_id)
     order by h.roster_ord limit 1;
    -- every stop of hers offers a whole level; one has sold 30 docks already, so its docks offer
    -- least and the best is docks at the first OTHER stop by code.
    update public.city_works w set level = 0, subscribed = 0
     where w.port_id in (select s.port_id from public.npc_fleets nf join public.standing_route_stops s on s.route_id = nf.route_id
                          where nf.player_id = v_house.player_id);
    select array_agg(x.id order by x.code) into v_stops
      from (select distinct po.id, po.code from public.npc_fleets nf
              join public.standing_route_stops s on s.route_id = nf.route_id
              join public.ports po on po.id = s.port_id and po.kind = 'HARBOUR'
             where nf.player_id = v_house.player_id) x;
    if array_length(v_stops, 1) >= 2 then
      update public.city_works set subscribed = 30 where port_id = v_stops[1] and kind = 'docks';
    end if;
    update public.players set ducats = 3 * v_house.capital where id = v_house.player_id;
    update public.npc_houses set invested_at = null where player_id = v_house.player_id;
    update public.npc_houses set invested_at = now() where player_id <> v_house.player_id;
    v_price := public.works_share_price(0);
    v_n := least(100, floor((3 * v_house.capital - public.wc_num('npc_invest_keep') * v_house.capital) / v_price))::int;
    v_city := public.npc_invest(now());
    if (v_city->>'invested')::int < 1
       or (select ducats from public.players where id = v_house.player_id) <> 3 * v_house.capital - v_n * v_price
       or (select sum(shares) from public.city_shares where player_id = v_house.player_id) <> v_n
       or not exists (select 1 from public.city_shares where player_id = v_house.player_id and kind = 'docks'
                         and port_id = case when array_length(v_stops, 1) >= 2 then v_stops[2] else v_stops[1] end) then
      raise exception '0123 self-assert FAIL: a merchant at 3 × capital did not buy % shares at % d. at her best stop (invest %)',
        v_n, v_price, v_city;
    end if;
    v_r := world.town_hall((select port_id from public.city_shares where player_id = v_house.player_id limit 1));
    if not exists (select 1 from jsonb_array_elements(v_r->'investors') e
                    where e->>'name' = v_house.company_name and (e->>'merchant')::boolean) then
      raise exception '0123 self-assert FAIL: the Town Hall does not name the merchant investor: %', v_r->'investors';
    end if;
    if jsonb_array_length(world.npc_fleet_card((select nf.fleet_id from public.npc_fleets nf where nf.player_id = v_house.player_id limit 1))
                          ->'company'->'invested') <> 1 then
      raise exception '0123 self-assert FAIL: the merchant card does not say where she invested';
    end if;
    -- at 1.9 × capital: nothing.
    delete from public.city_shares where player_id = v_house.player_id;
    update public.players set ducats = round(1.9 * v_house.capital) where id = v_house.player_id;
    update public.npc_houses set invested_at = null where player_id = v_house.player_id;
    v_city := public.npc_invest(now());
    if exists (select 1 from public.city_shares where player_id = v_house.player_id) then
      raise exception '0123 self-assert FAIL: a merchant at 1.9 × capital invested';
    end if;
    -- the budget cuts the loop (0114's deadline), and npc_tend carries the count and the receipt key.
    update public.players set ducats = 3 * v_house.capital where id = v_house.player_id;
    perform set_config('byeharu.npc_upkeep_deadline', (clock_timestamp() - interval '1 hour')::text, true);
    v_city := public.npc_invest(now());
    if exists (select 1 from public.city_shares where player_id = v_house.player_id) or (v_city->>'deferred')::int < 1 then
      raise exception '0123 self-assert FAIL: a spent budget did not defer the merchant''s stake (invest %)', v_city;
    end if;
    v_city := public.npc_tend(now());
    perform set_config('byeharu.npc_upkeep_deadline', '', true);
    if not (v_city ? 'invested') or (v_city->>'deferred')::int < 1 then
      raise exception '0123 self-assert FAIL: npc_tend does not carry the investment (tend %)', v_city;
    end if;
    v_notes := v_notes || format('%s at 3 × capital bought %s shares at %s d. at her best stop, at 1.9 × nothing, a spent budget deferred her; ',
                                 v_house.company_name, v_n, v_price);

    raise exception 'ROLLBACK_0123';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0123' then raise; end if;
  end;

  if public.city_treasury_on() or public.wc('npc_traders_enabled') <> v_npc_on or public.wc('standing_routes_enabled') <> v_rt_on
     or exists (select 1 from public.city_shares) or exists (select 1 from public.city_works where level <> 0 or subscribed <> 0)
     or exists (select 1 from public.players where auth_uid = c_probe) then
    raise exception '0123 self-assert FAIL: the probe world was not rolled back';
  end if;

  raise notice '0123 self-assert ok: A CITY BUILDS WITH OTHER PEOPLE''S MONEY. The door, the readers and the payout are server-only, cmd.invest / cmd.preview_invest / world.town_hall authenticated-only and registered, no client write grant, the register unreadable; every harbour has its four works at level 0 and the spread of every harbour and 200 allowances equal their pre-images byte for byte. Dark: nothing offered and the read says so. Lit: an undocked house was refused E_NOT_DOCKED and the read''s docked agrees; the dry run moved nothing; an unknown work, 101 of 100 shares (with figures) and a dust stake were refused; %the Town Hall named the investor and a stranger saw the same list without holdings; level 5 narrowed the spread by 5 steps, composed the allowance, the regeneration and the draft (+2), and the inn brought 10 hands and never passed its cap. Rolled back; investment ships DARK.',
    v_notes;
end $$;

drop table pg_temp.pre_0123_spread;
drop table pg_temp.pre_0123_cap;
