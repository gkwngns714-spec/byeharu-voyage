-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0283 — A HULL STARTS AT HER ROLLED MAX   (commission_ship stored the fractional product; ship_base floors it)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- THE ROOT, proven in CI today and read on prod. public.commission_ship (re-cut by 0276,
-- 20260818000276_every_new_ship_rolls_her_own.sql:460-464) inserts a new hull's durability as
--     c.durability * (v_roll->>'durability')::numeric,
-- the EXACT product — a numeric with a fractional part whenever the md5-derived roll's third decimal
-- is not a multiple of 0.005 for an integer class durability. public.ship_base(ship) — the ONE
-- authority for her max (0276:377-397) — returns
--     floor(c.durability * s.roll_hull)
-- so such a hull starts ABOVE her own max. CI, two runs on main 2026-10-30, measured
-- tests/rpc.surface.spec.ts:460 (expect(s.durability).toBe(s.max_durability)) red with durability
-- 405.6 against max_durability 405, and 469.2 against 469.
--
-- PROD MEASUREMENT (read-only, 2026-10-30, head 20260818000282): 917 ships; every roll_hull = 1.000;
-- 0 ships stand above her max; 103 stand below it from wear (durability < ship_base). The defect is
-- therefore LATENT in today's world and guaranteed for the next hull whose roll product is
-- fractional. Design: docs/SHIP_STORES_AND_VARIETY.md §2.2 — a hull's starting durability IS her
-- rolled max.
--
-- THE FIX: ONE change in ONE function. In public.commission_ship the insert's durability expression
-- gains floor():
--     floor(c.durability * (v_roll->>'durability')::numeric),
-- so the stored starting durability IS public.ship_base's answer, to the digit. The old line and the
-- new line differ by exactly the `floor(` prefix and the closing `)`.
--
-- WHAT MOVES: public.commission_ship(uuid,uuid,text,text,boolean,boolean,uuid) — its one ship insert.
-- WHAT DOES NOT MOVE: public.ship_base (the authority; untouched); every other function in public,
-- cmd, world and voyage (one md5 over the lot); the function's ACL, volatility (volatile), SECURITY
-- DEFINER, search_path (public, pg_temp); no table, no row, no grant, no knob, no switch, no client.
-- No existing ship is touched: every hull afloat carries roll_hull = 1.000, and for her the product
-- and its floor are the same integer.
--
-- SUPERSEDE (supabase/migrations/README.md:43-48). This file re-cuts ONE live function, by ONE exact
-- substring replacement in its live pg_get_functiondef text (the old substring is asserted to occur
-- exactly once and the new one zero times; the resulting body is asserted equal, by md5, to the live
-- body with only that substitution; ACL / volatility / definer / config and every other function's
-- md5 are asserted unmoved):
--   * public.commission_ship(uuid, uuid, text, text, boolean, boolean, uuid) — 0276's body, never
--     re-cut since (live md5 43640ad5239e5c93ef138945f58a3363, read on prod 2026-10-30). Its one
--     insert line gains floor().
-- A no-op for every hull whose roll product is a whole number (every roll 1.000 hull, every famous
-- hull, and the whole-product neighbours of a fractional one); it changes only a hull whose product
-- is fractional, which is exactly the hull the CI red named.
--
-- PROD CHECKS (before the push; read-only; in the PR body): head = 20260818000282; the live
-- commission_ship body md5 = 43640ad5239e5c93ef138945f58a3363 and it contains the unfloored product
-- exactly once and the floored one zero times; its ACL is {postgres=X/postgres,service_role=X/postgres},
-- volatility volatile, SECURITY DEFINER, search_path public, pg_temp; public.ship_base's body md5 =
-- dc62cd9737495b8565ad5cbf4c13414d (volatility stable — untouched); 917 ships, every roll_hull 1.000,
-- 0 above her max. AFTER THE DEPLOY: no existing ship moves; the next hull commissioned with a
-- fractional roll stores floor(class × roll) = her ship_base durability (the self-assert's probe
-- proves the same path through the real door). A forward rollback (a new migration restoring the
-- product) is in docs/dev-log/2026-10-30-hull-starts-at-her-max.md.
--
-- VERSION: 0283 (prod head 0282).

-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('public.commission_ship(uuid,uuid,text,text,boolean,boolean,uuid)') is null
     or to_regprocedure('public.ship_base(uuid)') is null then
    raise exception '0283 refuses: 0276 is not in this world';
  end if;
  if replace(pg_get_functiondef('public.commission_ship(uuid,uuid,text,text,boolean,boolean,uuid)'::regprocedure), E'\r', '')
     like '%floor(c.durability * (v_roll->>''durability'')%' then
    raise exception '0283 refuses: commission_ship already floors her starting durability — this has been applied once';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0283(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 0. AS FOUND ─────────────────────────────────────────────────────────────────────────────────
create temp table defs_before_0283 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       md5(replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '')) as md5,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('public.commission_ship(uuid,uuid,text,text,boolean,boolean,uuid)')) f(fn);

