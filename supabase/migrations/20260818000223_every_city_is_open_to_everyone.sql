-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0223 — EVERY CITY IS OPEN TO EVERYONE
--        (docs/dev-log/2026-10-26-city-open.md; the Stats tab's two city reads serve every figure to every
--        company, and the investment gate is gone — not set to zero, GONE)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER, VERBATIM (docs/OWNER_REQUESTS.md row 197) ────────────────────────────────────────
--   "on cities, i want to see all the info without investment" (2026-10-25)
--   "i told you no investment needed to see a city info, has this been built?" (2026-10-26)
--
-- ── WHAT SAYS THE OPPOSITE TODAY, NAMED ─────────────────────────────────────────────────────────
--   0214 built the gate the owner asked for on 2026-10-20 ("a statistic info of a city is added only when
--   you invest certain amount") and he has since reversed it. Three things carry it:
--     · public.stats_city_tier(player, port) (0214:303) — Σ city_shares.paid there against two knobs,
--       stats_city_tier1 (20,000 🪙) and stats_city_tier2 (100,000 🪙), into {tier, paid, need, tier1, tier2};
--     · world.stats_cities() (0214:649) — a city's purse, works and day-figures ONLY at tier ≥ 1;
--     · world.stats_city(port) (0214:690) — `overview` ONLY at tier ≥ 1, `detail` ONLY at tier ≥ 2.
--   The client (src/features/stats/Cities.tsx, CityDetail.tsx) drew a lock for what did not arrive. The
--   same PR removes every lock face and its words.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
--   (1) world.stats_cities() — 4 hunks: no caller read, no tier per row, no `tier1` / `tier2` on the list; a
--       city's figures follow its newest rollup row and nothing else.
--   (2) world.stats_city(uuid) — 5 hunks: no tier read; `overview` and `detail` follow the newest rollup
--       row and nothing else; `tier`, `paid`, `need`, `tier1`, `tier2` are no longer served.
--   (3) DROP public.stats_city_tier(uuid, uuid) — asserted to have no other caller first (no function body
--       in cmd / voyage / world / public names it once the two reads are re-cut).
--   (4) DELETE the two knobs stats_city_tier1 / stats_city_tier2 from public.world_config — the machinery
--       goes with the rule (docs/NO_SPAGHETTI.md §5: delete, don't adapt; a knob at 0 would be a gate left
--       standing with its door open).
--   (5) The comment on public.stats_city no longer says GATED.
--   Investing in a city stays a game action (cmd.invest, world.holdings); it has stopped being a key.
--
-- SUPERSEDES, by hunks sliced from the LIVE body (prod head 0220, LF-normalised, each asserted to occur exactly
-- once before and to reverse to the pre-image after; ACL, owner, volatility, SECURITY DEFINER and config
-- asserted unchanged):
--   world.stats_cities()      (0214:649)  4 hunks
--   world.stats_city(uuid)    (0214:690)  5 hunks
-- CREATE FUNCTION ×0, CREATE OR REPLACE ×2 (by hunks), DROP FUNCTION ×1, world_config −2 rows. No table changes.
-- The registry (public.client_rpc_entry_points) does not move: both reads keep their rows and their grant.
--
-- DOES NOT TOUCH (decided by default; the owner may reverse each): public.city_shares and cmd.invest (the
-- investment itself); world.holdings (where a company reads its own stakes); the rollup job public.tick_stats
-- and its tables; the other four Stats reads; world.npc_fleet_card.
--
-- ROLLBACK (forward migration): reverse the nine hunks (each OLD text is here verbatim), re-create
-- public.stats_city_tier from 0214:303-325 with its revoke, re-insert the two knobs from 0214:127-132.
--
-- SELF-ASSERT: its own probe company (id 00000000-0223-…), founded in a sub-block and rolled back, with NO
-- share anywhere, reads one harbour (the first by code that sells something) and the list: `overview` and
-- `detail` both served, the list row carries the purse and the day-figures, none of the five tier keys is on
-- either read, every harbour with a rollup row carries a purse. Counts only its own rows. Timing printed.

create or replace function pg_temp.occurs_0223(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

create temp table t0_0223 on commit drop as select clock_timestamp() as t0;

-- ── 1. THE PRE-IMAGE ───────────────────────────────────────────────────────────────────────────
create temp table defs_before_0223 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg,
       (select p.proowner from pg_proc p where p.oid = f.fn::regprocedure) as owner
  from (values ('world.stats_cities()'), ('world.stats_city(uuid)')) f(fn);

create temp table before_0223 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from public.world_config) as knobs;

create temp table hunks_0223 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0223 values
-- ── world.stats_cities() ──
('world.stats_cities()', 1,
$h$-- 0214: every harbour with the CALLER'S tier there (public.stats_city_tier): name, flag, the stake and what more
-- opens the next tier for all; the purse, works and the last day's income, spending, taxes and units ONLY where
-- the caller holds tier 1 or more. The gate is here, not in the client.
declare
  v_player uuid := public.current_player_id();
  v_slot   bigint;
$h$,
$h$-- 0214: every harbour: name, flag, the purse, works and the last day's income, spending, taxes and units.
-- 0223 (the owner: "on cities, i want to see all the info without investment"): served to EVERYONE — 0214's
-- investment gate is gone (its function dropped by 0223), and so are `tier`, `paid`, `need`, `tier1`, `tier2`.
declare
  v_slot   bigint;
$h$),
('world.stats_cities()', 2,
$h$    'tier1', public.wc_num('stats_city_tier1')::bigint, 'tier2', public.wc_num('stats_city_tier2')::bigint,
    'cities', coalesce((
$h$,
$h$    'cities', coalesce((
$h$),
('world.stats_cities()', 3,
$h$                                  'nation', (select n.code from public.nations n where n.id = public.port_nation(p.id)),
                                  'tier', (t.t->>'tier')::int, 'paid', (t.t->>'paid')::bigint, 'need', (t.t->>'need')::bigint)
               || case when (t.t->>'tier')::int >= 1 and c.port_id is not null then
$h$,
$h$                                  'nation', (select n.code from public.nations n where n.id = public.port_nation(p.id)))
               || case when c.port_id is not null then
$h$),
('world.stats_cities()', 4,
$h$        left join public.stats_city c on c.port_id = p.id and c.slot = v_slot
        cross join lateral (select public.stats_city_tier(v_player, p.id) as t) t
       where p.kind = 'HARBOUR'), '[]'::jsonb));
$h$,
$h$        left join public.stats_city c on c.port_id = p.id and c.slot = v_slot
       where p.kind = 'HARBOUR'), '[]'::jsonb));
