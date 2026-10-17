-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0155 — A PASSAGE TEACHES THE SKILL IN TRAINING  (K3: bonus training from sailing, D6 — DARK)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY NOW ─────────────────────────────────────────────────────────────────────────────────────
-- docs/SKILLS_AND_CAPTAINS.md D6, §3.2 "Bonus training" and §8 row K3 (research: docs/research/EVE_SKILLS.md
-- §1.9, recommendation 8 — EVE pays skill points for daily goals; the one accelerator its players accept).
-- An arrival after a passage of at least skill_sp_arrival_min_nm adds skill_sp_per_arrival skill points to
-- the skill in training, up to skill_sp_day_cap a real (UTC) day. Never sold for coin (D7).
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
--   KNOBS  skill_sp_per_arrival 0 (OFF — the dark switch; D6's figure is 1,000), skill_sp_arrival_min_nm 300,
--          skill_sp_day_cap 10,000. Inserted only where absent.
--   TABLE  public.skill_sp_grants (player_id, day, sp): what the bonus gave a house on a UTC day. Written only
--          by public.skill_sp_grant_for. Server-only (RLS on, no client grant).
--   public.skill_sp_bonus_today(player)   THE one reading of the bonus's state: {per_arrival, min_nm, cap,
--          today}. Read by skill_sp_grant_for and world.skills.
--   public.skill_sp_grant_for(player, sp) THE one writer. Merchants (no queue) leave at once, writing nothing.
--          With nothing in training it credits nothing and says so ("No skill in training: the sailing bonus
--          waits for one."); past the day's cap it credits what is left. Otherwise it COMPOSES THE QUEUE'S OWN
--          CHAIN STEP — public.skill_queue_set_for (the one writer of skill_queue) with the queue as it stands
--          banks the entry in progress; the bonus joins that skill's points; the same call again rebuilds the
--          chain from them — so the head entry finishes exactly sp ÷ skill_sp_per_hour hours sooner and every
--          entry after it moves up with it. The queue still has one writer.
--   THE HUNKS (sliced from the bodies as they stand after 0154 — K2 re-cut voyage.settle; world.skills is
--          prod's 0151 body — LF-normalised, each occurring once, each reversing to its pre-image, ACL unchanged):
--       voyage.settle   the arrival arm, before the VOYAGE_REPORT: the grant (only while the knob is above 0
--                       and the passage is long enough); the report carries its answer as `training` — and,
--                       while the knob is 0, the report and every write are what they were.
--       world.skills    `sailing_bonus` (skill_sp_bonus_today) — served only while the knob is above 0, so the
--                       Academy reads exactly as before while it is off.
--
-- ── WHAT IT DELIBERATELY DOES NOT DO ────────────────────────────────────────────────────────────
-- Light the bonus (the knob ships 0). Sell skill points, or give them anywhere but the skill in training (D7).
-- Touch a merchant (no queue, no row: asserted by row counts). Change a level, a queue entry or an enrolment
-- of any house (asserted). Touch the client (the Training line "+1,000 from sailing today · 3,000 / 10,000"
-- follows once this is LIVE and lit; world.skills serves its figures).
--
-- ── THE PROOF ───────────────────────────────────────────────────────────────────────────────────
-- (a) DARK (knob 0): a probe passage settled by the old body and by the new = the same passage, report and
--     writes, to the byte; world.skills old vs new = the same, as nobody and as every human house.
-- (b) THE PROBE (own throw-away houses that build their own state, rolled back), the knob at 1,000:
--     a 300+ nm arrival moves the head entry's finish earlier by 1,000 SP ÷ 1,800 SP/h = 2,000 s (to the
--     millisecond) and every later entry by the same; the report says so and the day's row reads 1,000;
--     ten grants fill the day (10,000) and the 11th arrival credits 0 ("spent for today"); a passage under
--     the minimum credits nothing and writes nothing; a house with an empty queue is told the bonus waits;
--     a merchant's arrival writes no grant, skill point, queue or level row; world.skills serves the day.
-- (c) the bodies reverse to their pre-images; ACLs unmoved; new functions server-only; no entry point.
--
-- ── LOCKS ───────────────────────────────────────────────────────────────────────────────────────
-- None beyond the row writes of the rolled-back probe and the knob rows. No table is altered.
--
-- ROLLBACK: a forward slice restoring the two bodies (their hunks' OLD text), dropping the two functions and
-- public.skill_sp_grants and deleting the three knobs. Skill points already banked by the bonus stay banked (a
-- house's progress is never taken).
-- SUPERSEDES, by hunks sliced from the bodies after 0154, each asserted to occur exactly once, ACLs unchanged:
-- voyage.settle (0154), world.skills (0151).
-- VERSION: 0155 (provisional; renumbered to head + 1 at merge). Applies on K2 (0154).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  perform set_config('random_page_cost', '1.1', true);   -- prod's planner page cost (0149's header)
end $guard$;

-- ── 0. HELPERS (pg_temp, gone at commit) ───────────────────────────────────────────────────────
create or replace function pg_temp.occurs_0155(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

create or replace function pg_temp.rb_0155(p_sql text)
returns jsonb
language plpgsql
as $$
declare
  r jsonb;
begin
  begin
    execute p_sql into r;
    raise exception 'RB_0155';
  exception when others then
    if sqlerrm <> 'RB_0155' then raise; end if;
  end;
  return r;
end $$;

create or replace function pg_temp.as_0155(p_uid uuid)
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  perform set_config('request.jwt.claims', case when p_uid is null then '' else json_build_object('sub', p_uid)::text end, true);
end $$;

-- ── 1. THE PRE-IMAGES ──────────────────────────────────────────────────────────────────────────
create temp table defs_before_0155 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('voyage.settle(uuid, timestamp with time zone)'), ('world.skills()')) f(fn);

create temp table untouched_before_0155 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl
  from (values ('public.skill_queue_set_for(uuid, jsonb)'), ('public.skill_queue_now(uuid)'),
               ('public.skill_queue_refusal(uuid, jsonb, uuid)'), ('public.skill_level_at(uuid, text, timestamp with time zone)'),
               ('public.skill_sp_for(integer, integer)'), ('public.skill_lock(uuid)'), ('public.voyage_xp(uuid)'),
               ('public.emit_event(uuid, text, jsonb)'), ('voyage.report_line(integer, text, jsonb)')) f(fn);

create temp table before_0155 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from public.player_skills) as skills_rows,
       (select md5(coalesce(string_agg(format('%s/%s/%s', ps.player_id, ps.skill_id, ps.level), '|' order by ps.player_id, ps.skill_id), '')) from public.player_skills ps) as skills_hash,
       (select md5(coalesce(string_agg(format('%s/%s/%s/%s/%s', q.player_id, q.pos, q.skill_id, q.to_level, q.finishes_at), '|' order by q.player_id, q.pos), '')) from public.skill_queue q) as queue_hash,
       (select md5(coalesce(string_agg(format('%s/%s/%s', x.player_id, x.skill_id, x.sp), '|' order by x.player_id, x.skill_id), '')) from public.skill_sp x) as sp_hash;

-- the old bodies, under pg_temp names (the dark comparison)
do $$
declare
  d     record;
  v_def text;
  v_new text;
begin
  for d in select * from defs_before_0155 loop
    v_new := 'CREATE OR REPLACE FUNCTION pg_temp.' || replace(split_part(d.fn, '(', 1), '.', '_') || '_b0155(';
    v_def := replace(d.def, 'CREATE OR REPLACE FUNCTION ' || split_part(d.fn, '(', 1) || '(', v_new);
    if pg_temp.occurs_0155(v_def, v_new) <> 1 then
      raise exception '0155 self-assert FAIL: could not rename the pre-image of %', d.fn;
    end if;
    execute v_def;
  end loop;
end $$;

-- ── 2. THE KNOBS (only where absent: a knob already set is left alone) ──────────────────────────
insert into public.world_config (key, value, description) values
  ('skill_sp_per_arrival', '0'::jsonb,
   '0155 (K3, D6): skill points an arrival adds to the skill in training after a passage of at least '
   'skill_sp_arrival_min_nm (public.skill_sp_grant_for). 0 = OFF, the dark switch; D6''s figure is 1000.'),
  ('skill_sp_arrival_min_nm', '300'::jsonb,
   '0155 (K3, D6): the shortest passage (voyages.total_nm) whose arrival earns the sailing bonus.'),
  ('skill_sp_day_cap', '10000'::jsonb,
   '0155 (K3, D6): the most skill points the sailing bonus gives one house in a real (UTC) day (public.skill_sp_grants).')
on conflict (key) do nothing;

-- ── 3. THE TABLE ───────────────────────────────────────────────────────────────────────────────
create table if not exists public.skill_sp_grants (
  player_id uuid    not null,
  day       date    not null,
  sp        numeric not null default 0 check (sp >= 0),
  primary key (player_id, day)
);
comment on table public.skill_sp_grants is
  '0155 (K3, D6): what the sailing bonus gave a house on a UTC day (skill_sp_day_cap bounds it). Written only by '
  'public.skill_sp_grant_for; read by public.skill_sp_bonus_today. Merchants never have a row. Server-only.';
alter table public.skill_sp_grants enable row level security;
revoke all on table public.skill_sp_grants from public, anon, authenticated;

-- ── 4. THE READING AND THE WRITER ──────────────────────────────────────────────────────────────
create or replace function public.skill_sp_bonus_today(p_player uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  -- 0155 (K3, D6): THE ONE READING OF THE SAILING BONUS — what an arrival gives, after how long a passage, a
  -- day's cap, and what this house has had of it today (UTC). Read by public.skill_sp_grant_for and world.skills.
  return jsonb_build_object(
    'per_arrival', public.wc_num('skill_sp_per_arrival'),
    'min_nm', public.wc_num('skill_sp_arrival_min_nm'),
    'cap', public.wc_num('skill_sp_day_cap'),
    'today', coalesce((select g.sp from public.skill_sp_grants g
                        where g.player_id = p_player and g.day = (now() at time zone 'utc')::date), 0));
end $$;
revoke all on function public.skill_sp_bonus_today(uuid) from public, anon, authenticated;

create or replace function public.skill_sp_grant_for(p_player uuid, p_sp numeric)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_state   jsonb;
  v_had     numeric;
  v_cap     numeric;
  v_give    numeric;
  h         record;
  v_entries jsonb;
  v_r       jsonb;
begin
  -- 0155 (K3, D6): THE ONE WRITER OF THE SAILING BONUS. A merchant has no queue: she leaves here, writing nothing.
  if p_player is null or coalesce(p_sp, 0) <= 0
     or exists (select 1 from public.players x where x.id = p_player and x.is_npc) then
    return null;
  end if;
  perform public.skill_lock(p_player);
  -- the entry in training: the one whose time is running now
  select q.pos, q.skill_id, q.to_level, sk.code, sk.name into h
    from public.skill_queue q join public.skills sk on sk.id = q.skill_id
   where q.player_id = p_player and q.starts_at <= now() and q.finishes_at > now()
   order by q.pos limit 1;
  if h.skill_id is null then
    return jsonb_build_object('credited', 0, 'reason', 'NOTHING_IN_TRAINING',
                              'words', 'No skill in training: the sailing bonus waits for one.');
  end if;
  v_state := public.skill_sp_bonus_today(p_player);
  v_had   := (v_state->>'today')::numeric;
  v_cap   := (v_state->>'cap')::numeric;
  v_give  := greatest(0, least(p_sp, v_cap - v_had));
  if v_give = 0 then
    return jsonb_build_object('credited', 0, 'reason', 'DAY_CAP', 'today', v_had, 'cap', v_cap,
      'words', format('The sailing bonus is spent for today (%s / %s).',
                      to_char(v_had, 'FM999,999,999'), to_char(v_cap, 'FM999,999,999')));
  end if;
  -- THE QUEUE'S OWN CHAIN STEP (public.skill_queue_set_for, the one writer of skill_queue), with the queue as
  -- it stands: 1. it banks the entry in progress (the points trained so far) …
  select coalesce(jsonb_agg(jsonb_build_object('code', x->>'code', 'level', (x->>'level')::int) order by (x->>'pos')::int), '[]'::jsonb)
    into v_entries from jsonb_array_elements(public.skill_queue_now(p_player)) x;
  v_r := public.skill_queue_set_for(p_player, v_entries);
  if not coalesce((v_r->>'ok')::boolean, false) then
    return jsonb_build_object('credited', 0, 'reason', 'QUEUE_REFUSED', 'refusal', v_r,
                              'words', 'The sailing bonus could not reach the queue as it stands.');
  end if;
  -- 2. … the bonus joins the points the house holds in that skill …
  insert into public.skill_sp (player_id, skill_id, sp) values (p_player, h.skill_id, v_give)
  on conflict (player_id, skill_id) do update set sp = public.skill_sp.sp + excluded.sp;
  -- 3. … and the same step rebuilds the chain from them: the head finishes v_give ÷ skill_sp_per_hour hours
  --    sooner, and every entry after it with it.
  v_r := public.skill_queue_set_for(p_player, v_entries);
  insert into public.skill_sp_grants (player_id, day, sp) values (p_player, (now() at time zone 'utc')::date, v_give)
  on conflict (player_id, day) do update set sp = public.skill_sp_grants.sp + excluded.sp;
  return jsonb_build_object('credited', v_give, 'skill', h.code, 'level', h.to_level, 'today', v_had + v_give, 'cap', v_cap,
    'words', format('+%s skill points from sailing to %s %s (%s / %s today).',
                    to_char(v_give, 'FM999,999,999'), h.name, public.skill_level_word(h.to_level),
                    to_char(v_had + v_give, 'FM999,999,999'), to_char(v_cap, 'FM999,999,999')));
end $$;
revoke all on function public.skill_sp_grant_for(uuid, numeric) from public, anon, authenticated;

-- ── 5. THE RE-CUTS ─────────────────────────────────────────────────────────────────────────────
create temp table hunks_0155 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0155 values
('voyage.settle(uuid, timestamp with time zone)', 1,
$h$  v_stores    numeric;
begin
$h$,
$h$  v_stores    numeric;
  v_bonus     jsonb;     -- 0155 (K3): the sailing bonus's answer, for the report
begin
$h$),
('voyage.settle(uuid, timestamp with time zone)', 2,
$h$    v_report := public.emit_event(f.player_id, 'VOYAGE_REPORT', jsonb_build_object(
$h$,
$h$    -- 0155 (K3, D6): THE SAILING BONUS — a passage of at least skill_sp_arrival_min_nm adds skill_sp_per_arrival
    -- skill points to the skill in training (public.skill_sp_grant_for: capped a day; nothing for a merchant, who
    -- has no queue). The knob at 0 is OFF, and then nothing below is read or written.
    if public.wc_num('skill_sp_per_arrival') > 0 and v.total_nm >= public.wc_num('skill_sp_arrival_min_nm') then
      v_bonus := public.skill_sp_grant_for(f.player_id, public.wc_num('skill_sp_per_arrival'));
    end if;
    v_report := public.emit_event(f.player_id, 'VOYAGE_REPORT', jsonb_build_object(
$h$),
('voyage.settle(uuid, timestamp with time zone)', 3,
$h$                  from public.voyage_events ve where ve.voyage_id = v.id)));
$h$,
$h$                  from public.voyage_events ve where ve.voyage_id = v.id))
      -- 0155: the bonus's own words, when it was asked
      || case when v_bonus is null then '{}'::jsonb else jsonb_build_object('training', v_bonus) end);
$h$),
('world.skills()', 1,
$h$  return jsonb_build_object(
    'max_level', public.wc_int('skill_max_level'),
$h$,
$h$  -- 0155 (K3, D6): the sailing bonus — what it has given you today, of its cap — served while it is on
  return (case when public.wc_num('skill_sp_per_arrival') > 0
               then jsonb_build_object('sailing_bonus', public.skill_sp_bonus_today(v_player)) else '{}'::jsonb end)
         || jsonb_build_object(
    'max_level', public.wc_int('skill_max_level'),
$h$);

create or replace function pg_temp.recut_0155(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := replace(pg_get_functiondef(p_fn::regprocedure), E'\r', '');
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0155 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0155(v_def, h.old);
    if v_n <> 1 then
      raise exception '0155 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0155(fn) from defs_before_0155 order by fn;

-- ── 6. DARK: world.skills old vs new, as nobody and as every human house ────────────────────────
create temp table academy_0155 (n int, bad int) on commit drop;
do $$
declare
  p     record;
  v_n   int := 0;
  v_bad int := 0;
begin
  for p in select null::uuid as uid union all select pl.auth_uid from public.players pl where not pl.is_npc and pl.auth_uid is not null loop
    perform pg_temp.as_0155(p.uid);
    v_n := v_n + 1;
    if world.skills() is distinct from pg_temp.world_skills_b0155() then
      v_bad := v_bad + 1;
    end if;
  end loop;
  perform pg_temp.as_0155(null);
  insert into academy_0155 values (v_n, v_bad);
end $$;

-- ── 7. THE PROBE (own throw-away houses that build their own state; rolled back) ────────────────
create or replace function pg_temp.passage_0155(p_fleet uuid, p_from uuid, p_to uuid)
returns uuid
language plpgsql
as $$
declare
  v_leg jsonb;
begin
  select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
    into v_leg from public.sea_reaches a, public.sea_reaches b where a.port_id = p_from and b.port_id = p_to;
  return voyage.depart(p_fleet, voyage.segments_from_course(v_leg), p_from, p_to, now() - interval '30 days');
end $$;

-- one passage settled (by the old body or the new), and what it left: the voyage, its days, the hulls, the
-- fleet, its report, the house's training
create or replace function pg_temp.settle_0155(p_voyage uuid, p_fleet uuid, p_old boolean)
returns jsonb
language plpgsql
as $$
declare
  v_voy uuid := p_voyage;
  v_p   uuid := (select player_id from public.fleets where id = p_fleet);
begin
  if p_old then
    perform pg_temp.voyage_settle_b0155(p_fleet, now());
  else
    perform voyage.settle(p_fleet, now());
  end if;
  return jsonb_build_object(
    'nm', (select v.total_nm from public.voyages v where v.id = v_voy),
    'voyage', (select jsonb_build_object('status', v.status, 'eta', v.eta, 'delay_hours', v.delay_hours, 'days', v.last_settled_day)
                 from public.voyages v where v.id = v_voy),
    'events', (select coalesce(jsonb_agg(jsonb_build_object('day', ve.day_index, 'kind', ve.kind, 'payload', ve.payload) order by ve.day_index), '[]'::jsonb)
                 from public.voyage_events ve where ve.voyage_id = v_voy),
    'ships', (select coalesce(jsonb_agg(jsonb_build_object('d', s.durability, 'crew', s.crew, 'water', s.water_t, 'food', s.food_t) order by s.id), '[]'::jsonb)
                from public.ships s where s.fleet_id = p_fleet),
    'fleet', (select jsonb_build_object('status', f.status, 'port', f.port_id) from public.fleets f where f.id = p_fleet),
    'report', (select e.payload from public.events e
                where e.player_id = v_p and e.kind = 'VOYAGE_REPORT' and e.payload->>'voyage_id' = v_voy::text),
    'reports', (select count(*) from public.events e where e.player_id = v_p and e.kind = 'VOYAGE_REPORT'),
    'queue', (select coalesce(jsonb_agg(jsonb_build_object('pos', q.pos, 'level', q.to_level, 'finishes_at', q.finishes_at) order by q.pos), '[]'::jsonb)
                from public.skill_queue q where q.player_id = v_p),
    'sp', (select coalesce(jsonb_agg(jsonb_build_object('skill', x.skill_id, 'sp', x.sp) order by x.skill_id), '[]'::jsonb)
             from public.skill_sp x where x.player_id = v_p),
    'grants', (select coalesce(jsonb_agg(jsonb_build_object('day', g.day, 'sp', g.sp)), '[]'::jsonb) from public.skill_sp_grants g where g.player_id = v_p));
end $$;

-- a passage departed and settled by the new body
create or replace function pg_temp.sail_0155(p_fleet uuid, p_from uuid, p_to uuid)
returns jsonb
language sql
as $$ select pg_temp.settle_0155(pg_temp.passage_0155(p_fleet, p_from, p_to), p_fleet, false) $$;

create or replace function pg_temp.probe_0155()
returns jsonb
language plpgsql
as $$
declare
  c_p    constant uuid := '00000000-0155-4000-8000-000000000001';
  c_q    constant uuid := '00000000-0155-4000-8000-000000000002';
  v_lis  uuid := (select id from public.ports where code = 'LIS');
  v_fnc  uuid := (select id from public.ports where code = 'FNC');
  v_p    uuid;
  v_pf   uuid;
  v_q    uuid;
  v_qf   uuid;
  v_m    uuid;
  v_mf   uuid;
  v_out  jsonb := '{}'::jsonb;
  v_r    jsonb;
  v_rate numeric := public.wc_num('skill_sp_per_hour');
  v_rows jsonb;
  v_voy  uuid;
  i      int;
begin
  begin
    if public.wc_num('skill_sp_per_arrival') <> 0 then
      raise exception '0155 self-assert FAIL: the sailing bonus is on before the probe — this file ships it off';
    end if;
    -- P: a company at Lisbon holding Navigation III, training Navigation IV then V
    v_p := public.new_house(c_p, 'Casa da Prova 0155', 'PRT', 'LIS');
    select id into v_pf from public.fleets where player_id = v_p;
    perform public.credit(v_p, 'PROBE_0155', 10000000);
    insert into public.player_skills (player_id, skill_id, level) select v_p, s.id, 3 from public.skills s where s.code = 'NAVIGATION';
    v_r := public.skill_queue_set_for(v_p, '[{"code": "NAVIGATION", "level": 4}, {"code": "NAVIGATION", "level": 5}]'::jsonb);
    if not coalesce((v_r->>'ok')::boolean, false) then
      raise exception '0155 self-assert FAIL: the probe could not queue Navigation IV and V: %', v_r;
    end if;
    -- DARK (knob 0): one departure, settled by the old body and by the new from the same start — the same
    -- passage, report and writes; then settled for real (she lies at Funchal)
    v_voy := pg_temp.passage_0155(v_pf, v_lis, v_fnc);
    v_out := v_out || jsonb_build_object('dark', jsonb_build_object(
      'new', pg_temp.rb_0155(format('select pg_temp.settle_0155(%L, %L, false)', v_voy, v_pf)),
      'old', pg_temp.rb_0155(format('select pg_temp.settle_0155(%L, %L, true)', v_voy, v_pf))));
    perform voyage.settle(v_pf, now());

    -- ON (inside this rolled-back block)
    update public.world_config set value = '1000'::jsonb where key = 'skill_sp_per_arrival';
    v_out := v_out || jsonb_build_object('before', jsonb_build_object(
      'queue', (select jsonb_agg(jsonb_build_object('pos', q.pos, 'finishes_at', q.finishes_at) order by q.pos) from public.skill_queue q where q.player_id = v_p)));
    v_r := pg_temp.sail_0155(v_pf, v_fnc, v_lis);
    v_out := v_out || jsonb_build_object('first', v_r, 'min_nm', public.wc_num('skill_sp_arrival_min_nm'));
    -- nine more grants fill the day (the core, as nine arrivals would call it) …
    for i in 2 .. 10 loop
      perform public.skill_sp_grant_for(v_p, 1000);
    end loop;
    v_out := v_out || jsonb_build_object('tenth', public.skill_sp_bonus_today(v_p),
      'queue10', (select jsonb_agg(jsonb_build_object('pos', q.pos, 'level', q.to_level, 'finishes_at', q.finishes_at) order by q.pos) from public.skill_queue q where q.player_id = v_p));
    -- … and the eleventh arrival credits nothing
    v_r := pg_temp.sail_0155(v_pf, v_lis, v_fnc);
    v_out := v_out || jsonb_build_object('eleventh', v_r);
    -- a passage under the minimum (the minimum raised past this one) credits nothing and writes nothing
    update public.world_config set value = to_jsonb((v_out->'first'->>'nm')::numeric + 1) where key = 'skill_sp_arrival_min_nm';
    update public.world_config set value = '20000'::jsonb where key = 'skill_sp_day_cap';
    v_r := pg_temp.sail_0155(v_pf, v_fnc, v_lis);
    v_out := v_out || jsonb_build_object('short', v_r);
    update public.world_config set value = '300'::jsonb where key = 'skill_sp_arrival_min_nm';
    update public.world_config set value = '10000'::jsonb where key = 'skill_sp_day_cap';
    -- the Academy serves the day, as P
    perform pg_temp.as_0155(c_p);
    v_out := v_out || jsonb_build_object('academy', world.skills()->'sailing_bonus');
    perform pg_temp.as_0155(null);

    -- Q: a company with nothing in training is told so, and nothing is written
    v_q := public.new_house(c_q, 'Casa da Fila Vazia 0155', 'PRT', 'LIS');
    select id into v_qf from public.fleets where player_id = v_q;
    v_out := v_out || jsonb_build_object('empty', pg_temp.sail_0155(v_qf, v_lis, v_fnc));

    -- M: a merchant company's arrival writes no grant, skill point, queue or level
    v_m := public.new_house(null, 'Companhia da Prova 0155', 'PRT', 'LIS', 'Prova', 'barca', 'Prova', null, true);
    select id into v_mf from public.fleets where player_id = v_m;
    select jsonb_build_array((select count(*) from public.skill_sp_grants), (select count(*) from public.skill_sp),
                             (select count(*) from public.skill_queue), (select count(*) from public.player_skills))
      into v_rows;
    v_r := pg_temp.sail_0155(v_mf, v_lis, v_fnc);
    v_out := v_out || jsonb_build_object('merchant', jsonb_build_object(
      'arrived', v_r->'voyage'->>'status', 'nm', v_r->'nm', 'training', v_r->'report'->'training',
      'rows_before', v_rows,
      'rows_after', jsonb_build_array((select count(*) from public.skill_sp_grants), (select count(*) from public.skill_sp),
                                      (select count(*) from public.skill_queue), (select count(*) from public.player_skills))));
    v_out := v_out || jsonb_build_object('rate', v_rate);
    raise exception 'PROBE_ROLLBACK_0155';
  exception when others then
    if sqlerrm <> 'PROBE_ROLLBACK_0155' then raise; end if;
  end;
  perform pg_temp.as_0155(null);
  return v_out;
end $$;

create temp table probe_0155 (j jsonb) on commit drop;
do $$
declare
  v_try   int := 0;
  v_state text;
  v_msg   text;
begin
  loop
    v_try := v_try + 1;
    begin
      insert into probe_0155 select pg_temp.probe_0155();
      exit;
    exception when lock_not_available or deadlock_detected then
      get stacked diagnostics v_msg = message_text, v_state = returned_sqlstate;
    end;
    if v_try >= 5 then
      raise exception '0155 self-assert FAIL: LOCK CONTENTION, not a result — the probe could not get its locks in 5 tries (%: %). Re-run the push.',
        v_state, v_msg;
    end if;
    perform pg_sleep(0.2);
  end loop;
end $$;

-- ── 8. SELF-ASSERT ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  b       record;
  d       record;
  h       record;
  p       record;
  v_def   text;
  v_pr    jsonb := (select j from probe_0155);
  v_ac    record;
  v_shift numeric;
  v_ok    boolean;
begin
  select * into b from before_0155;
  select * into v_ac from academy_0155;
  if public.wc_num('skill_sp_per_arrival') <> 0 or public.wc_num('skill_sp_arrival_min_nm') <> 300
     or public.wc_num('skill_sp_day_cap') <> 10000 then
    raise exception '0155 self-assert FAIL: the knobs are not as shipped (per arrival %, min nm %, cap %) — or one was already set',
      public.wc_num('skill_sp_per_arrival'), public.wc_num('skill_sp_arrival_min_nm'), public.wc_num('skill_sp_day_cap');
  end if;

  -- (a) DARK: the same passage, report and writes, old body vs new; the Academy unmoved for every reader
  if v_pr->'dark'->'new' is distinct from v_pr->'dark'->'old' or v_pr->'dark'->'new'->'voyage'->>'status' <> 'ARRIVED'
     or v_pr->'dark'->'new'->'report' ? 'training' or (v_pr->'dark'->'new'->>'reports')::int < 1
     or v_pr->'dark'->'new'->'grants' <> '[]'::jsonb then
    raise exception '0155 self-assert FAIL: dark, the passage or its report moved: new % / old %',
      v_pr->'dark'->'new' - 'events', v_pr->'dark'->'old' - 'events';
  end if;
  if v_ac.bad <> 0 or v_ac.n < 1 then
    raise exception '0155 self-assert FAIL: world.skills moved for % of % reader(s) while the bonus is off', v_ac.bad, v_ac.n;
  end if;

  -- (b) ON: the first arrival moves the head's finish earlier by exactly 1,000 ÷ rate hours, and the next with it
  v_shift := 1000 * 3600 / (v_pr->>'rate')::numeric;
  select bool_and(abs(extract(epoch from ((b0->>'finishes_at')::timestamptz - (a0->>'finishes_at')::timestamptz)) - v_shift) < 0.001)
    into v_ok
    from jsonb_array_elements(v_pr->'before'->'queue') b0
    join jsonb_array_elements(v_pr->'first'->'queue') a0 on a0->'pos' = b0->'pos';
  if coalesce(not v_ok or jsonb_array_length(v_pr->'before'->'queue') <> 2 or jsonb_array_length(v_pr->'first'->'queue') <> 2
     or (v_pr->'first'->>'nm')::numeric < (v_pr->>'min_nm')::numeric
     or (v_pr->'first'->'report'->'training'->>'credited')::numeric <> 1000
     or v_pr->'first'->'report'->'training'->>'skill' <> 'NAVIGATION' or (v_pr->'first'->'report'->'training'->>'level')::int <> 4
     or v_pr->'first'->'report'->'training'->>'words' <> '+1,000 skill points from sailing to Navigation IV (1,000 / 10,000 today).'
     or v_pr->'first'->'grants'->0->>'sp' <> '1000', true) then
    raise exception '0155 self-assert FAIL: the first arrival did not move the queue by % s, or did not say so: before %, after %, report %',
      v_shift, v_pr->'before'->'queue', v_pr->'first'->'queue', v_pr->'first'->'report'->'training';
  end if;
  -- ten grants fill the day; the eleventh arrival credits nothing and moves nothing
  if coalesce((v_pr->'tenth'->>'today')::numeric <> 10000 or (v_pr->'tenth'->>'cap')::numeric <> 10000
     or (v_pr->'eleventh'->'report'->'training'->>'credited')::numeric <> 0
     or v_pr->'eleventh'->'report'->'training'->>'reason' <> 'DAY_CAP'
     or v_pr->'eleventh'->'report'->'training'->>'words' <> 'The sailing bonus is spent for today (10,000 / 10,000).'
     or v_pr->'eleventh'->'queue' <> v_pr->'queue10' or v_pr->'eleventh'->'grants'->0->>'sp' <> '10000', true) then
    raise exception '0155 self-assert FAIL: the day''s cap did not hold: tenth %, eleventh %', v_pr->'tenth', v_pr->'eleventh'->'report'->'training';
  end if;
  -- a passage under the minimum: no word, no write
  if coalesce(v_pr->'short'->'report' ? 'training' or v_pr->'short'->'queue' <> v_pr->'eleventh'->'queue'
     or v_pr->'short'->'grants' <> v_pr->'eleventh'->'grants' or v_pr->'short'->'sp' <> v_pr->'eleventh'->'sp'
     or v_pr->'short'->'voyage'->>'status' <> 'ARRIVED', true) then
    raise exception '0155 self-assert FAIL: a passage under the minimum moved something: %', v_pr->'short' - 'events';
  end if;
  -- the empty queue is told so; the merchant writes nothing; the Academy serves the day
  if coalesce((v_pr->'empty'->'report'->'training'->>'credited')::numeric <> 0
     or v_pr->'empty'->'report'->'training'->>'words' <> 'No skill in training: the sailing bonus waits for one.'
     or v_pr->'empty'->'grants' <> '[]'::jsonb or v_pr->'empty'->'sp' <> '[]'::jsonb
     or v_pr->'merchant'->>'arrived' <> 'ARRIVED' or coalesce(v_pr->'merchant'->'training', 'null'::jsonb) <> 'null'::jsonb
     or v_pr->'merchant'->'rows_before' <> v_pr->'merchant'->'rows_after'
     or v_pr->'academy' <> '{"cap": 10000, "today": 10000, "min_nm": 300, "per_arrival": 1000}'::jsonb, true) then
    raise exception '0155 self-assert FAIL: the empty queue, the merchant or the Academy: %',
      jsonb_build_object('empty', v_pr->'empty'->'report'->'training', 'merchant', v_pr->'merchant', 'academy', v_pr->'academy');
  end if;
  if exists (select 1 from public.players where auth_uid::text like '00000000-0155-4000-8000-00000000000%'
                                            or company_name = 'Companhia da Prova 0155')
     or exists (select 1 from public.skill_sp_grants) or public.wc_num('skill_sp_per_arrival') <> 0 then
    raise exception '0155 self-assert FAIL: the probe world was not rolled back';
  end if;
  -- no house's progress moved
  if (select count(*) from public.player_skills) <> b.skills_rows
     or (select md5(coalesce(string_agg(format('%s/%s/%s', ps.player_id, ps.skill_id, ps.level), '|' order by ps.player_id, ps.skill_id), '')) from public.player_skills ps) <> b.skills_hash
     or (select md5(coalesce(string_agg(format('%s/%s/%s/%s/%s', q.player_id, q.pos, q.skill_id, q.to_level, q.finishes_at), '|' order by q.player_id, q.pos), '')) from public.skill_queue q) <> b.queue_hash
     or (select md5(coalesce(string_agg(format('%s/%s/%s', x.player_id, x.skill_id, x.sp), '|' order by x.player_id, x.skill_id), '')) from public.skill_sp x) <> b.sp_hash then
    raise exception '0155 self-assert FAIL: a house''s levels, queue or skill points moved';
  end if;

  -- (c) THE RE-CUTS reverse to their pre-images; ACL / volatility / definer / config unmoved
  for d in select * from defs_before_0155 order by fn loop
    v_def := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0155 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0155(v_def, h.new) <> 1 then
        raise exception '0155 self-assert FAIL: hunk % of % is not in the new body exactly once', h.n, d.fn;
      end if;
      v_def := replace(v_def, h.new, h.old);
    end loop;
    if v_def <> d.def then
      raise exception '0155 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef, coalesce(pr.proconfig::text, '') as cfg
      into p from pg_proc pr where pr.oid = d.fn::regprocedure;
    if p.acl <> d.acl or p.vol <> d.vol or p.secdef <> d.secdef or p.cfg <> d.cfg then
      raise exception '0155 self-assert FAIL: % changed its ACL, volatility, definer or config', d.fn;
    end if;
  end loop;
  for d in select * from untouched_before_0155 loop
    if replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '') <> d.def
       or coalesce((select pr.proacl::text from pg_proc pr where pr.oid = d.fn::regprocedure), '') <> d.acl then
      raise exception '0155 self-assert FAIL: % moved — it was to be left untouched', d.fn;
    end if;
  end loop;
  -- server-only: the two functions carry the queue core's ACL; the table is closed to clients; no entry point
  if coalesce((select pr.proacl::text from pg_proc pr where pr.oid = 'public.skill_sp_grant_for(uuid, numeric)'::regprocedure), '')
       is distinct from coalesce((select pr.proacl::text from pg_proc pr where pr.oid = 'public.skill_queue_set_for(uuid, jsonb)'::regprocedure), '')
     or coalesce((select pr.proacl::text from pg_proc pr where pr.oid = 'public.skill_sp_bonus_today(uuid)'::regprocedure), '')
       is distinct from coalesce((select pr.proacl::text from pg_proc pr where pr.oid = 'public.skill_queue_now(uuid)'::regprocedure), '')
     or exists (select 1 from unnest(array['anon', 'authenticated']) r(role)
                 where has_table_privilege(r.role, 'public.skill_sp_grants', 'select,insert,update,delete')
                    or has_function_privilege(r.role, 'public.skill_sp_grant_for(uuid, numeric)', 'execute')
                    or has_function_privilege(r.role, 'public.skill_sp_bonus_today(uuid)', 'execute'))
     or (select count(*) from public.client_rpc_entry_points()) <> b.entry_points then
    raise exception '0155 self-assert FAIL: a client can reach the bonus''s table or functions, an ACL is not its sibling''s, or the entry points moved';
  end if;
  -- D7: still never sold — no entry point names the bonus, skill points or coin
  if exists (select 1 from public.client_rpc_entry_points() e where e.fn::text ~* 'inject|extract|remap|buy_sp|sp_for_coin|sp_grant') then
    raise exception '0155 self-assert FAIL: an entry point sells or grants skill points (D7)';
  end if;

  raise notice '0155 self-assert ok: A PASSAGE TEACHES THE SKILL IN TRAINING (off: skill_sp_per_arrival 0; min % nm, cap % a day). DARK: the probe passage, its report and every write = the old body''s, to the byte; world.skills unmoved for % reader(s). ON (rolled back, 1,000 a passage): a % nm arrival moved Navigation IV and V each % s earlier (1,000 SP at % SP/h) — "%"; ten grants filled the day (10,000); the eleventh arrival credited 0 ("%"); a passage under the minimum wrote nothing; an empty queue was told "%"; a merchant''s arrival wrote no grant / skill point / queue / level row (% before = after); the Academy served %. BODIES: 2 reverse to their pre-images, 9 untouched; 2 new functions and public.skill_sp_grants server-only; no entry point.',
    public.wc_num('skill_sp_arrival_min_nm'), public.wc_num('skill_sp_day_cap'), v_ac.n,
    round((v_pr->'first'->>'nm')::numeric), round(v_shift, 3), v_pr->>'rate',
    v_pr->'first'->'report'->'training'->>'words', v_pr->'eleventh'->'report'->'training'->>'words',
    v_pr->'empty'->'report'->'training'->>'words', v_pr->'merchant'->'rows_after', v_pr->'academy';
end $$;
