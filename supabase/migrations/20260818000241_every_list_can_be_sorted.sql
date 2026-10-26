-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0241 — EVERY LIST CAN BE SORTED
--        (owner row 228: the Stats faces get filters and sorts; the two reads that lacked a field for them gain it)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER (docs/OWNER_REQUESTS.md row 228, 2026-10-26) ─────────────────────────────────────
--   "also create filter for all parts in stats, for example in cities such as by area (continents), or by richest, etc"
--
-- ── WHAT THIS FILE DOES (docs/dev-log/2026-10-26-stats-filters.md) ──────────────────────────────
--   The filters and sorts themselves are the client's (a view the player changes three times in ten seconds, the
--   Markets face's rule since 0214). This file serves the fields they need that no read served:
--   (1) public.region_area(text) — NEW, IMMUTABLE: THE ONE reading of "which part of the world is this region in"
--       (europe, africa, middle_east, india, se_asia, east_asia, americas, oceania). The 25 regions (0003) are the
--       authored unit; the area is a fixed grouping of them, so it is a CASE over the codes, not a column.
--   (2) world.stats_cities() ×2 hunks: every harbour also carries `region` (its region code), `area`
--       (public.region_area), `invested` (Σ city_shares.paid there, every investor), `mine` (the caller has shares
--       there) and `stock` (Σ units in its market, AS OF THE LAST COUNT — summing 139k port_goods rows costs 130–330 ms
--       on prod, too slow for a read asked every second; null until the first count after this file).
--   (3) public.stats_fold_day(bigint) ×1 hunk: the count keeps that `stock` on each city's day row (one sum a count).
--   (4) world.stats_merchants() ×3 hunks: `list` — EVERY merchant company as [name, nation, purse, fleets, day, laps]
--       (an array a row: 821 houses on prod, read every second), purse = her cash now, fleets = the roster's
--       (npc_fleets), day / laps = the same 24 h of laps the board is cut from (0232's stats_merchants_add, now read
--       once into v_d and given to both). Ordered richest first.
--   Nothing is written by any read; the trade path is untouched.
--
-- ── HUNKS SLICED FROM THE LIVE BODIES (prod head 0238, LF-normalised; each asserted to occur exactly once and to
--    reverse to its pre-image; ACL / volatility / definer / config unchanged) ──────────────────────────────────
--
-- ── WHAT IT SELF-ASSERTS (probe rows only; every probe in a sub-transaction, rolled back, asserted) ──
--   (a) the six hunks reverse; ACL / volatility / definer / config unmoved; registry unchanged; walls 0.
--   (b) region_area: every one of the authored regions (a static table) is in exactly one of the eight areas;
--       IBE → europe, JAP → east_asia, PAC → americas; an unknown code → null.
--   (c) THE FOLD: a probe city row for Lisbon at a slot past every real one — after stats_fold_day its day carries
--       `stock` = round(Σ port_goods.stock at Lisbon), read in the same transaction.
--   (d) CITIES: a probe company (a probe JWT subject) with shares at Lisbon reads Lisbon `mine` true, its `invested`
--       ≥ its own paid, `area` europe, `region` IBE; another harbour where it holds nothing reads `mine` false; every
--       served row carries `area` and `region`.
--   (e) MERCHANTS: a probe merchant company appears in `list` once, with its purse and its one roster fleet.
--   No table that grows on production is counted or summed against a remembered figure; nothing is DELETEd from an
--   append-only table; no `set role`; nothing reads the hour.
-- ROLLBACK (forward): put each hunk's OLD text back (verbatim below) and drop public.region_area(text).
-- VERSION: 0241 (prod head 0238; 0239–0240 are other slices in flight; the deploy renumbers).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '5min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('public.stats_fold_day(bigint)') is null or to_regprocedure('public.stats_merchants_add(jsonb,jsonb)') is null then
    raise exception '0241 refuses: 0232 (every figure keeps to the second) is not in this world';
  end if;
  if to_regprocedure('public.region_area(text)') is not null then
    raise exception '0241 refuses: public.region_area(text) already exists';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0241(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 1. THE AREA OF A REGION (one place) ─────────────────────────────────────────────────────────
create function public.region_area(p_region text)
returns text
language sql
immutable
set search_path = public, pg_temp
as $$
  -- 0241 (owner row 228, "by area (continents)"): the part of the world a region (0003's 25 codes) lies in. Decided by
  -- default: the Atlantic Isles and the Aegean, Anatolia & Black Sea count as Europe; Levant & Egypt and Arabia as the
  -- Middle East; the Maghreb as Africa.
  select case p_region
           when 'IBE' then 'europe' when 'ATL' then 'europe' when 'BRI' then 'europe' when 'FRA' then 'europe'
           when 'BAL' then 'europe' when 'SCA' then 'europe' when 'WES' then 'europe' when 'ADR' then 'europe'
           when 'AEG' then 'europe'
           when 'LEV' then 'middle_east' when 'ARA' then 'middle_east'
           when 'MAG' then 'africa' when 'WST' then 'africa' when 'EAS' then 'africa'
           when 'WIA' then 'india' when 'EST' then 'india'
           when 'SOU' then 'se_asia'
           when 'CHI' then 'east_asia' when 'KOR' then 'east_asia' when 'JAP' then 'east_asia'
           when 'CAR' then 'americas' when 'NOR' then 'americas' when 'STH' then 'americas' when 'PAC' then 'americas'
           when 'OCE' then 'oceania'
         end
$$;
comment on function public.region_area(text) is
  '0241: THE ONE reading of which part of the world a region lies in (europe, africa, middle_east, india, se_asia, '
  'east_asia, americas, oceania). Served on world.stats_cities rows as `area`; the Cities face filters by it.';
revoke all on function public.region_area(text) from public, anon, authenticated;

-- ── 0. THE PRE-IMAGES (LF-normalised) ───────────────────────────────────────────────────────────
create temp table defs_before_0241 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('world.stats_cities()'), ('public.stats_fold_day(bigint)'), ('world.stats_merchants()')) f(fn);

create temp table before_0241 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points;

-- ── 2. THE HUNKS (each occurs exactly once in its live body) ────────────────────────────────────
create temp table hunks_0241 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0241 values
('world.stats_cities()', 1,
$h$  v_at     timestamptz;
begin
$h$,
$h$  v_at     timestamptz;
  v_me     uuid := public.current_player_id();   -- 0241: whose shares are "mine" (null: no house, nothing is mine)
begin
$h$),
('world.stats_cities()', 2,
$h$                  else '{}'::jsonb end
               order by p.name)
        from public.ports p
        left join public.stats_city c on c.port_id = p.id and c.slot = v_slot
        left join public.stats_window_cities(v_at, now()) m on m.port_id = p.id
       where p.kind = 'HARBOUR'), '[]'::jsonb));
