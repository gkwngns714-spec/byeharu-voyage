-- 0272 — A CREW SHORTAGE IS PAID FROM THE HOLD   (the E_CREW_SHORT loop: a broke merchant sells to hire)
--
-- THE ROOT, proven on prod 2026-10-29 (head 0269; the reads and the report are docs/dev-log/2026-10-29-crew-short.md).
-- Two live merchants on "Carrera Izmir" routes (1b52a58e-…, lap 845, 19 clears, ship 10/12, purse 0; 63ade18d-…, lap 537,
-- 7 clears, ship 11/12, purse 0) lie DOCKED. Their stop tail renders `HIRE n` (0096:1114-1143); cmd.do_hire refuses
-- E_INSUFFICIENT_FUNDS (0007:675-678); cmd.advance's route rule writes the refused HIRE `skipped` and runs the SAIL
-- behind it (0092:743-748), which fails E_CREW_SHORT (0050:354-362). The halt law clears her hourly, and from the third
-- clear of a lap every clear re-plans her (0150's rule, now public.npc_clear_due) — but a plan writes LINES, never crew,
-- and it only sells at a profit. So the same refused HIRE and the same refused SAIL repeat for ever, one clear an hour.
-- Her money is in her hold, not her purse: at the quay's own bid it is worth 201 / 273 d. against hires of 40 / 20 d.
--
-- THE FIX (one change; one authority per concept):
--   1. public.npc_crew_blocked(fleet, from) — beside public.npc_casks_blocked (0150:172-209): she lies docked at `from`,
--      her fleet is short of complement, a hire would restore it (the quay has hands to sell, so cmd.do_hire would not
--      refuse E_CREW_POOL), her purse is below what that hire costs, and her hold at that quay's bid covers it.
--   2. public.npc_leg_lines — THE CUT-LOSS FOR CREW, seated after 0150's cut-loss for room and before the leg's answer:
--      when npc_crew_blocked is true, enough of the hold goes at the quay's bid (no profit test — the same SELL 0150
--      writes for room) for the HIRE the stop tail writes after these lines to be paid. Whole stacks, the largest bid
--      value first, until the hire's cost is covered; a stack is never split.
--   3. public.npc_clear_due — 0270's rule gains ONE clause: a SAIL refused E_CREW_SHORT re-plans her on the FIRST clear,
--      exactly as a SAIL refused E_ENDURANCE does (0150:219-232), so the cut-loss is written before the next SAIL.
--   NOTHING ELSE MOVES: the halt law, the clear, advance's skipped-HIRE handling, the hire price, the stop tail and its
--   HIRE line, the renderer, the quay, crew_pct / crew_terms, every knob, every ACL, every client entry point.
--
-- THE HIRE PRICE IS NOT RESTATED. public.crew_hire_cost(fleet, n) (0154:331-369) is THE one reading of what hiring n
-- hands costs a fleet where she lies — its own comment: "cmd.do_hire charges it and draws the pool by its split; the
-- Inn's price is cmd.preview of that door." The coverage test and the cut-loss both ask it. No rate, pool floor, skill
-- discount or urgent multiplier is spelled in this file, so the plan and the refused HIRE cannot disagree.
--
-- SUPERSEDE (supabase/migrations/README.md:43-48). This file re-cuts TWO live functions, by hunks sliced from their
-- bodies (each hunk asserts it occurs exactly once and reverses to its pre-image):
--   * public.npc_leg_lines(uuid, uuid, uuid, numeric, integer, numeric) — 0120's body, as last re-cut by 0142, 0147,
--     0150 (the cut-loss for room), 0180, 0181 and 0209; two hunks: three declarations and the crew cut-loss itself.
--   * public.npc_clear_due(uuid, uuid, int, text, text) — 0270's body (itself the one authority for 0150's rule); two
--     hunks: the rule's comment and the plan expression. Its COMMENT is re-issued so the catalogue reads true.
-- IT IS A NO-OP WHEN THE NEW INPUT IS ABSENT. public.npc_leg_lines: when npc_crew_blocked is false — she is not docked
-- at p_from, or no hull is below complement, or the quay has no hands, or her purse covers the hire, or her hold cannot
-- cover it at the bid — the block writes no line, reads no quote, and every value the leg answers (lines, profit,
-- wages, nm, any) is exactly 0142/0150's. public.npc_clear_due: unless the failed order is a SAIL refused E_CREW_SHORT
-- it answers exactly what 0270 answered (n, and plan = n >= 3 or E_ENDURANCE).
-- Everything that must move together moves in this one file: the rule that decides she is blocked, the cut-loss that
-- pays her hire, and the first-clear clause that runs the plan before the next SAIL.
--
-- WHAT IS NOT PROVEN (said plainly; the dev-log says it again). A house with NEITHER coin NOR saleable cargo is not
-- helped: npc_crew_blocked is false and the loop continues as today — that needs its own owner decision. The cut-loss
-- covers the HIRE, not a PROVISION that may run between the sale and the hire in the same stop: do_provision is
-- all-or-nothing (0007:602-607), so a stop whose store top-up the sale also pays may spend it before the HIRE. The next
-- clear re-plans (the new clause guarantees it) and sells again while the hold still covers; the store level is then
-- met, so the drain happens at most once. Selling at the bid forsakes the profit the at-profit SELL would have taken.
--
-- PROD CHECKS (before the push; read-only; in the PR body): the two live bodies are the ones the hunks were cut
-- against (their md5 / pg_get_functiondef); the two stuck routes still read purse 0, a shortfall of 1-2 and a hold
-- worth 5-13x the hire (41_cargo_value.sql). AFTER THE DEPLOY: for routes 1b52a58e… and 63ade18d…, NPC_CLEARED per
-- hour falls to none, their purses stop reading 0, their hulls come back to crew_required and their laps close (the
-- after-check in the dev-log).
--
-- VERSION: 0272 (prod head 0269; 0270 and 0271 are applied before this one, in number order).

