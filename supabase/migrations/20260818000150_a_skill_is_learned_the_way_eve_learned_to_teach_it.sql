-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0150 — A SKILL IS LEARNED THE WAY EVE LEARNED TO TEACH IT  (K1: EVE's fixes as data + hunks — DARK)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY NOW ─────────────────────────────────────────────────────────────────────────────────────
-- docs/SKILLS_AND_CAPTAINS.md §3.2-3.3 and §8 row K1 (research: docs/research/EVE_SKILLS.md). The owner:
-- *"EVE-style skill sets … make them properly"*. D1-D5 were approved by default (the standing rule: no
-- answer in 2 minutes = yes) — decided by default, the owner may reverse any of them, each is data.
--
-- ── WHAT THIS FILE DOES (data/skills.json + scripts/build-ships.mjs are the one authority; the
--    world guard holds the database to them) ──────────────────────────────────────────────────────
--   D1  skill_queue_max 10 → 50 (it only grows: a knob already ≥ 50 is left alone).
--   D2  the hull ladder asks III: the 22 skill_prereqs X_HEAVY ← X_MEDIUM and X_CAPITAL ← X_HEAVY, and
--       the 22 hull skill_requirements (heavy T1 ← Medium IV, capital ← Heavy IV), level 4 → 3. Item rows
--       at IV (G4 gear) untouched.
--   D3  skill_profile.enrol_where gains 'anywhere' = any port; the 33 'academy' rows and the 15 new
--       skills use it. public.skill_taught_at (THE place rule) answers null for it; public.skill_taught_place
--       says "any port". line_yard is unchanged ("to learn Chinese hulls you sail to Guangzhou").
--   D4  4 support-V prerequisites (Armed Merchantmen ← Cargo Stowage V, Privateers ← Gun Laying V, Survey
--       Ships ← Lookouts V, Convoy Escorts ← Hull Upkeep V) and 4 second per-level bonuses on the T2 hulls
--       of each one's role (+2 % hull, +2 % reach, +1 % speed, +2 % armour), beside the live +4 %.
--   D5  the SOCIAL group (ord 9) and 15 new skills, 92 → 107, each with its prerequisites and effect row.
--       Four are company effects their reader already sums (Wholesale TRADE_CAP, Negotiation SPREAD,
--       Provisioning ENDURANCE, Celestial Navigation SPEED); Crew Drill is a FITTING effect `hands`,
--       read by world.ship_budget (one hunk); the other ten are HOUSE effects whose readers arrive in
--       K2 / K2b / K6 (nothing reads those stats yet — said plainly).
--   THE CHECKS RE-MADE (§2): skill_effects admits fitting `hands` and the ten house stats;
--       skill_profile admits 'anywhere'.
--   THE HUNKS (sliced from the bodies live after 0149, LF-normalised, each occurring once, each body
--       reversing to its pre-image, ACLs unchanged):
--       public.skill_taught_at     'anywhere' → null (D3)
--       public.skill_taught_place  'anywhere' → 'any port' (D3)
--       world.ship_budget          Crew Drill: the Hands max × (1 + % / 100), floored — lit only (D5)
--       public.player_skill_bonus  a company effect of a skill that is NOT one of the four live skills
--                                  (skills.effect names those, live since 0016) bites only while
--                                  skills_bite is on — so the four new company effects stay DARK. Two
--                                  PL/pgSQL branches (lit: every row; dark: joined to the live four),
--                                  so the hot dark read (voyage.fleet_speed, endurance) costs no more:
--                                  an OR-ed switch in the WHERE was measured at 2.7 × (37 → 100 ms over
--                                  the merchants) — the switch is not inlined there and runs per row.
--       world.skills               `takes_effect` follows that same switch (the Academy never says a
--                                  skill works while it does not)
--       public.skill_effect_words  `hands` → "Hands" (the one new stat a lit K1 can print)
--
-- ── WHAT IT DELIBERATELY DOES NOT DO ────────────────────────────────────────────────────────────
-- Light skills_bite. Rename, merge or delete any skill (only added). Touch any house's level, queue entry,
-- enrolment or skill points (asserted). Read the ten house stats (K2 / K2b / K6 give them readers and
-- words). Touch the client (the Skills screen follow-up lands after this is LIVE). Give an injector,
-- extractor, attribute, remap or skill points for coin (D7: asserted absent from the catalogue and the
-- RPC registry). The bonus training from sailing (D6) is K3.
--
-- ── THE PROOF ───────────────────────────────────────────────────────────────────────────────────
-- (a) the catalogue: 107 skills, 9 groups, 48 anywhere / 55 line_yard / 4 none / 0 academy, 179 effects,
--     every new skill NONE / 0 on public.skills; the 22 ladder prereqs and the 22 hull requirement rows are
--     exactly the pre-image rows at IV, now III; every other prereq and requirement row unmoved.
-- (b) every house × the four company effects, and every hull's budget, read the SAME old vs new (pg_temp
--     pre-images, one statement each), dark and lit (rolled back) — nobody holds a new skill.
-- (c) world.skills(): the 92 old skills answer as before but for the enrolment words of the 33 general
--     skills ("Taught at any port.") and the 26 changed prerequisite lists; the 15 new skills do not
--     take effect dark; queue_max 50; SOCIAL served.
-- (d) the place rule over every skill × every port: line_yard and none = the pre-image; anywhere = null.
-- (e) no house's levels, queue, enrolments or skill points moved; every queue still legal; no house
--     holds or queues a T2 specialisation (the one tightening, D4) without its support skill at V.
-- (f) THE PROBE (own throw-away houses, rolled back): Gunnery enrolled at a port with no academy (it was
--     E_NO_ACADEMY there); a line hull skill still refused away from its yards (E_NOT_TAUGHT_HERE); 50
--     queued levels accepted by the verb, 51 refused E_SKILL_QUEUE_FULL with figures; Medium Hulls III
--     lets Heavy Hulls I queue, and a heavy hull's requirements are met by Medium III; Armed Merchantmen
--     refused without Cargo Stowage V, allowed with it; DARK, Wholesale / Provisioning / Celestial
--     Navigation / Negotiation / Crew Drill change nothing; LIT, they add exactly their per cents to the
--     company sums and Crew Drill V gives Hands × 1.15 (floored).
-- (g) timing (notice only): every merchant's player_skill_bonus (SPEED, ENDURANCE) old vs new.
--
-- ── LOCKS ───────────────────────────────────────────────────────────────────────────────────────
-- Heavy pre-image reads first (ACCESS SHARE). Then §2 re-makes three CHECKs: ACCESS EXCLUSIVE on
-- public.skill_effects and public.skill_profile, retried on lock_timeout / deadlock (5 tries) and held
-- to commit — after it come only the catalogue rows, the re-cuts, the comparisons and the probe
-- (seconds). Readers waiting on those two tables (player_skill_bonus in fleet_speed, the Academy) wait
-- that long. Deploy with the clock unwound (DEPLOY_RUNBOOK): unwind_the_clock() → db push → wind_the_clock().
--
-- ROLLBACK: a forward slice restoring skill_queue_max 10, the 22 prereqs and 22 requirement rows to IV,
-- 'academy' on the 33 rows, the six bodies (their hunks' OLD text), and deleting the 4 support-V prereqs,
-- the 4 second bonuses, the 15 skills (and their profile / prereq / effect rows) and SOCIAL — only after
-- asserting no house holds, queues or is enrolled in a new skill (a level a house holds is never taken).
-- SUPERSEDES, by hunks sliced from the LIVE bodies (LF-normalised), each asserted to occur exactly once,
-- ACLs unchanged: public.skill_taught_at (0131), public.skill_taught_place (0131), world.ship_budget
-- (0149), public.player_skill_bonus (0133), world.skills (0133), public.skill_effect_words (0133).
-- VERSION: 0150. Applies on K0 (0149), which deploys first.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  perform set_config('random_page_cost', '1.1', true);   -- prod's planner page cost (0149's header)
end $guard$;

