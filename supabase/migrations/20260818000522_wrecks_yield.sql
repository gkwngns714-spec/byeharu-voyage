-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none (dark: nothing changes for a player until the owner lights wrecks_yield_enabled)
-- 0522 - WHAT A WON ROUND GIVES  (dark: wrecks_yield_enabled. Slice `wrecks-yield`, docs/design/rounds-2026-11-25.md section 7; screen word Wrecks)
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-25 (R5): combat "gives the same benefits of expedition - gold and reputation", and "wrecks - ships and gears, that can be gathered and be
--   used to make, upgrade ships and gears".
-- EVERYTHING IS MOVED, NOTHING IS MADE (public.round_spoils, called by the one settle for the rounds it books that were won; a lost round gives nothing):
--   GOLD    out of the Brethren's hoard by its one payer (public.pirate_pay, kind LOOT: its day's room, its capital's surplus): yield.gold a point of the sea's
--           strength a won round, for the share of hull it cost her (0374's rule: loot_risk_full), under loot_per_ship a round and what is left of
--           loot_per_company_day (public.loot_today). A hoard with less room pays what it has; none: nothing, and it is not owed.
--   SALVAGE the goods a hull is made of (planks, timber, cordage, canvas duck, iron, tar), by the round's dice, taken OUT OF THE PIRATE HOMES' OWN STOCK
--           (port_goods of public.pirate_home harbours, which 0339's plunder fills): never more than a tenth of what is there, never more than her hold takes.
--           They are the yard's and the Forge's ordinary materials (goods_recipes, item_recipes): no new Forge, no new currency.
--   REPUTATION yield.rp a won round (kind `round`, inside the day's cap of rep_day_cap).
-- The player's own WRECKED fleet (#865, #868) is another thing: this code says salvage.
-- What a run gave is in its `carry` {gold, rp, salvage {good: units}}.
-- ROWS, lit: a settle with won rounds adds 1 to 8 rows (a ledger row, two treasury rows, a Reputation row, up to four market rows updated). -- budget: that. -- retention: none.
-- LOCKS: rows of data, CREATE FUNCTION x2, CREATE OR REPLACE x1 by hunks. A pirate home's market row busy is passed over (SKIP LOCKED); the hoard busy pays nothing.
-- ROLLBACK (forward, owner only): wrecks_yield_enabled false. FULL: a migration reversing the hunks.
-- VERSION: 0522 (after 0521).
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
do $m$
declare
  c_hunked constant text[] := array['public.round_settle(uuid,timestamp with time zone)', 'public.round_settle_due(timestamp with time zone,integer)']::text[];
  c_new    constant text[] := array['public.wrecks_yield_on()', 'public.round_spoils(uuid,integer,integer,timestamptz)']::text[];
  c_doors  constant text[] := array[]::text[];
  c_knobs  constant text[] := array['wrecks_yield_enabled']::text[];
  c_ua     constant uuid := '00000000-0522-4000-8000-0000000000a1';
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
  v_l          jsonb;
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);
  -- ── 0. GUARD ──
  if to_regprocedure('public.wrecks_yield_on()') is not null then
    raise exception '0522 refuses: it has been applied once';
  end if;
  if exists (select 1 from unnest(c_hunked || array['public.pirate_pay(text,bigint,timestamp with time zone,uuid,uuid)', 'public.loot_today(uuid,timestamp with time zone)', 'public.round_sequence(uuid,jsonb,jsonb,jsonb,timestamptz)']::text[]) f where to_regprocedure(f) is null) then
    raise exception '0522 refuses: what it stands on is not in this world';
  end if;
  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0522 (fn text primary key, def text) on commit drop;
  insert into pre_0522 select f, replace(pg_get_functiondef(f::regprocedure), E'\r', '') from unnest(c_hunked) f;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
    into v_cfg_before from public.world_config c;
  -- ── 2. THE KNOBS AND THE DATA ──
  insert into public.world_config (key, value, description) values
    ('wrecks_yield_enabled', 'false'::jsonb, '0522: THE SWITCH (the owner''s). true: a won combat round gives gold out of the pirates'' hoard, salvage out of their homes'' stock, and Reputation.');
  insert into public.reputation_kinds (code, sign, capped, word) values ('round', 1, true, 'Rounds');
  update public.round_works set yield = '{"gold": 40, "rp": 2, "salvage": [["timber", 3, 4], ["planks", 2, 2], ["cordage", 3, 3], ["canvas-duck", 2, 3], ["iron", 2, 3], ["tar", 1, 2]]}' where code = 'pirates';

  -- ── 3. THE RULES ──
  execute $f$
create function public.wrecks_yield_on()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0522: THE SWITCH, read once: world_config wrecks_yield_enabled.
  select public.wc('wrecks_yield_enabled') = 'true'::jsonb
$body$
  $f$;
  execute $f$
create function public.round_spoils(p_fleet uuid, p_from integer, p_to integer, p_at timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0522: WHAT THE WON ROUNDS p_from .. p_to OF HER RUN GAVE (public.round_settle books them and calls this once for them): gold out of the hoard, salvage out of the
-- pirate homes' stock, Reputation. The run's `carry` with them added. yield.salvage: [[good, weight, most units a pick]]; two picks a won round by voyage.rng.
declare
  r       public.round_runs%rowtype;
  y       jsonb;
  v_won   int := 0;
  v_gold  numeric := 0;
  v_due   bigint;
  v_paid  bigint := 0;
  v_full  numeric := public.wc_num('loot_risk_full');
  v_sum   numeric;
  v_need  jsonb := '{}'::jsonb;
  v_got   jsonb := '{}'::jsonb;
  v_rp    int := 0;
  g       record;
  h       record;
  v_left  numeric;
  v_take  numeric;
  v_roll  numeric;
  v_homes uuid[];   -- public.pirate_home's rule, read once for the four or so homes there are
begin
  select * into r from public.round_runs x where x.fleet_id = p_fleet;
  if not public.wrecks_yield_on() or not (r.terms ? 'fight') then
    return r.carry;
  end if;
  select w.yield into y from public.round_works w where w.code = r.work;
  select sum((e->>1)::numeric) into v_sum from jsonb_array_elements(y->'salvage') e;
  for n in p_from .. p_to loop
    continue when (r.terms #>> array['fight', 'w', (n - 1)::text]) is distinct from '1';
    v_won := v_won + 1;
    v_gold := v_gold + least(public.wc_num('loot_per_ship'), coalesce((y->>'gold')::numeric, 0) * (r.terms->>'strength')::numeric
                * case when v_full > 0 then least(1, (r.terms #>> array['fight', 'l', (n - 1)::text])::numeric / v_full) else 1 end);
    for k in 1 .. 2 loop
      v_roll := voyage.rng(p_fleet, n * 10 + k, 'salvage:' || extract(epoch from r.sent_at)::text) * coalesce(v_sum, 0);
      for g in select e->>0 as code, (e->>2)::int as most, sum((e->>1)::numeric) over (order by o) as hi from jsonb_array_elements(y->'salvage') with ordinality q(e, o) order by o loop
        if v_roll < g.hi then
          v_need := v_need || jsonb_build_object(g.code, coalesce((v_need->>g.code)::int, 0) + 1 + floor(voyage.rng(p_fleet, n * 10 + k, 'units:' || extract(epoch from r.sent_at)::text) * g.most)::int);
          exit;
        end if;
      end loop;
    end loop;
  end loop;
  if v_won = 0 then
    return r.carry;
  end if;
  -- the hoard: whole ducats, under the company's day, what the hoard may spend and its capital holds
  v_due := greatest(0, floor(least(v_gold, public.wc_num('loot_per_company_day') - public.loot_today(r.player_id, p_at), public.pirate_spend_room(p_at),
                                   public.city_surplus(public.pirate_capital()))))::bigint;
  if v_due > 0 then
    v_paid := public.pirate_pay('LOOT', v_due, p_at, null, r.player_id);
  end if;
  -- the salvage: from the homes with the most, never over a tenth of a stock, never over her hold
  select array_agg(a.port_id) into v_homes from public.port_allegiance a join public.great_powers q on q.nation_id = a.nation_id where a.home and q.pirate;
  for g in select e.key as code, e.value::numeric as qty, z.id, z.bulk from jsonb_each_text(v_need) e join public.goods z on z.code = e.key order by e.key loop
    v_left := least(g.qty, floor(public.fleet_free_hold(p_fleet) / g.bulk));
    for h in select pg.port_id, pg.stock from public.port_goods pg where pg.good_id = g.id and pg.stock >= 10 and pg.port_id = any (v_homes) order by pg.stock desc, pg.port_id for update of pg skip locked loop
      exit when v_left < 1;
      v_take := least(v_left, floor(h.stock / 10));
      update public.port_goods pg set stock = pg.stock - v_take, updated_at = now() where pg.port_id = h.port_id and pg.good_id = g.id;
      perform public.fleet_load(p_fleet, g.code, v_take, 0);
      v_got := v_got || jsonb_build_object(g.code, coalesce((v_got->>g.code)::numeric, 0) + v_take);
      v_left := v_left - v_take;
    end loop;
  end loop;
  if coalesce((y->>'rp')::int, 0) > 0 then
    v_rp := public.reputation_credit(r.player_id, 'round', (y->>'rp')::int * v_won, 'round:' || p_fleet || ':' || extract(epoch from r.sent_at)::text || ':' || p_to, jsonb_build_object('work', r.work));
  end if;
  return r.carry || jsonb_build_object('won', coalesce((r.carry->>'won')::int, 0) + v_won, 'gold', coalesce((r.carry->>'gold')::bigint, 0) + v_paid, 'rp', coalesce((r.carry->>'rp')::int, 0) + v_rp,
           'salvage', (select coalesce(jsonb_object_agg(z.k, z.q), '{}'::jsonb) from (select q.key as k, sum(q.value::numeric) as q
              from (select * from jsonb_each_text(coalesce(r.carry->'salvage', '{}'::jsonb)) union all select * from jsonb_each_text(v_got)) q group by q.key) z));
end
$body$
  $f$;
  foreach v_def in array c_new || c_doors loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v_def::regprocedure);
  end loop;
  foreach v_def in array c_doors loop
    execute format('grant execute on function %s to authenticated', v_def::regprocedure);
  end loop;
  -- ── 4. THE HUNKS ──
  create temp table hunks_0522 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0522 values
  ('public.round_settle(uuid,timestamp with time zone)', 1,
$h$    r.booked := r.booked + v_n;
$h$,
$h$    r.carry := public.round_spoils(p_fleet, r.booked + 1, r.booked + v_n, p_at);   -- 0522 (dark: the carry as it is)
    r.booked := r.booked + v_n;
$h$),
  ('public.round_settle(uuid,timestamp with time zone)', 2,
$h$  update public.round_runs set booked = r.booked, log = r.log,$h$,
$h$  update public.round_runs set booked = r.booked, log = r.log, carry = r.carry,$h$),
  ('public.round_settle(uuid,timestamp with time zone)', 3,
$h$'rounds', r.booked, 'why', r.terms->>'why',$h$,
$h$'rounds', r.booked, 'why', r.terms->>'why', 'carry', r.carry,$h$),
  ('public.round_settle_due(timestamp with time zone,integer)', 1,
$h$    v_n := v_n + 1;
$h$,
$h$    v_n := v_n + 1;
    exit when clock_timestamp() - v_t0 > interval '12 milliseconds';   -- 0522: the jobs' tick gives this 12 ms (the first always runs); the rest next run
$h$),
  ('public.round_settle_due(timestamp with time zone,integer)', 2,
$h$  v_n int := 0;
$h$,
$h$  v_n int := 0;
  v_t0 timestamptz := clock_timestamp();   -- 0522
$h$);

  for x in select distinct h.fn from hunks_0522 h loop
    v_pre := (select p.def from pre_0522 p where p.fn = x.fn);
    v_def := v_pre;
    for v_old, v_new, v_n in select h.old, h.new, h.ord from hunks_0522 h where h.fn = x.fn order by h.ord loop
      if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then
        raise exception '0522 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', v_n, x.fn,
          (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
      end if;
      v_def := replace(v_def, v_old, v_new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(x.fn::regprocedure), E'\r', '');
    for v_old, v_new, v_n in select h.old, h.new, h.ord from hunks_0522 h where h.fn = x.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, v_new, ''))) / length(v_new) <> 1 then
        raise exception '0522 self-assert FAIL: hunk % of % is not in the new body once', v_n, x.fn;
      end if;
      v_def := replace(v_def, v_new, v_old);
    end loop;
    if v_def <> v_pre then
      raise exception '0522 self-assert FAIL: % does not reverse to its pre-image', x.fn;
    end if;
  end loop;

  -- ── 6. THE SELF-ASSERT: the catalog ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked || c_new || c_doors) u(q)))) <> v_fn_before then
    raise exception '0522 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0522 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
        from public.world_config c where c.key <> all (c_knobs)) <> v_cfg_before or public.wrecks_yield_on() then
    raise exception '0522 self-assert FAIL: a knob of another file moved, or the switch is not false';
  end if;
  if exists (select 1 from unnest(c_new) u(q)
              where has_function_privilege('anon', u.q::regprocedure, 'execute') or has_function_privilege('authenticated', u.q::regprocedure, 'execute')
                 or has_function_privilege('service_role', u.q::regprocedure, 'execute') or has_function_privilege('public', u.q::regprocedure, 'execute'))
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0522 self-assert FAIL: a new function is reachable by a client or service_role';
  end if;

  -- ── 5. THE PROBE (its own company, work, stores; rolled back) ──
  begin
    declare
      v_pl uuid; v_fl uuid; v_lis uuid; a jsonb; b jsonb; v_k int; v_sum0 numeric; v_sum1 numeric; v_stk0 numeric; v_stk1 numeric; v_hold numeric; v_cap uuid := public.pirate_capital();
    begin
      v_pl := public.new_house(c_ua, 'Casa da Prova 0522', 'PRT');
      select f.id, f.port_id into v_fl, v_lis from public.fleets f where f.player_id = v_pl;
      update public.world_config set value = 'true'::jsonb where key in ('rounds_enabled', 'city_treasury_enabled', 'reputation_on', 'ship_stores_separate');
      update public.world_config set value = to_jsonb(1) where key = 'pirate_spend_day_pct';
      update public.world_config set value = to_jsonb(0.075) where key = 'loot_risk_full';
      update public.world_config set value = to_jsonb(60000) where key = 'loot_per_ship';
      update public.world_config set value = to_jsonb(240000) where key = 'loot_per_company_day';
      update public.world_config set value = to_jsonb(600) where key = 'rep_day_cap';
      insert into public.port_treasury (port_id) values (v_cap) on conflict (port_id) do nothing;
      update public.port_treasury set ducats = ducats + 100000000 where port_id = v_cap;
      update public.port_goods pg set stock = 1000 from public.goods g where g.id = pg.good_id and public.pirate_home(pg.port_id) and g.code in ('planks', 'timber', 'cordage', 'canvas-duck', 'iron', 'tar');
      -- a run of four rounds, three won, written here: no dice of a fight
      for v_k in 0 .. 1 loop
        begin
          if v_k = 1 then update public.world_config set value = 'true'::jsonb where key = 'wrecks_yield_enabled'; end if;
          insert into public.round_runs (fleet_id, player_id, work, sea_id, state, sent_at, stop_at, terms)
          values (v_fl, v_pl, 'pirates', (select h.sea_id from public.ports h where h.id = v_lis), 'out', now(), now() + interval '2400 seconds',
                  '{"seconds": 600, "crew": 0, "food": 0, "water": 0, "ammo": 0, "most": 4, "why": "rounds", "strength": 10, "kind": "combat", "fight": {"l": [0.075, 0.03, 0.15, 0.1], "c": [0, 0, 0, 0], "w": [1, 1, 0, 1]}}');
          update public.fleets set status = 'ROUNDS', busy_until = now() + interval '2400 seconds' where id = v_fl;
          v_sum0 := (select p.ducats from public.players p where p.id = v_pl) ;
          select coalesce(sum(t.ducats), 0) into v_stk0 from public.treasury_flows t where t.player_id = v_pl;
          v_hold := public.fleet_free_hold(v_fl);
          perform public.round_settle(v_fl, now() + interval '1300 seconds');
          perform public.round_settle(v_fl, now() + interval '3000 seconds');
          v_sum1 := (select p.ducats from public.players p where p.id = v_pl);
          select coalesce(sum(t.ducats), 0) into v_stk1 from public.treasury_flows t where t.player_id = v_pl;
          raise exception using errcode = 'ZY522', message = jsonb_build_object('carry', (select zr.carry from public.round_runs zr where zr.fleet_id = v_fl), 'purse', v_sum1 - v_sum0, 'city', v_stk1 - v_stk0,
            'kind', (select string_agg(distinct l.kind, ',') from public.ledger l where l.player_id = v_pl and l.kind = 'LOOT'),
            'aboard', (select sum(public.fleet_cargo_qty(v_fl, c.c)) from (values ('planks'), ('timber'), ('cordage'), ('canvas-duck'), ('iron'), ('tar')) c(c)),
            'home', (select 1000 * count(*) - sum(pg.stock) from public.port_goods pg join public.goods g on g.id = pg.good_id where public.pirate_home(pg.port_id) and g.code in ('planks', 'timber', 'cordage', 'canvas-duck', 'iron', 'tar')),
            'rp', (select coalesce(sum(b2.delta), 0) from public.reputation_book b2 where b2.player_id = v_pl and b2.kind = 'round'))::text;
        exception when sqlstate 'ZY522' then
          if v_k = 0 then a := sqlerrm::jsonb; else b := sqlerrm::jsonb; end if;
        end;
      end loop;
      raise exception using errcode = 'ZX522', message = jsonb_build_object('dark', a, 'lit', b)::text;
    end;
  exception when sqlstate 'ZX522' then v_l := sqlerrm::jsonb;
  end;
  if v_l is null or not coalesce(v_l #> '{dark,carry}' = '{}'::jsonb and (v_l #>> '{dark,purse}')::numeric = 0 and (v_l #>> '{dark,home}')::numeric = 0
     and (v_l #>> '{lit,purse}')::numeric = floor(40 * 10 * 1) + floor(40 * 10 * 0.4) + floor(40 * 10 * 1) and (v_l #>> '{lit,purse}')::numeric + (v_l #>> '{lit,city}')::numeric = 0
     and v_l #>> '{lit,kind}' = 'LOOT' and (v_l #>> '{lit,home}')::numeric = (v_l #>> '{lit,aboard}')::numeric and (v_l #>> '{lit,aboard}')::numeric between 6 and 24
     and (v_l #>> '{lit,rp}')::int = 6 and (v_l #>> '{lit,carry,won}')::int = 3 and (v_l #>> '{lit,carry,gold}')::bigint = (v_l #>> '{lit,purse}')::bigint, false) then
    raise exception '0522 self-assert FAIL: the probe: %', v_l;
  end if;
  if exists (select 1 from public.players p where p.company_name = 'Casa da Prova 0522') or public.wrecks_yield_on()
     or (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key)) from public.world_config c where c.key <> all (c_knobs)) <> v_cfg_before then
    raise exception '0522 self-assert FAIL: the probe left rows behind, or a knob moved';
  end if;
  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0522 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0522 self-assert ok: WHAT A WON ROUND GIVES (dark). Hunks once and reversing; no other function moved; two functions server only. Probe (rolled back): % . % ms.', v_l, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0522;
  drop table pre_0522;
end $m$;
