-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0148 — LEADING A CITY IS KNOWN  (docs/INFLUENCE.md slice I6)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER'S WORDS ───────────────────────────────────────────────────────────────────────────
-- O3 (2026-10-17): rewards for leading a city — all four: fame/rank, a Mayor, investor dividends,
-- cheaper trade. The mayor and the cheaper trade are 0147; this file is fame, rank and dividends.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) tick_influence step 5 FAME: one MAYOR_DAY event per mayor at each daily count (the record
--     fame reads — derived, never a counter, 0014's rule). Receipt `mayor_days`.
-- (2) public.player_progress: TRADING gains coin given into cities (INVESTED + DONATED, off the
--     ledger as turnover is, at fame_ducats_per_point) and fame_per_mayor_day (25) for each
--     MAYOR_DAY (D11). The trading object serves `given` and `mayor_days` beside `turnover`.
-- (3) DIVIDENDS (D10): tick_city step 6 — a holder's coupon is × influence_owner_coupon_mult (1.5)
--     when its company sails for the country that holds the city and the race is lit
--     (public.influence_coupon_mult, the one reader); otherwise × 1, byte for byte. A city still pays
--     only what it holds above its reserve (0123), so the bonus makes a poor city skip sooner.
-- (4) world.nation_standings() (registered): per country — cities held (home and won), won this
--     week, and its top three givers by name. Rank's Countries board.
-- (5) world.standings' card gains `mayor_of` (the cities a company is mayor of): a captain's row
--     says `Mayor of Havana`.
--
-- ── THE PROOF (in this file) ────────────────────────────────────────────────────────────────────
-- (a) The re-cuts reverse to their pre-images, ACLs unmoved. (b) player_progress equals its
--     pre-image for every house with no gift and no mayor day (a sample of the live world). (c) On
--     probe rows (rolled back): a probe giver's trading points rise by cost / fame_ducats_per_point;
--     one mayor day adds 25; the holder-country holder's coupon is 1.5 × another's for the same
--     `paid` (lit), and equal dark; nation_standings counts port_allegiance per country. Timings:
--     raise notice only.
--
-- ROLLBACK: influence_switch(false) (the multiplier is 1 dark); the fame terms read events only.
-- SUPERSEDES, by hunks sliced from the LIVE bodies: public.tick_influence (0147),
-- public.player_progress (0127), public.tick_city (0123), world.standings (0025/0028),
-- public.client_rpc_entry_points (0147). VERSION: 0148. Applies on 0147.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

create or replace function pg_temp.occurs_0148(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

create temp table defs_before_0148 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl
  from (values ('public.tick_influence(timestamp with time zone)'),
               ('public.player_progress(uuid)'),
               ('public.tick_city(timestamp with time zone)'),
               ('world.standings(integer)'),
               ('public.client_rpc_entry_points()')) f(fn);

-- player_progress before, on a sample of the live world's houses (players and merchants)
create temp table pre_0148_progress on commit drop as
select p.id, public.player_progress(p.id) as j
  from (select id from public.players order by is_npc, md5(id::text || '0148') limit 60) p;

-- ── 1. THE KNOBS ───────────────────────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('fame_per_mayor_day', to_jsonb(25),
   '0148 (D11): trading fame for each day a company is a city''s mayor (one MAYOR_DAY at each daily count).'),
  ('influence_owner_coupon_mult', to_jsonb(1.5),
   '0148 (D10): a holder''s coupon is multiplied by this in a city its country holds, while the race is lit.')
on conflict (key) do nothing;

create or replace function public.influence_coupon_mult(p_port uuid, p_player uuid)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0148 (D10): THE one reader of a holder's coupon multiplier — influence_owner_coupon_mult when the
-- race is lit and the holder sails for the country that holds the city, else exactly 1.
begin
  if public.influence_on()
     and (select pl.nation_id from public.players pl where pl.id = p_player) = public.port_nation(p_port) then
    return public.wc_num('influence_owner_coupon_mult');
  end if;
  return 1;
end $$;
revoke all on function public.influence_coupon_mult(uuid, uuid) from public, anon, authenticated;

create or replace function world.nation_standings()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0148: Rank's Countries board — every country's cities (home and won, from public.port_nation),
-- the cities it won in the last 7 days, and its three biggest givers (port_influence for that
-- country, by name). Most cities first.
begin
  return jsonb_build_object('at', now(), 'countries', (
    select coalesce(jsonb_agg(c.row order by c.held desc, c.code), '[]'::jsonb)
      from (
        select n.code, x.held,
               jsonb_build_object(
                 'nation', n.code,
                 'held', x.held, 'home', x.home, 'won', x.held - x.home,
                 'won_week', x.won_week,
                 'top', coalesce((select jsonb_agg(jsonb_build_object('name', t.company_name, 'merchant', t.is_npc, 'points', round(t.points))
                                                   order by t.points desc, t.company_name)
                                    from (select pl.company_name, pl.is_npc, sum(i.points) as points
                                            from public.port_influence i join public.players pl on pl.id = i.player_id
                                           where i.nation_id = n.id
                                           group by pl.company_name, pl.is_npc
                                           order by sum(i.points) desc, pl.company_name limit 3) t), '[]'::jsonb)) as row
          from public.nations n
          cross join lateral (
            select count(*) filter (where public.port_nation(a.port_id) = n.id) as held,
                   count(*) filter (where public.port_nation(a.port_id) = n.id and a.home) as home,
                   count(*) filter (where public.port_nation(a.port_id) = n.id and not a.home
                                      and a.since > now() - interval '7 days'
                                      and a.since > (select min(b.since) from public.port_allegiance b)) as won_week
              from public.port_allegiance a) x
      ) c));
end $$;
revoke all on function world.nation_standings() from public, anon;
grant execute on function world.nation_standings() to authenticated;

-- ── 2. THE RE-CUTS ─────────────────────────────────────────────────────────────────────────────
create temp table hunks_0148 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0148 values
('public.tick_influence(timestamp with time zone)', 1,
$h$  v_new     int := 0;   -- 0147
begin$h$,
$h$  v_new     int := 0;   -- 0147
  v_days    int := 0;   -- 0148
begin$h$),
('public.tick_influence(timestamp with time zone)', 2,
$h$  -- 6 RECEIPT
  return jsonb_build_object('enabled', true,$h$,
$h$  -- 5 FAME (0148, D11): one MAYOR_DAY per mayor — the record player_progress reads.
  v_t := clock_timestamp();
  begin
    select count(public.emit_event(m.player_id, 'MAYOR_DAY', jsonb_build_object(
             'port', p.code, 'port_name', p.name, 'nation', (select n.code from public.nations n where n.id = public.port_nation(m.port_id)))))
      into v_days
      from public.port_mayor m join public.ports p on p.id = m.port_id;
  exception when others then
    v_err := v_err || jsonb_build_object('step', 'fame', 'error', sqlerrm);
  end;
  v_ms := v_ms || jsonb_build_object('fame', round(extract(epoch from clock_timestamp() - v_t) * 1000));

  -- 6 RECEIPT
  return jsonb_build_object('enabled', true, 'mayor_days', v_days,   -- 0148$h$),
('public.player_progress(uuid)', 1,
$h$  v_combat    numeric := 0;                         -- 0127
begin$h$,
$h$  v_combat    numeric := 0;                         -- 0127
  v_given     numeric := 0;                         -- 0148
  v_mdays     int     := 0;                         -- 0148
begin$h$),
('public.player_progress(uuid)', 2,
$h$  v_trade   := floor(v_turnover / nullif(v_per_ducat, 0))::int;$h$,
$h$  -- 0148 (D11): coin given INTO cities (Invest, Donate) counts as turnover does, off the ledger; and
  -- each day as a mayor (a MAYOR_DAY event) counts fame_per_mayor_day.
  select coalesce(sum(abs(l.ducats_delta)), 0) into v_given
    from public.ledger l
    join public.events e on e.id = l.ref_event_id
   where l.player_id = p_player
     and e.kind in ('INVESTED', 'DONATED');
  select count(*) into v_mdays from public.events e where e.player_id = p_player and e.kind = 'MAYOR_DAY';
  v_trade   := (floor((v_turnover + v_given) / nullif(v_per_ducat, 0)) + v_mdays * public.wc_num('fame_per_mayor_day'))::int;$h$),
('public.player_progress(uuid)', 3,
$h$      'points', v_trade, 'level', public.level_from_points(v_trade), 'turnover', v_turnover),$h$,
$h$      'points', v_trade, 'level', public.level_from_points(v_trade), 'turnover', v_turnover,
      'given', v_given, 'mayor_days', v_mdays),   -- 0148$h$),
('public.tick_city(timestamp with time zone)', 1,
$h$                 round(s.paid * public.wc_num('works_coupon_pct') * (v_today - s.accrued_day))::bigint as due$h$,
$h$                 round(s.paid * public.wc_num('works_coupon_pct') * (v_today - s.accrued_day)
                       * public.influence_coupon_mult(hp.port_id, s.player_id))::bigint as due   -- 0148 (D10)$h$),
('world.standings(integer)', 1,
$h$                   'is_you',           (s.player_id = v_me)$h$,
$h$                   'is_you',           (s.player_id = v_me),
                   -- 0148: the cities this company is mayor of (public on every Town Hall already).
                   'mayor_of',         (select coalesce(jsonb_agg(po.name order by po.name), '[]'::jsonb)
                                          from public.port_mayor m join public.ports po on po.id = m.port_id
                                         where m.player_id = s.player_id)$h$),
('public.client_rpc_entry_points()', 1,
$h$      ('cmd',         'set_tax',               'uuid, numeric')
    ) as t(s, f, a)$h$,
$h$      ('cmd',         'set_tax',               'uuid, numeric'),
      -- 0148: Rank's Countries board (docs/INFLUENCE.md I6).
      ('world',       'nation_standings',      '')
    ) as t(s, f, a)$h$);