-- EVERY function in the four schemas except the one this file re-cuts: one md5 over the lot, so a
-- body that moves without being named here is caught — ship_base included by construction.
create temp table before_0283 on commit drop as
select (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
           and p.oid <> 'public.commission_ship(uuid,uuid,text,text,boolean,boolean,uuid)'::regprocedure) as fns,
       (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
           and p.oid <> 'public.commission_ship(uuid,uuid,text,text,boolean,boolean,uuid)'::regprocedure) as others_md5;

-- ── 1. THE ONE SUBSTITUTION, EXECUTED ───────────────────────────────────────────────────────────
do $$
declare
  v_old      text := 'c.durability * (v_roll->>''durability'')::numeric,';
  v_new      text := 'floor(c.durability * (v_roll->>''durability'')::numeric),';
  v_def      text;
  v_expected text;
  v_after    text;
  v_n        int;
  v_p        record;
begin
  select def into v_def from defs_before_0283;
  v_n := pg_temp.occurs_0283(v_def, v_old);
  if v_n <> 1 then
    raise exception '0283 self-assert FAIL: the unfloored product occurs % time(s) in the live commission_ship, not once — the live body is not the one this file was cut against', v_n;
  end if;
  v_n := pg_temp.occurs_0283(v_def, v_new);
  if v_n <> 0 then
    raise exception '0283 self-assert FAIL: the floored product is already in the live commission_ship (% occurrence(s)) — this has been applied once', v_n;
  end if;

  v_expected := replace(v_def, v_old, v_new);
  execute v_expected;

  select replace(pg_get_functiondef('public.commission_ship(uuid,uuid,text,text,boolean,boolean,uuid)'::regprocedure), E'\r', '')
    into v_after;
  if v_after is distinct from v_expected or md5(v_after) is distinct from md5(v_expected) then
    raise exception '0283 self-assert FAIL: the new body is not the live body with only the one substitution (md5 % vs %)', md5(v_after), md5(v_expected);
  end if;
  if pg_temp.occurs_0283(v_after, v_new) <> 1 then
    raise exception '0283 self-assert FAIL: the floored product is not in the new body exactly once';
  end if;

  select p.proacl::text as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg
    into v_p from pg_proc p
   where p.oid = 'public.commission_ship(uuid,uuid,text,text,boolean,boolean,uuid)'::regprocedure;
  if coalesce(v_p.acl, '') is distinct from (select acl from defs_before_0283)
     or v_p.vol is distinct from (select vol from defs_before_0283)
     or v_p.secdef is distinct from (select secdef from defs_before_0283)
     or v_p.cfg is distinct from (select cfg from defs_before_0283) then
    raise exception '0283 self-assert FAIL: the re-cut moved commission_ship''s ACL, volatility, definer or config';
  end if;

  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> 'public.commission_ship(uuid,uuid,text,text,boolean,boolean,uuid)'::regprocedure)
     is distinct from (select fns from before_0283) then
    raise exception '0283 self-assert FAIL: the four schemas gained or lost a function';
  end if;
  if (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> 'public.commission_ship(uuid,uuid,text,text,boolean,boolean,uuid)'::regprocedure)
     is distinct from (select others_md5 from before_0283) then
    raise exception '0283 self-assert FAIL: a function this file does not re-cut moved (the bodies'' own authorities included)';
  end if;
end $$;

-- ── 2. THE ROLLED-BACK PROBE ───────────────────────────────────────────────────────────────────
do $$
declare
  c_player   constant uuid := '00000000-0283-4000-8000-000000000001';
  c_prefix   constant text := '00000000-0283-4000-8000-';
  v_class    public.ship_classes%rowtype;
  v_roll     jsonb;
  v_prod     numeric;
  v_ship     uuid;
  v_made     uuid;
  v_player   uuid;
  v_fleet    uuid;
  v_stored   numeric;
  v_roll_hull numeric;
  v_base     numeric;
  v_i        int;
  v_found    boolean := false;
  v_after_md5 text;
