-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0256 — A DEPARTURE READS EACH QUAY ONCE  (the arrivals beat's departure path: the same answers for less work)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE DEFECT, MEASURED (prod, read-only, 2026-10-27/28, head 0252) ────────────────────────────
-- After 0250, public.arrivals_beats (30 min): p50 0.33 s, p95 1.72 s, 15 % of beats over 1 s. A least-squares fit
-- over 1,282 beats against what each wrote (events at the beat's instant): ~167 ms a DEPARTURE (a SAIL with its
-- stores and insurance), ~141 ms a SOLD, ~119 ms a ROUTE_LAP (an arrival planning her next stop), ~7.5 ms a
-- sea-day. Readers timed on prod (600 calls each, CLI wall time minus a baseline): world.quote_terms 4.6 ms,
-- world.spread_effective 1.8 ms, voyage.fleet_speed 2.7 ms, cmd.standing_route_lines ~18 ms a stop.
--
-- ── WHAT SAYS THE OPPOSITE, NAMED ───────────────────────────────────────────────────────────────
-- The same STABLE questions are asked again inside one answer:
--   * world.quote_terms calls world.spread_effective TWICE (with and without the bargain): the port's spread, her
--     purser and her traders (two public.crew_pct each), her house and the investors' shave, all read twice.
--   * cmd.standing_route_lines, for every merchant BUY line, asks the next stop's terms (world.quote), this stop's
--     (public.npc_buy_ceiling) and this stop's again on every step of public.npc_affordable (up to twelve) — and
--     with no fleet named world.quote_terms is the PORT's, the same for every good (0169; world.trade_routes and
--     public.npc_plan already read it once a quay and hand it over).
--   * cmd.do_sail reads voyage.fleet_speed for her report's voyage_days, and voyage.depart reads it again on the
--     very next line, with nothing written between.
-- Local (PGlite, head 0252 + prod's knobs, 835 merchants at sea, each departure / arrival / stop rolled back, old
-- vs these bodies): a SAIL −10 to −14 %, an arrival −9 %, a stop's lines −22 to −33 %.
--
-- ── WHAT THIS FILE DOES ────────────────────────────────────────────────────────────────────────
--   (a) world.spread_effective_pair (new, server-only): world.spread_effective's arithmetic moved there whole; it
--       answers both spreads (with the bargain asked, and with the bargain left at 0) from one reading.
--       world.spread_effective reads its first answer (one hunk: the body).
--   (b) world.quote_terms reads both spreads from one call of it (one hunk).
--   (c) cmd.standing_route_lines reads the two quays' terms once a stop (no fleet named) and hands them to
--       world.quote_priced, public.npc_buy_ceiling and public.npc_affordable (four hunks).
--   (d) cmd.do_sail takes her report's speed from the speed voyage.depart froze for her first segment (one hunk).
--
-- ── WHAT IT DELIBERATELY DOES NOT ───────────────────────────────────────────────────────────────
-- Change a rule, a knob, a flag, a grant, a client read, a signature, the arrivals job or its schedule. Cache
-- anything across statements. Touch world.quote_priced (E6 / E6b re-cut it), voyage.depart or voyage.sail_refusal.
--
-- ── THE PROOF (the self-assert) ─────────────────────────────────────────────────────────────────
-- The old bodies are kept as pg_temp copies (the old quote_terms reading the OLD spread_effective). Old and new
-- answer the same questions: spread_effective (both bargains) and quote_terms for seated, unseated and no fleets
-- over every probe port and good; then again on a rolled-back probe where the seated captains have taken up every
-- trait they hold and each probe house has struck a bargain on every probe quay (one at 0.0000); the lines of
-- merchant routes at every stop; and every pending SAIL (her port time waived) in its own rolled-back block — the
-- SAIL's answer, her voyage row, her fleet and ships, and the events she wrote. Every answer must be identical.
--
-- ── ROLLBACK ────────────────────────────────────────────────────────────────────────────────────
-- A forward slice reversing the hunks below (every OLD text is here verbatim, and the self-assert proves the live
-- bodies reverse to their pre-images by them); world.spread_effective_pair can then be dropped.
--
-- SUPERSEDES: the four bodies named above, sliced from the LIVE bodies (LF-normalised). VERSION: 0256 (after 0255).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('world.quote_terms(uuid,uuid,uuid)') is null
     or to_regprocedure('world.quote_priced(uuid,uuid,numeric,text,numeric,uuid,numeric,numeric,numeric,numeric)') is null
     or to_regprocedure('public.npc_affordable(uuid,uuid,numeric,numeric,numeric,numeric,numeric,numeric)') is null
     or to_regprocedure('public.npc_buy_ceiling(uuid,uuid,numeric,numeric,numeric,numeric,numeric)') is null then
    raise exception '0256 refuses: 0169 / 0181 is not in this world';
  end if;
  if to_regprocedure('world.spread_effective_pair(uuid,uuid,uuid,boolean)') is not null then
    raise exception '0256 refuses: world.spread_effective_pair already exists — this has been applied once';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0256(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 0. THE PRE-IMAGE (LF-normalised) ────────────────────────────────────────────────────────────
create temp table defs_before_0256 on commit drop as
select f.fn, f.name, f.old_name,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values
    ('world.spread_effective(uuid,uuid,uuid,boolean)', 'world.spread_effective', 'pg_temp.spread_effective_old_0256'),
    ('world.quote_terms(uuid,uuid,uuid)',               'world.quote_terms', 'pg_temp.quote_terms_old_0256'),
    ('cmd.standing_route_lines(uuid,integer,uuid)',     'cmd.standing_route_lines', 'pg_temp.standing_route_lines_old_0256'),
    ('cmd.do_sail(uuid,jsonb)',                         'cmd.do_sail', 'pg_temp.do_sail_old_0256')
  ) f(fn, name, old_name);

