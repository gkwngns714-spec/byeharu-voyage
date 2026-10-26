-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0236 — THE GIFT READS HER CASH
--        (a fix to slice E4 of docs/CLOSED_ECONOMY.md, 0234: a merchant company is BROKE — and so is given her
--         starting money by her country's capital — when her PURSE (cash) is under 20 % of her capital. 0234 read
--         her WORTH (purse + cargo at cost), so a house with an empty purse and a full hold was never gifted.
--         DARK: the pass answers null while the economy is open, before and after — nothing moves.)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER (docs/OWNER_REQUESTS.md rows 212, 215) ────────────────────────────────────────────
--   "broke merchants will receive donation (starting money) from their capital city". DECIDED BY DEFAULT (the owner
--   may reverse): broke = her PURSE under merchant_broke_pct (0.2) × her capital — the same figure E2's Stats line
--   "Broke merchants" counts (0229), so the line and the gift agree. Measured on prod 2026-10-26 (head 0231): 41
--   houses broke by purse, 0 by worth — 0234 lit would have given no gift at all.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
--   public.capital_gift_pass ×1 hunk: the worth test is dropped; the purse test (already the cheap first test) is the
--   rule. Her worth still orders the pass (poorest first, after gifted-longest-ago) and is still in the event.
--   Nothing else moves: the amount (her capital), the cooldowns, the payer (capital_pays), the reads.
--
-- ── HUNK SLICED FROM THE LIVE BODY (prod head 0234, LF-normalised; asserted to occur exactly once and to reverse to
--    its pre-image; ACL / volatility / definer / config unchanged) ──────────────────────────────────────────────
--
-- ── WHAT IT SELF-ASSERTS (a probe merchant company only; every probe in a sub-transaction, rolled back, asserted) ──
--   (a) the hunk reverses; ACL / volatility / definer / config unmoved; registry unchanged; walls 0.
--   (b) LIT, A FULL HOLD AND AN EMPTY PURSE: a probe merchant of Portugal (capital 5,000, purse 500, 10,000 of cargo
--       at cost aboard: worth 10,500) — the PRE-IMAGE (a pg_temp copy of 0234's body) gives no gift; THIS body gives
--       one of 5,000 (purse 5,500, CAPITAL_GIFT −5,000 at Lisbon).
--   (c) LIT, A FULL PURSE: the same house with a purse of 1,000 (= 20 %, not under it) → no gift.
--   (d) DARK: the pass answers null.
--   No table that grows on production is counted or summed against a remembered figure (flows are read above a mark
--   taken in-block AND at this transaction's now()); nothing is DELETEd from an append-only table; no `set role`;
--   npc_tend_houses is never RUN here (the pass is called for the probe company alone); nothing reads the hour.
-- ROLLBACK (forward): put the line `       and w.worth < h.capital * v_pct` back (the OLD text is below, verbatim).
-- VERSION: 0236 (0235 is reserved by the coordinator for a slice in flight; 0237 = E4b follows).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '5min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('public.capital_gift_pass(timestamptz,uuid)') is null or to_regprocedure('public.npc_worth(uuid)') is null then
    raise exception '0236 refuses: 0234 (E4) is not in this world';
  end if;
  if public.economy_closed() then
    raise exception '0236 refuses: the economy is already closed — this fix ships dark';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0236(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 0. THE PRE-IMAGE (LF-normalised), and a copy of it to compare against ───────────────────────
create temp table defs_before_0236 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('public.capital_gift_pass(timestamptz,uuid)')) f(fn);

create temp table before_0236 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points;

do $$
declare
  v_def text := (select def from defs_before_0236);
begin
  if pg_temp.occurs_0236(v_def, 'FUNCTION public.capital_gift_pass(') <> 1 then
    raise exception '0236 self-assert FAIL: capital_gift_pass''s definition does not name itself once';
  end if;
  execute replace(v_def, 'FUNCTION public.capital_gift_pass(', 'FUNCTION pg_temp.capital_gift_pass_old_0236(');
end $$;

-- ── 1. THE HUNK (occurs exactly once in the live body) ──────────────────────────────────────────
create temp table hunks_0236 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0236 values
('public.capital_gift_pass(timestamptz,uuid)', 1,
$h$       and pl.ducats < h.capital * v_pct               -- her purse alone is under the line (worth ≥ purse): the cheap test first
       and w.worth < h.capital * v_pct
$h$,
$h$       and pl.ducats < h.capital * v_pct               -- 0236: BROKE = her purse (cash) under the line; cargo aboard does not count
$h$);

do $$
declare
  v_def text := (select def from defs_before_0236);
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0236 order by n loop
    v_n := pg_temp.occurs_0236(v_def, h.old);
    if v_n <> 1 then
      raise exception '0236 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, h.fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

-- ── 2. THE PROBE'S TOOLS ────────────────────────────────────────────────────────────────────────
create or replace function pg_temp.above_0236(p_port uuid, p_above bigint)
returns void
language plpgsql
as $$
begin
  perform public.treasury_post(p_port, 'PROBE_0236',
    coalesce((select t.reserve from public.port_treasury t where t.port_id = p_port), 0) + p_above - public.treasury_balance(p_port),
    null, null);
end $$;

-- A probe merchant company of Portugal at Lisbon (capital 5,000, purse p_purse) with 10,000 of cargo at cost aboard.
create or replace function pg_temp.merchant_0236(p_purse bigint)
returns uuid
language plpgsql
as $$
declare
  v_m    uuid;
  v_good text := (select g.code from public.goods g order by g.code limit 1);
begin
  if exists (select 1 from public.players p where p.company_name = 'Casa do Porão 0236') then
    raise exception '0236 self-assert FAIL: the probe house already exists';
  end if;
  v_m := public.new_house(null, 'Casa do Porão 0236', 'PRT', 'LIS', p_ducats => p_purse, p_is_npc => true);
  insert into public.npc_houses (player_id, roster_ord, ink, blurb, master, home_port_id, capital, patience, wares)
  values (v_m, (select coalesce(max(h.roster_ord), 0) + 1 from public.npc_houses h), 'prt',
          'A probe house of 0236, rolled back.', 'Mestre da Prova', (select p.id from public.ports p where p.code = 'LIS'),
          5000, 0.1, '{}');
  update public.ships s set cargo = jsonb_build_object(v_good, 100), cargo_basis = jsonb_build_object(v_good, 100)
   where s.fleet_id = (select f.id from public.fleets f where f.player_id = v_m order by f.id limit 1);
  -- her merchant fleet (npc_worth counts the holds of the fleets the roster keeps for her)
  insert into public.npc_fleets (fleet_id, player_id, roster_ord)
  select f.id, v_m, (select coalesce(max(n.roster_ord), 0) + 1 from public.npc_fleets n)
    from public.fleets f where f.player_id = v_m order by f.id limit 1;
  return v_m;
end $$;

-- ── 3. THE SELF-ASSERT ──────────────────────────────────────────────────────────────────────────
do $$
declare
  v_before record;
  v_d record; v_h record; v_pp record; v_def text;
  v_mark   bigint := (select coalesce(max(f.id), 0) from public.treasury_flows f);
  v_lis    uuid := (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR');
  v_m      uuid;
  v_s      jsonb;
begin
  select * into v_before from before_0236;

  -- (a) THE RE-CUT reverses to its pre-image; ACL / volatility / definer / config unmoved
  for v_d in select * from defs_before_0236 loop
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    for v_h in select * from hunks_0236 where fn = v_d.fn order by n desc loop
      if pg_temp.occurs_0236(v_def, v_h.new) <> 1 then
        raise exception '0236 self-assert FAIL: hunk % of % is not in the new body exactly once', v_h.n, v_d.fn;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0236 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg
      into v_pp from pg_proc p where p.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0236 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;
  if (select count(*) from public.client_rpc_entry_points()) <> v_before.entry_points then
    raise exception '0236 self-assert FAIL: the registry moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0236 self-assert FAIL: a wall moved';
  end if;
  if v_lis is null then
    raise exception '0236 self-assert FAIL: no Lisbon';
  end if;

  -- (b) LIT, A FULL HOLD AND AN EMPTY PURSE: the pre-image gives nothing, this body gives her capital
  begin
    update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed', 'npc_traders_enabled', 'standing_routes_enabled');
    perform pg_temp.above_0236(v_lis, 1000000);
    v_m := pg_temp.merchant_0236(500);
    begin   -- the pre-image, in its own rolled-back block (a gift it gave would start the cooldown)
      raise exception using errcode = 'ZY236', message = jsonb_build_object('old', pg_temp.capital_gift_pass_old_0236(now(), v_m))::text;
    exception when sqlstate 'ZY236' then
      v_s := sqlerrm::jsonb;
    end;
    v_s := v_s || jsonb_build_object('worth', public.npc_worth(v_m));
    v_s := v_s || jsonb_build_object('new', public.capital_gift_pass(now(), v_m));
    raise exception using errcode = 'ZX236', message = (v_s || jsonb_build_object(
      'purse', (select pl.ducats from public.players pl where pl.id = v_m),
      'flows', (select coalesce(jsonb_agg(jsonb_build_array(p.code, f.kind, f.ducats) order by f.id), '[]'::jsonb)
                  from public.treasury_flows f join public.ports p on p.id = f.port_id
                 where f.id > v_mark and f.created_at = now() and f.kind = 'CAPITAL_GIFT')))::text;
  exception when sqlstate 'ZX236' then
    v_s := sqlerrm::jsonb;
  end;
  if (v_s->>'worth')::bigint <> 10500 or (v_s->'old'->>'gifted')::int <> 0 or (v_s->'new'->>'gifted')::int <> 1
     or (v_s->'new'->>'gift_ducats')::bigint <> 5000 or (v_s->>'purse')::bigint <> 5500
     or v_s->'flows' <> '[["LIS", "CAPITAL_GIFT", -5000]]'::jsonb then
    raise exception '0236 self-assert FAIL: lit, a house of purse 500 and worth 10,500 was not gifted by her cash (or the pre-image gifted her): %', v_s;
  end if;

  -- (c) LIT, A PURSE AT THE LINE: no gift
  begin
    update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed', 'npc_traders_enabled', 'standing_routes_enabled');
    perform pg_temp.above_0236(v_lis, 1000000);
    v_m := pg_temp.merchant_0236(1000);
    raise exception using errcode = 'ZX236', message = jsonb_build_object('new', public.capital_gift_pass(now(), v_m))::text;
  exception when sqlstate 'ZX236' then
    v_s := sqlerrm::jsonb;
  end;
  if (v_s->'new'->>'gifted')::int <> 0 then
    raise exception '0236 self-assert FAIL: lit, a house whose purse is 20 %% of her capital was gifted: %', v_s;
  end if;

  -- (d) DARK: the pass answers null
  begin
    update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'npc_traders_enabled', 'standing_routes_enabled');
    v_m := pg_temp.merchant_0236(500);
    raise exception using errcode = 'ZX236', message = jsonb_build_object('new', public.capital_gift_pass(now(), v_m))::text;
  exception when sqlstate 'ZX236' then
    v_s := sqlerrm::jsonb;
  end;
  if v_s->'new' <> 'null'::jsonb then
    raise exception '0236 self-assert FAIL: dark, the pass answered %', v_s->'new';
  end if;

  -- nothing of the probe survives
  if exists (select 1 from public.players p where p.company_name = 'Casa do Porão 0236')
     or exists (select 1 from public.treasury_flows f where f.id > v_mark and f.created_at = now())
     or public.economy_closed() then
    raise exception '0236 self-assert FAIL: the probe left rows behind';
  end if;

  raise notice '0236 self-assert ok: THE GIFT READS HER CASH. capital_gift_pass re-cut (1 hunk), reversed, ACL unmoved; registry unchanged; walls 0. LIT: a house of purse 500, cargo 10,000 at cost (worth 10,500), capital 5,000 — 0234''s body gave no gift, this one gave 5,000 from Lisbon; a purse of 1,000 (20 %%) — none. DARK: null. Rolled back.';
end $$;