$h$),
-- ── world.stats_city(uuid) ──
('world.stats_city(uuid)', 1,
$h$-- 0214: one harbour, at the caller's tier. Always: the city, the stake, the tier, what more opens the next.
-- Tier 1 adds `overview`; tier 2 adds `detail`. Nothing of a locked tier leaves the server.
declare
  v_player uuid := public.current_player_id();
  v_tier   jsonb;
  v_slot   bigint;
$h$,
$h$-- 0214: one harbour: the city, then `overview` and `detail` once the job has written its first row.
-- 0223 (the owner: "on cities, i want to see all the info without investment"): served to EVERYONE — 0214's
-- investment gate is gone (its function dropped by 0223), and so are `tier`, `paid`, `need`, `tier1`, `tier2`.
declare
  v_slot   bigint;
$h$),
('world.stats_city(uuid)', 2,
$h$  v_tier := public.stats_city_tier(v_player, p_port);
  select * into c from public.stats_city x where x.port_id = p_port order by x.slot desc limit 1;
$h$,
$h$  select * into c from public.stats_city x where x.port_id = p_port order by x.slot desc limit 1;
$h$),
('world.stats_city(uuid)', 3,
$h$    'slot_seconds', public.wc_num('drift_slot_seconds')) || v_tier;
$h$,
$h$    'slot_seconds', public.wc_num('drift_slot_seconds'));
$h$),
('world.stats_city(uuid)', 4,
$h$  if (v_tier->>'tier')::int >= 1 and v_slot is not null then
$h$,
$h$  if v_slot is not null then  -- 0223: the overview, for everyone
$h$),
('world.stats_city(uuid)', 5,
$h$  if (v_tier->>'tier')::int >= 2 and v_slot is not null then
$h$,
$h$  if v_slot is not null then  -- 0223: the detail, for everyone
$h$);

