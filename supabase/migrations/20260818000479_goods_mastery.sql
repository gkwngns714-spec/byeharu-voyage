-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0479 - GOODS MASTERY: A LADDER PER GOOD  (dark: the owner's switch goods_mastery_enabled, false; lit, every good a company sells has a
--        ladder 1-10 earned by the units she sells of it: each level a slightly better sale price and a bigger day's allowance, and at
--        the top the good's name in gold; her highest good is her specialty)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE DESIGN: docs/design/roadmap-2026-11-23.md slice 11 ("Goods mastery", Melvor's mastery per item); docs/dev-log/2026-11-23-goods-mastery.md.
--   The roadmap numbered it 0480; the logbook took 0478, so it is 0479 (prod head + 1).
--
-- WHY: a trader who has run pepper a hundred times sells it no better than on her first day. Melvor keeps a mastery per item: the more
--   you work one, the better it pays. Uncharted Waters' traders have their goods. It asks nothing new of her: it counts what she sells.
--
-- WHAT (DECIDED BY DEFAULT; the owner may reverse any of it; every figure is a knob):
--   THE TABLE public.goods_mastery: one row a company and a good she has sold (its primary key the guard; at most 629 a company), her
--     units sold of it and the level they make. MERCHANTS (players.is_npc) keep none: nothing is written for them.
--   THE LADDER (goods_mastery_units, the units sold to reach levels 1..10): 1, 100, 250, 500, 1,000, 2,000, 3,500, 6,000, 10,000, 16,000.
--     Melvor-like: level 1 is her first sale, 2-4 a load or a few (a hold carries ~100-300 units), 10 is about a hundred loads.
--   EACH LEVEL GIVES (from the level she holds BEFORE the sale):
--     PRICE: her sale price of the good x (1 + level x goods_mastery_price_step) (0.005: +0.5 % a level, +5 % at 10), through THE ONE
--       place a sale is priced: world.quote_terms' bid factor (one hunk -> public.goods_mastery_bid), so world.quote, cmd.do_sell, the
--       Trade desk's cards (world.best_sales -> world.board_sell -> world.quote, a per-row factor), the goods board and the dry runs agree.
--       NEVER PAST THE QUAY'S OWN ASK: the factor is held under (1 + s/2) / (1 - s/2) for the spread s she trades at, so a buy and the
--       sale of the same units at one quay never pays (the shelf rule of 0211 kept): it binds below a 4.9 % spread (a shaved one, or a
--       quay's own: Setubal's andalusian horses, 4.2 %, give +4.3 % at level 10, not +5 %).
--     ALLOWANCE: her day's allowance of the good at a harbour (THE ONE reading, world.daily_cap_remaining: one hunk ->
--       public.goods_mastery_cap) x (1 + level x goods_mastery_cap_step) (0.05: +50 % at 10). The allowance is one figure for buying and
--       selling the good there (trade_daily), so the bigger one serves both; a pirate home's ceiling grows with it.
--   THE MONEY LAW: the economy is closed, and a sale is paid by the city's purse, the whole total (0233: public.city_pays, a treasury row
--     -total and her credit +total). The better price is part of that total, so the purse pays it: nothing is made from air, W unchanged.
--     A purse short of the dearer lot shrinks it or refuses (E_CITY_BROKE) as before, judged on the price she is paid. Proof 182 GM_MONEY.
--   THE WRITER, at the one existing sale point, never a scan: cmd.do_sell's SOLD payload (one hunk, after the logbook's ->
--     public.goods_mastery_sale). Every sale settles there: a quay sale, a standing route's lap (cmd.run_manifest calls cmd.do_sell); an
--     arrival sells through those (voyage.settle sells nothing itself). Dark '{}' after one knob read; a merchant '{}' after one players
--     probe. Lit, a company: her units of the good grow by the units sold, and `mastery` {good, level, from, units, at, next, up} rides
--     the SOLD event (up: the level rose; the arrival card's chip and the level-up toast). Never raises: a fault is a warning and '{}'.
--   THE READ, world.goods_mastery() (the client's one door, registered): dark {"on": false}. Lit: each good she has sold with its level,
--     units, the units its level began at and the next one's; her specialty (the highest level, then the most units); the ladder and
--     the steps. Writes nothing.
-- THE BACK-FILL (once, here, dark, set-based): for each company that is not a merchant (prod 2026-11-23: 19 of them, 33 SOLD events), the
--   units of her SOLD events by good (by name, as the payload writes them, or by code) and the level they make. Read by the
--   (player_id, created_at) index per company. Dark it moves nothing a player sees (both factors are 1 while dark). Merchants are not read.
-- ONE AUTHORITY EACH: the rows, public.goods_mastery_sale; the level, public.goods_mastery_level; the price, public.goods_mastery_bid read
--   by world.quote_terms alone; the allowance, public.goods_mastery_cap read by world.daily_cap_remaining alone; the page, world.goods_mastery().
-- NOT CHANGED: a buy's price, a merchant's price or allowance, a quote with no fleet named (world.trade_routes, the merchants' planner),
--   the logbook, any other step of a sale, or anyone while dark. No knob of another feature moves.
-- ROWS: dark none (the back-fill once: at most 19 x her goods). Lit: one row a company and a good sold, updated at each of her sales.
--   -- budget: one new table of at most 629 rows a company (non-merchants only), an update at each of her sales, no job, no cron, no index beyond its primary key.
-- COST: dark one knob read at a sale, a quote for a fleet and a day's allowance; a quote with no fleet named nothing. Lit: a quote for a
--   fleet two key probes (her fleet, her row), an allowance one; a sale one upsert.
-- LOCKS: CREATE TABLE (new, no foreign key: one would lock public.players); CREATE FUNCTION x5; CREATE OR REPLACE x4 by a hunk each
--   (cmd.do_sell, world.quote_terms, world.daily_cap_remaining, public.client_rpc_entry_points); four knobs. TIME: a second.
--   BUDGET: statement_timeout 45 s, lock_timeout 5 s; fails above 30 s.
-- ROLLBACK (forward, owner only): QUICK, goods_mastery_enabled false (nothing is written, the price, the allowance and the payload are
--   their pre-images', the read is {"on": false}; the rows stay, inert). Full: a new migration reversing the four hunks (OLD texts below
--   verbatim), dropping the five functions and the table, deleting the knobs.
-- SELF-ASSERT: each hunk once and reversing; no other function moved; the hunked bodies' grants, volatility, definer, search path, owner
--   unmoved; the knobs; the back-fill wrote no merchant row; the table and the server-only functions unreachable by a client,
--   world.goods_mastery registered for authenticated alone. THE PROBE (rolled back; every comparison of two figures is made in ONE SELECT
--   against a pg_temp copy of the pre-image, and nothing read is time-budgeted: world.best_sales is never called): DARK with a level-10
--   row on her, the quote terms, a sale's quote and the allowance equal the pre-image's, a sale writes nothing and adds nothing to its
--   event, the read {"on": false}; LIT the bid factor is the pre-image's x 1.05 (under the quay's ask), the sale quote dearer by it, the
--   allowance x 1.5; a first sale of a good makes level 1 (up), its 100th unit level 2 (up), another sale no level; the purse paid the
--   SOLD total; the read's specialty; a merchant writes nothing. Proof 182 plays it with the purses lit and W.
-- VERSION: 0479 = 0478 + 1 (0478, #825, hunks cmd.do_sell and client_rpc_entry_points; this file's hunks of those are anchored on 0478's own lines).
-- news: none (dark: nothing changes for a player until the owner lights goods_mastery_enabled)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_hunked constant text[] := array['cmd.do_sell(uuid,jsonb)', 'world.quote_terms(uuid,uuid,uuid)',
                                    'world.daily_cap_remaining(uuid,uuid,uuid)', 'public.client_rpc_entry_points()'];
  c_new    constant text[] := array['public.goods_mastery_level(numeric)', 'public.goods_mastery_sale(uuid,uuid,numeric)',
                                    'public.goods_mastery_bid(uuid,uuid,numeric)', 'public.goods_mastery_cap(uuid,uuid)',
                                    'world.goods_mastery()'];
  c_uid    constant uuid := '00000000-0479-4000-8000-000000000001';
  v_t0        timestamptz := clock_timestamp();
  v_h         record;
  x           record;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_fn_before text;
  v_meta      text;
  v_note      text := '';
  v_lived     boolean := false;
  v_back      jsonb;
  v_set       uuid;
  v_me        uuid;
  v_fl        uuid;
  v_good      uuid;
  v_gcode     text;
  v_good2     uuid;
  v_gcode2    text;
  v_npc       uuid;
  v_r         jsonb;
  v_f         record;
  v_ev        uuid;
  v_s         jsonb;
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.world_config where key = 'goods_mastery_enabled') or to_regclass('public.goods_mastery') is not null then
    raise exception '0479 refuses: it has been applied once';
  end if;
  if to_regprocedure('public.logbook_sale(uuid,uuid)') is null or to_regprocedure('world.logbook()') is null
     or to_regprocedure('public.city_bid_factor(uuid)') is null or to_regprocedure('public.daily_cap_base(uuid,uuid)') is null
     or to_regprocedure('cmd.assume_identity(uuid)') is null then
    raise exception '0479 refuses: 0478 (the logbook), 0318 (the allowance), 0122 (the purses) or 0213 is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGE ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  -- the quote's terms and the day's allowance as they are, kept for the probe's comparisons (dropped at the end)
  execute replace(replace(pg_get_functiondef('world.quote_terms(uuid,uuid,uuid)'::regprocedure), E'\r', ''),
                  'FUNCTION world.quote_terms(', 'FUNCTION pg_temp.quote_terms_pre_0479(');
  execute replace(replace(pg_get_functiondef('world.daily_cap_remaining(uuid,uuid,uuid)'::regprocedure), E'\r', ''),
                  'FUNCTION world.daily_cap_remaining(', 'FUNCTION pg_temp.daily_cap_remaining_pre_0479(');

  -- ── 2. THE KNOBS AND THE TABLE ──
  insert into public.world_config (key, value, description) values
    ('goods_mastery_enabled', 'false'::jsonb,
     '0479: THE SWITCH (the owner''s). true: each good a company sells has a ladder 1-10 (public.goods_mastery, written at her sales by public.goods_mastery_sale): each level a better sale price (goods_mastery_price_step, through world.quote_terms) and a bigger day''s allowance (goods_mastery_cap_step, through world.daily_cap_remaining); the SOLD event says her level; world.goods_mastery() serves the page. false: nothing is written, the price, the allowance and the payload are as before, the read is {"on": false}.'),
    ('goods_mastery_units', '[1, 100, 250, 500, 1000, 2000, 3500, 6000, 10000, 16000]'::jsonb,
     '0479: the units of a good a company must have sold to reach mastery levels 1..10 (ten rising figures; public.goods_mastery_level).'),
    ('goods_mastery_price_step', to_jsonb(0.005), '0479: each mastery level of a good raises her sale price of it by this share (0.005: +5 % at 10), never past the quay''s own ask (public.goods_mastery_bid).'),
    ('goods_mastery_cap_step', to_jsonb(0.05), '0479: each mastery level of a good raises her day''s allowance of it at a harbour by this share (0.05: +50 % at 10; public.goods_mastery_cap).');

  -- retention: none, bounded by its primary key: one row a company and a good she has sold, at most 629 a non-merchant company.
  create table public.goods_mastery (
    player_id  uuid        not null,
    good_id    uuid        not null,
    units      numeric     not null default 0 check (units >= 0),
    level      smallint    not null default 0 check (level between 0 and 10),
    updated_at timestamptz not null default now(),
    primary key (player_id, good_id)
  );
  comment on table public.goods_mastery is
    '0479: GOODS MASTERY, a company''s units sold of each good and the level they make (public.goods_mastery_level). Written at her sale '
    '(cmd.do_sell -> public.goods_mastery_sale) alone; read by public.goods_mastery_bid (the price), public.goods_mastery_cap (the '
    'allowance) and world.goods_mastery() (the page). Merchants keep none. No foreign key on purpose: one would lock public.players.';
  alter table public.goods_mastery enable row level security;
  revoke all on table public.goods_mastery from public, anon, authenticated;

  -- ── 3. THE RULES ──
  execute $f$
create function public.goods_mastery_level(p_units numeric)
returns integer
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0479: THE LEVEL a count of units sold makes: how many of goods_mastery_units' figures it reaches (0 to 10). The one reading of the ladder.
  select count(*)::int from jsonb_array_elements_text(public.wc('goods_mastery_units')) t(v) where coalesce(p_units, 0) >= t.v::numeric
$body$
  $f$;

  execute $f$
create function public.goods_mastery_sale(p_player uuid, p_good uuid, p_units numeric)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0479: A SALE ON HER LADDER, from cmd.do_sell's SOLD payload (what this answers is added to the event). Dark: '{}' after one knob read.
-- A merchant (or nobody): '{}' after one players probe. Lit, a company: her units of the good grow by the units sold (one upsert on its
-- primary key) and the level is read again; answers mastery {good, level, from, units, at, next, up} (at: the units the level began at,
-- next: the next level's, null at the top; up: the level rose). Never raises: a fault is a warning and '{}', so a sale never fails here.
declare
  v_code  text;
  v_from  int;
  v_lv    int;
  v_units numeric;
  v_lad   jsonb;
begin
  if public.wc('goods_mastery_enabled') is distinct from 'true'::jsonb then
    return '{}'::jsonb;
  end if;
  if p_player is null or coalesce((select pl.is_npc from public.players pl where pl.id = p_player), true) then
    return '{}'::jsonb;
  end if;
  if p_good is null or coalesce(p_units, 0) <= 0 then
    return '{}'::jsonb;
  end if;
  begin
    select g.code into v_code from public.goods g where g.id = p_good;
    if v_code is null then
      return '{}'::jsonb;
    end if;
    v_from := coalesce((select m.level from public.goods_mastery m where m.player_id = p_player and m.good_id = p_good), 0);
    insert into public.goods_mastery as m (player_id, good_id, units, level, updated_at)
    values (p_player, p_good, p_units, public.goods_mastery_level(p_units), now())
    on conflict (player_id, good_id) do update
      set units = m.units + excluded.units, level = public.goods_mastery_level(m.units + excluded.units), updated_at = now()
    returning m.units, m.level into v_units, v_lv;
    v_lad := public.wc('goods_mastery_units');
    return jsonb_build_object('mastery', jsonb_build_object(
      'good', v_code, 'level', v_lv, 'from', v_from, 'units', v_units,
      'at', case when v_lv > 0 then (v_lad ->> (v_lv - 1))::numeric end,
      'next', case when v_lv < jsonb_array_length(v_lad) then (v_lad ->> v_lv)::numeric end,
      'up', v_lv > v_from));
  exception when others then
    raise warning 'goods_mastery_sale: % selling % of % was not written (SQLSTATE %: %)', p_player, p_units, p_good, sqlstate, sqlerrm;
    return '{}'::jsonb;
  end;
end
$body$
  $f$;

  execute $f$
create function public.goods_mastery_bid(p_fleet uuid, p_good uuid, p_spread numeric)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0479: WHAT HER MASTERY OF A GOOD ADDS TO HER SALE PRICE OF IT, as a factor on the city's bid (read by world.quote_terms alone, so every
-- reader of a sale's price agrees). No fleet or no good named (a quay's own terms: world.trade_routes, the merchants' planner): 1 at once.
-- Dark: 1 after one knob read. No row (every merchant): 1 after two key probes. Else 1 + level x goods_mastery_price_step, held under
-- (1 + s/2) / (1 - s/2) for the spread s she trades at, so the bid never passes the same quay's ask (a round trip never pays).
declare
  v_lv int;
  v_f  numeric;
begin
  if p_fleet is null or p_good is null then
    return 1;
  end if;
  if public.wc('goods_mastery_enabled') is distinct from 'true'::jsonb then
    return 1;
  end if;
  select m.level into v_lv
    from public.fleets f join public.goods_mastery m on m.player_id = f.player_id and m.good_id = p_good
   where f.id = p_fleet;
  if coalesce(v_lv, 0) <= 0 then
    return 1;
  end if;
  v_f := 1 + v_lv * greatest(0, coalesce(public.wc_num('goods_mastery_price_step'), 0));
  if p_spread is not null and p_spread >= 0 and p_spread < 2 then
    v_f := least(v_f, (1 + p_spread / 2) / (1 - p_spread / 2));
  end if;
  return greatest(1, v_f);
end
$body$
  $f$;

  execute $f$
create function public.goods_mastery_cap(p_player uuid, p_good uuid)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0479: WHAT HER MASTERY OF A GOOD ADDS TO HER DAY'S ALLOWANCE OF IT, as a factor (read by world.daily_cap_remaining alone, so the door,
-- the tray's Max and the cards agree). Dark: 1 after one knob read. No row (every merchant): 1 after one key probe. Else 1 + level x
-- goods_mastery_cap_step.
declare
  v_lv int;
begin
  if p_player is null or p_good is null then
    return 1;
  end if;
  if public.wc('goods_mastery_enabled') is distinct from 'true'::jsonb then
    return 1;
  end if;
  select m.level into v_lv from public.goods_mastery m where m.player_id = p_player and m.good_id = p_good;
  if coalesce(v_lv, 0) <= 0 then
    return 1;
  end if;
  return 1 + v_lv * greatest(0, coalesce(public.wc_num('goods_mastery_cap_step'), 0));
end
$body$
  $f$;

  execute $f$
create function world.goods_mastery()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0479: GOODS MASTERY, the client's one door. Dark (goods_mastery_enabled false): {"on": false}. Lit, signed out or a merchant:
-- {"on": true, "company": false}. Lit, her company: each good she has sold {good, kind, level, units, at, next} (the highest level first,
-- then the most units), her specialty (the first of them, null with none), the ladder (goods_mastery_units), top (its length), and the
-- two steps. Writes nothing.
declare
  v_me  uuid := public.current_player_id();
  v_lad jsonb;
begin
  if public.wc('goods_mastery_enabled') is distinct from 'true'::jsonb then
    return jsonb_build_object('on', false);
  end if;
  if v_me is null or coalesce((select pl.is_npc from public.players pl where pl.id = v_me), true) then
    return jsonb_build_object('on', true, 'company', false);
  end if;
  v_lad := public.wc('goods_mastery_units');
  return (
    with mine as (
      select g.code, g.category, m.level, m.units
        from public.goods_mastery m join public.goods g on g.id = m.good_id
       where m.player_id = v_me and m.level > 0
    ), ranked as (
      select jsonb_build_object('good', x.code, 'kind', x.category, 'level', x.level, 'units', x.units,
                                'at', (v_lad ->> (x.level - 1))::numeric,
                                'next', case when x.level < jsonb_array_length(v_lad) then (v_lad ->> x.level)::numeric end) as o,
             row_number() over (order by x.level desc, x.units desc, x.code) as rk
        from mine x
    )
    select jsonb_build_object(
      'on', true,
      'company', true,
      'goods', (select coalesce(jsonb_agg(r.o order by r.rk), '[]'::jsonb) from ranked r),
      'specialty', (select r.o from ranked r where r.rk = 1),
      'ladder', v_lad,
      'top', jsonb_array_length(v_lad),
      'price_step', coalesce(public.wc_num('goods_mastery_price_step'), 0),
      'cap_step', coalesce(public.wc_num('goods_mastery_cap_step'), 0))
  );
end
$body$
  $f$;
  revoke all on function public.goods_mastery_level(numeric) from public, anon, authenticated;
  revoke all on function public.goods_mastery_sale(uuid, uuid, numeric) from public, anon, authenticated;
  revoke all on function public.goods_mastery_bid(uuid, uuid, numeric) from public, anon, authenticated;
  revoke all on function public.goods_mastery_cap(uuid, uuid) from public, anon, authenticated;
  revoke all on function world.goods_mastery() from public, anon;
  grant execute on function world.goods_mastery() to authenticated;
  comment on function world.goods_mastery() is
    '0479: goods mastery (dark {"on": false}): each good she has sold with its level 1-10, her specialty, the ladder and the steps. A read. Client door.';

  -- ── 4. THE HUNKS (each occurs exactly once in the live body, and reverses) ──
  create temp table hunks_0479 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0479 values
  ('cmd.do_sell(uuid,jsonb)', 1,
$h$      || public.logbook_sale(f.player_id, g.id)));$h$,
$h$      || public.logbook_sale(f.player_id, g.id)
      -- 0479: goods mastery: her level of this good after the sale (mastery {good, level, from, units, at, next, up}; '{}' dark, a merchant)
      || public.goods_mastery_sale(f.player_id, g.id, q.units)));$h$),
  ('world.quote_terms(uuid,uuid,uuid)', 1,
$h$  q_bidf   := public.city_bid_factor(p_port);$h$,
$h$  q_bidf   := public.city_bid_factor(p_port)
              -- 0479: her mastery of the good (public.goods_mastery_bid: 1 with no fleet or good named, dark, for a merchant, under her
              -- first sale; never past this quay's ask). The bid factor is read on a sale's side alone (world.quote_priced).
              * public.goods_mastery_bid(p_fleet, p_good, q_spread);$h$),
  ('world.daily_cap_remaining(uuid,uuid,uuid)', 1,
$h$  select greatest(0,
           case when public.pirates_on() and public.pirate_home(p_port)$h$,
$h$  select greatest(0,
           -- 0479: her mastery of the good (public.goods_mastery_cap: 1 dark, for a merchant, under her first sale) grows the day's allowance
           public.goods_mastery_cap(p_player, p_good) *
           case when public.pirates_on() and public.pirate_home(p_port)$h$),
  ('public.client_rpc_entry_points()', 1,
$h$      ('world',       'logbook',               ''),$h$,
$h$      ('world',       'logbook',               ''),
      -- 0479: goods mastery (dark: {"on": false})
      ('world',       'goods_mastery',         ''),$h$);

  for v_h in select h.fn from hunks_0479 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0479 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0479 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0479 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0479 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0479 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 5. THE BACK-FILL (once; companies, not merchants; her units of each good sold, from her SOLD events) ──
  insert into public.goods_mastery (player_id, good_id, units, level, updated_at)
  select s.player_id, s.good_id, s.units, public.goods_mastery_level(s.units), now()
    from (select hu.id as player_id, gg.id as good_id, sum((e.payload ->> 'qty')::numeric) as units
            from public.players hu
            cross join lateral (select ex.payload from public.events ex where ex.player_id = hu.id and ex.kind = 'SOLD') e
            cross join lateral (select g.id from public.goods g where g.code = e.payload ->> 'good' or g.name = e.payload ->> 'good'
                                 order by (g.code = e.payload ->> 'good') desc, g.code limit 1) gg
           where not hu.is_npc and jsonb_typeof(e.payload -> 'qty') = 'number'
           group by hu.id, gg.id) s
   where s.units > 0;
  select jsonb_build_object('rows', (select count(*) from public.goods_mastery),
                            'companies', (select count(distinct m.player_id) from public.goods_mastery m),
                            'levels', (select coalesce(jsonb_object_agg(z.level, z.n), '{}'::jsonb)
                                         from (select m.level, count(*) as n from public.goods_mastery m group by m.level) z))
    into v_back;

  -- ── 6. SELF-ASSERT: the catalog, the knobs, the back-fill, the door ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_new) u(q)))) <> v_fn_before then
    raise exception '0479 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0479 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if public.wc('goods_mastery_enabled') <> 'false'::jsonb or public.wc_num('goods_mastery_price_step') <> 0.005
     or public.wc_num('goods_mastery_cap_step') <> 0.05
     or public.wc('goods_mastery_units') <> '[1, 100, 250, 500, 1000, 2000, 3500, 6000, 10000, 16000]'::jsonb
     or public.goods_mastery_level(0) <> 0 or public.goods_mastery_level(1) <> 1 or public.goods_mastery_level(99) <> 1
     or public.goods_mastery_level(100) <> 2 or public.goods_mastery_level(15999) <> 9 or public.goods_mastery_level(1000000) <> 10 then
    raise exception '0479 self-assert FAIL: the knobs or the ladder are not as written';
  end if;
  if exists (select 1 from public.goods_mastery m join public.players p on p.id = m.player_id where p.is_npc)
     or exists (select 1 from public.goods_mastery m where not exists (select 1 from public.players p where p.id = m.player_id))
     or exists (select 1 from public.goods_mastery m where m.level <> public.goods_mastery_level(m.units)) then
    raise exception '0479 self-assert FAIL: the back-fill wrote a merchant''s row, a row of nobody, or a level its units do not make';
  end if;
  if (select count(*) from public.client_rpc_entry_points() e
       where (e.schema_name, e.function_name, e.arg_types) = ('world', 'goods_mastery', '')
         and e.fn is not null and has_function_privilege('authenticated', e.fn, 'execute') and not has_function_privilege('anon', e.fn, 'execute')) <> 1
     or has_function_privilege('authenticated', 'public.goods_mastery_level(numeric)', 'execute')
     or has_function_privilege('authenticated', 'public.goods_mastery_sale(uuid,uuid,numeric)', 'execute')
     or has_function_privilege('authenticated', 'public.goods_mastery_bid(uuid,uuid,numeric)', 'execute')
     or has_function_privilege('authenticated', 'public.goods_mastery_cap(uuid,uuid)', 'execute')
     or has_table_privilege('authenticated', 'public.goods_mastery', 'select,insert,update,delete')
     or has_table_privilege('anon', 'public.goods_mastery', 'select')
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0479 self-assert FAIL: world.goods_mastery is not registered for authenticated alone, or a client reaches a server-only function or the table';
  end if;

  -- ── 7. THE PROBE, rolled back by a raised sentinel ──
  begin
    select p.id into v_set from public.ports p where p.code = 'SET' and p.kind = 'HARBOUR';
    -- two goods the harbour of the probe trades, of the deepest markets (the day's allowance holds the probe's 110 units with room)
    select g.id, g.code into v_good, v_gcode
      from public.port_goods pg join public.goods g on g.id = pg.good_id
     where pg.port_id = v_set and not public.culture_refuses((select p.culture from public.ports p where p.id = v_set), g.culture_mask)
     order by pg.stock_target desc, g.code limit 1;
    select g.id, g.code into v_good2, v_gcode2
      from public.port_goods pg join public.goods g on g.id = pg.good_id
     where pg.port_id = v_set and g.id <> v_good and not public.culture_refuses((select p.culture from public.ports p where p.id = v_set), g.culture_mask)
     order by pg.stock_target desc, g.code limit 1;
    v_me := public.new_house(c_uid, 'Casa da Mestria 0479', 'PRT');
    select f.id into v_fl from public.fleets f where f.player_id = v_me;
    select n.id into v_npc from public.players n where n.is_npc order by n.id limit 1;
    -- the purses lit and the economy closed, so the city's purse pays the sale (prod's switches; the image may run them dark)
    update public.world_config set value = 'true'::jsonb where key in ('economy_closed', 'city_treasury_enabled');
    insert into public.port_treasury (port_id) values (v_set) on conflict (port_id) do nothing;
    update public.port_treasury t set ducats = 5000000, reserve = 0 where t.port_id = v_set;
    update public.fleets f set status = 'DOCKED', port_id = v_set, lat = null, lon = null, busy_until = null, ready_at = null where f.id = v_fl;
    -- her top level of the first good, on her row while dark
    insert into public.goods_mastery (player_id, good_id, units, level) values (v_me, v_good, 16000, 10);

    -- (a) DARK: the terms, a sale's quote and the allowance are the pre-image's (ONE SELECT); a sale writes nothing and adds nothing
    select (k.q_spread, k.q_nohag, k.q_tax, k.q_bidf) is not distinct from (k0.q_spread, k0.q_nohag, k0.q_tax, k0.q_bidf) as terms,
           q.total as q_now, q0.total as q_pre,
           world.daily_cap_remaining(v_me, v_set, v_good) as cap_now, pg_temp.daily_cap_remaining_pre_0479(v_me, v_set, v_good) as cap_pre
      into v_f
      from world.quote_terms(v_set, v_good, v_fl) k
     cross join pg_temp.quote_terms_pre_0479(v_set, v_good, v_fl) k0
     cross join world.quote(v_set, v_good, 30, 'sell', null, v_fl) q
     cross join world.quote_priced(v_set, v_good, 30, 'sell', null, v_fl, k0.q_spread, k0.q_nohag, k0.q_tax, k0.q_bidf) q0;
    if not v_f.terms or v_f.q_now is distinct from v_f.q_pre or v_f.cap_now is distinct from v_f.cap_pre then
      raise exception '0479 self-assert FAIL: dark, a price or the allowance moved with a level-10 row on her: %', to_jsonb(v_f);
    end if;
    update public.ships s set cargo = jsonb_build_object(v_gcode, 40), cargo_basis = jsonb_build_object(v_gcode, 1) where s.fleet_id = v_fl;
    perform cmd.do_sell(v_fl, jsonb_build_object('good', v_good, 'qty', 10));
    perform cmd.assume_identity(c_uid);
    if exists (select 1 from public.events e where e.player_id = v_me and e.kind = 'SOLD' and e.payload ? 'mastery')
       or not exists (select 1 from public.events e where e.player_id = v_me and e.kind = 'SOLD')
       or (select m.units from public.goods_mastery m where m.player_id = v_me and m.good_id = v_good) <> 16000
       or (select count(*) from public.goods_mastery m where m.player_id = v_me) <> 1
       or public.goods_mastery_sale(v_me, v_good, 10) <> '{}'::jsonb
       or public.goods_mastery_bid(v_fl, v_good, 0.06) <> 1 or public.goods_mastery_cap(v_me, v_good) <> 1
       or world.goods_mastery() is distinct from '{"on": false}'::jsonb then
      raise exception '0479 self-assert FAIL: dark, a sale wrote or told mastery, a factor is not 1, or the read is not {"on": false}';
    end if;

    -- (b) LIT: the bid factor x 1.05 (under the ask), the sale quote dearer by it, the allowance x 1.5 (ONE SELECT, against the pre-image)
    update public.world_config set value = 'true'::jsonb where key = 'goods_mastery_enabled';
    select k.q_bidf as bidf, k0.q_bidf as bidf0, k0.q_spread as s0,
           (k.q_spread, k.q_nohag, k.q_tax) is not distinct from (k0.q_spread, k0.q_nohag, k0.q_tax) as rest,
           q.total as q_now, q0.total as q_pre, q.units as u,
           world.daily_cap_remaining(v_me, v_set, v_good) as cap_now, pg_temp.daily_cap_remaining_pre_0479(v_me, v_set, v_good) as cap_pre,
           coalesce((select td.qty from public.trade_daily td where td.player_id = v_me and td.port_id = v_set and td.good_id = v_good
                        and td.game_day = world.game_day()), 0) as traded
      into v_f
      from world.quote_terms(v_set, v_good, v_fl) k
     cross join pg_temp.quote_terms_pre_0479(v_set, v_good, v_fl) k0
     cross join world.quote(v_set, v_good, 30, 'sell', null, v_fl) q
     cross join world.quote_priced(v_set, v_good, 30, 'sell', null, v_fl, k0.q_spread, k0.q_nohag, k0.q_tax, k0.q_bidf) q0;
    if not v_f.rest or v_f.u <> 30
       or abs(v_f.bidf - v_f.bidf0 * least(1.05, (1 + v_f.s0 / 2) / (1 - v_f.s0 / 2))) > 0.0000001
       or v_f.q_now <= v_f.q_pre
       or abs(v_f.q_now - v_f.q_pre * v_f.bidf / v_f.bidf0) > v_f.u
       or abs((v_f.cap_now + v_f.traded) - 1.5 * (v_f.cap_pre + v_f.traded)) > 0.001 then
      raise exception '0479 self-assert FAIL: lit, the price or the allowance of a level-10 good is not the pre-image''s by its factor: %', to_jsonb(v_f);
    end if;
    -- the sale of the level-10 good: the purse paid the SOLD total, and the event says level 10, not risen
    perform cmd.do_sell(v_fl, jsonb_build_object('good', v_good, 'qty', 10));
    select e.id, e.payload into v_ev, v_s from public.events e
     where e.player_id = v_me and e.kind = 'SOLD' and e.payload ? 'mastery' order by e.created_at desc, e.id limit 1;
    if v_s #>> '{mastery,good}' is distinct from v_gcode or (v_s #>> '{mastery,level}')::int <> 10 or (v_s #>> '{mastery,up}')::boolean
       or (v_s #>> '{mastery,units}')::numeric <> 16010 or v_s #> '{mastery,next}' <> 'null'::jsonb
       or (select coalesce(sum(t.ducats), 0) from public.treasury_flows t where t.ref_event = v_ev and t.kind = 'SELL') <> -(v_s ->> 'total')::numeric then
      raise exception '0479 self-assert FAIL: lit, the level-10 sale was not told, or the purse did not pay its total: % %', v_s -> 'mastery', v_s -> 'total';
    end if;
    -- a first sale of another good makes level 1 (up); its 100th unit level 2 (up); one more sale no level
    update public.ships s set cargo = jsonb_build_object(v_gcode2, 200), cargo_basis = jsonb_build_object(v_gcode2, 1) where s.fleet_id = v_fl;
    perform cmd.do_sell(v_fl, jsonb_build_object('good', v_good2, 'qty', 10));
    perform cmd.do_sell(v_fl, jsonb_build_object('good', v_good2, 'qty', 90));
    perform cmd.do_sell(v_fl, jsonb_build_object('good', v_good2, 'qty', 10));
    select jsonb_agg(jsonb_build_array((e.payload #>> '{mastery,level}')::int, (e.payload #>> '{mastery,up}')::boolean, (e.payload #>> '{mastery,units}')::numeric)
                     order by (e.payload #>> '{mastery,units}')::numeric)
      into v_r from public.events e where e.player_id = v_me and e.kind = 'SOLD' and e.payload #>> '{mastery,good}' = v_gcode2;
    if v_r is distinct from '[[1, true, 10], [2, true, 100], [2, false, 110]]'::jsonb
       or (select m.level from public.goods_mastery m where m.player_id = v_me and m.good_id = v_good2) <> 2 then
      raise exception '0479 self-assert FAIL: lit, the ladder of a new good did not climb 1 then 2 then stay: %', v_r;
    end if;
    -- the read: her specialty is the level-10 good; a merchant is written nothing and keeps factor 1
    v_r := world.goods_mastery();
    if (v_r ->> 'company')::boolean is not true or v_r #>> '{specialty,good}' is distinct from v_gcode
       or (v_r #>> '{specialty,level}')::int <> 10 or jsonb_array_length(v_r -> 'goods') <> 2 or (v_r ->> 'top')::int <> 10
       or public.goods_mastery_sale(v_npc, v_good, 10) <> '{}'::jsonb or public.goods_mastery_cap(v_npc, v_good) <> 1
       or exists (select 1 from public.goods_mastery m where m.player_id = v_npc)
       -- the round-trip guard: at a spread shaved to 1.2 % the factor is the quay's ask over its bid, not 1.05
       or abs(public.goods_mastery_bid(v_fl, v_good, 0.012) - 1.006 / 0.994) > 0.0000001 then
      raise exception '0479 self-assert FAIL: lit, the read, a merchant or the round-trip guard is not as written: %', left(v_r::text, 600);
    end if;
    v_note := format('%s at 10: bid x%s, a 30-unit sale %s -> %s, allowance %s -> %s; %s climbed 1, 2, 2',
                     v_gcode, round(v_f.bidf / v_f.bidf0, 4), v_f.q_pre, v_f.q_now, round(v_f.cap_pre, 1), round(v_f.cap_now, 1), v_gcode2);
    raise exception using errcode = 'ZX479', message = 'PROBE_ROLLBACK_0479';
  exception when sqlstate 'ZX479' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0479 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.company_name like '% 0479' or p.auth_uid = c_uid)
     or public.wc('goods_mastery_enabled') is distinct from 'false'::jsonb
     or public.current_player_id() is not null then
    raise exception '0479 self-assert FAIL: the probe left something behind';
  end if;
  drop function pg_temp.quote_terms_pre_0479(uuid, uuid, uuid);
  drop function pg_temp.daily_cap_remaining_pre_0479(uuid, uuid, uuid);

  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0479 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0479 self-assert ok: GOODS MASTERY (dark). % hunks once and reversing; grants and volatility unmoved; no other function moved; the table, five functions, four knobs (goods_mastery_enabled false). Back-filled %. Probe (rolled back): dark the terms, the quote and the allowance the pre-image''s with a level-10 row, nothing written or told; lit %; the purse paid the SOLD total; a merchant nothing. % ms.',
    (select count(*) from hunks_0479), coalesce(v_back, '{}'::jsonb), v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