-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('public.npc_clear_due(uuid,uuid,int,text,text)') is null
     or to_regprocedure('public.crew_hire_cost(uuid,integer)') is null
     or to_regprocedure('public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)') is null then
    raise exception '0272 refuses: 0270 is not in this world';
  end if;
  if to_regprocedure('public.npc_crew_blocked(uuid,uuid)') is not null then
    raise exception '0272 refuses: public.npc_crew_blocked already exists — this has been applied once';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0272(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 0. AS FOUND ─────────────────────────────────────────────────────────────────────────────────
create temp table defs_before_0272 on commit drop as
select f.fn, replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)'),
               ('public.npc_clear_due(uuid,uuid,int,text,text)')) f(fn);

-- EVERY function in the four schemas except the two this file re-cuts: one md5 over the lot, so a body that moves
-- without being named here is caught — the functions both bodies decide with included, by construction.
create temp table before_0272 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
           and p.oid not in (to_regprocedure('public.npc_leg_lines(uuid,uuid,uuid,numeric,int,numeric)'),
                             to_regprocedure('public.npc_clear_due(uuid,uuid,int,text,text)'))) as fns,
       (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
           and p.oid not in (to_regprocedure('public.npc_leg_lines(uuid,uuid,uuid,numeric,int,numeric)'),
                             to_regprocedure('public.npc_clear_due(uuid,uuid,int,text,text)'))) as others_md5,
       (select string_agg(p.oid::regprocedure::text, ',' order by p.oid::regprocedure::text)
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname not in ('pg_catalog', 'information_schema') and n.nspname not like 'pg_temp%'
           and p.prokind in ('f', 'p') and pg_get_functiondef(p.oid) like '%hold_the_quay()%') as quay_takers;