-- ── 2. THE NEW BODIES ──────────────────────────────────────────────────────────────────────────
do $$
declare
  d     record;
  h     record;
  p     record;
  v_def text;
  v_rev text;
begin
  if (select count(*) from defs_before_0223 where def is not null) <> 2 then
    raise exception '0223 self-assert FAIL: world.stats_cities() or world.stats_city(uuid) was not found';
  end if;
  for d in select * from defs_before_0223 order by fn loop
    v_def := d.def;
    for h in select * from hunks_0223 where fn = d.fn order by n loop
      if pg_temp.occurs_0223(v_def, h.old) <> 1 then
        raise exception '0223 self-assert FAIL: % hunk % occurs % time(s), not once — the deployed body is not what this file was written against',
          d.fn, h.n, pg_temp.occurs_0223(v_def, h.old);
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    execute v_def;
    v_rev := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0223 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0223(v_rev, h.new) <> 1 then
        raise exception '0223 self-assert FAIL: % new hunk % is not in the live body once', d.fn, h.n;
      end if;
      v_rev := replace(v_rev, h.new, h.old);
    end loop;
    if v_rev <> d.def then
      raise exception '0223 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef,
           coalesce(pr.proconfig::text, '') as cfg, pr.proowner as owner
      into p from pg_proc pr where pr.oid = d.fn::regprocedure;
    if p.acl <> d.acl or p.vol <> d.vol or p.secdef <> d.secdef or p.cfg <> d.cfg or p.owner <> d.owner then
      raise exception '0223 self-assert FAIL: % changed its ACL (% → %), owner, volatility, definer or config (% → %)', d.fn, d.acl, p.acl, d.cfg, p.cfg;
    end if;
  end loop;
end $$;

-- ── 3. THE GATE GOES, WITH ITS KNOBS ───────────────────────────────────────────────────────────
do $$
begin
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname in ('cmd', 'voyage', 'world', 'public') and p.proname <> 'stats_city_tier'
                and p.prosrc like '%stats_city_tier%') then
    raise exception '0223 self-assert FAIL: public.stats_city_tier still has a caller: %',
      (select string_agg(n.nspname || '.' || p.proname, ', ') from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname in ('cmd', 'voyage', 'world', 'public') and p.proname <> 'stats_city_tier' and p.prosrc like '%stats_city_tier%');
  end if;
end $$;

drop function public.stats_city_tier(uuid, uuid);

delete from public.world_config where key in ('stats_city_tier1', 'stats_city_tier2');

comment on table public.stats_city is
  '0214: one row per harbour per drift slot — the treasury purse and the day''s income / spending / taxes, '
  'the units it sold and bought, its works and the treasury flows by kind. public.tick_stats writes it; '
  'world.stats_cities and world.stats_city read it. 0223: served to everyone (the 0214 tier gate is gone).';

-- ── 4. SELF-ASSERT ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_uid    constant uuid := '00000000-0223-4000-8000-000000000001';
  c_nil    constant uuid := '00000000-0000-0000-0000-000000000000';
  v_port   uuid; v_code text;
  v_p      uuid;
  v_v      jsonb; v_row jsonb; v_list jsonb; v_out jsonb;
  v_with   int; v_rolled int;
  v_t      timestamptz;
  v_ms_city numeric; v_ms_list numeric;
