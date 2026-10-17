-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0167 — A MERCHANT SAILS HER OWN COUNTRY'S SHIPS  (S18: merchants of every flag — the line hull a
--        merchant sails in place of a live class, founded so, converted once, her hull skills fixed once)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY NOW ─────────────────────────────────────────────────────────────────────────────────────
-- docs/SHIPS_AND_SKILLS.md §8 row S18 ("npc_found picks a line hull by home port nation; a one-time
-- conversion of existing merchant hulls to their line's hull nearest in hold (±10 %) and speed; merchant
-- hull skills fixed once via raise_skill; G1 patterns for new classes | merchant fleet hold within ±10 %
-- and speed within ±5 % of pre-image per fleet; no player row touched; no merchant queue rows; zero-net lap
-- share and arrivals duration measured before/after"), §5.1 ("S18 seeds their hull skills the same way,
-- once"), §6.9; docs/SKILLS_AND_CAPTAINS.md §9 (npc_found seats captains through seat_captain_for: it
-- already does — public.post_officer_to has called the seat core since 0157 — so nothing moves there).
-- Every merchant on the sea sails a barca, a caravela latina or a nau: the Portuguese line's three.
--
-- ── WHAT SAYS THE OPPOSITE TODAY, NAMED ─────────────────────────────────────────────────────────
--   * public.npc_found commissions the roster's class word for word (new_house's first ship and both
--     commission_ship calls); nothing reads the house's country.
--   * public.npc_fit_loadout finds patterns by the hull's own class only, and only the live three have any.
--   * No merchant holds a hull skill.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) THE ONE RULE — scripts/build-ships.mjs `merchant` (MERCHANT bounds): for each live class and each
--     other line, the line's T1 hull with cargo space within ± 10 % and speed within ± 5 %, needing NO MORE
--     crew and holding AT LEAST as many (so every merchant's crew, and with it her wages and her endurance,
--     is unchanged), with every rack and Deck at least the live class's (every pattern of her gear fits);
--     the nearest. Loaded as public.npc_line_hulls (`--sql-merchant`, 5 rows; held by the world guard).
--     Read by ONE sentence, public.npc_hull_for(class, port): the line hull of the country that holds the
--     port, or the class itself where that country builds none.
-- (2) FOUNDED SO: public.npc_found commissions npc_hull_for(class, her house's home) at all three sites,
--     and fixes her hull skills once (public.npc_fix_hull_skills) after her hulls' level is fixed (so 0127's
--     "1 + skills / 3" level is the four live skills', as before).
-- (3) HER GEAR: public.npc_fit_loadout reads the patterns of the live class a line hull stands in for
--     (npc_line_hulls) — one authored set per live class (data/npc-loadouts.json), never a copy.
-- (4) CONVERTED ONCE: every merchant hull whose house's home is held by a country with a line hull for
--     her class is re-classed (`ships.class_id`; her hull points kept in proportion), unless her cargo
--     would not fit the new hold (she is left as she is, and counted). Each change is written to
--     public.npc_hull_conversions (ship, from, to, hull points before/after) — the pre-image a rollback
--     restores. Her crew, her gear, her cabins, her voyage and her orders are untouched.
-- (5) HULL SKILLS, FIXED ONCE: public.npc_fix_hull_skills(player) raises, through public.raise_skill at
--     her home harbour (the academy's core; the city is paid), every hull skill level the hulls she sails
--     ask for (skill_requirements), each level endowed first exactly as npc_found endows its founding
--     tuition (credit FOUNDING), so her purse ends where it began. No queue row, ever.
--
-- ── WHAT IT DELIBERATELY DOES NOT DO ────────────────────────────────────────────────────────────
-- No player row moves (hashed). No crew, cargo, store, route, lap, voyage, seat or fitting row moves. No
-- knob, no entry point, no client write, no cron, no ALTER, no index. Dark: hull skills count for nothing
-- while skills_bite is off. Said plainly, the felt change: about sixty merchant hulls (English and French
-- houses) change their name of class — barca → Crayer / Barque, caravela latina → Caravelle normande, nau
-- → Levant Merchantman / Navire marchand — at the speed, cargo space and crew they had. Under §8's bounds no
-- other country has such a hull (a Dutch fluit is +25 % cargo space on a nau, a junk +15 %), so the sea does
-- NOT yet show fluits in the Baltic or junks off China — written in the PR for the owner.
--
-- ── LOCKS ───────────────────────────────────────────────────────────────────────────────────────
-- Heavy reads first. Row locks on the converted merchant ships only (an UPDATE of class_id and durability),
-- and on their houses' players rows (the endowment and tuition), held to commit; ROW EXCLUSIVE on two new
-- tables, player_skills, ledger, events, city purses. CREATE OR REPLACE FUNCTION locks no table. Probe writes
-- are rolled back; a probe that meets a lock is retried 5 × 0.2 s, then LOCK CONTENTION. No top-level LOCK /
-- SET LOCAL / BEGIN / SET ROLE.
--
-- SUPERSEDES, by hunks sliced from the LIVE bodies (LF-normalised, read from production with
-- pg_get_functiondef), each asserted to occur exactly once and to reverse to its pre-image, ACL /
-- volatility / definer / config unchanged: public.npc_found (0097, as live), public.npc_fit_loadout (0132).
--
-- ROLLBACK (forward migration): set every ship in npc_hull_conversions back to `from_class` and its hull
-- points to `durability_before`; reverse the two bodies' hunks (old text in hunks_0167); leave the hull
-- skills (they were paid for) or delete those rows; drop npc_hull_for, npc_fix_hull_skills, npc_line_hulls.
-- VERSION: 0167 (S17 is 0165 on prod; K9 takes 0166). Applies on 0165 (S17) and deploys after K9 (0166), which touches neither body.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  perform set_config('random_page_cost', '1.1', true);   -- prod's planner page cost (0149's header)
end $guard$;

-- ── 0. HELPERS (pg_temp, gone at commit) ───────────────────────────────────────────────────────
create or replace function pg_temp.occurs_0167(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

create temp table reads_0167 (phase text, what text, hulls bigint, ms numeric) on commit drop;
create or replace function pg_temp.time_reads_0167(p_phase text)
returns void
language plpgsql
as $$
declare
  v_t0  timestamptz;
  v_ids uuid[];
begin
  select array_agg(s.id order by s.id) into v_ids from public.ships s join public.players p on p.id = s.player_id where p.is_npc;
  v_t0 := clock_timestamp();
  perform voyage.ship_speed(x), public.ship_hold_capacity(x) from unnest(v_ids) x;
  insert into reads_0167 values (p_phase, 'speed+hold', coalesce(cardinality(v_ids), 0), round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
  v_t0 := clock_timestamp();
  perform world.ship_view(x) from unnest(v_ids) x;
  insert into reads_0167 values (p_phase, 'ship_view', coalesce(cardinality(v_ids), 0), round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
end $$;

-- ── 1. THE PRE-IMAGES (every heavy read happens here, before any write) ─────────────────────────
create temp table defs_before_0167 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('public.npc_found(jsonb)'), ('public.npc_fit_loadout(uuid)')) f(fn);

-- every merchant hull as she is: class, hull points, crew, cargo, what she makes and carries
create temp table ships_before_0167 on commit drop as
select s.id, s.fleet_id, s.player_id, c.code as class, s.durability, s.crew,
       public.ship_cargo_tuns(s.id) as cargo_t, voyage.ship_speed(s.id) as speed, public.ship_hold_capacity(s.id) as hold,
       (select count(*) from public.fitted_units u where u.ship_id = s.id) as units,
       (select md5(coalesce(string_agg(to_jsonb(u)::text, '|' order by u.id), '')) from public.fitted_units u where u.ship_id = s.id) as units_hash,
       (select md5(coalesce(string_agg(to_jsonb(cs)::text, '|' order by cs.player_officer_id), '')) from public.captain_seats cs where cs.ship_id = s.id) as seats_hash
  from public.ships s join public.players p on p.id = s.player_id and p.is_npc
  join public.ship_classes c on c.id = s.class_id;
-- every merchant fleet as it is: speed, cargo space, crew (her wages), status, what her captains give
create temp table fleets_before_0167 on commit drop as
select f.id, f.status, voyage.fleet_speed(f.id) as speed,
       (select sum(b.hold) from ships_before_0167 b where b.fleet_id = f.id) as hold,
       (select sum(b.crew) from ships_before_0167 b where b.fleet_id = f.id) as crew,
       (select jsonb_object_agg(ce.code, public.crew_pct(f.id, null, ce.code)) from public.crew_effects ce
         where ce.scope = 'fleet' and ce.code <> 'category_spread') as crew_pct
  from public.fleets f join public.players p on p.id = f.player_id and p.is_npc;

create temp table before_0167 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select md5(string_agg(to_jsonb(s)::text, '|' order by s.id)) from public.ships s join public.players p on p.id = s.player_id and not p.is_npc) as player_ships_hash,
       (select md5(string_agg(to_jsonb(p)::text, '|' order by p.id)) from public.players p where not p.is_npc) as players_hash,
       (select md5(coalesce(string_agg(to_jsonb(ps)::text, '|' order by ps.player_id, ps.skill_id), '')) from public.player_skills ps join public.players p on p.id = ps.player_id and not p.is_npc) as player_skills_hash,
       (select count(*) from public.skill_queue q join public.players p on p.id = q.player_id and p.is_npc) as npc_queue,
       (select coalesce(sum(p.ducats), 0) from public.players p where p.is_npc) as npc_purses;

-- THE LAP PRE-IMAGE (the 0120 method, printed): the last ten closed laps of every merchant fleet — the
-- share that closed at zero net or below, and the mean lap in real hours. A conversion changes nothing that
-- has sailed; the after-figure is the same query on prod a day later (written in the PR).
create temp table laps_before_0167 on commit drop as
select count(*) as laps,
       round(100.0 * count(*) filter (where l.net <= 0) / greatest(count(*), 1), 1) as zero_net_pct,
       round(avg(extract(epoch from l.closed_at - l.started_at) / 3600.0)::numeric, 2) as mean_hours
  from (select l.*, row_number() over (partition by l.route_id order by l.closed_at desc) as rn
          from public.standing_route_laps l join public.npc_fleets nf on nf.route_id = l.route_id
         where l.closed_at is not null) l
 where l.rn <= 10;

select pg_temp.time_reads_0167('before');

-- ── 2. THE ONE RULE (scripts/build-ships.mjs --sql-merchant, verbatim) ──────────────────────────
create table if not exists public.npc_line_hulls (
  live_class text not null references public.ship_classes(code),
  line_code  text not null references public.ship_lines(code),
  class_code text not null unique references public.ship_classes(code),
  primary key (live_class, line_code)
);
comment on table public.npc_line_hulls is
  '0167 (S18): the hull a merchant of a line sails in place of a live class (scripts/build-ships.mjs `merchant`, '
  'held by the world guard). Read by public.npc_hull_for and public.npc_fit_loadout. Server-only.';
alter table public.npc_line_hulls enable row level security;
revoke all on table public.npc_line_hulls from public, anon, authenticated;
insert into public.npc_line_hulls (live_class, line_code, class_code) values
  ('barca', 'ENG', 'crayer'),
  ('barca', 'FRA', 'barque'),
  ('carlat', 'FRA', 'carnorm'),
  ('nau', 'ENG', 'levanter'),
  ('nau', 'FRA', 'navire')
on conflict (live_class, line_code) do nothing;

create table if not exists public.npc_hull_conversions (
  ship_id           uuid primary key references public.ships(id) on delete cascade,
  from_class        text not null references public.ship_classes(code),
  to_class          text not null references public.ship_classes(code),
  durability_before numeric(8,2) not null,
  durability_after  numeric(8,2) not null,
  converted_at      timestamptz not null default now()
);
comment on table public.npc_hull_conversions is
  '0167 (S18): every merchant hull re-classed once to her country''s line hull — the pre-image a rollback restores. Server-only.';
alter table public.npc_hull_conversions enable row level security;
revoke all on table public.npc_hull_conversions from public, anon, authenticated;

create or replace function public.npc_hull_for(p_class text, p_port uuid)
returns text
language sql
stable
set search_path = public, pg_temp
as $nh$
  -- 0167 (S18): THE HULL A MERCHANT SAILS for a roster class, at a house whose home is p_port: the line
  -- hull of the country that holds the port today (public.port_nation, 0143), or the class itself where
  -- that country builds no such hull (public.npc_line_hulls, the one rule's rows).
  select coalesce((select h.class_code
                     from public.npc_line_hulls h
                     join public.ship_lines sl on sl.code = h.line_code
                     join public.nations n on n.id = public.port_nation(p_port)
                    where h.live_class = p_class and n.code = any(sl.builder_nations)
                    order by sl.code limit 1), p_class)
$nh$;
comment on function public.npc_hull_for(text, uuid) is
  '0167 (S18): the line hull a merchant sails in place of a roster class at a house whose home is that port. Server-only.';
revoke all on function public.npc_hull_for(text, uuid) from public, anon, authenticated;

create or replace function public.npc_fix_hull_skills(p_player uuid)
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $fh$
declare
  v_home  text;
  r       record;
  v_lvl   int;
  v_res   jsonb;
  v_cost  bigint;
  v_n     bigint := 0;
begin
  -- 0167 (S18): A MERCHANT'S HULL SKILLS, FIXED ONCE — every level the hulls she sails ask for
  -- (skill_requirements, kind 'hull'), raised through the academy's core at her home harbour, each level
  -- endowed first as npc_found endows its founding tuition, so her purse ends where it began. Levels she
  -- holds already are not raised again (run twice, it raises nothing). Answers the ducats endowed (and
  -- paid). Merchants only.
  if not exists (select 1 from public.players p where p.id = p_player and p.is_npc) then
    raise exception 'E_NOT_A_MERCHANT: npc_fix_hull_skills fixes a merchant company''s hull skills, and % is not one', p_player
      using errcode = 'P0001';
  end if;
  select p.code into v_home from public.npc_houses h join public.ports p on p.id = h.home_port_id where h.player_id = p_player;
  for r in
    select sr.skill_code, max(sr.level) as need,
           coalesce((select ps.level from public.player_skills ps join public.skills sk on sk.id = ps.skill_id
                      where ps.player_id = p_player and sk.code = sr.skill_code), 0) as have
      from public.ships s
      join public.ship_classes c on c.id = s.class_id
      join public.skill_requirements sr on sr.subject_kind = 'hull' and sr.subject_code = c.code
     where s.player_id = p_player
     group by sr.skill_code
     order by sr.skill_code
  loop
    for v_lvl in r.have + 1 .. r.need loop
      v_cost := public.wc_int('skill_study_base_cost') * v_lvl;   -- raise_skill's own price of level v_lvl
      perform public.credit(p_player, 'FOUNDING', v_cost);
      v_res := public.raise_skill(p_player, r.skill_code, v_home);
      if not coalesce((v_res->>'ok')::boolean, false) or (v_res->>'paid')::bigint <> v_cost then
        raise exception 'npc_fix_hull_skills: % could not study % for %: %', p_player, r.skill_code, v_cost, v_res;
      end if;
      v_n := v_n + v_cost;
    end loop;
  end loop;
  return v_n;
end $fh$;
comment on function public.npc_fix_hull_skills(uuid) is
  '0167 (S18): a merchant''s hull skills, fixed once from the hulls she sails, paid through raise_skill and endowed; answers the ducats. Server-only.';
revoke all on function public.npc_fix_hull_skills(uuid) from public, anon, authenticated;

-- ── 3. THE HUNKS (old → new), sliced from the live bodies ──────────────────────────────────────
create temp table hunks_0167 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0167 values
('public.npc_found(jsonb)', 1,
$h$  v_player := public.new_house(null, v_name, p_spec->>'nation', v_home, v_fl->>'name',
                               v_fl->'ships'->0->>'class', v_fl->'ships'->0->>'name',
$h$,
$h$  -- 0167 (S18): every hull she is founded with is her country's line hull for the roster's class
  -- (public.npc_hull_for at her house's home — the one rule).
  v_player := public.new_house(null, v_name, p_spec->>'nation', v_home, v_fl->>'name',
                               public.npc_hull_for(v_fl->'ships'->0->>'class', (select id from public.ports where code = v_home)),
                               v_fl->'ships'->0->>'name',
$h$),
('public.npc_found(jsonb)', 2,
$h$      perform public.commission_ship(v_player, v_fleet, v_fl->'ships'->0->>'class', v_fl->'ships'->0->>'name', true, true);
$h$,
$h$      perform public.commission_ship(v_player, v_fleet,
        public.npc_hull_for(v_fl->'ships'->0->>'class', (select id from public.ports where code = v_home)),   -- 0167
        v_fl->'ships'->0->>'name', true, true);
$h$),
('public.npc_found(jsonb)', 3,
$h$      perform public.commission_ship(v_player, v_fleet, v_sh->>'class', v_sh->>'name', false, true);
$h$,
$h$      perform public.commission_ship(v_player, v_fleet,
        public.npc_hull_for(v_sh->>'class', (select id from public.ports where code = v_home)),   -- 0167
        v_sh->>'name', false, true);
$h$),
('public.npc_found(jsonb)', 4,
$h$  if (select ducats from public.players where id = v_player) <> (p_spec->>'capital')::bigint then
$h$,
$h$  -- 0167 (S18): HER HULL SKILLS, FIXED ONCE from the hulls she sails — endowed and paid, so the purse
  -- check below still reads her capital. After npc_fix_level, so her hulls' level is the live skills'.
  perform public.npc_fix_hull_skills(v_player);

  if (select ducats from public.players where id = v_player) <> (p_spec->>'capital')::bigint then
$h$),
('public.npc_fit_loadout(uuid)', 1,
$h$  select count(distinct pattern) into v_n from public.npc_loadouts where class_code = v_class;
$h$,
$h$  -- 0167 (S18): a line hull a merchant sails in place of a live class wears THAT class's patterns
  -- (public.npc_line_hulls) — one authored set per live class, data/npc-loadouts.json, never a copy.
  v_class := coalesce((select h.live_class from public.npc_line_hulls h where h.class_code = v_class), v_class);
  select count(distinct pattern) into v_n from public.npc_loadouts where class_code = v_class;
$h$);

create or replace function pg_temp.recut_0167(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := replace(pg_get_functiondef(p_fn::regprocedure), E'\r', '');
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0167 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0167(v_def, h.old);
    if v_n <> 1 then
      raise exception '0167 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0167(fn) from defs_before_0167 order by fn;

create temp table fixed_0167 (player_id uuid primary key, ducats bigint) on commit drop;

-- ── 4. CONVERTED ONCE ──────────────────────────────────────────────────────────────────────────
-- the candidates: every merchant hull whose house's home country has a line hull for her class
create temp table convert_0167 on commit drop as
select b.id, b.player_id, b.class as from_class,
       public.npc_hull_for(b.class, h.home_port_id) as to_class, b.durability, b.cargo_t
  from ships_before_0167 b join public.npc_houses h on h.player_id = b.player_id
 where public.npc_hull_for(b.class, h.home_port_id) <> b.class;

do $conv$
declare
  r      record;
  v_new  numeric;
begin
  for r in select * from convert_0167 order by id loop
    select round(least(nc.durability, r.durability * nc.durability / oc.durability), 2) into v_new
      from public.ship_classes oc, public.ship_classes nc where oc.code = r.from_class and nc.code = r.to_class;
    update public.ships set class_id = (select id from public.ship_classes where code = r.to_class), durability = v_new
     where id = r.id;
    -- her cargo must still fit: where it would not, she stays as she is (counted in the receipt)
    if public.ship_hold_capacity(r.id) < r.cargo_t then
      update public.ships set class_id = (select id from public.ship_classes where code = r.from_class), durability = r.durability
       where id = r.id;
    else
      insert into public.npc_hull_conversions (ship_id, from_class, to_class, durability_before, durability_after)
      values (r.id, r.from_class, r.to_class, r.durability, v_new);
    end if;
  end loop;
  -- HER HULL SKILLS, FIXED ONCE, for every house that now sails a line hull
  insert into fixed_0167 (player_id, ducats)
  select x.player_id, public.npc_fix_hull_skills(x.player_id)
    from (select distinct b.player_id from public.npc_hull_conversions c join ships_before_0167 b on b.id = c.ship_id) x;
end $conv$;

-- ── 5. THE PROBE (its own merchant companies, which build their own state; rolled back whole) ────
-- npc_found at an English harbour (a barca, a caravela latina and a nau → Crayer, caravela latina — England
-- builds none within the bounds — and Levant Merchantman) and at a Portuguese one (the live three, as before)
create or replace function pg_temp.probe_0167()
returns jsonb
language plpgsql
as $$
declare
  v_out jsonb := '{}'::jsonb;
  v_s   record;
  v_m   uuid;
  v_k   int := 0;
  v_cty text;
begin
  begin
    foreach v_cty in array array['ENG', 'PRT'] loop
      v_k := v_k + 1;
      select y.id as y_id, y.code as y_code, l.code as z_code, l.course as y_to_z,
             (select l2.course from public.npc_known_legs(l.to_port) l2 where l2.to_port = y.id) as z_to_y
        into v_s
        from public.ports y
        join public.nations n on n.id = public.port_nation(y.id) and n.code = v_cty
       cross join lateral public.npc_known_legs(y.id) l
       where y.kind = 'HARBOUR'
         and exists (select 1 from public.npc_known_legs(l.to_port) l2 where l2.to_port = y.id)
       order by y.code, l.code limit 1;
      if v_s.y_id is null then
        raise exception '0167 self-assert FAIL: no % harbour with a known course both ways — no subject', v_cty;
      end if;
      v_m := public.npc_found(jsonb_build_object(
        'company', 'Casa da Prova 0167 ' || v_cty, 'alt_company', 'Casa da Prova 0167 ' || v_cty || ' II', 'nation', v_cty,
        'ink', 'prt', 'master', 'Mestre da Prova',
        'blurb', 'A probe company founded so that a merchant can be seen to sail her own country''s ships.',
        'capital', 40000, 'patience', 0.20, 'wares', '[]'::jsonb, 'roster_ord', 9166 + v_k,
        'skills', '{}'::jsonb,
        'fleets', jsonb_build_array(jsonb_build_object(
          'name', 'Prova 0167 ' || v_cty, 'roster_ord', 9166 + v_k, 'days', 12,
          'ships', jsonb_build_array(jsonb_build_object('class', 'barca', 'name', 'Prova Barca ' || v_cty),
                                     jsonb_build_object('class', 'carlat', 'name', 'Prova Caravela ' || v_cty),
                                     jsonb_build_object('class', 'nau', 'name', 'Prova Nau ' || v_cty)),
          'officers', '[]'::jsonb,
          'stops', jsonb_build_array(jsonb_build_object('port', v_s.y_code, 'course', v_s.y_to_z),
                                     jsonb_build_object('port', v_s.z_code, 'course', v_s.z_to_y)),
          'alt_stops', jsonb_build_array(jsonb_build_object('port', v_s.y_code, 'course', v_s.y_to_z),
                                         jsonb_build_object('port', v_s.z_code, 'course', v_s.z_to_y))))));
      v_out := v_out || jsonb_build_object(v_cty, jsonb_build_object(
        'home', v_s.y_code,
        'classes', (select jsonb_agg(c.code order by s.name) from public.ships s join public.ship_classes c on c.id = s.class_id where s.player_id = v_m),
        'units', (select jsonb_object_agg(c.code, (select count(*) from public.fitted_units u where u.ship_id = s.id))
                    from public.ships s join public.ship_classes c on c.id = s.class_id where s.player_id = v_m),
        'skills', (select coalesce(jsonb_object_agg(sk.code, ps.level), '{}'::jsonb) from public.player_skills ps
                     join public.skills sk on sk.id = ps.skill_id where ps.player_id = v_m),
        'purse', (select ducats from public.players where id = v_m),
        'queue', (select count(*) from public.skill_queue where player_id = v_m),
        'again', public.npc_fix_hull_skills(v_m)));
    end loop;
    raise exception 'PROBE_ROLLBACK_0167';
  exception when others then
    if sqlerrm <> 'PROBE_ROLLBACK_0167' then raise; end if;
  end;
  return v_out;
end $$;

create temp table probe_0167 on commit drop as select pg_temp.probe_0167() as j;

-- ── 6. THE COMPARISONS ─────────────────────────────────────────────────────────────────────────
analyze public.npc_line_hulls, public.npc_hull_conversions;
create temp table ships_after_0167 on commit drop as
select b.id, c.code as class, s.durability, s.crew, cl.crew_required, cl.crew_max,
       public.ship_cargo_tuns(s.id) as cargo_t, voyage.ship_speed(s.id) as speed, public.ship_hold_capacity(s.id) as hold,
       (select md5(coalesce(string_agg(to_jsonb(u)::text, '|' order by u.id), '')) from public.fitted_units u where u.ship_id = s.id) as units_hash,
       (select md5(coalesce(string_agg(to_jsonb(cs)::text, '|' order by cs.player_officer_id), '')) from public.captain_seats cs where cs.ship_id = s.id) as seats_hash,
       (select max(cs.seat) from public.captain_seats cs where cs.ship_id = s.id) as top_seat,
       (select cc.cabins from public.class_cabins cc where cc.class_code = c.code) as cabins
  from ships_before_0167 b join public.ships s on s.id = b.id
  join public.ship_classes c on c.id = s.class_id join public.ship_classes cl on cl.id = s.class_id;
create temp table fleets_after_0167 on commit drop as
select f.id, f.status, voyage.fleet_speed(f.id) as speed,
       (select sum(a.hold) from ships_after_0167 a join ships_before_0167 b on b.id = a.id where b.fleet_id = f.id) as hold,
       (select sum(a.crew) from ships_after_0167 a join ships_before_0167 b on b.id = a.id where b.fleet_id = f.id) as crew,
       (select jsonb_object_agg(ce.code, public.crew_pct(f.id, null, ce.code)) from public.crew_effects ce
         where ce.scope = 'fleet' and ce.code <> 'category_spread') as crew_pct
  from fleets_before_0167 fb join public.fleets f on f.id = fb.id;
select pg_temp.time_reads_0167('after');

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_b     record;
  d       record;
  h       record;
  v_pp    record;
  v_rd    record;
  v_lap   record;
  v_bad   int;
  v_list  text;
  v_def   text;
  v_p     jsonb := (select j from probe_0167);
  v_notes text := '';
  v_conv  int := (select count(*) from public.npc_hull_conversions);
  v_kept  int := (select count(*) from convert_0167) - (select count(*) from public.npc_hull_conversions);
begin
  select * into v_b from before_0167;
  select * into v_lap from laps_before_0167;

  -- (a) THE ONE RULE LANDED, as generated (the world guard holds every column), and every line hull is a T1
  --     hull of a line other than Portugal's, its live class one of the three
  if (select count(*) from public.npc_line_hulls) <> 5
     or exists (select 1 from public.npc_line_hulls lh join public.class_profile p on p.class_code = lh.class_code
                 where p.tech <> 'T1' or p.line_code <> lh.line_code or lh.line_code = 'PRT'
                    or lh.live_class not in ('barca', 'carlat', 'nau')) then
    raise exception '0167 self-assert FAIL: npc_line_hulls is not the generated rule';
  end if;

  -- (b) ONLY MERCHANT HULLS MOVED, and only to their own country's line hull: no player row touched
  if (select md5(string_agg(to_jsonb(s)::text, '|' order by s.id)) from public.ships s join public.players p on p.id = s.player_id and not p.is_npc) is distinct from v_b.player_ships_hash
     or (select md5(string_agg(to_jsonb(p)::text, '|' order by p.id)) from public.players p where not p.is_npc) is distinct from v_b.players_hash
     or (select md5(coalesce(string_agg(to_jsonb(ps)::text, '|' order by ps.player_id, ps.skill_id), '')) from public.player_skills ps join public.players p on p.id = ps.player_id and not p.is_npc) is distinct from v_b.player_skills_hash then
    raise exception '0167 self-assert FAIL: a player row (ship, house or skill) moved';
  end if;
  select count(*), string_agg(a.id::text, ',') into v_bad, v_list
    from ships_after_0167 a join ships_before_0167 b on b.id = a.id
   where a.class <> b.class
     and (not exists (select 1 from public.npc_hull_conversions c where c.ship_id = a.id and c.from_class = b.class and c.to_class = a.class)
          or a.class <> (select public.npc_hull_for(b.class, nh.home_port_id) from public.npc_houses nh where nh.player_id = b.player_id));
  if v_bad <> 0 or exists (select 1 from ships_after_0167 a join ships_before_0167 b on b.id = a.id
                            where a.class = b.class and (a.durability <> b.durability
                                  or exists (select 1 from public.npc_hull_conversions c where c.ship_id = a.id))) then
    raise exception '0167 self-assert FAIL: a merchant hull changed class without its record or to a hull not its country''s (%), or an unconverted hull moved', v_list;
  end if;
  if (select count(*) from public.npc_hull_conversions) <> (select count(*) from ships_after_0167 a join ships_before_0167 b on b.id = a.id where a.class <> b.class) then
    raise exception '0167 self-assert FAIL: the conversion record does not count the hulls that changed';
  end if;

  -- (c) THE SEAM — HER CREW, HER GEAR, HER CABINS, HER CARGO: every converted hull's crew unchanged and
  --     inside the new hull's bounds (nobody stranded short of hands, nobody over the cap), her fitted units
  --     and seats byte for byte, every seat within the new cabins, every units' rack inside the new racks,
  --     her cargo within the new hold
  select count(*), string_agg(a.id::text, ',') into v_bad, v_list
    from ships_after_0167 a join ships_before_0167 b on b.id = a.id
   where a.class <> b.class
     and (a.crew <> b.crew or (b.crew >= (select crew_required from public.ship_classes where code = b.class) and a.crew < a.crew_required)
          or a.crew > a.crew_max or a.units_hash <> b.units_hash or a.seats_hash <> b.seats_hash
          or coalesce(a.top_seat, 0) > a.cabins or a.cargo_t > a.hold
          or exists (select 1 from public.fitted_units u join public.item_profile ip on ip.item_code = u.item_code
                      where u.ship_id = a.id group by ip.rack
                     having count(*) > coalesce((select cs.count from public.class_slots cs where cs.class_code = a.class and cs.slot = ip.rack), 0)));
  if v_bad <> 0 then
    raise exception '0167 self-assert FAIL: % converted hull(s) lost crew, a fitting, a seat or cargo room: %', v_bad, v_list;
  end if;

  -- (d) LAP ECONOMICS PER FLEET (the row's assert): every merchant fleet's speed within ± 5 %, cargo space
  --     within ± 10 % and crew — her wages — exactly as before; her status and what her captains give unmoved
  select count(*), string_agg(fa.id::text || ' ' || fb.speed || '→' || fa.speed || ' kn ' || fb.hold || '→' || fa.hold || ' t', '; ')
    into v_bad, v_list
    from fleets_after_0167 fa join fleets_before_0167 fb on fb.id = fa.id
   where abs(fa.speed - fb.speed) > 0.05 * fb.speed + 1e-9
      or abs(fa.hold - fb.hold) > 0.10 * fb.hold + 1e-9
      or fa.crew is distinct from fb.crew or fa.status is distinct from fb.status
      or fa.crew_pct is distinct from fb.crew_pct;
  if v_bad <> 0 then
    raise exception '0167 self-assert FAIL: % merchant fleet(s) moved past ± 5 %% speed, ± 10 %% cargo space, or changed crew, status or captains: %', v_bad, v_list;
  end if;

  -- (e) HULL SKILLS, FIXED ONCE: every house that sails a line hull holds every level her hulls ask for; no
  --     merchant queue row; her purse where it began (endowed, then paid); a second fix raises nothing
  select count(*) into v_bad
    from public.ships s join public.players p on p.id = s.player_id and p.is_npc
    join public.ship_classes c on c.id = s.class_id
    join public.skill_requirements sr on sr.subject_kind = 'hull' and sr.subject_code = c.code
   where coalesce((select ps.level from public.player_skills ps join public.skills sk on sk.id = ps.skill_id
                    where ps.player_id = p.id and sk.code = sr.skill_code), 0) < sr.level;
  if v_bad <> 0
     or (select count(*) from public.skill_queue q join public.players p on p.id = q.player_id and p.is_npc) <> v_b.npc_queue
     or (select coalesce(sum(p.ducats), 0) from public.players p where p.is_npc) <> v_b.npc_purses then
    raise exception '0167 self-assert FAIL: a merchant lacks a hull skill her hulls ask for (%), has a queue row, or her purse moved', v_bad;
  end if;

  -- (f) FOUNDED SO (rolled back): at an English harbour the barca is a Crayer, the nau a Levant Merchantman and
  --     the caravela latina stays (England builds none within the bounds); each wears her live class's gear;
  --     her hull skills English Small I, Light III, Medium I; her purse her capital; no queue row; a second fix
  --     raises nothing. At a Portuguese harbour the live three, nothing learned
  if v_p->'ENG'->'classes' is distinct from '["crayer", "carlat", "levanter"]'::jsonb
     or v_p->'ENG'->'skills' is distinct from '{"ENG_SMALL": 1, "ENG_LIGHT": 3, "ENG_MEDIUM": 1}'::jsonb
     or (v_p->'ENG'->>'purse')::bigint <> 40000 or (v_p->'ENG'->>'queue')::int <> 0 or (v_p->'ENG'->>'again')::int <> 0
     or (select count(*) from jsonb_each_text(v_p->'ENG'->'units') e where e.value::int = 0) <> 0
     or v_p->'PRT'->'classes' is distinct from '["barca", "carlat", "nau"]'::jsonb
     or v_p->'PRT'->'skills' is distinct from '{}'::jsonb
     or (v_p->'PRT'->>'purse')::bigint <> 40000 or (v_p->'PRT'->>'again')::int <> 0
     or (v_p->'ENG'->'units'->>'crayer')::int <> (v_p->'PRT'->'units'->>'barca')::int then
    raise exception '0167 self-assert FAIL: npc_found did not found her country''s ships, her gear or her hull skills: %', v_p;
  end if;
  if exists (select 1 from public.players where company_name like 'Casa da Prova 0167%') then
    raise exception '0167 self-assert FAIL: the probe world was not rolled back';
  end if;

  -- (g) THE RE-CUTS reverse to their pre-images; ACL / volatility / definer / config unmoved
  for d in select * from defs_before_0167 order by fn loop
    v_def := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0167 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0167(v_def, h.new) <> 1 then
        raise exception '0167 self-assert FAIL: hunk % of % is not in the new body exactly once', h.n, d.fn;
      end if;
      v_def := replace(v_def, h.new, h.old);
    end loop;
    if v_def <> d.def then
      raise exception '0167 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef, coalesce(pr.proconfig::text, '') as cfg
      into v_pp from pg_proc pr where pr.oid = d.fn::regprocedure;
    if v_pp.acl <> d.acl or v_pp.vol <> d.vol or v_pp.secdef <> d.secdef or v_pp.cfg <> d.cfg then
      raise exception '0167 self-assert FAIL: % changed its ACL, volatility, definer or config', d.fn;
    end if;
  end loop;

  -- (h) THE WALL
  if (select count(*) from public.client_rpc_entry_points()) <> v_b.entry_points
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0
     or has_function_privilege('anon', 'public.npc_hull_for(text, uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.npc_hull_for(text, uuid)', 'execute')
     or has_function_privilege('anon', 'public.npc_fix_hull_skills(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.npc_fix_hull_skills(uuid)', 'execute')
     or has_table_privilege('anon', 'public.npc_line_hulls', 'select,insert,update,delete')
     or has_table_privilege('authenticated', 'public.npc_line_hulls', 'select,insert,update,delete')
     or has_table_privilege('anon', 'public.npc_hull_conversions', 'select,insert,update,delete')
     or has_table_privilege('authenticated', 'public.npc_hull_conversions', 'select,insert,update,delete') then
    raise exception '0167 self-assert FAIL: the registry, the grant wall or the read wall moved, or a client can reach a new function or table';
  end if;

  for v_rd in select bf.what, bf.ms as before_ms, af.ms as after_ms, bf.hulls
             from reads_0167 bf join reads_0167 af on af.what = bf.what and af.phase = 'after'
            where bf.phase = 'before' order by bf.what loop
    v_notes := v_notes || format('%s over %s merchant hull(s) %s ms → %s ms; ', v_rd.what, v_rd.hulls, v_rd.before_ms, v_rd.after_ms);
  end loop;

  raise notice '0167 self-assert ok: A MERCHANT SAILS HER OWN COUNTRY''S SHIPS. THE RULE: % line hull(s) (%). CONVERTED: % merchant hull(s) (%), % left as they were (cargo would not fit), across % merchant fleet(s) — every merchant fleet''s speed within ± 5 %%, cargo space within ± 10 %%, crew (wages) exactly as before, status and captains unmoved; every converted hull''s crew, gear, seats and cargo inside her new hull. HULL SKILLS: % house(s) fixed once (% d. endowed and paid to their home harbours), no queue row, merchant purses unmoved. FOUNDED (rolled back): at % an English company sails % with %; at % a Portuguese one the live three. NO PLAYER ROW MOVED. LAPS before (last ten a fleet): % laps, % %% closed at zero net or below, mean % h — the after-figure is the same query on prod a day on. 2 bodies reverse, no entry point. READS: %',
    (select count(*) from public.npc_line_hulls),
    (select string_agg(live_class || ' → ' || class_code || ' (' || line_code || ')', ', ' order by line_code, live_class) from public.npc_line_hulls),
    v_conv,
    (select coalesce(string_agg(x.k || ' ' || x.n, ', '), 'none') from (select from_class || ' → ' || to_class as k, count(*) as n from public.npc_hull_conversions group by 1 order by 1) x),
    v_kept,
    (select count(distinct b.fleet_id) from public.npc_hull_conversions c join ships_before_0167 b on b.id = c.ship_id),
    (select count(*) from fixed_0167), (select coalesce(sum(ducats), 0) from fixed_0167),
    v_p->'ENG'->>'home', v_p->'ENG'->'classes', v_p->'ENG'->'skills', v_p->'PRT'->>'home',
    v_lap.laps, v_lap.zero_net_pct, v_lap.mean_hours, v_notes;
end $$;