-- ── 0. HELPERS (pg_temp, gone at commit) ───────────────────────────────────────────────────────
create or replace function pg_temp.occurs_0150(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 1. THE PRE-IMAGES (every heavy read happens here, before anything is locked) ───────────────
create temp table defs_before_0150 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('public.skill_taught_at(uuid, uuid)'), ('public.skill_taught_place(uuid)'),
               ('world.ship_budget(uuid)'), ('public.player_skill_bonus(uuid, text)'),
               ('world.skills()'), ('public.skill_effect_words(text, numeric)')) f(fn);

create temp table untouched_before_0150 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl
  from (values ('public.skill_queue_refusal(uuid, jsonb, uuid)'), ('public.skill_queue_set_for(uuid, jsonb)'),
               ('public.skill_enroll_for(uuid, text, uuid)'), ('public.skill_enrol_refusal(uuid, uuid, uuid)'),
               ('public.skill_answers(uuid, uuid, jsonb)'), ('public.skill_level_at(uuid, text, timestamp with time zone)'),
               ('world.skill_bonuses(uuid, uuid)'), ('public.house_skill_scopes(uuid, uuid)'),
               ('public.requirements_unmet(uuid, text, text)')) f(fn);

create temp table before_0150 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from public.skills) as skills,
       (select count(*) from public.skill_groups) as groups,
       (select count(*) from public.skill_effects) as effects,
       (select count(*) from public.skill_prereqs) as prereqs,
       (select count(*) from public.skill_requirements) as requirements,
       (select count(*) from public.skill_profile where enrol_where = 'academy') as academy,
       public.wc_int('skill_queue_max') as queue_max,
       (select max(id) from public.skill_effects) as effects_max_id,
       -- the catalogue rows this file must leave exactly as found (world data; no player writes them)
       (select md5(string_agg(to_jsonb(s)::text, '|' order by s.code)) from public.skills s) as skills_hash,
       (select md5(string_agg(to_jsonb(e)::text, '|' order by e.id)) from public.skill_effects e) as effects_hash,
       (select md5(string_agg(format('%s/%s/%s/%s', r.subject_kind, r.subject_code, r.skill_code, r.level), '|'
                              order by r.subject_kind, r.subject_code, r.skill_code))
          from public.skill_requirements r
         where not (r.subject_kind = 'hull' and r.level = 4 and r.skill_code ~ '_(MEDIUM|HEAVY)$')) as req_rest_hash;

-- the rows D2 moves, found by their rule (never typed): IV-level ladder prerequisites and hull requirements
create temp table ladder_before_0150 on commit drop as
select s.code as skill, n.code as needs, q.level, q.choice
  from public.skill_prereqs q
  join public.skills s on s.id = q.skill_id
  join public.skills n on n.id = q.needs_skill_id
 where q.level = 4
   and ((s.code ~ '_HEAVY$' and n.code ~ '_MEDIUM$') or (s.code ~ '_CAPITAL$' and n.code ~ '_HEAVY$'));
create temp table req_before_0150 on commit drop as
select r.subject_code as hull, r.skill_code as skill, r.level
  from public.skill_requirements r
 where r.subject_kind = 'hull' and r.level = 4 and r.skill_code ~ '_(MEDIUM|HEAVY)$';
create temp table prereq_rest_0150 on commit drop as
select s.code as skill, n.code as needs, q.level, q.choice
  from public.skill_prereqs q
  join public.skills s on s.id = q.skill_id
  join public.skills n on n.id = q.needs_skill_id
 where (s.code, n.code) not in (select l.skill, l.needs from ladder_before_0150 l);

-- what every house holds, as found (no statement of this file writes these tables)
create temp table held_before_0150 on commit drop as
select ps.player_id, s.code, ps.level, p.is_npc
  from public.player_skills ps join public.skills s on s.id = ps.skill_id join public.players p on p.id = ps.player_id;
create temp table queue_before_0150 on commit drop as
select q.player_id, q.pos, s.code, q.to_level, q.finishes_at from public.skill_queue q join public.skills s on s.id = q.skill_id;
create temp table sp_before_0150 on commit drop as
select x.player_id, s.code, x.sp from public.skill_sp x join public.skills s on s.id = x.skill_id;

-- the Academy as it reads now (no one signed in: the catalogue's own answers)
create temp table academy_before_0150 on commit drop as
select world.skills() as v;

-- THE PLACE RULE over every skill × every port, as it answers now
create temp table taught_before_0150 on commit drop as
select s.id as skill_id, s.code, pr.enrol_where, p.id as port_id, public.skill_taught_at(s.id, p.id) as answer
  from public.skills s
  join public.skill_profile pr on pr.skill_id = s.id
 cross join public.ports p;

-- the old bodies compared in §5 (player_skill_bonus, ship_budget), kept under pg_temp names
do $$
declare
  d     record;
  v_def text;
begin
  for d in select * from defs_before_0150 where fn in ('public.player_skill_bonus(uuid, text)', 'world.ship_budget(uuid)') loop
    v_def := replace(d.def, 'CREATE OR REPLACE FUNCTION ' || split_part(d.fn, '(', 1) || '(',
                     'CREATE OR REPLACE FUNCTION pg_temp.' || split_part(split_part(d.fn, '(', 1), '.', 2) || '_before_0150(');
    if strpos(v_def, '_before_0150(') = 0 then
      raise exception '0150 self-assert FAIL: could not rename the pre-image of %', d.fn;
    end if;
    execute v_def;
  end loop;
end $$;

-- ── 2. THE CHECKS RE-MADE — from here to commit skill_effects and skill_profile are held ─────────
do $alter$
declare
  v_fit   text;
  v_house text;
  v_enrol text;
  v_try   int := 0;
  v_state text;
  v_msg   text;
begin
  select k.conname into v_fit from pg_constraint k
   where k.conrelid = 'public.skill_effects'::regclass and k.contype = 'c'
     and pg_get_constraintdef(k.oid) like '%''fitting''%' and pg_get_constraintdef(k.oid) like '%high_hands%';
  select k.conname into v_house from pg_constraint k
   where k.conrelid = 'public.skill_effects'::regclass and k.contype = 'c'
     and pg_get_constraintdef(k.oid) like '%''house''%' and pg_get_constraintdef(k.oid) like '%officer_bonus%';
  select k.conname into v_enrol from pg_constraint k
   where k.conrelid = 'public.skill_profile'::regclass and k.contype = 'c'
     and pg_get_constraintdef(k.oid) like '%enrol_where%' and pg_get_constraintdef(k.oid) like '%academy%'
     and pg_get_constraintdef(k.oid) not like '%line_code%';
  if v_fit is null or v_house is null or v_enrol is null then
    raise exception '0150 self-assert FAIL: the fitting (%), house (%) or enrol_where (%) check is not where 0131 / 0133 put it',
      v_fit, v_house, v_enrol;
  end if;
  loop
    v_try := v_try + 1;
    begin
      execute format(
        'alter table public.skill_effects drop constraint %I, drop constraint %I, '
        'add constraint skill_effects_fitting_stat check (scope <> ''fitting'' or stat in (''deck'', ''high_hands'', ''hands'')) not valid, '
        'add constraint skill_effects_house_stat check (scope <> ''house'' or stat in (''officer_bonus'', '
        '''standing_routes'', ''crew_wage'', ''profit_tax'', ''storm_damage'', ''calm_delay'', ''captain_wage'', '
        '''crew_hire'', ''influence'', ''captain_xp'', ''homesick'')) not valid', v_fit, v_house);
      execute format(
        'alter table public.skill_profile drop constraint %I, '
        'add constraint skill_profile_enrol_where_known check (enrol_where in (''none'', ''academy'', ''line_yard'', ''anywhere'')) not valid',
        v_enrol);
      alter table public.skill_effects validate constraint skill_effects_fitting_stat;
      alter table public.skill_effects validate constraint skill_effects_house_stat;
      alter table public.skill_profile validate constraint skill_profile_enrol_where_known;
      exit;
    exception when lock_not_available or deadlock_detected then
      get stacked diagnostics v_msg = message_text, v_state = returned_sqlstate;
      if v_try >= 5 then
        raise exception '0150 self-assert FAIL: LOCK CONTENTION, not a result — the skill tables could not be altered in 5 tries (%: %). Re-run the push.',
          v_state, v_msg;
      end if;
      perform pg_sleep(0.5);
    end;
  end loop;
