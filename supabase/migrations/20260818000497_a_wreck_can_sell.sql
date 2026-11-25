-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none (dark: nothing changes for a player until the owner lights wreck_sells_enabled)
-- 0497 - A WRECK CAN SELL  (dark: the switch wreck_sells_enabled, false)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE LEAD'S PROD READS, 2026-11-25 01:45 UTC, the owner's own company: purse 0; her one fleet UNABLE_TO_SAIL at Diego Garcia (a
--   market, an inn, a warehouse; no shipyard), hull 0, 899 black coral aboard; her queue SAIL BAN, SAIL MAL, SAIL MAC, SELL black-coral
--   ALL, all pending. Read in the bodies and played locally in exactly that state:
--     * cmd.do_sell, cmd.do_store and cmd.do_take ask status DOCKED, and cmd.advance runs nothing for an UNABLE_TO_SAIL fleet. So the
--       Sell press is not even refused: cmd.preview answers {queued: true}, cmd.issue answers ok, and the order waits for ever.
--     * the tow (public.tow_for) to the nearest yard asks coin she does not have (E_TOW_FUNDS), and there is no credit.
--   A hold worth half a million coin, and no way to turn one coral of it into coin where she lies: stuck for ever.
--
-- WHAT (lit; dark every body answers as before, to the letter):
--   public.wreck_sells_on()        THE SWITCH, read once: world_config wreck_sells_enabled.
--   public.fleet_alongside(fleet)  DOES SHE LIE WHERE A CARGO IS LANDED? THE ONE READING the three cargo doors ask instead of their own
--                                  `status <> 'DOCKED'`: DOCKED (as before); or, lit, a player's fleet UNABLE_TO_SAIL that lies IN A
--                                  PORT and has a ship. A wreck at sea, an empty fleet (0321: nothing to land) and a merchant's
--                                  fleet (she is tended by public.npc_tend_route's tow) are not alongside. Her state is still the
--                                  one rule's (public.fleet_state_of: wrecked): this asks only whether a quay is under her.
--   public.wreck_may(verb)         the orders a wreck alongside may run: SELL, STORE, TAKE. No buying, no sailing, nothing else.
--   public.wreck_order_refusal     THE TRUTH FOR A WRECK'S ORDER (lit): an UNABLE_TO_SAIL player fleet's order that cannot run (a
--                                  verb other than those three, or she is not alongside) is REFUSED with E_NOT_DOCKED and a plain
--                                  sentence, instead of being queued to wait for ever. Null for every other fleet and order.
--   cmd.do_sell, do_store, do_take (1 hunk each) ask public.fleet_alongside. Everything after that line is untouched: the same quote,
--                                  tax, wages, dock fee, day limit and city purse a docked fleet's sale meets.
--   cmd.advance                    (3 hunks) a wreck alongside runs her queue's SELL / STORE / TAKE orders in their order and
--                                  STEPS OVER the rest without running or cancelling them (her SAILs stay pending; a tow clears
--                                  them, as before). No standing route refills a wreck's queue.
--   cmd.preview, cmd.issue         (1 hunk each) ask public.wreck_order_refusal first; and the dry run of a wreck's SELL is the real
--                                  thing rolled back (its estimate), not {queued: true}.
-- NOT CHANGED: a docked fleet's every path (asserted: her dry run is the same answer before and after, lit); cmd.issue_lines (a plan
--   for a wreck still queues: a job's plan asks DOCKED already); public.tow_for and its price; cmd.do_repair; any knob but the new
--   switch; any table.
-- HER QUEUE (the owner's): lit, the first cmd.advance for her (her next press: any order she sends) runs the SELL already waiting in
--   her queue, then her own; the three SAILs stay pending and are never run while she is wrecked.
-- COST FOR A NORMAL FLEET: one function call more in each cargo door (her fleet row by key and one knob read); cmd.advance asks
--   nothing new unless she is UNABLE_TO_SAIL. The notice prints a docked dry run before and after.
-- ROWS: one world_config row. No table, no index, no cron, no beat step. 0 new rows a minute.
-- budget: no table, no cron job, no autovacuum or fillfactor change. Lit: a wreck's sale writes the rows any sale writes.
-- LOCKS: one INSERT (world_config); CREATE FUNCTION x4; CREATE OR REPLACE x6 by hunks. TIME: about a second. BUDGET:
--   statement_timeout 60 s, lock_timeout 5 s; fails above 45 s.
-- ROLLBACK (forward, owner only): QUICK, wreck_sells_enabled false. FULL: a migration reversing the eight hunks (OLD texts below
--   verbatim) and dropping the four functions.
-- SELF-ASSERT: each hunk once and reversing; no other function moved; the hunked bodies' grants, volatility, definer, search path and
--   owner unmoved; the new functions server only; one knob added (false), no other moved. THE PROBE (rolled back; its own company, a
--   good chosen by asking the server what its home quay buys: nothing of prod's market or companies is counted; where the quay buys
--   nothing today the law is read on the quay's own refusal: scripts/ops/harness/a-wreck-can-sell/perturb.mjs plays such worlds): dark, a wreck's
--   SELL is queued as before and a docked fleet's dry run is what it was; lit, the wreck's SELL runs past her pending SAILs (coin in,
--   cargo out, the SAILs still pending), STORE and TAKE run, BUY and SAIL are refused and not queued, a wreck at sea, an empty
--   fleet and a merchant's wreck are not alongside and run nothing, and a docked fleet's dry run is still what it was.
-- VERSION: 0497 (prod head 0496).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_hunked constant text[] := array['cmd.do_sell(uuid,jsonb)', 'cmd.do_store(uuid,jsonb)', 'cmd.do_take(uuid,jsonb)',
                                    'cmd.advance(uuid,timestamp with time zone)', 'cmd.preview(uuid,text,jsonb)', 'cmd.issue(uuid,text,integer,jsonb)'];
  c_new    constant text[] := array['public.wreck_sells_on()', 'public.fleet_alongside(uuid)', 'public.wreck_may(text)', 'public.wreck_order_refusal(uuid,text)'];
  c_ua     constant uuid := '00000000-0497-4000-8000-0000000000a1';
  v_t0        timestamptz := clock_timestamp();
  v_h         record;
  x           record;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_fn_before text;
  v_meta      text;
  v_cfg_before text;
  v_d0        jsonb;
  v_d1        jsonb;
  v_d2        jsonb;
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.world_config where key = 'wreck_sells_enabled') or to_regprocedure('public.fleet_alongside(uuid)') is not null then
    raise exception '0497 refuses: it has been applied once';
  end if;
  if exists (select 1 from unnest(c_hunked) u(q) where to_regprocedure(u.q) is null) or to_regprocedure('public.tow_for(uuid,uuid)') is null
     or to_regprocedure('cmd.refusal(text,text,jsonb)') is null or to_regprocedure('public.fleet_state(uuid)') is null then
    raise exception '0497 refuses: a body it cuts, the tow (0152) or the one state rule (0448) is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
    into v_cfg_before from public.world_config c;

  -- ── 2. THE SCENE (a temp function, run before the hunks, after them dark, and after them lit) ──
  execute $f$
create function pg_temp.scene_0497(p_uid uuid, p_lit boolean)
returns jsonb
language plpgsql
as $body$
declare
  v_pl   uuid;
  v_fl   uuid;
  v_port uuid;
  v_g    text;
  v_g0   text;      -- the first good that goes aboard at all: the scene's good when her quay buys nothing today
  v_r    jsonb;
  v_dock jsonb;
  v_prev jsonb;
  v_sell jsonb;
  v_ord  jsonb;
  v_c0   numeric;
  v_p0   bigint;
  v_c1   numeric;
  v_p1   bigint;
  v_store jsonb;
  v_take jsonb;
  v_buy  jsonb;
  v_sail jsonb;
  v_n0   bigint;
  v_sea  jsonb;
  v_empty jsonb;
  v_npc  jsonb;
  v_nf   uuid;
  v_ms   numeric;
  v_t    timestamptz;
  g      record;
begin
  v_pl := public.new_house(p_uid, 'Casa da Prova 0497', 'PRT');
  select f.id, f.port_id into v_fl, v_port from public.fleets f where f.player_id = v_pl;
  update public.players p set ducats = 1000 where p.id = v_pl;
  update public.fleets set status = 'DOCKED', ready_at = null where id = v_fl;
  if p_lit then
    update public.world_config set value = 'true'::jsonb where key = 'wreck_sells_enabled';
  end if;
  perform cmd.assume_identity(p_uid);
  -- THE GOOD: the first, by its code, that her home quay takes from her today (the server's own dry run says so; nothing here
  -- knows a price). 20 units of it go aboard at a cost of 1. A WORLD WHOSE QUAY BUYS NOTHING TODAY (its purse empty, its rows
  -- gone, the day's limit spent) IS STILL A WORLD THIS FILE MUST APPLY IN: then the first good that goes aboard is the scene's, and
  -- the law is read on the quay's own refusal instead of on a sale (the wreck is refused as a docked fleet is, never queued).
  for g in select x.code from public.goods x where x.bulk > 0 order by x.code limit 60 loop
    begin
      perform public.fleet_load(v_fl, g.code, 20, 1);
      v_g0 := coalesce(v_g0, g.code);
      v_r := cmd.preview(v_fl, format('SELL %s ALL', g.code));
      if (v_r->>'ok')::boolean and (v_r #>> '{estimate,qty}')::numeric >= 10 and (v_r #>> '{estimate,net}')::numeric > 0 then
        v_g := g.code;
        exit;
      end if;
      perform public.fleet_unload(v_fl, g.code, public.fleet_cargo_qty(v_fl, g.code));
    exception when others then
      null;
    end;
  end loop;
  if v_g is null then
    if v_g0 is null then
      raise exception '0497 scene: none of the first sixty goods can be put aboard a ship';
    end if;
    v_g := v_g0;
    perform public.fleet_load(v_fl, v_g, 20, 1);
  end if;
  -- (docked) her dry run, and what twenty of them cost in time
  v_dock := cmd.preview(v_fl, format('SELL %s 5', v_g));
  v_t := clock_timestamp();
  for i in 1 .. 20 loop
    perform cmd.preview(v_fl, format('SELL %s 5', v_g));
  end loop;
  v_ms := round(extract(epoch from clock_timestamp() - v_t)::numeric * 1000 / 20, 2);

  -- (wrecked, in port) the owner's state: every hull 0, UNABLE_TO_SAIL, a SAIL waiting in her queue ahead of anything she sends
  update public.ships set durability = 0 where fleet_id = v_fl;
  update public.fleets set status = 'UNABLE_TO_SAIL' where id = v_fl;
  insert into public.orders (fleet_id, player_id, seq, raw_text, verb, args, status)
  values (v_fl, v_pl, 1, 'SAIL CAD', 'SAIL', jsonb_build_object('dest', (select p.id from public.ports p where p.code = 'CAD')), 'pending');
  v_c0 := public.fleet_cargo_qty(v_fl, v_g);
  v_p0 := (select ducats from public.players where id = v_pl);
  v_prev := cmd.preview(v_fl, format('SELL %s 5', v_g));
  v_sell := cmd.issue(v_fl, format('SELL %s 5', v_g), null, null);
  v_c1 := public.fleet_cargo_qty(v_fl, v_g);
  v_p1 := (select ducats from public.players where id = v_pl);
  v_ord := (select jsonb_agg(o.verb || ':' || o.status order by o.seq) from public.orders o where o.fleet_id = v_fl);
  -- STORE, then TAKE it back (her home has a warehouse, or both are refused alike dark and lit)
  v_store := cmd.issue(v_fl, format('STORE %s 3', v_g), null, null);
  v_take := cmd.issue(v_fl, format('TAKE %s 3', v_g), null, null);
  -- what she may not do
  v_n0 := (select count(*) from public.orders o where o.fleet_id = v_fl);
  v_buy := cmd.issue(v_fl, format('BUY %s 1', v_g), null, null);
  v_sail := cmd.issue(v_fl, 'SAIL CAD', null, null);
  v_buy := v_buy || jsonb_build_object('queued', (select count(*) from public.orders o where o.fleet_id = v_fl) - v_n0, 'preview', cmd.preview(v_fl, format('BUY %s 1', v_g)));

  -- (wrecked, at sea) no quay under her
  update public.fleets set port_id = null, lat = 30, lon = -20 where id = v_fl;
  v_r := cmd.issue(v_fl, format('SELL %s 1', v_g), null, null);
  v_sea := jsonb_build_object('alongside', public.fleet_alongside(v_fl), 'sell', jsonb_build_object('ok', v_r->'ok', 'error_code', v_r->'error_code', 'status', v_r #> '{order,status}'));
  update public.fleets set port_id = v_port, lat = null, lon = null where id = v_fl;
  -- (an empty fleet, 0321) and (a merchant's wreck): not alongside; a merchant's waiting SELL is not run
  v_empty := to_jsonb(public.fleet_alongside((select f.id from public.fleets f where not exists (select 1 from public.ships s where s.fleet_id = f.id) limit 1)));
  select nf.fleet_id into v_nf from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id
   where f.port_id is not null and exists (select 1 from public.ships s where s.fleet_id = f.id) order by nf.fleet_id limit 1;
  if v_nf is not null then
    update public.orders set status = 'cancelled' where fleet_id = v_nf and status in ('pending', 'active');
    update public.fleets set status = 'UNABLE_TO_SAIL' where id = v_nf;
    insert into public.orders (fleet_id, player_id, seq, raw_text, verb, args, status)
    select v_nf, f.player_id, (select coalesce(max(o.seq), 0) + 1 from public.orders o where o.fleet_id = v_nf), 'SELL x ALL', 'SELL',
           jsonb_build_object('good', (select x.id from public.goods x where x.code = v_g), 'qty_mode', 'ALL'), 'pending'
      from public.fleets f where f.id = v_nf;
    v_npc := jsonb_build_object('alongside', public.fleet_alongside(v_nf), 'ran', cmd.advance(v_nf),
                                'refusal', public.wreck_order_refusal(v_nf, 'BUY'));
  end if;
  return jsonb_build_object(
    'good', v_g, 'dock', v_dock - 'parsed' - 'fixes', 'dock_ms', v_ms,
    'prev', v_prev - 'parsed' - 'fixes', 'sell', jsonb_build_object('ok', v_sell->'ok', 'code', v_sell->'error_code', 'order', jsonb_build_object('status', v_sell #> '{order,status}')), 'sold', v_c0 - v_c1, 'coin', v_p1 - v_p0, 'orders', v_ord,
    'store', jsonb_build_object('ok', v_store->'ok', 'status', v_store #> '{order,status}', 'code', v_store->'error_code'),
    'take', jsonb_build_object('ok', v_take->'ok', 'status', v_take #> '{order,status}', 'code', v_take->'error_code'),
    'buy', jsonb_build_object('ok', v_buy->'ok', 'code', v_buy->'error_code', 'msg', v_buy->'error_message', 'queued', v_buy->'queued',
                              'preview_ok', v_buy #> '{preview,ok}', 'preview_queued', v_buy #> '{preview,queued}', 'preview_code', v_buy #> '{preview,error_code}'),
    'sail', jsonb_build_object('ok', v_sail->'ok', 'code', v_sail->'error_code'),
    'sea', v_sea, 'empty', v_empty, 'npc', v_npc,
    'state', public.fleet_state(v_fl), 'status', (select f.status from public.fleets f where f.id = v_fl));
end
$body$
  $f$;

  -- the scene's helpers do not exist yet: before the hunks it is run through a twin that leaves them out
  execute replace(replace(replace(replace(replace(
            pg_get_functiondef('pg_temp.scene_0497(uuid,boolean)'::regprocedure),
            'scene_0497', 'scene_0497_before'),
            $q$jsonb_build_object('alongside', public.fleet_alongside(v_fl), 'sell'$q$, $q$jsonb_build_object('alongside', false, 'sell'$q$),
            $q$to_jsonb(public.fleet_alongside((select f.id from public.fleets f where not exists (select 1 from public.ships s where s.fleet_id = f.id) limit 1)))$q$, $q$'false'::jsonb$q$),
            $q$'alongside', public.fleet_alongside(v_nf), 'ran', cmd.advance(v_nf),$q$, $q$'alongside', false, 'ran', cmd.advance(v_nf),$q$),
            $q$'refusal', public.wreck_order_refusal(v_nf, 'BUY')$q$, $q$'refusal', null::jsonb$q$);
  begin
    v_d0 := pg_temp.scene_0497_before(c_ua, false);
    raise exception using errcode = 'ZX497', message = 'PROBE_ROLLBACK_0497_BEFORE';
  exception when sqlstate 'ZX497' then null;
  end;
  -- THE REPORT, BEFORE: a wreck's SELL is "queued" by the dry run, taken with ok by the door, and never runs
  if v_d0 #>> '{prev,queued}' is distinct from 'true' or v_d0 #>> '{sell,ok}' is distinct from 'true' or v_d0 #>> '{sell,order,status}' is distinct from 'pending'
     or (v_d0->>'sold')::numeric <> 0 or (v_d0->>'coin')::numeric <> 0 or v_d0 #>> '{dock,error_code}' = 'E_NOT_DOCKED' or v_d0->>'state' is distinct from 'wrecked' then
    raise exception '0497 self-assert FAIL: before the hunks a wreck''s SELL was not the silent queue the lead reported: %', left(v_d0::text, 1500);
  end if;

  -- ── 3. THE KNOB ──
  insert into public.world_config (key, value, description) values
    ('wreck_sells_enabled', 'false'::jsonb,
     '0497: THE SWITCH (the owner''s). true: a player''s fleet that is UNABLE_TO_SAIL and lies in a port may SELL, STORE and TAKE her cargo there (public.fleet_alongside), her queue''s SELL / STORE / TAKE orders run past her SAILs (cmd.advance), and an order she cannot run is refused instead of queued for ever (public.wreck_order_refusal). false: as before 0497, to the letter.');

  -- ── 4. THE RULES ──
  execute $f$
create function public.wreck_sells_on()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0497: THE SWITCH, read once: world_config wreck_sells_enabled.
  select public.wc('wreck_sells_enabled') = 'true'::jsonb
$body$
  $f$;

  execute $f$
create function public.wreck_may(p_verb text)
returns boolean
language sql
immutable
set search_path = public, pg_temp
as $body$
  -- 0497: THE ORDERS A WRECK ALONGSIDE MAY RUN: her cargo sold, landed into the warehouse, or taken up from it. No buying, no
  -- sailing, no hiring, no repair (the yard asks DOCKED; a tow brings her to one). Read by cmd.advance and public.wreck_order_refusal.
  select p_verb in ('SELL', 'STORE', 'TAKE')
$body$
  $f$;

  execute $f$
create function public.fleet_alongside(p_fleet uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0497: DOES SHE LIE WHERE A CARGO IS LANDED? THE ONE READING cmd.do_sell, cmd.do_store and cmd.do_take ask (each asked
  -- `status <> 'DOCKED'` itself). DOCKED: yes, as before. Lit (public.wreck_sells_on): a player's fleet that is UNABLE_TO_SAIL, lies
  -- IN A PORT and has a ship is alongside too: her hulls are wrecked, her cargo is not. Not alongside: a wreck at sea (no port), an
  -- empty fleet (0321: UNABLE_TO_SAIL with no ship has nothing to land), a merchant's fleet (public.npc_tend_route tows her). Her
  -- STATE is still the one rule's (public.fleet_state_of: wrecked); this is only whether a quay is under her. Writes nothing.
  select coalesce((
    select f.status = 'DOCKED'
           or (f.status = 'UNABLE_TO_SAIL' and f.port_id is not null and public.wreck_sells_on()
               and exists (select 1 from public.ships s where s.fleet_id = f.id)
               and not exists (select 1 from public.players p where p.id = f.player_id and p.is_npc))
      from public.fleets f where f.id = p_fleet), false)
$body$
  $f$;

  execute $f$
create function public.wreck_order_refusal(p_fleet uuid, p_verb text)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0497: THE TRUTH FOR A WRECK'S ORDER (lit; dark null). A player's UNABLE_TO_SAIL fleet runs nothing but SELL / STORE / TAKE where
  -- she lies in a port (public.fleet_alongside, public.wreck_may), and a tow cancels whatever waits in her queue (public.tow_for).
  -- So any other order of hers would wait for ever: it is refused here, in plain words, instead of being queued with an ok. Null
  -- for every other fleet (a fleet at sea still queues her orders, F.2) and for a merchant. Asked by cmd.preview and cmd.issue.
  select case
           when not public.wreck_sells_on() or f.status <> 'UNABLE_TO_SAIL' then null
           when exists (select 1 from public.players p where p.id = f.player_id and p.is_npc) then null
           when public.wreck_may(p_verb) and public.fleet_alongside(f.id) then null
           when f.port_id is null or not exists (select 1 from public.ships s where s.fleet_id = f.id) then
             cmd.refusal('E_NOT_DOCKED', format('%s cannot sail and lies in no port: nothing can be done aboard her', f.name))
           else
             cmd.refusal('E_NOT_DOCKED', format('%s is wrecked: she can sell or store her cargo here, and nothing else until a tow and a repair', f.name))
         end
    from public.fleets f where f.id = p_fleet
$body$
  $f$;

  -- grants: all server only (service_role too: the platform grants execute on a new function by default, 0459's first push)
  foreach v_def in array c_new loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v_def::regprocedure);
  end loop;

  -- ── 5. THE HUNKS (each OLD text once in the live body; each reverses) ──
  create temp table hunks_0497 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0497 values
  ('cmd.do_sell(uuid,jsonb)', 1,
$h$  if f.status <> 'DOCKED' then
    raise exception 'E_NOT_DOCKED: % is % and must be docked to trade', f.name, f.status using errcode = 'P0001';$h$,
$h$  if not public.fleet_alongside(p_fleet) then   -- 0497: DOCKED, or (lit) a wreck that lies in a port: her cargo can be sold
    raise exception 'E_NOT_DOCKED: % is % and must be docked to trade', f.name, f.status using errcode = 'P0001';$h$),
  ('cmd.do_store(uuid,jsonb)', 1,
$h$  if f.status <> 'DOCKED' then
    raise exception 'E_NOT_DOCKED: % is % and a cargo is landed alongside', f.name, f.status using errcode = 'P0001';$h$,
$h$  if not public.fleet_alongside(p_fleet) then   -- 0497: DOCKED, or (lit) a wreck that lies in a port
    raise exception 'E_NOT_DOCKED: % is % and a cargo is landed alongside', f.name, f.status using errcode = 'P0001';$h$),
  ('cmd.do_take(uuid,jsonb)', 1,
$h$  if f.status <> 'DOCKED' then
    raise exception 'E_NOT_DOCKED: % is % and a cargo is taken up alongside', f.name, f.status using errcode = 'P0001';$h$,
$h$  if not public.fleet_alongside(p_fleet) then   -- 0497: DOCKED, or (lit) a wreck that lies in a port
    raise exception 'E_NOT_DOCKED: % is % and a cargo is taken up alongside', f.name, f.status using errcode = 'P0001';$h$),
  ('cmd.advance(uuid,timestamp with time zone)', 1,
$h$    exit when f.status not in ('DOCKED', 'ANCHORED');   -- SAILING / ADRIFT / UNABLE_TO_SAIL: nothing can execute$h$,
$h$    -- 0497: A WRECK ALONGSIDE RUNS HER CARGO ORDERS (public.fleet_alongside: lit, a player's UNABLE_TO_SAIL fleet lying in a port);
    -- every other fleet as before
    exit when f.status not in ('DOCKED', 'ANCHORED')   -- SAILING / ADRIFT / UNABLE_TO_SAIL: nothing can execute
              and not (f.status = 'UNABLE_TO_SAIL' and public.fleet_alongside(p_fleet));$h$),
  ('cmd.advance(uuid,timestamp with time zone)', 2,
$h$     where fleet_id = p_fleet and status = 'pending' order by seq limit 1;$h$,
$h$     where fleet_id = p_fleet and status = 'pending'
       -- 0497: a wreck steps over what she cannot run (her SAILs wait, untouched; a tow clears them) and runs SELL / STORE / TAKE
       and (f.status <> 'UNABLE_TO_SAIL' or public.wreck_may(verb))
     order by seq limit 1;$h$),
  ('cmd.advance(uuid,timestamp with time zone)', 3,
$h$    if o.id is null then
      exit when v_refilled;$h$,
$h$    if o.id is null then
      exit when f.status = 'UNABLE_TO_SAIL';   -- 0497: no standing route refills a wreck's queue
      exit when v_refilled;$h$),
  ('cmd.preview(uuid,text,jsonb)', 1,
$h$  if (select status from public.fleets where id = (v_parsed->>'fleet_id')::uuid) not in ('DOCKED', 'ANCHORED') then$h$,
$h$  -- 0497: a wreck's order that cannot run is refused, not "queued" (public.wreck_order_refusal); her SELL / STORE / TAKE where she
  -- lies in a port is dry-run for real, below
  v_ref := public.wreck_order_refusal((v_parsed->>'fleet_id')::uuid, v_parsed->>'verb');
  if v_ref is not null then
    return jsonb_build_object('ok', false, 'parsed', v_parsed, 'error_code', v_ref->>'code', 'error_message', v_ref->>'sentence',
                              'fixes', cmd.fixes(v_ref->>'code', (v_parsed->>'fleet_id')::uuid));
  end if;
  if (select status from public.fleets where id = (v_parsed->>'fleet_id')::uuid) not in ('DOCKED', 'ANCHORED')
     and not public.fleet_alongside((v_parsed->>'fleet_id')::uuid) then$h$),
  ('cmd.issue(uuid,text,integer,jsonb)', 1,
$h$  v_res := cmd.enqueue(v_player, v_parsed, p_text, p_path, null);$h$,
$h$  -- 0497: a wreck's order that cannot run is refused here, never queued to wait for ever (public.wreck_order_refusal)
  v_ref := public.wreck_order_refusal((v_parsed->>'fleet_id')::uuid, v_parsed->>'verb');
  if v_ref is not null then
    return jsonb_build_object('ok', false, 'error_code', v_ref->>'code', 'error_message', v_ref->>'sentence',
      'fixes', cmd.fixes(v_ref->>'code', p_fleet), 'queue', cmd.queue(p_fleet));
  end if;
  v_res := cmd.enqueue(v_player, v_parsed, p_text, p_path, null);$h$);

  for v_h in select h.fn from hunks_0497 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0497 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0497 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0497 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0497 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0497 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 6. SELF-ASSERT: the catalog, the grants, the knob ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked || c_new) u(q)))) <> v_fn_before then
    raise exception '0497 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0497 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if exists (select 1 from unnest(c_new) u(q)
              where has_function_privilege('authenticated', u.q::regprocedure, 'execute') or has_function_privilege('anon', u.q::regprocedure, 'execute')
                 or has_function_privilege('service_role', u.q::regprocedure, 'execute'))
     or (select count(*) from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_new) u(q))) and p.provolatile in ('s', 'i')) <> 4
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0497 self-assert FAIL: a new function is reachable by a client or service_role, or writes';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
        from public.world_config c where c.key <> 'wreck_sells_enabled') <> v_cfg_before
     or public.wc('wreck_sells_enabled') is distinct from 'false'::jsonb or public.wreck_sells_on() then
    raise exception '0497 self-assert FAIL: a knob other than wreck_sells_enabled moved, or the switch is not false';
  end if;

  -- ── 7. THE PROBES ──
  -- (a) DARK: the same scene, the same answers, to the letter (the twin left the new readers out: they answer false and null dark)
  begin
    v_d1 := pg_temp.scene_0497(c_ua, false);
    raise exception using errcode = 'ZX497', message = 'PROBE_ROLLBACK_0497_DARK';
  exception when sqlstate 'ZX497' then null;
  end;
  if (v_d1 - 'dock_ms') is distinct from (v_d0 - 'dock_ms') then
    raise exception '0497 self-assert FAIL: dark, something answers differently: before % / after %', left(v_d0::text, 900), left(v_d1::text, 900);
  end if;
  -- (b) LIT
  begin
    v_d2 := pg_temp.scene_0497(c_ua, true);
    raise exception using errcode = 'ZX497', message = 'PROBE_ROLLBACK_0497_LIT';
  exception when sqlstate 'ZX497' then null;
  end;
  -- a docked fleet's dry run is what it was
  if v_d2->'dock' is distinct from v_d0->'dock' or v_d2->>'good' is distinct from v_d0->>'good' then
    raise exception '0497 self-assert FAIL: lit, a docked fleet''s dry run moved: before % / after %', v_d0->'dock', v_d2->'dock';
  end if;
  -- the wreck's SELL: HER DRY RUN IS A DOCKED FLEET'S (the same quote, or the same refusal of the quay: never "queued"); then it runs
  -- past her pending SAIL, which is neither run nor cancelled, and she is still wrecked
  if v_d2 #> '{prev,queued}' is not null or v_d2 #>> '{prev,ok}' is distinct from v_d2 #>> '{dock,ok}'
     or v_d2 #>> '{prev,error_code}' is distinct from v_d2 #>> '{dock,error_code}' or v_d2 #>> '{prev,error_code}' = 'E_NOT_DOCKED'
     or v_d2 #> '{prev,estimate,qty}' is distinct from v_d2 #> '{dock,estimate,qty}'
     or v_d2->>'state' is distinct from 'wrecked' or v_d2->>'status' is distinct from 'UNABLE_TO_SAIL' then
    raise exception '0497 self-assert FAIL: lit, the wreck''s dry run is not a docked fleet''s: %', left(v_d2::text, 1500);
  end if;
  if (v_d2 #>> '{dock,ok}')::boolean then
    -- her quay buys it: cargo out, coin in
    if v_d2 #>> '{sell,ok}' is distinct from 'true' or v_d2 #>> '{sell,order,status}' is distinct from 'done'
       or (v_d2->>'sold')::numeric <> 5 or (v_d2->>'coin')::numeric <= 0 or v_d2->'orders' is distinct from '["SAIL:pending", "SELL:done"]'::jsonb then
      raise exception '0497 self-assert FAIL: lit, the wreck''s SELL did not run past her pending SAIL: %', left(v_d2::text, 1500);
    end if;
  else
    -- her quay buys nothing today: the order RAN and was refused by the quay's own rule (the docked fleet's code), not left waiting
    if v_d2 #>> '{sell,ok}' is distinct from 'false' or v_d2 #>> '{sell,order,status}' is distinct from 'failed'
       or v_d2 #>> '{sell,code}' is distinct from v_d2 #>> '{dock,error_code}'
       or (v_d2->>'sold')::numeric <> 0 or v_d2->'orders' is distinct from '["SAIL:pending", "SELL:failed"]'::jsonb then
      raise exception '0497 self-assert FAIL: lit, where her quay buys nothing the wreck''s SELL was not refused as a docked fleet''s is: %', left(v_d2::text, 1500);
    end if;
  end if;
  -- STORE and TAKE run, or are refused by their own door for a reason that is not her state
  if v_d2 #>> '{store,status}' = 'pending' or v_d2 #>> '{take,status}' = 'pending'
     or v_d2 #>> '{store,code}' = 'E_NOT_DOCKED' or v_d2 #>> '{take,code}' = 'E_NOT_DOCKED' then
    raise exception '0497 self-assert FAIL: lit, the wreck''s STORE or TAKE did not run: % / %', v_d2->'store', v_d2->'take';
  end if;
  -- BUY and SAIL: refused in plain words, nothing queued; the dry run says the same
  if v_d2 #>> '{buy,ok}' is distinct from 'false' or v_d2 #>> '{buy,code}' is distinct from 'E_NOT_DOCKED' or v_d2 #>> '{buy,msg}' not like '% is wrecked: she can sell or store her cargo here%'
     or (v_d2 #>> '{buy,queued}')::int <> 0 or v_d2 #>> '{buy,preview_ok}' is distinct from 'false' or v_d2 #>> '{buy,preview_code}' is distinct from 'E_NOT_DOCKED'
     or v_d2 #>> '{sail,ok}' is distinct from 'false' or v_d2 #>> '{sail,code}' is distinct from 'E_NOT_DOCKED' then
    raise exception '0497 self-assert FAIL: lit, a wreck''s BUY or SAIL was not refused outright: % / %', v_d2->'buy', v_d2->'sail';
  end if;
  -- a wreck at sea, an empty fleet, a merchant's wreck: not alongside; the merchant's waiting SELL is not run and she is told nothing new
  if v_d2 #>> '{sea,alongside}' is distinct from 'false' or v_d2 #>> '{sea,sell,ok}' is distinct from 'false' or v_d2 #>> '{sea,sell,error_code}' is distinct from 'E_NOT_DOCKED'
     or v_d2->>'empty' is distinct from 'false'
     or (v_d2->'npc' <> 'null'::jsonb and (v_d2 #>> '{npc,alongside}' is distinct from 'false' or v_d2 #>> '{npc,ran}' is distinct from '0' or v_d2 #> '{npc,refusal}' <> 'null'::jsonb)) then
    raise exception '0497 self-assert FAIL: lit, a wreck at sea, an empty fleet or a merchant''s wreck is treated as alongside: % / % / %', v_d2->'sea', v_d2->'empty', v_d2->'npc';
  end if;
  if exists (select 1 from public.players p where p.company_name like '% 0497' or p.auth_uid = c_ua)
     or public.wc('wreck_sells_enabled') is distinct from 'false'::jsonb or public.current_player_id() is not null then
    raise exception '0497 self-assert FAIL: the probe left something behind';
  end if;
  drop function pg_temp.scene_0497(uuid, boolean);
  drop function pg_temp.scene_0497_before(uuid, boolean);

  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0497 self-assert FAIL: the file took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0497 self-assert ok: A WRECK CAN SELL (dark). % hunks once and reversing; no other function moved; the hunked bodies'' grants and volatility unmoved; one knob added (false), no other moved; four new functions server only. Probes (rolled back, good %): before and dark, a wreck''s SELL is dry-run "queued", taken ok and left % (sold %); lit, dry run % qty %, the order % %, sold % for % coin past her pending SAIL (%), STORE % TAKE %, BUY % "%" (queued %), SAIL %, at sea %, empty fleet alongside %, a merchant''s wreck %. A docked dry run: identical; % ms before, % dark, % lit (mean of 20). % ms.',
    (select count(*) from hunks_0497), v_d2->>'good', v_d0 #>> '{sell,order,status}', v_d0->>'sold',
    coalesce(v_d2 #>> '{prev,error_code}', 'ok'), coalesce(v_d2 #>> '{prev,estimate,qty}', '-'), v_d2 #>> '{sell,order,status}', coalesce(v_d2 #>> '{sell,code}', ''), v_d2->>'sold', v_d2->>'coin', v_d2->'orders', v_d2 #>> '{store,status}', v_d2 #>> '{take,status}',
    v_d2 #>> '{buy,code}', v_d2 #>> '{buy,msg}', v_d2 #>> '{buy,queued}', v_d2 #>> '{sail,code}', v_d2 #>> '{sea,sell,error_code}', v_d2->>'empty', v_d2->'npc',
    v_d0->>'dock_ms', v_d1->>'dock_ms', v_d2->>'dock_ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
