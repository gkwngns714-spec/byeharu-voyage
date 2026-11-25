-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none (dark: nothing changes for a player until the owner lights cargo_at_cost_enabled; no coin moves either way)
-- 0500 - CARGO AT COST  (dark: the owner's switch cargo_at_cost_enabled, false. Lit, HQ's per hour no longer reads goods she
--        bought and still holds as a loss; from deploy on, a day that loses cargo also records what that cargo cost)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE LEAD, 2026-11-25: HQ's per hour counts a cargo BUY as a running loss until it is sold (a test company reads Trading -38,869
--   while its cargo is at sea): the same kind of complaint as the owner's "why investing causes les money? wtf?" (0493).
--   Dev log docs/dev-log/2026-11-25-cargo-at-cost.md.
--
-- WHAT SAYS THE OPPOSITE, NAMED: public.company_rate_for (0493): the `trade` line is the ledger's BUY and SELL rows summed, so the
--   coin of a purchase is a loss the hour it is made and the sale's coin a gain hours later.
--
-- WHAT WAS AND WAS NOT RECORDED (read on the chain's bodies at 0499):
--   A SALE'S COST IS RECORDED: cmd.do_sell writes the SOLD event with `cost` (public.fleet_cargo_basis x units; 0081, 0474, 0490),
--     in the transaction that writes its SELL ledger row. So "sales less the basis of what was sold" is exact, also for goods
--     bought before the window.
--   A LOSS'S COST WAS NOT: voyage.lose_hold and voyage.raid_takes take goods through public.fleet_unload, which drops a good's
--     cargo_basis with its last unit; the day's payload kept `cargo_lost` {good: units} and no cost. THIS FILE RECORDS IT, from its
--     deploy on. FOR LOSSES BEFORE THE DEPLOY THERE IS NO RECORD, and none is estimated: the payload says from when it is exact.
--
-- WHAT:
--   THE RECORD (not behind the switch; additive; from deploy on). The three writers of a day that loses cargo add one key to the
--     day's payload (public.voyage_events), `cargo_lost_cost` = her cargo at cost before the loss less after it
--     (public.fleet_stock_at_cost, 0129: the one valuation of the basis fleet_unload drops; the very expression the day's news
--     tells, 0362):
--       voyage.settle       (3 hunks) the PIRATES arm: the figure is read before voyage.raid_takes (its own variable beside the news'
--                                     v_cost0 of 0362, so the record does not lean on the news; proof 64 rebuilds a body without it).
--       voyage.forced_home  (3 hunks) ran dry, the hold lost: the figure is read before voyage.lose_hold; the key is added to the
--                                     day's payload it returns (the FORCED_HOME feed event is as it was).
--       voyage.navy_meets   (3 hunks) a navy's plunder: read before voyage.raid_takes; the key is added.
--     voyage.lose_hold, voyage.raid_takes and public.fleet_unload ARE NOT TOUCHED: the loss itself (goods, hull, crew, coin) is the
--     same statements. No new row, no new table, no ledger row (no coin moves). voyage.npc_wreck (a merchant's wreck) is not touched.
--   THE SWITCH public.cargo_at_cost_on(): world_config cargo_at_cost_enabled (false). cargo_at_cost_since: this file's deploy time.
--   THE READ public.cargo_rate_for(player) (STABLE, server only; one row). Dark: lit false, zeros. Lit, her last 24 hours:
--       bought     her BUY ledger rows (the coin she paid for cargo)
--       cost_sold  the `cost` of her SOLD events (a sale of goods with no recorded basis, as land goods or a gift, counts 0: she
--                  paid nothing for them)
--       lost       the `cargo_lost_cost` of her voyages' days (resolved in the window), and how many such days
--       since      cargo_at_cost_since
--   public.company_rate_for (4 hunks; 0493's authority). Dark: its answer is 0493's to the letter (asserted against the old body).
--     Lit:  trade      = her ledger's trade line + bought - cost_sold  (her sales less the recorded cost of what she sold)
--           cargo_lost = a running line, -lost (no ledger row: no coin moved; `count` is the days)
--           cargo      = {at_cost: greatest(0, bought - cost_sold - lost), net_24h: -(bought - cost_sold - lost), bought, cost_sold,
--                         lost, exact_since, exact}
--     THE SUMS, exact: the running lines sum to net_24h; all_24h is still her ledger's sum; and
--           net_24h + one_time_24h + cargo.net_24h = all_24h.
--     cargo.net_24h is the reconciling figure: the coin that went into goods in the window and is neither sold nor lost (negative),
--     or, positive, the cost of goods bought BEFORE the window that she sold or lost in it (they count at their basis, and at_cost
--     is then 0). `exact` is false while the window reaches back before exact_since: a loss before the deploy is not in `lost`, so
--     its goods stay in at_cost until their BUY leaves the window. The lines (0493's sum of ALL lines = all_24h) now sum to
--     all_24h - cargo.net_24h.
-- NOT COUNTED, SAID PLAINLY: goods a forge or a make order consumes, and goods a courier contract carries, leave no cost record:
--   their coin stays in cargo.at_cost until the BUY leaves the window. A day's loss is windowed by the day's own instant
--   (voyage_events.resolved_at), a sale by its own (events.created_at = its ledger row's).
-- NOT CHANGED: any command, any coin, the ledger, any table or index, voyage.lose_hold, voyage.raid_takes, public.fleet_unload,
--   public.company_rate_line, world.hq_board's wiring (its `rate` is this authority's object, with `cargo` when lit).
-- ROWS: two world_config rows. No table, no index, no cron, no beat step, no new row kind: a day that loses cargo is the row it
--   was, about 40 bytes longer. 0 new rows a minute.
-- budget: no table, no cron job, no autovacuum or fillfactor change.
-- COST. The write: two public.fleet_stock_at_cost reads (her ships' cargo, a few rows) on a day that loses cargo, and none on any
--   other day. Measured in the self-assert (a forced home, old body and new, the same voyage) and in proof 203 (0.015 ms a read). The read, lit: two more index range scans of her last
--   24 hours (ledger_player_created, events_player_created) and her voyages' days (voyages by fleet, voyage_events by key).
-- LOCKS: CREATE FUNCTION x2; CREATE OR REPLACE x4 by hunks (voyage.settle, voyage.forced_home, voyage.navy_meets,
--   public.company_rate_for). TIME: a second. BUDGET: statement_timeout 60 s, lock_timeout 5 s; fails above 30 s.
-- ROLLBACK (forward, owner only): QUICK, cargo_at_cost_enabled false (the rate is 0493's again; the recorded key is inert). Full: a
--   migration reversing the thirteen hunks (OLD texts below verbatim), dropping the two functions, deleting the two knobs.
-- SELF-ASSERT: each hunk once and reversing; no other function moved; the hunked bodies' grants, volatility, definer, search path
--   and owner unmoved; no other knob moved; the two new functions STABLE and server only (service_role too). THE SCENE (rolled
--   back; ITS OWN COMPANY, ITS OWN VOYAGE AND PLANTED ROWS ONLY: no market price, no real company, no real job is read or written):
--   a forced home run on the NEW body and on the OLD body, on the same voyage: the hold, the hulls, the crew, her purse, her ledger,
--   her events, the voyage and the cities' purses are identical, the day's payload is identical but for the one new key, and the
--   key is her cargo at cost; both calls are timed. The rate: dark it equals the old body's answer; lit, every figure as written,
--   the sums above, goods bought before the window sold at their basis, exact false then true.
-- VERSION: 0500 = 0499 + 1 (0499, branch fit-to-sail, deploys first).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_hunked constant text[] := array['voyage.settle(uuid,timestamp with time zone)', 'voyage.forced_home(uuid,integer,uuid)',
                                    'voyage.navy_meets(uuid,integer,uuid,uuid,timestamp with time zone)', 'public.company_rate_for(uuid)'];
  c_new    constant text[] := array['public.cargo_at_cost_on()', 'public.cargo_rate_for(uuid)'];
  c_keys   constant text[] := array['cargo_at_cost_enabled', 'cargo_at_cost_since'];
  c_uid    constant uuid := '00000000-0500-4000-8000-000000000001';
  -- the scene's digest: everything a forced home can move for this fleet and this company, and the cities' purses
  c_digest constant text := $q$
    select md5(jsonb_build_object(
      'ships',  (select jsonb_agg(to_jsonb(s) order by s.id) from public.ships s where s.fleet_id = $1),
      'fleet',  (select to_jsonb(f) from public.fleets f where f.id = $1),
      'voyage', (select jsonb_agg(to_jsonb(v) order by v.id) from public.voyages v where v.fleet_id = $1),
      'purse',  (select p.ducats from public.players p where p.id = $2),
      'ledger', (select jsonb_agg(jsonb_build_array(l.kind, l.ducats_delta, l.balance_after) order by l.kind, l.ducats_delta, l.balance_after)
                   from public.ledger l where l.player_id = $2),
      'events', (select jsonb_agg(jsonb_build_array(e.kind, e.payload) order by e.kind, e.payload::text) from public.events e where e.player_id = $2),
      'cities', (select sum(t.ducats) from public.port_treasury t))::text) $q$;
  v_t0        timestamptz := clock_timestamp();
  v_t         timestamptz;
  v_h         record;
  x           record;
  v_q         text;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_fn_before text;
  v_meta      text;
  v_cfg_before text;
  v_lived     boolean := false;
  v_inner     boolean;
  v_me        uuid;
  v_fl        uuid;
  v_lis       uuid;
  v_voy       uuid;
  v_good      text;
  v_new       jsonb;
  v_old       jsonb;
  v_dn        text;
  v_do        text;
  v_ms_new    numeric;
  v_ms_old    numeric;
  v_r         jsonb;
  v_r0        jsonb;
  v_note      text := '';
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.world_config where key = any (c_keys)) or to_regprocedure('public.cargo_rate_for(uuid)') is not null
     or to_regprocedure('public.cargo_at_cost_on()') is not null then
    raise exception '0500 refuses: it has been applied once';
  end if;
  if to_regprocedure('public.company_rate_for(uuid)') is null or to_regprocedure('public.fleet_stock_at_cost(uuid)') is null
     or to_regprocedure('voyage.lose_hold(uuid)') is null or to_regprocedure('voyage.raid_takes(uuid,integer,uuid,text)') is null
     or to_regprocedure('voyage.navy_meets(uuid,integer,uuid,uuid,timestamp with time zone)') is null then
    raise exception '0500 refuses: 0493, 0129, 0322, 0213 or 0334 is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0500 (fn text primary key, def text) on commit drop;
  insert into pre_0500 select u.q, replace(pg_get_functiondef(u.q::regprocedure), E'\r', '') from unnest(c_hunked) u(q);
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
    into v_cfg_before from public.world_config c;

  -- ── 2. THE KNOBS ──
  insert into public.world_config (key, value, description) values
    ('cargo_at_cost_enabled', 'false'::jsonb,
     '0500: THE SWITCH (the owner''s). true: HQ''s per hour (public.company_rate_for) reads her trade line as sales less the recorded cost of what she sold, lost cargo as a running loss at its recorded cost, and serves the cargo she bought and still holds apart (cargo.at_cost). false: the rate is 0493''s, every BUY a loss the hour it is made.'),
    ('cargo_at_cost_since', to_jsonb(now()),
     '0500: when this migration was deployed: from this instant a day that loses cargo records what the cargo cost (cargo_lost_cost). The rate says `exact` once its 24 hours lie after it. Not a knob to turn.');

  -- ── 3. THE RULES ──
  execute $f$
create function public.cargo_at_cost_on()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0500: THE SWITCH, read once: world_config cargo_at_cost_enabled (the owner's).
  select public.wc('cargo_at_cost_enabled') is not distinct from 'true'::jsonb
$body$
  $f$;

  execute $f$
create function public.cargo_rate_for(p_player uuid)
returns table (lit boolean, bought numeric, cost_sold numeric, lost numeric, losses bigint, since timestamptz)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0500: HER CARGO AT COST over the last 24 hours, from records alone (public.company_rate_for's `c`; server only). Dark: lit false
-- and zeros. Lit: what she paid for cargo (her BUY ledger rows), the recorded cost of what she sold (her SOLD events' `cost`, 0081),
-- and the recorded cost of what she lost at sea (her voyages' days' `cargo_lost_cost`, recorded since 0500's deploy: `since`).
-- No market price is read and nothing is valued a second way. Writes nothing.
begin
  if not public.cargo_at_cost_on() then
    return query select false, 0::numeric, 0::numeric, 0::numeric, 0::bigint, null::timestamptz;
    return;
  end if;
  return query
  select true,
         coalesce((select -sum(l.ducats_delta) from public.ledger l
                    where l.player_id = p_player and l.created_at > now() - interval '24 hours' and l.kind = 'BUY'), 0)::numeric,
         coalesce((select sum((e.payload->>'cost')::numeric) from public.events e
                    where e.player_id = p_player and e.created_at > now() - interval '24 hours' and e.kind = 'SOLD'
                      and jsonb_typeof(e.payload->'cost') = 'number'), 0)::numeric,
         coalesce(z.lost, 0)::numeric, coalesce(z.n, 0)::bigint,
         (public.wc('cargo_at_cost_since') #>> '{}')::timestamptz
    from (select sum((ve.payload->>'cargo_lost_cost')::numeric) as lost, count(*) as n
            from (-- her voyage under way (one a fleet), and those that ended in the last days (a day resolves no later than its voyage ends)
                  select v.id from public.voyages v
                   where v.status = 'SAILING' and v.fleet_id in (select fl.id from public.fleets fl where fl.player_id = p_player)
                  union all
                  select v.id from public.voyages v
                   where v.status <> 'SAILING' and v.eta > now() - interval '8 days'
                     and v.fleet_id in (select fl.id from public.fleets fl where fl.player_id = p_player)) vv
            join public.voyage_events ve on ve.voyage_id = vv.id
           where ve.resolved_at > now() - interval '24 hours'
             and jsonb_typeof(ve.payload->'cargo_lost_cost') = 'number' and (ve.payload->>'cargo_lost_cost')::numeric > 0) z;
end
$body$
  $f$;

  -- grants: both server only (service_role too: the platform grants execute on a new function by default, 0459's first push)
  foreach v_q in array c_new loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v_q::regprocedure);
  end loop;

  -- ── 4. THE HUNKS (each OLD text once in the live body; each reverses) ──
  create temp table hunks_0500 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0500 values
  ('voyage.settle(uuid,timestamp with time zone)', 1,
$h$  v_taken   jsonb;     -- 0213: what the raiders carried off (voyage.raid_takes)
$h$,
$h$  v_taken   jsonb;     -- 0213: what the raiders carried off (voyage.raid_takes)
  v_hold0   bigint;    -- 0500: her cargo at what it cost, read before the raiders take their share (the day's payload says what the taken units cost)
$h$),
  ('voyage.settle(uuid,timestamp with time zone)', 2,
$h$        v_cost0 := public.fleet_stock_at_cost(p_fleet);   -- 0362: before they take it (public.fleet_unload drops a good's cost with its last tun)
$h$,
$h$        v_hold0 := public.fleet_stock_at_cost(p_fleet);   -- 0500: before they take it (its own read: the day's record does not lean on the news')
        v_cost0 := public.fleet_stock_at_cost(p_fleet);   -- 0362: before they take it (public.fleet_unload drops a good's cost with its last tun)
$h$),
  ('voyage.settle(uuid,timestamp with time zone)', 3,
$h$                           else jsonb_build_object('cargo_lost', v_taken) end
$h$,
$h$                           -- 0500: and what those units cost her (her cargo at cost before less after: the figure the day's news tells, 0362)
                           else jsonb_build_object('cargo_lost', v_taken, 'cargo_lost_cost', v_hold0 - public.fleet_stock_at_cost(p_fleet)) end
$h$),
  ('voyage.forced_home(uuid,integer,uuid)', 1,
$h$  v_lost   jsonb;
$h$,
$h$  v_lost   jsonb;
  v_cost0  bigint;   -- 0500: her cargo at what it cost, read before the hold is lost (public.fleet_unload drops a good's cost with its last tun)
$h$),
  ('voyage.forced_home(uuid,integer,uuid)', 2,
$h$  v_lost := voyage.lose_hold(p_fleet);   -- 0322: the same loop, lifted
$h$,
$h$  v_cost0 := public.fleet_stock_at_cost(p_fleet);   -- 0500: before she loses it
  v_lost := voyage.lose_hold(p_fleet);   -- 0322: the same loop, lifted
$h$),
  ('voyage.forced_home(uuid,integer,uuid)', 3,
$h$                            'insurance', v_ins, 'repair', v_repair);
end$h$,
$h$                            'insurance', v_ins, 'repair', v_repair,
                            -- 0500: what the lost hold cost her (the day's payload alone; the feed's event is as it was)
                            'cargo_lost_cost', v_cost0 - public.fleet_stock_at_cost(p_fleet));
end$h$),
  ('voyage.navy_meets(uuid,integer,uuid,uuid,timestamp with time zone)', 1,
$h$  v_taken   jsonb;
$h$,
$h$  v_taken   jsonb;
  v_cost0   bigint;   -- 0500: her cargo at what it cost, read before the navy takes its share
$h$),
  ('voyage.navy_meets(uuid,integer,uuid,uuid,timestamp with time zone)', 2,
$h$    v_taken := voyage.raid_takes(p_voyage, p_day, p_fleet, 'PLUNDERED');
$h$,
$h$    v_cost0 := public.fleet_stock_at_cost(p_fleet);   -- 0500: before they take it
    v_taken := voyage.raid_takes(p_voyage, p_day, p_fleet, 'PLUNDERED');
$h$),
  ('voyage.navy_meets(uuid,integer,uuid,uuid,timestamp with time zone)', 3,
$h$         || case when coalesce(v_taken, '{}'::jsonb) = '{}'::jsonb then '{}'::jsonb else jsonb_build_object('cargo_lost', v_taken) end;
$h$,
$h$         -- 0500: and what those units cost her
         || case when coalesce(v_taken, '{}'::jsonb) = '{}'::jsonb then '{}'::jsonb
                 else jsonb_build_object('cargo_lost', v_taken, 'cargo_lost_cost', v_cost0 - public.fleet_stock_at_cost(p_fleet)) end;
$h$),
  ('public.company_rate_for(uuid)', 1,
$h$  with g as materialized (
$h$,
$h$  with g0 as materialized (   -- 0500: her ledger's lines as 0493 read them (g, below, is these with her cargo read at cost, lit)
$h$),
  ('public.company_rate_for(uuid)', 2,
$h$     group by k.line, k.one_time
  ), s as (
$h$,
$h$     group by k.line, k.one_time
  ), c as materialized (
    -- 0500: her cargo at cost (public.cargo_rate_for; one row). Dark: lit false and zeros, so g is g0 to the unit.
    select x.lit, x.bought, x.cost_sold, x.lost, x.losses, x.since from public.cargo_rate_for(p_player) x
  ), g as materialized (
    -- the trade line is her sales less the RECORDED cost of what she sold (not less everything she bought): + bought - cost_sold
    select g0.line, g0.one_time, g0.total + case when g0.line = 'trade' then c.bought - c.cost_sold else 0 end as total, g0.n
      from g0 cross join c
    union all
    -- cargo she lost at sea, at its recorded cost: a running loss with no ledger row (no coin moved)
    select 'cargo_lost', false, -c.lost, c.losses from c where c.lit and c.lost > 0
  ), s as (
$h$),
  ('public.company_rate_for(uuid)', 3,
$h$           coalesce(sum(g.total), 0) as every
      from g
$h$,
$h$           (select coalesce(sum(g0.total), 0) from g0) as every   -- 0500: all_24h stays her ledger's sum
      from g
$h$),
  ('public.company_rate_for(uuid)', 4,
$h$                                from g), '[]'::jsonb))
    from s
$h$,
$h$                                from g), '[]'::jsonb))
         -- 0500 (lit only; dark the object is 0493's to the letter): her cargo at cost. bought - cost_sold - lost is the coin she put
         -- into goods in the window that is neither sold nor lost: at_cost is that figure floored at 0, net_24h the same figure as the
         -- ledger signs it (coin out is negative), so net_24h + one_time_24h + cargo.net_24h = all_24h exactly. Losses are recorded
         -- from exact_since on (0500's deploy); exact says the whole window is after it.
         || coalesce((select jsonb_build_object('cargo', jsonb_build_object(
                               'at_cost', greatest(0, c.bought - c.cost_sold - c.lost),
                               'net_24h', -(c.bought - c.cost_sold - c.lost),
                               'bought', c.bought, 'cost_sold', c.cost_sold, 'lost', c.lost,
                               'exact_since', c.since, 'exact', coalesce(c.since <= now() - interval '24 hours', false)))
                        from c where c.lit), '{}'::jsonb)
    from s
$h$);

  for v_h in select h.fn from hunks_0500 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0500 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0500 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0500 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0500 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0500 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;
  if (select count(distinct h.fn) from hunks_0500 h) <> 4 or (select count(*) from hunks_0500) <> 13
     or exists (select 1 from hunks_0500 h where h.fn <> all (c_hunked)) then
    raise exception '0500 self-assert FAIL: the hunks are not thirteen over the four bodies';
  end if;

  -- ── 5. SELF-ASSERT: the catalog, the knobs, the grants ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_new) u(q)))) <> v_fn_before then
    raise exception '0500 self-assert FAIL: another function moved (voyage.lose_hold, voyage.raid_takes and public.fleet_unload among them)';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0500 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key <> all (c_keys)) <> v_cfg_before
     or public.wc('cargo_at_cost_enabled') is distinct from 'false'::jsonb or public.cargo_at_cost_on()
     or (public.wc('cargo_at_cost_since') #>> '{}')::timestamptz is distinct from now() then
    raise exception '0500 self-assert FAIL: another knob moved, the switch is not false, or the deploy time is not this transaction''s';
  end if;
  if exists (select 1 from unnest(c_new) u(q)
              where has_function_privilege('authenticated', u.q::regprocedure, 'execute') or has_function_privilege('anon', u.q::regprocedure, 'execute')
                 or has_function_privilege('service_role', u.q::regprocedure, 'execute'))
     or (select count(*) from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_new) u(q))) and p.provolatile = 's') <> 2
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0500 self-assert FAIL: a new function is reachable by a client or service_role, or is not STABLE';
  end if;

  -- ── 6. THE SCENE, rolled back by a raised sentinel: its own company, its own voyage, planted rows; no market, no real company ──
  begin
    select p.id into v_lis from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR';
    v_me := public.new_house(c_uid, 'Casa da Carga 0500', 'PRT');
    select f.id into v_fl from public.fleets f where f.player_id = v_me limit 1;
    select g.code into v_good from public.goods g order by g.code limit 1;
    -- forty units aboard at 50 each (written straight, as 0490's probe writes them): her cargo at cost is 2,000
    update public.ships s set cargo = jsonb_build_object(v_good, 40), cargo_basis = jsonb_build_object(v_good, 50),
                              durability = (select b.durability from public.ship_base(s.id) b), crew = 20, water_t = 100000, food_t = 100000
     where s.fleet_id = v_fl;
    if public.fleet_stock_at_cost(v_fl) <> 2000 then
      raise exception '0500 self-assert FAIL: the scene''s cargo is not 2,000 at cost: %', public.fleet_stock_at_cost(v_fl);
    end if;
    -- her own three-day passage west of Lisbon and back (proof 66's shape), begun now
    v_voy := voyage.depart(v_fl, (select jsonb_agg(jsonb_build_object('a', jsonb_build_array(38.5, -9.6 - (d - 1)), 'b', jsonb_build_array(38.5, -9.6 - d),
                                                                       'nm', voyage.fleet_speed(v_fl) * 24,
                                                                       'sea_id', (select p.sea_id from public.ports p where p.id = v_lis)) order by d)
                                    from generate_series(1, 3) d), v_lis, v_lis, now());

    -- (a) THE RATE. Planted: she bought for 10,000 two hours ago, sold part for 9,000 (its recorded cost 6,000), paid wages 300,
    --     and a day of her voyage lost cargo that cost 1,500.
    insert into public.ledger (player_id, kind, ducats_delta, balance_after, created_at) values
      (v_me, 'BUY',  -10000, 1, now() - interval '2 hours'),
      (v_me, 'SELL',   9000, 1, now() - interval '1 hour'),
      (v_me, 'WAGES',  -300, 1, now() - interval '1 hour');
    insert into public.events (player_id, kind, payload, created_at) values
      (v_me, 'SOLD', jsonb_build_object('qty', 60, 'total', 9000, 'basis', 100, 'cost', 6000, 'profit', 3000), now() - interval '1 hour');
    insert into public.voyage_events (voyage_id, day_index, kind, payload, resolved_at)
    values (v_voy, 99, 'PIRATES', jsonb_build_object('outcome', 'PLUNDERED', 'cargo_lost', jsonb_build_object(v_good, 15), 'cargo_lost_cost', 1500),
            now() - interval '30 minutes');
    -- dark: the answer is the OLD body's, to the letter (the old body is put back for one call inside this rolled-back scene)
    v_r := public.company_rate_for(v_me);
    v_def := replace(pg_get_functiondef('public.company_rate_for(uuid)'::regprocedure), E'\r', '');
    execute (select p.def from pre_0500 p where p.fn = 'public.company_rate_for(uuid)');
    v_r0 := public.company_rate_for(v_me);
    execute v_def;
    if v_r is distinct from v_r0 or v_r ? 'cargo' or (v_r->>'net_24h')::numeric <> -1300 or (v_r->>'all_24h')::numeric <> -1300
       or (select (e->>'total_24h')::numeric from jsonb_array_elements(v_r->'lines') e where e->>'line' = 'trade') <> -1000 then
      raise exception '0500 self-assert FAIL: dark, the rate is not 0493''s: % / old body %', v_r, v_r0;
    end if;
    -- lit: trade = -1,000 + 10,000 - 6,000 = +3,000; lost cargo -1,500; wages -300; net 1,200; cargo 2,500 held at cost
    update public.world_config set value = 'true'::jsonb where key = 'cargo_at_cost_enabled';
    v_r := public.company_rate_for(v_me);
    if (v_r->>'net_24h')::numeric <> 1200 or (v_r->>'per_hour')::numeric <> 50 or (v_r->>'all_24h')::numeric <> -1300
       or (v_r->>'one_time_24h')::numeric <> 0
       or (select jsonb_agg(jsonb_build_array(e->>'line', (e->>'total_24h')::numeric, (e->>'count')::int) order by k)
             from jsonb_array_elements(v_r->'lines') with ordinality z(e, k))
            is distinct from jsonb_build_array(jsonb_build_array('cargo_lost', -1500, 1), jsonb_build_array('wages', -300, 1), jsonb_build_array('trade', 3000, 2))
       or (v_r->'cargo') - 'exact_since' is distinct from jsonb_build_object('at_cost', 2500, 'net_24h', -2500, 'bought', 10000, 'cost_sold', 6000, 'lost', 1500, 'exact', false)
       or (v_r #>> '{cargo,exact_since}')::timestamptz is distinct from now()
       or (select sum((e->>'total_24h')::numeric) from jsonb_array_elements(v_r->'lines') e where not (e->>'one_time')::boolean) <> (v_r->>'net_24h')::numeric
       or (v_r->>'net_24h')::numeric + (v_r->>'one_time_24h')::numeric + (v_r #>> '{cargo,net_24h}')::numeric <> (v_r->>'all_24h')::numeric
       or v_r->'top' is distinct from '["trade"]'::jsonb then
      raise exception '0500 self-assert FAIL: lit, the rate is not as written: %', v_r;
    end if;
    -- goods bought BEFORE the window, sold in it, count at their basis: a sale of 5,000 whose goods cost 4,000 thirty hours ago
    insert into public.ledger (player_id, kind, ducats_delta, balance_after, created_at) values
      (v_me, 'BUY', -4000, 1, now() - interval '30 hours'), (v_me, 'SELL', 5000, 1, now() - interval '20 minutes');
    insert into public.events (player_id, kind, payload, created_at) values
      (v_me, 'SOLD', jsonb_build_object('qty', 40, 'total', 5000, 'basis', 100, 'cost', 4000, 'profit', 1000), now() - interval '20 minutes');
    update public.world_config set value = to_jsonb(now() - interval '25 hours') where key = 'cargo_at_cost_since';
    v_r := public.company_rate_for(v_me);
    -- trade = (-10,000 + 9,000 + 5,000) + 10,000 - 10,000 = 4,000; net 4,000 - 1,500 - 300 = 2,200; bought - sold - lost = -1,500
    if (v_r->>'net_24h')::numeric <> 2200 or (v_r->>'all_24h')::numeric <> 3700
       or (select (e->>'total_24h')::numeric from jsonb_array_elements(v_r->'lines') e where e->>'line' = 'trade') <> 4000
       or (v_r->'cargo') - 'exact_since' is distinct from jsonb_build_object('at_cost', 0, 'net_24h', 1500, 'bought', 10000, 'cost_sold', 10000, 'lost', 1500, 'exact', true)
       or (v_r->>'net_24h')::numeric + (v_r->>'one_time_24h')::numeric + (v_r #>> '{cargo,net_24h}')::numeric <> (v_r->>'all_24h')::numeric then
      raise exception '0500 self-assert FAIL: goods bought before the window do not count at their basis, or the sums do not hold: %', v_r;
    end if;
    update public.world_config set value = 'false'::jsonb where key = 'cargo_at_cost_enabled';
    v_note := format('rate dark = 0493''s (old body); lit: trade +3,000, lost cargo -1,500, net 1,200, cargo 2,500 at cost, sums hold; older goods at basis: net 2,200, reconciling +1,500');

    -- (b) THE LOSS ITSELF IS THE SAME. A forced home on the NEW body, rolled back; then on the OLD body, the same voyage.
    v_inner := false;
    begin
      v_t := clock_timestamp();
      v_new := voyage.forced_home(v_voy, 1, v_fl);
      v_ms_new := round(extract(epoch from clock_timestamp() - v_t) * 1000, 1);
      execute c_digest using v_fl, v_me into v_dn;
      raise exception using errcode = 'ZX501', message = 'SCENE_NEW_0500';
    exception when sqlstate 'ZX501' then
      v_inner := true;
    end;
    if not v_inner or v_new is null then
      raise exception '0500 self-assert FAIL: the forced home (new body) did not run: %', v_new;
    end if;
    execute (select p.def from pre_0500 p where p.fn = 'voyage.forced_home(uuid,integer,uuid)');
    v_inner := false;
    begin
      v_t := clock_timestamp();
      v_old := voyage.forced_home(v_voy, 1, v_fl);
      v_ms_old := round(extract(epoch from clock_timestamp() - v_t) * 1000, 1);
      execute c_digest using v_fl, v_me into v_do;
      raise exception using errcode = 'ZX501', message = 'SCENE_OLD_0500';
    exception when sqlstate 'ZX501' then
      v_inner := true;
    end;
    if not v_inner or v_old is null or v_dn is null or v_dn is distinct from v_do
       or (v_new - 'cargo_lost_cost') is distinct from v_old or v_old ? 'cargo_lost_cost'
       or (v_new->>'cargo_lost_cost')::numeric is distinct from 2000
       or v_new->'cargo_lost' is distinct from jsonb_build_object(v_good, 40) then
      raise exception '0500 self-assert FAIL: the forced home is not the same on the new body (digest % / %), or the cost is not her cargo''s: % / %', v_dn, v_do, v_new, v_old;
    end if;
    v_note := v_note || format('; forced home, new body and old, the same voyage: hold, hulls, crew, purse, ledger, events, voyage and city purses identical (digest %s), payload identical but for cargo_lost_cost 2,000; %s ms new, %s ms old', left(v_dn, 8), v_ms_new, v_ms_old);
    raise exception using errcode = 'ZX500', message = 'PROBE_ROLLBACK_0500';
  exception when sqlstate 'ZX500' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0500 self-assert FAIL: the scene did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.company_name = 'Casa da Carga 0500' or p.auth_uid = c_uid) then
    raise exception '0500 self-assert FAIL: the scene left something behind';
  end if;
  -- the scene put two old bodies back for a call each: after its rollback every hunked body is the new one again
  for v_h in select h.fn from hunks_0500 h group by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    if exists (select 1 from hunks_0500 h where h.fn = v_h.fn and position(h.new in v_def) = 0)
       or v_def = (select p.def from pre_0500 p where p.fn = v_h.fn) then
      raise exception '0500 self-assert FAIL: % is not the new body after the scene', v_h.fn;
    end if;
  end loop;
  if public.wc('cargo_at_cost_enabled') is distinct from 'false'::jsonb
     or (public.wc('cargo_at_cost_since') #>> '{}')::timestamptz is distinct from now()
     or (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
           from public.world_config c where c.key <> all (c_keys)) <> v_cfg_before then
    raise exception '0500 self-assert FAIL: the scene left a knob moved';
  end if;

  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0500 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0500 self-assert ok: CARGO AT COST (dark). Thirteen hunks once each and reversing over four bodies; two new functions STABLE and server only; no other function or knob moved. Scene (rolled back): %. % ms.',
    v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