do $$
declare
  d record;
  h record;
  v_def text;
  v_n int;
begin
  for d in select * from defs_before_0148 order by fn loop
    v_def := d.def;
    for h in select * from hunks_0148 where fn = d.fn order by n loop
      v_n := pg_temp.occurs_0148(v_def, h.old);
      if v_n <> 1 then
        raise exception '0148 self-assert FAIL: hunk % of % occurs % time(s), not once', h.n, d.fn, v_n;
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    execute v_def;
  end loop;
  for d in select * from defs_before_0148 loop
    v_def := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0148 where fn = d.fn order by n desc loop
      v_def := replace(v_def, h.new, h.old);
    end loop;
    if v_def <> d.def or (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = d.fn::regprocedure) <> d.acl then
      raise exception '0148 self-assert FAIL: % does not reverse to its pre-image, or its ACL moved', d.fn;
    end if;
  end loop;
end $$;

-- ── 3. THE PROOF ───────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_bad int;
begin
  -- (b) a house with no gift and no mayor day reads as it did (the two new keys aside)
  select count(*) into v_bad from pre_0148_progress x
   where not exists (select 1 from public.events e where e.player_id = x.id and e.kind in ('INVESTED', 'DONATED', 'MAYOR_DAY'))
     and (public.player_progress(x.id) #- '{trading,given}' #- '{trading,mayor_days}') <> x.j;
  if v_bad > 0 then
    raise exception '0148 self-assert FAIL: player_progress moved for % houses that gave nothing', v_bad;
  end if;
  if (select count(*) from public.client_rpc_entry_points() e where e.function_name = 'nation_standings'
        and e.fn is not null and has_function_privilege('authenticated', e.fn, 'execute')) <> 1 then
    raise exception '0148 self-assert FAIL: world.nation_standings is not registered for authenticated';
  end if;
end $$;

create or replace function pg_temp.probe_0148()
returns jsonb
language plpgsql
as $$
declare
  c_a  constant uuid := '00000000-0148-4000-8000-00000000000a';
  c_b  constant uuid := '00000000-0148-4000-8000-00000000000b';
  v_prt uuid := (select id from public.nations where code = 'PRT');
  v_a  uuid;
  v_b  uuid;
  v_city uuid;
  v_p0 jsonb;
  v_p1 jsonb;
  v_r  jsonb;
  v_ns jsonb;
  v_da bigint;
  v_db bigint;
  v_out jsonb;
begin
  begin
    update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'influence_enabled');
    v_a := public.new_house(c_a, 'Casa da Fama 0148', 'PRT');
    v_b := public.new_house(c_b, 'Casa del Cupón 0148', 'ESP');
    perform public.credit(v_a, 'PROBE_0148', 1000000);
    perform public.credit(v_b, 'PROBE_0148', 1000000);
    select port_id into v_city from public.port_allegiance where not home order by md5(port_id::text || '0148') limit 1;
    update public.port_allegiance set nation_id = v_prt where port_id = v_city;
    -- (c) a gift raises trading by cost / fame_ducats_per_point
    v_p0 := public.player_progress(v_a);
    perform public.donate_for(v_a, v_city, 5000);
    v_p1 := public.player_progress(v_a);
    if (v_p1->'trading'->>'points')::int - (v_p0->'trading'->>'points')::int <> floor(5000 / public.wc_num('fame_ducats_per_point'))
       or (v_p1->'trading'->>'given')::numeric <> 5000 then
      raise exception '0148 self-assert FAIL: a 5,000 gift moved trading by % (given %)',
        (v_p1->'trading'->>'points')::int - (v_p0->'trading'->>'points')::int, v_p1->'trading'->>'given';
    end if;
    -- one mayor day = 25: the count names her mayor of the city she alone gave to for its country
    delete from public.port_influence where port_id = v_city and player_id <> v_a;
    v_r := public.tick_influence(now());
    if (select player_id from public.port_mayor where port_id = v_city) is distinct from v_a
       or (select count(*) from public.events where player_id = v_a and kind = 'MAYOR_DAY') <> 1 then
      raise exception '0148 self-assert FAIL: the count did not record one mayor day for the mayor: %', v_r;
    end if;
    if (public.player_progress(v_a)->'trading'->>'points')::int - (v_p1->'trading'->>'points')::int <> public.wc_int('fame_per_mayor_day') then
      raise exception '0148 self-assert FAIL: a mayor day is not % trading points', public.wc_int('fame_per_mayor_day');
    end if;
    -- (c) dividends: the same `paid`, a PRT holder (the holding country) and an ESP holder
    insert into public.city_shares (port_id, kind, player_id, shares, paid, accrued, accrued_day)
    values (v_city, 'docks', v_a, 10, 100000, 0, world.game_day() - 1),
           (v_city, 'docks', v_b, 10, 100000, 0, world.game_day() - 1)
    on conflict (port_id, kind, player_id) do update set paid = 100000, accrued = 0, accrued_day = world.game_day() - 1;
    perform public.treasury_post(v_city, 'PROBE_0148', 100000000, null, null, true);
    perform public.tick_city(now());
    select accrued into v_da from public.city_shares where port_id = v_city and kind = 'docks' and player_id = v_a;
    select accrued into v_db from public.city_shares where port_id = v_city and kind = 'docks' and player_id = v_b;
    if v_db <= 0 or v_da <> round(v_db * public.wc_num('influence_owner_coupon_mult')) then
      raise exception '0148 self-assert FAIL: the holding country''s coupon % is not % × the other''s %', v_da, public.wc_num('influence_owner_coupon_mult'), v_db;
    end if;
    if public.influence_coupon_mult(v_city, v_a) <> 1.5 or public.influence_coupon_mult(v_city, v_b) <> 1 then
      raise exception '0148 self-assert FAIL: the multiplier reader';
    end if;
    update public.world_config set value = 'false'::jsonb where key = 'influence_enabled';
    if public.influence_coupon_mult(v_city, v_a) <> 1 then
      raise exception '0148 self-assert FAIL: dark, the multiplier is not 1';
    end if;
    -- (c) the standings count port_allegiance per country
    v_ns := world.nation_standings();
    if exists (select 1 from jsonb_array_elements(v_ns->'countries') c
                where (c->>'held')::int <> (select count(*) from public.port_allegiance a join public.nations n on n.id = a.nation_id where n.code = c->>'nation')
                   or (c->>'home')::int <> (select count(*) from public.port_allegiance a join public.nations n on n.id = a.nation_id where n.code = c->>'nation' and a.home))
       or jsonb_array_length(v_ns->'countries') <> (select count(*) from public.nations) then
      raise exception '0148 self-assert FAIL: nation_standings does not count port_allegiance: %', v_ns;
    end if;
    v_out := jsonb_build_object('gift', '5,000 → +' || floor(5000 / public.wc_num('fame_ducats_per_point')), 'mayor_day', public.wc_int('fame_per_mayor_day'),
                                'coupons', format('holding country %s, other %s', v_da, v_db));
    raise exception 'PROBE_ROLLBACK_0148';
  exception when others then
    if sqlerrm <> 'PROBE_ROLLBACK_0148' then raise; end if;
  end;
  return v_out;
end $$;

do $$
declare
  v_p jsonb := pg_temp.probe_0148();
begin
  if (select value from public.world_config where key = 'influence_enabled') <> 'false'::jsonb then
    raise exception '0148 self-assert FAIL: the probe left the race lit';
  end if;
  raise notice '0148 self-assert ok: LEADING A CITY IS KNOWN — 5 bodies reverse to their pre-images; player_progress unmoved for houses that gave nothing; %', v_p;
end $$;
