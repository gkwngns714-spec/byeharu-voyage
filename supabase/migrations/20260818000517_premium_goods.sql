-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none (dark: nothing changes for a player until the owner lights premium_goods_enabled)
-- 0517 - PREMIUM GOODS: ONE MADE GOOD, ONE CITY THAT PAYS 3 TO 5 TIMES  (dark: the owner's switch premium_goods_enabled, false.
--   Slice `premium-goods`: owner-spec-2026-11-25.md rows 18 and 24, answer 5; owner-spec-red-2026-11-25.md R7 and R8)
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-25: "Some trade goods can be combined to create PREMIUM TRADE GOODS. Each PTG will be needed by one city only, and it
--   will pay 300~500% more. PREMIUM TRADE GOODS by themselves costs more. 1 PTG linked with 1 city." Then: "3-5 times, with daily limits yes";
--   R7 "far cities pay closer to 5 times, near cities closer to 3 times. - YES"; R8 "We already have premium trade goods no? ... if so, reuse".
-- WHAT IS ADDED: no good and no recipe. 100 of the made goods of 0280 get their one city (goods.premium_port_id, data; one good a city).
-- LIT (and the economy closed with the city purses on, else nothing: an open economy would mint it):
--   THE PAY: that city buys it from a COMPANY at 3 to 5 times its own normal price there: premium_mult_near at premium_near_nm sailed miles or
--     fewer from the good's nearest maker (port_goods.haul_nm, 0173's one derivation from public.sea_reaches) to premium_mult_far at
--     premium_far_nm, straight between (public.premium_mult). Any other city: the normal price. Never times a want (0255) as well.
--   THE DAILY LIMIT: premium_day_units a real UTC day (public.real_day, the day a bargain counts by), shared by all companies; the rest of a
--     load sells at the normal price in the same quote. Counted on the market's own row (port_goods.premium_day / premium_units), locked.
--   A SMALL PURSE: the units are also no more than premium_purse_share of what the city holds above its reserve and its floor
--     (public.treasury_balance, port_treasury.reserve, public.city_floor) can pay whole: none to spare, no premium. The rest of the empty-purse
--     rule of cmd.do_sell is unmoved. No coin is made: the sale is one SELL of public.city_pays, from that purse.
--   A PREMIUM GOOD COSTS MORE: its base price is premium_price_lift (1.25) times, everywhere, buying and selling (world.mid_terms).
--   ONLY WHAT SHE MADE: the units are also no more than the company made in its Forge and has not yet sold at a premium (public.premium_made:
--     counted by cmd.forge_good, dark too; before this file by its FORGED events). What she bought at a quay is paid the normal price.
--     A count a company and good, not a mark on each unit. What the land's smith makes is not counted.
--   Not where the city offers the good itself (no buying and selling at one quay). A merchant and a quote with no fleet: the normal price.
-- READ FROM ONE PLACE: public.premium_left, by THE one quote (world.quote_priced) and by the door's tally (cmd.do_sell). The sale's face, the
--   Best cards, the boards, the day (public.run_day) and the never-lose rule (0498) ask that quote, so none is re-cut; the board's shortlist
--   always prices the premium city. FACES: world.market rows and world.goods_forge recipes carry `premium`.
-- THE DEFAULT LIST (decided by default; the owner may reverse; NOT the deck's twelve, which were not approved): the 100 recipes whose good is
--   worth most against its materials (205 of 287 are worth LESS than their materials at base; a good no city offers has no maker to measure
--   from), the dearer the good the farther its city (500 to 12,000 miles), each city of size 3 or 5 at most once, never one that offers or
--   makes the good or whose culture refuses it. docs/dev-log/2026-11-25-premium-goods.md lists it. To move one: update goods.premium_port_id.
-- DARK (as deployed): byte-identical answers.
-- THE HUNKS (17; each once in the live body, all reverse): world.quote_priced 3, cmd.do_sell 6, world.mid_terms 1, world.good_mids 1,
--   world.market 3, world.goods_forge 1, world.board_sell_memo 1, cmd.forge_good 1. NEW: 11 functions, server only. KNOBS: 8. NOT CHANGED: every other.
-- ROWS: 100 goods get a value; one table, public.premium_made: one row a company and good it has made (a row written a forging, none a minute).
--   budget: none (no cron job, no autovacuum setting). -- retention: none, bounded by one row a company and made good (287 at most).
-- THE TICK'S COST: no tick, no beat step. Lit: one lookup by key in a company's sale quote; in the premium city five more key reads.
-- LOCKS: ALTER TABLE goods (one column, a reference), port_goods (two columns, no rewrite); CREATE TABLE x1; CREATE OR REPLACE x8 by hunks. Under a second.
--   BUDGET: statement_timeout 45 s, lock_timeout 5 s; fails above 30 s.
-- ROLLBACK (forward, owner only): QUICK, premium_goods_enabled false. FULL: scripts/ops/harness/premium-goods/rollback-0517.sql (a draft).
-- SELF-ASSERT: each hunk once and reversing; no other function moved; grants and settings unmoved; no other knob moved; the new functions server
--   only; the list. THE PROBE (rolled back by a raised sentinel; no role changed; INDEPENDENT OF PROD'S MARKET, DICE, COMPANIES AND AGE: a company
--   founded inside it, Lisbon's row of one good and its purse written inside it). Proof 221 plays it through the Forge, two companies and the jobs.
-- VERSION: 0517 (after 0507 and what the lead deploys before it, in number order).
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
do $m$
declare
  c_hunked constant text[] := array['world.quote_priced(uuid,uuid,numeric,text,numeric,uuid,numeric,numeric,numeric,numeric)', 'cmd.do_sell(uuid,jsonb)', 'world.mid_terms(uuid,uuid)', 'world.good_mids(uuid)', 'world.market(uuid)', 'world.goods_forge(uuid)', 'world.board_sell_memo(uuid,uuid,jsonb,jsonb)', 'cmd.forge_good(uuid,uuid,integer)'];
  c_new    constant text[] := array['public.premium_on()', 'public.premium_lift()', 'public.premium_mult(numeric)', 'public.premium_units(uuid,uuid)', 'public.premium_left(uuid,uuid,uuid)', 'public.premium_mine(uuid,uuid)', 'public.premium_count(uuid,uuid,numeric)', 'public.premium_hold(uuid,uuid)', 'public.premium_spend(uuid,uuid,uuid,numeric)', 'public.premium_port(uuid)', 'public.premium_face(uuid)'];
  c_knobs  constant text[] := array['premium_goods_enabled', 'premium_mult_near', 'premium_mult_far', 'premium_near_nm', 'premium_far_nm', 'premium_day_units', 'premium_purse_share', 'premium_price_lift'];
  c_ua     constant uuid := '00000000-0517-4000-8000-0000000000a1';
  v_t0         timestamptz := clock_timestamp();
  x            record;
  v_def        text;
  v_pre        text;
  v_old        text;
  v_new        text;
  v_n          int;
  v_fn_before  text;
  v_meta       text;
  v_cfg_before text;
  v_b          jsonb;
  v_d          jsonb;
  v_l          jsonb;
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.world_config where key = any (c_knobs))
     or exists (select 1 from unnest(c_new) f where to_regprocedure(f) is not null) then
    raise exception '0517 refuses: it has been applied once';
  end if;
  if exists (select 1 from unnest(c_hunked || array['public.real_day(timestamptz)', 'public.city_floor(uuid)', 'public.run_day(uuid,uuid,uuid,uuid,uuid,numeric,numeric,numeric,numeric,numeric)']) f
              where to_regprocedure(f) is null) then
    raise exception '0517 refuses: a body it cuts or reads is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0517 (fn text primary key, def text) on commit drop;
  insert into pre_0517 select f, replace(pg_get_functiondef(f::regprocedure), E'\r', '') from unnest(c_hunked) f;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
    into v_cfg_before from public.world_config c;

  -- ── 2. THE SCENE (a temp function; its own company, Lisbon's row of one good and Lisbon's purse written here) ──
  execute $f$
create function pg_temp.scene_0517(p_uid uuid, p_lit boolean)
returns jsonb
language plpgsql
as $body$
declare
  v_lis uuid := (select h.id from public.ports h where h.code = 'LIS' and h.kind = 'HARBOUR');
  v_set uuid;
  v_pl  uuid;
  v_fl  uuid;
  v_g   uuid;
  v_o   uuid;
  v_c   text;
  v_out jsonb;
  v_r   jsonb;
  v_sum numeric;
begin
  v_pl := public.new_house(p_uid, 'Casa da Prova 0517', 'PRT');
  select f.id into v_fl from public.fleets f where f.player_id = v_pl;
  update public.players set ducats = 1000000 where id = v_pl;
  -- a made good Lisbon does not offer, and a raw one
  select g.id, g.code into v_g, v_c from public.goods g join public.port_goods pg on pg.port_id = v_lis and pg.good_id = g.id
   where exists (select 1 from public.goods_recipes r where r.product_id = g.id) and not public.port_offers(v_lis, g.id) and g.bulk <= 1 and g.base_value >= 100
     and not public.culture_refuses((select h.culture from public.ports h where h.id = v_lis), g.culture_mask) order by g.code limit 1;
  select pg.good_id into v_o from public.port_goods pg join public.goods g on g.id = pg.good_id
   where pg.port_id = v_lis and not exists (select 1 from public.goods_recipes r where r.product_id = g.id) order by g.code limit 1;
  select pg.port_id into v_set from public.port_goods pg join public.ports h on h.id = pg.port_id and h.kind = 'HARBOUR'
   where pg.good_id = v_g and pg.port_id <> v_lis order by h.code limit 1;
  if v_lis is null or v_fl is null or v_g is null or v_o is null or public.fleet_free_hold(v_fl) < 13 then
    raise exception '0517 self-assert FAIL: no Lisbon, no fleet with room, or no good';
  end if;
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed');
  update public.port_goods pg set stock_target = 1000000, stock = 1000000, affinity = 1, demand = 1, drift = 0, season_mod = 0, glut = 0, haul = 1, haul_nm = 6250, want_period = null,
         updated_at = now(), glut_at = now() where pg.port_id = v_lis and pg.good_id = v_g;
  insert into public.port_treasury (port_id) values (v_lis) on conflict (port_id) do nothing;
  update public.port_treasury t set ducats = 500000000 - (public.treasury_balance(v_lis) - t.ducats), reserve = 0 where t.port_id = v_lis;
  perform cmd.assume_identity(p_uid);
  perform public.fleet_load(v_fl, v_c, 13, 10);   -- one stays aboard: the market serves its row
  v_out := jsonb_build_object(
    'q8', (select to_jsonb(q) from world.quote(v_lis, v_g, 8, 'sell', null, v_fl) q),
    'q30', (select to_jsonb(q) from world.quote(v_lis, v_g, 30, 'sell', null, v_fl) q),
    'q40', (select to_jsonb(q) from world.quote(v_lis, v_g, 40, 'sell', null, v_fl) q),
    'any', (select to_jsonb(q) from world.quote(v_lis, v_g, 40, 'sell', null, null) q),
    'buy', (select to_jsonb(q) from world.quote(v_lis, v_g, 40, 'buy', null, v_fl) q),
    'else', (select to_jsonb(q) from world.quote(v_set, v_g, 40, 'sell', null, v_fl) q),
    'mid', world.mid_price(v_lis, v_g, 1000000), 'mid_o', world.mid_price(v_lis, v_o, 1000),
    'mids', (select m.mid from world.good_mids(v_g) m where m.port_id = v_lis),
    'forge', md5(world.goods_forge(v_lis)::text));
  if not p_lit then
    v_r := cmd.do_sell(v_fl, jsonb_build_object('good', v_g, 'qty', 8));
    return v_out || jsonb_build_object('sold', v_r, 'spent', (select count(*) from public.treasury_flows t where t.player_id = v_pl and t.kind = 'SELL'),
      -- (last: the read steps the quay's drift, by dice) the keys a row carries
      'keys', (select jsonb_agg(distinct k order by k) from jsonb_array_elements(world.market(v_lis)->'goods') e, jsonb_object_keys(e) k));
  end if;

  update public.goods set premium_port_id = null where premium_port_id = v_lis or id = v_g;
  update public.goods set premium_port_id = v_lis where id = v_g;
  update public.world_config set value = 'true'::jsonb where key = 'premium_goods_enabled';
  v_out := v_out || jsonb_build_object('bought', coalesce((select w.left_units from public.premium_left(v_fl, v_lis, v_g) w), 0));   -- not made by her
  perform public.premium_count(v_pl, v_g, 50);
  v_out := v_out || jsonb_build_object('lift_mid', world.mid_price(v_lis, v_g, 1000000), 'lift_o', world.mid_price(v_lis, v_o, 1000),
    'lift_mids', (select m.mid from world.good_mids(v_g) m where m.port_id = v_lis),
    'lift_buy', (select q.mid_total from world.quote(v_lis, v_g, 40, 'buy', null, v_fl) q));
  -- the lift off, so a premium figure compares with the same quote dark
  update public.world_config set value = to_jsonb(1) where key = 'premium_price_lift';
  v_out := v_out || jsonb_build_object(
    'mult', public.premium_mult(6250), 'near', public.premium_mult(0), 'far', public.premium_mult(99999), 'nul', public.premium_mult(null),
    'l8', (select to_jsonb(q) from world.quote(v_lis, v_g, 8, 'sell', null, v_fl) q),
    'l40', (select to_jsonb(q) from world.quote(v_lis, v_g, 40, 'sell', null, v_fl) q),
    'l_any', (select to_jsonb(q) from world.quote(v_lis, v_g, 40, 'sell', null, null) q),
    'l_buy', (select to_jsonb(q) from world.quote(v_lis, v_g, 40, 'buy', null, v_fl) q),
    'l_else', (select to_jsonb(q) from world.quote(v_set, v_g, 40, 'sell', null, v_fl) q),
    'face', public.premium_face(v_g),
    'on_forge', (select e->'premium' from jsonb_array_elements(world.goods_forge(v_lis)->'recipes') e where e->>'product' = v_c));
  -- a merchant; the economy open; a city that offers the good itself
  update public.players set is_npc = true, auth_uid = null where id = v_pl;
  v_out := v_out || jsonb_build_object('npc', (select q.mid_total from world.quote(v_lis, v_g, 40, 'sell', null, v_fl) q));
  update public.players set is_npc = false, auth_uid = p_uid where id = v_pl;
  update public.world_config set value = 'false'::jsonb where key = 'economy_closed';
  v_out := v_out || jsonb_build_object('open', (select q.mid_total from world.quote(v_lis, v_g, 40, 'sell', null, v_fl) q), 'open_lift', public.premium_lift());
  update public.world_config set value = 'true'::jsonb where key = 'economy_closed';
  insert into public.port_specialties (port_id, good_id) values (v_lis, v_g);
  v_out := v_out || jsonb_build_object('offers', coalesce((select w.left_units from public.premium_left(v_fl, v_lis, v_g) w), 0));
  delete from public.port_specialties where port_id = v_lis and good_id = v_g;
  -- a small purse: at the floor none; a little above it, what its share pays whole
  update public.port_treasury t set ducats = public.city_floor(v_lis) - (public.treasury_balance(v_lis) - t.ducats) where t.port_id = v_lis;
  v_out := v_out || jsonb_build_object('poor', coalesce((select w.left_units from public.premium_left(v_fl, v_lis, v_g) w), 0));
  update public.port_treasury t set ducats = t.ducats + ceil(5.5 * (v_out->>'mid')::numeric * 4 / public.wc_num('premium_purse_share')) where t.port_id = v_lis;
  v_out := v_out || jsonb_build_object('little', (select w.left_units from public.premium_left(v_fl, v_lis, v_g) w));
  update public.port_treasury t set ducats = 500000000 - (public.treasury_balance(v_lis) - t.ducats) where t.port_id = v_lis;
  -- the door: the quote, from the city's purse; what she gained the cities lost (her own flows: a live world moves; proof 221 counts the whole)
  v_sum := (select p.ducats from public.players p where p.id = v_pl) + (select coalesce(sum(t.ducats), 0) from public.treasury_flows t where t.player_id = v_pl);
  v_r := cmd.do_sell(v_fl, jsonb_build_object('good', v_g, 'qty', 8));
  v_out := v_out || jsonb_build_object('sold', v_r, 'flows', (select jsonb_agg(t.ducats) from public.treasury_flows t where t.player_id = v_pl and t.port_id = v_lis and t.kind = 'SELL'),
    'world', (select p.ducats from public.players p where p.id = v_pl) + (select coalesce(sum(t.ducats), 0) from public.treasury_flows t where t.player_id = v_pl) - v_sum,
    'left', (select w.left_units from public.premium_left(v_fl, v_lis, v_g) w));
  perform public.premium_spend(v_pl, v_lis, v_g, 20);
  v_r := cmd.do_sell(v_fl, jsonb_build_object('good', v_g, 'qty', 4));
  v_out := v_out || jsonb_build_object('sold2', v_r, 'left2', coalesce((select w.left_units from public.premium_left(v_fl, v_lis, v_g) w), 0),
    'spent_q', (select q.mid_total from world.quote(v_lis, v_g, 8, 'sell', null, v_fl) q), 'plain_q', (select q.mid_total from world.quote(v_lis, v_g, 8, 'sell', null, null) q));
  update public.port_goods set premium_day = premium_day - 1 where port_id = v_lis and good_id = v_g;
  v_out := v_out || jsonb_build_object('mine', public.premium_mine(v_pl, v_g));
  return v_out || jsonb_build_object('next_day', (select w.left_units from public.premium_left(v_fl, v_lis, v_g) w),
    'on_market', (select count(*) from jsonb_array_elements(world.market(v_lis)->'goods') e where e #>> '{premium,port}' = 'LIS'));
end
$body$
  $f$;

  begin
    raise exception using errcode = 'ZX517', message = pg_temp.scene_0517(c_ua, false)::text;
  exception when sqlstate 'ZX517' then v_b := sqlerrm::jsonb;
  end;

  -- ── 3. THE KNOBS (this file's own; the owner's switch dark), THE COLUMNS, THE LIST ──
  insert into public.world_config (key, value, description) values
    ('premium_goods_enabled', 'false'::jsonb, '0517: THE SWITCH (the owner''s). true (with the economy closed and the city purses on): each premium good''s one city (goods.premium_port_id) pays a company 3 to 5 times for the day''s units, from its purse, and the good''s base price is premium_price_lift times. false: nothing.'),
    ('premium_mult_near', to_jsonb(3), '0517: lit, what a premium city pays, times its normal price, at premium_near_nm sailed miles or fewer from the good''s nearest maker.'),
    ('premium_mult_far', to_jsonb(5), '0517: the same at premium_far_nm or more; straight between.'),
    ('premium_near_nm', to_jsonb(500), '0517: the sailed miles (port_goods.haul_nm) up to which the near multiple is paid.'),
    ('premium_far_nm', to_jsonb(12000), '0517: the sailed miles from which the far multiple is paid.'),
    ('premium_day_units', to_jsonb(30), '0517: the units a premium city buys at its multiple a real UTC day, all companies together.'),
    ('premium_purse_share', to_jsonb(0.05), '0517: the share of a city''s coin above its reserve and floor that its premium units, paid whole, may take at a time.'),
    ('premium_price_lift', to_jsonb(1.25), '0517: a premium good''s base price is times this, buying and selling, everywhere (the owner: they cost more).');
  alter table public.goods add column premium_port_id uuid references public.ports(id);
  create unique index goods_premium_port_one on public.goods (premium_port_id) where premium_port_id is not null;
  alter table public.port_goods add column premium_day integer, add column premium_units numeric;
  -- retention: none, bounded by one row a company and made good (287 at most a company); a company's rows go with it
  create table public.premium_made (
    player_id uuid not null references public.players(id) on delete cascade,
    good_id   uuid not null references public.goods(id),
    made      numeric not null default 0,
    sold      numeric not null default 0,
    primary key (player_id, good_id));
  alter table public.premium_made enable row level security;
  revoke all on table public.premium_made from public, anon, authenticated, service_role;
  comment on table public.premium_made is '0517: units of a made good a company forged (made) and sold at a premium (sold). Writers: public.premium_count, public.premium_spend. Server only.';
  -- what the chain records of goods made before this file: a FORGED event a forging (0281), by the product's name. Companies only, by the
  -- events' own (player, time) index. (Not recorded: what the land's smith made.)
  insert into public.premium_made (player_id, good_id, made)
  select e.player_id, g.id, sum((e.payload->>'qty')::numeric)
    from public.players pl
    join public.events e on e.player_id = pl.id and e.kind = 'FORGED'
    join public.goods g on g.name = e.payload->>'product' and exists (select 1 from public.goods_recipes r where r.product_id = g.id)
   where not coalesce(pl.is_npc, false)
   group by 1, 2;
  comment on column public.goods.premium_port_id is '0517: the ONE city that wants this made good and pays 3 to 5 times for it (premium_goods_enabled). Data: the owner may move it. One good a city.';
  comment on column public.port_goods.premium_day is '0517: the real day (public.real_day) premium_units counts. One writer: public.premium_spend.';
  comment on column public.port_goods.premium_units is '0517: the units this city took at its premium on premium_day.';
  update public.goods g set premium_port_id = h.id
    from (values
      ('cassava', 'OPO'), ('palm-sugar', 'MNL'), ('palm-wine', 'VAL'), ('mission-wine', 'OSA'), ('perry', 'STO'),
      ('baijiu', 'HIR'), ('dried-shrimp', 'TOK'), ('pulque', 'PAN'), ('dried-squid', 'NAH'), ('doenjang', 'QUA'),
      ('butter', 'TUN'), ('cheese', 'HAM'), ('sesame-oil', 'MRS'), ('shrimp-paste', 'YEO'), ('cider', 'NAP'),
      ('ramie-cloth', 'GUA'), ('soy-sauce', 'BND'), ('toddy', 'MAC'), ('chianti', 'COP'), ('maple-sugar', 'DUB'),
      ('sake', 'AYU'), ('wine', 'RIG'), ('witch-hazel', 'LON'), ('crossbows', 'BER'), ('arrack', 'NAG'),
      ('rum', 'PLY'), ('trepang', 'INC'), ('shields', 'MLG'), ('prussian-blue', 'IZM'), ('sharks-fin', 'MUM'),
      ('sugar', 'QUE'), ('steel-billets', 'XIA'), ('folding-fans', 'CHE'), ('attar-of-roses', 'NIN'), ('martaban-jars', 'FUK'),
      ('guayaquil-cacao', 'SLV'), ('war-bows', 'HOO'), ('dried-abalone', 'SRT'), ('rosewater', 'STJ'), ('ramie-korea', 'KHA'),
      ('glassware', 'BOS'), ('flanders-lace', 'JAM'), ('cacao', 'PON'), ('tapa-cloth', 'BAS'), ('lead-white', 'REC'),
      ('worsted', 'PRT'), ('pike-heads', 'CAR'), ('palm-leaf-manuscripts', 'CAD'), ('maghreb-brass', 'ARK'), ('celadon', 'SFR'),
      ('isinglass', 'NEW'), ('porcelain', 'BSR'), ('soconusco-cacao', 'BUS'), ('armour', 'HAV'), ('caviar', 'SGO'),
      ('parchment', 'RIO'), ('muslin', 'ALG'), ('wootz-steel', 'BAR'), ('block-printed-books', 'CPT'), ('pandanus-mats', 'ARI'),
      ('tea', 'ACA'), ('shot-and-ball', 'BUE'), ('coffee', 'SAK'), ('antwerp-presses', 'ZAN'), ('lace', 'ISL'),
      ('matchlocks', 'JED'), ('saffian-leather', 'KOZ'), ('firearms', 'GYE'), ('paintings', 'MOM'), ('iznik-tiles', 'VER'),
      ('rice-paper', 'LPA'), ('falconet', 'ADE'), ('goryeo-celadon', 'LUA'), ('korean-movable-type', 'ELM'), ('sword-blades', 'CLL'),
      ('rocket-tubes', 'BOR'), ('cannon', 'MOC'), ('slow-match', 'HOR'), ('venetian-imprints', 'KOC'), ('zanzibar-doors', 'TAL'),
      ('arquebus', 'COL'), ('kyoto-fans', 'FNC'), ('murano-glass', 'OLD'), ('swivel-gun', 'MUS'), ('mother-of-pearl-inlay', 'LIS'),
      ('sutra-scrolls', 'SVQ'), ('nipa-mats', 'NAN'), ('shawls', 'VLL'), ('astrolabes', 'AMS'), ('sea-charts', 'TER'),
      ('tapestries', 'BNT'), ('nautical-clocks', 'JAK'), ('clocks', 'BAN'), ('flemish-panels', 'MAL'), ('scroll-paintings', 'LAR'),
      ('armillary-spheres', 'TAI'), ('italian-canvases', 'AMB'), ('globes', 'HOI'), ('portolan-charts', 'MAK'), ('ukiyo-e', 'BIL')) v(good, city)
    join public.ports h on h.code = v.city and h.kind = 'HARBOUR'
   where g.code = v.good and exists (select 1 from public.goods_recipes r where r.product_id = g.id)
     and exists (select 1 from public.port_goods pg where pg.port_id = h.id and pg.good_id = g.id);
  if (select count(*) from public.goods where premium_port_id is not null) <> 100 then
    raise exception '0517 refuses: % of the 100 goods found their city', (select count(*) from public.goods where premium_port_id is not null);
  end if;

  -- ── 4. THE RULES ──
  execute $f$
create function public.premium_on()
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0517: THE SWITCH, read once: premium_goods_enabled, and only where the cities pay from their own purses and no coin is made (0122, 0228).
begin
  return public.wc('premium_goods_enabled') = 'true'::jsonb and public.city_treasury_on() and coalesce(public.economy_closed(), false);
end
$body$
  $f$;
  execute $f$
create function public.premium_lift()
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0517: what a premium good's base price is times (world.mid_terms and the readers of its terms); 1 dark.
begin
  if public.wc('premium_goods_enabled') is distinct from 'true'::jsonb then
    return 1;
  end if;
  return case when public.premium_on() then public.wc_num('premium_price_lift') else 1 end;
end
$body$
  $f$;
  execute $f$
create function public.premium_mult(p_nm numeric)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0517: WHAT THE CITY PAYS, times its normal price, by the sailed miles from the good's nearest maker (port_goods.haul_nm): premium_mult_near up to
-- premium_near_nm, premium_mult_far from premium_far_nm, straight between. No distance: the near one.
begin
  return round(public.wc_num('premium_mult_near') + (public.wc_num('premium_mult_far') - public.wc_num('premium_mult_near'))
    * least(1, greatest(0, (coalesce(p_nm, 0) - public.wc_num('premium_near_nm'))
                           / greatest(1, public.wc_num('premium_far_nm') - public.wc_num('premium_near_nm')))), 2);
end
$body$
  $f$;
  execute $f$
create function public.premium_units(p_port uuid, p_good uuid)
returns table (mult numeric, left_units numeric)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0517: THE ONE reader of a city's premium: what it pays and the units it still takes at it today. No row dark, at any other city, where the city
-- offers the good itself. The units: premium_day_units less today's (public.real_day), and no more than premium_purse_share of what the city
-- holds above its reserve and its floor pays whole: a small purse keeps its coin, and then the price is the normal one.
declare
  r       record;
  v_mult  numeric;
  v_mid   numeric;
  v_spare numeric;
begin
  select pg.haul_nm, pg.stock, case when pg.premium_day = public.real_day(now()) then pg.premium_units else 0 end as used into r
    from public.goods g join public.port_goods pg on pg.good_id = g.id and pg.port_id = p_port
   where g.id = p_good and g.premium_port_id = p_port;
  if not found or not public.premium_on() or public.port_offers(p_port, p_good) then
    return;
  end if;
  v_mult := public.premium_mult(r.haul_nm);
  v_mid := world.mid_price(p_port, p_good, r.stock);
  v_spare := public.treasury_balance(p_port)
             - greatest(coalesce((select t.reserve from public.port_treasury t where t.port_id = p_port), 0), public.city_floor(p_port));
  mult := v_mult;
  left_units := greatest(0, least(public.wc_num('premium_day_units') - coalesce(r.used, 0),
                                  floor(greatest(0, v_spare) * public.wc_num('premium_purse_share') / greatest(v_mid * v_mult, 0.01))));
  return next;
end
$body$
  $f$;
  execute $f$
create function public.premium_left(p_fleet uuid, p_port uuid, p_good uuid)
returns table (mult numeric, left_units numeric)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0517: public.premium_units for a COMPANY'S fleet, and no more than the units of it the company MADE and has not yet sold at a premium
-- (public.premium_mine). No row with no fleet or for a merchant. Asked by THE one quote and by the door's tally alone.
declare
  v_player uuid;
begin
  if not exists (select 1 from public.goods g where g.id = p_good and g.premium_port_id = p_port) then
    return;
  end if;
  select f.player_id into v_player from public.fleets f join public.players pl on pl.id = f.player_id where f.id = p_fleet and not coalesce(pl.is_npc, false);
  if v_player is null then
    return;
  end if;
  return query select u.mult, least(u.left_units, public.premium_mine(v_player, p_good)) from public.premium_units(p_port, p_good) u;
end
$body$
  $f$;
  execute $f$
create function public.premium_mine(p_player uuid, p_good uuid)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0517: THE units of a good a company made in its Forge and has not yet sold at a premium; 0 with no row.
begin
  return coalesce((select greatest(0, m.made - m.sold) from public.premium_made m where m.player_id = p_player and m.good_id = p_good), 0);
end
$body$
  $f$;
  execute $f$
create function public.premium_count(p_player uuid, p_good uuid, p_units numeric)
returns void
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $body$
-- 0517: a company's units made in the Forge (cmd.forge_good alone calls it, after they are in its Storage). Counted dark too, so what is made
-- before the light counts.
begin
  insert into public.premium_made as m (player_id, good_id, made) values (p_player, p_good, p_units)
  on conflict (player_id, good_id) do update set made = m.made + excluded.made;
end
$body$
  $f$;
  execute $f$
create function public.premium_hold(p_port uuid, p_good uuid)
returns void
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $body$
-- 0517: the market row of a city's own premium good, held for this sale (so two sales never both take its last units). Dark, or any other: nothing.
begin
  if public.premium_on() and exists (select 1 from public.goods g where g.id = p_good and g.premium_port_id = p_port) then
    perform 1 from public.port_goods pg where pg.port_id = p_port and pg.good_id = p_good for no key update;
  end if;
end
$body$
  $f$;
  execute $f$
create function public.premium_spend(p_player uuid, p_port uuid, p_good uuid, p_units numeric)
returns void
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $body$
-- 0517: the units a sale took at the premium: on the city's day (public.real_day) and off what the company made. THE one writer of both.
begin
  update public.premium_made set sold = sold + p_units where player_id = p_player and good_id = p_good;
  update public.port_goods set premium_units = p_units + case when premium_day = public.real_day(now()) then coalesce(premium_units, 0) else 0 end,
         premium_day = public.real_day(now())
   where port_id = p_port and good_id = p_good;
end
$body$
  $f$;
  execute $f$
create function public.premium_port(p_good uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0517: the one city of a premium good while lit (null dark or none): the board's shortlist always prices it.
begin
  return (select g.premium_port_id from public.goods g where g.id = p_good and g.premium_port_id is not null and public.premium_on());
end
$body$
  $f$;
  execute $f$
create function public.premium_face(p_good uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0517: what a face shows of a premium good: {premium: {port, name, mult, nm, per_day, made, left}}; null dark, or not one. made: what the
-- reader's company made and has not sold at a premium; left: the lesser of it and what the city still takes today.
begin
  if not public.premium_on() then
    return null;
  end if;
  return (select jsonb_build_object('premium', jsonb_build_object('port', h.code, 'name', h.name, 'mult', u.mult, 'nm', pg.haul_nm,
                                                                  'per_day', public.wc_num('premium_day_units'), 'made', mine.n, 'left', least(u.left_units, mine.n)))
            from public.goods g
            join public.ports h on h.id = g.premium_port_id
            join public.port_goods pg on pg.port_id = h.id and pg.good_id = g.id
           cross join lateral public.premium_units(h.id, g.id) u
           cross join (select public.premium_mine(public.current_player_id(), p_good) as n) mine
           where g.id = p_good);
end
$body$
  $f$;

  foreach v_def in array c_new loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v_def::regprocedure);
  end loop;

  -- ── 5. THE HUNK ──
  create temp table hunks_0517 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0517 values
  ('world.quote_priced(uuid,uuid,numeric,text,numeric,uuid,numeric,numeric,numeric,numeric)', 1,
$h$  v_wper   bigint;    -- 0255: the row's want marker (port_goods.want_period), read with its stock
$h$,
$h$  v_wper   bigint;    -- 0255: the row's want marker (port_goods.want_period), read with its stock
  v_pmult  numeric;   -- 0517: what this city pays for its one premium good, times the normal price (none dark)
  v_pleft  numeric := 0;   -- 0517: the units it still takes at it today
  v_prem   boolean := false;   -- 0517: units are still left at the premium (the walk tests this one flag)
$h$),
  ('world.quote_priced(uuid,uuid,numeric,text,numeric,uuid,numeric,numeric,numeric,numeric)', 2,
$h$  -- §G.2: "Orders execute in 10-tun steps, each repricing, so a large order pays a genuinely worse
$h$,
$h$  -- 0517 (dark: premium_goods_enabled): lit, THE ONE CITY THAT WANTS THIS MADE GOOD pays its multiple to a company for the units still left
  -- today (public.premium_left, read once a sale; no row for a quote with no fleet, a merchant, another city, or a purse with none to spare).
  if p_side = 'sell' and p_fleet is not null and public.premium_on() then
    select w.mult, w.left_units into v_pmult, v_pleft from public.premium_left(p_fleet, p_port, p_good) w;
    v_pleft := coalesce(v_pleft, 0);
    v_prem  := v_pleft > 0;
  end if;

  -- §G.2: "Orders execute in 10-tun steps, each repricing, so a large order pays a genuinely worse
$h$),
  ('world.quote_priced(uuid,uuid,numeric,text,numeric,uuid,numeric,numeric,numeric,numeric)', 3,
$h$    if v_want then   -- 0255 (E6b): a sale's units at the want price; the shelf splits where the want runs out (a sale's mid
$h$,
$h$    if v_prem then   -- 0517: the premium units first (never times a want too); the shelf splits where they run out
      v_n     := least(v_n, v_pleft);
      v_mid   := v_mid * v_pmult;
      v_pleft := v_pleft - v_n;
      v_prem  := v_pleft > 0;
    elsif v_want then   -- 0255 (E6b): a sale's units at the want price; the shelf splits where the want runs out (a sale's mid
$h$),
  ('cmd.do_sell(uuid,jsonb)', 4,
$h$  v_trip    bigint;        -- 0490$h$,
$h$  v_prem    numeric := 0;  -- 0517: the units of this sale at the city's premium (0 dark)
  v_trip    bigint;        -- 0490$h$),
  ('cmd.do_sell(uuid,jsonb)', 5,
$h$  if g.id is null then raise exception 'E_NO_SUCH_GOOD: unknown good' using errcode = 'P0001'; end if;
$h$,
$h$  if g.id is null then raise exception 'E_NO_SUCH_GOOD: unknown good' using errcode = 'P0001'; end if;
  perform public.premium_hold(f.port_id, g.id);   -- 0517 (dark: nothing): one sale at a time of a city's premium good, so two never share its last units
$h$),
  ('cmd.do_sell(uuid,jsonb)', 6,
$h$  v_basis  := public.fleet_cargo_basis(p_fleet, g.code);
$h$,
$h$  -- 0517 (dark: 0): the units of it the quote paid the premium on, read before anything moves (public.premium_left, the quote's own reader)
  v_prem   := coalesce((select least(q.units, w.left_units) from public.premium_left(p_fleet, f.port_id, g.id) w), 0);
  v_basis  := public.fleet_cargo_basis(p_fleet, g.code);
$h$),
  ('cmd.do_sell(uuid,jsonb)', 7,
$h$  -- 0255 (E6b): the units this sale took at the city's want price count against the period's cap
$h$,
$h$  if v_prem > 0 then   -- 0517: they count against the city's day
    perform public.premium_spend(f.player_id, f.port_id, g.id, v_prem);
  end if;
  -- 0255 (E6b): the units this sale took at the city's want price count against the period's cap
$h$),
  ('cmd.do_sell(uuid,jsonb)', 8,
$h$least(q.units, w.left_units)
    from world.want_left(f.port_id, g.id) w
   where w.left_units > 0
$h$,
$h$least(q.units - v_prem, w.left_units)   -- 0517: less those at the premium
    from world.want_left(f.port_id, g.id) w
   where w.left_units > 0 and q.units > v_prem
$h$),
  ('cmd.do_sell(uuid,jsonb)', 9,
$h$      || coalesce(v_gift, '{}'::jsonb);
$h$,
$h$      || coalesce(v_gift, '{}'::jsonb)
      || case when v_prem > 0 then jsonb_build_object('premium_units', v_prem) else '{}'::jsonb end;   -- 0517 (absent when none)
$h$),
  ('world.mid_terms(uuid,uuid)', 10,
$h$  select g.base_value, pg.affinity$h$,
$h$  select g.base_value * case when g.premium_port_id is null then 1 else public.premium_lift() end   -- 0517 (dark: x 1): a premium good costs more, everywhere
       , pg.affinity$h$),
  ('world.good_mids(uuid)', 11,
$h$mid_from_terms(g.base_value, pg.affinity$h$,
$h$mid_from_terms(g.base_value * case when g.premium_port_id is null then 1 else (select public.premium_lift()) end,   -- 0517: world.mid_terms' own base
                              pg.affinity$h$),
  ('world.market(uuid)', 12,
$h$'range_lo', world.mid_from_terms(g.base_value, $h$,
$h$'range_lo', world.mid_from_terms(g.base_value * case when g.premium_port_id is null then 1 else public.premium_lift() end,   -- 0517: world.mid_terms' own base
                      $h$),
  ('world.market(uuid)', 13,
$h$'range_hi', world.mid_from_terms(g.base_value, $h$,
$h$'range_hi', world.mid_from_terms(g.base_value * case when g.premium_port_id is null then 1 else public.premium_lift() end,   -- 0517: world.mid_terms' own base
                      $h$),
  ('world.market(uuid)', 14,
$h$                       from world.want_left(pg.port_id, pg.good_id) w), '{}'::jsonb)
$h$,
$h$                       from world.want_left(pg.port_id, pg.good_id) w), '{}'::jsonb)
        -- 0517: a premium good carries {premium: its one city, what it pays, the units left today} (absent dark and otherwise)
        || coalesce(case when g.premium_port_id is not null then public.premium_face(g.id) end, '{}'::jsonb)
$h$),
  ('world.goods_forge(uuid)', 15,
$h$             where gr.product_id = g.id))
        order by g.tier, g.name), '[]'::jsonb)$h$,
$h$             where gr.product_id = g.id))
          -- 0517: a premium good's one city and its pay (absent dark and otherwise)
          || coalesce(case when g.premium_port_id is not null then public.premium_face(g.id) end, '{}'::jsonb)
        order by g.tier, g.name), '[]'::jsonb)$h$),
  ('world.board_sell_memo(uuid,uuid,jsonb,jsonb)', 16,
$h$order by (c.nm is null), c.mid desc, c.nm nulls last, c.code) as rk$h$,
$h$order by (c.nm is null), (c.id is not distinct from (select public.premium_port(p_good))) desc,   -- 0517: the city that pays the premium is always priced (dark: none)
                                       c.mid desc, c.nm nulls last, c.code) as rk$h$),
  ('cmd.forge_good(uuid,uuid,integer)', 17,
$h$    perform public.storage_put(v_player, p_port, p_product, v_qty, v_basis);
$h$,
$h$    perform public.storage_put(v_player, p_port, p_product, v_qty, v_basis);
    perform public.premium_count(v_player, p_product, v_qty);   -- 0517: made by her: only such units are ever paid a premium
$h$);

  for x in select distinct h.fn from hunks_0517 h loop
    v_pre := (select p.def from pre_0517 p where p.fn = x.fn);
    v_def := v_pre;
    for v_old, v_new, v_n in select h.old, h.new, h.ord from hunks_0517 h where h.fn = x.fn order by h.ord loop
      if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then
        raise exception '0517 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', v_n, x.fn,
          (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
      end if;
      v_def := replace(v_def, v_old, v_new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(x.fn::regprocedure), E'\r', '');
    for v_old, v_new, v_n in select h.old, h.new, h.ord from hunks_0517 h where h.fn = x.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, v_new, ''))) / length(v_new) <> 1 then
        raise exception '0517 self-assert FAIL: hunk % of % is not in the new body once', v_n, x.fn;
      end if;
      v_def := replace(v_def, v_new, v_old);
    end loop;
    if v_def <> v_pre then
      raise exception '0517 self-assert FAIL: % does not reverse to its pre-image', x.fn;
    end if;
  end loop;

  -- ── 6. THE SELF-ASSERT: the catalog ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked || c_new) u(q)))) <> v_fn_before then
    raise exception '0517 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0517 self-assert FAIL: the grants, volatility, definer, search path or owner of the hunked body moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
        from public.world_config c where c.key <> all (c_knobs)) <> v_cfg_before or public.premium_on() then
    raise exception '0517 self-assert FAIL: a knob of another file moved, or the switch is not false';
  end if;
  if exists (select 1 from unnest(c_new) u(q)
              where has_function_privilege('anon', u.q::regprocedure, 'execute') or has_function_privilege('authenticated', u.q::regprocedure, 'execute')
                 or has_function_privilege('service_role', u.q::regprocedure, 'execute') or has_function_privilege('public', u.q::regprocedure, 'execute')) then
    raise exception '0517 self-assert FAIL: a new function is reachable by a client or service_role';
  end if;
  if (select array_agg(p.oid::regprocedure::text order by p.oid::regprocedure::text) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> 'public.premium_left(uuid,uuid,uuid)'::regprocedure
         and position('premium_left(' in p.prosrc) > 0) is distinct from array[c_hunked[2], c_hunked[1]] then
    raise exception '0517 self-assert FAIL: the premium is not asked by the one quote and the door alone';
  end if;

  -- ── 7. DARK IDENTITY, then LIT ──
  begin
    raise exception using errcode = 'ZX517', message = pg_temp.scene_0517(c_ua, false)::text;
  exception when sqlstate 'ZX517' then v_d := sqlerrm::jsonb;
  end;
  if v_d is distinct from v_b then
    raise exception '0517 self-assert FAIL: DARK IS NOT IDENTICAL. Before: % After: %', left(v_b::text, 900), left(v_d::text, 900);
  end if;
  begin
    raise exception using errcode = 'ZX517', message = pg_temp.scene_0517(c_ua, true)::text;
  exception when sqlstate 'ZX517' then v_l := sqlerrm::jsonb;
  end;
  drop function pg_temp.scene_0517(uuid, boolean);

  -- it costs more: the base is lifted everywhere it is read, and nothing else's
  if abs((v_l->>'lift_mid')::numeric - (v_l->>'mid')::numeric * 1.25) > 0.001 or v_l->'lift_mids' is distinct from v_l->'lift_mid' or v_l->'lift_o' is distinct from v_l->'mid_o'
     or abs((v_l->>'lift_buy')::numeric - (v_l #>> '{buy,mid_total}')::numeric * 1.25) > 0.1 then
    raise exception '0517 self-assert FAIL: the lift: %', v_l;
  end if;
  -- 3 to 5 times by the miles; 8 units four times; 40 units: 30 of them four times, the rest the normal price
  if (v_l->>'mult')::numeric <> 4 or (v_l->>'near')::numeric <> 3 or (v_l->>'far')::numeric <> 5 or (v_l->>'nul')::numeric <> 3
     or abs((v_l #>> '{l8,mid_total}')::numeric - 4 * (v_l #>> '{q8,mid_total}')::numeric) > 0.1
     or abs((v_l #>> '{l40,mid_total}')::numeric - (v_l #>> '{q40,mid_total}')::numeric - 3 * (v_l #>> '{q30,mid_total}')::numeric) > 0.5 then
    raise exception '0517 self-assert FAIL: the pay: %', v_l;
  end if;
  -- any other city, a purchase, no fleet, a merchant, an open economy, a city that offers it: the normal price
  if v_l->'l_else' is distinct from v_l->'else' or v_l->'l_buy' is distinct from v_l->'buy' or v_l->'l_any' is distinct from v_l->'any'
     or (v_l->>'npc')::numeric <> (v_l #>> '{q40,mid_total}')::numeric
     or (v_l->>'open')::numeric <> (v_l #>> '{q40,mid_total}')::numeric or (v_l->>'open_lift')::numeric <> 1 or (v_l->>'offers')::numeric <> 0 then
    raise exception '0517 self-assert FAIL: the premium was paid where it is not: %', v_l;
  end if;
  -- a purse with none to spare pays none; a small one what its share pays whole
  if (v_l->>'poor')::numeric <> 0 or (v_l->>'little')::numeric <> 5 then
    raise exception '0517 self-assert FAIL: the purse rule: at the floor %, a little above it %', v_l->>'poor', v_l->>'little';
  end if;
  -- the door: the quote, one SELL out of the purse, no coin made; the day's units counted, spent, new the next day
  if v_l #> '{sold,total}' is distinct from v_l #> '{l8,total}' or (v_l #>> '{sold,premium_units}')::numeric <> 8 or v_l->'flows' is distinct from jsonb_build_array(-(v_l #>> '{l8,total}')::bigint)
     or (v_l->>'world')::numeric <> 0 or (v_l->>'left')::numeric <> 22 or (v_l #>> '{sold2,premium_units}')::numeric <> 2 or (v_l->>'left2')::numeric <> 0
     or (v_l->>'spent_q')::numeric <> (v_l->>'plain_q')::numeric or (v_l->>'next_day')::numeric <> 20 or (v_l->>'mine')::numeric <> 20 or (v_l->>'bought')::numeric <> 0 then
    raise exception '0517 self-assert FAIL: the door: %', v_l;
  end if;
  if v_l #>> '{face,premium,port}' <> 'LIS' or (v_l #>> '{face,premium,mult}')::numeric <> 4 or v_l->'on_forge' is distinct from v_l #> '{face,premium}' or (v_l->>'on_market')::int < 1 then
    raise exception '0517 self-assert FAIL: the face: % %', v_l->'face', v_l->'on_forge';
  end if;

  -- ── 8. NOTHING OF THE PROBE SURVIVES; the switch is dark ──
  if exists (select 1 from public.players p where p.company_name = 'Casa da Prova 0517') or public.premium_on()
     or (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
           from public.world_config c where c.key <> all (c_knobs)) <> v_cfg_before then
    raise exception '0517 self-assert FAIL: the probe left rows behind, or a knob moved';
  end if;
  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0517 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0517 self-assert ok: PREMIUM GOODS (dark). 17 hunks once and reversing in eight bodies; no other function moved; eleven new functions, one table server only; eight knobs (premium_goods_enabled false), no other moved; 100 goods, one city each. DARK IDENTICAL. LIT: 8 units % -> % d. (4 times at 6,250 miles; 3 near, 5 far), paid in one SELL from the city''s purse, she gained what the cities lost; 30 a day for all, then the normal price, new the next day; a purse at its floor pays none, a small one 5 units; units she did not make, another city, a purchase, a quote with no fleet, a merchant, an open economy, a city that offers it: none; the base price % -> %. % ms.',
    v_l #> '{q8,total}', v_l #> '{l8,total}', v_l->'mid', v_l->'lift_mid', round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0517;
  drop table pre_0517;
end $m$;
