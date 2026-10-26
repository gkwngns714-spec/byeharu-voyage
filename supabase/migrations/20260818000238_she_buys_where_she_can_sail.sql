-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0238 — SHE BUYS WHERE SHE CAN SAIL  (a sell row that must be bought first is planned through a buy city her
--        stores reach; and when no seller is within them, the shut row says the crossing is on the way to buy it)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER (2026-10-26, on the Trade card) ────────────────────────────────────────────────────────────────────
-- *"Best, Port Royal — Hold too full: 4.3 days of supplies, crossing needs 7.8 days. - I don't get it, if this is a
--  limit then i can go to city by city, short distances with lots of visiting. right? why is this a limit?"*
--
-- ── WHY (measured on prod, read-only, head 0235) ─────────────────────────────────────────────────────────────────
-- His Gaivota (51b8f474…) was bound for Cumaná with 149 furs (178.8 of 180 t): supply_reach 4.28 days, cap 883 nm.
-- From Cumaná the capped search reaches Port Royal directly (844.9 nm) — that was never the problem. The card was
-- the TEA board: tea is not aboard, so every sell row is priced as "buy it first, then sell", and world.good_board
-- picks the buy city as the CHEAPEST seller anywhere (`order by price_each`), never asking whether she can sail
-- there. For tea that was Guangzhou; every way from the Caribbean to China has a 1,613.6 nm crossing (the 7.8 days of
-- supplies — the same figure Tsushima showed). So Port Royal's row carried the crossing to GUANGZHOU, and said
-- nothing about Guangzhou. Two faults:
--   (1) the buy city is chosen without her reach: a dearer seller her stores DO reach was passed over, and every
--       sell row was shut by the leg to the cheap one;
--   (2) a row shut by the way to the buy city reads as if the sell city itself were out of reach.
--
-- ── WHAT THIS FILE DOES (world.good_board, 4 hunks; nothing else) ────────────────────────────────────────────────
-- (1) THE BUY CITY SHE CAN SAIL TO. The board's buy city (no city asked: the cheapest seller with units) is now the
--     cheapest seller whose buy row is `sailable` — reached by the capped search (every leg within her stores) and
--     fitting them; only when no seller is sailable does the cheapest of all stand. A city asked (p_from) is kept.
--     So a sell row is "Hold too full" only when no route of legs within her stores runs through any buy city; when
--     one exists, the row is sailable through it, with its stops listed (the capped search, 0231).
-- (2) THE ROW SAYS WHERE THE CROSSING IS. When the buy city's own route is the one her stores cannot sail, every
--     sell row's `shut.figures` gains `buy_at` and `buy_at_name` (the client: "buying at Guangzhou means a crossing
--     that needs 7.8 days of supplies; you can carry 4.3 days").
--
-- ── NOT THE OWNER'S — CONFIRM ────────────────────────────────────────────────────────────────────────────────────
-- * "Sailable" for the buy city is its buy row's own `sailable` (the one reading every row already serves), so the
--   choice and the row agree by construction. A sailable seller is preferred over a cheaper unsailable one at ANY
--   price difference.
-- * A row shut with a sailable buy city (the sell city past her stores from there) keeps 0231's figures, no buy_at.
--
-- ── LOCKS AND TIME ───────────────────────────────────────────────────────────────────────────────────────────────
-- CREATE OR REPLACE ×1 (good_board, by hunks sliced from the LIVE body at prod head 0235 and re-checked at 0237, LF-normalised; each asserted
-- to occur exactly once and to reverse to its pre-image; ACL, volatility, definer, config, owner unchanged). The
-- probes run on their own company inside a sub-block rolled back whole; only their rows are read. No LOCK TABLE, no
-- set role, no set local, no begin. Timings are notices only.
-- ROLLBACK: a forward slice reverses the 4 hunks (each OLD text is here verbatim).
-- VERSION: 0238 (prod head 0237 when written; 0237 re-cut good_board elsewhere, every hunk still occurs once there).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