end $alter$;

comment on column public.skill_profile.enrol_where is
  '0131 / 0150: where a skill is ENROLLED — none = counts as enrolled (the four live skills); anywhere = any '
  'port (the general skills, D3); line_yard = any build yard in a country of line_code''s builder_nations; '
  'academy = any port with an academy (no row uses it since 0150). public.skill_taught_at is the one place rule.';

-- ── 3. THE CATALOGUE ROWS (data/skills.json; data/ships.generated.json for the hull requirements) ──
-- D1: the queue only grows
update public.world_config set value = to_jsonb(50) where key = 'skill_queue_max' and (value #>> '{}')::int < 50;

-- D5: the group and the 15 skills
insert into public.skill_groups (code, name, ord) values ('SOCIAL', 'Social', 9) on conflict (code) do nothing;

create temp table new_skills_0150 (code text primary key, name text, grp text, rank int, blurb text) on commit drop;
insert into new_skills_0150 values
  ('WHOLESALE',     'Wholesale',            'TRADE',      4, 'Dealing by the shipload, so a day''s trade may run larger.'),
  ('NEGOTIATION',   'Negotiation',          'TRADE',      3, 'Patient talk across the counter, so a haggle goes your way more often.'),
  ('FACTORAGE',     'Factorage',            'TRADE',      3, 'Factors kept in foreign ports, so more standing routes can run at once.'),
  ('PURSERSHIP',    'Pursership',           'TRADE',      2, 'Keeping the ship''s purse, so the crew''s daily wages cost less.'),
  ('BROKERAGE',     'Brokerage',            'TRADE',      2, 'Knowing the brokers, so less of a profit goes to the city''s tax.'),
  ('CREW_DRILL',    'Crew Drill',           'SEAMANSHIP', 2, 'Drilled hands work more gear, so a ship has more Hands to fit with.'),
  ('PROVISIONING',  'Provisioning',         'SEAMANSHIP', 2, 'Stowing and rationing stores, so supplies last longer at sea.'),
  ('CELESTIAL_NAV', 'Celestial Navigation', 'NAVIGATION', 5, 'Fixing the ship''s place by sun and stars, so passages run a little faster.'),
  ('WEATHER_LORE',  'Weather Lore',         'NAVIGATION', 3, 'Reading the sky, so storms do less harm to the hull.'),
  ('LIGHT_AIR',     'Light-air Sailing',    'NAVIGATION', 2, 'Working a ship in faint winds, so a calm holds her for less time.'),
  ('LEADERSHIP',    'Leadership',           'COMMAND',    2, 'Teaching captains by example, so they gain experience faster.'),
  ('HOSPITALITY',   'Hospitality',          'COMMAND',    2, 'A good table and letters from home, so captains far from home miss it less.'),
  ('RECRUITING',    'Recruiting',           'SOCIAL',     1, 'Knowing where good captains are found, so hiring one costs less.'),
  ('ETIQUETTE',     'Etiquette',            'SOCIAL',     2, 'Manners that open doors in port, so hiring crew costs less.'),
  ('PATRONAGE',     'Patronage',            'SOCIAL',     3, 'Gifts given where they count, so the coin you give a city buys more influence.');

insert into public.skills (code, name, effect, pct_per_level, blurb)
select n.code, n.name, 'NONE', 0, n.blurb from new_skills_0150 n
on conflict (code) do nothing;

-- each new skill's place in its group: after the last there, in data/skills.json's order
insert into public.skill_profile (skill_id, group_code, rank, enrol_where, line_code, ord)
select s.id, n.grp, n.rank, 'anywhere', null,
       (select coalesce(max(pr.ord), 0) from public.skill_profile pr where pr.group_code = n.grp)
       + row_number() over (partition by n.grp order by x.k)
  from new_skills_0150 n
  join public.skills s on s.code = n.code
  join (values ('WHOLESALE', 1), ('NEGOTIATION', 2), ('FACTORAGE', 3), ('PURSERSHIP', 4), ('BROKERAGE', 5),
               ('CREW_DRILL', 1), ('PROVISIONING', 2), ('CELESTIAL_NAV', 1), ('WEATHER_LORE', 2), ('LIGHT_AIR', 3),
               ('LEADERSHIP', 1), ('HOSPITALITY', 2), ('RECRUITING', 1), ('ETIQUETTE', 2), ('PATRONAGE', 3)) x(code, k)
    on x.code = n.code
on conflict (skill_id) do nothing;

-- D3: the general skills are enrolled anywhere
update public.skill_profile set enrol_where = 'anywhere' where enrol_where = 'academy';

-- D2: the ladder asks III (exactly the rows found in §1)
update public.skill_prereqs q set level = 3
  from public.skills s, public.skills n, ladder_before_0150 l
 where s.id = q.skill_id and n.id = q.needs_skill_id and s.code = l.skill and n.code = l.needs and q.level = 4;
update public.skill_requirements r set level = 3
  from req_before_0150 b
 where r.subject_kind = 'hull' and r.subject_code = b.hull and r.skill_code = b.skill and r.level = 4;

-- D4 + D5: the new prerequisites
insert into public.skill_prereqs (skill_id, needs_skill_id, level, choice)
select s.id, n.id, v.level, 0
  from (values ('ARMED_MERCHANT', 'CARGO_STOWAGE', 5), ('PRIVATEERS', 'GUN_LAYING', 5),
               ('SURVEY_SHIPS', 'LOOKOUTS', 5), ('CONVOY_ESCORTS', 'HULL_UPKEEP', 5),
               ('WHOLESALE', 'FACTORAGE', 3), ('NEGOTIATION', 'HAGGLING', 3), ('FACTORAGE', 'ACCOUNTING', 3),
               ('PURSERSHIP', 'ACCOUNTING', 1), ('BROKERAGE', 'ACCOUNTING', 2), ('CREW_DRILL', 'SEAMANSHIP', 2),
               ('PROVISIONING', 'SEAMANSHIP', 2), ('CELESTIAL_NAV', 'NAVIGATION', 5), ('WEATHER_LORE', 'NAVIGATION', 3),
               ('LIGHT_AIR', 'NAVIGATION', 2), ('ETIQUETTE', 'RECRUITING', 2), ('PATRONAGE', 'ETIQUETTE', 3),
               ('LEADERSHIP', 'COMMAND', 1), ('HOSPITALITY', 'COMMAND', 1)) v(skill, needs, level)
  join public.skills s on s.code = v.skill
  join public.skills n on n.code = v.needs
on conflict do nothing;

-- D4 + D5: the effect rows
insert into public.skill_effects (skill_code, scope, stat, pct_per_level, role, tech) values
  ('ARMED_MERCHANT', 'ship',    'durability',      2, 'trade',    'T2'),
  ('PRIVATEERS',     'ship',    'reach',           2, 'combat',   'T2'),
  ('SURVEY_SHIPS',   'ship',    'speed',           1, 'explorer', 'T2'),
  ('CONVOY_ESCORTS', 'ship',    'armour',          2, 'support',  'T2'),
  ('WHOLESALE',      'company', 'TRADE_CAP',       3, null, null),
  ('NEGOTIATION',    'company', 'SPREAD',          2, null, null),
  ('FACTORAGE',      'house',   'standing_routes', 1, null, null),
  ('PURSERSHIP',     'house',   'crew_wage',       3, null, null),
  ('BROKERAGE',      'house',   'profit_tax',      5, null, null),
  ('CREW_DRILL',     'fitting', 'hands',           3, null, null),
  ('PROVISIONING',   'company', 'ENDURANCE',       3, null, null),
  ('CELESTIAL_NAV',  'company', 'SPEED',           1, null, null),
  ('WEATHER_LORE',   'house',   'storm_damage',    4, null, null),
  ('LIGHT_AIR',      'house',   'calm_delay',      5, null, null),
  ('RECRUITING',     'house',   'captain_wage',    5, null, null),
  ('ETIQUETTE',      'house',   'crew_hire',       4, null, null),
  ('PATRONAGE',      'house',   'influence',       4, null, null),
  ('LEADERSHIP',     'house',   'captain_xp',      5, null, null),
  ('HOSPITALITY',    'house',   'homesick',        2, null, null)
on conflict do nothing;
analyze public.skill_effects;
analyze public.skill_prereqs;
analyze public.skill_profile;

-- ── 4. THE RE-CUTS (hunks: old = verbatim from the live bodies; new = what replaces it) ─────────
create temp table hunks_0150 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0150 values
('public.skill_taught_at(uuid, uuid)', 1,
$h$    when pr.enrol_where = 'none' then null
$h$,
$h$    when pr.enrol_where = 'none' then null
    -- 0150 (K1, D3): the general skills are enrolled in ANY port (EVE's Skills on Demand); a line's hull
    -- skills stay at that line's build yards, below.
    when pr.enrol_where = 'anywhere' then null
$h$),
('public.skill_taught_place(uuid)', 1,
$h$           when 'academy' then 'any academy'
$h$,
$h$           when 'academy' then 'any academy'
           when 'anywhere' then 'any port'   -- 0150 (K1, D3)
$h$),
('world.ship_budget(uuid)', 1,
$h$  v_drill numeric;
$h$,
$h$  v_drill numeric;
  v_hands numeric;   -- 0150: Crew Drill
$h$),
('world.ship_budget(uuid)', 2,
$h$         coalesce(sum(sb.pct) filter (where sb.stat = 'high_hands'), 0)
    into v_deck, v_drill
$h$,
$h$         coalesce(sum(sb.pct) filter (where sb.stat = 'high_hands'), 0),
         coalesce(sum(sb.pct) filter (where sb.stat = 'hands'), 0)   -- 0150 (K1, D5): Crew Drill
    into v_deck, v_drill, v_hands
$h$),
('world.ship_budget(uuid)', 3,
$h$  if v_deck = 0 and v_drill = 0 then
$h$,
$h$  if v_deck = 0 and v_drill = 0 and v_hands = 0 then
$h$),
('world.ship_budget(uuid)', 4,
$h$                                       'max', v_bud->'hands'->'max'));
$h$,
$h$                                       -- 0150 (K1, D5): CREW DRILL raises the Hands max (× (1 + % / 100),
                                       -- floored), as Deck Management raises the Deck max
                                       'max', case when v_hands = 0 then v_bud->'hands'->'max'
                                                   else to_jsonb(floor(public.skill_scale((v_bud->'hands'->>'max')::numeric, v_hands))::int) end));