create temp table before_0256 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points;

-- the old bodies, kept for the self-assert's comparison (the old quote_terms reads the OLD spread_effective)
do $$
declare
  d record;
  v_def text;
begin
  for d in select * from defs_before_0256 loop
    if pg_temp.occurs_0256(d.def, 'FUNCTION ' || d.name || '(') <> 1 then
      raise exception '0256 self-assert FAIL: %''s definition does not name itself once', d.fn;
    end if;
    v_def := replace(d.def, 'FUNCTION ' || d.name || '(', 'FUNCTION ' || d.old_name || '(');
    if d.name = 'world.quote_terms' then
      if pg_temp.occurs_0256(v_def, 'world.spread_effective(') <> 2 then
        raise exception '0256 self-assert FAIL: world.quote_terms does not read world.spread_effective twice';
      end if;
      v_def := replace(v_def, 'world.spread_effective(', 'pg_temp.spread_effective_old_0256(');
    end if;
    execute v_def;
  end loop;
end $$;

-- ── 1. THE PAIR, AND THE RE-CUT ─────────────────────────────────────────────────────────────────
create function world.spread_effective_pair(p_port uuid, p_good uuid, p_fleet uuid, p_with_bargain boolean,
                                          out q_spread numeric, out q_nohag numeric)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $fn$
-- 0256: THE SPREAD THIS HOUSE EXECUTES AT, AND THE SAME WITHOUT THE BARGAIN, FROM ONE READING. The arithmetic of
-- world.spread_effective (0022 / 0083 / 0157 / 0161 / 0191), moved here whole: q_spread is what it answered asked with
-- p_with_bargain, q_nohag what it answered asked with false (the bargain left at its 0). world.spread_effective reads
-- q_spread; world.quote_terms reads both, so a quote asks the port's spread, the purser, the traders and the
-- investors' shave once, not twice. Server-only.
declare
  v_pub    numeric := world.spread(p_port);
  v_player uuid;
  v_purser numeric := 0;
  v_hag    numeric := 0;
  v_nohag  numeric := 0;   -- 0256: the bargain an unbargained answer keeps (spread_effective(..., false) left v_hag here)
  v_trader numeric;   -- 0161
  v_inv    numeric := 0;   -- 0191: the company's standing among this city's givers
  v_floor  numeric;