$h$,
$h$                  else '{}'::jsonb end
               -- 0241 (owner row 228): what the Cities face filters and sorts by — the region and its area, Σ invested
               -- there, whether the caller holds shares there, and the market's units as of the last count
               || jsonb_build_object('region', r.code, 'area', public.region_area(r.code), 'invested', coalesce(s.paid, 0),
                                     'mine', s.mine is not null, 'stock', c.day->'stock')
               order by p.name)
        from public.ports p
        join public.regions r on r.id = p.region_id
        left join public.stats_city c on c.port_id = p.id and c.slot = v_slot
        left join public.stats_window_cities(v_at, now()) m on m.port_id = p.id
        left join (select x.port_id, sum(x.paid)::bigint as paid, sum(x.paid) filter (where x.player_id = v_me) as mine
                     from public.city_shares x group by x.port_id) s on s.port_id = p.id
       where p.kind = 'HARBOUR'), '[]'::jsonb));
$h$),
('public.stats_fold_day(bigint)', 3,
$h$                                  'income', d.income, 'spending', d.spending, 'taxes', d.taxes, 'sold', d.sold, 'bought', d.bought,
$h$,
$h$                                  'income', d.income, 'spending', d.spending, 'taxes', d.taxes, 'sold', d.sold, 'bought', d.bought,
                                  -- 0241: the market's units as of this count (world.stats_cities serves it as `stock`)
                                  'stock', (select coalesce(round(sum(pg.stock)), 0)::bigint from public.port_goods pg where pg.port_id = n.port_id),
$h$),
('world.stats_merchants()', 4,
$h$  v_b jsonb;
  v_p bigint;
$h$,
$h$  v_b jsonb;
  v_d jsonb;   -- 0241: the 24 h of laps, read once — the board and the list are both cut from it
  v_p bigint;
$h$),
('world.stats_merchants()', 5,
$h$  v_b := case when m.day is null
              then jsonb_build_object('profit_day', m.profit_day, 'laps_day', m.laps_day, 'losing_pct', m.losing_pct, 'top', m.top, 'bottom', m.bottom)
              else public.stats_merchants_board(public.stats_merchants_add(m.day, public.stats_merchants_window(m.at, now()))) end;
$h$,
$h$  v_d := case when m.day is null then null else public.stats_merchants_add(m.day, public.stats_merchants_window(m.at, now())) end;
  v_b := case when m.day is null
              then jsonb_build_object('profit_day', m.profit_day, 'laps_day', m.laps_day, 'losing_pct', m.losing_pct, 'top', m.top, 'bottom', m.bottom)
              else public.stats_merchants_board(v_d) end;
$h$),
('world.stats_merchants()', 6,
$h$    'top', v_b->'top', 'bottom', v_b->'bottom',
$h$,
$h$    'top', v_b->'top', 'bottom', v_b->'bottom',
    -- 0241 (owner row 228): every merchant company, richest first, as [name, nation, purse, fleets, day, laps]
    'list', coalesce((select jsonb_agg(jsonb_build_array(pl.company_name, n.code, pl.ducats, coalesce(f.n, 0), coalesce(d.day, 0), coalesce(d.laps, 0))
                                       order by pl.ducats desc, pl.company_name)
                        from public.npc_houses h
                        join public.players pl on pl.id = h.player_id
                        left join public.nations n on n.id = pl.nation_id
                        left join (select nf.player_id, count(*)::int as n from public.npc_fleets nf group by nf.player_id) f on f.player_id = h.player_id
                        left join (select x.name, x.nation, sum(x.day)::bigint as day, sum(x.laps)::int as laps
                                     from jsonb_to_recordset(coalesce(v_d->'houses', '[]'::jsonb)) x(name text, nation text, day bigint, laps int)
                                    group by x.name, x.nation) d on d.name = pl.company_name and d.nation is not distinct from n.code), '[]'::jsonb),
$h$);