-- ── 1. THE ONE RULE: SHE IS BELOW COMPLEMENT AND CANNOT PAY THE HIRE ───────────────────────────
create function public.npc_crew_blocked(p_fleet uuid, p_from uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0272: SHE CANNOT PAY THE HIRE SHE NEEDS TO SAIL. She lies docked at p_from, her fleet is short of
-- complement (public.fleet_crew_shortfall), the quay has hands to sell (cmd.do_hire's own E_CREW_POOL
-- floor, 0007:666-670), the hands that would restore her cost more than her purse holds
-- (public.crew_hire_cost — THE one hire price, 0154), and the goods in her hold, at this quay's own bid,
-- are worth at least that. Read by public.npc_leg_lines (the cut-loss for crew) and by its probe.
-- Reads fleets, ports, players, ships and goods, and asks world.quote: no lock, no write, no clock.
declare
  f       public.fleets%rowtype;
  v_short int;
  v_cost  bigint;
  v_have  numeric := 0;
  g       record;
begin
  if p_fleet is null or p_from is null then
    return false;
  end if;
  select * into f from public.fleets where id = p_fleet;
  if f.id is null or f.status <> 'DOCKED' or f.port_id is distinct from p_from then
    return false;
  end if;
  v_short := public.fleet_crew_shortfall(p_fleet);
  if v_short <= 0 then
    return false;
  end if;
  if not exists (select 1 from public.ports p where p.id = p_from and coalesce(p.crew_pool, 0) > 0) then
    return false;   -- no hands at all: cmd.do_hire refuses E_CREW_POOL, so there is no hire to pay
  end if;
  v_cost := (public.crew_hire_cost(p_fleet, v_short)->>'cost')::bigint;
  if v_cost is null or v_cost <= 0 then
    return false;
  end if;
  if (select p.ducats from public.players p where p.id = f.player_id) >= v_cost then
    return false;   -- her purse already covers it: nothing must be sold
  end if;
  for g in select z.code, gd.id as good_id, z.qty
             from (select e.key as code, sum((e.value)::text::numeric) as qty
                     from public.ships s cross join lateral jsonb_each(s.cargo) e
                    where s.fleet_id = p_fleet and (e.value)::text::numeric > 0
                    group by e.key) z
             join public.goods gd on gd.code = z.code
            order by z.code loop
    v_have := v_have + coalesce((select q.total from world.quote(p_from, g.good_id, g.qty, 'sell', null, null) q), 0);
    exit when v_have >= v_cost;
  end loop;
  return v_have >= v_cost;
end $$;
comment on function public.npc_crew_blocked(uuid, uuid) is
  '0272: true when a merchant lies docked at p_from below complement and cannot pay the hire that would restore '
  'her from her purse, while her hold at that quay''s bid covers it. The price is public.crew_hire_cost''s (0154), '
  'the one cmd.do_hire charges. Read by public.npc_leg_lines (the cut-loss for crew). Server-only.';
revoke all on function public.npc_crew_blocked(uuid, uuid) from public, anon, authenticated;

-- ── 2. THE HUNKS ────────────────────────────────────────────────────────────────────────────────
create temp table hunks_0272 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0272 (fn, n, old, new) values
-- ── public.npc_clear_due: the rule's comment and ONE clause in the plan expression ──
('public.npc_clear_due(uuid,uuid,int,text,text)', 1,
$h$--   plan = 0150: the third clear of her lap, or her SAIL refused E_ENDURANCE (a clear alone re-sends the SAIL
--          and nothing else; only a plan answers it).
$h$,
$h$--   plan = 0150: the third clear of her lap, or her SAIL refused E_ENDURANCE (a clear alone re-sends the SAIL
--          and nothing else; only a plan answers it); 0272: or her SAIL refused E_CREW_SHORT — she is below
--          complement and cannot pay the hire, and only a plan can write the cut-loss that pays it.
$h$),
('public.npc_clear_due(uuid,uuid,int,text,text)', 2,
$h$  return jsonb_build_object('n', v_n, 'plan', v_n >= 3 or (p_verb = 'SAIL' and p_error_code = 'E_ENDURANCE'));
$h$,
$h$  -- 0272: a SAIL refused E_CREW_SHORT is answered on the FIRST clear, as E_ENDURANCE is: the cut-loss for crew
  -- (public.npc_leg_lines) must be written before the next SAIL, not after the count reaches three.
  return jsonb_build_object('n', v_n, 'plan', v_n >= 3
         or (p_verb = 'SAIL' and p_error_code in ('E_ENDURANCE', 'E_CREW_SHORT')));
$h$),
-- ── public.npc_leg_lines: three declarations, then the cut-loss for crew before the leg answers ──
('public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)', 1,
$h$  k_to      record;   -- 0209: the sink's
begin
$h$,
$h$  k_to      record;   -- 0209: the sink's
  v_need    bigint;   -- 0272: what the hire the stop tail will ask for costs (public.crew_hire_cost)
  v_have    numeric;  -- 0272: what the hold's goods let go so far are worth at this quay's bid
  v_bid     numeric;  -- 0272: one good's whole stack at this quay's bid
begin
$h$),
('public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)', 2,
$h$  return jsonb_build_object('lines', v_lines, 'profit', v_profit, 'wages', v_wages,
$h$,
$h$  -- 0272: THE CUT-LOSS FOR CREW. Her fleet lies at this quay below complement, her purse cannot pay the HIRE
  -- the tail behind these lines will ask for, and her hold covers it at the bid (public.npc_crew_blocked) —
  -- so enough of the hold goes at the quay's bid (no AT, no profit test: 0142's own cut-loss form, the same
  -- SELL 0150 writes for room) for that HIRE to be paid. Whole stacks, the largest bid value first, until the
  -- hire's cost is covered; the price is public.crew_hire_cost's, the one cmd.do_hire charges.
  if public.npc_crew_blocked(sr.fleet_id, p_from) then
    v_need := (public.crew_hire_cost(sr.fleet_id, public.fleet_crew_shortfall(sr.fleet_id))->>'cost')::bigint;
    v_have := 0;
    for v_cut, v_bid in
      select z.code, coalesce((select q.total from world.quote(p_from, z.good_id, z.qty, 'sell', null, null) q), 0)
        from (select e.key as code, gd.id as good_id, sum((e.value)::text::numeric) as qty
                from public.ships s cross join lateral jsonb_each(s.cargo) e
                join public.goods gd on gd.code = e.key
               where s.fleet_id = sr.fleet_id and (e.value)::text::numeric > 0
               group by e.key, gd.id) z
       order by 2 desc, 1
    loop
      exit when v_have >= coalesce(v_need, 0);
      continue when v_lines @> jsonb_build_array(jsonb_build_object('kind', 'SELL', 'good', v_cut));
      v_lines := v_lines || jsonb_build_object('kind', 'SELL', 'good', v_cut, 'at_profit', false);
      v_have  := v_have + v_bid;
    end loop;
  end if;

  return jsonb_build_object('lines', v_lines, 'profit', v_profit, 'wages', v_wages,
$h$);

-- THE OLD BODIES, kept whole for the probe's OLD / NEW switch (0270's shape: the live text, re-installed as it is)
create temp table old_bodies_0272 (fn text, old_def text) on commit drop;
insert into old_bodies_0272 (fn, old_def)
select 'leg', def from defs_before_0272 where fn = 'public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)';
insert into old_bodies_0272 (fn, old_def)
select 'due', def from defs_before_0272 where fn = 'public.npc_clear_due(uuid,uuid,int,text,text)';

-- THE HUNKS, each once, then the new bodies
do $$
declare
  d   record;
  h   record;
  v_def text;
  v_n int;
begin
  for d in select * from defs_before_0272 order by fn loop
    v_def := d.def;
    for h in select * from hunks_0272 where fn = d.fn order by n loop
      v_n := pg_temp.occurs_0272(v_def, h.old);
      if v_n <> 1 then
        raise exception '0272 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against', h.n, d.fn, v_n;
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    execute v_def;
  end loop;
end $$;

-- the new bodies, for the probe's OLD / NEW switch
create temp table new_bodies_0272 (fn text, new_def text) on commit drop;
insert into new_bodies_0272 (fn, new_def) values
  ('leg', replace(pg_get_functiondef('public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)'::regprocedure), E'\r', '')),
  ('due', replace(pg_get_functiondef('public.npc_clear_due(uuid,uuid,int,text,text)'::regprocedure), E'\r', ''));

-- the function's own comment is re-issued so the catalogue reads the whole rule
comment on function public.npc_clear_due(uuid, uuid, int, text, text) is
  '0270: a merchant''s place in her lap''s clears (her NPC_CLEARED events of this lap + 1) and 0150''s re-plan '
  'rule (the third clear of the lap, or a SAIL refused E_ENDURANCE; 0272: or a SAIL refused E_CREW_SHORT), in '
  'one place: read by public.npc_tend_route''s clear branch and by its plan pass. Server-only.';

-- ── 3. THE PROBES' EYES ─────────────────────────────────────────────────────────────────────────
-- a merchant's rows after a run (uuids blanked: new rows carry new ones) — 0269's / 0270's shape
create function pg_temp.digest_0272(p_fleet uuid, p_route uuid, p_house uuid)
returns text
language sql
as $$
select regexp_replace(concat_ws(' # ',
  (select (to_jsonb(sr) - 'id')::text from public.standing_routes sr where sr.id = p_route),
  (select string_agg((to_jsonb(s) - 'id')::text, ',' order by s.ord) from public.standing_route_stops s where s.route_id = p_route),
  (select string_agg(x, ',' order by x) from (select (to_jsonb(l) - 'id')::text as x from public.standing_route_lines l
     where l.route_id = p_route) a),
  (select string_agg((to_jsonb(x) - 'id')::text, ',' order by x.lap_no) from public.standing_route_laps x where x.route_id = p_route),
  (select string_agg((to_jsonb(o) - 'id')::text, ',' order by o.seq) from public.orders o where o.fleet_id = p_fleet),
  (select to_jsonb(f)::text from public.fleets f where f.id = p_fleet),
  (select string_agg(to_jsonb(s)::text, ',' order by s.id) from public.ships s where s.fleet_id = p_fleet),
  (select string_agg((to_jsonb(v) - 'id')::text, ',' order by v.departed_at) from public.voyages v where v.fleet_id = p_fleet),
  (select to_jsonb(p)::text from public.players p where p.id = p_house),
  (select string_agg(x, ',' order by x) from (select (to_jsonb(l) - 'id')::text as x from public.ledger l
     where l.player_id = p_house and l.created_at >= now()) a),
  (select string_agg(x, ',' order by x) from (select (to_jsonb(e) - 'id')::text as x from public.events e
     where e.player_id = p_house and e.created_at >= now()) a),
  (select md5(string_agg(to_jsonb(g)::text, ',' order by g.good_id)) from public.port_goods g
     where g.port_id = (select f.port_id from public.fleets f where f.id = p_fleet)),
  (select to_jsonb(t)::text from public.port_treasury t where t.port_id = (select f.port_id from public.fleets f where f.id = p_fleet))
  ), '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', 'U', 'g')
$$;

-- ── 4. A MERCHANT THE PROBE CAN PUT IN THE STUCK SHAPE ─────────────────────────────────────────
-- One docked merchant whose port is one of her own stops, not the lap's first stop (so the stop carries no
-- REPAIR), with hands at the quay, a good the quay bids on, and no failed order of her own (the probe plants one).
create temp table sample_0272 on commit drop as
select r.route_id, r.fleet_id, r.player_id, r.k, f.port_id
  from public.npc_tend_roster() r
  join public.fleets f on f.id = r.fleet_id
 where f.status = 'DOCKED'
   and (select count(*) from public.standing_route_stops s2 where s2.route_id = r.route_id) >= 2
   and exists (select 1 from public.standing_route_stops s
                where s.route_id = r.route_id and s.port_id = f.port_id and s.ord <> 0)
   and exists (select 1 from public.ports p where p.id = f.port_id and coalesce(p.crew_pool, 0) > 0)
   and exists (select 1 from public.goods g
                where coalesce((select q.total from world.quote(f.port_id, g.id, 10, 'sell', null, null) q), 0) > 0)
   and not exists (select 1 from public.orders o where o.fleet_id = r.fleet_id and o.status = 'failed')
 order by r.k
 limit 1;