begin
  -- With no fleet named this is world.spread() exactly, which is what every caller that predates
  -- the purser still passes (0005's own asserts, 0007's capacity walk, 0019's scan).
  if p_fleet is not null then
    select f.player_id into v_player from public.fleets f where f.id = p_fleet;
    v_purser := public.crew_pct(p_fleet, null, 'spread', p_good);   -- 0157: the captains, through the one reader
    -- 0161 (K7): and the traders of THIS good's category (0 while crew_bite is off — then nothing is added)
    v_trader := public.crew_pct(p_fleet, null, 'category_spread', p_good);
    if v_trader <> 0 then
      v_purser := v_purser + v_trader;
    end if;
    -- 0083: asked with p_with_bargain = false this is what the SAME house executes at without
    -- today's bargain — world.quote reads both, so it can say what the bargain saved.
    if v_player is not null and p_with_bargain then
      v_hag := public.haggle_concession(v_player, p_port, p_good);
    end if;
  end if;
  -- 0191: a city's leading givers are spared part of the spread (public.investor_shave) — a standing,
  -- not a bargain, so it holds with or without one.
  if v_player is not null then
    v_inv := public.investor_shave(v_player, p_port);
  end if;
  -- Decision 5: MULTIPLICATIVE, so two shaves cannot add up to more than either could win.
  -- Decision 6: and the floor, which the port keeps whatever stacks.
  v_floor  := public.wc_num('haggle_spread_floor_frac');
  q_spread := greatest(v_pub * v_floor, v_pub * (1 - v_purser) * (1 - v_hag) * (1 - v_inv));
  q_nohag  := greatest(v_pub * v_floor, v_pub * (1 - v_purser) * (1 - v_nohag) * (1 - v_inv));
end $fn$;
revoke all on function world.spread_effective_pair(uuid, uuid, uuid, boolean) from public;

create temp table hunks_0256 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0256 (fn, n, old, new) values
('world.spread_effective(uuid,uuid,uuid,boolean)', 1,
$h$declare
  v_pub    numeric := world.spread(p_port);
  v_player uuid;
  v_purser numeric := 0;
  v_hag    numeric := 0;
  v_trader numeric;   -- 0161
  v_inv    numeric := 0;   -- 0191: the company's standing among this city's givers
begin
  -- With no fleet named this is world.spread() exactly, which is what every caller that predates
  -- the purser still passes (0005's own asserts, 0007's capacity walk, 0019's scan).
  if p_fleet is not null then
    select f.player_id into v_player from public.fleets f where f.id = p_fleet;
    v_purser := public.crew_pct(p_fleet, null, 'spread', p_good);   -- 0157: the captains, through the one reader
    -- 0161 (K7): and the traders of THIS good's category (0 while crew_bite is off — then nothing is added)
    v_trader := public.crew_pct(p_fleet, null, 'category_spread', p_good);
    if v_trader <> 0 then
      v_purser := v_purser + v_trader;
    end if;
    -- 0083: asked with p_with_bargain = false this is what the SAME house executes at without
    -- today's bargain — world.quote reads both, so it can say what the bargain saved.
    if v_player is not null and p_with_bargain then
      v_hag := public.haggle_concession(v_player, p_port, p_good);
    end if;
  end if;

  -- 0191: a city's leading givers are spared part of the spread (public.investor_shave) — a standing,
  -- not a bargain, so it holds with or without one.
  if v_player is not null then
    v_inv := public.investor_shave(v_player, p_port);
  end if;

  -- Decision 5: MULTIPLICATIVE, so two shaves cannot add up to more than either could win.
  -- Decision 6: and the floor, which the port keeps whatever stacks.
  return greatest(v_pub * public.wc_num('haggle_spread_floor_frac'),
                  v_pub * (1 - v_purser) * (1 - v_hag) * (1 - v_inv));
end$h$,
$h$declare
  v_spread numeric;
begin
  -- 0256: THE ARITHMETIC IS world.spread_effective_pair's (moved there whole): this is its first answer, the spread
  -- this house executes at (with today's bargain unless p_with_bargain is false).
  select p.q_spread into v_spread from world.spread_effective_pair(p_port, p_good, p_fleet, p_with_bargain) p;
  return v_spread;
end$h$),
('world.quote_terms(uuid,uuid,uuid)', 1,
$h$  q_spread := world.spread_effective(p_port, p_good, p_fleet);
  -- 0083: what the same house pays with no bargain; with no fleet named there is no bargain.
  q_nohag  := case when p_fleet is null then q_spread
                   else world.spread_effective(p_port, p_good, p_fleet, false) end;$h$,
$h$  -- 0256: both spreads from ONE reading (world.spread_effective_pair: the port's spread, her purser and traders, her
  -- standing among the givers read once; q_nohag is the same arithmetic with the bargain left at 0) — it was read twice.
  select p.q_spread, p.q_nohag into q_spread, q_nohag
    from world.spread_effective_pair(p_port, p_good, p_fleet, true) p;
  -- 0083: what the same house pays with no bargain; with no fleet named there is no bargain.
  q_nohag  := case when p_fleet is null then q_spread
                   else q_nohag end;$h$),
('cmd.standing_route_lines(uuid,integer,uuid)', 1,
$h$  v_patience numeric; -- 0181: her house's patience (null on a player's route)
begin$h$,
$h$  v_patience numeric; -- 0181: her house's patience (null on a player's route)
  v_terms  boolean := false;   -- 0256: the two quays' terms are read (once a stop, at the first merchant BUY)
  ks       record;             -- 0256: the next stop's four terms (world.quote_terms, no fleet named)
  kb       record;             -- 0256: this stop's four terms (world.quote_terms, no fleet named)
begin$h$),
('cmd.standing_route_lines(uuid,integer,uuid)', 2,
$h$      continue when ln.qty is null;
      select * into q from world.quote(v_sink, ln.good_id, ln.qty, 'sell', null, null);$h$,
$h$      continue when ln.qty is null;
      -- 0256: THE QUAYS' TERMS, ONCE A STOP. Asked with no fleet named, world.quote_terms is the port's own, the
      -- same for every good (0169: why world.trade_routes and public.npc_plan read them once a quay); every line
      -- below read both quays' again (world.quote; npc_buy_ceiling; npc_affordable, up to twelve times).
      if not v_terms then
        select * into ks from world.quote_terms(v_sink, null, null);
        select * into kb from world.quote_terms(st.port_id, null, null);
        v_terms := true;
      end if;
      select * into q from world.quote_priced(v_sink, ln.good_id, ln.qty, 'sell', null, null,
                                              ks.q_spread, ks.q_nohag, ks.q_tax, ks.q_bidf);$h$),
('cmd.standing_route_lines(uuid,integer,uuid)', 3,
$h$      ln.price_limit := least(coalesce(public.npc_buy_ceiling(st.port_id, ln.good_id, v_patience), v_cap), v_cap);$h$,
$h$      ln.price_limit := least(coalesce(public.npc_buy_ceiling(st.port_id, ln.good_id, v_patience,
                                                              kb.q_spread, kb.q_nohag, kb.q_tax, kb.q_bidf), v_cap), v_cap);$h$),
('cmd.standing_route_lines(uuid,integer,uuid)', 4,
$h$      select * into v_aff from public.npc_affordable(st.port_id, ln.good_id, ln.qty, v_budget);$h$,
$h$      select * into v_aff from public.npc_affordable(st.port_id, ln.good_id, ln.qty, v_budget,
                                                     kb.q_spread, kb.q_nohag, kb.q_tax, kb.q_bidf);$h$),
('cmd.do_sail(uuid,jsonb)', 1,
$h$  v_speed := voyage.fleet_speed(p_fleet);
  v_voyage := voyage.depart(p_fleet, v_segs, f.port_id, v_dest);$h$,
$h$  v_voyage := voyage.depart(p_fleet, v_segs, f.port_id, v_dest);
  -- 0256: the speed voyage.depart froze for her first segment (its own voyage.fleet_speed, read at the very state
  -- this line read it at: nothing is written between) — the same number, not a fifth reading of her speed.
  select (v.speed_profile ->> 0)::numeric into v_speed from public.voyages v where v.id = v_voyage;$h$);

create or replace function pg_temp.recut_0256(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := (select def from defs_before_0256 where fn = p_fn);
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0256 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0256(v_def, h.old);
    if v_n <> 1 then
      raise exception '0256 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0256(fn) from defs_before_0256 order by fn;

-- ── 2. THE PROBE: old and new answer the same questions ─────────────────────────────────────────
-- p_plant: the seated captains of the probe fleets take up every trait they hold (and a few they do not), and every
-- probe house strikes a bargain on every probe quay and good (the first good at 0.0000, the rest at 0.0400), inside
-- this block, which is rolled back.
create or replace function pg_temp.probe_0256(p_plant boolean)
returns jsonb
language plpgsql
as $$
declare
  v_fleets uuid[];
  v_ports  uuid[];
  v_goods  uuid[];
  f        uuid;
  p        uuid;
  g        uuid;
  b        boolean;
  r        record;
  v_a      text;
  v_b      text;
  v_n      int := 0;
  v_purse  int := 0;     -- spread answers where her purser / traders shaved something
  v_hagged int := 0;     -- quote terms where the bargain moved the spread
  v_lines  int := 0;
  v_bought int := 0;     -- merchant BUY lines written (the path the terms are handed down)
  v_bad    jsonb := '[]'::jsonb;
  v_planted int := 0;
begin
  begin
    v_fleets := array(
      (select f0.id from public.fleets f0
        where exists (select 1 from public.ships s0 join public.captain_seats cs on cs.ship_id = s0.id where s0.fleet_id = f0.id)
        order by f0.id limit 16)
      union all
      (select f0.id from public.fleets f0
        where exists (select 1 from public.ships s0 where s0.fleet_id = f0.id)
          and not exists (select 1 from public.ships s0 join public.captain_seats cs on cs.ship_id = s0.id where s0.fleet_id = f0.id)
        order by f0.id limit 6));
    v_ports := array(select x.id from (select po.id from public.ports po where po.kind = 'HARBOUR' order by po.code limit 5) x
                     union all
                     select x.id from (select f0.port_id as id from public.fleets f0 where f0.id = any(v_fleets) and f0.port_id is not null limit 3) x);
    -- a good of every traders' category first (category_spread), then the cheapest few
    v_goods := array(select x.id from (select distinct on (tr.goods) g0.id from public.goods g0 join public.traits tr on tr.goods = g0.category
                                         order by tr.goods, g0.code limit 3) x
                     union all
                     select x.id from (select g0.id from public.goods g0 order by g0.code limit 2) x);

    if p_plant then
      insert into public.captain_active (player_officer_id, trait)
      select cs.player_officer_id, ct.trait
        from public.ships s0 join public.captain_seats cs on cs.ship_id = s0.id
        join public.player_officers po on po.id = cs.player_officer_id
        join public.captain_traits ct on ct.officer_id = po.officer_id
       where s0.fleet_id = any(v_fleets)
      on conflict do nothing;
      get diagnostics v_planted = row_count;
      insert into public.haggle_daily (player_id, port_id, good_id, game_day, concession)
      select distinct f0.player_id, pp.id, gg.id, world.game_day(), case when gg.o = 1 then 0.0000 else 0.0400 end
        from public.fleets f0 cross join unnest(v_ports) pp(id) cross join unnest(v_goods) with ordinality gg(id, o)
       where f0.id = any(v_fleets) and f0.player_id is not null
      on conflict do nothing;
    end if;

    -- (a)(b) spread_effective (both bargains) and quote_terms: every probe fleet, and none, on every probe quay and good
    foreach p in array v_ports loop
      foreach g in array v_goods loop
        for f in select x from unnest(v_fleets || array[null::uuid]) x loop
          foreach b in array array[true, false] loop
            begin v_a := pg_temp.spread_effective_old_0256(p, g, f, b)::text; exception when others then v_a := 'ERR ' || sqlstate || ' ' || sqlerrm; end;
            begin v_b := world.spread_effective(p, g, f, b)::text;             exception when others then v_b := 'ERR ' || sqlstate || ' ' || sqlerrm; end;
            v_n := v_n + 1;
            if v_a is distinct from v_b then
              v_bad := v_bad || jsonb_build_array(jsonb_build_object('fn', 'spread_effective', 'port', p, 'good', g, 'fleet', f, 'bargain', b, 'old', v_a, 'new', v_b));
            elsif f is not null and not b and v_b not like 'ERR%'
                  and v_b::numeric <> pg_temp.spread_effective_old_0256(p, g, null, false) then
              v_purse := v_purse + 1;
            end if;
          end loop;
          begin select to_jsonb(k)::text into v_a from pg_temp.quote_terms_old_0256(p, g, f) k; exception when others then v_a := 'ERR ' || sqlstate || ' ' || sqlerrm; end;
          begin select to_jsonb(k)::text into v_b from world.quote_terms(p, g, f) k;             exception when others then v_b := 'ERR ' || sqlstate || ' ' || sqlerrm; end;
          v_n := v_n + 1;
          if v_a is distinct from v_b then
            v_bad := v_bad || jsonb_build_array(jsonb_build_object('fn', 'quote_terms', 'port', p, 'good', g, 'fleet', f, 'old', v_a, 'new', v_b));
          elsif v_b not like 'ERR%' and (v_b::jsonb->>'q_spread') is distinct from (v_b::jsonb->>'q_nohag') then
            v_hagged := v_hagged + 1;
          end if;
        end loop;
      end loop;
    end loop;

    -- (c) the lines: merchant routes (and every player route) at every stop
    for r in select sr.id, sr.fleet_id, s.ord
               from (select sr0.* from public.standing_routes sr0 where sr0.fleet_id is not null
                      order by (sr0.id in (select nf.route_id from public.npc_fleets nf)), sr0.id limit 120) sr
               join public.standing_route_stops s on s.route_id = sr.id
              order by sr.id, s.ord loop
      begin v_a := pg_temp.standing_route_lines_old_0256(r.id, r.ord, r.fleet_id)::text; exception when others then v_a := 'ERR ' || sqlstate || ' ' || sqlerrm; end;
      begin v_b := cmd.standing_route_lines(r.id, r.ord, r.fleet_id)::text;              exception when others then v_b := 'ERR ' || sqlstate || ' ' || sqlerrm; end;
      v_n := v_n + 1; v_lines := v_lines + 1;
      if v_a is distinct from v_b then
        v_bad := v_bad || jsonb_build_array(jsonb_build_object('fn', 'standing_route_lines', 'route', r.id, 'stop', r.ord, 'old', v_a, 'new', v_b));
      else
        v_bought := v_bought + coalesce((select count(*) from unnest(v_b::text[]) x where x like 'BUY %'), 0);
      end if;
    end loop;

    raise exception using errcode = 'ZY256', message = jsonb_build_object('asked', v_n, 'fleets', cardinality(v_fleets),
      'ports', cardinality(v_ports), 'goods', cardinality(v_goods), 'purse', v_purse, 'hagged', v_hagged, 'lines', v_lines,
      'bought', v_bought, 'planted', v_planted, 'bad', jsonb_array_length(v_bad), 'first_bad', v_bad -> 0)::text;
  exception when sqlstate 'ZY256' then
    return sqlerrm::jsonb;
  end;
end $$;

-- (d) a SAIL (it writes): in its own rolled-back block, her port time waived — what she answered, her voyage, her fleet,
-- her ships, and the events she wrote (ids blanked: a voyage id is drawn at random)
create or replace function pg_temp.sail_0256(p_new boolean, p_fleet uuid, p_args jsonb)
returns text
language plpgsql
as $$
declare
  v_res jsonb;
  v_out text;
begin
  begin
    update public.fleets set ready_at = null where id = p_fleet;
    if p_new then
      v_res := cmd.do_sail(p_fleet, p_args);
    else
      v_res := pg_temp.do_sail_old_0256(p_fleet, p_args);
    end if;
    select jsonb_build_object('res', v_res,
             'voyage', (select to_jsonb(v) - 'id' from public.voyages v where v.id = (v_res->>'voyage_id')::uuid),
             'fleet', (select to_jsonb(f) from public.fleets f where f.id = p_fleet),
             'ships', (select jsonb_agg(to_jsonb(s) order by s.id) from public.ships s where s.fleet_id = p_fleet),
             'events', (select jsonb_agg(to_jsonb(e) - 'id' order by e.kind, e.payload::text) from public.events e where e.created_at = now()))::text
      into v_out;
    raise exception using errcode = 'ZY256', message = regexp_replace(v_out, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', 'U', 'g');
  exception
    when sqlstate 'ZY256' then return sqlerrm;
    when others then return 'ERR ' || sqlstate || ' ' || sqlerrm;
  end;
end $$;

-- ── 3. THE SELF-ASSERT ──────────────────────────────────────────────────────────────────────────
do $$
declare
  v_before record;
  v_d   record; v_h record; v_pp record; v_def text;
  v_live  jsonb;
  v_plant jsonb;
  o     record;
  v_a   text;
  v_b   text;
  v_sails int := 0;
  v_sailed int := 0;
  v_sbad  jsonb := '[]'::jsonb;
begin
  select * into v_before from before_0256;

  -- (a) THE RE-CUT reverses to its pre-image; ACL / volatility / definer / config unmoved; the pair as private
  for v_d in select * from defs_before_0256 loop
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    if pg_temp.occurs_0256(v_def, '0256') = 0 then
      raise exception '0256 self-assert FAIL: % was not re-cut', v_d.fn;
    end if;
    for v_h in select * from hunks_0256 where fn = v_d.fn order by n desc loop
      if pg_temp.occurs_0256(v_def, v_h.new) <> 1 then
        raise exception '0256 self-assert FAIL: hunk % of % is not in the new body exactly once', v_h.n, v_d.fn;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0256 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg
      into v_pp from pg_proc p where p.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0256 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;
  select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg
    into v_pp from pg_proc p where p.oid = 'world.spread_effective_pair(uuid,uuid,uuid,boolean)'::regprocedure;
  select * into v_d from defs_before_0256 where fn = 'world.spread_effective(uuid,uuid,uuid,boolean)';
  if v_pp.acl <> v_d.acl or v_pp.vol <> 's' or not v_pp.secdef or v_pp.cfg <> v_d.cfg then
    raise exception '0256 self-assert FAIL: world.spread_effective_pair is not as private and stable as world.spread_effective (% / %)', v_pp.acl, v_d.acl;
  end if;
  -- the readers asked twice are asked once
  if pg_temp.occurs_0256(replace(pg_get_functiondef('world.quote_terms(uuid,uuid,uuid)'::regprocedure), E'\r', ''), 'world.spread_effective(') <> 0
     or pg_temp.occurs_0256(replace(pg_get_functiondef('world.quote_terms(uuid,uuid,uuid)'::regprocedure), E'\r', ''), 'world.spread_effective_pair(') <> 1
     or pg_temp.occurs_0256(replace(pg_get_functiondef('cmd.standing_route_lines(uuid,integer,uuid)'::regprocedure), E'\r', ''), 'world.quote_terms(') <> 2
     or pg_temp.occurs_0256(replace(pg_get_functiondef('cmd.standing_route_lines(uuid,integer,uuid)'::regprocedure), E'\r', ''), 'world.quote(') <> 0
     or pg_temp.occurs_0256(replace(pg_get_functiondef('cmd.do_sail(uuid,jsonb)'::regprocedure), E'\r', ''), 'voyage.fleet_speed(') <> 0 then
    raise exception '0256 self-assert FAIL: a quote still reads the spread twice, a stop its quays'' terms a line, or the SAIL her speed again';
  end if;

  -- (b) SAME ANSWERS: as it stands, and with captains and bargains planted (rolled back)
  v_live  := pg_temp.probe_0256(false);
  v_plant := pg_temp.probe_0256(true);
  if (v_live->>'bad')::int <> 0 or (v_plant->>'bad')::int <> 0 then
    raise exception '0256 self-assert FAIL: old and new answered differently: live % / planted %', v_live, v_plant;
  end if;
  if (v_live->>'fleets')::int = 0 or (v_live->>'lines')::int = 0 or (v_plant->>'hagged')::int = 0 or (v_plant->>'purse')::int = 0
     or (v_live->>'bought')::int = 0 then
    raise exception '0256 self-assert FAIL: the probe proved nothing (no fleet, no stop, no merchant BUY, no bargain or purser that moved a spread): live % / planted %', v_live, v_plant;
  end if;

  -- (c) every pending SAIL, old and new, each in its own rolled-back block
  for o in select o0.fleet_id, o0.args from public.orders o0 join public.fleets f0 on f0.id = o0.fleet_id
            where o0.status = 'pending' and o0.verb = 'SAIL' and f0.status in ('DOCKED', 'ANCHORED')
            order by o0.issued_at, o0.id limit 40 loop
    v_a := pg_temp.sail_0256(false, o.fleet_id, o.args);
    v_b := pg_temp.sail_0256(true, o.fleet_id, o.args);
    v_sails := v_sails + 1;
    if v_a is distinct from v_b then
      v_sbad := v_sbad || jsonb_build_array(jsonb_build_object('fleet', o.fleet_id, 'old', left(v_a, 600), 'new', left(v_b, 600)));
    elsif v_b not like 'ERR%' then
      v_sailed := v_sailed + 1;
    end if;
  end loop;
  if jsonb_array_length(v_sbad) <> 0 then
    raise exception '0256 self-assert FAIL: a SAIL answered differently: %', v_sbad -> 0;
  end if;

  -- (d) POSTURE
  if (select count(*) from public.client_rpc_entry_points()) <> v_before.entry_points then
    raise exception '0256 self-assert FAIL: the registry moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0256 self-assert FAIL: a wall moved';
  end if;

  raise notice '0256 self-assert ok: A DEPARTURE READS EACH QUAY ONCE. world.spread_effective_pair minted (private, stable, as world.spread_effective); four bodies re-cut by seven hunks (spread_effective, quote_terms, standing_route_lines, do_sail), each reversed to its pre-image, ACL / volatility / definer / config unmoved; registry unchanged; walls 0. OLD vs NEW, as it stands: % questions over % fleets / % quays / % goods (% spreads shaved by a purser or trader; % stops'' lines, % merchant BUYs), 0 different; with % traits taken up and a bargain struck on every probe quay (rolled back): % questions (% spreads shaved, % quotes moved by the bargain), 0 different; % pending SAILs (% sailed) alike, each rolled back. Nothing left behind.',
    v_live->>'asked', v_live->>'fleets', v_live->>'ports', v_live->>'goods', v_live->>'purse', v_live->>'lines', v_live->>'bought',
    v_plant->>'planted', v_plant->>'asked', v_plant->>'purse', v_plant->>'hagged', v_sails, v_sailed;
end $$;