do $$
declare
  d   record;
  h   record;
  v_def text;
  v_n int;
begin
  for d in select * from defs_before_0241 loop
    v_def := d.def;
    for h in select * from hunks_0241 where fn = d.fn order by n loop
      v_n := pg_temp.occurs_0241(v_def, h.old);
      if v_n <> 1 then
        raise exception '0241 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
          h.n, h.fn, v_n;
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    execute v_def;
  end loop;
end $$;

-- ── 3. THE SELF-ASSERT ──────────────────────────────────────────────────────────────────────────
do $$
declare
  v_before record;
  v_d record; v_h record; v_pp record; v_def text;
  c_uid    uuid := '0241a5e4-0000-4000-8000-000000000241';
  v_lis    uuid := (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR');
  v_other  uuid := (select p.id from public.ports p where p.kind = 'HARBOUR' and p.code <> 'LIS' order by p.code limit 1);
  v_slot   bigint;
  v_p      uuid;
  v_m      uuid;
  v_s      jsonb;
begin
  select * into v_before from before_0241;

  -- (a) THE RE-CUTS reverse to their pre-images; ACL / volatility / definer / config unmoved
  for v_d in select * from defs_before_0241 loop
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    for v_h in select * from hunks_0241 where fn = v_d.fn order by n desc loop
      if pg_temp.occurs_0241(v_def, v_h.new) <> 1 then
        raise exception '0241 self-assert FAIL: hunk % of % is not in the new body exactly once', v_h.n, v_d.fn;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0241 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg
      into v_pp from pg_proc p where p.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0241 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;
  if (select count(*) from public.client_rpc_entry_points()) <> v_before.entry_points then
    raise exception '0241 self-assert FAIL: the registry moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0241 self-assert FAIL: a wall moved';
  end if;
  if v_lis is null or v_other is null then
    raise exception '0241 self-assert FAIL: no Lisbon, or no second harbour';
  end if;

  -- (b) THE AREA: every authored region in one of the eight; three named; an unknown code is in none
  if exists (select 1 from public.regions r
              where public.region_area(r.code) is null
                 or public.region_area(r.code) not in ('europe', 'africa', 'middle_east', 'india', 'se_asia', 'east_asia', 'americas', 'oceania'))
     or public.region_area('IBE') <> 'europe' or public.region_area('JAP') <> 'east_asia' or public.region_area('PAC') <> 'americas'
     or public.region_area('ZZZ') is not null then
    raise exception '0241 self-assert FAIL: a region is in no area, or a named one is in the wrong one';
  end if;

  -- (c) THE FOLD keeps the stock: a probe city row for Lisbon at a slot past every real one
  v_slot := greatest(coalesce((select max(x.slot) from public.stats_city x where x.port_id = v_lis), 0),
                     coalesce((select max(w.slot) from public.stats_world w), 0)) + 1000;
  begin
    insert into public.stats_city (port_id, slot, at, purse, income, spending, taxes, works, sold, bought, flows)
    values (v_lis, v_slot, now(), 0, 0, 0, 0, 0, 0, 0, '{}'::jsonb);
    perform public.stats_fold_day(v_slot);
    raise exception using errcode = 'ZX241', message = jsonb_build_object(
      'stock', (select x.day->'stock' from public.stats_city x where x.port_id = v_lis and x.slot = v_slot),
      'want', (select coalesce(round(sum(pg.stock)), 0)::bigint from public.port_goods pg where pg.port_id = v_lis))::text;
  exception when sqlstate 'ZX241' then
    v_s := sqlerrm::jsonb;
  end;
  if v_s->'stock' is null or jsonb_typeof(v_s->'stock') <> 'number' or v_s->'stock' <> v_s->'want' then
    raise exception '0241 self-assert FAIL: the fold did not keep Lisbon''s stock: %', v_s;
  end if;

  -- (d) CITIES: a probe company with shares at Lisbon reads Lisbon as hers, and another harbour not
  begin
    perform set_config('request.jwt.claim.sub', c_uid::text, true);
    v_p := public.new_house(c_uid, 'Casa das Contas 0241', 'PRT', 'LIS');
    insert into public.city_shares (port_id, kind, player_id, shares, paid, accrued, accrued_day)
    values (v_lis, 'market', v_p, 1, 777, 0, 0);
    v_s := world.stats_cities();
    raise exception using errcode = 'ZX241', message = jsonb_build_object(
      'me', public.current_player_id() = v_p,
      'lis', (select c from jsonb_array_elements(v_s->'cities') c where c->>'id' = v_lis::text),
      'other', (select c from jsonb_array_elements(v_s->'cities') c where c->>'id' = v_other::text),
      'bare', (select count(*) from jsonb_array_elements(v_s->'cities') c where not (c ? 'area' and c ? 'region' and c ? 'mine' and c ? 'invested')),
      'rows', jsonb_array_length(v_s->'cities'))::text;
  exception when sqlstate 'ZX241' then
    v_s := sqlerrm::jsonb;
  end;
  if (v_s->>'me')::boolean is not true
     or (v_s->'lis'->>'mine')::boolean is not true or (v_s->'lis'->>'invested')::bigint < 777
     or v_s->'lis'->>'area' <> 'europe' or v_s->'lis'->>'region' <> 'IBE'
     or (v_s->'other'->>'mine')::boolean is not false
     or (v_s->>'bare')::int <> 0 or (v_s->>'rows')::int < 2 then
    raise exception '0241 self-assert FAIL: the cities read does not carry the filter fields: %', v_s;
  end if;

  -- (e) MERCHANTS: a probe merchant company is in the list once, with her purse and her one roster fleet
  begin
    v_m := public.new_house(null, 'Casa da Lista 0241', 'PRT', 'LIS', p_ducats => 4321, p_is_npc => true);
    insert into public.npc_houses (player_id, roster_ord, ink, blurb, master, home_port_id, capital, patience, wares)
    values (v_m, (select coalesce(max(h.roster_ord), 0) + 1 from public.npc_houses h), 'prt',
            'A probe house of 0241, rolled back.', 'Mestre da Lista', v_lis, 5000, 0.1, '{}');
    insert into public.npc_fleets (fleet_id, player_id, roster_ord)
    select f.id, v_m, (select coalesce(max(n.roster_ord), 0) + 1 from public.npc_fleets n)
      from public.fleets f where f.player_id = v_m order by f.id limit 1;
    -- a stats_merchants row for the read to stand on, past every real one (the read answers bare without one)
    if not exists (select 1 from public.stats_merchants) then
      insert into public.stats_merchants (slot, at, houses, fleets, sailing, docked, repairing, unable, laid_up, purse, profit_day, laps_day, losing_pct, top, bottom)
      values (1, now(), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, '[]'::jsonb, '[]'::jsonb);
    end if;
    v_s := world.stats_merchants();
    raise exception using errcode = 'ZX241', message = jsonb_build_object(
      'mine', (select jsonb_agg(e) from jsonb_array_elements(v_s->'list') e where e->>0 = 'Casa da Lista 0241'))::text;
  exception when sqlstate 'ZX241' then
    v_s := sqlerrm::jsonb;
  end;
  if jsonb_array_length(coalesce(v_s->'mine', '[]'::jsonb)) <> 1
     or v_s->'mine'->0->>1 <> 'PRT' or (v_s->'mine'->0->>2)::bigint <> 4321 or (v_s->'mine'->0->>3)::int <> 1
     or (v_s->'mine'->0->>4)::bigint <> 0 or (v_s->'mine'->0->>5)::int <> 0 then
    raise exception '0241 self-assert FAIL: the merchants list does not carry the probe house as [name, PRT, 4321, 1, 0, 0]: %', v_s;
  end if;

  -- nothing of the probe survives
  if exists (select 1 from public.players p where p.company_name in ('Casa das Contas 0241', 'Casa da Lista 0241'))
     or exists (select 1 from public.stats_city x where x.slot = v_slot)
     or coalesce(current_setting('request.jwt.claim.sub', true), '') <> '' then
    raise exception '0241 self-assert FAIL: the probe left rows behind';
  end if;

  raise notice '0241 self-assert ok: EVERY LIST CAN BE SORTED. region_area minted (25 regions in 8 areas); stats_cities (2 hunks), stats_fold_day (1), stats_merchants (3) re-cut, reversed, ACL unmoved; registry unchanged; walls 0. The fold kept Lisbon''s stock; a probe company with shares at Lisbon read it as hers (europe, IBE) and another harbour not; a probe merchant (purse 4,321, one fleet) is in the list once. Rolled back.';
end $$;
