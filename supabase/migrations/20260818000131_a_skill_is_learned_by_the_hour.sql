-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0131 — A SKILL IS LEARNED BY THE HOUR  (ninety-two skills in eight groups; a queue that trains
--        while you are away; enrolment is the price, time is the teacher)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY NOW ─────────────────────────────────────────────────────────────────────────────────────
-- docs/SHIPS_AND_SKILLS.md §8, step S9 "Skills I: catalogue + queue" (§5.1 the model, §5.2 the
-- catalogue). Every later step (S11 effects and requirements, S12 the new hulls) reads a skill from
-- this catalogue, and a house must be able to train it — in real time, offline too — first.
--
-- ── WHAT SAYS THE OPPOSITE TODAY, NAMED ─────────────────────────────────────────────────────────
--   * cmd.study_skill (0016:155, cut by 0096 onto public.raise_skill) sells a level INSTANTLY for
--     500 × the next level at an academy. §5.1 retires the instant purchase: a skill is ENROLLED once
--     (tuition skill_study_base_cost × rank, where it is taught) and each level is then TRAINED by
--     time, in a queue.
--   * public.skill_level (0107:169) reads player_skills only, and public.player_skill_bonus
--     (0016:97) reads player_skills BY HAND beside it — two readings of one level. A queued level
--     must count the instant its time passes, with nothing running (no cron), so both now read ONE
--     core, public.skill_level_at(player, code, t).
--   * public.skills.effect admits only the four live effects and pct_per_level must be > 0
--     (0016:57-65): a skill that does nothing yet (S11 gives the 88 their effects) could not exist.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) THE CATALOGUE (data/skills.json, generated from §5.2): 88 new rows of public.skills with
--     effect 'NONE' and pct_per_level 0 — 55 hull skills (eleven lines × Small/Light/Medium/Heavy/
--     Capital) and 33 others (Roles, Seamanship, Navigation, Trade, Gunnery, Command, Shipwright).
--     The effect check is re-made NOT VALID then VALIDATEd to admit 'NONE'; the pct check likewise
--     to admit 0 for exactly the 'NONE' rows (a NONE skill with a percentage would be a number that
--     moves nothing). Under lock_timeout, inside a DO block, retried on a lock wait.
-- (2) SIDE TABLES, all server-only: skill_groups (the eight, in order), skill_profile (group, rank,
--     where it is enrolled — none / any academy / any build yard of a line's countries), skill_prereqs
--     (all rows with choice 0 needed; rows sharing a choice > 0 need ANY one — "Famous Ships needs any
--     T2 role skill III"), skill_queue (player, pos, skill, to_level, starts_at, finishes_at), skill_sp
--     (a house's ENROLMENT and its banked skill points: a row is "enrolled", sp is what training left
--     there — EVE keeps your SP when an entry is removed). No FK to players: a FK would lock the
--     ticks' table (0127's method); a player row is never deleted by the game.
-- (3) TIME PER LEVEL (EVE's curve): skill points to reach level L = rank × round(250 × 2^(2.5(L−1)))
--     (250 / 1,414 / 8,000 / 45,255 / 256,000 per rank), public.skill_sp_for; trained at
--     skill_sp_per_hour (1,800) — one rate for everybody.
-- (4) THE ONE READING, re-cut: public.skill_level(player, code) = public.skill_level_at(player, code,
--     now()), and skill_level_at = greatest(player_skills.level, max(to_level) of her queue rows
--     with finishes_at ≤ t). A pure function of time: a level lands the instant its finish passes.
--     public.player_skill_bonus re-cut to read the level through skill_level (one reading).
-- (5) THE VERBS. Cores (server-only): public.skill_enroll_for, public.skill_queue_set_for (folds
--     finished entries into player_skills, banks the entry in progress, validates the WHOLE new list
--     with public.skill_queue_refusal — the one rule — and rebuilds the chain from now),
--     public.skill_study_for (enrol if needed, append the next level). Doors: cmd.study_skill re-cut
--     onto skill_study_for (the Academy button starts a timer instead of finishing at once); NEW
--     cmd.skill_enroll(code, fleet) and cmd.skill_queue_set(entries) — +2 entry points exactly.
-- (6) THE READ: world.skills() re-cut — groups, ranks, prereqs (met or not), enrolment (cost, where,
--     the docked fleet that can enrol, or the refusal), the queue with finishes, SP, the time the
--     next level takes, the ETA, and for every skill whether its next level can be queued and the
--     verb's own refusal if not (the same function the verb asks). The client renders only.
-- (7) A merchant's card (world.npc_fleet_card) lists the skills it holds and the four it always
--     showed — not 88 zero rows (merchants never train: fixed at founding, §5.1); and a harbour's
--     merchant list (world.port_merchants, 0113) sums a merchant's level over those four skills, not
--     over all 92 (92 skill_level calls per merchant row would cost a busy harbour's tap ~100 ms).
--     Both key on skill_profile.enrol_where = 'none', not on the effect, so S11 does not move them.
--     Enrolment, the queue and the Academy button take one per-house lock (public.skill_lock) first,
--     and tuition is paid only by the call whose insert wrote the enrolment row.
--
-- ── WHAT IT DELIBERATELY DOES NOT DO ────────────────────────────────────────────────────────────
-- No skill effect for the 88 (S11: skill_effects / skill_requirements). No cron: levels are a pure
-- function of time. public.raise_skill is untouched — it stays the core merchants are founded
-- through. Levels already held count as enrolled and are never taken away; the four live skills
-- need no enrolment. SAID PLAINLY, the one change a player feels: the four live skills' next levels
-- are no longer bought at once for 500 × level — they are queued, free, and take time (rank 1:
-- 8 min to I … 5.9 days to V).
--
-- ── LOCKS ───────────────────────────────────────────────────────────────────────────────────────
-- lock_timeout 5 s; no LOCK TABLE, no set role, no begin/commit. db push applies this file in ONE
-- transaction, so every lock taken is held until the file commits. Two matter:
--   * the new tables' FKs take SHARE ROW EXCLUSIVE on public.skills (and ship_lines, skill_groups)
--     from §3 on — that blocks only WRITES to those tables, which no tick makes;
--   * the ALTER of public.skills (§8) takes ACCESS EXCLUSIVE, which blocks every READ of skills —
--     and the ticks read it (player_skill_bonus in fleet speed and endurance) — until the commit. So it
--     is taken as LATE as the file allows: every heavy read (the pre-images, and the comparisons of
--     every house's levels, bonuses and 0107 gates, the merchant cards and harbour lists through the
--     re-cut bodies, §7) runs BEFORE it, and after it come only the catalogue rows, the probe (about a
--     second) and light reads. The ALTER is retried on a lock wait and fails as LOCK CONTENTION, never
--     as a result.
-- Every probe runs on its own founded house and rolls back; a probe call that reaches pay_city
-- (tuition → the city's books) is retried on 55P03/40P01 and fails as LOCK CONTENTION if it
-- persists. Pre-images are taken in this file — never an assumed empty world.
--
-- SUPERSEDES, by hunks sliced from the LIVE bodies (LF-normalised), each asserted to occur exactly
-- once and to reverse to its pre-image, ACLs unchanged: public.skill_level (0107),
-- public.player_skill_bonus (0016), world.skills() (0027), cmd.study_skill (0016 as cut by 0096),
-- public.client_rpc_entry_points() (0123), world.npc_fleet_card (0124), world.port_merchants (0113).
--
-- ROLLBACK (forward migration): reverse the seven hunks; drop the two doors (and their registry
-- rows), the cores, skill_queue, skill_sp, skill_prereqs, skill_profile, skill_groups; delete the 88
-- NONE rows (no player_skills row can reference them: only queue folds write those, and the fold
-- is what a rollback keeps — levels earned stay). The knobs may stay.
-- VERSION: 0131. Applies on prod head 0130.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);   -- 0127's posture: never queue the arrivals sweep for long
end $guard$;

-- ── 0. THE PROBE HELPERS ───────────────────────────────────────────────────────────────────────
-- A call that may reach a lock the live world holds (pay_city: a purse, a city's books). A lock
-- wait or deadlock is not an answer: retried up to 5 times, 0.2 s apart, then LOCK CONTENTION.
create or replace function pg_temp.call_0131(p_sql text)
returns jsonb
language plpgsql
as $$
declare
  v       jsonb;
  v_try   int := 0;
  v_state text;
  v_msg   text;
begin
  loop
    v_try := v_try + 1;
    begin
      execute p_sql into v;
      return v;
    exception when lock_not_available or deadlock_detected then
      get stacked diagnostics v_msg = message_text, v_state = returned_sqlstate;
      if v_try >= 5 then
        raise exception '0131 self-assert FAIL: LOCK CONTENTION, not a result — "%" could not get its locks in 5 tries (%: %). Re-run the push.',
          p_sql, v_state, v_msg;
      end if;
      perform pg_sleep(0.2);
    end;
  end loop;
end $$;

-- What up to 40 merchant fleets' cards say about their company's skills. The card answers only
-- while the merchant switch is on; if it is off here (a local chain), it is switched on inside a
-- sub-block that is rolled back, so the switch is never moved by this file.
create or replace function pg_temp.cards_0131()
returns jsonb
language plpgsql
as $$
declare
  v_out jsonb := '{}'::jsonb;
  f     record;
begin
  begin
    if not public.npc_traders_on() then
      update public.world_config set value = 'true'::jsonb
       where key in ('npc_traders_enabled', 'standing_routes_enabled') and value <> 'true'::jsonb;
    end if;
    for f in select nf.fleet_id from public.npc_fleets nf order by nf.fleet_id limit 40 loop
      v_out := v_out || jsonb_build_object(f.fleet_id::text, world.npc_fleet_card(f.fleet_id)->'skills');
    end loop;
    raise exception 'CARDS_ROLLBACK_0131';
  exception when others then
    if sqlerrm <> 'CARDS_ROLLBACK_0131' then raise; end if;
  end;
  return v_out;
end $$;

-- What the busiest harbours' merchant lists say each merchant's level is (world.port_merchants) — the
-- eight harbours most merchant routes call at. Same switch handling as the cards.
create or replace function pg_temp.harbours_0131()
returns jsonb
language plpgsql
as $$
declare
  v_out jsonb := '{}'::jsonb;
  h     record;
begin
  begin
    if not public.npc_traders_on() then
      update public.world_config set value = 'true'::jsonb
       where key in ('npc_traders_enabled', 'standing_routes_enabled') and value <> 'true'::jsonb;
    end if;
    for h in select s.port_id, count(*) as n from public.standing_route_stops s
               join public.npc_fleets nf on nf.route_id = s.route_id
              group by s.port_id order by count(*) desc, s.port_id limit 8 loop
      v_out := v_out || jsonb_build_object(h.port_id::text,
                 (select coalesce(jsonb_object_agg(m->>'id', m->'level'), '{}'::jsonb)
                    from jsonb_array_elements(world.port_merchants(h.port_id)->'merchants') m));
    end loop;
    raise exception 'HARBOURS_ROLLBACK_0131';
  exception when others then
    if sqlerrm <> 'HARBOURS_ROLLBACK_0131' then raise; end if;
  end;
  return v_out;
end $$;

-- How many cron jobs there are (null where there is no pg_cron, as in a local chain). Dynamic, so the
-- name cron.job is only resolved where it exists.
create or replace function pg_temp.cron_jobs_0131()
returns bigint
language plpgsql
as $$
declare
  v bigint;
begin
  if to_regclass('cron.job') is null then
    return null;
  end if;
  execute 'select count(*) from cron.job' into v;
  return v;
end $$;

-- ── 1. THE PRE-IMAGES ──────────────────────────────────────────────────────────────────────────
create temp table defs_before_0131 as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl
  from unnest(array['public.skill_level(uuid, text)',
                    'public.player_skill_bonus(uuid, text)',
                    'world.skills()',
                    'cmd.study_skill(text, uuid)',
                    'public.client_rpc_entry_points()',
                    'world.npc_fleet_card(uuid)',
                    'world.port_merchants(uuid)']) f(fn);

create temp table before_0131 as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from public.skills) as skills,
       (select md5(string_agg(to_jsonb(s)::text, '|' order by s.code)) from public.skills s) as skills_hash,
       (select md5(coalesce(string_agg(to_jsonb(ps)::text, '|' order by ps.player_id, ps.skill_id), '')) from public.player_skills ps) as player_skills_hash,
       (select count(*) from public.player_skills) as player_skills,
       pg_temp.cron_jobs_0131() as cron_jobs,
       (select count(*) from public.players) as players;

-- every house's level in the four live skills, through THE reading
create temp table levels_before_0131 as
select p.id as player_id, p.is_npc, sk.code, public.skill_level(p.id, sk.code) as level
  from public.players p cross join public.skills sk;

-- every house's four company bonuses
create temp table bonus_before_0131 as
select p.id as player_id, e.effect, public.player_skill_bonus(p.id, e.effect) as bonus
  from public.players p
 cross join unnest(array['ENDURANCE', 'SPEED', 'TRADE_CAP', 'SPREAD']) e(effect);

-- 0107's gates for every house: the earned caps, and the leg-length gate around each rung of
-- NAVIGATION's ladder (900 · 1,800 · 3,600 · 7,200 · 14,400 miles), destination-free
create temp table gates_before_0131 as
select p.id as player_id, public.earned_caps(p.id) as caps,
       jsonb_build_array(public.passage_gate(p.id, 899, null), public.passage_gate(p.id, 901, null),
                         public.passage_gate(p.id, 1801, null), public.passage_gate(p.id, 3601, null),
                         public.passage_gate(p.id, 7201, null), public.passage_gate(p.id, 14401, null)) as legs
  from public.players p;

create temp table cards_before_0131 as
select pg_temp.cards_0131() as j;

create temp table harbours_before_0131 as
select pg_temp.harbours_0131() as j;

-- the skills that existed before this file (the four live ones), by id
create temp table live_skills_0131 as
select s.id, s.code from public.skills s;

-- ── 2. THE KNOBS ───────────────────────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('skill_sp_per_hour', to_jsonb(1800),
   '0131: skill points a house trains per real hour — ONE rate for everybody (no attributes, no implants), the '
   'one number that tunes the whole grind. Level L of a skill needs rank × round(250 × 2^(2.5 × (L − 1))) points '
   'in all (public.skill_sp_for): rank 1 takes 8 min to I and 5.9 days to V.'),
  ('skill_queue_max', to_jsonb(10),
   '0131: the most levels a house may have in its training queue at once (each the next level of its skill).')
on conflict (key) do nothing;

-- ── 3. THE SIDE TABLES ─────────────────────────────────────────────────────────────────────────
create table if not exists public.skill_groups (
  code text primary key check (code ~ '^[A-Z]+$'),
  name text not null,
  ord  int  not null unique check (ord >= 1)
);
comment on table public.skill_groups is
  '0131: the eight skill groups, in the order the Skills screen shows them (data/skills.json). Server-only; '
  'served by world.skills().';
alter table public.skill_groups enable row level security;
revoke all on table public.skill_groups from public, anon, authenticated;

insert into public.skill_groups (code, name, ord) values
  ('HULLS', 'Hulls', 1),
  ('ROLES', 'Roles', 2),
  ('SEAMANSHIP', 'Seamanship', 3),
  ('NAVIGATION', 'Navigation', 4),
  ('TRADE', 'Trade', 5),
  ('GUNNERY', 'Gunnery', 6),
  ('COMMAND', 'Command', 7),
  ('SHIPWRIGHT', 'Shipwright', 8)
on conflict (code) do nothing;

create table if not exists public.skill_profile (
  skill_id    uuid primary key references public.skills(id) on delete cascade,
  group_code  text not null references public.skill_groups(code),
  rank        int  not null check (rank between 1 and 16),
  enrol_where text not null check (enrol_where in ('none', 'academy', 'line_yard')),
  line_code   text references public.ship_lines(code),
  ord         int  not null check (ord >= 1),
  check ((enrol_where = 'line_yard') = (line_code is not null))
);
comment on table public.skill_profile is
  '0131: every skill''s group, rank (time multiplier, public.skill_sp_for) and where it is ENROLLED: none = counts '
  'as enrolled (the four live skills); academy = any port with an academy; line_yard = any build yard in a country '
  'of line_code''s builder_nations (public.skill_taught_at). Authored in data/skills.json; the world guard holds it '
  'to the file. Server-only.';
alter table public.skill_profile enable row level security;
revoke all on table public.skill_profile from public, anon, authenticated;

-- the 92 profiles (data/skills.json), kept in one temp table: inserted HERE for the four live skills
-- (the re-cut reads below key on them), and again after the catalogue rows exist (§8).
create temp table profile_rows_0131 (code text, grp text, rank int, enrol text, line text, ord int);
insert into profile_rows_0131 (code, grp, rank, enrol, line, ord) values
    ('PRT_SMALL', 'HULLS', 1, 'line_yard', 'PRT', 1),
    ('PRT_LIGHT', 'HULLS', 2, 'line_yard', 'PRT', 2),
    ('PRT_MEDIUM', 'HULLS', 4, 'line_yard', 'PRT', 3),
    ('PRT_HEAVY', 'HULLS', 6, 'line_yard', 'PRT', 4),
    ('PRT_CAPITAL', 'HULLS', 10, 'line_yard', 'PRT', 5),
    ('ESP_SMALL', 'HULLS', 1, 'line_yard', 'ESP', 6),
    ('ESP_LIGHT', 'HULLS', 2, 'line_yard', 'ESP', 7),
    ('ESP_MEDIUM', 'HULLS', 4, 'line_yard', 'ESP', 8),
    ('ESP_HEAVY', 'HULLS', 6, 'line_yard', 'ESP', 9),
    ('ESP_CAPITAL', 'HULLS', 10, 'line_yard', 'ESP', 10),
    ('NLD_SMALL', 'HULLS', 1, 'line_yard', 'NLD', 11),
    ('NLD_LIGHT', 'HULLS', 2, 'line_yard', 'NLD', 12),
    ('NLD_MEDIUM', 'HULLS', 4, 'line_yard', 'NLD', 13),
    ('NLD_HEAVY', 'HULLS', 6, 'line_yard', 'NLD', 14),
    ('NLD_CAPITAL', 'HULLS', 10, 'line_yard', 'NLD', 15),
    ('ENG_SMALL', 'HULLS', 1, 'line_yard', 'ENG', 16),
    ('ENG_LIGHT', 'HULLS', 2, 'line_yard', 'ENG', 17),
    ('ENG_MEDIUM', 'HULLS', 4, 'line_yard', 'ENG', 18),
    ('ENG_HEAVY', 'HULLS', 6, 'line_yard', 'ENG', 19),
    ('ENG_CAPITAL', 'HULLS', 10, 'line_yard', 'ENG', 20),
    ('FRA_SMALL', 'HULLS', 1, 'line_yard', 'FRA', 21),
    ('FRA_LIGHT', 'HULLS', 2, 'line_yard', 'FRA', 22),
    ('FRA_MEDIUM', 'HULLS', 4, 'line_yard', 'FRA', 23),
    ('FRA_HEAVY', 'HULLS', 6, 'line_yard', 'FRA', 24),
    ('FRA_CAPITAL', 'HULLS', 10, 'line_yard', 'FRA', 25),
    ('ITA_SMALL', 'HULLS', 1, 'line_yard', 'ITA', 26),
    ('ITA_LIGHT', 'HULLS', 2, 'line_yard', 'ITA', 27),
    ('ITA_MEDIUM', 'HULLS', 4, 'line_yard', 'ITA', 28),
    ('ITA_HEAVY', 'HULLS', 6, 'line_yard', 'ITA', 29),
    ('ITA_CAPITAL', 'HULLS', 10, 'line_yard', 'ITA', 30),
    ('OTT_SMALL', 'HULLS', 1, 'line_yard', 'OTT', 31),
    ('OTT_LIGHT', 'HULLS', 2, 'line_yard', 'OTT', 32),
    ('OTT_MEDIUM', 'HULLS', 4, 'line_yard', 'OTT', 33),
    ('OTT_HEAVY', 'HULLS', 6, 'line_yard', 'OTT', 34),
    ('OTT_CAPITAL', 'HULLS', 10, 'line_yard', 'OTT', 35),
    ('IND_SMALL', 'HULLS', 1, 'line_yard', 'IND', 36),
    ('IND_LIGHT', 'HULLS', 2, 'line_yard', 'IND', 37),
    ('IND_MEDIUM', 'HULLS', 4, 'line_yard', 'IND', 38),
    ('IND_HEAVY', 'HULLS', 6, 'line_yard', 'IND', 39),
    ('IND_CAPITAL', 'HULLS', 10, 'line_yard', 'IND', 40),
    ('CHN_SMALL', 'HULLS', 1, 'line_yard', 'CHN', 41),
    ('CHN_LIGHT', 'HULLS', 2, 'line_yard', 'CHN', 42),
    ('CHN_MEDIUM', 'HULLS', 4, 'line_yard', 'CHN', 43),
    ('CHN_HEAVY', 'HULLS', 6, 'line_yard', 'CHN', 44),
    ('CHN_CAPITAL', 'HULLS', 10, 'line_yard', 'CHN', 45),
    ('JPN_SMALL', 'HULLS', 1, 'line_yard', 'JPN', 46),
    ('JPN_LIGHT', 'HULLS', 2, 'line_yard', 'JPN', 47),
    ('JPN_MEDIUM', 'HULLS', 4, 'line_yard', 'JPN', 48),
    ('JPN_HEAVY', 'HULLS', 6, 'line_yard', 'JPN', 49),
    ('JPN_CAPITAL', 'HULLS', 10, 'line_yard', 'JPN', 50),
    ('KOR_SMALL', 'HULLS', 1, 'line_yard', 'KOR', 51),
    ('KOR_LIGHT', 'HULLS', 2, 'line_yard', 'KOR', 52),
    ('KOR_MEDIUM', 'HULLS', 4, 'line_yard', 'KOR', 53),
    ('KOR_HEAVY', 'HULLS', 6, 'line_yard', 'KOR', 54),
    ('KOR_CAPITAL', 'HULLS', 10, 'line_yard', 'KOR', 55),
    ('MERCHANT_SHIPS', 'ROLES', 4, 'academy', null, 1),
    ('SHIPS_OF_WAR', 'ROLES', 4, 'academy', null, 2),
    ('EXPLORERS', 'ROLES', 4, 'academy', null, 3),
    ('ESCORT_SUPPORT', 'ROLES', 4, 'academy', null, 4),
    ('ARMED_MERCHANT', 'ROLES', 5, 'academy', null, 5),
    ('PRIVATEERS', 'ROLES', 5, 'academy', null, 6),
    ('SURVEY_SHIPS', 'ROLES', 5, 'academy', null, 7),
    ('CONVOY_ESCORTS', 'ROLES', 5, 'academy', null, 8),
    ('FAMOUS_SHIPS', 'ROLES', 12, 'academy', null, 9),
    ('SEAMANSHIP', 'SEAMANSHIP', 1, 'none', null, 1),
    ('HULL_UPKEEP', 'SEAMANSHIP', 2, 'academy', null, 2),
    ('DAMAGE_CONTROL', 'SEAMANSHIP', 3, 'academy', null, 3),
    ('DECK_MANAGEMENT', 'SEAMANSHIP', 3, 'academy', null, 4),
    ('HANDLING_SPEC', 'SEAMANSHIP', 5, 'academy', null, 5),
    ('NAVIGATION', 'NAVIGATION', 1, 'none', null, 1),
    ('RIGGING', 'NAVIGATION', 2, 'academy', null, 2),
    ('LOOKOUTS', 'NAVIGATION', 2, 'academy', null, 3),
    ('INSTRUMENTS', 'NAVIGATION', 3, 'academy', null, 4),
    ('RIGGING_SPEC', 'NAVIGATION', 5, 'academy', null, 5),
    ('INSTRUMENT_SPEC', 'NAVIGATION', 5, 'academy', null, 6),
    ('ACCOUNTING', 'TRADE', 1, 'none', null, 1),
    ('HAGGLING', 'TRADE', 1, 'none', null, 2),
    ('CARGO_STOWAGE', 'TRADE', 3, 'academy', null, 3),
    ('STOWAGE_SPEC', 'TRADE', 5, 'academy', null, 4),
    ('GUNNERY', 'GUNNERY', 1, 'academy', null, 1),
    ('GUN_LAYING', 'GUNNERY', 2, 'academy', null, 2),
    ('LONG_GUNS', 'GUNNERY', 3, 'academy', null, 3),
    ('SHORT_GUNS', 'GUNNERY', 3, 'academy', null, 4),
    ('BOARDING', 'GUNNERY', 2, 'academy', null, 5),
    ('GUN_DRILL', 'GUNNERY', 3, 'academy', null, 6),
    ('GUNNERY_SPEC', 'GUNNERY', 5, 'academy', null, 7),
    ('COMMAND', 'COMMAND', 3, 'academy', null, 1),
    ('FLEET_COMMAND', 'COMMAND', 8, 'academy', null, 2),
    ('SHIPWRIGHT', 'SHIPWRIGHT', 2, 'academy', null, 1),
    ('REFITTING', 'SHIPWRIGHT', 4, 'academy', null, 2),
    ('AUGMENTATION', 'SHIPWRIGHT', 5, 'academy', null, 3),
    ('SHIPWRIGHT_SPEC', 'SHIPWRIGHT', 5, 'academy', null, 4);

insert into public.skill_profile (skill_id, group_code, rank, enrol_where, line_code, ord)
select s.id, v.grp, v.rank, v.enrol, v.line, v.ord
  from profile_rows_0131 v join public.skills s on s.code = v.code
on conflict (skill_id) do nothing;

create table if not exists public.skill_prereqs (
  skill_id       uuid not null references public.skills(id) on delete cascade,
  needs_skill_id uuid not null references public.skills(id) on delete cascade,
  level          int  not null check (level between 1 and 5),
  choice         int  not null default 0 check (choice >= 0),
  primary key (skill_id, needs_skill_id),
  check (skill_id <> needs_skill_id)
);
comment on table public.skill_prereqs is
  '0131: what a skill needs before a level of it may START training. Rows with choice 0 are all needed; rows '
  'sharing a choice > 0 need ANY one of them. Checked against the queue''s own chain by public.skill_queue_refusal '
  '(the one rule). Authored in data/skills.json. Server-only.';
alter table public.skill_prereqs enable row level security;
revoke all on table public.skill_prereqs from public, anon, authenticated;

-- No FK to players on the two per-house tables: a FK takes SHARE ROW EXCLUSIVE on players, which the
-- ticks write (0127's method). A player row is never deleted by the game.
create table if not exists public.skill_queue (
  player_id   uuid        not null,
  pos         int         not null check (pos between 1 and 100),
  skill_id    uuid        not null references public.skills(id) on delete cascade,
  to_level    int         not null check (to_level between 1 and 20),
  starts_at   timestamptz not null,
  finishes_at timestamptz not null,
  primary key (player_id, pos),
  unique (player_id, skill_id, to_level),
  check (finishes_at > starts_at)
);
create index if not exists skill_queue_player_skill on public.skill_queue (player_id, skill_id, finishes_at);
comment on table public.skill_queue is
  '0131: a house''s training queue — each row the next level of its skill, chained (starts_at = the previous '
  'row''s finishes_at). Read by public.skill_level_at (a level counts the instant finishes_at passes); written only '
  'by public.skill_queue_set_for, which folds finished rows into player_skills. Merchants never have a row. Server-only.';
alter table public.skill_queue enable row level security;
revoke all on table public.skill_queue from public, anon, authenticated;

create table if not exists public.skill_sp (
  player_id uuid    not null,
  skill_id  uuid    not null references public.skills(id) on delete cascade,
  sp        numeric not null default 0 check (sp >= 0),
  primary key (player_id, skill_id)
);
comment on table public.skill_sp is
  '0131: a row = the house is ENROLLED in the skill (tuition paid); sp = the skill points it holds in it, kept when '
  'a queue entry is removed part-way (EVE keeps your SP). Written only by public.skill_enroll_for and '
  'public.skill_queue_set_for. Merchants never have a row. Server-only.';
alter table public.skill_sp enable row level security;
revoke all on table public.skill_sp from public, anon, authenticated;

-- ── 4. THE NEW FUNCTIONS ───────────────────────────────────────────────────────────────────────
create or replace function public.skill_sp_for(p_rank int, p_level int)
returns numeric
language sql
immutable
set search_path = public, pg_temp
as $$
  -- 0131: skill points to REACH level p_level from nothing (EVE's curve, docs/SHIPS_AND_SKILLS.md §5.1):
  -- rank × round(250 × 2^(2.5 × (L − 1))) — 250 / 1,414 / 8,000 / 45,255 / 256,000 per rank.
  select case when coalesce(p_level, 0) <= 0 then 0::numeric
              else p_rank * round(250 * power(2::numeric, 2.5 * (p_level - 1))) end
$$;
comment on function public.skill_sp_for(int, int) is
  '0131: THE curve — skill points to reach a level (from 0), per rank. Read by the queue core and world.skills.';

create or replace function public.skill_level_at(p_player uuid, p_code text, p_at timestamptz)
returns int
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0131: a house's level in one skill AT A MOMENT — the level it has learned (player_skills, 0 where
  -- there is no row, 0016's ruling) or the highest queued level whose finish has passed by p_at,
  -- whichever is greater. A pure function of time: nothing runs for a level to land.
  select greatest(
           coalesce((select ps.level from public.player_skills ps
                       join public.skills sk on sk.id = ps.skill_id
                      where ps.player_id = p_player and sk.code = p_code), 0),
           coalesce((select max(q.to_level) from public.skill_queue q
                       join public.skills sk on sk.id = q.skill_id
                      where q.player_id = p_player and sk.code = p_code and q.finishes_at <= p_at), 0))
$$;
comment on function public.skill_level_at(uuid, text, timestamptz) is
  '0131: THE core of a skill level — learned, or queued and finished by p_at. public.skill_level is this at now(). '
  'Server-only.';

create or replace function public.skill_is_enrolled(p_player uuid, p_skill uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0131: enrolled = needs no enrolment (the four live skills), or tuition paid (a skill_sp row), or any
  -- level already held (a level a house has counts as enrolled, §5.1).
  select exists (select 1 from public.skill_profile pr where pr.skill_id = p_skill and pr.enrol_where = 'none')
      or exists (select 1 from public.skill_sp x where x.player_id = p_player and x.skill_id = p_skill)
      or exists (select 1 from public.player_skills ps where ps.player_id = p_player and ps.skill_id = p_skill)
$$;

create or replace function public.skill_enrol_cost(p_skill uuid)
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0131: the tuition — skill_study_base_cost × rank (§5.1), the one place it is computed.
  select public.wc_int('skill_study_base_cost')::bigint * pr.rank
    from public.skill_profile pr where pr.skill_id = p_skill
$$;

create or replace function public.skill_taught_place(p_skill uuid)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0131: where a skill is enrolled, in words — "any academy", "any build yard in Portugal" — or null
  -- when it needs no enrolment.
  select case pr.enrol_where
           when 'academy' then 'any academy'
           when 'line_yard' then 'any build yard in ' ||
             (select string_agg(n.name, ', ' order by array_position(sl.builder_nations, n.code))
                from public.ship_lines sl join public.nations n on n.code = any(sl.builder_nations)
               where sl.code = pr.line_code)
         end
    from public.skill_profile pr where pr.skill_id = p_skill
$$;

create or replace function public.skill_taught_at(p_skill uuid, p_port uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0131: THE ONE PLACE RULE for enrolment — null when the skill can be enrolled at this port (or needs
  -- no enrolment), else the refusal (cmd.refusal) with its sentence: an academy skill at a port with no
  -- academy (E_NO_ACADEMY), a line's hull skill anywhere but a build yard in that line's countries
  -- (E_NOT_TAUGHT_HERE).
  select case
    when pr.enrol_where = 'none' then null
    when pr.enrol_where = 'academy' then
      case when exists (select 1 from public.port_buildings b where b.port_id = p_port and b.kind = 'academy') then null
           else cmd.refusal('E_NO_ACADEMY',
                  format('%s is taught at %s, and %s has none.', s.name, public.skill_taught_place(s.id),
                         coalesce(p.name, 'this place'))) end
    else
      case when exists (select 1 from public.port_buildings b where b.port_id = p_port and b.kind = 'building_yard')
                and n.code = any(sl.builder_nations) then null
           else cmd.refusal('E_NOT_TAUGHT_HERE',
                  format('%s is taught at %s, and %s', s.name, public.skill_taught_place(s.id),
                         case when not exists (select 1 from public.port_buildings b
                                                where b.port_id = p_port and b.kind = 'building_yard')
                                then format('%s has no build yard.', coalesce(p.name, 'this place'))
                              when n.code is null then format('%s belongs to no country.', coalesce(p.name, 'this place'))
                              else format('%s is in %s.', p.name, n.name) end)) end
  end
  from public.skills s
  join public.skill_profile pr on pr.skill_id = s.id
  left join public.ship_lines sl on sl.code = pr.line_code
  left join public.ports p on p.id = p_port
  left join public.nations n on n.id = p.nation_id
 where s.id = p_skill
$$;
comment on function public.skill_taught_at(uuid, uuid) is
  '0131: THE ONE PLACE RULE for enrolment: null when this port teaches the skill, else the refusal with its '
  'sentence. Read by public.skill_enrol_refusal (so by the enrol verb and world.skills), nothing else.';

create or replace function public.skill_enrol_refusal(p_player uuid, p_skill uuid, p_fleet uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0131: may THIS fleet's company enrol in this skill where the fleet is docked, now? Null when it may;
-- else the refusal. Read by public.skill_enroll_for (the verb) and public.skill_answers (the screen).
declare
  f      record;
  v_ref  jsonb;
  v_cost bigint;
  v_have bigint;
begin
  select x.id, x.player_id, x.port_id into f from public.fleets x where x.id = p_fleet;
  if f.id is null or f.player_id is distinct from p_player then
    return cmd.refusal('E_NOT_YOUR_FLEET', 'That fleet is not yours.');
  end if;
  if f.port_id is null then
    return cmd.refusal('E_AT_SEA', 'That fleet is at sea. You enrol in port.');
  end if;
  v_ref := public.skill_taught_at(p_skill, f.port_id);
  if v_ref is not null then
    return v_ref;
  end if;
  v_cost := public.skill_enrol_cost(p_skill);
  select ducats into v_have from public.players where id = p_player;
  if coalesce(v_have, 0) < v_cost then
    return cmd.refusal('E_NOT_ENOUGH_DUCATS',
             format('Enrolling in %s costs %s 🪙 and you have %s 🪙.',
                    (select name from public.skills where id = p_skill), v_cost, coalesce(v_have, 0)),
             cmd.figures(coalesce(v_have, 0), v_cost, 'ducats'));
  end if;
  return null;
end $$;

create or replace function public.skill_queue_now(p_player uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0131: a house's queue as it stands — the entries not yet finished, in order.
  select coalesce(jsonb_agg(jsonb_build_object(
           'pos', q.pos, 'code', sk.code, 'name', sk.name, 'level', q.to_level,
           'starts_at', q.starts_at, 'finishes_at', q.finishes_at) order by q.pos), '[]'::jsonb)
    from public.skill_queue q join public.skills sk on sk.id = q.skill_id
   where q.player_id = p_player and q.finishes_at > now()
$$;

create or replace function public.skill_queue_refusal(p_player uuid, p_entries jsonb, p_assume uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0131: THE ONE QUEUE RULE. Is p_entries — [{code, level}, …] in order — a legal queue for this house,
-- starting from the levels it has NOW? Null when it is; else the refusal (cmd.refusal + 'at', the
-- 1-based entry). Each entry must be: a skill that exists; enrolled (p_assume: one skill to treat as
-- enrolled — "would it queue once enrolled?"); the NEXT level of its skill at that point in the chain;
-- not past the top level; with every prerequisite met BY THE TIME IT STARTS, i.e. by the levels held now
-- and the entries before it. At most skill_queue_max entries. Read by skill_queue_set_for (the verb),
-- skill_study_for and skill_answers (the screen) — the screen's answer IS the verb's.
declare
  v_maxq int := public.wc_int('skill_queue_max');
  v_max  int := public.wc_int('skill_max_level');
  v_n    int;
  v_sim  jsonb := '{}'::jsonb;
  e      jsonb;
  i      int := 0;
  s      record;
  v_have int;
  v_lvl  int;
  p      record;
  g      record;
begin
  if p_player is null then
    return cmd.refusal('E_NOT_SIGNED_IN', 'Nobody is signed in.');
  end if;
  if p_entries is null or jsonb_typeof(p_entries) <> 'array' then
    return cmd.refusal('E_SKILL_ORDER', 'A queue is a list of skills, each with the level to train.');
  end if;
  v_n := jsonb_array_length(p_entries);
  if v_n > v_maxq then
    return cmd.refusal('E_SKILL_QUEUE_FULL',
             format('The queue holds %s levels, and this asks for %s.', v_maxq, v_n),
             cmd.figures(v_maxq, v_n, 'levels')) || jsonb_build_object('at', v_maxq + 1);
  end if;
  for e in select value from jsonb_array_elements(p_entries) loop
    i := i + 1;
    select sk.id, sk.code, sk.name into s from public.skills sk
      join public.skill_profile pr on pr.skill_id = sk.id
     where sk.code = upper(btrim(coalesce(e->>'code', '')));
    if s.id is null then
      return cmd.refusal('E_NO_SUCH_SKILL', format('Nothing is taught under the name "%s".', coalesce(e->>'code', '')))
             || jsonb_build_object('at', i);
    end if;
    if s.id is distinct from p_assume and not public.skill_is_enrolled(p_player, s.id) then
      return cmd.refusal('E_NOT_ENROLLED',
               format('Enrol in %s first — it is taught at %s.', s.name, public.skill_taught_place(s.id)))
             || jsonb_build_object('at', i, 'skill', s.code);
    end if;
    v_have := coalesce((v_sim->>s.code)::int, public.skill_level(p_player, s.code));
    if v_have >= v_max then
      return cmd.refusal('E_SKILL_MAXED', format('%s is already at %s, which is as far as it is taught.', s.name, v_max))
             || jsonb_build_object('at', i, 'skill', s.code);
    end if;
    v_lvl := case when e->>'level' ~ '^[0-9]+$' then (e->>'level')::int end;
    if v_lvl is distinct from v_have + 1 then
      return cmd.refusal('E_SKILL_ORDER',
               format('%s will be at level %s by then, so the next level to train is %s, not %s.',
                      s.name, v_have, v_have + 1, coalesce(e->>'level', 'none')))
             || jsonb_build_object('at', i, 'skill', s.code);
    end if;
    -- every prerequisite with choice 0
    for p in select n.code, n.name, q.level from public.skill_prereqs q join public.skills n on n.id = q.needs_skill_id
              where q.skill_id = s.id and q.choice = 0 order by n.code loop
      if coalesce((v_sim->>p.code)::int, public.skill_level(p_player, p.code)) < p.level then
        return cmd.refusal('E_SKILL_PREREQ',
                 format('%s needs %s at level %s, and you will have level %s when it starts.',
                        s.name, p.name, p.level, coalesce((v_sim->>p.code)::int, public.skill_level(p_player, p.code))),
                 cmd.figures(coalesce((v_sim->>p.code)::int, public.skill_level(p_player, p.code)), p.level, 'level'))
               || jsonb_build_object('at', i, 'skill', s.code, 'needs', p.code);
      end if;
    end loop;
    -- each choice group: any one row
    for g in select q.choice, q.level,
                    string_agg(n.name, ' or ' order by n.code) as names,
                    max(coalesce((v_sim->>n.code)::int, public.skill_level(p_player, n.code))) as best
               from public.skill_prereqs q join public.skills n on n.id = q.needs_skill_id
              where q.skill_id = s.id and q.choice > 0
              group by q.choice, q.level order by q.choice loop
      if g.best < g.level then
        return cmd.refusal('E_SKILL_PREREQ',
                 format('%s needs one of %s at level %s, and the best you will have when it starts is level %s.',
                        s.name, g.names, g.level, g.best),
                 cmd.figures(g.best, g.level, 'level'))
               || jsonb_build_object('at', i, 'skill', s.code);
      end if;
    end loop;
    v_sim := v_sim || jsonb_build_object(s.code, v_lvl);
  end loop;
  return null;
end $$;
comment on function public.skill_queue_refusal(uuid, jsonb, uuid) is
  '0131: THE ONE QUEUE RULE — null when the list is a legal queue from the levels held now, else the refusal '
  '(+ at, the entry). The verb and the screen both ask it.';

create or replace function public.skill_refused(p_refusal jsonb)
returns jsonb
language sql
immutable
as $$
  -- 0131: a refusal (cmd.refusal) in the doors' answer shape — what cmd.study_skill has always returned.
  select jsonb_build_object('ok', false, 'error_code', p_refusal->>'code', 'error_message', p_refusal->>'sentence',
                            'fixes', '[]'::jsonb)
         || (p_refusal - array['code', 'sentence'])
$$;

create or replace function public.skill_lock(p_player uuid)
returns void
language sql
volatile
set search_path = public, pg_temp
as $$
  -- 0131: ONE HOUSE'S SKILL WRITES, ONE AT A TIME — a transaction-scoped advisory lock on the house
  -- (re-entrant), taken FIRST by every core that reads the queue or enrolment before it writes. No
  -- table row is locked, so nothing the ticks hold is waited on.
  select pg_advisory_xact_lock(hashtextextended('skill_queue:' || p_player::text, 131))
$$;

create or replace function public.skill_enroll_for(p_player uuid, p_code text, p_fleet uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0131: CORE of cmd.skill_enroll — enrol a house in a skill where its fleet is docked: the place rule,
-- the tuition (skill_study_base_cost × rank) to that harbour through pay_city, and the skill_sp row.
-- Merchants never enrol (their skills are fixed at founding, §5.1). Server-only.
declare
  s      record;
  v_ref  jsonb;
  v_port record;
  v_cost bigint;
  v_rows int;
begin
  if exists (select 1 from public.players x where x.id = p_player and x.is_npc) then
    raise exception 'E_MERCHANT_FIXED: a merchant company''s skills are fixed at founding; it does not enrol or train'
      using errcode = 'P0001';
  end if;
  perform public.skill_lock(p_player);   -- one house's enrolments and queue edits, one at a time
  select sk.id, sk.code, sk.name into s from public.skills sk
    join public.skill_profile pr on pr.skill_id = sk.id
   where sk.code = upper(btrim(coalesce(p_code, '')));
  if s.id is null then
    return public.skill_refused(cmd.refusal('E_NO_SUCH_SKILL', format('Nothing is taught under the name "%s".', coalesce(p_code, ''))));
  end if;
  if public.skill_is_enrolled(p_player, s.id) then
    return public.skill_refused(cmd.refusal('E_ALREADY_ENROLLED', format('You are already enrolled in %s.', s.name)));
  end if;
  v_ref := public.skill_enrol_refusal(p_player, s.id, p_fleet);
  if v_ref is not null then
    return public.skill_refused(v_ref);
  end if;
  select p.id, p.code, p.name into v_port from public.fleets f join public.ports p on p.id = f.port_id where f.id = p_fleet;
  v_cost := public.skill_enrol_cost(s.id);
  insert into public.skill_sp (player_id, skill_id, sp) values (p_player, s.id, 0)
  on conflict (player_id, skill_id) do nothing;
  -- THE ROW IS THE RECEIPT: tuition is paid only by the call that wrote it. A second tap that got here
  -- (its check ran before the first committed) inserts nothing and pays nothing.
  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    return public.skill_refused(cmd.refusal('E_ALREADY_ENROLLED', format('You are already enrolled in %s.', s.name)));
  end if;
  perform public.pay_city(p_player, v_port.id, 'TUITION', v_cost,
    public.emit_event(p_player, 'ENROLLED', jsonb_build_object(
      'skill', s.name, 'code', s.code, 'port', v_port.code, 'cost', v_cost)));
  return jsonb_build_object('ok', true, 'enrolled', true, 'skill', s.code, 'name', s.name,
                            'paid', v_cost, 'port', v_port.code);
end $$;

create or replace function public.skill_queue_set_for(p_player uuid, p_entries jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0131: CORE of cmd.skill_queue_set — THE ONE WRITER of skill_queue. In order:
--   1. FOLD: entries whose finish has passed become player_skills levels (and their skill points), and go.
--   2. VALIDATE the whole new list with public.skill_queue_refusal (refused → nothing else moves).
--   3. BANK the entry in progress: the points it has trained so far (its finish minus the time left).
--   4. REBUILD from now: each entry starts when the one before finishes and takes
--      (points to its level − points held) / skill_sp_per_hour.
-- Merchants never train. Server-only.
declare
  v_t     timestamptz := now();
  v_rate  numeric := public.wc_num('skill_sp_per_hour');
  v_ref   jsonb;
  e       jsonb;
  i       int := 0;
  s       record;
  v_lvl   int;
  v_end   numeric;
  v_start numeric;
  v_fin   timestamptz;
begin
  if exists (select 1 from public.players x where x.id = p_player and x.is_npc) then
    raise exception 'E_MERCHANT_FIXED: a merchant company''s skills are fixed at founding; it does not enrol or train'
      using errcode = 'P0001';
  end if;
  if p_player is null then
    return public.skill_refused(cmd.refusal('E_NOT_SIGNED_IN', 'Nobody is signed in.'));
  end if;
  perform public.skill_lock(p_player);

  -- 1. FOLD
  insert into public.player_skills (player_id, skill_id, level, studied_at)
  select q.player_id, q.skill_id, max(q.to_level), max(q.finishes_at)
    from public.skill_queue q
   where q.player_id = p_player and q.finishes_at <= v_t
   group by q.player_id, q.skill_id
  on conflict (player_id, skill_id) do update
     set level = excluded.level, studied_at = excluded.studied_at
   where excluded.level > public.player_skills.level;
  insert into public.skill_sp (player_id, skill_id, sp)
  select q.player_id, q.skill_id, public.skill_sp_for(pr.rank, max(q.to_level))
    from public.skill_queue q join public.skill_profile pr on pr.skill_id = q.skill_id
   where q.player_id = p_player and q.finishes_at <= v_t
   group by q.player_id, q.skill_id, pr.rank
  on conflict (player_id, skill_id) do update set sp = greatest(public.skill_sp.sp, excluded.sp);
  delete from public.skill_queue where player_id = p_player and finishes_at <= v_t;

  -- 2. VALIDATE
  v_ref := public.skill_queue_refusal(p_player, coalesce(p_entries, '[]'::jsonb));
  if v_ref is not null then
    return public.skill_refused(v_ref) || jsonb_build_object('queue', public.skill_queue_now(p_player));
  end if;

  -- 3. BANK the entry in progress (points to its level less the time it still had to run)
  insert into public.skill_sp (player_id, skill_id, sp)
  select q.player_id, q.skill_id,
         greatest(0, public.skill_sp_for(pr.rank, q.to_level)
                     - extract(epoch from (q.finishes_at - v_t)) * v_rate / 3600)
    from public.skill_queue q join public.skill_profile pr on pr.skill_id = q.skill_id
   where q.player_id = p_player and q.starts_at <= v_t
  on conflict (player_id, skill_id) do update set sp = greatest(public.skill_sp.sp, excluded.sp);

  -- 4. REBUILD
  delete from public.skill_queue where player_id = p_player;
  for e in select value from jsonb_array_elements(coalesce(p_entries, '[]'::jsonb)) loop
    i := i + 1;
    select sk.id, pr.rank into s from public.skills sk join public.skill_profile pr on pr.skill_id = sk.id
     where sk.code = upper(btrim(e->>'code'));
    v_lvl := (e->>'level')::int;
    v_end := public.skill_sp_for(s.rank, v_lvl);
    v_start := greatest(public.skill_sp_for(s.rank, v_lvl - 1),
                        least(coalesce((select x.sp from public.skill_sp x
                                         where x.player_id = p_player and x.skill_id = s.id), 0), v_end));
    v_fin := v_t + make_interval(secs => ((v_end - v_start) * 3600 / v_rate)::double precision);
    insert into public.skill_queue (player_id, pos, skill_id, to_level, starts_at, finishes_at)
    values (p_player, i, s.id, v_lvl, v_t, v_fin);
    v_t := v_fin;
  end loop;
  return jsonb_build_object('ok', true, 'queue', public.skill_queue_now(p_player),
                            'eta', case when i > 0 then v_t end);
end $$;

create or replace function public.skill_study_for(p_player uuid, p_code text, p_fleet uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0131: CORE of the Academy's one button (cmd.study_skill): enrol where the fleet is docked if the house is
-- not enrolled yet, then add the skill's NEXT level to the end of the queue. The whole new queue is asked
-- of the one rule BEFORE any tuition is taken, so a level that could not be queued costs nothing.
declare
  s       record;
  v_q     jsonb;
  v_next  int;
  v_list  jsonb;
  v_ref   jsonb;
  v_res   jsonb;
  v_paid  bigint := 0;
begin
  if exists (select 1 from public.players x where x.id = p_player and x.is_npc) then
    raise exception 'E_MERCHANT_FIXED: a merchant company''s skills are fixed at founding; it does not enrol or train'
      using errcode = 'P0001';
  end if;
  perform public.skill_lock(p_player);   -- BEFORE the queue is read: the list built below is the one written
  select sk.id, sk.code, sk.name into s from public.skills sk
    join public.skill_profile pr on pr.skill_id = sk.id
   where sk.code = upper(btrim(coalesce(p_code, '')));
  if s.id is null then
    return public.skill_refused(cmd.refusal('E_NO_SUCH_SKILL', format('Nothing is taught under the name "%s".', coalesce(p_code, ''))));
  end if;
  v_q := public.skill_queue_now(p_player);
  v_next := greatest(public.skill_level(p_player, s.code),
                     coalesce((select max((x->>'level')::int) from jsonb_array_elements(v_q) x where x->>'code' = s.code), 0)) + 1;
  v_list := coalesce((select jsonb_agg(jsonb_build_object('code', x->>'code', 'level', (x->>'level')::int)
                                       order by (x->>'pos')::int)
                        from jsonb_array_elements(v_q) x), '[]'::jsonb)
            || jsonb_build_array(jsonb_build_object('code', s.code, 'level', v_next));
  v_ref := public.skill_queue_refusal(p_player, v_list, s.id);
  if v_ref is not null then
    return public.skill_refused(v_ref);
  end if;
  if not public.skill_is_enrolled(p_player, s.id) then
    v_res := public.skill_enroll_for(p_player, s.code, p_fleet);
    if not coalesce((v_res->>'ok')::boolean, false) then
      return v_res;
    end if;
    v_paid := (v_res->>'paid')::bigint;
  end if;
  v_res := public.skill_queue_set_for(p_player, v_list);
  if not coalesce((v_res->>'ok')::boolean, false) then
    return v_res;
  end if;
  return v_res || jsonb_build_object('skill', s.code, 'name', s.name, 'level', v_next, 'paid', v_paid);
end $$;

create or replace function public.skill_answers(p_player uuid, p_skill uuid, p_queue jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0131: everything the Skills screen prints about ONE skill for this house, answered by the rules the
-- verbs use (skill_level, skill_queue_refusal, skill_enrol_refusal) so the screen re-derives nothing.
declare
  s        record;
  v_max    int := public.wc_int('skill_max_level');
  v_rate   numeric := public.wc_num('skill_sp_per_hour');
  v_level  int;
  v_qto    int;
  v_next   int;
  v_enr    boolean;
  v_sp     numeric := 0;
  v_end    numeric;
  v_start  numeric;
  v_ref    jsonb;
  v_fleet  uuid;
  v_eref   jsonb;
  v_r      jsonb;
  f        record;
begin
  select sk.id, sk.code, pr.rank, pr.group_code, pr.enrol_where into s
    from public.skills sk join public.skill_profile pr on pr.skill_id = sk.id where sk.id = p_skill;
  v_level := case when p_player is null then 0 else public.skill_level(p_player, s.code) end;
  v_qto := (select max((x->>'level')::int) from jsonb_array_elements(coalesce(p_queue, '[]'::jsonb)) x
             where x->>'code' = s.code);
  v_next := greatest(v_level, coalesce(v_qto, 0)) + 1;
  if v_next > v_max then v_next := null; end if;
  v_enr := s.enrol_where = 'none' or (p_player is not null and public.skill_is_enrolled(p_player, s.id));
  if p_player is not null then
    v_sp := coalesce((select x.sp from public.skill_sp x where x.player_id = p_player and x.skill_id = s.id), 0);
  end if;
  if v_next is not null then
    v_end := public.skill_sp_for(s.rank, v_next);
    v_start := greatest(public.skill_sp_for(s.rank, v_next - 1), least(v_sp, v_end));
    v_ref := public.skill_queue_refusal(p_player,
               coalesce((select jsonb_agg(jsonb_build_object('code', x->>'code', 'level', (x->>'level')::int)
                                          order by (x->>'pos')::int)
                           from jsonb_array_elements(coalesce(p_queue, '[]'::jsonb)) x), '[]'::jsonb)
               || jsonb_build_array(jsonb_build_object('code', s.code, 'level', v_next)),
               case when v_enr then null else s.id end);
  end if;
  if not v_enr and p_player is not null then
    for f in select x.id from public.fleets x where x.player_id = p_player and x.port_id is not null order by x.name, x.id loop
      v_r := public.skill_enrol_refusal(p_player, s.id, f.id);
      if v_r is null then v_fleet := f.id; exit; end if;
      if v_eref is null then v_eref := v_r; end if;
    end loop;
    if v_fleet is not null then v_eref := null; end if;
  end if;
  return jsonb_build_object(
    'level', v_level,
    'group', s.group_code,
    'rank', s.rank,
    'prereqs', (select coalesce(jsonb_agg(jsonb_build_object(
                         'code', n.code, 'name', n.name, 'level', q.level, 'choice', q.choice,
                         'met', case when p_player is null then false
                                     else public.skill_level(p_player, n.code) >= q.level end)
                       order by q.choice, n.code), '[]'::jsonb)
                  from public.skill_prereqs q join public.skills n on n.id = q.needs_skill_id
                 where q.skill_id = s.id),
    'enrolled', v_enr,
    'enrol_cost', case when v_enr then null else public.skill_enrol_cost(s.id) end,
    'enrol_where', case when v_enr then null else 'Taught at ' || public.skill_taught_place(s.id) || '.' end,
    'enrol_fleet', v_fleet,
    'enrol_refusal', v_eref,
    'can_enrol', not v_enr and v_fleet is not null,
    'queued_to', v_qto,
    'next_level', v_next,
    'next_cost', case when v_next is null then null when v_enr then 0 else public.skill_enrol_cost(s.id) end,
    'sp', v_sp,
    'sp_next', v_end,
    'train_seconds', case when v_next is null then null else round((v_end - v_start) * 3600 / v_rate) end,
    'can_queue', v_enr and v_next is not null and v_ref is null,
    'queue_refusal', v_ref);
end $$;

-- THE DOORS (+2 entry points). Neither takes a player id.
create or replace function cmd.skill_enroll(p_code text, p_fleet uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0131: enrol your company in a skill where this fleet is docked (any academy, or a build yard of the
-- line's countries for a hull skill), for the tuition. Levels then train anywhere, by time.
declare
  v_player uuid := public.current_player_id();
begin
  if v_player is null then
    return public.skill_refused(cmd.refusal('E_NOT_SIGNED_IN', 'Nobody is signed in, so there is no captain to teach.'));
  end if;
  return public.skill_enroll_for(v_player, p_code, p_fleet);
end $$;

create or replace function cmd.skill_queue_set(p_entries jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0131: set your whole training queue — [{code, level}, …] in order. Refused whole, with the server's
-- sentence, if any entry may not train where it stands; the entry in progress keeps what it trained.
declare
  v_player uuid := public.current_player_id();
begin
  if v_player is null then
    return public.skill_refused(cmd.refusal('E_NOT_SIGNED_IN', 'Nobody is signed in, so there is no captain to teach.'));
  end if;
  return public.skill_queue_set_for(v_player, p_entries);
end $$;

revoke all on function public.skill_sp_for(int, int) from public, anon, authenticated;
revoke all on function public.skill_level_at(uuid, text, timestamptz) from public, anon, authenticated;
revoke all on function public.skill_is_enrolled(uuid, uuid) from public, anon, authenticated;
revoke all on function public.skill_enrol_cost(uuid) from public, anon, authenticated;
revoke all on function public.skill_taught_place(uuid) from public, anon, authenticated;
revoke all on function public.skill_taught_at(uuid, uuid) from public, anon, authenticated;
revoke all on function public.skill_enrol_refusal(uuid, uuid, uuid) from public, anon, authenticated;
revoke all on function public.skill_queue_now(uuid) from public, anon, authenticated;
revoke all on function public.skill_queue_refusal(uuid, jsonb, uuid) from public, anon, authenticated;
revoke all on function public.skill_refused(jsonb) from public, anon, authenticated;
revoke all on function public.skill_lock(uuid) from public, anon, authenticated;
revoke all on function public.skill_enroll_for(uuid, text, uuid) from public, anon, authenticated;
revoke all on function public.skill_queue_set_for(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.skill_study_for(uuid, text, uuid) from public, anon, authenticated;
revoke all on function public.skill_answers(uuid, uuid, jsonb) from public, anon, authenticated;
revoke all on function cmd.skill_enroll(text, uuid) from public, anon;
revoke all on function cmd.skill_queue_set(jsonb) from public, anon;
grant execute on function cmd.skill_enroll(text, uuid) to authenticated;
grant execute on function cmd.skill_queue_set(jsonb) to authenticated;

-- ── 5. THE HUNKS (old → new), sliced from the live bodies ──────────────────────────────────────
create temp table hunks_0131 (fn text, n int, old text, new text);
insert into hunks_0131 values
-- public.skill_level: the queue term, through the one core
('public.skill_level(uuid, text)', 1,
$h$  select coalesce((select ps.level from public.player_skills ps
                     join public.skills sk on sk.id = ps.skill_id
                    where ps.player_id = p_player and sk.code = p_code), 0)
$h$,
$h$  -- 0131: and a QUEUED level the instant its finish passes — public.skill_level_at at now(), the one
  -- core. A level lands whether the captain is signed in or not, with nothing running.
  select public.skill_level_at(p_player, p_code, now())
$h$),
-- public.player_skill_bonus: the level is skill_level's, never player_skills read by hand
('public.player_skill_bonus(uuid, text)', 1,
$h$  select coalesce(sum(s.pct_per_level * ps.level), 0) / 100.0
    from public.player_skills ps
    join public.skills s on s.id = ps.skill_id
   where ps.player_id = p_player
     and s.effect = upper(p_effect);
$h$,
$h$  -- 0131: the LEVEL is public.skill_level's (a queued level counts the instant it finishes), never
  -- player_skills joined by hand. A skill with no level adds 0, as the absent row did.
  select coalesce(sum(s.pct_per_level * public.skill_level(p_player, s.code)), 0) / 100.0
    from public.skills s
   where s.effect = upper(p_effect);
$h$),
-- world.skills: the queue and every answer the screen prints
('world.skills()', 1,
$h$  v_read   constant text[] := array['ENDURANCE', 'SPREAD', 'TRADE_CAP', 'SPEED'];
begin
$h$,
$h$  v_read   constant text[] := array['ENDURANCE', 'SPREAD', 'TRADE_CAP', 'SPEED'];
  -- 0131: the queue as it stands (unfinished entries, in order) — the chain every answer is asked against.
  v_queue  jsonb := public.skill_queue_now(v_player);
begin
$h$),
('world.skills()', 2,
$h$    'skills', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'code', s.code, 'name', s.name, 'effect', s.effect,
               'pct_per_level', s.pct_per_level, 'blurb', s.blurb,
               'level', coalesce(ps.level, 0),
               'next_cost', case when coalesce(ps.level, 0) >= public.wc_int('skill_max_level')
                                 then null
                                 else public.wc_int('skill_study_base_cost') * (coalesce(ps.level, 0) + 1) end,
               'takes_effect', (s.effect = any(v_read))
             ) order by s.code), '[]'::jsonb)
        from public.skills s
        left join public.player_skills ps on ps.skill_id = s.id and ps.player_id = v_player));
$h$,
$h$    -- 0131: THE QUEUE — what is training, in order, each with its finish — and what it runs by.
    'queue', v_queue,
    'queue_max', public.wc_int('skill_queue_max'),
    'sp_per_hour', public.wc_num('skill_sp_per_hour'),
    'eta', (select max((x->>'finishes_at')::timestamptz) from jsonb_array_elements(v_queue) x),
    'now', now(),
    'groups', (select coalesce(jsonb_agg(jsonb_build_object('code', g.code, 'name', g.name) order by g.ord), '[]'::jsonb)
                 from public.skill_groups g),
    -- 0131: each skill's level (public.skill_level), next cost, group, rank, prereqs, enrolment and queue
    -- answers come from public.skill_answers — the rules the verbs use, asked once per skill.
    'skills', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'code', s.code, 'name', s.name, 'effect', s.effect,
               'pct_per_level', s.pct_per_level, 'blurb', s.blurb,
               'takes_effect', (s.effect = any(v_read))
             ) || public.skill_answers(v_player, s.id, v_queue)
             order by g.ord, pr.ord, s.code), '[]'::jsonb)
        from public.skills s
        join public.skill_profile pr on pr.skill_id = s.id
        join public.skill_groups g on g.code = pr.group_code));
$h$),
-- cmd.study_skill: enrol (if needed) and queue the next level; the instant purchase is retired
('cmd.study_skill(text, uuid)', 1,
$h$  -- TEACHING HAPPENS SOMEWHERE. A captain at sea is not in a lecture room, and a port without an
  -- academy has nobody to teach. `has_academy` finally means something.
  if v_fleet.port_id is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_AT_SEA',
      'error_message', 'She is at sea. A trade is learned ashore.',
      'fixes', jsonb_build_array('(SAIL to a port with an academy, then study)'));
  end if;

  -- 0067: the row, not the column - see cmd.do_repair above.
  select p.code, p.name,
         exists (select 1 from public.port_buildings b
                  where b.port_id = p.id and b.kind = 'academy') as has_academy
    into v_port
    from public.ports p where p.id = v_fleet.port_id;
  if not v_port.has_academy then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_ACADEMY',
      'error_message', format('%s keeps no academy.', v_port.name),
      'fixes', (select coalesce(jsonb_agg(format('(sail to %s — %s)', p.code, p.name) order by p.code), '[]'::jsonb)
                  from (select p2.code, p2.name from public.ports p2
                         join public.port_buildings b2 on b2.port_id = p2.id and b2.kind = 'academy'
                        order by p2.code limit 6) p));
  end if;

  -- 0096: the level, the tuition and the record are public.raise_skill's. The academy gate
  -- above — taught ashore, where a school stands — stays the door's.
  return public.raise_skill(v_player, v_code, v_port.code);
$h$,
$h$  -- 0131: ENROL where the skill is taught (only if not yet enrolled — that is the one time a place and
  -- tuition matter), then QUEUE its next level: the button starts a timer instead of finishing at once.
  -- The instant purchase is retired from this door; public.raise_skill stays the merchants' core.
  return public.skill_study_for(v_player, v_code, p_fleet);
$h$),
-- the registry: +2 entry points
('public.client_rpc_entry_points()', 1,
$h$      ('cmd',         'study_skill',         'text, uuid'),
$h$,
$h$      ('cmd',         'study_skill',         'text, uuid'),
      -- 0131: enrol in a skill where it is taught, and set the training queue (docs/SHIPS_AND_SKILLS.md §5.1).
      ('cmd',         'skill_enroll',        'text, uuid'),
      ('cmd',         'skill_queue_set',     'jsonb'),
$h$),
-- world.npc_fleet_card: the skills a merchant holds, not 88 zero rows
('world.npc_fleet_card(uuid)', 1,
$h$                 from public.skills sk
                 left join public.player_skills ps on ps.skill_id = sk.id and ps.player_id = p.id));
$h$,
$h$                 from public.skills sk
                 left join public.player_skills ps on ps.skill_id = sk.id and ps.player_id = p.id
                -- 0131: the skills it HOLDS and the four every company has always been shown (the ones that
                -- need no enrolment) — never the catalogue skills a merchant does not train (fixed at
                -- founding, docs/SHIPS_AND_SKILLS.md §5.1). Keyed on the profile, not the effect, so it
                -- holds when S11 gives the catalogue its effects.
                where ps.level is not null
                   or exists (select 1 from public.skill_profile pr where pr.skill_id = sk.id and pr.enrol_where = 'none')));
$h$),
-- world.port_merchants: a merchant's level is summed over the four company skills, not all 92
('world.port_merchants(uuid)', 1,
$h$                     'level', (select coalesce(sum(public.skill_level(p.id, sk.code)), 0)::int
                                 from public.skills sk),
$h$,
$h$                     'level', (select coalesce(sum(public.skill_level(p.id, sk.code)), 0)::int
                                 from public.skills sk
                                 -- 0131: the four company skills (those needing no enrolment) — not the
                                 -- catalogue a merchant never trains; one skill_level call per skill
                                 -- per row, so a busy harbour's tap stays four calls a merchant.
                                 join public.skill_profile pr on pr.skill_id = sk.id and pr.enrol_where = 'none'),
$h$);

-- ── 6. THE RE-CUTS ─────────────────────────────────────────────────────────────────────────────
create or replace function pg_temp.recut_0131(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := replace(pg_get_functiondef(p_fn::regprocedure), E'\r', '');
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0131 where fn = p_fn order by n loop
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0131 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0131(fn) from defs_before_0131 order by fn;

-- ── 7. THE HEAVY COMPARISONS, BEFORE public.skills IS LOCKED ───────────────────────────────────
-- Every house's levels, bonuses and 0107 gates, the merchant cards and the busiest harbours' merchant
-- levels, read through the RE-CUT bodies against the pre-images — run here, before the ALTER below
-- takes public.skills ACCESS EXCLUSIVE for the rest of the file. The re-cuts read only the four live
-- skills' rows and profiles at this point; the catalogue rows cannot move any of these figures (a NONE
-- skill reads level 0 for every house, asserted at the end).
create temp table early_0131 (lv int, bn int, gt int, cards int, harbours int);
do $$
declare
  v_bad int;
  v_lv  int;
  v_bn  int;
  v_gt  int;
  v_cards int;
  v_now jsonb;
begin
  select count(*) into v_lv from levels_before_0131;
  select count(*) into v_bad from levels_before_0131 b where public.skill_level(b.player_id, b.code) is distinct from b.level;
  if v_bad <> 0 then
    raise exception '0131 self-assert FAIL: % house × skill level(s) moved', v_bad;
  end if;
  if (select players from before_0131) > 0 and not exists (select 1 from levels_before_0131 where level > 0) then
    raise exception '0131 self-assert FAIL: % houses and not one holds a level — the level comparison proves nothing', (select players from before_0131);
  end if;

  select count(*) into v_bn from bonus_before_0131;
  select count(*) into v_bad from bonus_before_0131 b where public.player_skill_bonus(b.player_id, b.effect) is distinct from b.bonus;
  if v_bad <> 0 then
    raise exception '0131 self-assert FAIL: % house × effect bonus(es) moved', v_bad;
  end if;

  select count(*) into v_gt from gates_before_0131;
  select count(*) into v_bad from gates_before_0131 g
   where public.earned_caps(g.player_id) is distinct from g.caps
      or jsonb_build_array(public.passage_gate(g.player_id, 899, null), public.passage_gate(g.player_id, 901, null),
                           public.passage_gate(g.player_id, 1801, null), public.passage_gate(g.player_id, 3601, null),
                           public.passage_gate(g.player_id, 7201, null), public.passage_gate(g.player_id, 14401, null)) is distinct from g.legs;
  if v_bad <> 0 then
    raise exception '0131 self-assert FAIL: % house(s) whose 0107 gates moved', v_bad;
  end if;

  v_now := pg_temp.cards_0131();
  if v_now is distinct from (select j from cards_before_0131) then
    raise exception '0131 self-assert FAIL: a merchant card''s skills moved: % → %', left((select j from cards_before_0131)::text, 400), left(v_now::text, 400);
  end if;
  v_cards := (select count(*) from jsonb_object_keys(v_now));

  v_now := pg_temp.harbours_0131();
  if v_now is distinct from (select j from harbours_before_0131) then
    raise exception '0131 self-assert FAIL: a harbour''s merchant levels moved: % → %', left((select j from harbours_before_0131)::text, 400), left(v_now::text, 400);
  end if;
  if (select count(*) from public.npc_fleets) > 0
     and not exists (select 1 from jsonb_each(v_now) h, jsonb_each(h.value) m where (m.value)::int > 0) then
    raise exception '0131 self-assert FAIL: merchants sail but no harbour list shows a merchant level — the comparison proves nothing';
  end if;

  insert into early_0131 values (v_lv, v_bn, v_gt, v_cards,
    (select count(*) from jsonb_each(v_now) h, jsonb_each(h.value) m));
end $$;

-- ── 8. THE CATALOGUE: the checks re-made, then the 88 rows (data/skills.json) ──────────────────
-- From here to the end of the file public.skills is held ACCESS EXCLUSIVE (the ALTER), until the
-- file commits. Everything heavy has already run above; what follows is the rows, the probe (about
-- a second) and light catalogue reads.
do $alter$
declare
  v_eff   text;
  v_pct   text;
  v_try   int := 0;
  v_state text;
  v_msg   text;
begin
  perform set_config('lock_timeout', '5s', true);
  select k.conname into v_eff from pg_constraint k
   where k.conrelid = 'public.skills'::regclass and k.contype = 'c'
     and pg_get_constraintdef(k.oid) like '%effect%' and pg_get_constraintdef(k.oid) not like '%pct_per_level%';
  select k.conname into v_pct from pg_constraint k
   where k.conrelid = 'public.skills'::regclass and k.contype = 'c'
     and pg_get_constraintdef(k.oid) like '%pct_per_level%' and pg_get_constraintdef(k.oid) not like '%effect%';
  if v_eff is null or v_pct is null then
    raise exception '0131 self-assert FAIL: the effect (%) or pct_per_level (%) check of public.skills is not where 0016 put it', v_eff, v_pct;
  end if;
  loop
    v_try := v_try + 1;
    begin
      execute format(
        'alter table public.skills drop constraint %I, drop constraint %I, '
        'add constraint skills_effect_known check (effect in (''ENDURANCE'', ''SPEED'', ''TRADE_CAP'', ''SPREAD'', ''NONE'')) not valid, '
        'add constraint skills_pct_per_level_sane check ((effect = ''NONE'' and pct_per_level = 0) '
        'or (effect <> ''NONE'' and pct_per_level > 0 and pct_per_level <= 10)) not valid',
        v_eff, v_pct);
      alter table public.skills validate constraint skills_effect_known;
      alter table public.skills validate constraint skills_pct_per_level_sane;
      exit;
    exception when lock_not_available or deadlock_detected then
      get stacked diagnostics v_msg = message_text, v_state = returned_sqlstate;
      if v_try >= 5 then
        raise exception '0131 self-assert FAIL: LOCK CONTENTION, not a result — public.skills could not be altered in 5 tries (%: %). Re-run the push.', v_state, v_msg;
      end if;
      perform pg_sleep(0.5);
    end;
  end loop;
end $alter$;

comment on column public.skills.effect is
  'The ONE thing this skill changes. Exactly one, for the same reason an officer has one specialty: '
  'a skill that moved several numbers would need several rules to read it. 0131: NONE = nothing yet '
  '(the 88 catalogue skills of docs/SHIPS_AND_SKILLS.md §5.2; S11 gives them their effects through '
  'skill_effects), always with pct_per_level 0.';

insert into public.skills (code, name, effect, pct_per_level, blurb) values
  ('PRT_SMALL', 'Portuguese Small Hulls', 'NONE', 0, 'How Portuguese small ships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('PRT_LIGHT', 'Portuguese Light Hulls', 'NONE', 0, 'How Portuguese light ships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('PRT_MEDIUM', 'Portuguese Medium Hulls', 'NONE', 0, 'How Portuguese medium ships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('PRT_HEAVY', 'Portuguese Heavy Hulls', 'NONE', 0, 'How Portuguese heavy ships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('PRT_CAPITAL', 'Portuguese Capital Hulls', 'NONE', 0, 'How Portuguese capital ships and flagships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('ESP_SMALL', 'Spanish Small Hulls', 'NONE', 0, 'How Spanish small ships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('ESP_LIGHT', 'Spanish Light Hulls', 'NONE', 0, 'How Spanish light ships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('ESP_MEDIUM', 'Spanish Medium Hulls', 'NONE', 0, 'How Spanish medium ships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('ESP_HEAVY', 'Spanish Heavy Hulls', 'NONE', 0, 'How Spanish heavy ships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('ESP_CAPITAL', 'Spanish Capital Hulls', 'NONE', 0, 'How Spanish capital ships and flagships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('NLD_SMALL', 'Dutch Small Hulls', 'NONE', 0, 'How Dutch small ships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('NLD_LIGHT', 'Dutch Light Hulls', 'NONE', 0, 'How Dutch light ships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('NLD_MEDIUM', 'Dutch Medium Hulls', 'NONE', 0, 'How Dutch medium ships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('NLD_HEAVY', 'Dutch Heavy Hulls', 'NONE', 0, 'How Dutch heavy ships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('NLD_CAPITAL', 'Dutch Capital Hulls', 'NONE', 0, 'How Dutch capital ships and flagships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('ENG_SMALL', 'English Small Hulls', 'NONE', 0, 'How English small ships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('ENG_LIGHT', 'English Light Hulls', 'NONE', 0, 'How English light ships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('ENG_MEDIUM', 'English Medium Hulls', 'NONE', 0, 'How English medium ships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('ENG_HEAVY', 'English Heavy Hulls', 'NONE', 0, 'How English heavy ships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('ENG_CAPITAL', 'English Capital Hulls', 'NONE', 0, 'How English capital ships and flagships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('FRA_SMALL', 'French Small Hulls', 'NONE', 0, 'How French small ships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('FRA_LIGHT', 'French Light Hulls', 'NONE', 0, 'How French light ships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('FRA_MEDIUM', 'French Medium Hulls', 'NONE', 0, 'How French medium ships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('FRA_HEAVY', 'French Heavy Hulls', 'NONE', 0, 'How French heavy ships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('FRA_CAPITAL', 'French Capital Hulls', 'NONE', 0, 'How French capital ships and flagships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('ITA_SMALL', 'Italian Small Hulls', 'NONE', 0, 'How Italian small ships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('ITA_LIGHT', 'Italian Light Hulls', 'NONE', 0, 'How Italian light ships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('ITA_MEDIUM', 'Italian Medium Hulls', 'NONE', 0, 'How Italian medium ships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('ITA_HEAVY', 'Italian Heavy Hulls', 'NONE', 0, 'How Italian heavy ships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('ITA_CAPITAL', 'Italian Capital Hulls', 'NONE', 0, 'How Italian capital ships and flagships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('OTT_SMALL', 'Ottoman Small Hulls', 'NONE', 0, 'How Ottoman small ships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('OTT_LIGHT', 'Ottoman Light Hulls', 'NONE', 0, 'How Ottoman light ships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('OTT_MEDIUM', 'Ottoman Medium Hulls', 'NONE', 0, 'How Ottoman medium ships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('OTT_HEAVY', 'Ottoman Heavy Hulls', 'NONE', 0, 'How Ottoman heavy ships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('OTT_CAPITAL', 'Ottoman Capital Hulls', 'NONE', 0, 'How Ottoman capital ships and flagships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('IND_SMALL', 'Indian Small Hulls', 'NONE', 0, 'How Indian small ships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('IND_LIGHT', 'Indian Light Hulls', 'NONE', 0, 'How Indian light ships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('IND_MEDIUM', 'Indian Medium Hulls', 'NONE', 0, 'How Indian medium ships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('IND_HEAVY', 'Indian Heavy Hulls', 'NONE', 0, 'How Indian heavy ships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('IND_CAPITAL', 'Indian Capital Hulls', 'NONE', 0, 'How Indian capital ships and flagships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('CHN_SMALL', 'Chinese Small Hulls', 'NONE', 0, 'How Chinese small ships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('CHN_LIGHT', 'Chinese Light Hulls', 'NONE', 0, 'How Chinese light ships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('CHN_MEDIUM', 'Chinese Medium Hulls', 'NONE', 0, 'How Chinese medium ships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('CHN_HEAVY', 'Chinese Heavy Hulls', 'NONE', 0, 'How Chinese heavy ships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('CHN_CAPITAL', 'Chinese Capital Hulls', 'NONE', 0, 'How Chinese capital ships and flagships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('JPN_SMALL', 'Japanese Small Hulls', 'NONE', 0, 'How Japanese small ships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('JPN_LIGHT', 'Japanese Light Hulls', 'NONE', 0, 'How Japanese light ships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('JPN_MEDIUM', 'Japanese Medium Hulls', 'NONE', 0, 'How Japanese medium ships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('JPN_HEAVY', 'Japanese Heavy Hulls', 'NONE', 0, 'How Japanese heavy ships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('JPN_CAPITAL', 'Japanese Capital Hulls', 'NONE', 0, 'How Japanese capital ships and flagships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('KOR_SMALL', 'Korean Small Hulls', 'NONE', 0, 'How Korean small ships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('KOR_LIGHT', 'Korean Light Hulls', 'NONE', 0, 'How Korean light ships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('KOR_MEDIUM', 'Korean Medium Hulls', 'NONE', 0, 'How Korean medium ships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('KOR_HEAVY', 'Korean Heavy Hulls', 'NONE', 0, 'How Korean heavy ships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('KOR_CAPITAL', 'Korean Capital Hulls', 'NONE', 0, 'How Korean capital ships and flagships are sailed and kept. Taught only at the build yards of the countries that build them.'),
  ('MERCHANT_SHIPS', 'Merchant Ships', 'NONE', 0, 'Running big trading ships: packing, loading and keeping a large cargo moving.'),
  ('SHIPS_OF_WAR', 'Ships of War', 'NONE', 0, 'Fighting big warships: the gun decks, the drills and the crews they need.'),
  ('EXPLORERS', 'Exploration Vessels', 'NONE', 0, 'Long voyages into unknown water: lookouts, charts and ships built to range far.'),
  ('ESCORT_SUPPORT', 'Escort & Support', 'NONE', 0, 'Ships that guard and serve a fleet: tough, steady and kept in good repair.'),
  ('ARMED_MERCHANT', 'Armed Merchantmen', 'NONE', 0, 'Improved trading ships that carry guns as well as cargo.'),
  ('PRIVATEERS', 'Privateers', 'NONE', 0, 'Improved warships built to hunt and hit hard.'),
  ('SURVEY_SHIPS', 'Survey Ships', 'NONE', 0, 'Improved exploration ships that see farther and range wider.'),
  ('CONVOY_ESCORTS', 'Convoy Escorts', 'NONE', 0, 'Improved escorts that keep a convoy together and safe.'),
  ('FAMOUS_SHIPS', 'Famous Ships', 'NONE', 0, 'The great named ships of each country. Only the most experienced captains are trusted with one.'),
  ('HULL_UPKEEP', 'Hull Upkeep', 'NONE', 0, 'Keeping planking, seams and frames sound so every ship lasts longer.'),
  ('DAMAGE_CONTROL', 'Damage Control', 'NONE', 0, 'Plugging holes and shoring up under fire, so damage does less harm.'),
  ('DECK_MANAGEMENT', 'Deck Management', 'NONE', 0, 'Fitting more gear on a deck without getting in the crew''s way.'),
  ('HANDLING_SPEC', 'Ship Handling Specialisation', 'NONE', 0, 'Mastery of improved rudders, anchors and capstans.'),
  ('RIGGING', 'Rigging', 'NONE', 0, 'Setting and trimming sails so a ship turns and answers quickly.'),
  ('LOOKOUTS', 'Lookouts', 'NONE', 0, 'Training sharp eyes aloft to spot sails and coasts sooner.'),
  ('INSTRUMENTS', 'Instruments', 'NONE', 0, 'Compass, charts and the astrolabe, used well.'),
  ('RIGGING_SPEC', 'Rigging Specialisation', 'NONE', 0, 'Mastery of improved sails and rigging.'),
  ('INSTRUMENT_SPEC', 'Instrument Specialisation', 'NONE', 0, 'Mastery of improved navigation instruments.'),
  ('CARGO_STOWAGE', 'Cargo Stowage', 'NONE', 0, 'Packing cargo tightly so every ship carries more.'),
  ('STOWAGE_SPEC', 'Stowage Specialisation', 'NONE', 0, 'Mastery of improved cargo fittings.'),
  ('GUNNERY', 'Gunnery', 'NONE', 0, 'Loading, aiming and firing a ship''s guns.'),
  ('GUN_LAYING', 'Gun Laying', 'NONE', 0, 'Aiming each gun with care so more shots hit.'),
  ('LONG_GUNS', 'Long Guns', 'NONE', 0, 'Long-barrelled chase guns that reach farther.'),
  ('SHORT_GUNS', 'Short Guns', 'NONE', 0, 'Short, heavy guns that hit hard up close.'),
  ('BOARDING', 'Boarding', 'NONE', 0, 'Grappling, crossing over and fighting on another ship''s deck.'),
  ('GUN_DRILL', 'Gun Drill', 'NONE', 0, 'Drilled gun crews, so the guns need fewer hands.'),
  ('GUNNERY_SPEC', 'Gunnery Specialisation', 'NONE', 0, 'Mastery of improved guns, boarding gear and magazines.'),
  ('COMMAND', 'Command', 'NONE', 0, 'Leading officers and running more ships at once.'),
  ('FLEET_COMMAND', 'Fleet Command', 'NONE', 0, 'Leading a whole fleet from a flagship.'),
  ('SHIPWRIGHT', 'Shipwright', 'NONE', 0, 'How ships are built, so a build yard needs less paid work.'),
  ('REFITTING', 'Refitting', 'NONE', 0, 'Lasting changes to a ship''s build.'),
  ('AUGMENTATION', 'Augmentation', 'NONE', 0, 'Adding chosen extras to fitted gear.'),
  ('SHIPWRIGHT_SPEC', 'Shipwright Specialisation', 'NONE', 0, 'Mastery of improved hull fittings.')
on conflict (code) do nothing;

-- the remaining 88 profiles, and the prerequisites (both need the new rows)
insert into public.skill_profile (skill_id, group_code, rank, enrol_where, line_code, ord)
select s.id, v.grp, v.rank, v.enrol, v.line, v.ord
  from profile_rows_0131 v join public.skills s on s.code = v.code
on conflict (skill_id) do nothing;

insert into public.skill_prereqs (skill_id, needs_skill_id, level, choice)
select s.id, n.id, v.level, v.choice
  from (values
    ('PRT_LIGHT', 'PRT_SMALL', 3, 0),
    ('PRT_MEDIUM', 'PRT_LIGHT', 3, 0),
    ('PRT_HEAVY', 'PRT_MEDIUM', 4, 0),
    ('PRT_CAPITAL', 'PRT_HEAVY', 4, 0),
    ('PRT_CAPITAL', 'COMMAND', 3, 0),
    ('ESP_LIGHT', 'ESP_SMALL', 3, 0),
    ('ESP_MEDIUM', 'ESP_LIGHT', 3, 0),
    ('ESP_HEAVY', 'ESP_MEDIUM', 4, 0),
    ('ESP_CAPITAL', 'ESP_HEAVY', 4, 0),
    ('ESP_CAPITAL', 'COMMAND', 3, 0),
    ('NLD_LIGHT', 'NLD_SMALL', 3, 0),
    ('NLD_MEDIUM', 'NLD_LIGHT', 3, 0),
    ('NLD_HEAVY', 'NLD_MEDIUM', 4, 0),
    ('NLD_CAPITAL', 'NLD_HEAVY', 4, 0),
    ('NLD_CAPITAL', 'COMMAND', 3, 0),
    ('ENG_LIGHT', 'ENG_SMALL', 3, 0),
    ('ENG_MEDIUM', 'ENG_LIGHT', 3, 0),
    ('ENG_HEAVY', 'ENG_MEDIUM', 4, 0),
    ('ENG_CAPITAL', 'ENG_HEAVY', 4, 0),
    ('ENG_CAPITAL', 'COMMAND', 3, 0),
    ('FRA_LIGHT', 'FRA_SMALL', 3, 0),
    ('FRA_MEDIUM', 'FRA_LIGHT', 3, 0),
    ('FRA_HEAVY', 'FRA_MEDIUM', 4, 0),
    ('FRA_CAPITAL', 'FRA_HEAVY', 4, 0),
    ('FRA_CAPITAL', 'COMMAND', 3, 0),
    ('ITA_LIGHT', 'ITA_SMALL', 3, 0),
    ('ITA_MEDIUM', 'ITA_LIGHT', 3, 0),
    ('ITA_HEAVY', 'ITA_MEDIUM', 4, 0),
    ('ITA_CAPITAL', 'ITA_HEAVY', 4, 0),
    ('ITA_CAPITAL', 'COMMAND', 3, 0),
    ('OTT_LIGHT', 'OTT_SMALL', 3, 0),
    ('OTT_MEDIUM', 'OTT_LIGHT', 3, 0),
    ('OTT_HEAVY', 'OTT_MEDIUM', 4, 0),
    ('OTT_CAPITAL', 'OTT_HEAVY', 4, 0),
    ('OTT_CAPITAL', 'COMMAND', 3, 0),
    ('IND_LIGHT', 'IND_SMALL', 3, 0),
    ('IND_MEDIUM', 'IND_LIGHT', 3, 0),
    ('IND_HEAVY', 'IND_MEDIUM', 4, 0),
    ('IND_CAPITAL', 'IND_HEAVY', 4, 0),
    ('IND_CAPITAL', 'COMMAND', 3, 0),
    ('CHN_LIGHT', 'CHN_SMALL', 3, 0),
    ('CHN_MEDIUM', 'CHN_LIGHT', 3, 0),
    ('CHN_HEAVY', 'CHN_MEDIUM', 4, 0),
    ('CHN_CAPITAL', 'CHN_HEAVY', 4, 0),
    ('CHN_CAPITAL', 'COMMAND', 3, 0),
    ('JPN_LIGHT', 'JPN_SMALL', 3, 0),
    ('JPN_MEDIUM', 'JPN_LIGHT', 3, 0),
    ('JPN_HEAVY', 'JPN_MEDIUM', 4, 0),
    ('JPN_CAPITAL', 'JPN_HEAVY', 4, 0),
    ('JPN_CAPITAL', 'COMMAND', 3, 0),
    ('KOR_LIGHT', 'KOR_SMALL', 3, 0),
    ('KOR_MEDIUM', 'KOR_LIGHT', 3, 0),
    ('KOR_HEAVY', 'KOR_MEDIUM', 4, 0),
    ('KOR_CAPITAL', 'KOR_HEAVY', 4, 0),
    ('KOR_CAPITAL', 'COMMAND', 3, 0),
    ('MERCHANT_SHIPS', 'CARGO_STOWAGE', 2, 0),
    ('SHIPS_OF_WAR', 'GUNNERY', 3, 0),
    ('EXPLORERS', 'LOOKOUTS', 3, 0),
    ('ESCORT_SUPPORT', 'HULL_UPKEEP', 3, 0),
    ('ARMED_MERCHANT', 'MERCHANT_SHIPS', 5, 0),
    ('PRIVATEERS', 'SHIPS_OF_WAR', 5, 0),
    ('SURVEY_SHIPS', 'EXPLORERS', 5, 0),
    ('CONVOY_ESCORTS', 'ESCORT_SUPPORT', 5, 0),
    ('FAMOUS_SHIPS', 'COMMAND', 5, 0),
    ('FAMOUS_SHIPS', 'ARMED_MERCHANT', 3, 1),
    ('FAMOUS_SHIPS', 'PRIVATEERS', 3, 1),
    ('FAMOUS_SHIPS', 'SURVEY_SHIPS', 3, 1),
    ('FAMOUS_SHIPS', 'CONVOY_ESCORTS', 3, 1),
    ('HULL_UPKEEP', 'SEAMANSHIP', 2, 0),
    ('DAMAGE_CONTROL', 'HULL_UPKEEP', 3, 0),
    ('DECK_MANAGEMENT', 'SEAMANSHIP', 3, 0),
    ('HANDLING_SPEC', 'SEAMANSHIP', 5, 0),
    ('RIGGING', 'NAVIGATION', 1, 0),
    ('LOOKOUTS', 'NAVIGATION', 2, 0),
    ('INSTRUMENTS', 'NAVIGATION', 3, 0),
    ('RIGGING_SPEC', 'RIGGING', 5, 0),
    ('INSTRUMENT_SPEC', 'INSTRUMENTS', 5, 0),
    ('CARGO_STOWAGE', 'ACCOUNTING', 2, 0),
    ('STOWAGE_SPEC', 'CARGO_STOWAGE', 5, 0),
    ('GUN_LAYING', 'GUNNERY', 2, 0),
    ('LONG_GUNS', 'GUNNERY', 3, 0),
    ('SHORT_GUNS', 'GUNNERY', 3, 0),
    ('BOARDING', 'GUNNERY', 1, 0),
    ('GUN_DRILL', 'GUNNERY', 3, 0),
    ('GUNNERY_SPEC', 'GUNNERY', 5, 0),
    ('COMMAND', 'SEAMANSHIP', 3, 0),
    ('FLEET_COMMAND', 'COMMAND', 5, 0),
    ('SHIPWRIGHT', 'SEAMANSHIP', 1, 0),
    ('REFITTING', 'SHIPWRIGHT', 3, 0),
    ('AUGMENTATION', 'REFITTING', 3, 0),
    ('SHIPWRIGHT_SPEC', 'SHIPWRIGHT', 5, 0)
  ) v(code, needs, level, choice)
  join public.skills s on s.code = v.code
  join public.skills n on n.code = v.needs
on conflict (skill_id, needs_skill_id) do nothing;


-- ── 9. THE PROBE ───────────────────────────────────────────────────────────────────────────────
-- Founds its own house (rolled back whole), and asserts as it goes: refusals by place, enrolment and
-- its tuition, the one queue rule (prereq / order / full), the exact finishes of a chain, the pure
-- step of skill_level_at at each finish, the Academy button queuing instead of selling, the screen's
-- answers agreeing with the verbs, and a merchant refused. Returns a summary for the receipt.
create or replace function pg_temp.probe_0131()
returns jsonb
language plpgsql
as $$
declare
  c_uid    constant uuid := '00000000-0131-4000-8000-000000000001';
  v_player uuid;
  v_fleet  uuid;
  v_acad   uuid;
  v_noacad uuid;
  v_wrong  uuid;
  v_wrong_name text;
  v_wrong_nation text;
  v_r      jsonb;
  v_book   jsonb;
  v_card   jsonb;
  v_purse  bigint;
  v_t0     timestamptz := now();
  v_f1     timestamptz;
  v_f2     timestamptz;
  v_f3     timestamptz;
  v_npc    uuid;
  v_out    jsonb := '{}'::jsonb;
  v_list   jsonb;
begin
  begin
    -- the places: an academy, a harbour with none, a build yard outside Portugal's line
    select b.port_id into v_acad from public.port_buildings b join public.ports p on p.id = b.port_id
     where b.kind = 'academy' order by (p.code = 'LIS') desc, p.code limit 1;
    select p.id into v_noacad from public.ports p
     where p.kind = 'HARBOUR' and not exists (select 1 from public.port_buildings b where b.port_id = p.id and b.kind = 'academy')
     order by p.code limit 1;
    select p.id, p.name, n.name into v_wrong, v_wrong_name, v_wrong_nation
      from public.port_buildings b join public.ports p on p.id = b.port_id join public.nations n on n.id = p.nation_id
     where b.kind = 'building_yard'
       and not n.code = any((select builder_nations from public.ship_lines where code = 'PRT')::text[])
     order by p.code limit 1;
    if v_acad is null or v_noacad is null or v_wrong is null then
      raise exception '0131 self-assert FAIL: the probe found no academy (%), no harbour without one (%) or no foreign build yard (%)',
        v_acad, v_noacad, v_wrong;
    end if;

    v_player := public.new_house(c_uid, 'Casa da Prova 0131', 'PRT');
    select id into v_fleet from public.fleets where player_id = v_player;
    perform public.credit(v_player, 'PROBE_0131', 10000000);
    perform cmd.assume_identity(c_uid);

    -- (p1) BY PLACE: an academy skill where there is no academy; Portuguese hulls at a foreign build yard.
    update public.fleets set port_id = v_noacad, status = 'DOCKED' where id = v_fleet;
    v_r := pg_temp.call_0131(format('select cmd.skill_enroll(%L, %L)', 'GUNNERY', v_fleet));
    if v_r->>'error_code' is distinct from 'E_NO_ACADEMY' then
      raise exception '0131 self-assert FAIL: enrolling in Gunnery with no academy answered %', v_r;
    end if;
    update public.fleets set port_id = v_wrong, status = 'DOCKED' where id = v_fleet;
    v_r := pg_temp.call_0131(format('select cmd.skill_enroll(%L, %L)', 'PRT_SMALL', v_fleet));
    if v_r->>'error_code' is distinct from 'E_NOT_TAUGHT_HERE'
       or position('Portugal' in v_r->>'error_message') = 0
       or position(format('%s is in %s.', v_wrong_name, v_wrong_nation) in v_r->>'error_message') = 0 then
      raise exception '0131 self-assert FAIL: enrolling in Portuguese hulls at % answered %', v_wrong_name, v_r;
    end if;
    select x.value into v_card from jsonb_array_elements(world.skills()->'skills') x where x.value->>'code' = 'PRT_SMALL';
    if (v_card->>'can_enrol')::boolean or v_card->'enrol_refusal'->>'sentence' is distinct from v_r->>'error_message'
       or v_card->>'enrol_where' is distinct from 'Taught at any build yard in Portugal.' then
      raise exception '0131 self-assert FAIL: the screen disagrees with the enrol verb at %: %', v_wrong_name, v_card;
    end if;
    if exists (select 1 from public.skill_sp where player_id = v_player) then
      raise exception '0131 self-assert FAIL: a refused enrolment wrote a skill_sp row';
    end if;

    -- (p2) ENROL at the academy: tuition = skill_study_base_cost × rank, an ENROLLED event, the row.
    update public.fleets set port_id = v_acad, status = 'DOCKED' where id = v_fleet;
    select ducats into v_purse from public.players where id = v_player;
    v_r := pg_temp.call_0131(format('select cmd.skill_enroll(%L, %L)', 'GUNNERY', v_fleet));
    if not coalesce((v_r->>'ok')::boolean, false) or (v_r->>'paid')::bigint <> public.wc_int('skill_study_base_cost') * 1
       or (select ducats from public.players where id = v_player) <> v_purse - public.wc_int('skill_study_base_cost') * 1
       or not exists (select 1 from public.events e where e.player_id = v_player and e.kind = 'ENROLLED' and e.payload->>'code' = 'GUNNERY')
       or not exists (select 1 from public.skill_sp x join public.skills k on k.id = x.skill_id
                       where x.player_id = v_player and k.code = 'GUNNERY' and x.sp = 0) then
      raise exception '0131 self-assert FAIL: enrolling in Gunnery (rank 1) did not charge the tuition, record it and enrol: %', v_r;
    end if;
    -- a SECOND enrolment (a double tap) charges nothing and writes no second record
    select ducats into v_purse from public.players where id = v_player;
    v_r := pg_temp.call_0131(format('select cmd.skill_enroll(%L, %L)', 'GUNNERY', v_fleet));
    if v_r->>'error_code' is distinct from 'E_ALREADY_ENROLLED'
       or (select ducats from public.players where id = v_player) <> v_purse
       or (select count(*) from public.events e where e.player_id = v_player and e.kind = 'ENROLLED' and e.payload->>'code' = 'GUNNERY') <> 1 then
      raise exception '0131 self-assert FAIL: a second enrolment charged or recorded again: %', v_r;
    end if;
    select ducats into v_purse from public.players where id = v_player;
    v_r := pg_temp.call_0131(format('select cmd.skill_enroll(%L, %L)', 'GUN_LAYING', v_fleet));
    if not coalesce((v_r->>'ok')::boolean, false) or (select ducats from public.players where id = v_player) <> v_purse - public.wc_int('skill_study_base_cost') * 2 then
      raise exception '0131 self-assert FAIL: enrolling in Gun Laying (rank 2) did not charge 2 × the base: %', v_r;
    end if;

    -- (p3) THE ONE QUEUE RULE refuses, with figures, and moves nothing.
    v_r := cmd.skill_queue_set('[{"code":"GUNNERY","level":1},{"code":"GUN_LAYING","level":1}]'::jsonb);
    if v_r->>'error_code' is distinct from 'E_SKILL_PREREQ'
       or (v_r->'figures'->>'have')::numeric <> 1 or (v_r->'figures'->>'need')::numeric <> 2 or v_r->'figures'->>'unit' <> 'level'
       or (v_r->>'at')::int <> 2 or v_r->>'needs' <> 'GUNNERY'
       or position('Gun Laying needs Gunnery at level 2, and you will have level 1 when it starts.' in v_r->>'error_message') <> 1 then
      raise exception '0131 self-assert FAIL: a prerequisite not met by the time it starts was not refused with figures: %', v_r;
    end if;
    v_r := cmd.skill_queue_set('[{"code":"GUNNERY","level":2}]'::jsonb);
    if v_r->>'error_code' is distinct from 'E_SKILL_ORDER' then
      raise exception '0131 self-assert FAIL: a level out of order answered %', v_r;
    end if;
    v_r := cmd.skill_queue_set('[{"code":"PRT_SMALL","level":1}]'::jsonb);
    if v_r->>'error_code' is distinct from 'E_NOT_ENROLLED' then
      raise exception '0131 self-assert FAIL: a skill not enrolled was queued: %', v_r;
    end if;
    select jsonb_agg(jsonb_build_object('code', 'GUNNERY', 'level', g)) into v_list
      from generate_series(1, public.wc_int('skill_queue_max') + 1) g;
    v_r := cmd.skill_queue_set(v_list);
    if v_r->>'error_code' is distinct from 'E_SKILL_QUEUE_FULL' then
      raise exception '0131 self-assert FAIL: % entries were not refused as a full queue: %', public.wc_int('skill_queue_max') + 1, v_r;
    end if;
    if exists (select 1 from public.skill_queue where player_id = v_player) then
      raise exception '0131 self-assert FAIL: a refused queue wrote rows';
    end if;

    -- (p4) A CHAIN, AND ITS EXACT FINISHES. At 1,800 points an hour (0.5 a second): Gunnery I (rank 1)
    --      is 250 points = 500 s; Gunnery II is 1,414 − 250 = 1,164 points = 2,328 s; Gun Laying I (rank
    --      2) is 500 points = 1,000 s — each starting when the one before finishes.
    if public.wc_num('skill_sp_per_hour') <> 1800 then
      raise exception '0131 self-assert FAIL: skill_sp_per_hour is %, the probe''s figures are for 1,800', public.wc_num('skill_sp_per_hour');
    end if;
    v_r := cmd.skill_queue_set('[{"code":"GUNNERY","level":1},{"code":"GUNNERY","level":2},{"code":"GUN_LAYING","level":1}]'::jsonb);
    if not coalesce((v_r->>'ok')::boolean, false) then
      raise exception '0131 self-assert FAIL: a legal chain was refused: %', v_r;
    end if;
    select finishes_at into v_f1 from public.skill_queue where player_id = v_player and pos = 1;
    select finishes_at into v_f2 from public.skill_queue where player_id = v_player and pos = 2;
    select finishes_at into v_f3 from public.skill_queue where player_id = v_player and pos = 3;
    if v_f1 <> v_t0 + interval '500 seconds' or v_f2 <> v_f1 + interval '2328 seconds' or v_f3 <> v_f2 + interval '1000 seconds'
       or (select starts_at from public.skill_queue where player_id = v_player and pos = 2) <> v_f1
       or (select starts_at from public.skill_queue where player_id = v_player and pos = 3) <> v_f2
       or (v_r->>'eta')::timestamptz <> v_f3 then
      raise exception '0131 self-assert FAIL: the chain''s finishes are %, %, % (eta %), not now + 500 s, + 2,328 s, + 1,000 s',
        v_f1, v_f2, v_f3, v_r->>'eta';
    end if;
    -- (p5) skill_level_at STEPS EXACTLY AT EACH FINISH — a pure function of time, no clock travel.
    if public.skill_level_at(v_player, 'GUNNERY', v_f1 - interval '1 microsecond') <> 0
       or public.skill_level_at(v_player, 'GUNNERY', v_f1) <> 1
       or public.skill_level_at(v_player, 'GUNNERY', v_f2 - interval '1 microsecond') <> 1
       or public.skill_level_at(v_player, 'GUNNERY', v_f2) <> 2
       or public.skill_level_at(v_player, 'GUN_LAYING', v_f3 - interval '1 microsecond') <> 0
       or public.skill_level_at(v_player, 'GUN_LAYING', v_f3) <> 1
       or public.skill_level(v_player, 'GUNNERY') <> 0 then
      raise exception '0131 self-assert FAIL: skill_level_at does not step at the finishes (% / % / %)', v_f1, v_f2, v_f3;
    end if;

    -- (p6) THE ACADEMY BUTTON queues — free, no level now — and refuses BEFORE tuition when a level could
    --      not be queued (Hull Upkeep needs Seamanship II; the queue will only reach I).
    select ducats into v_purse from public.players where id = v_player;
    v_r := pg_temp.call_0131(format('select cmd.study_skill(%L, %L)', 'SEAMANSHIP', v_fleet));
    if not coalesce((v_r->>'ok')::boolean, false) or (v_r->>'level')::int <> 1 or (v_r->>'paid')::bigint <> 0
       or (select ducats from public.players where id = v_player) <> v_purse
       or exists (select 1 from public.player_skills where player_id = v_player)
       or public.skill_level(v_player, 'SEAMANSHIP') <> 0
       or (select q.finishes_at from public.skill_queue q where q.player_id = v_player and q.pos = 4) <> v_f3 + interval '500 seconds' then
      raise exception '0131 self-assert FAIL: the Academy button did not queue Seamanship I after the chain, free: %', v_r;
    end if;
    v_r := pg_temp.call_0131(format('select cmd.study_skill(%L, %L)', 'HULL_UPKEEP', v_fleet));
    if v_r->>'error_code' is distinct from 'E_SKILL_PREREQ' or (select ducats from public.players where id = v_player) <> v_purse
       or exists (select 1 from public.skill_sp x join public.skills k on k.id = x.skill_id where x.player_id = v_player and k.code = 'HULL_UPKEEP') then
      raise exception '0131 self-assert FAIL: a level that could not be queued took the tuition or enrolled: %', v_r;
    end if;

    -- (p7) THE SCREEN IS THE VERBS' ANSWER.
    v_book := world.skills();
    select x.value into v_card from jsonb_array_elements(v_book->'skills') x where x.value->>'code' = 'HULL_UPKEEP';
    if (v_card->>'can_queue')::boolean or v_card->'queue_refusal'->>'code' <> 'E_SKILL_PREREQ'
       or not (v_card->>'can_enrol')::boolean or (v_card->>'enrol_fleet')::uuid <> v_fleet
       or (v_card->>'enrol_cost')::bigint <> public.wc_int('skill_study_base_cost') * 2 then
      raise exception '0131 self-assert FAIL: the screen''s answer for Hull Upkeep is not the verbs'': %', v_card;
    end if;
    select x.value into v_card from jsonb_array_elements(v_book->'skills') x where x.value->>'code' = 'GUNNERY';
    if (v_card->>'level')::int <> 0 or (v_card->>'queued_to')::int <> 2 or (v_card->>'next_level')::int <> 3
       or not (v_card->>'can_queue')::boolean or (v_card->>'next_cost')::int <> 0
       or (v_card->>'train_seconds')::numeric <> (8000 - 1414) * 2 then
      raise exception '0131 self-assert FAIL: the screen''s answer for Gunnery is %', v_card;
    end if;
    if jsonb_array_length(v_book->'queue') <> 4 or (v_book->>'eta')::timestamptz <> v_f3 + interval '500 seconds'
       or (v_book->'queue'->0->>'finishes_at')::timestamptz <> v_f1
       or jsonb_array_length(v_book->'groups') <> 8 or jsonb_array_length(v_book->'skills') <> (select count(*) from public.skills) then
      raise exception '0131 self-assert FAIL: the screen''s queue / groups / catalogue are wrong: queue %, groups %',
        v_book->'queue', v_book->'groups';
    end if;

    -- (p8) REMOVING keeps the points; the queue empties; no level was given.
    v_r := cmd.skill_queue_set('[]'::jsonb);
    if not coalesce((v_r->>'ok')::boolean, false) or exists (select 1 from public.skill_queue where player_id = v_player)
       or exists (select 1 from public.player_skills where player_id = v_player) then
      raise exception '0131 self-assert FAIL: clearing the queue did not clear it cleanly: %', v_r;
    end if;

    -- (p9) A MERCHANT IS REFUSED by every core (its skills are fixed at founding).
    select id into v_npc from public.players where is_npc order by id limit 1;
    if v_npc is not null then
      begin
        perform public.skill_queue_set_for(v_npc, '[]'::jsonb);
        raise exception '0131 self-assert FAIL: a merchant''s queue was set';
      exception when others then
        if sqlerrm not like 'E_MERCHANT_FIXED%' then raise; end if;
      end;
      begin
        perform public.skill_study_for(v_npc, 'SEAMANSHIP', null);
        raise exception '0131 self-assert FAIL: a merchant studied';
      exception when others then
        if sqlerrm not like 'E_MERCHANT_FIXED%' then raise; end if;
      end;
    end if;

    v_out := jsonb_build_object('f1', v_f1, 'f2', v_f2, 'f3', v_f3, 'acad', (select code from public.ports where id = v_acad),
                                'wrong', (select code from public.ports where id = v_wrong), 'npc', v_npc is not null);
    raise exception 'PROBE_ROLLBACK_0131';
  exception when others then
    if sqlerrm <> 'PROBE_ROLLBACK_0131' then raise; end if;
  end;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  return v_out;
end $$;

create temp table probe_0131 as
select pg_temp.probe_0131() as j;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_bad   int;
  v_n     int;
  v_list  text;
  v_def   text;
  h       record;
  d       record;
  v_probe jsonb := (select j from probe_0131);
  v_lv    int;
  v_bn    int;
  v_gt    int;
begin
  -- (a) THE CATALOGUE: 88 new rows, each NONE / 0; the four live rows untouched; both checks re-made,
  --     validated, and the old definitions gone.
  if (select count(*) from public.skills) <> (select skills from before_0131) + 88 then
    raise exception '0131 self-assert FAIL: % skills, expected % + 88', (select count(*) from public.skills), (select skills from before_0131);
  end if;
  if (select count(*) from public.skills where effect = 'NONE' and pct_per_level = 0) <> 88 then
    raise exception '0131 self-assert FAIL: % NONE skills at 0 %%, expected 88', (select count(*) from public.skills where effect = 'NONE' and pct_per_level = 0);
  end if;
  if (select md5(string_agg(to_jsonb(s)::text, '|' order by s.code)) from public.skills s where s.effect <> 'NONE') <> (select skills_hash from before_0131) then
    raise exception '0131 self-assert FAIL: a live skill row moved';
  end if;
  if (select count(*) from pg_constraint k where k.conrelid = 'public.skills'::regclass and k.contype = 'c'
        and k.conname in ('skills_effect_known', 'skills_pct_per_level_sane') and k.convalidated) <> 2
     or exists (select 1 from pg_constraint k where k.conrelid = 'public.skills'::regclass and k.contype = 'c'
                  and k.conname not in ('skills_effect_known', 'skills_pct_per_level_sane')
                  and (pg_get_constraintdef(k.oid) like '%effect%' or pg_get_constraintdef(k.oid) like '%pct_per_level%')) then
    raise exception '0131 self-assert FAIL: the effect / pct checks are not exactly the two re-made, validated checks';
  end if;
  -- positive control: the re-made checks still refuse what they must
  begin
    insert into public.skills (code, name, effect, pct_per_level, blurb) values ('ZZ_PROBE', 'x', 'NONE', 1, 'x');
    raise exception '0131 self-assert FAIL: a NONE skill with a percentage was admitted';
  exception when check_violation then null;
  end;
  begin
    insert into public.skills (code, name, effect, pct_per_level, blurb) values ('ZZ_PROBE', 'x', 'BOGUS', 1, 'x');
    raise exception '0131 self-assert FAIL: an unknown effect was admitted';
  exception when check_violation then null;
  end;

  -- (b) THE PROFILE: every skill one profile, eight groups, every hull skill enrolable at ≥ 1 build yard
  --     of its line's countries, an academy exists, the prerequisites resolve with no cycle, and every
  --     choice group offers a real choice.
  if exists (select 1 from public.skills s where not exists (select 1 from public.skill_profile pr where pr.skill_id = s.id))
     or (select count(*) from public.skill_profile) <> (select count(*) from public.skills)
     or (select count(*) from public.skill_groups) <> 8
     or (select count(*) from public.skill_profile where enrol_where = 'line_yard') <> 55
     or (select count(*) from public.skill_profile pr join public.skills s on s.id = pr.skill_id
          where pr.enrol_where = 'none') <> 4
     or exists (select 1 from public.skill_profile pr
                 where (pr.enrol_where = 'none') <> (pr.skill_id in (select id from live_skills_0131))) then
    raise exception '0131 self-assert FAIL: the profile does not cover the catalogue as authored (92 / 8 groups / 55 hull / 4 live)';
  end if;
  select string_agg(distinct pr.line_code, ',') into v_list from public.skill_profile pr
   where pr.enrol_where = 'line_yard'
     and not exists (select 1 from public.port_buildings b join public.ports p on p.id = b.port_id
                      join public.nations n on n.id = p.nation_id join public.ship_lines sl on sl.code = pr.line_code
                     where b.kind = 'building_yard' and n.code = any(sl.builder_nations));
  if v_list is not null or not exists (select 1 from public.port_buildings where kind = 'academy') then
    raise exception '0131 self-assert FAIL: line(s) % have no build yard to enrol at, or there is no academy', coalesce(v_list, '-');
  end if;
  if (select count(*) from public.skill_prereqs) <> 91 then
    raise exception '0131 self-assert FAIL: % prerequisite rows, data/skills.json has 91', (select count(*) from public.skill_prereqs);
  end if;
  with recursive walk(start_id, at_id, depth) as (
    select skill_id, needs_skill_id, 1 from public.skill_prereqs
    union all
    select w.start_id, q.needs_skill_id, w.depth + 1 from walk w join public.skill_prereqs q on q.skill_id = w.at_id
     where w.depth < 100)
  select count(*) into v_bad from walk where start_id = at_id;
  if v_bad <> 0 then
    raise exception '0131 self-assert FAIL: the prerequisites have a cycle';
  end if;
  if exists (select 1 from public.skill_prereqs where choice > 0 group by skill_id, choice having count(*) < 2) then
    raise exception '0131 self-assert FAIL: a choice group offers no choice';
  end if;

  -- (c) THE HEAVY COMPARISONS ran in §7 before the lock (levels, bonuses, 0107 gates, merchant cards,
  --     harbour merchant levels) and recorded their counts; they must have run. The levels again, now
  --     that the catalogue rows exist — cheap, and the proof that 88 NONE rows moved no house's level.
  select lv, bn, gt into v_lv, v_bn, v_gt from early_0131;
  if v_lv is null then
    raise exception '0131 self-assert FAIL: the comparisons before the lock did not run';
  end if;
  select count(*) into v_bad from levels_before_0131 b where public.skill_level(b.player_id, b.code) is distinct from b.level;
  if v_bad <> 0 then
    raise exception '0131 self-assert FAIL: % house × skill level(s) moved once the catalogue landed', v_bad;
  end if;
  -- the new skills read 0 for every house: no level row names one, and this file left no queue or
  -- enrolment row behind (the probe's were rolled back)
  select count(*) into v_bad from public.player_skills ps join public.skills s on s.id = ps.skill_id where s.effect = 'NONE';
  select v_bad + (select count(*) from public.skill_queue) + (select count(*) from public.skill_sp) into v_bad;
  if v_bad <> 0 then
    raise exception '0131 self-assert FAIL: % level / queue / enrolment row(s) for the new skills exist after the file', v_bad;
  end if;

  -- (f) player_skills untouched by this file.
  if (select md5(coalesce(string_agg(to_jsonb(ps)::text, '|' order by ps.player_id, ps.skill_id), '')) from public.player_skills ps)
       <> (select player_skills_hash from before_0131) then
    raise exception '0131 self-assert FAIL: player_skills moved';
  end if;

  -- (g) MERCHANTS have no queue and no enrolment rows (and the probe saw every core refuse one).
  select count(*) into v_bad from public.skill_queue q join public.players p on p.id = q.player_id where p.is_npc;
  select v_bad + count(*) into v_bad from public.skill_sp x join public.players p on p.id = x.player_id where p.is_npc;
  if v_bad <> 0 then
    raise exception '0131 self-assert FAIL: % merchant queue / enrolment row(s)', v_bad;
  end if;

  -- (h) NO CRON ADDED: levels are a pure function of time.
  if pg_temp.cron_jobs_0131() is distinct from (select cron_jobs from before_0131) then
    raise exception '0131 self-assert FAIL: the cron jobs moved';
  end if;

  -- (i) THE DOORS: +2 entry points exactly, granted to authenticated and denied to anon; no client
  --     write grant, no client-executable writer; every core and table server-only.
  if (select count(*) from public.client_rpc_entry_points()) <> (select entry_points from before_0131) + 2
     or (select count(*) from public.client_rpc_entry_points() e
          where e.fn in ('cmd.skill_enroll(text, uuid)'::regprocedure, 'cmd.skill_queue_set(jsonb)'::regprocedure)) <> 2 then
    raise exception '0131 self-assert FAIL: the entry points are % (was %), not +2 with both doors',
      (select count(*) from public.client_rpc_entry_points()), (select entry_points from before_0131);
  end if;
  if not has_function_privilege('authenticated', 'cmd.skill_enroll(text, uuid)', 'execute')
     or not has_function_privilege('authenticated', 'cmd.skill_queue_set(jsonb)', 'execute')
     or has_function_privilege('anon', 'cmd.skill_enroll(text, uuid)', 'execute')
     or has_function_privilege('anon', 'cmd.skill_queue_set(jsonb)', 'execute') then
    raise exception '0131 self-assert FAIL: the two doors are not granted to authenticated only';
  end if;
  if (select count(*) from public.client_executable_writers()) <> 0 or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0131 self-assert FAIL: % client-executable writer(s), % client write grant(s)',
      (select count(*) from public.client_executable_writers()), (select count(*) from public.client_write_grants());
  end if;
  select count(*) into v_bad
    from unnest(array['public.skill_sp_for(int, int)', 'public.skill_level_at(uuid, text, timestamptz)',
                      'public.skill_is_enrolled(uuid, uuid)', 'public.skill_enrol_cost(uuid)',
                      'public.skill_taught_place(uuid)', 'public.skill_taught_at(uuid, uuid)',
                      'public.skill_enrol_refusal(uuid, uuid, uuid)', 'public.skill_queue_now(uuid)',
                      'public.skill_queue_refusal(uuid, jsonb, uuid)', 'public.skill_refused(jsonb)',
                      'public.skill_lock(uuid)',
                      'public.skill_enroll_for(uuid, text, uuid)', 'public.skill_queue_set_for(uuid, jsonb)',
                      'public.skill_study_for(uuid, text, uuid)', 'public.skill_answers(uuid, uuid, jsonb)']) f(fn)
   cross join unnest(array['anon', 'authenticated']) r(role)
   where has_function_privilege(r.role, f.fn, 'execute');
  select v_bad + count(*) into v_bad
    from unnest(array['public.skill_groups', 'public.skill_profile', 'public.skill_prereqs', 'public.skill_queue', 'public.skill_sp']) t(tbl)
   cross join unnest(array['anon', 'authenticated']) r(role)
   where has_table_privilege(r.role, t.tbl, 'select,insert,update,delete');
  if v_bad <> 0 then
    raise exception '0131 self-assert FAIL: % client reach(es) into the skill cores or tables', v_bad;
  end if;

  -- (j) THE RE-CUTS: each new body reverses to its pre-image hunk by hunk; ACLs unmoved.
  for d in select * from defs_before_0131 loop
    v_def := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0131 where fn = d.fn order by n desc loop
      if (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new) <> 1 then
        raise exception '0131 self-assert FAIL: hunk % of % is not in the new body exactly once', h.n, d.fn;
      end if;
      v_def := replace(v_def, h.new, h.old);
    end loop;
    if v_def <> d.def then
      raise exception '0131 self-assert FAIL: % does not reverse to its pre-image — something beyond the hunks moved', d.fn;
    end if;
    if coalesce((select p.proacl::text from pg_proc p where p.oid = d.fn::regprocedure), '') <> d.acl then
      raise exception '0131 self-assert FAIL: the ACL of % moved', d.fn;
    end if;
  end loop;

  -- (k) THE PROBE ran to its end and was rolled back.
  if v_probe->>'f3' is null
     or exists (select 1 from public.players where auth_uid = '00000000-0131-4000-8000-000000000001') then
    raise exception '0131 self-assert FAIL: the probe did not finish, or its house was not rolled back: %', v_probe;
  end if;

  raise notice '0131 self-assert ok: A SKILL IS LEARNED BY THE HOUR. Catalogue +88 (NONE, 0 %%) = % skills, the 4 live rows untouched, effect/pct checks re-made NOT VALID then VALIDATED (positive controls refused a NONE with a percentage and an unknown effect); 8 groups, every skill profiled (55 hull skills by line, 4 needing no enrolment), every line a build yard to enrol at, 91 prerequisites, no cycle. Levels: % house × skill readings equal their pre-image through the re-cut skill_level; % house × effect player_skill_bonus readings equal; % houses'' 0107 gates (earned caps + the six leg rungs) equal; player_skills untouched; every new skill reads 0 for every house. Merchants: 0 queue / enrolment rows, every core refuses one, % card(s) show their skills as before and % merchant level(s) in the 8 busiest harbours'' lists equal their pre-image (port_merchants now sums four skills, not 92). No cron (% before and after). +2 entry points exactly (skill_enroll, skill_queue_set), authenticated only; 0 client writers; cores and tables server-only; 7 bodies reverse to their pre-images, ACLs unmoved. PROBE (own house, rolled back): E_NO_ACADEMY with no academy, E_NOT_TAUGHT_HERE for Portuguese hulls at % with its figures (and the screen served the same sentence), tuition 500 × rank charged once with an ENROLLED event, a second enrolment charged nothing; prereq / order / not-enrolled / full refused with figures, nothing written; the chain Gunnery I → II → Gun Laying I finished at exactly now + 500 s (%), + 2,328 s (%), + 1,000 s (%) and skill_level_at stepped at each finish; the Academy button queued Seamanship I free (no level now) and refused Hull Upkeep before any tuition; the screen''s can_queue / refusal / ETA matched the verbs; clearing the queue left no level.',
    (select count(*) from public.skills), v_lv, v_bn, v_gt,
    (select cards from early_0131), (select harbours from early_0131),
    coalesce((select cron_jobs::text from before_0131), 'no cron schema'),
    v_probe->>'wrong', v_probe->>'f1', v_probe->>'f2', v_probe->>'f3';
end $$;