begin
  -- (a) the gate and its knobs are gone; nothing served carries their names
  if to_regprocedure('public.stats_city_tier(uuid, uuid)') is not null then
    raise exception '0223 self-assert FAIL: public.stats_city_tier still exists';
  end if;
  if exists (select 1 from public.world_config where key in ('stats_city_tier1', 'stats_city_tier2')) then
    raise exception '0223 self-assert FAIL: a stats_city_tier knob survived';
  end if;
  if (select count(*) from public.world_config) <> (select knobs from before_0223) - 2 then
    raise exception '0223 self-assert FAIL: world_config has % rows, not the % before less 2',
      (select count(*) from public.world_config), (select knobs from before_0223);
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname in ('world') and p.proname in ('stats_cities', 'stats_city')
                and (p.prosrc like '%stats_city_tier%' or p.prosrc like '%v_tier%' or p.prosrc like '%''tier''%')) then
    raise exception '0223 self-assert FAIL: a city read still names the tier';
  end if;

  -- (b) the probe: the first harbour by code that sells something; its own company, no share anywhere
  select p.id, p.code into v_port, v_code from public.ports p
   where p.kind = 'HARBOUR' and exists (select 1 from public.port_specialties s where s.port_id = p.id)
   order by p.code limit 1;
  if v_port is null then
    raise exception '0223 self-assert FAIL: no harbour sells anything — the probe has no subject';
  end if;
  if exists (select 1 from public.players p where p.id = c_uid or p.auth_uid = c_uid or p.company_name = 'Casa Aberta 0223') then
    raise exception '0223 self-assert FAIL: the probe company''s id or name is already taken in this world';
  end if;

  begin
    v_p := public.new_house(c_uid, 'Casa Aberta 0223', 'PRT', 'LIS');
    if exists (select 1 from public.city_shares c where c.player_id = v_p) then
      raise exception '0223 self-assert FAIL: the probe company holds a share — the probe must own nothing';
    end if;
    -- a rollup row for every harbour, so the reads have figures to serve (rolled back with the rest)
    perform public.tick_price_snapshot(now());
    perform public.tick_stats(now());
    if (select count(*) from public.stats_city) <> (select count(*) from public.ports where kind = 'HARBOUR') then
      raise exception '0223 self-assert FAIL: the job wrote % city rows for % harbours',
        (select count(*) from public.stats_city), (select count(*) from public.ports where kind = 'HARBOUR');
    end if;

    perform cmd.assume_identity(c_uid);
    v_t := clock_timestamp();
    v_v := world.stats_city(v_port);
    v_ms_city := round(extract(epoch from clock_timestamp() - v_t) * 1000, 1);
    if not (v_v ? 'overview') or not (v_v ? 'detail') then
      raise exception '0223 self-assert FAIL: with nothing invested % is not fully served: keys %', v_code, (select jsonb_agg(k) from jsonb_object_keys(v_v) k);
    end if;
    if (v_v ? 'tier') or (v_v ? 'paid') or (v_v ? 'need') or (v_v ? 'tier1') or (v_v ? 'tier2') then
      raise exception '0223 self-assert FAIL: the city read still carries a tier key: %', (select jsonb_agg(k) from jsonb_object_keys(v_v) k);
    end if;
    if (v_v->'overview'->>'purse')::bigint <> public.treasury_balance(v_port)::bigint then
      raise exception '0223 self-assert FAIL: the overview''s purse % is not the treasury''s %', v_v->'overview'->>'purse', public.treasury_balance(v_port);
    end if;
    if jsonb_typeof(v_v->'overview'->'works') <> 'array' or jsonb_typeof(v_v->'overview'->'series') <> 'array'
       or jsonb_typeof(v_v->'detail'->'goods') <> 'array' then
      raise exception '0223 self-assert FAIL: the overview or the detail is not the 0214 shape: %', left(v_v::text, 400);
    end if;
    if jsonb_array_length(v_v->'detail'->'goods') < (select count(*) from public.port_specialties s where s.port_id = v_port) then
      raise exception '0223 self-assert FAIL: the detail lists % goods, fewer than the % the harbour offers',
        jsonb_array_length(v_v->'detail'->'goods'), (select count(*) from public.port_specialties s where s.port_id = v_port);
    end if;

    v_t := clock_timestamp();
    v_list := world.stats_cities();
    v_ms_list := round(extract(epoch from clock_timestamp() - v_t) * 1000, 1);
    if (v_list ? 'tier1') or (v_list ? 'tier2') then
      raise exception '0223 self-assert FAIL: the list still carries tier1 / tier2';
    end if;
    if jsonb_array_length(v_list->'cities') <> (select count(*) from public.ports where kind = 'HARBOUR') then
      raise exception '0223 self-assert FAIL: the list has % cities for % harbours',
        jsonb_array_length(v_list->'cities'), (select count(*) from public.ports where kind = 'HARBOUR');
    end if;
    select x into v_row from jsonb_array_elements(v_list->'cities') x where x->>'code' = v_code;
    if v_row is null or not (v_row ? 'purse') or not (v_row ? 'income_1d') or not (v_row ? 'spending_1d')
       or not (v_row ? 'taxes_1d') or not (v_row ? 'sold_1d') or not (v_row ? 'bought_1d') or not (v_row ? 'works') then
      raise exception '0223 self-assert FAIL: the list row for % lacks a figure: %', v_code, v_row;
    end if;
    if (v_row ? 'tier') or (v_row ? 'paid') or (v_row ? 'need') then
      raise exception '0223 self-assert FAIL: the list row still carries a tier key: %', v_row;
    end if;
    if (v_row->>'purse')::bigint <> public.treasury_balance(v_port)::bigint then
      raise exception '0223 self-assert FAIL: the list row''s purse % is not the treasury''s %', v_row->>'purse', public.treasury_balance(v_port);
    end if;
    select count(*) into v_with from jsonb_array_elements(v_list->'cities') x where x ? 'purse';
    if v_with <> jsonb_array_length(v_list->'cities') then
      raise exception '0223 self-assert FAIL: a company with no stake anywhere was served % purses for % cities', v_with, jsonb_array_length(v_list->'cities');
    end if;
    perform cmd.assume_identity(c_nil);

    raise exception using errcode = 'ZX223', message = jsonb_build_object('ms_city', v_ms_city, 'ms_list', v_ms_list, 'cities', v_with,
      'goods', jsonb_array_length(v_v->'detail'->'goods'), 'port', v_code)::text;
  exception when sqlstate 'ZX223' then
    v_out := sqlerrm::jsonb;
  end;

  -- (c) nothing of the probe survives; the registry and the grants
  select count(*) into v_rolled from public.players where id = v_p;
  if v_rolled <> 0 or exists (select 1 from public.stats_city) or exists (select 1 from public.players p where p.company_name = 'Casa Aberta 0223') then
    raise exception '0223 self-assert FAIL: the probe survived its rollback';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> (select entry_points from before_0223)
     or not has_function_privilege('authenticated', 'world.stats_cities()', 'execute')
     or not has_function_privilege('authenticated', 'world.stats_city(uuid)', 'execute')
     or exists (select 1 from public.client_rpc_entry_points() e where e.fn is null or not has_function_privilege('authenticated', e.fn, 'execute')) then
    raise exception '0223 self-assert FAIL: the registry moved or a row is not executable';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0 or (select count(*) from public.client_executable_writers()) <> 0 then
    raise exception '0223 self-assert FAIL: a client role can write';
  end if;

  raise notice '0223 self-assert ok: EVERY CITY IS OPEN TO EVERYONE. world.stats_cities re-cut by 4 hunks and world.stats_city by 5, each reversed (ACL, owner, volatility, definer, config kept); public.stats_city_tier dropped with no other caller; knobs stats_city_tier1 / stats_city_tier2 deleted (world_config −2). A probe company with no share anywhere read % (overview + detail, % goods, purse = the treasury) in % ms and the list (% of % cities with a purse, no tier keys) in % ms; rolled back. Registry unmoved; walls 0. % ms in all.',
    v_out->>'port', v_out->>'goods', v_out->>'ms_city', v_out->>'cities', v_out->>'cities', v_out->>'ms_list',
    round(extract(epoch from clock_timestamp() - (select t0 from t0_0223)) * 1000);
end $$;
