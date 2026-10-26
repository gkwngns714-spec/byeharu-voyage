-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0233 — NO CITY IS PAID BY NOBODY
--        (slice E3 of docs/CLOSED_ECONOMY.md: lit, the two city faucets stop — a city earns no EARNINGS from
--         nobody, and a sale's distance premium is no longer paid by "the townsfolk" from nowhere: the purse pays
--         the whole sale. DARK: every body below answers exactly as before while economy_closed is false.)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER, VERBATIM (docs/OWNER_REQUESTS.md row 212, 2026-10-26) ────────────────────────────
--   "i want the gold to be stopped here, meaning no more excess gold produced - so that the economy circulates
--    like real world."
--
-- ── WHAT THIS FILE DOES (lit only — public.economy_closed(), 0228, is the one gate) ─────────────
--   1. public.city_day: EARNINGS (a city's development income, minted: 28.2 M a day on 2026-10-26) is not
--      posted. CROWN_TAX and CROWN_AID (city to city, moved) run as before.
--   2. cmd.do_sell: IMPORT_DEMAND (the distance premium the townsfolk paid from nowhere, 0174: 25.4 M a day) is
--      not posted, and the empty-purse rule judges the WHOLE total, not the base (total / haul): the purse pays
--      the whole sale, so it must cover the whole sale — a short purse shrinks the lot to what it covers whole,
--      and refuses (E_CITY_BROKE) when it covers no step. Done in ONE line: lit, the haul the purse divides by
--      is 1 — the shrink loop, the refusal and the premium all read that one variable (the price does not: it
--      is world.quote's, untouched). The bid factor (0122) is unchanged.
--   3. public.city_sell_outflow (the reserve's measure): lit, SELL counted whole — no longer net of IMPORT_DEMAND
--      (the days already kept still carry IMPORT_DEMAND rows; lit they are not netted, because lit the purse pays
--      the whole sale).
--
-- ── HUNKS SLICED FROM THE LIVE BODIES (prod head 0229, LF-normalised; each asserted to occur exactly once and
--    to reverse to its pre-image; ACL / volatility / definer / config unchanged) ────────────────────────────
--   public.city_day(timestamptz) ×1, cmd.do_sell(uuid,jsonb) ×1, public.city_sell_outflow(uuid) ×1.
--   None of the three is sliced by 0231 (osn-legs-fit-supplies: voyage.reach_passage, world.good_board) or
--   0232 (osn-stats-all-live: tick_stats and the stats faces), so the bodies are cut as they stand at 0229.
--
-- ── WHAT IT SELF-ASSERTS (own probe rows only: flows with id above a mark taken in-block AND written at this
--    transaction's now(); each probe in a sub-transaction rolled back, asserted) ─────────────────────────
--   (a) the hunks reverse; ACL / volatility / definer / config unmoved; registry unchanged; walls 0.
--   (b) THE SALE, BYTE FOR BYTE DARK: one probe sale (a probe company docked at a probe harbour selling a good
--       priced from afar, haul ≥ 1.5, its purse lit and full) run once on the PRE-IMAGE body (before the
--       re-cut) and once on the new body, economy open: the sale's answer, its SOLD event, every flow it wrote
--       (kind, ducats, in order) and the house's ledger are identical, and IMPORT_DEMAND > 0 (the premium path
--       is the one exercised). The (port, good) row and the harbour's purse row are locked for the file's
--       transaction so no live trade moves them between the two runs.
--   (c) LIT, THE SAME SALE: the same answer, event and ledger; the flows are the dark flows less IMPORT_DEMAND
--       alone (SELL is the whole total: the purse paid it all).
--   (d) A PURSE OF EXACTLY THE BASE (round(total / haul)): dark, all 40 t sell (0174's rule, unchanged); lit,
--       the lot shrinks — fewer than 40 t, more than none, its whole total within the purse.
--   (e) city_day at a moment three hours ahead (every harbour has a game-day to earn; nothing depends on the
--       hour of day), the probe harbour's purse emptied: dark, it posts EARNINGS at the probe harbour (the
--       positive control); lit, it posts NO EARNINGS anywhere.
--   (f) city_sell_outflow at the probe harbour, a probe IMPORT_DEMAND of 400 kept yesterday: dark it equals
--       −(SELL + IMPORT_DEMAND) per day kept, lit −SELL per day kept — each compared with its own definition in
--       ONE statement — and lit is above dark.
--   No table that grows on production is counted against a remembered figure; nothing is DELETEd from an
--   append-only table; no `set role`.
-- ROLLBACK (forward): reverse the three hunks (each OLD text is here verbatim).
-- VERSION: 0233 (numbered by the coordinator: 0231 and 0232 deploy first; neither touches these bodies).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '5min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('public.economy_closed()') is null or to_regclass('public.capital_gifts') is null then
    raise exception '0233 refuses: 0228 (E1, the books say what moves) is not in this world';
  end if;
  if to_regprocedure('public.cargo_haul(uuid,uuid)') is null or to_regprocedure('public.city_day(timestamptz)') is null
     or to_regprocedure('public.city_sell_outflow(uuid)') is null or to_regprocedure('cmd.do_sell(uuid,jsonb)') is null then
    raise exception '0233 refuses: 0172 / 0174 (city earnings, the distance premium) is not in this world';
  end if;
  if public.economy_closed() then
    raise exception '0233 refuses: the economy is already closed — this slice ships dark';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0233(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 0. THE PRE-IMAGES (LF-normalised) ───────────────────────────────────────────────────────────
create temp table defs_before_0233 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('public.city_day(timestamptz)'), ('cmd.do_sell(uuid,jsonb)'), ('public.city_sell_outflow(uuid)')) f(fn);

create temp table before_0233 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points;

-- ── 1. THE PROBE'S HARBOUR AND GOOD, and the two rows held still for this transaction ──────────
-- A harbour that prices a light good from afar (haul ≥ 1.5, so the premium is at least a third of a sale) and
-- earns something a day (the city_day control). Its (port, good) row and its purse row are locked to the end of
-- this file's transaction: no live trade, drift or roll moves either between the runs compared below.
create temp table probe_0233 (k text primary key, j jsonb) on commit drop;
insert into probe_0233 (k, j)
select 'pick', jsonb_build_object('port', x.port_id, 'pcode', x.pcode, 'good', x.good_id, 'gcode', x.gcode, 'haul', x.haul,
                                  'mark', (select coalesce(max(f.id), 0) from public.treasury_flows f))
  from (select pg.port_id, p.code as pcode, pg.good_id, g.code as gcode, pg.haul
          from public.port_goods pg
          join public.ports p on p.id = pg.port_id and p.kind = 'HARBOUR'
          join public.goods g on g.id = pg.good_id
          join public.port_treasury t on t.port_id = pg.port_id
         where pg.haul >= 1.5 and g.bulk <= 1 and not public.culture_refuses(p.culture, g.culture_mask)
           and public.city_earnings(pg.port_id) > 0
         order by pg.haul desc, p.code, g.code
         limit 1) x;

do $$
declare
  v jsonb := (select j from probe_0233 where k = 'pick');
begin
  if v is null then
    raise exception '0233 self-assert FAIL: no harbour prices a light good from afar (haul >= 1.5) and earns a day';
  end if;
  perform 1 from public.port_goods pg where pg.port_id = (v->>'port')::uuid and pg.good_id = (v->>'good')::uuid for update;
  perform 1 from public.port_treasury t where t.port_id = (v->>'port')::uuid for update;
end $$;

-- ONE probe sale, in the caller's sub-transaction: a probe house docked at the harbour, 40 t of the good aboard
-- at 1 d. a tun, the city purse lit with its reserve 0 (bid factor 1) and its live balance set to p_purse (null:
-- 50,000,000), then a sale of p_qty. Answers the sale, its SOLD event, the flows it wrote (kind, ducats, by id;
-- the probe's own balance-setting flow left out) and the house's ledger (by kind: its ids are not ordered).
create or replace function pg_temp.sale_0233(p_purse bigint, p_qty int)
returns jsonb
language plpgsql
as $$
declare
  c_uid  constant uuid := '00000000-0233-4000-8000-000000000001';
  v      jsonb := (select j from probe_0233 where k = 'pick');
  v_port uuid := (v->>'port')::uuid;
  v_good uuid := (v->>'good')::uuid;
  v_p    uuid;
  v_f    uuid;
  v_r    jsonb;
  v_err  text;
begin
  if exists (select 1 from public.players p where p.auth_uid = c_uid or p.company_name = 'Casa do Mercado 0233') then
    raise exception '0233 self-assert FAIL: the probe house already exists';
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled';
  update public.port_treasury set reserve = 0 where port_id = v_port;
  v_p := public.new_house(c_uid, 'Casa do Mercado 0233', 'PRT', v->>'pcode');
  select f.id into v_f from public.fleets f where f.player_id = v_p order by f.id limit 1;
  if public.fleet_load(v_f, v->>'gcode', 40, 1) <> 40 then
    raise exception '0233 self-assert FAIL: the probe fleet could not take 40 t of %', v->>'gcode';
  end if;
  if world.daily_cap_remaining(v_p, v_port, v_good) < 40 then
    raise exception '0233 self-assert FAIL: the day''s allowance of % at % is under 40 t for a new house', v->>'gcode', v->>'pcode';
  end if;
  perform public.treasury_post(v_port, 'PROBE_0233', coalesce(p_purse, 50000000) - public.treasury_balance(v_port), null, null);
  begin
    v_r := cmd.do_sell(v_f, jsonb_build_object('good', v_good, 'qty', p_qty));
  exception when others then
    v_err := sqlerrm;
  end;
  return jsonb_build_object(
    'r', v_r, 'err', v_err,
    'event', (select jsonb_agg(e.payload order by e.payload::text) from public.events e where e.player_id = v_p and e.kind = 'SOLD'),
    'flows', coalesce((select jsonb_agg(jsonb_build_array(f.kind, f.ducats) order by f.id) from public.treasury_flows f
                        where f.id > (v->>'mark')::bigint and f.created_at = now() and f.kind <> 'PROBE_0233'), '[]'::jsonb),
    'ledger', (select jsonb_agg(jsonb_build_array(l.kind, l.ducats_delta, l.balance_after) order by l.kind, l.ducats_delta)
                 from public.ledger l where l.player_id = v_p));
end $$;

-- ── 2. THE DARK SALE ON THE PRE-IMAGE (the body as it stood before this file), rolled back ─────
do $$
declare
  v_out jsonb;
begin
  begin
    raise exception using errcode = 'ZX233', message = pg_temp.sale_0233(null, 40)::text;
  exception when sqlstate 'ZX233' then
    v_out := sqlerrm::jsonb;
  end;
  if v_out->'r' is null then
    raise exception '0233 self-assert FAIL: the pre-image''s probe sale was refused: %', v_out->>'err';
  end if;
  insert into probe_0233 values ('pre', v_out);
end $$;

-- ── 3. THE HUNKS (each occurs exactly once in the live body) ─────────────────────────────────────
create temp table hunks_0233 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0233 values
('public.city_day(timestamptz)', 1,
$h$    if v_e > 0 then
      perform public.treasury_post(r.port_id, 'EARNINGS', v_e, null, null);
$h$,
$h$    if v_e > 0 and not public.economy_closed() then   -- 0233 (E3): closed, no city is paid by nobody
      perform public.treasury_post(r.port_id, 'EARNINGS', v_e, null, null);
$h$),
('cmd.do_sell(uuid,jsonb)', 1,
$h$    -- 0174: the purse pays the BASE of a sale, round(total / haul); the city's people pay the rest.
    v_haul := public.cargo_haul(f.port_id, g.id);
$h$,
$h$    -- 0174: the purse pays the BASE of a sale, round(total / haul); the city's people pay the rest.
    v_haul := public.cargo_haul(f.port_id, g.id);
    -- 0233 (E3): closed, nobody else pays — the purse pays the WHOLE total: the shrink and the refusal below judge
    -- it whole, and the premium (IMPORT_DEMAND, total − round(total / 1)) is 0 and not posted. The price is untouched.
    if public.economy_closed() then v_haul := 1; end if;
$h$),
('public.city_sell_outflow(uuid)', 1,
$h$  select coalesce(round(-sum(d.ducats) filter (where d.kind in ('SELL', 'IMPORT_DEMAND'))
$h$,
$h$  -- 0233 (E3): closed, the purse pays a sale whole (no IMPORT_DEMAND), so SELL is counted whole.
  select coalesce(round(-sum(d.ducats) filter (where d.kind = 'SELL' or (d.kind = 'IMPORT_DEMAND' and not public.economy_closed()))
$h$);

create or replace function pg_temp.recut_0233(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := (select def from defs_before_0233 where fn = p_fn);
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0233 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0233(v_def, h.old);
    if v_n <> 1 then
      raise exception '0233 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0233(fn) from defs_before_0233 order by fn;

-- ── 4. THE SELF-ASSERT ──────────────────────────────────────────────────────────────────────────
do $$
declare
  v_before record;
  v_d record; v_h record; v_pp record; v_def text;
  v        jsonb := (select j from probe_0233 where k = 'pick');
  v_port   uuid := (v->>'port')::uuid;
  v_pre    jsonb := (select j from probe_0233 where k = 'pre');
  v_dark   jsonb; v_lit jsonb; v_bd jsonb; v_bl jsonb;
  v_base   bigint;
  v_less   jsonb;
  v_dem    bigint;
  v_t      timestamptz := now() + interval '3 hours';
  v_e      jsonb;
  v_ok     boolean;
  v_so     jsonb;
begin
  select * into v_before from before_0233;

  -- (a) THE RE-CUTS reverse to their pre-images; ACL / volatility / definer / config unmoved
  for v_d in select * from defs_before_0233 loop
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    for v_h in select * from hunks_0233 where fn = v_d.fn order by n desc loop
      if pg_temp.occurs_0233(v_def, v_h.new) <> 1 then
        raise exception '0233 self-assert FAIL: hunk % of % is not in the new body exactly once', v_h.n, v_d.fn;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0233 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg
      into v_pp from pg_proc p where p.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0233 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;
  if (select count(*) from public.client_rpc_entry_points()) <> v_before.entry_points then
    raise exception '0233 self-assert FAIL: the registry moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0233 self-assert FAIL: a wall moved';
  end if;

  -- (b) THE SALE, BYTE FOR BYTE DARK: the new body against the pre-image's run
  begin
    raise exception using errcode = 'ZX233', message = pg_temp.sale_0233(null, 40)::text;
  exception when sqlstate 'ZX233' then
    v_dark := sqlerrm::jsonb;
  end;
  if v_dark is distinct from v_pre then
    raise exception '0233 self-assert FAIL: dark, the probe sale is not what the pre-image did: pre %, now %', v_pre, v_dark;
  end if;
  select coalesce(sum((x->>1)::bigint), 0) into v_dem from jsonb_array_elements(v_dark->'flows') x where x->>0 = 'IMPORT_DEMAND';
  if v_dem <= 0 or (v_dark->'r'->>'qty')::numeric <> 40
     or not exists (select 1 from jsonb_array_elements(v_dark->'flows') x where x->>0 = 'SELL' and (x->>1)::bigint = -(v_dark->'r'->>'total')::bigint) then
    raise exception '0233 self-assert FAIL: the dark probe did not exercise the premium path (IMPORT_DEMAND %, sale %)', v_dem, v_dark->'r';
  end if;

  -- (c) LIT, THE SAME SALE: no IMPORT_DEMAND, everything else as dark
  begin
    update public.world_config set value = 'true'::jsonb where key = 'economy_closed';
    raise exception using errcode = 'ZX233', message = pg_temp.sale_0233(null, 40)::text;
  exception when sqlstate 'ZX233' then
    v_lit := sqlerrm::jsonb;
  end;
  select coalesce(jsonb_agg(x order by o), '[]'::jsonb) into v_less
    from jsonb_array_elements(v_dark->'flows') with ordinality t(x, o) where x->>0 <> 'IMPORT_DEMAND';
  if v_lit->'r' is distinct from v_dark->'r' or v_lit->'event' is distinct from v_dark->'event'
     or v_lit->'ledger' is distinct from v_dark->'ledger' or v_lit->'flows' is distinct from v_less then
    raise exception '0233 self-assert FAIL: lit, the sale is not the dark sale less its IMPORT_DEMAND: dark %, lit %', v_dark, v_lit;
  end if;
  if public.economy_closed() then
    raise exception '0233 self-assert FAIL: the lit probe did not roll back (economy_closed is true)';
  end if;

  -- (d) A PURSE OF EXACTLY THE BASE: dark all 40 t sell; lit the lot shrinks to what the purse covers whole
  v_base := (v_dark->'r'->>'total')::bigint - v_dem;
  begin
    raise exception using errcode = 'ZX233', message = pg_temp.sale_0233(v_base, 40)::text;
  exception when sqlstate 'ZX233' then
    v_bd := sqlerrm::jsonb;
  end;
  begin
    update public.world_config set value = 'true'::jsonb where key = 'economy_closed';
    raise exception using errcode = 'ZX233', message = pg_temp.sale_0233(v_base, 40)::text;
  exception when sqlstate 'ZX233' then
    v_bl := sqlerrm::jsonb;
  end;
  if v_bd->'r' is null or (v_bd->'r'->>'qty')::numeric <> 40 then
    raise exception '0233 self-assert FAIL: dark, a purse of the base % did not take all 40 t: %', v_base, v_bd;
  end if;
  if v_bl->'r' is null or (v_bl->'r'->>'qty')::numeric >= 40 or (v_bl->'r'->>'qty')::numeric <= 0
     or (v_bl->'r'->>'total')::bigint > v_base
     or exists (select 1 from jsonb_array_elements(v_bl->'flows') x where x->>0 = 'IMPORT_DEMAND') then
    raise exception '0233 self-assert FAIL: lit, a purse of the base % did not shrink the lot to its whole total: %', v_base, v_bl;
  end if;

  -- (e) city_day: dark the probe harbour (emptied) earns; lit no harbour earns
  begin
    update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled';
    perform public.treasury_post(v_port, 'PROBE_0233', -public.treasury_balance(v_port), null, null);
    perform public.city_day(v_t);
    raise exception using errcode = 'ZX233', message = jsonb_build_object(
      'here', (select count(*) from public.treasury_flows f where f.id > (v->>'mark')::bigint and f.created_at = now()
                  and f.kind = 'EARNINGS' and f.port_id = v_port and f.ducats > 0))::text;
  exception when sqlstate 'ZX233' then
    v_e := sqlerrm::jsonb;
  end;
  if (v_e->>'here')::int <> 1 then
    raise exception '0233 self-assert FAIL: dark, city_day did not pay the emptied probe harbour its EARNINGS (the positive control): %', v_e;
  end if;
  begin
    update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed');
    perform public.treasury_post(v_port, 'PROBE_0233', -public.treasury_balance(v_port), null, null);
    perform public.city_day(v_t);
    raise exception using errcode = 'ZX233', message = jsonb_build_object(
      'any', (select count(*) from public.treasury_flows f where f.id > (v->>'mark')::bigint and f.created_at = now()
                 and f.kind = 'EARNINGS'))::text;
  exception when sqlstate 'ZX233' then
    v_e := v_e || sqlerrm::jsonb;
  end;
  if (v_e->>'any')::int <> 0 then
    raise exception '0233 self-assert FAIL: lit, city_day posted EARNINGS: %', v_e;
  end if;

  -- (f) city_sell_outflow: dark net of IMPORT_DEMAND, lit SELL whole — each against its own definition in one statement
  begin
    update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled';
    insert into public.treasury_daybook (port_id, game_day, kind, ducats) values
      (v_port, world.game_day() - 1, 'SELL', -1000), (v_port, world.game_day() - 1, 'IMPORT_DEMAND', 400)
    on conflict (port_id, game_day, kind) do update set ducats = public.treasury_daybook.ducats + excluded.ducats;
    select jsonb_build_object('dark', public.city_sell_outflow(v_port), 'ok_dark', public.city_sell_outflow(v_port) = x.both)
      into v_so
      from (select coalesce(round(-sum(d.ducats) filter (where d.kind in ('SELL', 'IMPORT_DEMAND')) / nullif(count(distinct d.game_day), 0)), 0)::bigint as both
              from public.treasury_daybook d
             where d.port_id = v_port and d.kind <> 'CARRIED'
               and d.game_day >= world.game_day() - public.wc_int('treasury_days_kept') and d.game_day < world.game_day()) x;
    update public.world_config set value = 'true'::jsonb where key = 'economy_closed';
    select v_so || jsonb_build_object('lit', public.city_sell_outflow(v_port), 'ok_lit', public.city_sell_outflow(v_port) = x.sell)
      into v_so
      from (select coalesce(round(-sum(d.ducats) filter (where d.kind = 'SELL') / nullif(count(distinct d.game_day), 0)), 0)::bigint as sell
              from public.treasury_daybook d
             where d.port_id = v_port and d.kind <> 'CARRIED'
               and d.game_day >= world.game_day() - public.wc_int('treasury_days_kept') and d.game_day < world.game_day()) x;
    raise exception using errcode = 'ZX233', message = v_so::text;
  exception when sqlstate 'ZX233' then
    v_so := sqlerrm::jsonb;
  end;
  if not (v_so->>'ok_dark')::boolean or not (v_so->>'ok_lit')::boolean or (v_so->>'lit')::bigint <= (v_so->>'dark')::bigint then
    raise exception '0233 self-assert FAIL: city_sell_outflow is not net of IMPORT_DEMAND dark and SELL whole lit: %', v_so;
  end if;

  -- nothing of the probe survives
  if exists (select 1 from public.players p where p.auth_uid = '00000000-0233-4000-8000-000000000001')
     or exists (select 1 from public.treasury_flows f where f.id > (v->>'mark')::bigint and f.created_at = now())
     or public.economy_closed() then
    raise exception '0233 self-assert FAIL: the probe left rows behind';
  end if;

  raise notice '0233 self-assert ok: NO CITY IS PAID BY NOBODY. city_day, cmd.do_sell, city_sell_outflow re-cut by one hunk each, each reversed, ACL unmoved; registry unchanged; walls 0. Probe at % (%, haul %): DARK the sale of 40 t is the pre-image''s byte for byte (answer, event, % flows, ledger; total %, IMPORT_DEMAND %); LIT the same sale less its IMPORT_DEMAND (SELL whole). A purse of the base %: dark 40 t sold, lit % t for % (shrunk on the whole total). city_day 3 h ahead: dark EARNINGS at the emptied probe harbour, lit none anywhere. city_sell_outflow dark % / lit %. Rolled back.',
    v->>'pcode', v->>'gcode', v->>'haul', jsonb_array_length(v_dark->'flows'), v_dark->'r'->>'total', v_dem,
    v_base, v_bl->'r'->>'qty', v_bl->'r'->>'total', v_so->>'dark', v_so->>'lit';
end $$;
