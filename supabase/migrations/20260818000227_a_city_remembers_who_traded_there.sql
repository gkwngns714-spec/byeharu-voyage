-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0227 — A CITY REMEMBERS WHO TRADED THERE
--        (a trade's event names its city; ONE read lists a city's recent trades of one good: who,
--         bought or sold, how many, at what price, when)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER, VERBATIM (docs/OWNER_REQUESTS.md row 211, 2026-10-26) ────────────────────────────
--   "i want to see who bought what when pressed a city - clicking trade goods."
--
-- ── WHAT EXISTS, AND WHY IT COULD NOT ANSWER (docs/dev-log/2026-10-26-city-good-trades.md) ──────
--   * A trade is a BOUGHT / SOLD event (0007), written by cmd.do_buy / cmd.do_sell and nothing else
--     (prod 2026-10-26: those two bodies are the only emitters). Its payload names the fleet, the good
--     (by NAME), qty, avg_price, total — and NOT the city. The fleet moves on, so "where" was lost.
--   * The city's side, a SELL / BUY flow (public.treasury_flows, ref_event), names the harbour, but
--     tick_city rolls the flows into the daybook and deletes them hourly (0122): an hour of memory.
--   * The Stats tab's rollups (0214 stats_city_good) keep sums per slot, no names.
--   So nothing could say "who bought Wine at Lisbon".
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
--   1. THE EVENT NAMES ITS CITY. cmd.do_buy and cmd.do_sell each gain one payload key, `port` = the
--      harbour's CODE — the same key and the same spelling every other event already uses for a city
--      (FOUNDED, TRAINED, ENROLLED…; src/features/ledger/headline.ts reads it as a code). One hunk each,
--      sliced from the live body; nothing else in either body moves. Events written before the deploy
--      carry no city and are not listed (a merchant's events live ~6 h — npc_compact — so the list is
--      full within the day; a player's older trades stay unplaced).
--   2. ONE INDEX, partial, on the trades only: (payload->>'port', payload->>'good', created_at desc)
--      where kind in ('SOLD', 'BOUGHT'). Measured on prod read-only 2026-10-26: without it a good's
--      last 50 trades in a city was a backward scan of events_created_at filtering 127,533 rows
--      (239 ms) — and a quiet pair would scan the whole week. The table is 216,606 rows / 101 MB, the
--      trades ~29,500 of them; a plain (not CONCURRENTLY: a migration is one transaction) build reads
--      the heap once (a full seq scan of it took 475 ms) and holds inserts to events until commit.
--   3. ONE READ, world.city_good_trades(port, good, limit default 50): the city's trades of that good
--      over the last 7 days, newest first, at most `limit` (1…200): at, company (players.company_name
--      — a player's or a merchant's), merchant (is_npc), own (the caller's), side (bought / sold, the
--      company's side), qty, price (avg_price), total. NO purse, NO fleet, NO position.
--      DECIDED BY DEFAULT, the owner's word: names are shown. It outranks the older "never show a
--      rival's books" reading; the read gives the trade, never the house's money.
--   4. The registry (client_rpc_entry_points) gains the read: one hunk, sliced from the live body.
--
-- ── RE-CUTS (each hunk occurs once in the live body, each reverses; ACL / volatility / definer /
--    config asserted unmoved) ────────────────────────────────────────────────────────────────────
--   * cmd.do_buy(uuid, jsonb)  — 1 hunk: `'port'` into the BOUGHT payload.
--   * cmd.do_sell(uuid, jsonb) — 1 hunk: `'port'` into the SOLD payload.
--   * public.client_rpc_entry_points() — 1 hunk: + ('world', 'city_good_trades', 'uuid, uuid, int').
--
-- ── WHAT IT SELF-ASSERTS (own probe rows only; the probe is rolled back whole; nothing is deleted) ─
--   (a) the three re-cuts reverse to their pre-images; nothing else about them moved.
--   (b) the registry is the old one + 1, every row executable by authenticated; anon cannot run the
--       read; the walls are 0; the index exists and is valid.
--   (c) POSITIVE CONTROL: a probe company at Lisbon sells 10 and buys 5 of one good through
--       cmd.do_sell / cmd.do_buy; both events carry port = 'LIS'; the read, as the probe, lists exactly
--       those two of the probe's (a sale of 10 and a purchase of 5, own, not a merchant, price = the
--       event's avg_price), newest first across the whole list; limit 1 gives one row; an unknown good
--       is refused (E_NO_SUCH_GOOD). Timings of the read ×6, notice only.
--   (d) nothing of the probe survives.
--
-- Depends on: 0004 (events, players), 0007 (the trade events), 0018 (current_player_id, the registry),
-- 0224 (the do_buy / do_sell bodies as they stand, the probe idiom), 0226 (the registry as it stands).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

create or replace function pg_temp.occurs_0227(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 0. THE PRE-IMAGES of the three bodies this file re-cuts (LF-normalised), with their ACL /
--       volatility / definer / config ──────────────────────────────────────────────────────────────
create temp table defs_before_0227 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('cmd.do_buy(uuid,jsonb)'), ('cmd.do_sell(uuid,jsonb)'), ('public.client_rpc_entry_points()')) f(fn);

create temp table before_0227 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points;

-- ── 1. THE INDEX — the trades only, by city and good, newest first ──────────────────────────────
create index events_trades_port_good on public.events ((payload->>'port'), (payload->>'good'), created_at desc)
 where kind in ('SOLD', 'BOUGHT');
comment on index public.events_trades_port_good is
  '0227: world.city_good_trades — a city''s trades of one good, newest first. Partial: BOUGHT / SOLD only.';

-- ── 2. THE READ ─────────────────────────────────────────────────────────────────────────────────
create function world.city_good_trades(p_port uuid, p_good uuid, p_limit int default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0227 (owner row 211): "who bought what" — one good at one city, the last 7 days, newest first. A trade is
-- a BOUGHT / SOLD event (0007) whose payload names the city by code (since 0227) and the good by name.
-- Reads; decides nothing. Shows the company and the trade, never a purse, a fleet or a position.
declare
  v_code text := (select p.code from public.ports p where p.id = p_port);
  v_name text := (select g.name from public.goods g where g.id = p_good);
  v_me   uuid := public.current_player_id();
  v_n    int  := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_rows jsonb;
begin
  if v_code is null or v_name is null then
    raise exception 'E_NO_SUCH_GOOD: no port % or no good %', p_port, p_good using errcode = 'P0001';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'at',       t.created_at,
           'company',  pl.company_name,
           'merchant', pl.is_npc,
           'own',      coalesce(t.player_id = v_me, false),
           'side',     case t.kind when 'BOUGHT' then 'bought' else 'sold' end,
           'qty',      (t.payload->>'qty')::numeric,
           'price',    (t.payload->>'avg_price')::numeric,
           'total',    round((t.payload->>'total')::numeric))
         order by t.created_at desc, t.id), '[]'::jsonb)
    into v_rows
    from (select e.id, e.player_id, e.kind, e.payload, e.created_at
            from public.events e
           where e.kind in ('SOLD', 'BOUGHT')
             and e.payload->>'port' = v_code
             and e.payload->>'good' = v_name
             and e.created_at > now() - interval '7 days'
           order by e.created_at desc
           limit v_n) t
    join public.players pl on pl.id = t.player_id;
  return jsonb_build_object('port', p_port, 'good', p_good, 'now', now(), 'days', 7, 'trades', v_rows);