-- the traders' switch, on, for the step (rolled back with everything else — as 0150's and 0270's probes)
create function pg_temp.traders_on_0272()
returns void
language sql
as $$ update public.world_config set value = 'true'::jsonb
       where key in ('npc_traders_enabled', 'standing_routes_enabled') and value is distinct from 'true'::jsonb $$;

-- the good the probe stocks: the smallest-bulk good this quay bids on (a bid of 10 tuns, so the value is real)
create function pg_temp.probe_good_0272(p_port uuid)
returns table (good_id uuid, code text, bulk numeric)
language sql
stable
as $$
  select g.id, g.code, g.bulk
    from public.goods g
   where coalesce((select q.total from world.quote(p_port, g.id, 10, 'sell', null, null) q), 0) > 0
   order by g.bulk, g.code
   limit 1
$$;

-- THE STUCK SHAPE, put on the probe merchant: docked at the stop's port, p_short hands below complement on every
-- hull, purse p_purse, her hold stocked (p_qty tuns at cost 1,000,000 — so the at-profit SELL is refused), her casks
-- full, her preset gone (so no PROVISION line stands between the sale and the hire), her queue cleared, a failed
-- SAIL refused E_CREW_SHORT at the head, and p_clears NPC_CLEARED events already on this lap.
create function pg_temp.state_0272(p_house uuid, p_fleet uuid, p_route uuid, p_port uuid, p_short int,
                                    p_purse bigint, p_qty numeric, p_clears int)
returns void
language plpgsql
as $$
declare
  v_lap   int;
  v_oid   uuid;
  v_ord   int;
  v_code  text;
  v_next  text;
  v_seq   int;
  v_n     int;
  sh      record;
  v_free  numeric;
  v_wp    numeric := public.wc_num('water_per_crew_day');
  v_fp    numeric := public.wc_num('food_per_crew_day');
