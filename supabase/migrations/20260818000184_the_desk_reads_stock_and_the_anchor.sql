-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0184 — THE DESK READS STOCK, AND A FLEET AT ANCHOR IS PRICED FROM WHERE SHE LIES
--        (stock and its normal level on every desk read; world.good_board from the nearest harbour)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER'S WORDS ───────────────────────────────────────────────────────────────────────────
-- 2026-10-17: *"when i press coffee trade goods, it will show chart, where i can buy, the price if i
-- sell to other cities. at which time"*. On 2026-10-18 his fleet lay at anchor and the desk's Sell at
-- read "Osaka 172,268" with "—" for net per ton and "—" for the arrival on every row.
--
-- 2026-10-18: *"i don't see stock of the trade goods so there needs fixing"* — every Buy at / Sell at
-- row and every watchlist row shows the city's stock against its normal level, and the chart a stock
-- line, so he sees why a price moved.
--
-- ── WHY ─────────────────────────────────────────────────────────────────────────────────────────
-- world.good_board (0171) runs its distances from the fleet's berth, or from the port she is bound
-- for (the miles still to sail added). A fleet with neither — ANCHORED (0047's free sea), or adrift
-- at a held position — had no origin: voyage.reach_from(null) is empty, so every row carried null
-- miles, null days, null arrival, null wages and therefore a null net.
--
-- And no desk read served a city's NORMAL stock (port_goods.stock_target — the level the price is
-- centred on and regeneration returns to): world.market had it, world.good_board served `stock` on a buy
-- row only, world.watchlist and world.price_history no stock at all, world.price_outlook stepped it
-- (public.price_path) and dropped it.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) STOCK, served beside its normal level (additive keys only; nothing removed or renamed):
--     world.good_board  buy rows + stock_target; sell rows + stock, stock_target;
--     world.watchlist   best + stock, stock_target (the cheapest seller's);
--     world.price_history points + stock (the column the snapshot already writes);
--     world.price_outlook points + stock (public.price_path's own stepped stock), + stock_target.
-- (2) AT ANCHOR — one hunk in world.good_board: with no berth and no voyage under way, the origin is THE NEAREST
-- HARBOUR to her position (great circle, voyage.gc_distance_nm — the sailed-distance table holds
-- harbours only), the great-circle miles to it are the lead (as a voyage's miles left are), and the
-- lead's time is those miles at her speed. `fleet.where` stays {kind: 'at_sea', port: null} and adds
-- `via` (that harbour's code) and `miles_left`. Every other figure is unchanged and still a call of
-- its one authority. The shape is a superset of 0171's: a client that does not read `via` is unhurt.
--
-- ── NOT THE OWNER'S — CONFIRM ───────────────────────────────────────────────────────────────────
-- * The lead is the great circle to the nearest harbour, not a sailed course (open water from an
--   anchorage is the client pathfinder's, not the server's). It is an estimate's figure, labelled so.
--
-- ── LOCKS AND TIME ──────────────────────────────────────────────────────────────────────────────
-- CREATE OR REPLACE FUNCTION ×4 by hunks sliced from the LIVE bodies (prod head 0181, LF-normalised,
-- asserted to occur exactly once and to reverse to its pre-image, ACL unchanged). The probe runs on
-- its own house inside a sub-transaction rolled back whole. No LOCK TABLE, no set role, no begin.
-- ROLLBACK: a forward slice puts the hunk's OLD text back (it is here verbatim).
-- VERSION: 0184 (after #220 0182 and #219 0183, in flight; renumbered at push if they move). Written on prod head 0181; touches none of their functions.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '10min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

-- ── 0. HELPERS (pg_temp, gone at commit) ───────────────────────────────────────────────────────
create or replace function pg_temp.occurs_0184(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 1. THE PRE-IMAGE ───────────────────────────────────────────────────────────────────────────
create temp table defs_before_0184 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl
  from (values ('world.good_board(uuid,uuid,uuid,numeric)'),
               ('world.watchlist(uuid)'),
               ('world.price_history(uuid,integer)'),
               ('world.price_outlook(uuid,uuid,integer,text)')) f(fn);

do $$
begin
  if (select count(*) from defs_before_0184 where def is not null) <> 4 then
    raise exception '0184 self-assert FAIL: % of the 4 bodies found', (select count(*) from defs_before_0184 where def is not null);
  end if;
end $$;

-- the old board under a pg_temp name, for the side-by-side probe (positive control)
do $$
declare
  v_def text := replace((select def from defs_before_0184 where fn like 'world.good_board%'),
                        'CREATE OR REPLACE FUNCTION world.good_board(', 'CREATE OR REPLACE FUNCTION pg_temp.good_board_old_0184(');
begin
  if v_def not like '%pg_temp.good_board_old_0184(%' then
    raise exception '0184 self-assert FAIL: the old copy of world.good_board was not renamed';
  end if;
  execute v_def;
end $$;

-- ── 2. THE HUNK ────────────────────────────────────────────────────────────────────────────────
create temporary table hunks_0184 (fn text not null, n int not null, old text not null, new text not null,
                                   primary key (fn, n)) on commit drop;
insert into hunks_0184 values
('world.good_board(uuid,uuid,uuid,numeric)', 1,
$h$      v_where := jsonb_build_object('kind', 'at_sea', 'port', null);
$h$,
$h$      -- 0184: AT ANCHOR (no berth, no voyage under way): from THE NEAREST HARBOUR to where she lies —
      -- the great-circle miles to it are the lead, as a voyage's miles left are, and the lead's time is
      -- those miles at her speed. The sailed-distance table holds harbours only. Never a board of bare rows.
      select p.id, voyage.gc_distance_nm(f.lat, f.lon, p.lat, p.lon)
        into v_origin, v_lead_nm
        from public.ports p
       where p.kind = 'HARBOUR' and f.lat is not null and f.lon is not null
       order by voyage.gc_distance_nm(f.lat, f.lon, p.lat, p.lon), p.code
       limit 1;
      v_lead_nm := coalesce(v_lead_nm, 0);
      if v_origin is not null and v_speed > 0 then
        v_lead_at := v_now + make_interval(secs => (v_lead_nm / v_speed * 3600 / v_tc)::double precision);
      end if;
      v_where := jsonb_build_object('kind', 'at_sea', 'port', null,
                                    'via', (select code from public.ports where id = v_origin),
                                    'miles_left', round(v_lead_nm));
$h$),
-- (2..5) good_board: stock and its normal level on both ladders
('world.good_board(uuid,uuid,uuid,numeric)', 2,
$h$    select p.id, p.code, p.name, rc.nm, pg.stock,
           qb.units, qb.total, qb.avg_price
$h$,
$h$    select p.id, p.code, p.name, rc.nm, pg.stock, pg.stock_target,   -- 0184: + the normal level
           qb.units, qb.total, qb.avg_price
$h$),
('world.good_board(uuid,uuid,uuid,numeric)', 3,
$h$           'units', s.units, 'cost', s.total, 'price_each', s.avg_price, 'stock', s.stock,
$h$,
$h$           'units', s.units, 'cost', s.total, 'price_each', s.avg_price, 'stock', s.stock,
           'stock_target', s.stock_target,   -- 0184
$h$),
('world.good_board(uuid,uuid,uuid,numeric)', 4,
$h$    select p.id, p.code, p.name,
           world.mid_price(p.id, p_good, pg.stock) as mid,
$h$,
$h$    select p.id, p.code, p.name, pg.stock, pg.stock_target,   -- 0184: + the city's stock and its normal level
           world.mid_price(p.id, p_good, pg.stock) as mid,
$h$),
('world.good_board(uuid,uuid,uuid,numeric)', 5,
$h$           'port', r.code, 'name', r.name, 'mid', r.mid, 'quoted', p.id is not null,
$h$,
$h$           'port', r.code, 'name', r.name, 'mid', r.mid, 'quoted', p.id is not null,
           'stock', r.stock, 'stock_target', r.stock_target,   -- 0184
$h$),
-- watchlist: the cheapest seller's stock and normal level
('world.watchlist(uuid)', 1,
$h$           h.at as as_of, h.mid is not null as recorded
$h$,
$h$           h.at as as_of, h.mid is not null as recorded,
           pg.stock, pg.stock_target   -- 0184
$h$),
('world.watchlist(uuid)', 2,
$h$                        else jsonb_build_object('port', b.port, 'mid', round(b.mid, 2), 'as_of', b.as_of, 'recorded', b.recorded) end,
$h$,
$h$                        else jsonb_build_object('port', b.port, 'mid', round(b.mid, 2), 'as_of', b.as_of, 'recorded', b.recorded,
                                                'stock', round(b.stock, 2), 'stock_target', b.stock_target) end,   -- 0184
$h$),
-- price_history: the stock the snapshot wrote beside each mid
('world.price_history(uuid,integer)', 1,
$h$             jsonb_agg(jsonb_build_object('slot', h.slot, 'at', h.at, 'mid', round(h.mid, 2))
$h$,
$h$             jsonb_agg(jsonb_build_object('slot', h.slot, 'at', h.at, 'mid', round(h.mid, 2), 'stock', round(h.stock, 2))   -- 0184
$h$),
-- price_outlook: price_path's stepped stock on each point, and the normal level once
('world.price_outlook(uuid,uuid,integer,text)', 1,
$h$    select p.k, p.at,
$h$,
$h$    select p.k, p.at, p.stock,   -- 0184
$h$),
('world.price_outlook(uuid,uuid,integer,text)', 2,
$h$  select (select jsonb_agg(jsonb_build_object('at', pp.at, 'value', pp.value, 'lo', pp.lo, 'hi', pp.hi) order by pp.k) from pp),
$h$,
$h$  select (select jsonb_agg(jsonb_build_object('at', pp.at, 'value', pp.value, 'lo', pp.lo, 'hi', pp.hi,
                                               'stock', round(pp.stock, 2)) order by pp.k) from pp),   -- 0184
$h$),
('world.price_outlook(uuid,uuid,integer,text)', 3,
$h$    'points', v_pts,
$h$,
$h$    'points', v_pts,
    'stock_target', (select pg.stock_target from public.port_goods pg where pg.port_id = p_port and pg.good_id = p_good),   -- 0184
$h$);

do $$
declare
  d     record;
  h     record;
  v_def text;
  v_rev text;
begin
  for d in select * from defs_before_0184 order by fn loop
    v_def := d.def;
    for h in select * from hunks_0184 where fn = d.fn order by n loop
      if pg_temp.occurs_0184(v_def, h.old) <> 1 then
        raise exception '0184 self-assert FAIL: hunk % of % occurs % time(s), not once — the deployed body is not what this file was written against',
          h.n, d.fn, pg_temp.occurs_0184(v_def, h.old);
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    execute v_def;
    v_rev := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0184 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0184(v_rev, h.new) <> 1 then
        raise exception '0184 self-assert FAIL: hunk % of % is not in the new body once', h.n, d.fn;
      end if;
      v_rev := replace(v_rev, h.new, h.old);
    end loop;
    if v_rev <> d.def then
      raise exception '0184 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    if coalesce((select p.proacl::text from pg_proc p where p.oid = d.fn::regprocedure), '') <> d.acl then
      raise exception '0184 self-assert FAIL: the ACL of % moved', d.fn;
    end if;
  end loop;
end $$;

-- ── 3. THE PROBE AND THE SELF-ASSERT (an own house at Lisbon, put to anchor off it; rolled back whole)
do $$
declare
  c_uid   constant uuid := '00000000-0184-4000-8000-000000000001';
  v_lis   uuid := (select id from public.ports where code = 'LIS');
  v_p     uuid;
  v_pf    uuid;
  v_good  uuid;
  v_b0    jsonb;   -- docked at Lisbon
  v_b1    jsonb;   -- at anchor off it, the new board
  v_old   jsonb;   -- at anchor off it, the old board (positive control)
  v_w     jsonb;
  v_o     jsonb;
  v_t0    timestamptz;
  v_out   jsonb;
  v_res   jsonb;
begin
  begin
    v_p := public.new_house(c_uid, 'Casa da Âncora 0184', 'PRT', 'LIS');
    select id into v_pf from public.fleets where player_id = v_p;
    perform cmd.assume_identity(c_uid);
    select g.id into v_good
      from public.goods g join public.port_goods pg on pg.good_id = g.id and pg.port_id = v_lis
     where public.port_offers(v_lis, g.id) and pg.stock >= 50
     order by g.code limit 1;
    v_b0 := world.good_board(v_good, v_pf);
    -- to anchor, a few miles west of the Tagus bar
    update public.fleets set status = 'ANCHORED', port_id = null, lat = 38.62, lon = -9.55 where id = v_pf;
    v_t0 := clock_timestamp();
    v_b1 := world.good_board(v_good, v_pf);
    v_out := jsonb_build_object('ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
    v_old := pg_temp.good_board_old_0184(v_good, v_pf);
    v_w := world.watchlist(v_pf);
    v_o := world.price_outlook(v_lis, v_good, 4, 'mid');
    v_out := v_out || jsonb_build_object(
      'sell_no_stock', (select count(*) from jsonb_array_elements(v_b1->'sell') e
                         where e->'stock' = 'null'::jsonb or e->'stock_target' is null or e->'stock_target' = 'null'::jsonb),
      'buy_no_target', (select count(*) from jsonb_array_elements(v_b1->'buy') e
                         where e->'stock_target' is null or e->'stock_target' = 'null'::jsonb),
      'stock_off', (select count(*) from jsonb_array_elements(v_b1->'sell') e
                      join public.ports p on p.code = e->>'port'
                      join public.port_goods pg on pg.port_id = p.id and pg.good_id = v_good
                     where (e->>'stock')::numeric <> pg.stock or (e->>'stock_target')::numeric <> pg.stock_target),
      'watch_no_target', (select count(*) from jsonb_array_elements(v_w->'goods') e
                           where e->'best' <> 'null'::jsonb and (e->'best'->'stock_target' is null or e->'best'->'stock_target' = 'null'::jsonb)),
      'watch_n', jsonb_array_length(v_w->'goods'),
      'outlook_no_stock', (select count(*) from jsonb_array_elements(v_o->'points') e where e->'stock' is null or e->'stock' = 'null'::jsonb),
      'outlook_target', v_o->'stock_target',
      'outlook_now_stock', (v_o->'points'->0->>'stock')::numeric,
      'lis_stock', (select pg.stock from public.port_goods pg where pg.port_id = v_lis and pg.good_id = v_good),
      'history_runs', world.price_history(v_lis, 4) ? 'goods',
      'good', v_good,
      'where', v_b1->'fleet'->'where',
      'via_nearest', (select p.code from public.ports p where p.kind = 'HARBOUR'
                       order by voyage.gc_distance_nm(38.62, -9.55, p.lat, p.lon), p.code limit 1),
      'quoted', (select count(*) from jsonb_array_elements(v_b1->'sell') e where (e->>'quoted')::boolean),
      'bare', (select count(*) from jsonb_array_elements(v_b1->'sell') e
                where (e->>'quoted')::boolean and (e->'days' = 'null'::jsonb or e->'arrive_at' = 'null'::jsonb
                                                   or e->'net_per_ton' = 'null'::jsonb or e->'miles' = 'null'::jsonb)),
      'buy_bare', (select count(*) from jsonb_array_elements(v_b1->'buy') e where e->'days' = 'null'::jsonb),
      'old_bare', (select count(*) from jsonb_array_elements(v_old->'sell') e
                    where (e->>'quoted')::boolean and e->'days' = 'null'::jsonb),
      -- every sell row reached from both: anchored miles = docked miles + the lead (each rounded: ±1)
      'off', (select count(*) from jsonb_array_elements(v_b0->'sell') a
                join jsonb_array_elements(v_b1->'sell') b on b->>'port' = a->>'port'
               where a->'miles' <> 'null'::jsonb
                 and abs((b->>'miles')::numeric - (a->>'miles')::numeric - (v_b1->'fleet'->'where'->>'miles_left')::numeric) > 1),
      'lead_ok', (v_b1->'fleet'->'where'->>'miles_left')::numeric
                  = round(voyage.gc_distance_nm(38.62, -9.55, (select lat from public.ports where code = 'LIS'),
                                                (select lon from public.ports where code = 'LIS'))::numeric));
    raise exception using errcode = 'ZX184', message = v_out::text;
  exception when sqlstate 'ZX184' then
    v_res := sqlerrm::jsonb;
  end;

  if exists (select 1 from public.players where id = v_p) then
    raise exception '0184 self-assert FAIL: the probe house survived its rolled-back block';
  end if;
  if v_res->'where'->>'kind' <> 'at_sea' or v_res->'where'->>'via' is distinct from v_res->>'via_nearest'
     or (v_res->'where'->>'miles_left')::numeric <= 0 then
    raise exception '0184 self-assert FAIL: at anchor the board does not name the nearest harbour and the miles to it: %', v_res;
  end if;
  if (v_res->>'quoted')::int < 1 or (v_res->>'bare')::int <> 0 or (v_res->>'buy_bare')::int <> 0 then
    raise exception '0184 self-assert FAIL: at anchor % quoted sell row(s), % of them bare, % bare buy row(s): %',
      v_res->>'quoted', v_res->>'bare', v_res->>'buy_bare', v_res;
  end if;
  if (v_res->>'old_bare')::int < 1 then
    raise exception '0184 self-assert FAIL: the positive control — the old board was not bare at anchor: %', v_res;
  end if;
  if (v_res->>'sell_no_stock')::int <> 0 or (v_res->>'buy_no_target')::int <> 0 or (v_res->>'stock_off')::int <> 0
     or (v_res->>'watch_no_target')::int <> 0 or (v_res->>'watch_n')::int < 1
     or (v_res->>'outlook_no_stock')::int <> 0 or v_res->'outlook_target' = 'null'::jsonb
     or round((v_res->>'outlook_now_stock')::numeric) <> round((v_res->>'lis_stock')::numeric)
     or not (v_res->>'history_runs')::boolean then
    raise exception '0184 self-assert FAIL: a desk read does not serve stock beside its normal level: %', v_res;
  end if;
  if v_res->>'via_nearest' = 'LIS' and ((v_res->>'off')::int <> 0 or not (v_res->>'lead_ok')::boolean) then
    raise exception '0184 self-assert FAIL: off Lisbon the anchored miles are not the docked miles + the lead: %', v_res;
  end if;

  raise notice '0184 self-assert ok: STOCK on every desk read — % sell row(s) carry stock and its normal level equal to port_goods, every buy row its normal level, % watchlist goods, the outlook % point(s) from stock % (normal %).',
    v_res->>'quoted', v_res->>'watch_n', 4, v_res->>'lis_stock', v_res->>'outlook_target';
  raise notice '0184 self-assert ok: A FLEET AT ANCHOR IS PRICED FROM WHERE SHE LIES. Off the Tagus bar the board runs from % (% miles, the nearest harbour); % quoted sell row(s), none bare (the old board: % bare); anchored miles = docked miles + the lead on every row (% off); % ms. Body reverses, ACL unchanged.',
    v_res->'where'->>'via', v_res->'where'->>'miles_left', v_res->>'quoted', v_res->>'old_bare', v_res->>'off', v_res->>'ms';
end $$;