$h$),
('public.player_skill_bonus(uuid, text)', 1,
$h$#variable_conflict use_column
begin
  return (
$h$,
$h$#variable_conflict use_column
begin
  -- 0150 (K1): WHILE skills_bite IS ON, every skill's company effect counts — the four live ones and the
  -- new ones (Wholesale, Negotiation, Provisioning, Celestial Navigation) alike …
  if public.skills_bite_on() then
    return (select coalesce(sum(e.pct_per_level * public.skill_level(p_player, e.skill_code)), 0) / 100.0
              from public.skill_effects e
             where e.scope = 'company' and e.stat = upper(p_effect));
  end if;
  -- … and while it is off, only the four LIVE skills' (live since 0016 — skills.effect names them, the
  -- join below), exactly as before: they were never gated. PL/pgSQL branches, both plans cached.
  return (
$h$),
('public.player_skill_bonus(uuid, text)', 2,
$h$    from public.skill_effects e
   where e.scope = 'company' and e.stat = upper(p_effect)
  );
$h$,
$h$    from public.skill_effects e
    join public.skills sk on sk.code = e.skill_code and sk.effect <> 'NONE'   -- 0150: the live four only
   where e.scope = 'company' and e.stat = upper(p_effect)
  );
$h$),
('world.skills()', 1,
$h$               'takes_effect', (coalesce(ce.stat, 'NONE') = any(v_read))
$h$,
$h$               'takes_effect', (coalesce(ce.stat, 'NONE') = any(v_read)
                                -- 0150: and the switch that player_skill_bonus reads for it (the live
                                -- four are never gated) — the Academy never says a skill works while it does not
                                and (s.effect <> 'NONE' or public.skills_bite_on()))
$h$),
('public.skill_effect_words(text, numeric)', 1,
$h$                     when 'high_hands'    then 'Hands for High fittings'
$h$,
$h$                     when 'high_hands'    then 'Hands for High fittings'
                     when 'hands'         then 'Hands'   -- 0150: Crew Drill
$h$);