begin
  perform pg_temp.traders_on_0272();
  perform cmd.clear_for(p_house, p_fleet, false);
  update public.voyages set status = 'ARRIVED' where fleet_id = p_fleet and status = 'SAILING';
  update public.fleets set status = 'DOCKED', port_id = p_port, lat = null, lon = null,
                           provision_preset_id = null
   where id = p_fleet;
  -- her hulls: below complement by p_short each, empty holds, dry casks
  update public.ships hs
     set crew = greatest(0, c.crew_required - p_short),
         cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb, water_t = 0, food_t = 0
    from public.ship_classes c
   where c.id = hs.class_id and hs.fleet_id = p_fleet;
  if p_qty > 0 then
    select x.code into v_code from pg_temp.probe_good_0272(p_port) x;
    perform public.fleet_load(p_fleet, v_code, p_qty, 1000000);
  end if;
  -- casks to the brim of what the cargo left: the SAIL must pass on stores, so the probe never measures a
  -- crew-short fleet through an E_ENDURANCE it did not intend
  for sh in select s.id, s.crew, public.ship_hold_capacity(s.id) as hold, public.ship_cargo_tuns(s.id) as cargo_t
              from public.ships s where s.fleet_id = p_fleet loop
    v_free := greatest(0, sh.hold - sh.cargo_t);
    update public.ships
       set water_t = round(v_free * v_wp / (v_wp + v_fp), 3),
           food_t  = round(v_free * v_fp / (v_wp + v_fp), 3)
     where id = sh.id;
  end loop;
  -- her purse, through the ledger (the purse reconciles with it — 0150's purse_0150)
  perform public.credit(p_house, 'PROBE_0272',
                        (p_purse - (select ducats from public.players where id = p_house))::bigint);
  -- her route: at the stop's port, cursor on it, no pause, no hold, no reserve, a lap of her own
  select min(s.ord) into v_ord from public.standing_route_stops s
   where s.route_id = p_route and s.port_id = p_port and s.ord <> 0;
  select count(*) into v_n from public.standing_route_stops s where s.route_id = p_route;
  select count(*) into v_lap from public.standing_route_laps x where x.route_id = p_route;
  v_lap := 900272 + v_lap;
  insert into public.standing_route_laps (route_id, lap_no, started_at)
  values (p_route, v_lap, now() - interval '7 hours') returning id into v_oid;
  update public.standing_routes
     set fleet_id = p_fleet, lap_no = v_lap, stop_cursor = v_ord, paused_reason = null, hold_until = null,
         reserve = 0, lap_id = v_oid, updated_at = now() - interval '2 minutes'
   where id = p_route;
  -- the failed order at the head: a SAIL refused E_CREW_SHORT, the shape prod shows
  select p.code into v_next
    from public.standing_route_stops s join public.ports p on p.id = s.port_id
   where s.route_id = p_route and s.ord = (v_ord + 1) % v_n;
  select coalesce(max(o.seq), 0) + 1 into v_seq from public.orders o where o.fleet_id = p_fleet;
  insert into public.orders (fleet_id, player_id, seq, raw_text, verb, status, error_code, error_message)
  values (p_fleet, p_house, v_seq, format('SAIL TO %s', v_next), 'SAIL', 'failed', 'E_CREW_SHORT', 'probe_0272');
  -- her lap's clears, already counted: p_clears of them
  insert into public.events (player_id, kind, payload)
  select p_house, 'NPC_CLEARED', jsonb_build_object('route_id', p_route, 'lap_no', v_lap, 'n', i)
    from generate_series(1, greatest(p_clears, 0)) i;
end $$;

create function pg_temp.crew_case_0272(p_mode text, p_house uuid, p_fleet uuid, p_route uuid, p_port uuid,
                                       p_short int, p_purse bigint, p_qty numeric, p_clears int)
returns jsonb
language plpgsql
as $$
declare
  v_r  jsonb;
  v_sq text;
begin
  begin
    perform pg_temp.state_0272(p_house, p_fleet, p_route, p_port, p_short, p_purse, p_qty, p_clears);
    if p_mode = 'old' then
      select old_def into v_sq from old_bodies_0272 where fn = 'leg';
      execute v_sq;
      select old_def into v_sq from old_bodies_0272 where fn = 'due';
      execute v_sq;
    else
      select new_def into v_sq from new_bodies_0272 where fn = 'leg';
      execute v_sq;
      select new_def into v_sq from new_bodies_0272 where fn = 'due';
      execute v_sq;
    end if;
    v_r := public.npc_tend_route(now(), p_fleet, p_route, 1);
    raise exception using errcode = 'ZY272', message = jsonb_build_object(
      'receipt', v_r,
      'mode', p_mode,
      'digest', pg_temp.digest_0272(p_fleet, p_route, p_house),
      'shortfall', public.fleet_crew_shortfall(p_fleet),
      'purse', (select p.ducats from public.players p where p.id = p_house),
      'fleet', (select f.status from public.fleets f where f.id = p_fleet),
      'ledger_ok', ((select coalesce(sum(l.ducats_delta), 0) from public.ledger l where l.player_id = p_house)
                    = (select p.ducats from public.players p where p.id = p_house)),
      'orders', coalesce((select jsonb_agg(jsonb_build_object('verb', o.verb, 'status', o.status,
                                                              'code', o.error_code, 'text', o.raw_text) order by o.seq)
                            from public.orders o where o.fleet_id = p_fleet), '[]'::jsonb))::text;
  exception when sqlstate 'ZY272' then
    return sqlerrm::jsonb;
  end;
end $$;

-- ── 5. THE SELF-ASSERT ──────────────────────────────────────────────────────────────────────────
do $$
declare
  v_b    record;
  v_d    record;
  v_h    record;
  v_def  text;
  v_pp   record;
  o      jsonb;
  n      jsonb;
  c      jsonb;
  m      record;
  g      record;
  v_short int;
  v_cost  bigint;
  v_qty   numeric;
  v_bid   numeric;
  v_one   numeric;
  v_hold  numeric;
  v_bulk  numeric;
  v_case  text;
  v_rule  int := 0;
  v_step  int := 0;
  v_lap   int;
  v_route uuid;
  v_house uuid;
begin
  select * into v_b from before_0272;

  -- (a) THE HUNKS reverse to the live pre-images; ACL / volatility / definer / config unmoved; nothing else in
  -- the four schemas moved; exactly one function was minted; no new quay taker; the client entry points still
  -- number what they numbered; no client role may run the new rule.
  for v_d in select * from defs_before_0272 loop
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    for v_h in select * from hunks_0272 where fn = v_d.fn order by n desc loop
      if pg_temp.occurs_0272(v_def, v_h.new) <> 1 then
        raise exception '0272 self-assert FAIL: hunk % of % is not in the new body exactly once', v_h.n, v_d.fn;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0272 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg
      into v_pp from pg_proc p where p.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0272 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid not in (to_regprocedure('public.npc_leg_lines(uuid,uuid,uuid,numeric,int,numeric)'),
                           to_regprocedure('public.npc_clear_due(uuid,uuid,int,text,text)'),
                           to_regprocedure('public.npc_crew_blocked(uuid,uuid)'))) <> v_b.fns then
    raise exception '0272 self-assert FAIL: the four schemas gained or lost a function beyond public.npc_crew_blocked';
  end if;
  if (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid not in (to_regprocedure('public.npc_leg_lines(uuid,uuid,uuid,numeric,int,numeric)'),
                           to_regprocedure('public.npc_clear_due(uuid,uuid,int,text,text)'),
                           to_regprocedure('public.npc_crew_blocked(uuid,uuid)'))) <> v_b.others_md5 then
    raise exception '0272 self-assert FAIL: a function this file does not re-cut moved (the two bodies'' own authorities included)';
  end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'npc_crew_blocked') <> 1 then
    raise exception '0272 self-assert FAIL: the rule is not in one place';
  end if;
  if (select string_agg(p.oid::regprocedure::text, ',' order by p.oid::regprocedure::text)
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname not in ('pg_catalog', 'information_schema') and n.nspname not like 'pg_temp%'
         and p.prokind in ('f', 'p') and pg_get_functiondef(p.oid) like '%hold_the_quay()%') <> v_b.quay_takers then
    raise exception '0272 self-assert FAIL: the set of functions that take the quay changed';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> v_b.entry_points then
    raise exception '0272 self-assert FAIL: the client entry points changed';
  end if;
  if has_function_privilege('authenticated', 'public.npc_crew_blocked(uuid,uuid)', 'execute')
     or has_function_privilege('anon', 'public.npc_crew_blocked(uuid,uuid)', 'execute') then
    raise exception '0272 self-assert FAIL: a client role may execute the new rule';
  end if;

  -- (b) THE FIX'S OWN SHAPE, on the new bodies: the plan asks the one rule and the one hire price once each, and
  -- the cut-loss stands after 0150's for room and before the leg's answer.
  v_def := replace(pg_get_functiondef('public.npc_clear_due(uuid,uuid,int,text,text)'::regprocedure), E'\r', '');
  if pg_temp.occurs_0272(v_def, '''E_CREW_SHORT''') <> 1 then
    raise exception '0272 self-assert FAIL: E_CREW_SHORT is not in the plan rule exactly once';
  end if;
  v_def := replace(pg_get_functiondef('public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)'::regprocedure), E'\r', '');
  if pg_temp.occurs_0272(v_def, 'public.npc_crew_blocked(sr.fleet_id') <> 1
     or pg_temp.occurs_0272(v_def, 'public.crew_hire_cost(sr.fleet_id') <> 1 then
    raise exception '0272 self-assert FAIL: the cut-loss does not ask the one rule and the one hire price once each';
  end if;
  if position('public.npc_casks_blocked(sr.fleet_id' in v_def) = 0
     or position('public.npc_casks_blocked(sr.fleet_id' in v_def) > position('public.npc_crew_blocked(sr.fleet_id' in v_def)
     or position('public.npc_crew_blocked(sr.fleet_id' in v_def) > position('return jsonb_build_object(''lines'', v_lines' in v_def) then
    raise exception '0272 self-assert FAIL: the crew cut-loss does not stand after the room cut-loss and before the answer';
  end if;

  -- (c) PROBE A, the rule itself, on a real route: a SAIL refused E_CREW_SHORT plans on the FIRST clear, as
  -- E_ENDURANCE does; at the third clear everything plans; an ordinary refusal at n < 3 does not. The old rule
  -- (0270's) is recomputed here; the two must agree on every case but the one this file adds. Rolled back below.
  begin
    select x.player_id, x.route_id into v_house, v_route from pg_temp.sample_0272 x;
    if v_route is null then
      select sr.player_id, sr.id into v_house, v_route from public.standing_routes sr
       where sr.fleet_id is not null order by sr.id limit 1;
    end if;
    if v_route is null then
      raise exception '0272 self-assert FAIL: no route to plant a clear on — the rule probe proves nothing';
    end if;
    select coalesce(max(l.lap_no), 0) into v_lap from public.standing_route_laps l where l.route_id = v_route;
    for m in select * from (values ('SAIL', 'E_CREW_SHORT', 0, 1), ('SAIL', 'E_ENDURANCE', 0, 2),
                                   ('SAIL', 'E_NO_CARGO', 0, 3), ('SELL', 'E_INSUFFICIENT_FUNDS', 0, 4),
                                   ('SAIL', 'E_CREW_SHORT', 2, 5), ('SAIL', 'E_NO_CARGO', 2, 6),
                                   ('SAIL', 'E_ENDURANCE', 2, 7)) t(verb, code, clears, k) loop
      insert into public.events (player_id, kind, payload)
      select v_house, 'NPC_CLEARED', jsonb_build_object('route_id', v_route, 'lap_no', v_lap + m.k, 'n', i)
        from generate_series(1, m.clears) i;
      c := public.npc_clear_due(v_house, v_route, v_lap + m.k, m.verb, m.code);
      v_rule := v_rule + 1;
      if (c->>'n')::int <> m.clears + 1 then
        raise exception '0272 self-assert FAIL: the rule counted % clears where the probe planted %', c->>'n', m.clears;
      end if;
      if (c->>'plan')::boolean <> (m.clears + 1 >= 3 or m.code = 'E_ENDURANCE' or m.code = 'E_CREW_SHORT') then
        raise exception '0272 self-assert FAIL: the rule says % for % / % at clear %', c->>'plan', m.verb, m.code, m.clears + 1;
      end if;
      -- the old rule, recomputed: it may differ only on the case this file adds
      if (c->>'plan')::boolean <> (m.clears + 1 >= 3 or m.code = 'E_ENDURANCE')
         and not (m.verb = 'SAIL' and m.code = 'E_CREW_SHORT' and m.clears + 1 < 3) then
        raise exception '0272 self-assert FAIL: the rule moved a case it must not move: % / % at clear %', m.verb, m.code, m.clears + 1;
      end if;
    end loop;
    raise exception using errcode = 'ZY272', message = 'rule ok';   -- roll the planted clears back
  exception when sqlstate 'ZY272' then
    null;
  end;

  -- (d) PROBE B, THE CUT-LOSS: the same merchant, the same step, OLD bodies against NEW. Two clears are planted so
  -- this is the third clear of her lap: 0270's rule already re-plans on BOTH sides, and the only difference measured
  -- is the cut-loss.
  if (select count(*) from pg_temp.sample_0272) < 1 then
    raise exception '0272 self-assert FAIL: no merchant the step can reach — the cut-loss probe proves nothing';
  end if;
  select * into g from pg_temp.sample_0272;
  perform pg_temp.traders_on_0272();
  select x.* into m from pg_temp.probe_good_0272(g.port_id) x;
  if m.good_id is null then
    raise exception '0272 self-assert FAIL: the probe port (%) bids on no good', g.port_id;
  end if;
  -- the hire her planted shortfall costs, and a hold worth several times it at this quay's bid
  select coalesce(sum(least(c.crew_required, 2)), 0) into v_short
    from public.ships s join public.ship_classes c on c.id = s.class_id where s.fleet_id = g.fleet_id;
  v_cost  := (public.crew_hire_cost(g.fleet_id, v_short)->>'cost')::bigint;
  v_bid   := coalesce((select q.total from world.quote(g.port_id, m.good_id, 10, 'sell', null, null) q), 0);
  v_one   := coalesce((select q.total from world.quote(g.port_id, m.good_id, 1, 'sell', null, null) q), 0);
  v_bulk  := greatest(m.bulk, 0.001);
  select min(public.ship_hold_capacity(s.id)) into v_hold from public.ships s where s.fleet_id = g.fleet_id;
  v_qty   := least(ceil(4 * v_cost * 10 / greatest(v_bid, 0.01)), floor(v_hold * 0.5 / v_bulk));
  if v_qty < 1 then
    raise exception '0272 self-assert FAIL: her hold (%) cannot carry enough % to cover a % d. hire', v_hold, m.code, v_cost;
  end if;
  if v_one >= v_cost then
    raise exception '0272 self-assert FAIL: one tun of % is worth % d. at the quay — the "cannot cover" control cannot be built against a % d. hire', m.code, v_one, v_cost;
  end if;

  -- (d0) the rule's own truth table on the planted shape (every case rolled back with its subtransaction)
  for v_case in select unnest(array['pays', 'covers', 'short', 'full']) loop
    begin
      perform pg_temp.state_0272(g.player_id, g.fleet_id, g.route_id, g.port_id,
                                 case when v_case = 'full' then 0 else 2 end,
                                 case when v_case = 'covers' then 10000 else 0 end,
                                 case when v_case = 'short' then 1 else v_qty end, 0);
      if public.npc_crew_blocked(g.fleet_id, g.port_id) is distinct from (v_case = 'pays') then
        raise exception '0272 self-assert FAIL: the rule says % on the "%" shape (shortfall %, purse %, hold) where it must say %',
          public.npc_crew_blocked(g.fleet_id, g.port_id), v_case, public.fleet_crew_shortfall(g.fleet_id),
          (select p.ducats from public.players p where p.id = g.player_id), (v_case = 'pays');
      end if;
      -- and only at HER quay: a port she does not lie at is never blocked
      if public.npc_crew_blocked(g.fleet_id,
           (select p2.id from public.ports p2 where p2.id <> g.port_id order by p2.code limit 1)) then
        raise exception '0272 self-assert FAIL: she is read as blocked at a quay she does not lie at';
      end if;
      raise exception using errcode = 'ZY272', message = 'shape ok';
    exception when sqlstate 'ZY272' then
      null;
    end;
  end loop;

  -- (d1) THE POSITIVE CASE: purse 0, a hold worth more than the hire, a failed SAIL refused E_CREW_SHORT.
  o := pg_temp.crew_case_0272('old', g.player_id, g.fleet_id, g.route_id, g.port_id, 2, 0, v_qty, 2);
  n := pg_temp.crew_case_0272('new', g.player_id, g.fleet_id, g.route_id, g.port_id, 2, 0, v_qty, 2);
  c := pg_temp.crew_case_0272('old', g.player_id, g.fleet_id, g.route_id, g.port_id, 2, 0, v_qty, 2);
  if o->'receipt'->>'cleared' is distinct from '1' or o->'receipt'->>'failed' is distinct from '0' then
    raise exception '0272 self-assert FAIL: the old step answered % — it did not reach the clear', o->'receipt';
  end if;
  if o->>'digest' is distinct from c->>'digest' then
    raise exception '0272 self-assert FAIL: the control moved (old against old): % / %', left(o->>'digest', 600), left(c->>'digest', 600);
  end if;
  -- OLD: the bug itself — the HIRE refused for want of money, the SAIL behind it refused for want of crew
  if not exists (select 1 from jsonb_array_elements(o->'orders') e
                  where e->>'verb' = 'HIRE' and e->>'status' = 'skipped' and e->>'code' = 'E_INSUFFICIENT_FUNDS')
     or not exists (select 1 from jsonb_array_elements(o->'orders') e
                     where e->>'verb' = 'SAIL' and e->>'status' = 'failed' and e->>'code' = 'E_CREW_SHORT') then
    raise exception '0272 self-assert FAIL: the old step did not reproduce the loop (HIRE skipped, SAIL refused): %', o->'orders';
  end if;
  if (o->>'fleet') <> 'DOCKED' or (o->>'shortfall')::int <= 0 then
    raise exception '0272 self-assert FAIL: the old step left her fleet %, shortfall %', o->>'fleet', o->>'shortfall';
  end if;
  -- NEW: a SELL at the bid, the HIRE paid, the SAIL accepted, crew restored, the ledger reconciled
  if not exists (select 1 from jsonb_array_elements(n->'orders') e
                  where e->>'verb' = 'SELL' and e->>'status' = 'done' and e->>'text' not like '%AT >=%') then
    raise exception '0272 self-assert FAIL: the new step wrote no SELL at the quay''s bid: %', n->'orders';
  end if;
  if not exists (select 1 from jsonb_array_elements(n->'orders') e
                  where e->>'verb' = 'HIRE' and e->>'status' = 'done')
     or not exists (select 1 from jsonb_array_elements(n->'orders') e
                     where e->>'verb' = 'SAIL' and e->>'status' = 'done') then
    raise exception '0272 self-assert FAIL: the sale did not pay the hire and the sail: %', n->'orders';
  end if;
  if (n->>'fleet') <> 'SAILING' or (n->>'shortfall')::int <> 0 then
    raise exception '0272 self-assert FAIL: the new step left her fleet % with a shortfall of %', n->>'fleet', n->>'shortfall';
  end if;
  if not (n->>'ledger_ok')::boolean then
    raise exception '0272 self-assert FAIL: her purse no longer reconciles with her ledger after the sale and the hire';
  end if;
  if (o->>'digest') is not distinct from (n->>'digest') then
    raise exception '0272 self-assert FAIL: old and new left the same rows where the cut-loss must act';
  end if;
  v_step := v_step + 1;

  -- (d2) THE CONTROLS: where the rule must not act, old and new leave the same rows.
  -- covers: her purse already pays the hire — nothing is sold, and she sails.
  o := pg_temp.crew_case_0272('old', g.player_id, g.fleet_id, g.route_id, g.port_id, 2, 10000, v_qty, 2);
  n := pg_temp.crew_case_0272('new', g.player_id, g.fleet_id, g.route_id, g.port_id, 2, 10000, v_qty, 2);
  if (o->>'digest') is distinct from (n->>'digest') then
    raise exception '0272 self-assert FAIL: the rule acted where her purse covers the hire: % / %', left(o->>'digest', 400), left(n->>'digest', 400);
  end if;
  if exists (select 1 from jsonb_array_elements(n->'orders') e
              where e->>'verb' = 'SELL' and e->>'status' = 'done' and e->>'text' not like '%AT >=%') then
    raise exception '0272 self-assert FAIL: a merchant whose purse covers the hire still sold at the bid: %', n->'orders';
  end if;
  if not exists (select 1 from jsonb_array_elements(n->'orders') e where e->>'verb' = 'HIRE' and e->>'status' = 'done')
     or (n->>'shortfall')::int <> 0 then
    raise exception '0272 self-assert FAIL: her own money did not pay the hire: %', n->'orders';
  end if;
  v_step := v_step + 1;
  -- short: her hold cannot cover the hire — no sale, and the old outcome stands
  o := pg_temp.crew_case_0272('old', g.player_id, g.fleet_id, g.route_id, g.port_id, 2, 0, 1, 2);
  n := pg_temp.crew_case_0272('new', g.player_id, g.fleet_id, g.route_id, g.port_id, 2, 0, 1, 2);
  if (o->>'digest') is distinct from (n->>'digest') then
    raise exception '0272 self-assert FAIL: the rule acted on a hold that cannot cover the hire: % / %', left(o->>'digest', 400), left(n->>'digest', 400);
  end if;
  if not exists (select 1 from jsonb_array_elements(n->'orders') e
                  where e->>'verb' = 'HIRE' and e->>'status' = 'skipped')
     or not exists (select 1 from jsonb_array_elements(n->'orders') e
                     where e->>'verb' = 'SAIL' and e->>'status' = 'failed' and e->>'code' = 'E_CREW_SHORT') then
    raise exception '0272 self-assert FAIL: a hold that cannot cover the hire left a different outcome than the old one: %', n->'orders';
  end if;
  v_step := v_step + 1;
  -- full: no shortfall — no HIRE line, no sale, and she sails on the old and the new body alike
  o := pg_temp.crew_case_0272('old', g.player_id, g.fleet_id, g.route_id, g.port_id, 0, 0, v_qty, 2);
  n := pg_temp.crew_case_0272('new', g.player_id, g.fleet_id, g.route_id, g.port_id, 0, 0, v_qty, 2);
  if (o->>'digest') is distinct from (n->>'digest') then
    raise exception '0272 self-assert FAIL: the rule acted on a fleet at full complement: % / %', left(o->>'digest', 400), left(n->>'digest', 400);
  end if;
  if (n->>'fleet') <> 'SAILING' then
    raise exception '0272 self-assert FAIL: a fleet at full complement did not sail (fleet %)', n->>'fleet';
  end if;
  if exists (select 1 from jsonb_array_elements(n->'orders') e where e->>'verb' = 'HIRE') then
    raise exception '0272 self-assert FAIL: a fleet at full complement was asked to hire: %', n->'orders';
  end if;
  v_step := v_step + 1;

  -- (e) THE PROBE LEFT NOTHING: every row it wrote went with its transaction
  if exists (select 1 from public.orders where error_message = 'probe_0272')
     or exists (select 1 from public.ledger where kind = 'PROBE_0272') then
    raise exception '0272 self-assert FAIL: a probe row survived its transaction';
  end if;

  raise notice '0272 self-assert ok: A CREW SHORTAGE IS PAID FROM THE HOLD. npc_leg_lines and npc_clear_due reverse to their pre-images hunk by hunk, ACLs unmoved, every other function in the four schemas unmoved (md5), public.npc_crew_blocked the one function minted, the quay takers and the client entry points unmoved. The rule on % planted clears: a SAIL refused E_CREW_SHORT plans on the FIRST clear, E_ENDURANCE too, the third clear too, an ordinary refusal at n < 3 not. The cut-loss, her step OLD vs NEW on merchant %: OLD leaves HIRE skipped and SAIL refused E_CREW_SHORT with her docked; NEW sells at the bid, pays the HIRE, sails, crew restored and the ledger reconciled; % controls (purse covers, hold short, at full complement) left identical rows. Rolled back.',
    v_rule, g.route_id, v_step - 1;
end $$;