create or replace function pg_temp.occurs_0238(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

create temp table t0_0238 on commit drop as select clock_timestamp() as t0;

-- ── 1. THE PRE-IMAGE ────────────────────────────────────────────────────────────────────────────────────────────
create temp table defs_before_0238 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg,
       (select p.proowner from pg_proc p where p.oid = f.fn::regprocedure) as owner
  from (values ('world.good_board(uuid,uuid,uuid,numeric)')) f(fn);

create temp table hunks_0238 (n int, old text, new text) on commit drop;
insert into hunks_0238 values
(1,
$h$  v_cap     numeric;                -- 0231: the longest leg those stores cover: every passage below keeps within it
$h$,
$h$  v_cap     numeric;                -- 0231: the longest leg those stores cover: every passage below keeps within it
  v_src_cut boolean := false;       -- 0238: the buy city's own route is past her stores (no seller is within them)
  v_src_name text;                  -- 0238: its name, for the shut row's words
$h$),
(2,
$h$     and (p_from is null or e->>'port' = (select code from public.ports where id = p_from))
   order by (e->>'price_each')::numeric, e->>'port' limit 1;
$h$,
$h$     and (p_from is null or e->>'port' = (select code from public.ports where id = p_from))
   -- 0238 (owner, Port Royal): THE CHEAPEST SELLER SHE CAN SAIL TO — its buy row `sailable` (every leg within her
   -- stores, 0231); the cheapest of all only when no seller is
   order by (e->>'sailable')::boolean is not true, (e->>'price_each')::numeric, e->>'port' limit 1;
  -- 0238: when even that city's route is past her stores, every sell row's shut names it (the crossing is on the way there)
  v_src_cut := v_basis <> 'on_board' and v_src.code is not null
               and not exists (select 1 from jsonb_array_elements(v_buy) e
                                where e->>'port' = v_src.code and jsonb_typeof(e->'miles') = 'number');
  v_src_name := (select p.name from public.ports p where p.code = v_src.code);
$h$),
(3,
$h$           'shut', (select sh.refusal from shuts sh where sh.nm = r.shut_leg and r.nm is null),   -- 0231
$h$,
$h$           'shut', (select case when v_src_cut   -- 0238: the crossing is on the way to the buy city: say which
                                then jsonb_set(sh.refusal, '{figures}', coalesce(sh.refusal->'figures', '{}'::jsonb)
                                               || jsonb_build_object('buy_at', v_src.code, 'buy_at_name', v_src_name))
                                else sh.refusal end
                      from shuts sh where sh.nm = r.shut_leg and r.nm is null),   -- 0231
$h$),
(4,
$h$-- 0171: ONE GOOD AT EVERY CITY, FOR YOUR FLEET (docs/COMMAND_DESK.md §3.3, §7.2). Every figure is a call of its
$h$,
$h$-- 0171: ONE GOOD AT EVERY CITY, FOR YOUR FLEET (docs/COMMAND_DESK.md §3.3, §7.2). Every figure is a call of its
-- 0238: a good bought first is bought at the cheapest seller she can SAIL to (within her stores), not the cheapest
-- anywhere; a sell row shut by the way to that city says so (shut.figures.buy_at).
$h$);

-- the pre-image under a pg_temp name, for the parity proofs and the positive controls
do $$
begin
  if (select count(*) from defs_before_0238 where def is not null) <> 1 then
    raise exception '0238 self-assert FAIL: world.good_board(uuid,uuid,uuid,numeric) not found';
  end if;
  execute replace((select def from defs_before_0238),
                  'CREATE OR REPLACE FUNCTION world.good_board(', 'CREATE OR REPLACE FUNCTION pg_temp.good_board_old_0238(');
end $$;

-- ── 2. THE NEW BODY ─────────────────────────────────────────────────────────────────────────────────────────────
do $$
declare
  d     record;
  h     record;
  p     record;
  v_def text;
  v_rev text;
begin
  select * into d from defs_before_0238;
  v_def := d.def;
  for h in select * from hunks_0238 order by n loop
    if pg_temp.occurs_0238(v_def, h.old) <> 1 then
      raise exception '0238 self-assert FAIL: good_board hunk % occurs % time(s), not once — the deployed body is not what this file was written against',
        h.n, pg_temp.occurs_0238(v_def, h.old);
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
  v_rev := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
  for h in select * from hunks_0238 order by n desc loop
    if pg_temp.occurs_0238(v_rev, h.new) <> 1 then
      raise exception '0238 self-assert FAIL: new hunk % is not in the live body once', h.n;
    end if;
    v_rev := replace(v_rev, h.new, h.old);
  end loop;
  if v_rev <> d.def then
    raise exception '0238 self-assert FAIL: good_board does not reverse to its pre-image';
  end if;
  select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef,
         coalesce(pr.proconfig::text, '') as cfg, pr.proowner as owner
    into p from pg_proc pr where pr.oid = d.fn::regprocedure;
  if p.acl <> d.acl or p.vol <> d.vol or p.secdef <> d.secdef or p.cfg <> d.cfg or p.owner <> d.owner then
    raise exception '0238 self-assert FAIL: good_board changed its ACL (% → %), owner, volatility, definer or config', d.acl, p.acl;
  end if;
end $$;

-- ── 3. THE PROBES: one company of this file's own, inside a sub-block that is rolled back whole ─────────────────
do $$
declare
  c_auth    constant uuid := '00000000-0238-4000-8000-000000000001';
  v_player  uuid;
  v_fleet   uuid;
  v_lis     uuid;
  v_load    uuid;
  v_lcode   text;
  v_lbulk   numeric;
  v_speed   numeric;
  v_cap     numeric;
  v_good    uuid;
  v_gcode   text;
  v_board   jsonb;
  v_old     jsonb;
  v_src     text;
  v_want    text;
  v_far     text;
  v_near    text;
  v_n       int;
  v_tries   int := 0;
  v_ms      numeric[] := '{}';
  v_ms_old  numeric[] := '{}';
  v_t       timestamptz;
  v_hazard  jsonb;
  c         record;
  k         int;
  r_a text; r_b text; r_c text; r_d text;
begin
  select value into v_hazard from public.world_config where key = 'hazard_p_max';
  begin
    update public.world_config set value = to_jsonb(0.0) where key = 'hazard_p_max';
    select id into v_lis from public.ports where code = 'LIS';
    v_player := public.new_house(c_auth, 'Probe 0238', 'PRT');
    select id into v_fleet from public.fleets where player_id = v_player;
    if (select port_id from public.fleets where id = v_fleet) <> v_lis then
      raise exception '0238 self-assert FAIL: the probe company was not founded at Lisbon';
    end if;
    perform cmd.assume_identity(c_auth);

    -- THE OWNER'S HOLD: casks dry, the hold all but full of one good (as 0231's probe: room beside the cargo for the
    -- stores of a ~600-mile leg), so her stores cap the legs well below her navigation
    select g.id, g.code, g.bulk into v_load, v_lcode, v_lbulk
      from public.port_goods pg join public.goods g on g.id = pg.good_id
     where pg.port_id = v_lis and pg.stock > 0 and public.port_offers(v_lis, g.id)
     order by g.code limit 1;
    update public.ships set water_t = 0, food_t = 0 where fleet_id = v_fleet;
    v_speed := greatest(voyage.fleet_speed(v_fleet), 0.1);
    update public.ships s
       set cargo = jsonb_build_object(v_lcode, floor(greatest(0, public.ship_hold_capacity(s.id)
                     - s.crew * (public.wc_num('water_per_crew_day') + public.wc_num('food_per_crew_day'))
                       * voyage.stores_need_days(600, v_speed)) / greatest(v_lbulk, 0.001)))
     where s.fleet_id = v_fleet;
    select sr.cap_nm into v_cap from public.supply_reach(v_fleet) sr;
    if v_cap is null or v_cap < 300 or v_cap > public.passage_reach_nm(v_player) * 0.8 then
      raise exception '0238 self-assert FAIL: the loaded probe''s cap is % nm — between 300 nm and 80%% of her navigation was the precondition', round(v_cap);
    end if;

    -- (a) THE OWNER'S BUG, ON A GOOD NOT ABOARD: the pre-image buys at the cheapest seller anywhere, one past her
    --     stores, while a dearer seller within them sells it. Candidates: a good whose cheapest seller at the market
    --     price is beyond the capped search from Lisbon and that another seller within it sells; the pre-image board
    --     confirms (positive control), at most 8 boards asked.
    create temp table reach_0238 on commit drop as
      select r.port_id, r.code, r.nm from voyage.reach_passage(v_player, v_fleet, v_lis, v_cap) r;
    insert into reach_0238 values (v_lis, 'LIS', 0);
    for c in
      with sellers as (
        select pg.good_id, pg.port_id, world.mid_price(pg.port_id, pg.good_id, pg.stock) as mid,
               (select x.nm from reach_0238 x where x.port_id = pg.port_id) as nm
          from public.port_goods pg join public.ports p on p.id = pg.port_id
         where p.kind = 'HARBOUR' and pg.stock > 0 and pg.good_id <> v_load and public.port_offers(pg.port_id, pg.good_id)
      ), firsts as (
        select distinct on (s.good_id) s.good_id, s.nm from sellers s order by s.good_id, s.mid, s.port_id
      )
      select f.good_id, g.code from firsts f join public.goods g on g.id = f.good_id
       where f.nm is null and exists (select 1 from sellers s where s.good_id = f.good_id and s.nm is not null)
       order by g.code limit 8
    loop
      v_tries := v_tries + 1;
      v_old := pg_temp.good_board_old_0238(c.good_id, v_fleet, null, null);
      v_src := v_old->'qty'->>'bought_at';
      if v_src is not null
         and not exists (select 1 from reach_0238 x where x.code = v_src and x.nm is not null)
         and exists (select 1 from jsonb_array_elements(v_old->'buy') e where (e->>'units')::numeric > 0 and (e->>'sailable')::boolean) then
        v_good := c.good_id;
        v_gcode := c.code;
        exit;
      end if;
    end loop;
    if v_good is null then
      raise exception '0238 self-assert FAIL: positive control — no good of % tried has the pre-image buying past her stores while a seller within them sells it', v_tries;
    end if;
    for k in 1 .. 3 loop
      v_t := clock_timestamp();
      v_board := world.good_board(v_good, v_fleet, null, null);
      v_ms := v_ms || round(extract(epoch from clock_timestamp() - v_t) * 1000, 1);
      v_t := clock_timestamp();
      v_old := pg_temp.good_board_old_0238(v_good, v_fleet, null, null);
      v_ms_old := v_ms_old || round(extract(epoch from clock_timestamp() - v_t) * 1000, 1);
    end loop;
    v_far := v_old->'qty'->>'bought_at';
    if (select count(*) from jsonb_array_elements(v_old->'sell') e where (e->>'sailable')::boolean) <> 0 then
      raise exception '0238 self-assert FAIL: positive control — the pre-image (buying at %) sails % sell row(s)', v_far,
        (select count(*) from jsonb_array_elements(v_old->'sell') e where (e->>'sailable')::boolean);
    end if;
    r_a := format('%s (%s boards tried): the pre-image buys at %s, past her stores (cap %s nm) — 0 of %s sell rows sailable',
                  v_gcode, v_tries, v_far, round(v_cap), jsonb_array_length(v_old->'sell'));

    -- (b) THE FIX: the cheapest SAILABLE seller; every sell city a route of legs within her stores reaches from it is
    --     sailable with that route; every other shut row is not blamed on the buy city
    select e->>'port' into v_want from jsonb_array_elements(v_board->'buy') e
     where (e->>'units')::numeric > 0 and (e->>'sailable')::boolean
     order by (e->>'price_each')::numeric, e->>'port' limit 1;
    v_src := v_board->'qty'->>'bought_at';
    if v_src is distinct from v_want then
      raise exception '0238 self-assert FAIL: the board buys at %, the cheapest sailable seller is %', v_src, v_want;
    end if;
    create temp table reach2_0238 on commit drop as
      select r.code, r.nm, r.max_leg_nm from voyage.reach_passage(v_player, v_fleet, (select id from public.ports where code = v_src), v_cap) r;
    insert into reach2_0238 values (v_src, 0, 0);
    select count(*) into v_n from jsonb_array_elements(v_board->'sell') e
      join reach2_0238 x on x.code = e->>'port' and x.nm is not null;
    if v_n = 0
       or exists (select 1 from jsonb_array_elements(v_board->'sell') e
                    join reach2_0238 x on x.code = e->>'port'
                   where (x.nm is not null) is distinct from (jsonb_typeof(e->'miles') = 'number')
                      or (x.nm is not null and ((e->>'sailable')::boolean is not true
                                                or (e->'longest_leg'->>'miles')::numeric > v_cap + 0.5)))
       or exists (select 1 from jsonb_array_elements(v_board->'sell') e
                   where jsonb_typeof(e->'shut') = 'object' and (e->'shut'->'figures') ? 'buy_at') then
      raise exception '0238 self-assert FAIL: buying at %, the sell rows a capped route reaches are not exactly the sailable ones within the cap, or a shut row blames the buy city', v_src;
    end if;
    r_b := format('now buys at %s (the cheapest seller within her stores): %s of %s sell rows sailable, every one by legs within %s nm; good_board %s ms (pre-image %s ms)',
                  v_src, (select count(*) from jsonb_array_elements(v_board->'sell') e where (e->>'sailable')::boolean),
                  jsonb_array_length(v_board->'sell'), round(v_cap), array_to_string(v_ms, ', '), array_to_string(v_ms_old, ', '));

    -- (c) WHEN THE BUY CITY IS PAST HER STORES (asked for it: p_from), every shut sell row names it — and only that
    --     changed against the pre-image
    v_board := world.good_board(v_good, v_fleet, (select id from public.ports where code = v_far), null);
    v_old := pg_temp.good_board_old_0238(v_good, v_fleet, (select id from public.ports where code = v_far), null);
    select count(*) into v_n from jsonb_array_elements(v_board->'sell') e where jsonb_typeof(e->'shut') = 'object';
    if v_board->'qty'->>'bought_at' is distinct from v_far or v_n = 0
       or exists (select 1 from jsonb_array_elements(v_board->'sell') e
                   where jsonb_typeof(e->'shut') = 'object'
                     and (e->'shut'->'figures'->>'buy_at' is distinct from v_far
                          or e->'shut'->'figures'->>'buy_at_name' is distinct from (select name from public.ports where code = v_far)))
       or exists (select 1 from jsonb_array_elements(v_old->'sell') e where (e->'shut'->'figures') ? 'buy_at')
       or (select jsonb_agg(case when jsonb_typeof(e->'shut') = 'object'
                                 then jsonb_set(e, '{shut,figures}', (e->'shut'->'figures') - 'buy_at' - 'buy_at_name') else e end)
             from jsonb_array_elements(v_board->'sell') e) <> (v_old->'sell')
       or (v_board - 'sell') <> (v_old - 'sell') then
      raise exception '0238 self-assert FAIL: asked to buy at % (past her stores), the shut sell rows do not name it, or the board differs from its pre-image by more than that', v_far;
    end if;
    r_c := format('asked to buy at %s: %s shut sell row(s), each naming %s (%s); otherwise the pre-image to the byte, e.g. %s',
                  v_far, v_n, v_far, (select name from public.ports where code = v_far),
                  (select (e->'shut'->'figures')::text from jsonb_array_elements(v_board->'sell') e where jsonb_typeof(e->'shut') = 'object' limit 1));

    -- (d) PARITY: a board whose buy city she can sail to (asked: the sailable seller), and the board of the good in her
    --     hold, are their pre-images exactly
    v_near := v_src;
    if world.good_board(v_good, v_fleet, (select id from public.ports where code = v_near), null)
         <> pg_temp.good_board_old_0238(v_good, v_fleet, (select id from public.ports where code = v_near), null)
       or world.good_board(v_load, v_fleet, null, null) <> pg_temp.good_board_old_0238(v_load, v_fleet, null, null) then
      raise exception '0238 self-assert FAIL: a board whose buy city is within her stores (%), or the board of her cargo (%), is not its pre-image', v_near, v_lcode;
    end if;
    r_d := format('parity: %s bought at %s, and %s aboard, = their pre-images', v_gcode, v_near, v_lcode);

    raise exception 'ROLLBACK_0238';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0238' then
      raise;
    end if;
  end;
  if exists (select 1 from public.players where id = v_player)
     or (select value from public.world_config where key = 'hazard_p_max') <> v_hazard then
    raise exception '0238 self-assert FAIL: the probe did not roll back whole';
  end if;
  raise notice '0238 probe (a): %', r_a;
  raise notice '0238 probe (b): %', r_b;
  raise notice '0238 probe (c): %', r_c;
  raise notice '0238 probe (d): %', r_d;
  raise notice '0238 self-assert ok: SHE BUYS WHERE SHE CAN SAIL. world.good_board buys a good at the cheapest seller within her stores, and a row shut by the way to the buy city names it. % s.',
    round(extract(epoch from clock_timestamp() - (select t0 from t0_0238)), 1);
end $$;
