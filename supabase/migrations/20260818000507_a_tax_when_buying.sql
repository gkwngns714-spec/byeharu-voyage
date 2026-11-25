-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none (dark: nothing changes for a player until the owner lights buy_tax_enabled)
-- 0507 - A TAX WHEN BUYING, 0 TO 3 %  (dark: the owner's switch buy_tax_enabled, false. Slice T3 `buy-tax`,
--   docs/design/owner-spec-plan-2026-11-25.md section 6, row 56 and Q7; the owner's answer: "0-3% is okay")
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-25: "TAX is only payed when only a profit is made, or when buying." Then: "0-3% is okay."
-- TODAY: a purchase pays no tax (0122 made the tax one on a sale's profit).
-- LIT (buy_tax_enabled true): a company's purchase costs a tenth (buy_tax_share 0.1) of the rate THE CITY ASKS HER more
--   (world.tax_rate(city, company), the one authority of the rate: her country's standing, and 0505's home half when that is lit, so
--   her own country and her home city ask less here too), never above buy_tax_max (0.03). On a 10 % city: 1 %. A free pirate port and
--   the purses dark: nothing. A merchant (players.is_npc): nothing (its own plan is quoted with no fleet, so nothing it pays moves).
-- READ FROM ONE PLACE: public.buy_tax_rate(fleet, city), called by THE one quote alone (world.quote_priced, one hunk, the buy side of
--   a quote that names a fleet; after the bargain of 0506). Everything that prices her purchase asks that quote: the door (cmd.do_buy
--   charges its total), the Max (public.fleet_buy_capacity), the Best cards (world.best_sales, world.good_board, world.board_sell),
--   the routes, the never-lose rule (0498: public.fleet_run_quote, public.sale_fit, public.cards_fit) and the day (public.run_day).
--   So none of them is re-cut, and a job that the tax would make lose waits before it buys.
-- THE MONEY: the tax rides the purchase's own payment (public.pay_city, kind BUY, the city's purse): no second ledger row. It is
--   itemised as `tax_total` of the quote and of the BOUGHT event, the key 0083 already serves. It is part of what the goods cost her, so
--   the profit tax at the sale is on the gain after it. A buy's limit price stays a limit on the price without the tax.
-- DARK (as deployed): byte-identical answers: one switch read more in a buy quote that names a fleet.
-- WHAT IT DOES TO PASSIVE NEAR JOBS (measured on the chain's world, docs/dev-log/2026-11-25-buy-tax.md; the owner sees it before the light).
-- THE HUNK (1; once in the live body, reverses): world.quote_priced. NEW: public.buy_tax_on(), public.buy_tax_rate(fleet, city): STABLE,
--   server only. KNOBS: buy_tax_enabled false, buy_tax_share 0.1, buy_tax_max 0.03. NOT CHANGED: every other knob, function and table.
-- ROWS: none, dark or lit. budget: none (no table, no cron job, no index, no autovacuum setting is made). -- retention: none.
-- THE TICK'S COST: no tick, no beat step. Lit, one world.tax_rate more (a handful of key reads) in a buy quote that names a company's fleet.
-- LOCKS: CREATE OR REPLACE x1 by a hunk, CREATE FUNCTION x2, three knobs. TIME: under a second. BUDGET: statement_timeout 45 s,
--   lock_timeout 5 s; fails above 30 s.
-- ROLLBACK (forward, owner only): QUICK, buy_tax_enabled false: the next purchase pays none; what was paid is the city's.
--   FULL: scripts/ops/harness/buy-tax/rollback-0507.sql (a draft).
-- SELF-ASSERT: the hunk once and reversing; no other function moved; grants and settings unmoved; no other knob moved; the new functions
--   STABLE and server only; buy_tax_rate called by world.quote_priced alone. THE PROBE (rolled back by a raised sentinel; no role is
--   changed; INDEPENDENT OF PROD'S MARKET, DICE AND COMPANIES: a company founded inside it, Lisbon's market row of one good and its
--   purse written inside it; every figure compared with the same quote without the tax in the same instant; the rate compared with
--   world.tax_rate's own answer for her): dark identical; lit, her total is the plain one x (1 + the rate), ceiled once, her sale, a quote
--   with no fleet and a merchant's are equal; the ceiling 3 %; a mayor's 30 % asks a stranger at most 3 %; the Max's price is the quote's; the
--   door charges exactly the quote in one BUY payment to the city; sold back at once she gets less than she paid.
--   Proof 209 plays it through the doors and the never-lose rule.
-- VERSION: 0507 (after 0506; the lead deploys in number order).
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
do $m$
declare
  c_hunked constant text[] := array['world.quote_priced(uuid,uuid,numeric,text,numeric,uuid,numeric,numeric,numeric,numeric)'];
  c_new    constant text[] := array['public.buy_tax_on()', 'public.buy_tax_rate(uuid,uuid)'];
  c_knobs  constant text[] := array['buy_tax_enabled', 'buy_tax_share', 'buy_tax_max'];
  c_ua     constant uuid := '00000000-0507-4000-8000-0000000000a1';
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
    raise exception '0507 refuses: it has been applied once';
  end if;
  if exists (select 1 from unnest(c_hunked || array['public.bargain_factor(uuid,uuid,uuid,text)', 'public.tax_home_half(uuid,uuid,numeric,numeric)',
                                                    'public.fleet_run_quote(uuid,uuid,uuid,text,text,text[])', 'public.fleet_buy_capacity(uuid,uuid)']) f
              where to_regprocedure(f) is null) then
    raise exception '0507 refuses: 0505, 0506 or the never-lose rule (0498) is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0507 (fn text primary key, def text) on commit drop;
  insert into pre_0507 select f, replace(pg_get_functiondef(f::regprocedure), E'\r', '') from unnest(c_hunked) f;
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
create function pg_temp.scene_0507(p_uid uuid, p_lit boolean)
returns jsonb
language plpgsql
as $body$
declare
  v_lis uuid := (select h.id from public.ports h where h.code = 'LIS' and h.kind = 'HARBOUR');
  v_pl  uuid;
  v_fl  uuid;
  v_g   uuid;
  v_out jsonb;
  v_r   jsonb;
begin
  v_pl := public.new_house(p_uid, 'Casa da Prova 0507', 'PRT');
  select f.id into v_fl from public.fleets f where f.player_id = v_pl;
  update public.players set ducats = 50000000 where id = v_pl;
  select g.id into v_g
    from public.port_goods pg join public.goods g on g.id = pg.good_id
   where pg.port_id = v_lis and public.port_offers(v_lis, g.id) and g.bulk > 0 and g.bulk <= 2
     and not public.culture_refuses((select h.culture from public.ports h where h.id = v_lis), g.culture_mask)
   order by g.base_value desc, g.code limit 1;
  if v_lis is null or v_fl is null or v_g is null or public.fleet_free_hold(v_fl) < 45 then
    raise exception '0507 self-assert FAIL: no Lisbon, no fleet with room, or no good on its quay';
  end if;
  update public.port_goods pg set stock_target = greatest(pg.stock_target, 1000), stock = greatest(pg.stock_target, 1000), glut = 0, want_period = null, updated_at = now(), glut_at = now()
   where pg.port_id = v_lis and pg.good_id = v_g;
  update public.port_treasury t set ducats = t.ducats + 50000000 where t.port_id = v_lis;
  update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled';
  perform cmd.assume_identity(p_uid);
  v_out := jsonb_build_object(
    'hers', (select to_jsonb(q) from world.quote(v_lis, v_g, 20, 'buy', null, v_fl) q),
    'sale', (select to_jsonb(q) from world.quote(v_lis, v_g, 20, 'sell', null, v_fl) q),
    'any', (select to_jsonb(q) from world.quote(v_lis, v_g, 20, 'buy', null, null) q),
    'rate', world.tax_rate(v_lis, v_pl));
  if not p_lit then
    v_r := cmd.do_buy(v_fl, jsonb_build_object('good', v_g, 'qty', 20));
    return v_out || jsonb_build_object('paid', v_r);
  end if;

  update public.world_config set value = 'true'::jsonb where key = 'buy_tax_enabled';
  v_out := v_out || jsonb_build_object(
    'hers_l', (select to_jsonb(q) from world.quote(v_lis, v_g, 20, 'buy', null, v_fl) q),
    'sale_l', (select to_jsonb(q) from world.quote(v_lis, v_g, 20, 'sell', null, v_fl) q),
    'any_l', (select to_jsonb(q) from world.quote(v_lis, v_g, 20, 'buy', null, null) q),
    'r', public.buy_tax_rate(v_fl, v_lis), 'none', public.buy_tax_rate(null, v_lis));
  -- the Max's price is the quote of its units
  v_r := public.fleet_buy_capacity(v_fl, v_g);
  v_out := v_out || jsonb_build_object('max', v_r->'est_total', 'max_q',
    (select q.total from world.quote(v_lis, v_g, (v_r->>'max_qty')::numeric, 'buy', null, v_fl) q));
  -- a merchant's
  update public.players set is_npc = true, auth_uid = null where id = v_pl;
  v_out := v_out || jsonb_build_object('npc', public.buy_tax_rate(v_fl, v_lis));
  update public.players set is_npc = false, auth_uid = p_uid where id = v_pl;
  -- the ceiling, whatever the rate and the share
  update public.world_config set value = to_jsonb(1000) where key = 'buy_tax_share';
  v_out := v_out || jsonb_build_object('cap', public.buy_tax_rate(v_fl, v_lis));
  update public.world_config set value = to_jsonb(0.1) where key = 'buy_tax_share';
  -- the purses dark: no tax on a purchase but the old turnover rate the quote carries
  update public.world_config set value = 'false'::jsonb where key = 'city_treasury_enabled';
  v_out := v_out || jsonb_build_object('purses_dark', public.buy_tax_rate(v_fl, v_lis));
  update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled';
  -- the door: the quote's total, in one BUY payment to the city; sold back at once: less than she paid
  v_r := cmd.do_buy(v_fl, jsonb_build_object('good', v_g, 'qty', 20));
  v_out := v_out || jsonb_build_object('paid', v_r,
    'flows', (select jsonb_agg(jsonb_build_array(t.kind, t.ducats)) from public.treasury_flows t where t.player_id = v_pl and t.port_id = v_lis and t.kind not in ('START', 'FOUNDING')),
    'purse', 50000000 - (select p.ducats from public.players p where p.id = v_pl));
  v_out := v_out || jsonb_build_object('back', (select q.total from world.quote(v_lis, v_g, 20, 'sell', null, v_fl) q));
  return v_out;
end
$body$
  $f$;

  begin
    raise exception using errcode = 'ZX507', message = pg_temp.scene_0507(c_ua, false)::text;
  exception when sqlstate 'ZX507' then v_b := sqlerrm::jsonb;
  end;

  -- ── 3. THE KNOBS (this file's own; the owner's switch dark) ──
  insert into public.world_config (key, value, description) values
    ('buy_tax_enabled', 'false'::jsonb,
     '0507: THE SWITCH (the owner''s). true: a company''s purchase costs buy_tax_share of the rate the city asks her (world.tax_rate), at most buy_tax_max, more, paid to the city in the purchase itself (public.buy_tax_rate in world.quote_priced, so every quote, the day and the never-lose rule read it). false: a purchase pays no tax, as before.'),
    ('buy_tax_share', to_jsonb(0.1), '0507: lit, the share of the city''s profit tax rate a purchase pays (the owner: a tenth).'),
    ('buy_tax_max', to_jsonb(0.03), '0507: lit, the most a purchase pays (the owner: 0 to 3 %).');

  -- ── 4. THE RULES ──
  execute $f$
create function public.buy_tax_on()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0507: THE SWITCH, read once: world_config buy_tax_enabled.
  select public.wc('buy_tax_enabled') = 'true'::jsonb
$body$
  $f$;

  execute $f$
create function public.buy_tax_rate(p_fleet uuid, p_port uuid)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0507: WHAT A PURCHASE PAYS ON TOP, as a share of its price. THE one place (world.quote_priced alone asks it). 0 while dark, with no fleet,
-- for a merchant, and while the city purses are dark; else buy_tax_share of world.tax_rate(city, company), at most buy_tax_max.
declare
  v_player uuid;
begin
  if p_fleet is null or not public.buy_tax_on() or not public.city_treasury_on() then
    return 0;
  end if;
  select f.player_id into v_player from public.fleets f join public.players pl on pl.id = f.player_id
   where f.id = p_fleet and not coalesce(pl.is_npc, false);
  if v_player is null then
    return 0;
  end if;
  return greatest(0, least(public.wc_num('buy_tax_max'), world.tax_rate(p_port, v_player) * public.wc_num('buy_tax_share')));
end
$body$
  $f$;

  foreach v_def in array c_new loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v_def::regprocedure);
  end loop;

  -- ── 5. THE HUNK ──
  create temp table hunks_0507 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0507 values
  ('world.quote_priced(uuid,uuid,numeric,text,numeric,uuid,numeric,numeric,numeric,numeric)', 1,
$h$    v_total := v_total * v_unit;
  end if;
  units     := v_units;
$h$,
$h$    v_total := v_total * v_unit;
  end if;
  -- 0507 (dark: buy_tax_enabled): lit, A TAX WHEN BUYING (public.buy_tax_rate, asked here alone), on what she pays after her bargain, in
  -- the total and in tax_total. (v_unit is free once the walk is done; it holds the rate.)
  if p_side = 'buy' and p_fleet is not null and public.buy_tax_on() then
    v_unit  := public.buy_tax_rate(p_fleet, p_port);
    v_tax_t := v_tax_t + v_total * v_unit;
    v_total := v_total + v_total * v_unit;
  end if;
  units     := v_units;
$h$);

  for x in select distinct h.fn from hunks_0507 h loop
    v_pre := (select p.def from pre_0507 p where p.fn = x.fn);
    v_def := v_pre;
    for v_old, v_new, v_n in select h.old, h.new, h.ord from hunks_0507 h where h.fn = x.fn order by h.ord loop
      if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then
        raise exception '0507 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', v_n, x.fn,
          (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
      end if;
      v_def := replace(v_def, v_old, v_new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(x.fn::regprocedure), E'\r', '');
    for v_old, v_new, v_n in select h.old, h.new, h.ord from hunks_0507 h where h.fn = x.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, v_new, ''))) / length(v_new) <> 1 then
        raise exception '0507 self-assert FAIL: hunk % of % is not in the new body once', v_n, x.fn;
      end if;
      v_def := replace(v_def, v_new, v_old);
    end loop;
    if v_def <> v_pre then
      raise exception '0507 self-assert FAIL: % does not reverse to its pre-image', x.fn;
    end if;
  end loop;

  -- ── 6. THE SELF-ASSERT: the catalog ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked || c_new) u(q)))) <> v_fn_before then
    raise exception '0507 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0507 self-assert FAIL: the grants, volatility, definer, search path or owner of the hunked body moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
        from public.world_config c where c.key <> all (c_knobs)) <> v_cfg_before or public.buy_tax_on() then
    raise exception '0507 self-assert FAIL: a knob of another file moved, or the switch is not false';
  end if;
  if exists (select 1 from unnest(c_new) u(q)
              where has_function_privilege('anon', u.q::regprocedure, 'execute') or has_function_privilege('authenticated', u.q::regprocedure, 'execute')
                 or has_function_privilege('service_role', u.q::regprocedure, 'execute') or has_function_privilege('public', u.q::regprocedure, 'execute')
                 or (select p.provolatile from pg_proc p where p.oid = u.q::regprocedure) <> 's') then
    raise exception '0507 self-assert FAIL: a new function is reachable by a client or service_role, or is not STABLE';
  end if;
  if (select array_agg(p.oid::regprocedure::text) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> 'public.buy_tax_rate(uuid,uuid)'::regprocedure
         and position('buy_tax_rate(' in p.prosrc) > 0) is distinct from array[c_hunked[1]::regprocedure::text] then
    raise exception '0507 self-assert FAIL: the tax is not asked by world.quote_priced alone';
  end if;

  -- ── 7. DARK IDENTITY, then LIT ──
  begin
    raise exception using errcode = 'ZX507', message = pg_temp.scene_0507(c_ua, false)::text;
  exception when sqlstate 'ZX507' then v_d := sqlerrm::jsonb;
  end;
  if v_d is distinct from v_b then
    raise exception '0507 self-assert FAIL: DARK IS NOT IDENTICAL. Before: % After: %', left(v_b::text, 900), left(v_d::text, 900);
  end if;
  begin
    raise exception using errcode = 'ZX507', message = pg_temp.scene_0507(c_ua, true)::text;
  exception when sqlstate 'ZX507' then v_l := sqlerrm::jsonb;
  end;
  drop function pg_temp.scene_0507(uuid, boolean);

  -- nobody else's quote, no sale, no merchant
  if v_l->'any_l' is distinct from v_l->'any' or v_l->'sale_l' is distinct from v_l->'sale' or (v_l->>'none')::numeric <> 0 or (v_l->>'npc')::numeric <> 0
     or (v_l->>'purses_dark')::numeric <> 0 then
    raise exception '0507 self-assert FAIL: a sale, a quote with no fleet or a merchant paid the tax: %', left(v_l::text, 900);
  end if;
  -- the rate: a tenth of what the city asks her, at most 3 %; her total is the plain one and the rate, ceiled once
  if (v_l->>'r')::numeric <> least(0.03, (v_l->>'rate')::numeric * 0.1) or (v_l->>'cap')::numeric <> (case when (v_l->>'rate')::numeric > 0 then 0.03 else 0 end)
     or (v_l #>> '{hers_l,total}')::numeric - (v_l #>> '{hers,total}')::numeric * (1 + (v_l->>'r')::numeric) not between -1.04 and 1
     or (v_l #>> '{hers_l,units}') <> (v_l #>> '{hers,units}') or (v_l #>> '{hers_l,mid_total}') <> (v_l #>> '{hers,mid_total}')
     or abs((v_l #>> '{hers_l,tax_total}')::numeric - (v_l #>> '{hers,tax_total}')::numeric - (v_l #>> '{hers,total}')::numeric * (v_l->>'r')::numeric) > 0.1 then
    raise exception '0507 self-assert FAIL: her total is not the plain one x (1 + a tenth of the city''s rate): %', left(v_l::text, 900);
  end if;
  -- the Max, the door, the city's one payment, the way back
  if v_l->'max' is distinct from v_l->'max_q' or v_l #> '{paid,total}' is distinct from v_l #> '{hers_l,total}' or (v_l->>'purse')::numeric <> (v_l #>> '{hers_l,total}')::numeric
     or v_l->'flows' is distinct from jsonb_build_array(jsonb_build_array('BUY', (v_l #>> '{hers_l,total}')::bigint))
     or (v_l->>'back')::numeric >= (v_l #>> '{paid,total}')::numeric then
    raise exception '0507 self-assert FAIL: the door did not charge the quote in one payment to the city: max % / %, paid %, purse %, flows %, back %',
      v_l->'max', v_l->'max_q', v_l->'paid', v_l->'purse', v_l->'flows', v_l->'back';
  end if;

  -- ── 8. NOTHING OF THE PROBE SURVIVES; the switch is dark ──
  if exists (select 1 from public.players p where p.company_name = 'Casa da Prova 0507') or public.buy_tax_on()
     or (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
           from public.world_config c where c.key <> all (c_knobs)) <> v_cfg_before then
    raise exception '0507 self-assert FAIL: the probe left rows behind, or a knob moved';
  end if;
  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0507 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0507 self-assert ok: A TAX WHEN BUYING, 0 TO 3 %% (dark). One hunk once and reversing (world.quote_priced, the only caller of public.buy_tax_rate); no other function moved; two new functions STABLE and server only; three knobs (buy_tax_enabled false), no other moved. DARK IDENTICAL. LIT: at a city that asks her % she pays % more: 20 units % -> % d., in one BUY payment to the city; the Max priced the same; the ceiling 3 %%; a sale, a quote with no fleet, a merchant and the purses dark: none; sold back at once %. % ms.',
    v_l->'rate', v_l->'r', v_l #> '{hers,total}', v_l #> '{hers_l,total}', v_l->'back', round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0507;
  drop table pre_0507;
end $m$;