create or replace function pg_temp.recut_0150(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := replace(pg_get_functiondef(p_fn::regprocedure), E'\r', '');
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0150 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0150(v_def, h.old);
    if v_n <> 1 then
      raise exception '0150 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0150(fn) from defs_before_0150 order by fn;

-- ── 5. THE COMPARISONS (old body vs new, one statement each), dark and lit ─────────────────────
create or replace function pg_temp.compare_0150()
returns jsonb
language plpgsql
as $$
begin
  return jsonb_build_object(
    'company', (select jsonb_build_object('n', count(*), 'bad', count(*) filter (where z.a is distinct from z.b),
                                          'nonzero', count(*) filter (where z.a <> 0))
                  from (select public.player_skill_bonus(p.id, e.eff) as a, pg_temp.player_skill_bonus_before_0150(p.id, e.eff) as b
                          from public.players p
                         cross join (values ('ENDURANCE'), ('SPEED'), ('TRADE_CAP'), ('SPREAD')) e(eff)) z),
    'budgets', (select jsonb_build_object('n', count(*), 'bad', count(*) filter (where z.a::text is distinct from z.b::text))
                  from (select world.ship_budget(s.id) as a, pg_temp.ship_budget_before_0150(s.id) as b from public.ships s) z));
end $$;

create temp table proven_0150 (k text primary key, v jsonb) on commit drop;
insert into proven_0150 values ('dark', pg_temp.compare_0150());
do $$
declare
  r jsonb;
begin
  begin
    update public.world_config set value = 'true'::jsonb where key = 'skills_bite';
    r := pg_temp.compare_0150();
    raise exception 'LIT_ROLLBACK_0150';
  exception when others then
    if sqlerrm <> 'LIT_ROLLBACK_0150' then raise; end if;
  end;
  insert into proven_0150 values ('lit', r);
end $$;

create temp table academy_after_0150 on commit drop as
select world.skills() as v;

create temp table taught_after_0150 on commit drop as
select b.*, public.skill_taught_at(b.skill_id, b.port_id) as now_answer,
       (select pr.enrol_where from public.skill_profile pr where pr.skill_id = b.skill_id) as now_where
  from taught_before_0150 b;

-- THE PROBE (own throw-away houses, rolled back)
create or replace function pg_temp.probe_0150()
returns jsonb
language plpgsql
as $$
declare
  v_port    text := (select p.code from public.ports p
                      where p.kind = 'HARBOUR'
                        and not exists (select 1 from public.port_buildings b where b.port_id = p.id and b.kind in ('academy', 'building_yard'))
                      order by p.code limit 1);
  v_p       uuid;
  v_pf      uuid;
  v_ps      uuid;
  v_q       uuid;
  v_hull    text := (select cp.class_code from public.class_profile cp where cp.line_code = 'PRT' and cp.size = 4 order by cp.class_code limit 1);
  v_out     jsonb := '{}'::jsonb;
  v_e50     jsonb := '[]'::jsonb;
  v_r       jsonb;
  x         record;
  v_err     text;
begin
  begin
    if public.skills_bite_on() then
      raise exception '0150 self-assert FAIL: skills_bite is on before the probe — this file ships it dark';
    end if;
    v_out := v_out || jsonb_build_object('port', v_port, 'hull', v_hull);
    -- P: a company docked at a harbour with no academy and no build yard
    v_p := public.new_house('00000000-0150-4000-8000-000000000001', 'Casa da Prova 0150 P', 'PRT', v_port);
    select id into v_pf from public.fleets where player_id = v_p;
    select id into v_ps from public.ships where fleet_id = v_pf;
    perform public.credit(v_p, 'PROBE_0150', 10000000);
    -- D3: a general skill enrolled at a port with no academy; a line hull skill still refused there
    v_out := v_out || jsonb_build_object(
      'gunnery_before', (select b.answer->>'code' from taught_before_0150 b join public.ports p on p.id = b.port_id
                          where b.code = 'GUNNERY' and p.code = v_port),
      'gunnery', public.skill_enroll_for(v_p, 'GUNNERY', v_pf),
      'prt_small', public.skill_enroll_for(v_p, 'PRT_SMALL', v_pf));
    -- D1: fifty levels queue, the fifty-first is refused with figures
    insert into public.skill_sp (player_id, skill_id, sp)
    select v_p, s.id, 0 from public.skills s
     where s.code in ('LOOKOUTS', 'CELESTIAL_NAV', 'PROVISIONING', 'CREW_DRILL', 'FACTORAGE', 'WHOLESALE', 'NEGOTIATION')
    on conflict do nothing;
    for x in select c.code, l.lvl
               from unnest(array['NAVIGATION', 'SEAMANSHIP', 'ACCOUNTING', 'HAGGLING', 'LOOKOUTS', 'CELESTIAL_NAV',
                                 'PROVISIONING', 'CREW_DRILL', 'FACTORAGE', 'WHOLESALE']) with ordinality c(code, o)
              cross join generate_series(1, 5) l(lvl)
              order by c.o, l.lvl loop
      v_e50 := v_e50 || jsonb_build_array(jsonb_build_object('code', x.code, 'level', x.lvl));
    end loop;
    v_out := v_out || jsonb_build_object(
      'q50_refusal', public.skill_queue_refusal(v_p, v_e50),
      'q51_refusal', public.skill_queue_refusal(v_p, v_e50 || '[{"code": "NEGOTIATION", "level": 1}]'::jsonb));
    -- the verb itself takes all fifty (its own statement, so the count below sees what it wrote)
    v_out := v_out || jsonb_build_object('q50_set', public.skill_queue_set_for(v_p, v_e50)->'ok');
    v_out := v_out || jsonb_build_object('q50_rows', (select count(*) from public.skill_queue where player_id = v_p));
    delete from public.skill_queue where player_id = v_p;

    -- Q: the ladder at III, and T2's support skill at V
    v_q := public.new_house('00000000-0150-4000-8000-000000000002', 'Casa da Prova 0150 Q', 'PRT');
    insert into public.player_skills (player_id, skill_id, level)
    select v_q, s.id, x2.lvl from (values ('PRT_SMALL', 5), ('PRT_LIGHT', 5), ('PRT_MEDIUM', 3), ('MERCHANT_SHIPS', 5)) x2(code, lvl)
      join public.skills s on s.code = x2.code;
    insert into public.skill_sp (player_id, skill_id, sp)
    select v_q, s.id, 0 from public.skills s where s.code in ('PRT_HEAVY', 'ARMED_MERCHANT', 'CARGO_STOWAGE');
    v_out := v_out || jsonb_build_object(
      'heavy_queue', public.skill_queue_refusal(v_q, '[{"code": "PRT_HEAVY", "level": 1}]'::jsonb),
      'medium_prereq', (select q.level from public.skill_prereqs q join public.skills s on s.id = q.skill_id
                          join public.skills n on n.id = q.needs_skill_id where s.code = 'PRT_HEAVY' and n.code = 'PRT_MEDIUM'),
      'armed_queue', public.skill_queue_refusal(v_q, '[{"code": "ARMED_MERCHANT", "level": 1}]'::jsonb));
    update public.player_skills set level = 5 where player_id = v_q and skill_id = (select id from public.skills where code = 'MERCHANT_SHIPS');
    insert into public.player_skills (player_id, skill_id, level)
    select v_q, s.id, 5 from public.skills s where s.code = 'CARGO_STOWAGE';
    v_out := v_out || jsonb_build_object('armed_queue_met', public.skill_queue_refusal(v_q, '[{"code": "ARMED_MERCHANT", "level": 1}]'::jsonb));
    -- the heavy hull's requirements, lit: with Medium III, Heavy I and its role skill I nothing is unmet
    insert into public.player_skills (player_id, skill_id, level)
    select v_q, s.id, 1 from public.skills s where s.code = 'PRT_HEAVY'
    on conflict (player_id, skill_id) do nothing;
    insert into public.player_skills (player_id, skill_id, level)
    select v_q, s.id, r.level from public.skill_requirements r join public.skills s on s.code = r.skill_code
     where r.subject_kind = 'hull' and r.subject_code = v_hull and r.skill_code !~ '^PRT_'
    on conflict (player_id, skill_id) do update set level = greatest(public.player_skills.level, excluded.level);

    -- P holds the new company / fitting skills: DARK they change nothing
    insert into public.player_skills (player_id, skill_id, level)
    select v_p, s.id, x3.lvl from (values ('ACCOUNTING', 2), ('WHOLESALE', 3), ('PROVISIONING', 2), ('CELESTIAL_NAV', 1),
                                          ('NEGOTIATION', 2), ('CREW_DRILL', 5)) x3(code, lvl)
      join public.skills s on s.code = x3.code
    on conflict (player_id, skill_id) do update set level = excluded.level;
    v_out := v_out || jsonb_build_object('dark', jsonb_build_object(
      'trade_cap', public.player_skill_bonus(v_p, 'TRADE_CAP'), 'endurance', public.player_skill_bonus(v_p, 'ENDURANCE'),
      'speed', public.player_skill_bonus(v_p, 'SPEED'), 'spread', public.player_skill_bonus(v_p, 'SPREAD'),
      'budget', world.ship_budget(v_ps),
      'wholesale_takes', (select s->'takes_effect' from jsonb_array_elements(world.skills()->'skills') s where s->>'code' = 'WHOLESALE'),
      'heavy_unmet', (select count(*) from public.requirements_unmet(v_q, 'hull', v_hull)),
      'heavy_reqs', (select count(*) from public.skill_requirements r where r.subject_kind = 'hull' and r.subject_code = v_hull)));
    -- LIT (inside this rolled-back block)
    update public.world_config set value = 'true'::jsonb where key = 'skills_bite';
    v_out := v_out || jsonb_build_object('lit', jsonb_build_object(
      'trade_cap', public.player_skill_bonus(v_p, 'TRADE_CAP'), 'endurance', public.player_skill_bonus(v_p, 'ENDURANCE'),
      'speed', public.player_skill_bonus(v_p, 'SPEED'), 'spread', public.player_skill_bonus(v_p, 'SPREAD'),
      'budget', world.ship_budget(v_ps),
      'bonuses', world.ship_view(v_ps)->'bonuses',
      'wholesale_takes', (select s->'takes_effect' from jsonb_array_elements(world.skills()->'skills') s where s->>'code' = 'WHOLESALE'),
      'heavy_unmet', (select coalesce(jsonb_agg(u.skill_code), '[]'::jsonb) from public.requirements_unmet(v_q, 'hull', v_hull) u)));
    update public.player_skills set level = 2 where player_id = v_q and skill_id = (select id from public.skills where code = 'PRT_MEDIUM');
    v_out := v_out || jsonb_build_object('lit_medium_ii_unmet',
      (select coalesce(jsonb_agg(jsonb_build_object('skill', u.skill_code, 'have', u.have, 'need', u.need)), '[]'::jsonb)
         from public.requirements_unmet(v_q, 'hull', v_hull) u));
    v_out := v_out || jsonb_build_object('pcts', jsonb_build_object(
      'accounting', (select pct_per_level from public.skill_effects where skill_code = 'ACCOUNTING' and scope = 'company'),
      'wholesale', (select pct_per_level from public.skill_effects where skill_code = 'WHOLESALE' and scope = 'company'),
      'provisioning', (select pct_per_level from public.skill_effects where skill_code = 'PROVISIONING' and scope = 'company'),
      'celestial', (select pct_per_level from public.skill_effects where skill_code = 'CELESTIAL_NAV' and scope = 'company'),
      'negotiation', (select pct_per_level from public.skill_effects where skill_code = 'NEGOTIATION' and scope = 'company'),
      'crew_drill', (select pct_per_level from public.skill_effects where skill_code = 'CREW_DRILL' and scope = 'fitting')));
    raise exception 'PROBE_ROLLBACK_0150';
  exception when others then
    if sqlerrm <> 'PROBE_ROLLBACK_0150' then raise; end if;
  end;
  return v_out;
end $$;

create temp table probe_0150 (j jsonb) on commit drop;
do $$
declare
  v_try   int := 0;
  v_state text;
  v_msg   text;
begin
  loop
    v_try := v_try + 1;
    begin
      insert into probe_0150 select pg_temp.probe_0150();
      exit;
    exception when lock_not_available or deadlock_detected then
      get stacked diagnostics v_msg = message_text, v_state = returned_sqlstate;
    end;
    if v_try >= 5 then
      raise exception '0150 self-assert FAIL: LOCK CONTENTION, not a result — the probe could not get its locks in 5 tries (%: %). Re-run the push.',
        v_state, v_msg;
    end if;
    perform pg_sleep(0.2);
  end loop;
end $$;

-- THE TIMING (reported, not gated): the merchant fleet speed and supplies reads of player_skill_bonus
create temp table timing_0150 (what text, old_ms numeric, new_ms numeric) on commit drop;
do $$
declare
  v_t0  timestamptz;
  v_old numeric;
  v_new numeric;
  v_n   numeric;
  w     text;
begin
  foreach w in array array['SPEED', 'ENDURANCE'] loop
    v_old := null; v_new := null;
    for i in 1 .. 3 loop
      v_t0 := clock_timestamp();
      select sum(pg_temp.player_skill_bonus_before_0150(p.id, w)) into v_n from public.players p where p.is_npc;
      v_old := least(coalesce(v_old, 1e12), round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
      v_t0 := clock_timestamp();
      select sum(public.player_skill_bonus(p.id, w)) into v_n from public.players p where p.is_npc;
      v_new := least(coalesce(v_new, 1e12), round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
    end loop;
    insert into timing_0150 values (w, v_old, v_new);
  end loop;
end $$;

-- ── 6. SELF-ASSERT ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  b       record;
  d       record;
  h       record;
  p       record;
  v_def   text;
  v_n     int;
  v_bad   int;
  v_ex    text;
  v_pr    jsonb := (select j from probe_0150);
  v_dark  jsonb := (select v from proven_0150 where k = 'dark');
  v_lit   jsonb := (select v from proven_0150 where k = 'lit');
  v_old   jsonb := (select v from academy_before_0150);
  v_new   jsonb := (select v from academy_after_0150);
  v_k     text;
  v_tim   text;
  v_hmax  int;
begin
  select * into b from before_0150;
  if public.skills_bite_on() then
    raise exception '0150 self-assert FAIL: skills_bite is on — this file ships it dark';
  end if;

  -- (a) THE CATALOGUE
  if (select count(*) from public.skills) <> b.skills + 15 or (select count(*) from public.skills) <> 107
     or (select count(*) from public.skill_groups) <> b.groups + 1
     or (select ord from public.skill_groups where code = 'SOCIAL') <> b.groups + 1
     or (select count(*) from public.skill_effects) <> b.effects + 19
     or (select count(*) from public.skill_prereqs) <> b.prereqs + 18
     or (select count(*) from public.skill_requirements) <> b.requirements then
    raise exception '0150 self-assert FAIL: the catalogue counts are not the pre-image plus the rows written (skills %, groups %, effects %, prereqs %, requirements %)',
      (select count(*) from public.skills), (select count(*) from public.skill_groups), (select count(*) from public.skill_effects),
      (select count(*) from public.skill_prereqs), (select count(*) from public.skill_requirements);
  end if;
  if b.academy <> 33 or (select count(*) from public.skill_profile where enrol_where = 'academy') <> 0
     or (select count(*) from public.skill_profile where enrol_where = 'anywhere') <> b.academy + 15
     or exists (select 1 from new_skills_0150 n join public.skills s on s.code = n.code
                  join public.skill_profile pr on pr.skill_id = s.id
                 where s.effect <> 'NONE' or s.pct_per_level <> 0 or pr.enrol_where <> 'anywhere' or pr.group_code <> n.grp
                    or pr.rank <> n.rank or pr.line_code is not null)
     or (select sum(pr.rank) from new_skills_0150 n join public.skills s on s.code = n.code join public.skill_profile pr on pr.skill_id = s.id) <> 38
     or exists (select pr.group_code, pr.ord from public.skill_profile pr group by 1, 2 having count(*) > 1) then
    raise exception '0150 self-assert FAIL: enrolment / the new skills'' rows are not as written (academy before %, anywhere now %)',
      b.academy, (select count(*) from public.skill_profile where enrol_where = 'anywhere');
  end if;
  if (select md5(string_agg(to_jsonb(s)::text, '|' order by s.code)) from public.skills s
       where s.code not in (select code from new_skills_0150)) is distinct from b.skills_hash
     or (select md5(string_agg(to_jsonb(e)::text, '|' order by e.id)) from public.skill_effects e where e.id <= b.effects_max_id)
        is distinct from b.effects_hash then
    raise exception '0150 self-assert FAIL: an existing skill or skill effect row moved';
  end if;
  -- D2: exactly the 22 ladder prereqs and 22 hull requirement rows found at IV are at III; none is left at IV
  if (select count(*) from ladder_before_0150) <> 22 or (select count(*) from req_before_0150) <> 22
     or exists (select 1 from ladder_before_0150 l join public.skills s on s.code = l.skill join public.skills n on n.code = l.needs
                  join public.skill_prereqs q on q.skill_id = s.id and q.needs_skill_id = n.id where q.level <> 3)
     or exists (select 1 from req_before_0150 r join public.skill_requirements x
                  on x.subject_kind = 'hull' and x.subject_code = r.hull and x.skill_code = r.skill where x.level <> 3)
     or exists (select 1 from public.skill_prereqs q join public.skills s on s.id = q.skill_id join public.skills n on n.id = q.needs_skill_id
                 where q.level = 4 and ((s.code ~ '_HEAVY$' and n.code ~ '_MEDIUM$') or (s.code ~ '_CAPITAL$' and n.code ~ '_HEAVY$')))
     or (select md5(string_agg(format('%s/%s/%s/%s', r.subject_kind, r.subject_code, r.skill_code, r.level), '|'
                               order by r.subject_kind, r.subject_code, r.skill_code))
           from public.skill_requirements r
          where not exists (select 1 from req_before_0150 x where x.hull = r.subject_code and x.skill = r.skill_code and r.subject_kind = 'hull'))
        is distinct from b.req_rest_hash
     or exists (select 1 from prereq_rest_0150 o join public.skills s on s.code = o.skill join public.skills n on n.code = o.needs
                 where not exists (select 1 from public.skill_prereqs q where q.skill_id = s.id and q.needs_skill_id = n.id
                                     and q.level = o.level and q.choice = o.choice)) then
    raise exception '0150 self-assert FAIL: the ladder (D2) did not move exactly its 22 + 22 rows from IV to III, or another row moved';
  end if;
  if public.wc_int('skill_queue_max') <> greatest(50, b.queue_max) then
    raise exception '0150 self-assert FAIL: skill_queue_max is %, not %', public.wc_int('skill_queue_max'), greatest(50, b.queue_max);
  end if;

  -- (b) EVERY HOUSE'S COMPANY EFFECTS AND EVERY HULL'S BUDGET = THE PRE-IMAGE, dark and lit
  if (v_dark->'company'->>'bad')::int <> 0 or (v_lit->'company'->>'bad')::int <> 0
     or (v_dark->'budgets'->>'bad')::int <> 0 or (v_lit->'budgets'->>'bad')::int <> 0
     or (v_dark->'company'->>'n')::int <> 4 * (select count(*) from public.players)
     or (v_dark->'budgets'->>'n')::int <> (select count(*) from public.ships) then
    raise exception '0150 self-assert FAIL: a company effect or a budget moved (dark %, lit %)', v_dark, v_lit;
  end if;

  -- (c) THE ACADEMY: the 92 old skills answer as before but for the general skills' words and the
  --     changed prerequisite lists; the new skills do not take effect dark; queue_max; SOCIAL served
  select count(*), min(o->>'code') into v_bad, v_ex
    from jsonb_array_elements(v_old->'skills') o
    join jsonb_array_elements(v_new->'skills') n on n->>'code' = o->>'code'
   where (o - 'enrol_where' - 'prereqs') <> (n - 'enrol_where' - 'prereqs')
      or (o->>'enrol_where' is distinct from n->>'enrol_where'
          and not (o->>'enrol_where' = 'Taught at any academy.' and n->>'enrol_where' = 'Taught at any port.'))
      or (o->'prereqs' is distinct from n->'prereqs'
          and (o->>'code') not in (select l.skill from ladder_before_0150 l)
          and (o->>'code') not in ('ARMED_MERCHANT', 'PRIVATEERS', 'SURVEY_SHIPS', 'CONVOY_ESCORTS'));
  if v_bad <> 0 or jsonb_array_length(v_old->'skills') <> b.skills or jsonb_array_length(v_new->'skills') <> 107
     or (select count(*) from jsonb_array_elements(v_new->'skills') n where n->>'enrol_where' = 'Taught at any port.') <> 48
     or (select count(*) from jsonb_array_elements(v_new->'skills') n
          where n->>'code' in (select code from new_skills_0150) and (n->>'takes_effect')::boolean) <> 0
     or (select count(*) from jsonb_array_elements(v_new->'skills') n where (n->>'takes_effect')::boolean) <> 4
     or (v_new->>'queue_max')::int <> public.wc_int('skill_queue_max')
     or (v_new->'groups')->-1->>'code' <> 'SOCIAL' then
    raise exception '0150 self-assert FAIL: the Academy moved beyond the enrolment words and the changed prerequisites (% skill(s), e.g. %)', v_bad, v_ex;
  end if;

  -- (d) THE PLACE RULE: line_yard and none = the pre-image at every port; anywhere = null everywhere
  select count(*) into v_bad from taught_after_0150 t
   where (t.enrol_where in ('line_yard', 'none') and t.now_answer is distinct from t.answer)
      or (t.now_where = 'anywhere' and t.now_answer is not null)
      or (t.enrol_where = 'academy' and t.now_where <> 'anywhere');
  if v_bad <> 0 or (select count(*) from taught_after_0150 where enrol_where = 'academy' and answer->>'code' = 'E_NO_ACADEMY') = 0
     or (select count(*) from taught_after_0150 where enrol_where = 'line_yard' and now_answer is not null) = 0 then
    raise exception '0150 self-assert FAIL: the place rule moved beyond D3 (% (skill, port) answer(s)), or the comparison is vacuous', v_bad;
  end if;

  -- (e) NO HOUSE'S PROGRESS MOVED; every queue still legal; no T2 specialisation held without its support V
  if exists (select 1 from held_before_0150 hb left join public.player_skills ps
               on ps.player_id = hb.player_id and ps.skill_id = (select id from public.skills where code = hb.code)
              where ps.level is null or (hb.is_npc and ps.level <> hb.level) or ps.level < hb.level)
     or exists (select 1 from queue_before_0150 q join public.skill_queue x on x.player_id = q.player_id and x.pos = q.pos
                  join public.skills s on s.id = x.skill_id
                 where s.code = q.code and x.to_level = q.to_level and x.finishes_at <> q.finishes_at)
     or exists (select 1 from sp_before_0150 o left join public.skill_sp x
                  on x.player_id = o.player_id and x.skill_id = (select id from public.skills where code = o.code)
                 where x.sp is null or x.sp < o.sp) then
    raise exception '0150 self-assert FAIL: a house''s level, queue finish or skill points moved';
  end if;
  select count(*) into v_bad from (select distinct q.player_id from public.skill_queue q where q.finishes_at > now()) hq
   where public.skill_queue_refusal(hq.player_id, public.skill_queue_now(hq.player_id)) is not null;
  if v_bad <> 0 then
    raise exception '0150 self-assert FAIL: % house(s) hold a queue this file made illegal', v_bad;
  end if;
  select count(*) into v_bad
    from (values ('ARMED_MERCHANT', 'CARGO_STOWAGE'), ('PRIVATEERS', 'GUN_LAYING'), ('SURVEY_SHIPS', 'LOOKOUTS'),
                 ('CONVOY_ESCORTS', 'HULL_UPKEEP')) t(spec, support)
    join public.skills s on s.code = t.spec
    join public.players pl on exists (select 1 from public.player_skills ps where ps.player_id = pl.id and ps.skill_id = s.id)
                           or exists (select 1 from public.skill_queue q where q.player_id = pl.id and q.skill_id = s.id)
   where public.skill_level(pl.id, t.support) < 5;
  if v_bad <> 0 then
    raise exception '0150 self-assert FAIL: % house(s) hold or queue a T2 specialisation without its support skill at V — convert them before D4 tightens it', v_bad;
  end if;

  -- (f) THE PROBE
  v_hmax := (v_pr->'dark'->'budget'->'hands'->>'max')::int;
  if coalesce(v_pr->>'port' is null or v_pr->>'hull' is null
     or v_pr->>'gunnery_before' is distinct from 'E_NO_ACADEMY'
     or (v_pr->'gunnery'->>'ok')::boolean is distinct from true
     or v_pr->'prt_small'->>'error_code' is distinct from 'E_NOT_TAUGHT_HERE'
     or v_pr->'q50_refusal' is distinct from 'null'::jsonb
     or v_pr->'q51_refusal'->>'code' is distinct from 'E_SKILL_QUEUE_FULL'
     or v_pr->'q51_refusal'->'figures' is distinct from '{"have": 50, "need": 51, "unit": "levels"}'::jsonb
     or (v_pr->>'q50_rows')::int <> 50 or (v_pr->>'q50_set')::boolean is distinct from true
     or v_pr->'heavy_queue' is distinct from 'null'::jsonb or (v_pr->>'medium_prereq')::int <> 3
     or v_pr->'armed_queue'->>'code' is distinct from 'E_SKILL_PREREQ' or v_pr->'armed_queue'->>'needs' is distinct from 'CARGO_STOWAGE'
     or v_pr->'armed_queue_met' is distinct from 'null'::jsonb, true) then
    raise exception '0150 self-assert FAIL: enrolment / the queue / the ladder / the support skill did not answer as written: %', v_pr;
  end if;
  if coalesce((v_pr->'dark'->>'trade_cap')::numeric <> 2 * (v_pr->'pcts'->>'accounting')::numeric / 100
     or (v_pr->'dark'->>'endurance')::numeric <> 0 or (v_pr->'dark'->>'speed')::numeric <> 0 or (v_pr->'dark'->>'spread')::numeric <> 0
     or (v_pr->'dark'->>'wholesale_takes')::boolean
     or (v_pr->'lit'->>'trade_cap')::numeric <> (2 * (v_pr->'pcts'->>'accounting')::numeric + 3 * (v_pr->'pcts'->>'wholesale')::numeric) / 100
     or (v_pr->'lit'->>'endurance')::numeric <> 2 * (v_pr->'pcts'->>'provisioning')::numeric / 100
     or (v_pr->'lit'->>'speed')::numeric <> 1 * (v_pr->'pcts'->>'celestial')::numeric / 100
     or (v_pr->'lit'->>'spread')::numeric <> 2 * (v_pr->'pcts'->>'negotiation')::numeric / 100
     or not (v_pr->'lit'->>'wholesale_takes')::boolean
     or v_hmax is null
     or (v_pr->'lit'->'budget'->'hands'->>'max')::int <> floor(v_hmax * (1 + 5 * (v_pr->'pcts'->>'crew_drill')::numeric / 100))::int
     or (v_pr->'lit'->'budget'->'hands'->>'max')::int <= v_hmax
     or v_pr->'lit'->'budget'->'deck' is distinct from v_pr->'dark'->'budget'->'deck'
     or (select count(*) from jsonb_array_elements(v_pr->'lit'->'bonuses') x
          where x->>'source' = 'Crew Drill V' and x->>'effect' = '+15% Hands') <> 1
     -- dark, no level counts (0135): every requirement of the hull is unmet, as before K1
     or (v_pr->'dark'->>'heavy_unmet')::int <> (v_pr->'dark'->>'heavy_reqs')::int or (v_pr->'dark'->>'heavy_reqs')::int < 3
     or v_pr->'lit'->'heavy_unmet' <> '[]'::jsonb
     or v_pr->'lit_medium_ii_unmet' is distinct from '[{"skill": "PRT_MEDIUM", "have": 2, "need": 3}]'::jsonb, true) then
    raise exception '0150 self-assert FAIL: the new effects did not stay dark, or did not add exactly their per cents lit: %', v_pr;
  end if;
  if exists (select 1 from public.players where auth_uid::text like '00000000-0150-4000-8000-00000000000%') or public.skills_bite_on() then
    raise exception '0150 self-assert FAIL: the probe world was not rolled back';
  end if;

  -- (g) THE RE-CUTS reverse to their pre-images; ACL / volatility / definer / config unmoved; the
  --     untouched bodies untouched
  for d in select * from defs_before_0150 order by fn loop
    v_def := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0150 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0150(v_def, h.new) <> 1 then
        raise exception '0150 self-assert FAIL: hunk % of % is not in the new body exactly once', h.n, d.fn;
      end if;
      v_def := replace(v_def, h.new, h.old);
    end loop;
    if v_def <> d.def then
      raise exception '0150 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef, coalesce(pr.proconfig::text, '') as cfg
      into p from pg_proc pr where pr.oid = d.fn::regprocedure;
    if p.acl <> d.acl or p.vol <> d.vol or p.secdef <> d.secdef or p.cfg <> d.cfg then
      raise exception '0150 self-assert FAIL: % changed its ACL, volatility, definer or config', d.fn;
    end if;
  end loop;
  for d in select * from untouched_before_0150 loop
    if replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '') <> d.def
       or coalesce((select pr.proacl::text from pg_proc pr where pr.oid = d.fn::regprocedure), '') <> d.acl then
      raise exception '0150 self-assert FAIL: % moved — it was to be left untouched', d.fn;
    end if;
  end loop;

  -- (h) D7 — NEVER: no injector, extractor, attribute remap or skill points for coin, in the catalogue
  --     or among the client's entry points; and no new entry point at all
  if exists (select 1 from public.skills s where s.code ~* 'inject|extract|remap|attribute' or s.name ~* 'inject|extract|remap|attribute')
     or exists (select 1 from public.client_rpc_entry_points() e where e.fn::text ~* 'inject|extract|remap|buy_sp|sp_for_coin') then
    raise exception '0150 self-assert FAIL: the catalogue or the RPC registry names an injector, extractor or remap (D7)';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> b.entry_points then
    raise exception '0150 self-assert FAIL: the client entry points moved (% → %)', b.entry_points, (select count(*) from public.client_rpc_entry_points());
  end if;
  if exists (select 1 from unnest(array['anon', 'authenticated']) r(role)
              where has_table_privilege(r.role, 'public.skill_effects', 'insert,update,delete')
                 or has_table_privilege(r.role, 'public.skill_profile', 'insert,update,delete')
                 or has_table_privilege(r.role, 'public.skill_prereqs', 'insert,update,delete')) then
    raise exception '0150 self-assert FAIL: a client role can write the skill catalogue';
  end if;

  select string_agg(format('%s %s ms → %s ms', what, old_ms, new_ms), '; ' order by what) into v_tim from timing_0150;

  raise notice '0150 self-assert ok: A SKILL IS LEARNED THE WAY EVE LEARNED TO TEACH IT (dark: skills_bite false). CATALOGUE: % skills in % groups (SOCIAL ord %), % effects, % prerequisites; D1 queue % levels; D2 % ladder prerequisites and % hull requirements IV → III, nothing else moved; D3 % general skills enrolled at any port (0 at an academy), line_yard unchanged at % (skill, port) pairs; D4 4 support-V prerequisites and 4 second T2 bonuses; D5 15 new skills (rank sum 38). SAME ANSWERS, old body vs new: % (house, company effect) pairs, % hull budgets — dark and lit, 0 differ; the Academy: % old skills read as before but for the enrolment words and % changed prerequisite lists; no new skill takes effect dark. PROGRESS: % skill rows, % queue entries, % enrolments untouched; every queue legal. PROBE (rolled back): Gunnery enrolled at % (it was E_NO_ACADEMY there), Portuguese Small Hulls refused there (E_NOT_TAUGHT_HERE); 50 levels queued, the 51st refused (E_SKILL_QUEUE_FULL 50 / 51); Medium Hulls III lets Heavy Hulls I queue and meets % (lit; Medium II leaves "PRT_MEDIUM 2 / 3" unmet); Armed Merchantmen needs Cargo Stowage V; dark Wholesale III / Provisioning II / Celestial Navigation I / Negotiation II / Crew Drill V change nothing; lit: trade limit % → %, supplies % → %, speed % → %, bargain % → %, Hands % → % (Crew Drill V, +15%%). BODIES: 6 reverse to their pre-images, 9 untouched; D7: no injector, extractor or remap; no new entry point. TIMING (merchants, fastest of 3, random_page_cost %; reported, not gated): %.',
    (select count(*) from public.skills), (select count(*) from public.skill_groups), (select ord from public.skill_groups where code = 'SOCIAL'),
    (select count(*) from public.skill_effects), (select count(*) from public.skill_prereqs), public.wc_int('skill_queue_max'),
    (select count(*) from ladder_before_0150), (select count(*) from req_before_0150), b.academy,
    (select count(*) from taught_after_0150 where enrol_where = 'line_yard'),
    v_dark->'company'->>'n', v_dark->'budgets'->>'n', b.skills,
    (select count(distinct l.skill) from ladder_before_0150 l) + 4,
    (select count(*) from held_before_0150), (select count(*) from queue_before_0150), (select count(*) from sp_before_0150),
    v_pr->>'port', v_pr->>'hull',
    v_pr->'dark'->>'trade_cap', v_pr->'lit'->>'trade_cap', v_pr->'dark'->>'endurance', v_pr->'lit'->>'endurance',
    v_pr->'dark'->>'speed', v_pr->'lit'->>'speed', v_pr->'dark'->>'spread', v_pr->'lit'->>'spread',
    v_hmax, v_pr->'lit'->'budget'->'hands'->>'max', current_setting('random_page_cost'), v_tim;
end $$;