end $$;
comment on function world.city_good_trades(uuid, uuid, int) is
  '0227: a city''s recent trades of one good (7 days, newest first, ≤ limit): who, bought or sold, qty, price each, when. Names shown (owner row 211); no purse, fleet or position.';
revoke all on function world.city_good_trades(uuid, uuid, int) from public, anon, authenticated;
grant execute on function world.city_good_trades(uuid, uuid, int) to authenticated;

-- ── 3. THE RE-CUTS (hunks sliced from the live bodies; each occurs once; each reverses) ──────────
create temp table hunks_0227 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0227 values
('cmd.do_buy(uuid,jsonb)', 1,
$h$    public.emit_event(f.player_id, 'BOUGHT', jsonb_build_object(
      'fleet', f.name,$h$,
$h$    public.emit_event(f.player_id, 'BOUGHT', jsonb_build_object(
      'port', (select pc.code from public.ports pc where pc.id = f.port_id),   -- 0227: the city, by code (world.city_good_trades)
      'fleet', f.name,$h$),
('cmd.do_sell(uuid,jsonb)', 1,
$h$    public.emit_event(f.player_id, 'SOLD', jsonb_build_object(
      'fleet', f.name,$h$,
$h$    public.emit_event(f.player_id, 'SOLD', jsonb_build_object(
      'port', (select pc.code from public.ports pc where pc.id = f.port_id),   -- 0227: the city, by code (world.city_good_trades)
      'fleet', f.name,$h$),
('public.client_rpc_entry_points()', 1,
$h$      ('cmd',         'watch_price',           'uuid, uuid')
    ) as t(s, f, a)$h$,
$h$      ('cmd',         'watch_price',           'uuid, uuid'),
      -- 0227: who bought what — a city's recent trades of one good (owner row 211).
      ('world',       'city_good_trades',      'uuid, uuid, int')
    ) as t(s, f, a)$h$);

create or replace function pg_temp.recut_0227(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := (select def from defs_before_0227 where fn = p_fn);
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0227 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0227(v_def, h.old);
    if v_n <> 1 then
      raise exception '0227 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0227(fn) from defs_before_0227 order by fn;

-- ── 4. THE SELF-ASSERT (own probe rows; the probe is rolled back whole) ─────────────────────────
do $$
declare
  c_uid    constant uuid := '00000000-0227-4000-8000-000000000001';
  c_name   constant text := 'Casa do Cais 0227';
  v_d      record; v_h record; v_pp record; v_def text;
  v_before record;
  v_p      uuid; v_f uuid; v_g uuid; v_gcode text; v_port uuid;
  v_r      jsonb; v_mine jsonb; v_x jsonb;
  v_prev   timestamptz;
  v_sold   record; v_bought record;
  v_t      timestamptz;
  v_ms     numeric[] := '{}';
  v_out    jsonb;
  i        int;
begin
  select * into v_before from before_0227;

  -- (a) THE RE-CUTS reverse to their pre-images; ACL / volatility / definer / config unmoved
  for v_d in select * from defs_before_0227 loop
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    for v_h in select * from hunks_0227 where fn = v_d.fn order by n desc loop
      if pg_temp.occurs_0227(v_def, v_h.new) <> 1 then
        raise exception '0227 self-assert FAIL: hunk % of % is not in the new body exactly once', v_h.n, v_d.fn;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0227 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg
      into v_pp from pg_proc p where p.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0227 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;

  -- (b) THE REGISTRY, THE WALLS, THE INDEX
  if (select count(*) from public.client_rpc_entry_points()) <> v_before.entry_points + 1
     or not exists (select 1 from public.client_rpc_entry_points() e where e.function_name = 'city_good_trades')
     or exists (select 1 from public.client_rpc_entry_points() e where e.fn is null or not has_function_privilege('authenticated', e.fn, 'execute')) then
    raise exception '0227 self-assert FAIL: the registry is not the old one + city_good_trades, every row executable by authenticated';
  end if;
  if has_function_privilege('anon', 'world.city_good_trades(uuid, uuid, int)', 'execute')
     or (select p.provolatile from pg_proc p where p.oid = 'world.city_good_trades(uuid, uuid, int)'::regprocedure) <> 's' then
    raise exception '0227 self-assert FAIL: anon can run the read, or it is not stable';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0227 self-assert FAIL: a wall moved';
  end if;
  if not exists (select 1 from pg_index i where i.indexrelid = to_regclass('public.events_trades_port_good') and i.indisvalid) then
    raise exception '0227 self-assert FAIL: the index events_trades_port_good is missing or not valid';
  end if;

  -- (c) THE PROBE, rolled back whole
  begin
    if exists (select 1 from public.players p where p.auth_uid = c_uid) then
      raise exception '0227 self-assert FAIL: the probe house already exists';
    end if;
    v_p := public.new_house(c_uid, c_name, 'PRT', 'LIS');
    select f.id into v_f from public.fleets f where f.player_id = v_p order by f.id limit 1;
    select pg.port_id, pg.good_id, g.code into v_port, v_g, v_gcode
      from public.port_goods pg join public.ports p on p.id = pg.port_id join public.goods g on g.id = pg.good_id
     where p.code = 'LIS' and pg.stock > 50 and not public.culture_refuses(p.culture, g.culture_mask)
       and exists (select 1 from public.port_offered_goods(pg.port_id) o where o.good_id = pg.good_id)
     order by g.code limit 1;
    if v_g is null or v_f is null then
      raise exception '0227 self-assert FAIL: no probe fleet, or Lisbon offers no good with stock over 50';
    end if;
    perform public.fleet_load(v_f, v_gcode, 60, 1);

    -- THE POSITIVE CONTROL: she sells 10 and buys 5
    perform cmd.do_sell(v_f, jsonb_build_object('good', v_g, 'qty', 10));
    perform cmd.do_buy(v_f, jsonb_build_object('good', v_g, 'qty', 5));
    select e.payload->>'port' as port, (e.payload->>'qty')::numeric as qty, (e.payload->>'avg_price')::numeric as price
      into v_sold from public.events e where e.player_id = v_p and e.kind = 'SOLD';
    select e.payload->>'port' as port, (e.payload->>'qty')::numeric as qty, (e.payload->>'avg_price')::numeric as price
      into v_bought from public.events e where e.player_id = v_p and e.kind = 'BOUGHT';
    if v_sold.port is distinct from 'LIS' or v_bought.port is distinct from 'LIS' or v_sold.qty <> 10 or v_bought.qty <> 5 then
      raise exception '0227 self-assert FAIL: the probe''s events do not name Lisbon: SOLD % ×%, BOUGHT % ×%', v_sold.port, v_sold.qty, v_bought.port, v_bought.qty;
    end if;

    perform cmd.assume_identity(c_uid);
    v_r := world.city_good_trades(v_port, v_g);
    select coalesce(jsonb_agg(x), '[]'::jsonb) into v_mine from jsonb_array_elements(v_r->'trades') x where x->>'company' = c_name;
    if jsonb_array_length(v_mine) <> 2
       or not exists (select 1 from jsonb_array_elements(v_mine) x
                       where x->>'side' = 'sold' and (x->>'qty')::numeric = 10 and (x->>'price')::numeric = v_sold.price
                         and (x->>'own')::boolean and not (x->>'merchant')::boolean)
       or not exists (select 1 from jsonb_array_elements(v_mine) x
                       where x->>'side' = 'bought' and (x->>'qty')::numeric = 5 and (x->>'price')::numeric = v_bought.price
                         and (x->>'own')::boolean and not (x->>'merchant')::boolean) then
      raise exception '0227 self-assert FAIL: the read did not list the probe''s sale of 10 and purchase of 5: %', v_mine;
    end if;
    v_prev := null;
    for v_x in select x from jsonb_array_elements(v_r->'trades') x loop
      if v_prev is not null and (v_x->>'at')::timestamptz > v_prev then
        raise exception '0227 self-assert FAIL: the list is not newest first: %', v_r->'trades';
      end if;
      v_prev := (v_x->>'at')::timestamptz;
    end loop;
    if jsonb_array_length(world.city_good_trades(v_port, v_g, 1)->'trades') <> 1 then
      raise exception '0227 self-assert FAIL: limit 1 did not give one row';
    end if;
    begin
      perform world.city_good_trades(v_port, gen_random_uuid());
      raise exception '0227 self-assert FAIL: an unknown good was not refused';
    exception when others then
      if sqlerrm not like 'E_NO_SUCH_GOOD%' then raise; end if;
    end;

    for i in 1..6 loop
      v_t := clock_timestamp();
      perform world.city_good_trades(v_port, v_g);
      v_ms := v_ms || round(extract(epoch from clock_timestamp() - v_t) * 1000, 2);
    end loop;

    raise exception using errcode = 'ZX227', message = jsonb_build_object(
      'good', v_gcode, 'listed', jsonb_array_length(v_r->'trades'), 'ms', to_jsonb(v_ms))::text;
  exception when sqlstate 'ZX227' then
    v_out := sqlerrm::jsonb;
  end;

  -- (d) nothing of the probe survives
  if exists (select 1 from public.players p where p.auth_uid = c_uid) then
    raise exception '0227 self-assert FAIL: the probe left rows behind';
  end if;

  raise notice '0227 self-assert ok: A CITY REMEMBERS WHO TRADED THERE. do_buy / do_sell / the registry re-cut by one hunk each, each reversed; registry +1; walls 0; index valid. Probe at Lisbon, %: a sale of 10 and a purchase of 5, both events naming LIS, both listed as the probe''s own (% row(s) in the list), newest first; limit 1 → 1 row; an unknown good refused. world.city_good_trades × 6 = % ms. Rolled back.',
    v_out->>'good', v_out->>'listed', v_out->'ms';
end $$;