begin
  select * into v_class from public.ship_classes where code = 'barca';
  if v_class.id is null or v_class.durability is null or v_class.durability <= 0 then
    raise exception '0283 self-assert FAIL: the world has no barca hull (positive control) — the probe proves nothing';
  end if;

  -- THE RE-CUT'S OWN MD5, read after section 1 executed it (the receipt names both ends of the
  -- substitution).
  select md5(replace(pg_get_functiondef('public.commission_ship(uuid,uuid,text,text,boolean,boolean,uuid)'::regprocedure), E'\r', ''))
    into v_after_md5;

  -- A FIXED SEED WHOSE PRODUCT IS FRACTIONAL: the roll is md5 of the ship id, so this search is
  -- deterministic and the same id answers the same factors on every machine. If 50 fixed seeds all
  -- came out whole the probe would be vacuous, so it raises instead of passing.
  for v_i in 1..50 loop
    v_ship := (c_prefix || lpad(to_hex(v_i), 12, '0'))::uuid;
    v_roll := public.ship_roll(v_ship, v_class.code);
    v_prod := v_class.durability * (v_roll->>'durability')::numeric;
    if v_prod <> floor(v_prod) then
      v_found := true;
      exit;
    end if;
  end loop;
  if not v_found then
    raise exception '0283 self-assert FAIL: 50 fixed barca seeds produced no fractional product — the probe cannot show the defect';
  end if;

  -- THE SUBTRANSACTION, ROLLED BACK BY THE SENTINEL: a throwaway player, fleet and hull through the
  -- real doors (public.form_fleet, public.commission_ship).
  begin
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
    values (c_player, 'Casa da Prova 0283', (select id from public.nations where code = 'PRT'), 0, false)
    returning id into v_player;
    v_fleet := public.form_fleet(v_player, 'Prova 0283', (select id from public.ports where code = 'LIS'));
    v_made := public.commission_ship(v_player, v_fleet, v_class.code, 'Prova 0283', false, false, v_ship);
    if v_made is distinct from v_ship then
      raise exception '0283 self-assert FAIL: commission_ship returned % rather than the probe''s fixed id %', v_made, v_ship;
    end if;

    select s.durability, s.roll_hull into v_stored, v_roll_hull
      from public.ships s where s.id = v_ship;
    if not found then
      raise exception '0283 self-assert FAIL: commission_ship inserted no ship %', v_ship;
    end if;
    select sb.durability into v_base from public.ship_base(v_ship) sb;
    if not found then
      raise exception '0283 self-assert FAIL: public.ship_base answered no row for the probe hull %', v_ship;
    end if;

    if v_roll_hull is distinct from (v_roll->>'durability')::numeric then
      raise exception '0283 self-assert FAIL: the stored roll_hull % is not the roll this probe computed (%)', v_roll_hull, v_roll->>'durability';
    end if;
    if v_stored is distinct from floor(v_prod) then
      raise exception '0283 self-assert FAIL: the stored durability % is not floor(class x roll) % (the pre-fix body stored the product)', v_stored, floor(v_prod);
    end if;
    if v_stored is distinct from v_base then
      raise exception '0283 self-assert FAIL: the stored durability % is not ship_base''s answer %', v_stored, v_base;
    end if;
    -- THE ASSERT CAN FAIL: the product this file removes was strictly above the floored value, so the
    -- old body would have stored a hull above her own max — the CI red, reproduced on one hull.
    if v_prod is null or v_prod <= v_stored then
      raise exception '0283 self-assert FAIL: the probe''s product % is not above the floored value % — the case cannot show the defect', v_prod, v_stored;
    end if;

    raise exception using errcode = 'ZX283', message = 'probe ok';
  exception when sqlstate 'ZX283' then
    null;
  end;

  -- THE PROBE LEFT NOTHING BEHIND (its own ids only; never a count or sum of a live table).
  if exists (select 1 from public.players where auth_uid = c_player)
     or exists (select 1 from public.ships where id = v_ship)
     or exists (select 1 from public.fleets where player_id = v_player) then
    raise exception '0283 self-assert FAIL: the rolled-back probe left a row behind';
  end if;

  raise notice '0283 self-assert ok: A HULL STARTS AT HER ROLLED MAX. public.commission_ship''s one insert now stores floor(c.durability * her roll) — the exact answer public.ship_base gives — and nothing else moved: the body equals its pre-image with only that one substitution (as found md5 %, new md5 %), ACL / volatility / definer / config unmoved, and every other function in public/cmd/world/voyage unmoved by md5 (%, functions). Probe, rolled back: barca seed % rolled durability %, product % (fractional) — the pre-fix product was above the floored value; commissioned through the real door, the hull stores % = ship_base''s % = floor(product); no probe row survived. Prod 2026-10-30 (head 0282): 917 ships, every roll_hull 1.000, 0 above her max — latent then, fixed for the next fractional roll.',
    (select md5 from defs_before_0283), v_after_md5, (select fns from before_0283), v_ship,
    (v_roll->>'durability'), v_prod, v_stored, v_base;
end $$;
