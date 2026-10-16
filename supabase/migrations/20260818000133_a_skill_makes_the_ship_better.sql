-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0133 — A SKILL MAKES THE SHIP BETTER  (what a level gives, what a hull or a fitting needs — DARK)
--        plus: 0127's empty gear level asks (item_level_asks) are retired
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY NOW ─────────────────────────────────────────────────────────────────────────────────────
-- docs/SHIPS_AND_SKILLS.md §8, step S11 "Skills II: effects & requirements (DARK)" (§5.2 the per-level
-- bonuses, §5.3 where they land, §4.4 / §6.2 requirements). The owner: *"skill systems like eve too"*.
-- 0131 put 92 skills in a queue that trains in real time; 88 of them do nothing yet. This file gives a
-- level its effect and lets a hull or a fitting NEED a skill — and ships every bit of it behind ONE
-- switch, `skills_bite`, false: until the owner throws it the world reads exactly as before.
--
-- ── WHAT SAYS THE OPPOSITE TODAY, NAMED ─────────────────────────────────────────────────────────
--   * public.skills.effect / pct_per_level (0016:57-65) is the only place a level's per cent lives, and
--     it admits one company effect per skill (ENDURANCE / SPEED / TRADE_CAP / SPREAD) — read by
--     public.player_skill_bonus (0016:97, re-cut 0131). A hull trait ("+4 % sighting per level on
--     Portuguese medium hulls") has nowhere to live.
--   * world.ship_stats (0124, cut by 0127 and 0132) = class base + mounted units + hull level: no skill.
--   * world.ship_budget (0132) = class Deck / Hands: no Deck Management, no Gun Drill.
--   * public.fleet_officer_bonus (0015, cut by 0127): officers' bonuses with no Command.
--   * public.assert_house_caps (0021, cut by 0107): the house hull cap is the flat knob `ship_max`.
--   * public.mount_fitting (0126, cut by 0127/0132) asks a fitting's SHIP LEVEL (public.item_level_asks,
--     0127:163-171, EMPTY) — "may I fit this" belongs to skills (§2); cmd.do_build asks no skill at all.
--   * world.skills (0027, cut by 0131) serves the Academy each skill's effect / pct_per_level from the skills
--     columns — a second home of "what a level gives" once skill_effects exists.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) public.skill_effects — ONE ROW PER PER-LEVEL BONUS (skill, scope, stat, pct per level, and an
--     optional line / size / role / tech filter). 160 rows: 4 COMPANY rows (the live four, mirrors of
--     skills.effect / pct_per_level, asserted equal); 132 HULL rows (each line's two traits, from
--     public.ship_lines.traits, on that line's hulls of that size — Capital Hulls on 5 and 6); 24 others
--     (§5.2: roles, Hull Upkeep, Damage Control, Rigging, Lookouts, Instruments, Cargo Stowage, the
--     gunnery five — ship stats; Deck Management and Gun Drill — fitting; Command — house).
--     data/skills.json `effects` + data/ship-lines.json `traits`; the world guard holds it to both.
-- (2) public.skill_requirements (subject_kind hull|item, subject_code, skill_code, level) — EMPTY: the
--     three live hulls and the twelve G1 items need nothing (§4.4, §6.2; asserted). S12 adds rows.
-- (3) THE ONE READING: world.skill_bonuses(player, ship) — every bonus her company's skills give this
--     hull (or, with no ship, the house: Command), by SOURCE, with the level, the per cent and the effect
--     in words. Nothing at all while skills_bite is off. world.skill_pct(player, ship, stat) is its sum.
--     The level is public.skill_level's (0107/0131 — the one reading of a level, queue included).
-- (4) THE ONE RULE OF A REQUIREMENT: public.requirements_unmet(player, kind, code) (nothing while dark);
--     public.requirements_met = none unmet; public.requirements_refusal = the sentence ("Nau needs
--     Portuguese Medium Hulls IV"). Refusal E_NEEDS_SKILL, with figures (level have / need).
-- (5) THE HUNKS (sliced from the LIVE bodies, LF-normalised, each asserted to occur once and to reverse
--     to its pre-image, ACLs unchanged):
--       world.ship_stats       (base + units) × (1 + Σ skill % / 100) + hull level — §5.3's order; the per
--                              cents ride in the units' CTE (one read, gated by the switch), rounded to scale
--       public.player_skill_bonus   reads skill_effects (scope company) — same arithmetic, same text
--       cmd.do_build           (door) E_NEEDS_SKILL after the country rule
--       public.mount_fitting   (core) E_NEEDS_SKILL first; Gun Drill on the new unit's Hands; the
--                              item_level_asks read (E_SHIP_LEVEL) removed
--       public.fleet_officer_bonus  × (1 + Command %) under the cap
--       public.assert_house_caps    the hull cap is public.house_ship_max (ship_max + Command ×
--                              command_hulls_per_level while lit)
--       world.ship_budget      Deck × (1 + Deck Management %) floored; High units' Hands × (1 − Gun Drill %)
--       world.ship_view        + `bonuses` (each bonus by source) — [] while dark
--       world.building_yard    + per hull `needs` (the door's own sentence), and `buildable` folds it in
--       world.workstation      + per item `needs` (the FIT refusal's own sentence)
--       world.skills           the Academy's effect / pct_per_level read from skill_effects (scope company)
--                              — the same values as text (asserted), one home
-- (6) item_level_asks DROPPED (asserted empty first; no live body names it after the re-cut — positive
--     control: mount_fitting's pre-image did). public.ship_fittings_retired_0132 is NOT touched here (its
--     drop needs ACCESS EXCLUSIVE on public.ships): a later small migration drops it, clock unwound.
-- (7) Knobs: skills_bite false (THE switch); command_hulls_per_level 1.
--
-- ── WHAT IT DELIBERATELY DOES NOT DO ────────────────────────────────────────────────────────────
-- Nothing a player can see moves while skills_bite is false: every stat, slot, budget, refusal, officer
-- bonus, cap, yard and workstation answer is the pre-image (asserted, every hull / player / fleet / yard).
-- The only served change is two NEW keys that are empty / null while dark: ship_view.bonuses = [] and
-- `needs` = null on yard hulls and workstation items. No new entry point, no client write, no cron. Not
-- given an effect yet, said plainly: the six specialisations (their T2 modules arrive with S15),
-- Shipwright's yard labour, Fleet Command, Refitting, Augmentation. world.snapshot's config.ship_max stays
-- the flat knob (a lit Command house may hold more than RANK prints — a client follow-up when lit).
-- Merchants get no exemption anywhere (no is_npc read in any new body): their fixed skills are the four
-- live ones, which carry only company effects, so a merchant's ship reads the same lit or dark (asserted).
--
-- ── COST (the arrivals sweep: 10 s budget; prod p95 8.7 s / max 11.8 s on 2026-10-17) ──────────────
-- DARK IS ~FREE: public.skills_bite_on() is an inlinable SQL read of world_config; every hot read gates its
-- skill lookup behind it as a ONE-TIME FILTER (ship_stats' units CTE, ship_budget's k, ship_view's bonuses) or a
-- CASE (fleet_officer_bonus, which also skips it when the officers' sum is 0), so while dark no skill
-- function is even called. The self-assert times the merchant reads twice per phase, keeps the faster,
-- and refuses dark > before × 1.15 + 50 ms. LIT costs more (timed in the receipt, rolled back) —
-- RE-MEASURE ON PROD BEFORE THROWING skills_bite: the arrivals budget is already tight.
--
-- ── LOCKS (db push holds every lock until this file commits) ───────────────────────────────────
-- Until §7 this file takes NO lock any live statement waits on: ACCESS SHARE on what it reads; its own
-- new tables (their FK to ship_lines takes SHARE ROW EXCLUSIVE on ship_lines — written by nothing live);
-- CREATE OR REPLACE FUNCTION (no table lock); world_config INSERT of two new keys. The skill_effects /
-- skill_requirements FKs to public.skills are NOT added early (SHARE ROW EXCLUSIVE on skills held to
-- commit). Every probe write is inside a rolled-back subtransaction (its table and row locks go with it;
-- the per-house ADVISORY lock public.fitting_lock takes for the probe's FITs is transaction-scoped and is
-- held to commit — on the probe's own throw-away house, which nothing else can name); the probe is
-- retried on 55P03 / 40P01 and fails as LOCK CONTENTION, never as a result.
--   (§1) every heavy pre-image read;  (§2-§4) knobs, tables, catalogue rows, functions, re-cuts;
--   (§5) the old bodies kept under pg_temp names;  (§6) every comparison, the probes, the timings;
--   (§7) LAST, ONE short retried step, LOCK ORDER fixed:
--          1. ACCESS EXCLUSIVE on public.item_kinds, NOWAIT, then public.item_level_asks → drop
--             item_level_asks (its FK triggers live on item_kinds);
--          2. SHARE ROW EXCLUSIVE on public.skills, NOWAIT → the two FKs to skills(code).
--        public.ships is NOT locked (beyond the ACCESS SHARE every read takes). WHY NO CYCLE: the live
--        RPCs that touch these (cmd.do_build: ships → item_kinds; cmd.do_fit / mount_fitting: ships →
--        item_kinds; skill verbs: skills, key-share only) take ACCESS SHARE / ROW SHARE and never wait on
--        anything this file holds before §7 (it holds no lock they need); and in §7 every lock is NOWAIT,
--        so this file never WAITS while holding one — a busy table is 55P03 at once, the step's subtxn
--        rolls back (releasing what it took), sleeps 0.2 s and retries (10 tries), then LOCK CONTENTION,
--        not a result. After it: catalogue reads only (ms), then the commit (item_kinds readers — FITs,
--        ship cards — queue for those ms). The clock need not be unwound for this file (DEPLOY_RUNBOOK's
--        unwind/wind is still the safe default).
--
-- SUPERSEDES, by hunks sliced from the LIVE bodies (LF-normalised), each asserted to occur exactly once
-- and to reverse to its pre-image, ACLs unchanged: world.ship_stats (0132), public.player_skill_bonus
-- (0131), cmd.do_build (0130), public.mount_fitting (0132), public.fleet_officer_bonus (0127),
-- public.assert_house_caps (0107), world.ship_budget (0132), world.ship_view (0132), world.building_yard
-- (0130), world.workstation (0068), world.skills (0131).
--
-- ROLLBACK: `update public.world_config set value = 'false'::jsonb where key = 'skills_bite'` — one UPDATE,
-- and every effect and requirement is off (the dark state this file proves is the pre-image). A full
-- forward revert: reverse the eleven bodies' hunks (old text in hunks_0133); drop world.skill_bonuses,
-- world.skill_pct, public.requirements_refusal / requirements_met / requirements_unmet,
-- public.house_ship_max, public.drilled_hands, public.skill_scale, public.skill_effect_words,
-- public.skill_level_word, public.skills_bite_on, skill_requirements, skill_effects. item_level_asks
-- (0127:163-171, empty) is not restored.
-- SAID PLAINLY, ONE RESIDUE OF A ROLLBACK: a company that grew past ship_max under Command while lit keeps
-- every hull it has (nothing is taken away), but with skills_bite false its cap is ship_max again, so any
-- later write that re-checks the cap on its ships — a hull transferred between fleets, a new hull — fails
-- E_SHIP_MAX until it is back under ship_max.
-- VERSION: 0133. Applies on prod head 0132.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);   -- never queue the arrivals sweep for long
end $guard$;

-- ── 0. HELPERS (pg_temp, gone at commit) ───────────────────────────────────────────────────────
-- Run a statement that takes a lock; a lock the live world holds (55P03 lock_timeout, 40P01 deadlock)
-- is not an answer: retry, then fail as LOCK CONTENTION. Returns the milliseconds it took.
create or replace function pg_temp.locked_0133(p_sql text, p_what text)
returns numeric
language plpgsql
as $$
declare
  v_try   int := 0;
  v_state text;
  v_msg   text;
  v_t0    timestamptz := clock_timestamp();
begin
  loop
    v_try := v_try + 1;
    begin
      execute p_sql;
      return round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
    exception when lock_not_available or deadlock_detected then
      get stacked diagnostics v_msg = message_text, v_state = returned_sqlstate;
    end;
    if v_try >= 10 then
      raise exception '0133 self-assert FAIL: LOCK CONTENTION, not a result — % could not get its locks in 10 tries (%: %). Re-run the push.',
        p_what, v_state, v_msg;
    end if;
    perform pg_sleep(0.2);
  end loop;
end $$;

-- ── 1. THE PRE-IMAGES (every heavy read happens here, before anything moves) ───────────────────
create temp table defs_before_0133 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl
  from unnest(array['world.ship_stats(uuid)',
                    'public.player_skill_bonus(uuid, text)',
                    'cmd.do_build(uuid, jsonb)',
                    'public.mount_fitting(uuid, text)',
                    'public.fleet_officer_bonus(uuid, text)',
                    'public.assert_house_caps(uuid, uuid)',
                    'world.ship_budget(uuid)',
                    'world.ship_view(uuid)',
                    'world.building_yard(uuid)',
                    'world.workstation(uuid, uuid)',
                    'world.skills()']) f(fn);

-- NOT re-cut: their bodies must come out of this file exactly as they went in.
create temp table untouched_before_0133 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl
  from unnest(array['world.ship_slots(uuid)', 'public.skill_level(uuid, text)',
                    'public.skill_level_at(uuid, text, timestamp with time zone)',
                    'world.ship_racks(uuid, jsonb)', 'public.class_budget(text)']) f(fn);

create temp table before_0133 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from public.item_level_asks) as level_asks,
       (select md5(string_agg(to_jsonb(s)::text, '|' order by s.code)) from public.skills s) as skills_hash,
       (select md5(string_agg(to_jsonb(c)::text, '|' order by c.code)) from public.ship_classes c) as classes_hash,
       (select md5(string_agg(to_jsonb(k)::text, '|' order by k.code)) from public.item_kinds k) as kinds_hash,
       (select md5(string_agg(to_jsonb(p)::text, '|' order by p.class_code)) from public.class_profile p) as profile_hash,
       (select md5(string_agg(to_jsonb(l)::text, '|' order by l.code)) from public.ship_lines l) as lines_hash;

-- every hull: its ten stats, budget and whole view, as found (§6 counts any that live play moved since)
create temp table hulls_before_0133 on commit drop as
select s.id as ship_id, p.is_npc,
       world.ship_stats(s.id) as stats, world.ship_budget(s.id) as budget, world.ship_view(s.id) as view
  from public.ships s
  join public.players p on p.id = s.player_id;

-- every company's four company effects, and every fleet's officer bonus by specialty
create temp table bonus_before_0133 on commit drop as
select p.id as player_id, e.eff, public.player_skill_bonus(p.id, e.eff) as b
  from public.players p
 cross join (values ('ENDURANCE'), ('SPEED'), ('TRADE_CAP'), ('SPREAD')) e(eff);
create temp table officer_before_0133 on commit drop as
select f.id as fleet_id, sp.specialty, public.fleet_officer_bonus(f.id, sp.specialty) as b
  from public.fleets f
 cross join (select distinct o.specialty from public.officers o) sp;

-- What the arrivals tick and a merchant card read per merchant hull — speed + hold, and the whole
-- ship — timed over every merchant hull, before (and in §6: after, dark; and lit, rolled back).
create temp table reads_0133 (phase text, what text, hulls bigint, ms numeric) on commit drop;
-- Each read is timed TWICE and the faster kept (the first pass also warms the plans), so one noisy pass
-- cannot fail the assert in §6 or hide a regression. Returns {what: ms}.
create or replace function pg_temp.reads_now_0133()
returns jsonb
language plpgsql
as $$
declare
  v_t0 timestamptz;
  v_a  numeric := null;
  v_b  numeric := null;
begin
  for i in 1 .. 2 loop
    v_t0 := clock_timestamp();
    perform voyage.ship_speed(h.ship_id), public.ship_hold_capacity(h.ship_id) from hulls_before_0133 h where h.is_npc;
    v_a := least(coalesce(v_a, 1e12), round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
    v_t0 := clock_timestamp();
    perform world.ship_view(h.ship_id) from hulls_before_0133 h where h.is_npc;
    v_b := least(coalesce(v_b, 1e12), round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
  end loop;
  return jsonb_build_object('speed+hold', v_a, 'ship_view', v_b);
end $$;
create or replace function pg_temp.time_reads_0133(p_phase text)
returns void
language plpgsql
as $$
declare
  v_n bigint := (select count(*) from hulls_before_0133 where is_npc);
begin
  insert into reads_0133 select p_phase, key, v_n, value::text::numeric from jsonb_each(pg_temp.reads_now_0133());
end $$;
select pg_temp.time_reads_0133('before');

-- ── 2. THE SWITCH, THE TABLES, THE CATALOGUE ROWS (data/skills.json, data/ship-lines.json) ─────
insert into public.world_config (key, value, description) values
  ('skills_bite', 'false'::jsonb,
   '0133: true = skills DO something — the per-level bonuses of public.skill_effects on ship stats, '
   'budgets and officers, the house hull cap from Command, and the requirements of public.skill_requirements '
   'on BUILD and FIT. false = every one of them is off and the world reads as before 0133 (proven by its '
   'self-assert). Shipped false (dark). The company effects of the four live skills are NOT gated (live since 0016).'),
  ('command_hulls_per_level', to_jsonb(1),
   '0133: hulls a company may keep beyond ship_max per level of Command (public.house_ship_max), while skills_bite is on.')
on conflict (key) do nothing;

create table if not exists public.skill_effects (
  id            bigint generated always as identity primary key,
  skill_code    text not null,      -- FK to skills(code) added in §7 (see LOCKS)
  scope         text not null check (scope in ('company', 'ship', 'fitting', 'house')),
  stat          text not null,
  pct_per_level numeric(5,2) not null check (pct_per_level > 0 and pct_per_level <= 10),
  line_code     text references public.ship_lines(code),
  size          int  check (size between 1 and 6),
  role          text check (role in ('trade', 'combat', 'explorer', 'support')),
  tech          text check (tech in ('T1', 'T2', 'F')),
  check ((scope = 'company') = (stat in ('ENDURANCE', 'SPEED', 'TRADE_CAP', 'SPREAD'))),
  check (scope <> 'ship' or stat in ('hold', 'speed', 'handling', 'durability', 'armour', 'attack', 'accuracy', 'reach', 'sighting')),
  check (scope <> 'fitting' or stat in ('deck', 'high_hands')),
  check (scope <> 'house' or stat = 'officer_bonus'),
  check (scope = 'ship' or (line_code is null and size is null and role is null and tech is null))
);
create unique index if not exists skill_effects_one_row_idx on public.skill_effects
  (skill_code, stat, coalesce(line_code, ''), coalesce(size, 0), coalesce(role, ''), coalesce(tech, ''));
comment on table public.skill_effects is
  '0133: WHAT ONE LEVEL OF A SKILL GIVES (docs/SHIPS_AND_SKILLS.md §5.2-5.3) — one row per bonus: scope company '
  '(the four live company effects, read by public.player_skill_bonus, never gated; skills.effect / pct_per_level '
  'are their mirrors), ship (a per cent on a world.ship_stats stat, optionally only on hulls of a line / size / '
  'role / tech), fitting (deck, high_hands: world.ship_budget), house (officer_bonus: public.fleet_officer_bonus). '
  'ship / fitting / house rows are read ONLY through world.skill_bonuses, and only while skills_bite is true. '
  'data/skills.json `effects` + data/ship-lines.json `traits` (hull skills); the world guard holds it to both.';
alter table public.skill_effects enable row level security;
revoke all on table public.skill_effects from public, anon, authenticated;

create table if not exists public.skill_requirements (
  subject_kind text not null check (subject_kind in ('hull', 'item')),
  subject_code text not null,
  skill_code   text not null,      -- FK to skills(code) added in §7 (see LOCKS)
  level        int  not null check (level between 1 and 5),
  primary key (subject_kind, subject_code, skill_code)
);
comment on table public.skill_requirements is
  '0133: WHAT A HULL (BUILD) OR AN ITEM (FIT) NEEDS OF THE COMPANY — a skill at a level. Read ONLY by '
  'public.requirements_unmet (cmd.do_build, public.mount_fitting, world.building_yard, world.workstation), and '
  'only while skills_bite is true. Empty in S11: the three live hulls and the twelve G1 items need nothing. '
  'data/skills.json `requirements`; the world guard holds it to the file.';
alter table public.skill_requirements enable row level security;
revoke all on table public.skill_requirements from public, anon, authenticated;

-- the HULL rows: every line's two traits, on that line's hulls of that size (hull = durability)
insert into public.skill_effects (skill_code, scope, stat, pct_per_level, line_code, size)
select sl.code || '_' || z.suffix, 'ship',
       case t->>'stat' when 'hull' then 'durability' else t->>'stat' end,
       (t->>'pct')::numeric, sl.code, z.size
  from public.ship_lines sl
 cross join jsonb_array_elements(sl.traits) t
 cross join (values ('SMALL', 1), ('LIGHT', 2), ('MEDIUM', 3), ('HEAVY', 4), ('CAPITAL', 5), ('CAPITAL', 6)) z(suffix, size)
 order by sl.code, z.size, t->>'stat'
on conflict do nothing;

-- the rest (data/skills.json `effects`)
insert into public.skill_effects (skill_code, scope, stat, pct_per_level, role, tech) values
  ('MERCHANT_SHIPS',  'ship',    'hold',          3, 'trade',    null),
  ('SHIPS_OF_WAR',    'ship',    'attack',        3, 'combat',   null),
  ('EXPLORERS',       'ship',    'sighting',      4, 'explorer', null),
  ('EXPLORERS',       'ship',    'speed',         1, 'explorer', null),
  ('ESCORT_SUPPORT',  'ship',    'durability',    4, 'support',  null),
  ('ARMED_MERCHANT',  'ship',    'hold',          4, 'trade',    'T2'),
  ('PRIVATEERS',      'ship',    'attack',        4, 'combat',   'T2'),
  ('SURVEY_SHIPS',    'ship',    'sighting',      4, 'explorer', 'T2'),
  ('CONVOY_ESCORTS',  'ship',    'durability',    4, 'support',  'T2'),
  ('FAMOUS_SHIPS',    'ship',    'durability',    2, null,       'F'),
  ('SEAMANSHIP',      'company', 'ENDURANCE',     6, null,       null),
  ('HULL_UPKEEP',     'ship',    'durability',    4, null,       null),
  ('DAMAGE_CONTROL',  'ship',    'armour',        3, null,       null),
  ('DECK_MANAGEMENT', 'fitting', 'deck',          5, null,       null),
  ('NAVIGATION',      'company', 'SPEED',         4, null,       null),
  ('RIGGING',         'ship',    'handling',      3, null,       null),
  ('LOOKOUTS',        'ship',    'sighting',      5, null,       null),
  ('INSTRUMENTS',     'ship',    'sighting',      2, null,       null),
  ('ACCOUNTING',      'company', 'TRADE_CAP',     5, null,       null),
  ('HAGGLING',        'company', 'SPREAD',        5, null,       null),
  ('CARGO_STOWAGE',   'ship',    'hold',          3, null,       null),
  ('GUNNERY',         'ship',    'attack',        3, null,       null),
  ('GUN_LAYING',      'ship',    'accuracy',      4, null,       null),
  ('LONG_GUNS',       'ship',    'reach',         4, null,       null),
  ('SHORT_GUNS',      'ship',    'attack',        2, null,       null),
  ('BOARDING',        'ship',    'attack',        2, null,       null),
  ('GUN_DRILL',       'fitting', 'high_hands',    4, null,       null),
  ('COMMAND',         'house',   'officer_bonus', 2, null,       null)
on conflict do nothing;
create index if not exists skill_effects_skill_idx on public.skill_effects (skill_code);
analyze public.skill_effects;

-- ── 3. THE NEW FUNCTIONS ───────────────────────────────────────────────────────────────────────
create or replace function public.skills_bite_on()
returns boolean
language sql
stable
as $$
  -- 0133: THE switch. A plain SQL read of world_config — no SET, no SECURITY DEFINER, no wc() call — so the
  -- planner INLINES it, and in a SQL body with no column of its own it is a ONE-TIME FILTER (evaluated once,
  -- and when false the gated lookup below it never runs). Missing row = off.
  select coalesce((select c.value = 'true'::jsonb from public.world_config c where c.key = 'skills_bite'), false)
$$;
comment on function public.skills_bite_on() is
  '0133: THE switch of skill effects and requirements (world_config skills_bite), inlinable. Server-only.';
revoke all on function public.skills_bite_on() from public, anon, authenticated;

create or replace function public.skill_level_word(p_level int)
returns text
language sql
immutable
as $$
  -- 0133: a skill level as the player reads it — I … V (docs/SHIPS_AND_SKILLS.md: "needs X IV").
  select coalesce((array['I', 'II', 'III', 'IV', 'V'])[p_level], p_level::text)
$$;
comment on function public.skill_level_word(int) is '0133: I … V. Server-only.';
revoke all on function public.skill_level_word(int) from public, anon, authenticated;

create or replace function public.skill_effect_words(p_stat text, p_pct numeric)
returns text
language sql
immutable
as $$
  -- 0133: ONE bonus in words, as the ship panel prints it (docs/WORDS.md): "+12% sighting",
  -- "+6% cargo space", "−8% Hands for High fittings". Gun Drill is the one per cent that is taken OFF.
  select case when p_stat = 'high_hands' then '−' else '+' end || trim_scale(p_pct)::text || '% ' ||
         case p_stat when 'hold'          then 'cargo space'
                     when 'durability'    then 'hull'
                     when 'deck'          then 'Deck'
                     when 'high_hands'    then 'Hands for High fittings'
                     when 'officer_bonus' then 'officer bonuses'
                     else p_stat end
$$;
comment on function public.skill_effect_words(text, numeric) is '0133: a skill bonus in words. Server-only.';
revoke all on function public.skill_effect_words(text, numeric) from public, anon, authenticated;

create or replace function public.skill_scale(p_x numeric, p_pct numeric)
returns numeric
language sql
immutable
as $$
  -- 0133: x × (1 + pct / 100) — and x ITSELF, untouched (same value, same text), when no per cent
  -- applies. The one formula every skill per cent is applied through (ship_stats, ship_budget,
  -- fleet_officer_bonus), so "dark = the pre-image to the digit" holds by construction.
  select case when coalesce(p_pct, 0) = 0 then p_x else p_x * ((100 + p_pct) * 0.01) end
$$;
comment on function public.skill_scale(numeric, numeric) is '0133: the one skill-per-cent formula. Server-only.';
revoke all on function public.skill_scale(numeric, numeric) from public, anon, authenticated;

create or replace function public.drilled_hands(p_hands int, p_rack text, p_pct numeric)
returns int
language sql
immutable
as $$
  -- 0133: GUN DRILL — what one unit needs of Hands: a High unit × (1 − pct / 100), rounded; any other
  -- unit, or no drill, exactly its item_profile.hands. Read by world.ship_budget (what is mounted) and
  -- public.mount_fitting (the unit being fitted), so both count a unit the same way.
  select case when p_rack = 'high' and coalesce(p_pct, 0) > 0
              then round(p_hands * (100 - least(p_pct, 100)) / 100.0)::int
              else p_hands end
$$;
comment on function public.drilled_hands(int, text, numeric) is '0133: a unit''s Hands under Gun Drill. Server-only.';
revoke all on function public.drilled_hands(int, text, numeric) from public, anon, authenticated;

create or replace function world.skill_bonuses(p_player uuid, p_ship uuid)
returns table (stat text, scope text, skill_code text, level int, pct numeric, source text, effect text)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $sb$
begin
  -- 0133: THE ONE READING OF WHAT A COMPANY'S SKILLS GIVE — for one of its hulls (scopes ship and
  -- fitting, through the hull's line / size / role / tech), or with no hull for the company itself
  -- (scope house: Command). One row per bonus, BY SOURCE: the skill, its level (public.skill_level —
  -- the one reading, a finished queue entry included), the per cent (per level × level), "Portuguese
  -- Medium Hulls III" and "+12% sighting". NOTHING while skills_bite is off. Company effects (the
  -- live four) are not here: public.player_skill_bonus reads them, as it always has.
  -- Cheap for a merchant: her fixed skills are the live four, which carry only company effects, so
  -- the join below finds no row and no level is read — no merchant flag is read, no exemption.
  if p_player is null or not public.skills_bite_on() then
    return;
  end if;
  return query
  with held as (
    select ps.skill_id from public.player_skills ps where ps.player_id = p_player
    union
    select q.skill_id from public.skill_queue q where q.player_id = p_player and q.finishes_at <= now()
  ),
  prof as (
    select cp.line_code, cp.size, cp.role, cp.tech
      from public.ships s
      join public.ship_classes c on c.id = s.class_id
      left join public.class_profile cp on cp.class_code = c.code
     where s.id = p_ship
  )
  select e.stat, e.scope, sk.code, l.lvl, e.pct_per_level * l.lvl,
         sk.name || ' ' || public.skill_level_word(l.lvl),
         public.skill_effect_words(e.stat, e.pct_per_level * l.lvl)
    from held h
    join public.skills sk on sk.id = h.skill_id
    join public.skill_effects e on e.skill_code = sk.code and e.scope <> 'company'
    left join prof p on true
   cross join lateral (select public.skill_level(p_player, sk.code) as lvl) l
   where l.lvl > 0
     and case when p_ship is null then e.scope = 'house'
              else e.scope in ('ship', 'fitting') and exists (select 1 from prof) end
     and (e.line_code is null or e.line_code = p.line_code)
     and (e.size is null or e.size = p.size)
     and (e.role is null or e.role = p.role)
     and (e.tech is null or e.tech = p.tech)
   order by sk.code, e.stat;
end $sb$;
comment on function world.skill_bonuses(uuid, uuid) is
  '0133: THE one reading of skill bonuses, by source (empty while skills_bite is off). Read by world.ship_stats, '
  'world.ship_budget, world.ship_view (`bonuses`) and world.skill_pct. Server-only.';
revoke all on function world.skill_bonuses(uuid, uuid) from public, anon, authenticated;

create or replace function world.skill_pct(p_player uuid, p_ship uuid, p_stat text)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0133: the per cent a company's skills add to one stat of one hull (or, with no hull, of the company):
  -- the sum of world.skill_bonuses for that stat. 0 while skills_bite is off.
  select coalesce(sum(sb.pct), 0) from world.skill_bonuses(p_player, p_ship) sb where sb.stat = p_stat
$$;
comment on function world.skill_pct(uuid, uuid, text) is
  '0133: Σ world.skill_bonuses for one stat. Read by public.fleet_officer_bonus and public.mount_fitting. Server-only.';
revoke all on function world.skill_pct(uuid, uuid, text) from public, anon, authenticated;

create or replace function public.house_ship_max(p_player uuid)
returns int
language sql
stable
set search_path = public, pg_temp
as $$
  -- 0133: THE ONE READING OF A COMPANY'S HULL CAP — ship_max, plus command_hulls_per_level per level of
  -- Command while skills_bite is on. Exactly ship_max while dark.
  select public.wc_int('ship_max')
         + case when public.skills_bite_on()
                then public.skill_level(p_player, 'COMMAND') * public.wc_int('command_hulls_per_level')
                else 0 end
$$;
comment on function public.house_ship_max(uuid) is
  '0133: the house hull cap (ship_max + Command while lit). Read by public.assert_house_caps. Server-only.';
revoke all on function public.house_ship_max(uuid) from public, anon, authenticated;

create or replace function public.requirements_unmet(p_player uuid, p_kind text, p_code text)
returns table (skill_code text, skill_name text, have int, need int)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $ru$
begin
  -- 0133: THE ONE RULE OF A REQUIREMENT — every skill a hull (kind 'hull', BUILD) or an item (kind
  -- 'item', FIT) needs that the company does not yet have at the level asked, with what it has (the
  -- one reading of a level, public.skill_level). Nothing while skills_bite is off.
  if not public.skills_bite_on() then
    return;
  end if;
  return query
  select r.skill_code, sk.name, x.lvl, r.level
    from public.skill_requirements r
    join public.skills sk on sk.code = r.skill_code
   cross join lateral (select coalesce(public.skill_level(p_player, r.skill_code), 0) as lvl) x
   where r.subject_kind = p_kind and r.subject_code = p_code and x.lvl < r.level
   order by sk.name;
end $ru$;
comment on function public.requirements_unmet(uuid, text, text) is
  '0133: the one rule of skill requirements (empty while skills_bite is off). Server-only.';
revoke all on function public.requirements_unmet(uuid, text, text) from public, anon, authenticated;

create or replace function public.requirements_met(p_player uuid, p_kind text, p_code text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0133: may this company build this hull / fit this item — nothing unmet (public.requirements_unmet).
  select not exists (select 1 from public.requirements_unmet(p_player, p_kind, p_code))
$$;
comment on function public.requirements_met(uuid, text, text) is
  '0133: no requirement unmet. Read by cmd.do_build (door) and public.mount_fitting (core). Server-only.';
revoke all on function public.requirements_met(uuid, text, text) from public, anon, authenticated;

create or replace function public.requirements_refusal(p_player uuid, p_kind text, p_code text)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0133: THE SENTENCE — "Nau needs Portuguese Medium Hulls IV", "Suit of Sails needs Rigging II and
  -- Gunnery I" — or null when nothing is unmet. The refusal E_NEEDS_SKILL says it, and the build yard and
  -- the workshop serve it word for word: the client prints it, it rebuilds nothing.
  select case when count(*) > 0 then
           coalesce(case p_kind when 'hull' then (select c.name from public.ship_classes c where c.code = p_code)
                                when 'item' then (select k.name from public.item_kinds k where k.code = p_code) end,
                    p_code)
           || ' needs '
           || string_agg(u.skill_name || ' ' || public.skill_level_word(u.need), ' and ' order by u.skill_name)
         end
    from public.requirements_unmet(p_player, p_kind, p_code) u
$$;
comment on function public.requirements_refusal(uuid, text, text) is
  '0133: the E_NEEDS_SKILL sentence, or null. Read by cmd.do_build, public.mount_fitting, world.building_yard, '
  'world.workstation. Server-only.';
revoke all on function public.requirements_refusal(uuid, text, text) from public, anon, authenticated;

-- ── 4. THE HUNKS (old → new), sliced from the live bodies ───────────────────────────────────────
create temp table hunks_0133 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0133 values
-- world.ship_stats: (base + units) × (1 + Σ skill % / 100); the per cents ride in the units' own CTE
('world.ship_stats(uuid)', 1,
$h$    select e.stat, sum(e.delta) as delta
      from public.fitted_units f
      join public.item_effects e on e.item_code = f.item_code
     where f.ship_id = p_ship
     group by e.stat
  )
$h$,
$h$    -- 0133: and WHAT HER COMPANY'S SKILLS ADD, per stat, in per cent (world.skill_bonuses, the one
    -- reading), in the SAME CTE — no second CTE, no extra join: while skills_bite is off the second branch
    -- is a one-time filter (the lookup never runs) and every stat's pct is null. Measured: a separate
    -- materialized CTE cost the merchant reads +13 % dark; this shape costs one world_config read.
    select x.stat, sum(x.delta) as delta, sum(x.pct) as pct
      from (select e.stat, e.delta, null::numeric as pct
              from public.fitted_units f
              join public.item_effects e on e.item_code = f.item_code
             where f.ship_id = p_ship
            union all
            select sb.stat, null, sb.pct
              from public.ships s0
             cross join lateral world.skill_bonuses(s0.player_id, s0.id) sb
             where public.skills_bite_on() and s0.id = p_ship and sb.scope = 'ship') x
     group by x.stat
  )
$h$),
('world.ship_stats(uuid)', 2,
$h$                              b.base + coalesce(d.delta, 0)
$h$,
$h$                              -- 0133: (base + what is mounted) × (1 + Σ skill % / 100), §5.3's order, rounded
                              -- to the sum's own scale (the precision the stat is shown in) — and the
                              -- untouched sum wherever no skill adds (always, while dark).
                              case when d.pct is null then b.base + coalesce(d.delta, 0)
                                   else round(public.skill_scale(b.base + coalesce(d.delta, 0), d.pct),
                                              scale(b.base + coalesce(d.delta, 0))) end
$h$),
-- public.player_skill_bonus: the per cent is skill_effects' (scope company)
('public.player_skill_bonus(uuid, text)', 1,
$h$  select coalesce(sum(s.pct_per_level * public.skill_level(p_player, s.code)), 0) / 100.0
    from public.skills s
   where s.effect = upper(p_effect);
$h$,
$h$  -- 0133: the per-level per cent is public.skill_effects' (scope company) — the one home of what a
  -- level gives. skills.effect / pct_per_level stay as its mirrors (asserted equal), retired later.
  select coalesce(sum(e.pct_per_level * public.skill_level(p_player, e.skill_code)), 0) / 100.0
    from public.skill_effects e
   where e.scope = 'company' and e.stat = upper(p_effect);
$h$),
-- cmd.do_build (door): what the hull needs of the company
('cmd.do_build(uuid, jsonb)', 1,
$h$  if v_wrong is not null then
    raise exception 'E_WRONG_YARD: %', v_wrong using errcode = 'P0001';
  end if;
$h$,
$h$  if v_wrong is not null then
    raise exception 'E_WRONG_YARD: %', v_wrong using errcode = 'P0001';
  end if;
  -- 0133: WHAT THE HULL NEEDS OF THE COMPANY — public.requirements_met, the one rule (skill_requirements;
  -- nothing while skills_bite is off). The sentence and its figures are the rule's own.
  if not public.requirements_met(f.player_id, 'hull', c.code) then
    perform cmd.refuse('E_NEEDS_SKILL', public.requirements_refusal(f.player_id, 'hull', c.code),
      (select cmd.figures(u.have, u.need, 'level')
         from public.requirements_unmet(f.player_id, 'hull', c.code) u order by u.skill_name limit 1));
  end if;
$h$),
-- public.mount_fitting (core): requirements first; Gun Drill on the unit's Hands; item_level_asks gone
('public.mount_fitting(uuid, text)', 1,
$h$  v_lvl   int;
  v_ask   int;
$h$,
$h$  v_lvl   int;
$h$),
('public.mount_fitting(uuid, text)', 2,
$h$  perform public.fitting_lock(v_ship.player_id);
$h$,
$h$  perform public.fitting_lock(v_ship.player_id);
  -- 0133: WHAT THE ITEM NEEDS OF THE COMPANY that owns the hull — public.requirements_met, the one rule
  -- (nothing while skills_bite is off; the G1 items need nothing, so a merchant's loadout mounts as before).
  if not public.requirements_met(v_ship.player_id, 'item', k.code) then
    perform cmd.refuse('E_NEEDS_SKILL', public.requirements_refusal(v_ship.player_id, 'item', k.code),
      (select cmd.figures(u.have, u.need, 'level')
         from public.requirements_unmet(v_ship.player_id, 'item', k.code) u order by u.skill_name limit 1));
  end if;
$h$),
('public.mount_fitting(uuid, text)', 3,
$h$   where ip.item_code = k.code;
  select count(*) into v_used
$h$,
$h$   where ip.item_code = k.code;
  -- 0133: GUN DRILL — what this unit needs of Hands, counted as world.ship_budget counts it.
  v_hands := public.drilled_hands(v_hands, v_rack, world.skill_pct(v_ship.player_id, v_ship.id, 'high_hands'));
  select count(*) into v_used
$h$),
('public.mount_fitting(uuid, text)', 4,
$h$    v_lvl := public.level_in_force(coalesce((select sx.xp from public.ship_xp sx where sx.ship_id = v_ship.id), 0));
    -- GEAR ASKS A LEVEL OF HER (public.item_level_asks; none = 1).
    v_ask := coalesce((select a.min_level from public.item_level_asks a where a.item_code = k.code), 1);
    if v_ask > v_lvl then
      perform cmd.refuse('E_SHIP_LEVEL',
        format('%s asks a level %s ship and %s is level %s', k.name, v_ask, v_ship.name, v_lvl),
        cmd.figures(v_lvl, v_ask, 'level'));
    end if;
$h$,
$h$    v_lvl := public.level_in_force(coalesce((select sx.xp from public.ship_xp sx where sx.ship_id = v_ship.id), 0));
    -- 0133: "may I fit this" is no longer the SHIP's level (0127's gear level asks, empty, dropped here):
    -- it is the company's skills — public.requirements_met, above, for every hull.
$h$),
-- public.fleet_officer_bonus: Command, under the cap
('public.fleet_officer_bonus(uuid, text)', 1,
$h$           coalesce(sum(o.bonus_pct * public.captain_level_mult(po.id)), 0),
$h$,
$h$           -- 0133: and × (1 + Command's per cent / 100) while skills_bite is on (public.skill_scale:
           -- exactly the sum while dark) — still under the cap below.
           -- No skill is read at all while dark or when no officer adds anything (the arrivals sweep's path).
           public.skill_scale(coalesce(sum(o.bonus_pct * public.captain_level_mult(po.id)), 0),
                              case when coalesce(sum(o.bonus_pct * public.captain_level_mult(po.id)), 0) = 0
                                     or not public.skills_bite_on() then 0
                                   else world.skill_pct((select fl.player_id from public.fleets fl where fl.id = p_fleet), null, 'officer_bonus') end),
$h$),
-- public.assert_house_caps: the hull cap is public.house_ship_max
('public.assert_house_caps(uuid, uuid)', 1,
$h$  select count(*) into v_ships from public.ships where player_id = p_player;
  if v_ships > public.wc_int('ship_max') then
    raise exception 'E_SHIP_MAX: the house may hold % ship(s) and this would make %',
      public.wc_int('ship_max'), v_ships using errcode = 'P0001';
  end if;
$h$,
$h$  -- 0133: the cap is public.house_ship_max — ship_max, plus command_hulls_per_level per level of Command
  -- while skills_bite is on (exactly ship_max while dark).
  select count(*) into v_ships from public.ships where player_id = p_player;
  if v_ships > public.house_ship_max(p_player) then
    raise exception 'E_SHIP_MAX: the house may hold % ship(s) and this would make %',
      public.house_ship_max(p_player), v_ships using errcode = 'P0001';
  end if;
$h$),
-- world.ship_budget: Deck Management on the Deck, Gun Drill on the High units' Hands
('world.ship_budget(uuid)', 1,
$h$           'deck',  jsonb_build_object('used', coalesce(u.deck, 0),  'max', b.deck),
$h$,
$h$           -- 0133: Deck Management — the Deck × (1 + its per cent / 100), floored (exactly b.deck while dark).
           'deck',  jsonb_build_object('used', coalesce(u.deck, 0),  'max', floor(public.skill_scale(b.deck, k.deck))::int),
$h$),
('world.ship_budget(uuid)', 2,
$h$   cross join lateral public.class_budget(c.code) b
    left join lateral (select sum(ip.deck)::int as deck, sum(ip.hands)::int as hands
$h$,
$h$   cross join lateral public.class_budget(c.code) b
   -- 0133: the two fitting per cents her company's skills give (world.skill_bonuses, read once).
   cross join lateral (select coalesce(sum(sb.pct) filter (where sb.stat = 'deck'), 0) as deck,
                              coalesce(sum(sb.pct) filter (where sb.stat = 'high_hands'), 0) as drill
                         from world.skill_bonuses(s.player_id, s.id) sb
                        where public.skills_bite_on()) k   -- dark: a one-time filter
    -- 0133: Gun Drill — a High unit needs fewer Hands (public.drilled_hands; exactly ip.hands while dark).
    left join lateral (select sum(ip.deck)::int as deck, sum(public.drilled_hands(ip.hands, ip.rack, k.drill))::int as hands
$h$),
-- world.ship_view: + bonuses by source
('world.ship_view(uuid)', 1,
$h$           'budget', world.ship_budget(s.id),
$h$,
$h$           'budget', world.ship_budget(s.id),
           -- 0133: WHAT HER COMPANY'S SKILLS ADD TO HER, by source (world.skill_bonuses, the one reading): the
           -- skill and level and the effect in words — the client lists them, it derives none. [] while dark.
           'bonuses', (select coalesce(jsonb_agg(jsonb_build_object(
                          'skill', sb.skill_code, 'level', sb.level, 'stat', sb.stat, 'pct', sb.pct,
                          'source', sb.source, 'effect', sb.effect)
                          order by sb.source, sb.stat), '[]'::jsonb)
                         from world.skill_bonuses(s.player_id, s.id) sb
                        where public.skills_bite_on()),   -- dark: a one-time filter
$h$),
-- world.building_yard: + needs (the door's sentence), folded into buildable
('world.building_yard(uuid)', 1,
$h$        'buildable', v_tier is not null and v_tier >= h.yard_tier and yw.wrong is null,   -- 0130: and its country
$h$,
$h$        'buildable', v_tier is not null and v_tier >= h.yard_tier and yw.wrong is null   -- 0130: and its country
                     and yw.needs is null,                                               -- 0133: and its skills
$h$),
('world.building_yard(uuid)', 2,
$h$        'wrong_yard', yw.wrong,
$h$,
$h$        'wrong_yard', yw.wrong,
        -- 0133: the skills it needs that you lack — cmd.do_build's own E_NEEDS_SKILL sentence, or null.
        'needs', yw.needs,
$h$),
('world.building_yard(uuid)', 3,
$h$      cross join lateral (select public.yard_wrong_country(p_port, c.code) as wrong) yw));   -- 0130: once per hull
$h$,
$h$      cross join lateral (select public.yard_wrong_country(p_port, c.code) as wrong,                -- 0130: once per hull
                                 public.requirements_refusal(v_player, 'hull', c.code) as needs) yw));   -- 0133
$h$),
-- world.workstation: + needs (the FIT refusal's sentence)
('world.workstation(uuid, uuid)', 1,
$h$        'makeable', v_tier is not null and v_tier >= k.ws_tier,
$h$,
$h$        'makeable', v_tier is not null and v_tier >= k.ws_tier,
        -- 0133: the skills FITTING it needs that you lack — public.mount_fitting's own E_NEEDS_SKILL
        -- sentence, or null. Making it needs none.
        'needs', public.requirements_refusal(v_player, 'item', k.code),
$h$),
-- world.skills: the Academy's effect / pct_per_level from skill_effects (scope company) — one home
('world.skills()', 1,
$h$               'code', s.code, 'name', s.name, 'effect', s.effect,
               'pct_per_level', s.pct_per_level, 'blurb', s.blurb,
               'takes_effect', (s.effect = any(v_read))
$h$,
$h$               -- 0133: what a level gives is public.skill_effects' (scope company); a skill with no
               -- company effect reads NONE / 0.00, as its skills row always said (asserted, as text).
               'code', s.code, 'name', s.name, 'effect', coalesce(ce.stat, 'NONE'),
               'pct_per_level', coalesce(ce.pct_per_level, 0.00::numeric(5,2)), 'blurb', s.blurb,
               'takes_effect', (coalesce(ce.stat, 'NONE') = any(v_read))
$h$),
('world.skills()', 2,
$h$        join public.skill_groups g on g.code = pr.group_code));
$h$,
$h$        join public.skill_groups g on g.code = pr.group_code
        left join public.skill_effects ce on ce.skill_code = s.code and ce.scope = 'company'));   -- 0133
$h$);

create or replace function pg_temp.recut_0133(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := replace(pg_get_functiondef(p_fn::regprocedure), E'\r', '');
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0133 where fn = p_fn order by n loop
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0133 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0133(fn) from defs_before_0133 order by fn;

comment on function public.mount_fitting(uuid, text) is
  '0126/0132/0133: THE one core that puts a fitting on a hull — the house lock, what the item needs of the '
  'company (public.requirements_met: E_NEEDS_SKILL), her slots of the item''s RACK (world.ship_slots: E_NO_SLOT / '
  'E_SLOTS_FULL), the two budgets on FIT only (world.ship_budget: E_OVER_DECK / E_OVER_HANDS; Gun Drill counted '
  'by public.drilled_hands), one row into public.fitted_units. Called by cmd.do_fit and public.npc_fit_loadout. '
  'Server-only.';

-- ── 5. THE OLD BODIES, KEPT UNDER pg_temp NAMES (old vs new on ONE statement in §6) ─────────────
do $$
declare
  d     record;
  v_def text;
begin
  for d in select * from defs_before_0133
            where fn in ('world.ship_stats(uuid)', 'world.ship_budget(uuid)', 'world.ship_view(uuid)',
                         'public.player_skill_bonus(uuid, text)', 'public.fleet_officer_bonus(uuid, text)',
                         'world.building_yard(uuid)', 'world.workstation(uuid, uuid)', 'world.skills()') loop
    v_def := d.def;
    v_def := replace(v_def, 'CREATE OR REPLACE FUNCTION ' || split_part(d.fn, '(', 1) || '(',
                     'CREATE OR REPLACE FUNCTION pg_temp.' || split_part(split_part(d.fn, '(', 1), '.', 2) || '_before_0133(');
    if strpos(v_def, '_before_0133(') = 0 then
      raise exception '0133 self-assert FAIL: could not rename the pre-image of %', d.fn;
    end if;
    if d.fn = 'world.ship_view(uuid)' then
      -- the old builder over the old stats and the old budget, so its whole answer is the pre-image's
      if strpos(v_def, 'world.ship_stats(s.id)') = 0 or strpos(v_def, 'world.ship_budget(s.id)') = 0 then
        raise exception '0133 self-assert FAIL: the old ship_view does not read ship_stats / ship_budget where expected';
      end if;
      v_def := replace(replace(v_def, 'world.ship_stats(s.id)', 'pg_temp.ship_stats_before_0133(s.id)'),
                       'world.ship_budget(s.id)', 'pg_temp.ship_budget_before_0133(s.id)');
    end if;
    execute v_def;
  end loop;
end $$;

-- ── 6. THE COMPARISONS, THE PROBES, THE TIMINGS (before any hot DDL) ───────────────────────────
-- THE HEAVY SELF-ASSERT. Old and new, every hull / company / fleet / yard, each read in ONE statement
-- (one snapshot: STABLE functions see what the statement sees), then compared at leisure.
create temp table hulls_after_0133 on commit drop as
select s.id as ship_id,
       world.ship_stats(s.id) as new_stats, pg_temp.ship_stats_before_0133(s.id) as old_stats,
       world.ship_budget(s.id) as new_bud, pg_temp.ship_budget_before_0133(s.id) as old_bud,
       world.ship_view(s.id) as new_view, pg_temp.ship_view_before_0133(s.id) as old_view
  from public.ships s;
create temp table bonus_after_0133 on commit drop as
select p.id as player_id, e.eff,
       public.player_skill_bonus(p.id, e.eff) as new_b, pg_temp.player_skill_bonus_before_0133(p.id, e.eff) as old_b
  from public.players p
 cross join (values ('ENDURANCE'), ('SPEED'), ('TRADE_CAP'), ('SPREAD')) e(eff);
create temp table officer_after_0133 on commit drop as
select f.id as fleet_id, sp.specialty,
       public.fleet_officer_bonus(f.id, sp.specialty) as new_b, pg_temp.fleet_officer_bonus_before_0133(f.id, sp.specialty) as old_b
  from public.fleets f
 cross join (select distinct o.specialty from public.officers o) sp;
create temp table yards_after_0133 on commit drop as
select b.port_id, world.building_yard(b.port_id) as new_v, pg_temp.building_yard_before_0133(b.port_id) as old_v
  from public.port_buildings b where b.kind = 'building_yard';
create temp table skills_after_0133 on commit drop as
select world.skills() as new_v, pg_temp.skills_before_0133() as old_v;
create temp table ws_after_0133 on commit drop as
select b.port_id, world.workstation(b.port_id, null) as new_v, pg_temp.workstation_before_0133(b.port_id, null) as old_v
  from public.port_buildings b where b.kind = 'workstation';

select pg_temp.time_reads_0133('after');

-- THE PROBE (its own company, rolled back): dark first, then LIT inside the same rolled-back block.
create or replace function pg_temp.probe_0133()
returns jsonb
language plpgsql
as $$
declare
  c_uid     constant uuid := '00000000-0133-4000-8000-000000000001';
  v_player  uuid;
  v_fleet   uuid;
  v_port    uuid;
  v_lis     uuid := (select id from public.ports where code = 'LIS');
  v_barca   uuid;
  v_nau     uuid;
  v_out     jsonb := '{}'::jsonb;
  v_err     text;
  v_det     text;
  v_cap     int := public.wc_int('ship_max');
  v_n       int;
  v_npc     uuid;
  v_npc_sh  uuid;
  v_npc_fl  uuid;
  v_pat     jsonb;
  v_off     uuid;
begin
  begin
    if public.skills_bite_on() then
      raise exception '0133 self-assert FAIL: skills_bite is on before the probe — this file ships it dark';
    end if;
    v_player := public.new_house(c_uid, 'Casa das Artes 0133', 'PRT');
    select id, port_id into v_fleet, v_port from public.fleets where player_id = v_player;
    select id into v_barca from public.ships where fleet_id = v_fleet;
    v_nau := public.commission_ship(v_player, v_fleet, 'nau', 'Prova Nau', false, true);
    -- the skills the probe "has trained" (rows written directly, rolled back with everything else)
    insert into public.player_skills (player_id, skill_id, level)
    select v_player, sk.id, x.lvl
      from (values ('PRT_MEDIUM', 3), ('COMMAND', 2), ('DECK_MANAGEMENT', 2), ('GUN_DRILL', 2)) x(code, lvl)
      join public.skills sk on sk.code = x.code;
    insert into public.player_items (player_id, port_id, item_code, qty) values
      (v_player, v_port, 'broadside-guns', 2), (v_player, v_port, 'suit-of-sails', 3)
    on conflict (player_id, port_id, item_code) do update set qty = excluded.qty;
    perform cmd.do_fit(v_fleet, jsonb_build_object('item', 'broadside-guns', 'ship', 'Prova Nau'));
    perform cmd.do_fit(v_fleet, jsonb_build_object('item', 'broadside-guns', 'ship', 'Prova Nau'));
    select o.id into v_off from public.officers o where o.specialty = 'QUARTERMASTER' order by o.bonus_pct desc, o.code limit 1;
    insert into public.player_officers (player_id, officer_id, fleet_id) values (v_player, v_off, v_fleet);
    -- room in one fleet for every hull the cap allows (knobs bent inside this rolled-back block only)
    update public.world_config set value = to_jsonb(40) where key in ('fleet_ship_max', 'fleet_ship_base');
    -- requirements PLANTED for the probe (rolled back): the nau needs PRT Medium Hulls IV, sails need Rigging II
    insert into public.skill_requirements (subject_kind, subject_code, skill_code, level) values
      ('hull', 'nau', 'PRT_MEDIUM', 4), ('item', 'suit-of-sails', 'RIGGING', 2);

    -- ── DARK (skills_bite false): the skills and the planted rows change nothing ──────────────
    v_err := null;
    begin
      perform cmd.do_build(v_fleet, jsonb_build_object('class', 'nau', 'name', 'Prova Construida'));
    exception when sqlstate 'P0001' then v_err := sqlerrm;
    end;
    v_out := v_out || jsonb_build_object('dark_build', v_err);
    -- dark: sails need nothing — fitted
    perform cmd.do_fit(v_fleet, jsonb_build_object('item', 'suit-of-sails', 'ship', 'Prova Nau'));
    v_out := v_out || jsonb_build_object('dark_fit_units', (select count(*) from public.fitted_units where ship_id = v_nau and item_code = 'suit-of-sails'));
    -- what the hulls read dark, with everything the lit reads below will see mounted
    v_out := v_out || jsonb_build_object(
      'dark_nau', world.ship_stats(v_nau), 'dark_barca', world.ship_stats(v_barca),
      'dark_bonuses', world.ship_view(v_nau)->'bonuses', 'dark_budget', world.ship_budget(v_nau),
      'dark_officer', public.fleet_officer_bonus(v_fleet, 'QUARTERMASTER'),
      'officer_pct', (select bonus_pct from public.officers where id = v_off),
      'dark_ship_max', public.house_ship_max(v_player),
      'dark_yard_nau', (select h from jsonb_array_elements(world.building_yard(v_lis)->'hulls') h where h->>'class' = 'nau'),
      'dark_ws_sails', (select it->'needs' from jsonb_array_elements(world.workstation(v_port, null)->'items') it where it->>'code' = 'suit-of-sails'));
    -- dark: the cap is ship_max — fill to it, one more is refused
    select count(*) into v_n from public.ships where player_id = v_player;
    for i in v_n + 1 .. v_cap loop
      perform public.commission_ship(v_player, v_fleet, 'barca', 'Prova ' || i, false, false);
    end loop;
    v_err := null;
    begin
      perform public.commission_ship(v_player, v_fleet, 'barca', 'Prova Mais', false, false);
    exception when sqlstate 'P0001' then v_err := sqlerrm;
    end;
    v_out := v_out || jsonb_build_object('dark_cap_refusal', v_err, 'hulls_at_cap', (select count(*) from public.ships where player_id = v_player));

    -- ── LIT (skills_bite true, inside this rolled-back block) ────────────────────────────────
    update public.world_config set value = 'true'::jsonb where key = 'skills_bite';
    v_out := v_out || jsonb_build_object(
      'lit_nau', world.ship_stats(v_nau), 'lit_barca', world.ship_stats(v_barca),
      'lit_bonuses', world.ship_view(v_nau)->'bonuses', 'lit_budget', world.ship_budget(v_nau),
      'lit_officer', public.fleet_officer_bonus(v_fleet, 'QUARTERMASTER'),
      'lit_ship_max', public.house_ship_max(v_player),
      'lit_house_bonuses', (select jsonb_agg(to_jsonb(sb) order by sb.skill_code) from world.skill_bonuses(v_player, null) sb),
      'lit_yard_nau', (select h from jsonb_array_elements(world.building_yard(v_lis)->'hulls') h where h->>'class' = 'nau'),
      'lit_ws_sails', (select it->'needs' from jsonb_array_elements(world.workstation(v_port, null)->'items') it where it->>'code' = 'suit-of-sails'));
    -- Command II: two more hulls are kept, a third is refused with the new cap in its words
    perform public.commission_ship(v_player, v_fleet, 'barca', 'Prova Mais Um', false, false);
    perform public.commission_ship(v_player, v_fleet, 'barca', 'Prova Mais Dois', false, false);
    v_err := null;
    begin
      perform public.commission_ship(v_player, v_fleet, 'barca', 'Prova Mais Tres', false, false);
    exception when sqlstate 'P0001' then v_err := sqlerrm;
    end;
    v_out := v_out || jsonb_build_object('lit_cap_refusal', v_err, 'lit_hulls', (select count(*) from public.ships where player_id = v_player));
    -- the planted requirement refuses BUILD at the door, with figures, before the shed is read
    v_err := null; v_det := null;
    begin
      perform cmd.do_build(v_fleet, jsonb_build_object('class', 'nau', 'name', 'Prova Construida'));
    exception when sqlstate 'P0001' then get stacked diagnostics v_err = message_text, v_det = pg_exception_detail;
    end;
    v_out := v_out || jsonb_build_object('lit_build', v_err, 'lit_build_figures', v_det);
    -- and FIT at the core, taking nothing from the store
    v_err := null; v_det := null;
    begin
      perform cmd.do_fit(v_fleet, jsonb_build_object('item', 'suit-of-sails', 'ship', 'Prova Nau'));
    exception when sqlstate 'P0001' then get stacked diagnostics v_err = message_text, v_det = pg_exception_detail;
    end;
    v_out := v_out || jsonb_build_object('lit_fit', v_err, 'lit_fit_figures', v_det,
      'lit_fit_store', (select qty from public.player_items where player_id = v_player and port_id = v_port and item_code = 'suit-of-sails'),
      'lit_fit_units', (select count(*) from public.fitted_units where ship_id = v_nau and item_code = 'suit-of-sails'));
    -- met: with Rigging II the same FIT goes on; with PRT Medium Hulls IV the BUILD passes the skill check
    -- (and stops where it stopped dark: the shed)
    insert into public.player_skills (player_id, skill_id, level)
    select v_player, sk.id, 2 from public.skills sk where sk.code = 'RIGGING';
    update public.player_skills set level = 4
     where player_id = v_player and skill_id = (select id from public.skills where code = 'PRT_MEDIUM');
    perform cmd.do_fit(v_fleet, jsonb_build_object('item', 'suit-of-sails', 'ship', 'Prova Nau'));
    v_err := null;
    begin
      perform cmd.do_build(v_fleet, jsonb_build_object('class', 'nau', 'name', 'Prova Construida'));
    exception when sqlstate 'P0001' then v_err := sqlerrm;
    end;
    v_out := v_out || jsonb_build_object('met_fit_units', (select count(*) from public.fitted_units where ship_id = v_nau and item_code = 'suit-of-sails'),
                                         'met_build', v_err,
                                         'met_refusal', public.requirements_refusal(v_player, 'hull', 'nau'),
                                         'met_met', public.requirements_met(v_player, 'hull', 'nau'));

    -- A MERCHANT, LIT: G1 items need nothing (the planted rows removed), so her loadout mounts through the
    -- same core, and her hull reads the same lit as dark (her fixed skills carry only company effects).
    delete from public.skill_requirements;
    v_npc := public.new_house(null, 'Prova Mercante 0133', 'PRT', 'LIS', 'Prova Frota 0133', 'barca', 'Prova Mercante', 8000, true);
    -- her fixed skills: a live one (company effect only), as npc_found gives every merchant
    insert into public.player_skills (player_id, skill_id, level)
    select v_npc, sk.id, 2 from public.skills sk where sk.code = 'SEAMANSHIP';
    select s.id, s.fleet_id into v_npc_sh, v_npc_fl from public.ships s where s.player_id = v_npc;
    v_out := v_out || jsonb_build_object('npc_fit', public.npc_fit_loadout(v_npc_sh));
    select jsonb_object_agg(l.item_code, l.qty) into v_pat
      from public.npc_loadouts l
     where l.class_code = 'barca'
       and l.pattern = mod(mod(('x' || left(md5(v_npc_fl::text), 8))::bit(32)::int,
                               (select count(distinct pattern) from public.npc_loadouts where class_code = 'barca')::int)
                           + (select count(distinct pattern) from public.npc_loadouts where class_code = 'barca')::int,
                           (select count(distinct pattern) from public.npc_loadouts where class_code = 'barca')::int);
    v_out := v_out || jsonb_build_object('npc_pattern', v_pat,
      'npc_units', (select jsonb_object_agg(x.item_code, x.n) from (select item_code, count(*) as n from public.fitted_units where ship_id = v_npc_sh group by item_code) x),
      'npc_lit_stats', world.ship_stats(v_npc_sh), 'npc_lit_bonuses', world.ship_view(v_npc_sh)->'bonuses');
    update public.world_config set value = 'false'::jsonb where key = 'skills_bite';
    v_out := v_out || jsonb_build_object('npc_dark_stats', world.ship_stats(v_npc_sh));

    raise exception 'PROBE_ROLLBACK_0133';
  exception when others then
    if sqlerrm <> 'PROBE_ROLLBACK_0133' then raise; end if;
  end;
  return v_out;
end $$;

create temp table probe_0133 (j jsonb) on commit drop;
do $$
declare
  v_try   int := 0;
  v_state text;
  v_msg   text;
begin
  loop
    v_try := v_try + 1;
    begin
      insert into probe_0133 select pg_temp.probe_0133();
      exit;
    exception when lock_not_available or deadlock_detected then
      get stacked diagnostics v_msg = message_text, v_state = returned_sqlstate;
    end;
    if v_try >= 5 then
      raise exception '0133 self-assert FAIL: LOCK CONTENTION, not a result — the probe could not get its locks in 5 tries (%: %). Re-run the push.',
        v_state, v_msg;
    end if;
    perform pg_sleep(0.2);
  end loop;
end $$;

-- the merchant reads LIT (rolled back): what the arrivals tick would pay once the switch is thrown. The
-- timings ride out of the rolled-back block in a variable (its own table rows would roll back with it).
create temp table lit_reads_0133 (what text, hulls bigint, ms numeric) on commit drop;
do $$
declare
  v_n  bigint := (select count(*) from hulls_before_0133 where is_npc);
  r    jsonb := '{}'::jsonb;
begin
  begin
    update public.world_config set value = 'true'::jsonb where key = 'skills_bite';
    r := pg_temp.reads_now_0133();
    raise exception 'LIT_ROLLBACK_0133';
  exception when others then
    if sqlerrm <> 'LIT_ROLLBACK_0133' then raise; end if;
  end;
  insert into lit_reads_0133 select key, v_n, value::text::numeric from jsonb_each(r);
end $$;

create temp table proven_0133 (k text primary key, v text) on commit drop;
do $$
declare
  v_bad     bigint;
  v_n       bigint;
  v_hulls   bigint;
  v_list    text;
  v_def     text;
  h         record;
  d         record;
  v_p       jsonb := (select j from probe_0133);
  v_nau_d   jsonb;
  v_nau_l   jsonb;
  v_stat    text;
  v_nau_name text := (select name from public.ship_classes where code = 'nau');
begin
  if public.skills_bite_on() then
    raise exception '0133 self-assert FAIL: skills_bite is on — this file ships it dark';
  end if;

  -- (a) EVERY HULL'S TEN STATS = THE PRE-IMAGE, to the digit (old vs new on one statement, as text)
  select count(*), count(*) filter (where a.old_stats::text is distinct from a.new_stats::text)
    into v_hulls, v_bad from hulls_after_0133 a;
  if v_hulls = 0 or v_bad <> 0 then
    raise exception '0133 self-assert FAIL: % of % hull(s) read different stats dark', v_bad, v_hulls;
  end if;
  select count(*) into v_n from hulls_before_0133 b join hulls_after_0133 a on a.ship_id = b.ship_id
   where b.stats::text is distinct from a.new_stats::text;
  insert into proven_0133 values ('stats', format('%s hulls, 0 differ old/new; %s moved by play since the pre-image', v_hulls, v_n));

  -- (b) EVERY HULL'S BUDGET = THE PRE-IMAGE; ship_view = the pre-image plus `bonuses` = []
  select count(*) into v_bad from hulls_after_0133 a where a.old_bud::text is distinct from a.new_bud::text;
  if v_bad <> 0 then
    raise exception '0133 self-assert FAIL: % hull(s) read a different budget dark', v_bad;
  end if;
  select count(*) into v_bad from hulls_after_0133 a
   where (a.new_view - 'bonuses')::text is distinct from a.old_view::text
      or a.new_view->'bonuses' is distinct from '[]'::jsonb
      or (select count(*) from jsonb_object_keys(a.new_view)) <> (select count(*) from jsonb_object_keys(a.old_view)) + 1;
  if v_bad <> 0 then
    raise exception '0133 self-assert FAIL: % hull(s) whose ship_view is not the pre-image plus bonuses = []', v_bad;
  end if;
  select count(*) into v_n from hulls_before_0133 b join hulls_after_0133 a on a.ship_id = b.ship_id
   where b.budget::text is distinct from a.new_bud::text or b.view::text is distinct from (a.new_view - 'bonuses')::text;
  insert into proven_0133 values ('budget', format('%s hulls, 0 differ old/new; %s moved by play since the pre-image', v_hulls, v_n));

  -- (c) EVERY COMPANY'S FOUR COMPANY EFFECTS = THE PRE-IMAGE (player_skill_bonus over skill_effects)
  select count(*), count(*) filter (where a.old_b::text is distinct from a.new_b::text)
    into v_n, v_bad from bonus_after_0133 a;
  if v_n = 0 or v_bad <> 0 then
    raise exception '0133 self-assert FAIL: % of % (company, effect) bonus(es) differ', v_bad, v_n;
  end if;
  insert into proven_0133 values ('company', format('%s (company, effect) pairs, %s non-zero, 0 differ old/new; %s moved by play since the pre-image', v_n,
    (select count(*) from bonus_after_0133 where new_b <> 0),
    (select count(*) from bonus_before_0133 b join bonus_after_0133 a using (player_id, eff) where b.b::text is distinct from a.new_b::text)));

  -- (d) EVERY FLEET'S OFFICER BONUS = THE PRE-IMAGE
  select count(*), count(*) filter (where a.old_b::text is distinct from a.new_b::text)
    into v_n, v_bad from officer_after_0133 a;
  if v_n = 0 or v_bad <> 0 then
    raise exception '0133 self-assert FAIL: % of % (fleet, specialty) officer bonus(es) differ', v_bad, v_n;
  end if;
  insert into proven_0133 values ('officers', format('%s (fleet, specialty) pairs, %s non-zero', v_n,
    (select count(*) from officer_after_0133 where new_b <> 0)));

  -- (e) EVERY COMPANY'S HULL CAP = ship_max; NO REQUIREMENT REFUSES ANYONE (every company × every hull
  --     and item); every yard and workstation answer = the pre-image plus `needs` = null
  select count(*) into v_bad from public.players p where public.house_ship_max(p.id) <> public.wc_int('ship_max');
  if v_bad <> 0 then
    raise exception '0133 self-assert FAIL: % company(ies) whose hull cap is not ship_max dark', v_bad;
  end if;
  select count(*) into v_bad
    from public.players p
   cross join (select 'hull' as kind, c.code from public.ship_classes c
               union all select 'item', k.code from public.item_kinds k) x
   where public.requirements_refusal(p.id, x.kind, x.code) is not null
      or not public.requirements_met(p.id, x.kind, x.code);
  if v_bad <> 0 then
    raise exception '0133 self-assert FAIL: % (company, subject) pair(s) refused by a requirement dark', v_bad;
  end if;
  select count(*) into v_bad from yards_after_0133 y
   where jsonb_set(y.new_v, '{hulls}', coalesce((select jsonb_agg(hh - 'needs' order by o)
                                                   from jsonb_array_elements(y.new_v->'hulls') with ordinality t(hh, o)), '[]'::jsonb))::text
         is distinct from y.old_v::text
      or exists (select 1 from jsonb_array_elements(y.new_v->'hulls') hh where not (hh ? 'needs') or hh->'needs' <> 'null'::jsonb);
  if v_bad <> 0 or (select count(*) from yards_after_0133) = 0 then
    raise exception '0133 self-assert FAIL: % build yard(s) whose answer is not the pre-image plus needs = null', v_bad;
  end if;
  select count(*) into v_bad from ws_after_0133 y
   where jsonb_set(y.new_v, '{items}', coalesce((select jsonb_agg(ii - 'needs' order by o)
                                                   from jsonb_array_elements(y.new_v->'items') with ordinality t(ii, o)), '[]'::jsonb))::text
         is distinct from y.old_v::text
      or exists (select 1 from jsonb_array_elements(y.new_v->'items') ii where not (ii ? 'needs') or ii->'needs' <> 'null'::jsonb);
  if v_bad <> 0 or (select count(*) from ws_after_0133) = 0 then
    raise exception '0133 self-assert FAIL: % workshop(s) whose answer is not the pre-image plus needs = null', v_bad;
  end if;
  -- the Academy (world.skills) = the pre-image, as text, now reading skill_effects
  if (select new_v::text is distinct from old_v::text from skills_after_0133)
     or (select jsonb_array_length(new_v->'skills') from skills_after_0133) <> (select count(*) from public.skills) then
    raise exception '0133 self-assert FAIL: world.skills over skill_effects is not the pre-image';
  end if;
  insert into proven_0133 values ('caps', format('%s companies at ship_max %s; %s yards, %s workshops',
    (select count(*) from public.players), public.wc_int('ship_max'), (select count(*) from yards_after_0133), (select count(*) from ws_after_0133)));

  -- (f) THE CATALOGUE: 4 company rows mirror skills.effect / pct_per_level; 132 hull rows = every line's
  --     two traits × 6 sizes, each on its own line's hull skill of that size; 24 others; every row's skill
  --     exists; no requirement row (the live hulls and items need nothing)
  if (select count(*) from public.skill_effects where scope = 'company') <> 4
     or exists (select 1 from public.skills s where s.effect <> 'NONE'
                   and not exists (select 1 from public.skill_effects e where e.skill_code = s.code and e.scope = 'company'
                                      and e.stat = s.effect and e.pct_per_level = s.pct_per_level))
     or exists (select 1 from public.skill_effects e join public.skills s on s.code = e.skill_code
                 where e.scope = 'company' and s.effect = 'NONE') then
    raise exception '0133 self-assert FAIL: the company rows do not mirror skills.effect / pct_per_level';
  end if;
  if (select count(*) from public.skill_effects where line_code is not null) <> 132
     or (select count(*) from public.skill_effects where line_code is not null)
        <> (select 6 * sum(jsonb_array_length(traits)) from public.ship_lines)
     or exists (select 1 from public.skill_effects e
                  join public.skills s on s.code = e.skill_code
                  join public.skill_profile pr on pr.skill_id = s.id
                 where e.line_code is not null
                   and (pr.line_code is distinct from e.line_code
                        or e.skill_code <> e.line_code || '_' || (array['SMALL', 'LIGHT', 'MEDIUM', 'HEAVY', 'CAPITAL', 'CAPITAL'])[e.size]))
     or exists (select 1 from public.ship_lines sl cross join jsonb_array_elements(sl.traits) t
                 cross join generate_series(1, 6) z(size)
                 where not exists (select 1 from public.skill_effects e
                                    where e.line_code = sl.code and e.size = z.size
                                      and e.stat = case t->>'stat' when 'hull' then 'durability' else t->>'stat' end
                                      and e.pct_per_level = (t->>'pct')::numeric)) then
    raise exception '0133 self-assert FAIL: the hull rows are not every line''s two traits on its hulls of each size';
  end if;
  if (select count(*) from public.skill_effects) <> 160
     or exists (select 1 from public.skill_effects e where not exists (select 1 from public.skills s where s.code = e.skill_code)) then
    raise exception '0133 self-assert FAIL: % skill effect row(s), not 160, or one names no skill', (select count(*) from public.skill_effects);
  end if;
  if (select count(*) from public.skill_requirements) <> 0 then
    raise exception '0133 self-assert FAIL: skill_requirements is not empty — S11 ships none (the live hulls and items need nothing)';
  end if;
  insert into proven_0133 values ('catalogue', format('%s effects (4 company, 132 hull, %s other), 0 requirements',
    (select count(*) from public.skill_effects), (select count(*) from public.skill_effects where line_code is null and scope <> 'company')));

  -- (g) item_level_asks: empty (pre-image and now), and no live body, view or FK names it any more
  --     (positive controls: mount_fitting's pre-image did; a planted body that names it is seen).
  if (select level_asks from before_0133) <> 0 or (select count(*) from public.item_level_asks) <> 0 then
    raise exception '0133 self-assert FAIL: item_level_asks is not empty (% row(s)) — convert each to a skill requirement before dropping it',
      (select count(*) from public.item_level_asks);
  end if;
  if strpos((select def from defs_before_0133 where fn = 'public.mount_fitting(uuid, text)'), 'item_level_asks') = 0 then
    raise exception '0133 self-assert FAIL: the reader scan''s positive control — mount_fitting''s pre-image did not name item_level_asks';
  end if;
  select count(*), string_agg(n.nspname || '.' || p.proname, ', ') into v_bad, v_list
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname not in ('pg_catalog', 'information_schema') and n.nspname not like 'pg\_%'
     and p.prosrc ~* 'item_level_asks';
  if v_bad <> 0 then
    raise exception '0133 self-assert FAIL: live bodies still name item_level_asks: %', v_list;
  end if;
  begin
    execute $planted$create function public.zz_planted_reader_0133() returns bigint language sql as
      'select count(*) from public.item_level_asks'$planted$;
    if (select count(*) from pg_proc p where p.prosrc ~* 'item_level_asks') <> 1 then
      raise exception '0133 self-assert FAIL: the reader scan did not see a planted reader — it proves nothing';
    end if;
    raise exception 'CONTROL_ROLLBACK_0133';
  exception when others then
    if sqlerrm <> 'CONTROL_ROLLBACK_0133' then raise; end if;
  end;
  if exists (select 1 from pg_proc where proname = 'zz_planted_reader_0133') then
    raise exception '0133 self-assert FAIL: the planted reader was not rolled back';
  end if;
  if exists (select 1 from pg_depend dp join pg_rewrite rw on rw.oid = dp.objid
              where dp.refobjid = 'public.item_level_asks'::regclass
                and dp.classid = 'pg_rewrite'::regclass)
     or exists (select 1 from pg_constraint where confrelid = 'public.item_level_asks'::regclass) then
    raise exception '0133 self-assert FAIL: a view or a foreign key still references item_level_asks';
  end if;
  insert into proven_0133 values ('retired', 'item_level_asks 0 rows, read by nothing');

  -- (h) THE RE-CUTS: each new body reverses to its pre-image hunk by hunk; ACLs unmoved; the untouched
  --     bodies untouched; the catalogue (skills, ship_classes, item_kinds, class_profile, ship_lines) unmoved
  for d in select * from defs_before_0133 loop
    v_def := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0133 where fn = d.fn order by n desc loop
      if (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new) <> 1 then
        raise exception '0133 self-assert FAIL: hunk % of % is not in the new body exactly once', h.n, d.fn;
      end if;
      v_def := replace(v_def, h.new, h.old);
    end loop;
    if v_def <> d.def then
      raise exception '0133 self-assert FAIL: % does not reverse to its pre-image — something beyond the hunks moved', d.fn;
    end if;
    if coalesce((select p.proacl::text from pg_proc p where p.oid = d.fn::regprocedure), '') <> d.acl then
      raise exception '0133 self-assert FAIL: the ACL of % moved', d.fn;
    end if;
  end loop;
  for d in select * from untouched_before_0133 loop
    if replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '') <> d.def
       or coalesce((select p.proacl::text from pg_proc p where p.oid = d.fn::regprocedure), '') <> d.acl then
      raise exception '0133 self-assert FAIL: % moved — it was to be left untouched', d.fn;
    end if;
  end loop;
  if (select md5(string_agg(to_jsonb(s)::text, '|' order by s.code)) from public.skills s) <> (select skills_hash from before_0133)
     or (select md5(string_agg(to_jsonb(c)::text, '|' order by c.code)) from public.ship_classes c) <> (select classes_hash from before_0133)
     or (select md5(string_agg(to_jsonb(k)::text, '|' order by k.code)) from public.item_kinds k) <> (select kinds_hash from before_0133)
     or (select md5(string_agg(to_jsonb(p)::text, '|' order by p.class_code)) from public.class_profile p) <> (select profile_hash from before_0133)
     or (select md5(string_agg(to_jsonb(l)::text, '|' order by l.code)) from public.ship_lines l) <> (select lines_hash from before_0133) then
    raise exception '0133 self-assert FAIL: skills, ship_classes, item_kinds, class_profile or ship_lines moved';
  end if;
  -- no new body tells a merchant from a player
  for v_stat in select unnest(array['world.skill_bonuses(uuid, uuid)', 'world.skill_pct(uuid, uuid, text)',
                                    'public.requirements_unmet(uuid, text, text)', 'public.requirements_met(uuid, text, text)',
                                    'public.requirements_refusal(uuid, text, text)', 'public.house_ship_max(uuid)',
                                    'public.mount_fitting(uuid, text)', 'world.ship_budget(uuid)']) loop
    if strpos(pg_get_functiondef(v_stat::regprocedure), 'is_npc') > 0 then
      raise exception '0133 self-assert FAIL: % reads is_npc', v_stat;
    end if;
  end loop;

  -- (i) THE WALL: no new entry point; the new tables and functions server-only; no client write
  if (select count(*) from public.client_rpc_entry_points()) <> (select entry_points from before_0133)
     or exists (select 1 from public.client_rpc_entry_points() e
                 where e.fn is null or not has_function_privilege('authenticated', e.fn, 'execute'))
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0133 self-assert FAIL: the registry, the grant wall or the read wall moved';
  end if;
  if exists (select 1 from unnest(array['public.skills_bite_on()', 'public.skill_level_word(integer)',
                                        'public.skill_effect_words(text, numeric)', 'public.skill_scale(numeric, numeric)',
                                        'public.drilled_hands(integer, text, numeric)', 'world.skill_bonuses(uuid, uuid)',
                                        'world.skill_pct(uuid, uuid, text)', 'public.house_ship_max(uuid)',
                                        'public.requirements_unmet(uuid, text, text)', 'public.requirements_met(uuid, text, text)',
                                        'public.requirements_refusal(uuid, text, text)']) f(fn),
                           unnest(array['anon', 'authenticated']) r(role)
              where has_function_privilege(r.role, f.fn, 'execute'))
     or exists (select 1 from unnest(array['public.skill_effects', 'public.skill_requirements']) t(tbl),
                              unnest(array['anon', 'authenticated']) r(role)
                 where has_table_privilege(r.role, t.tbl, 'select,insert,update,delete')) then
    raise exception '0133 self-assert FAIL: a client role can reach a new function or table';
  end if;

  -- (j) THE PROBE, DARK: trained skills and planted requirements change nothing while skills_bite is off
  if coalesce(v_p->'dark_bonuses' is distinct from '[]'::jsonb
     or (v_p->>'dark_ship_max')::int <> public.wc_int('ship_max')
     or v_p->'dark_yard_nau'->'needs' is distinct from 'null'::jsonb
     or v_p->'dark_ws_sails' is distinct from 'null'::jsonb
     or v_p->>'dark_build' not like 'E_NO_TIMBER:%'
     or (v_p->>'dark_fit_units')::int <> 1
     or v_p->>'dark_cap_refusal' is distinct from format('E_SHIP_MAX: the house may hold %s ship(s) and this would make %s',
                                                         public.wc_int('ship_max'), public.wc_int('ship_max') + 1)
     or (v_p->>'hulls_at_cap')::int <> public.wc_int('ship_max'), true) then
    raise exception '0133 self-assert FAIL: the probe moved while dark: %', v_p;
  end if;

  -- (k) THE PROBE, LIT: PRT Medium Hulls III → the nau reads +12 %% sighting and +6 %% speed, every other
  --     stat and the barca (a small hull) unmoved; the bonuses listed by source
  v_nau_d := v_p->'dark_nau';
  v_nau_l := v_p->'lit_nau';
  if coalesce((v_nau_l->>'sighting') <> round((v_nau_d->>'sighting')::numeric * 1.12, scale((v_nau_d->>'sighting')::numeric))::text
     or (v_nau_l->>'speed') <> round((v_nau_d->>'speed')::numeric * 1.06, scale((v_nau_d->>'speed')::numeric))::text
     or (v_nau_l->>'sighting')::numeric = (v_nau_d->>'sighting')::numeric
     or exists (select 1 from jsonb_object_keys(v_nau_d) k
                 where k not in ('sighting', 'speed') and (v_nau_l->>k)::numeric is distinct from (v_nau_d->>k)::numeric)
     or exists (select 1 from jsonb_object_keys(v_p->'dark_barca') k
                 where (v_p->'lit_barca'->>k)::numeric is distinct from (v_p->'dark_barca'->>k)::numeric), true) then
    raise exception '0133 self-assert FAIL: PRT Medium Hulls III did not give the nau exactly +12%% sighting and +6%% speed (and nothing else): dark % lit %',
      v_nau_d, v_nau_l;
  end if;
  if (select count(*) from jsonb_array_elements(v_p->'lit_bonuses') b
       where b->>'source' = 'Portuguese Medium Hulls III'
         and ((b->>'stat' = 'sighting' and b->>'effect' = '+12% sighting') or (b->>'stat' = 'speed' and b->>'effect' = '+6% speed'))) <> 2 then
    raise exception '0133 self-assert FAIL: the nau''s bonuses are not listed by source: %', v_p->'lit_bonuses';
  end if;
  -- Deck Management II: the nau's Deck 56 → 61; Gun Drill II: two guns (8 Hands each) → 7 each; sails unchanged
  if coalesce((v_p->'dark_budget'->'deck'->>'max')::int <> 56
     or (v_p->'lit_budget'->'deck'->>'max')::int <> 61
     or (v_p->'dark_budget'->'hands'->>'used')::int <> 2 * 8 + 4
     or (v_p->'lit_budget'->'hands'->>'used')::int <> 2 * 7 + 4
     or (v_p->'lit_budget'->'hands'->>'max') <> (v_p->'dark_budget'->'hands'->>'max')
     or (v_p->'lit_budget'->'deck'->>'used') <> (v_p->'dark_budget'->'deck'->>'used'), true) then
    raise exception '0133 self-assert FAIL: Deck Management / Gun Drill did not move the budget as written: dark % lit %',
      v_p->'dark_budget', v_p->'lit_budget';
  end if;
  -- Command II: officers' bonuses × 1.04 under the cap; the house keeps ship_max + 2 hulls, not + 3
  if coalesce((v_p->>'lit_officer')::numeric <> least((v_p->>'officer_pct')::numeric * 1.04, public.wc_num('officer_bonus_cap_pct')) / 100.0
     or (v_p->>'dark_officer')::numeric <> least((v_p->>'officer_pct')::numeric, public.wc_num('officer_bonus_cap_pct')) / 100.0
     or (v_p->>'lit_ship_max')::int <> public.wc_int('ship_max') + 2
     or (v_p->>'lit_hulls')::int <> public.wc_int('ship_max') + 2
     or v_p->>'lit_cap_refusal' is distinct from format('E_SHIP_MAX: the house may hold %s ship(s) and this would make %s',
                                                        public.wc_int('ship_max') + 2, public.wc_int('ship_max') + 3)
     or (select count(*) from jsonb_array_elements(v_p->'lit_house_bonuses') b
          where b->>'source' = 'Command II' and b->>'effect' = '+4% officer bonuses') <> 1, true) then
    raise exception '0133 self-assert FAIL: Command II did not lift the officer bonus 4%% and the hull cap by two: %', v_p;
  end if;
  -- requirements: refused at the door (BUILD) and the core (FIT) in the rule's sentence with figures, the
  -- store untouched; the yard and the workshop serve the same sentence; met → passes
  if coalesce(v_p->>'lit_build' is distinct from 'E_NEEDS_SKILL: ' || v_nau_name || ' needs Portuguese Medium Hulls IV'
     or (v_p->>'lit_build_figures')::jsonb is distinct from '{"have": 3, "need": 4, "unit": "level"}'::jsonb
     or v_p->'lit_yard_nau'->>'needs' is distinct from v_nau_name || ' needs Portuguese Medium Hulls IV'
     or (v_p->'lit_yard_nau'->>'buildable')::boolean
     or v_p->>'lit_fit' is distinct from 'E_NEEDS_SKILL: Suit of Sails needs Rigging II'
     or (v_p->>'lit_fit_figures')::jsonb is distinct from '{"have": 0, "need": 2, "unit": "level"}'::jsonb
     or v_p->>'lit_ws_sails' is distinct from 'Suit of Sails needs Rigging II'
     or (v_p->>'lit_fit_store')::int <> 2 or (v_p->>'lit_fit_units')::int <> 1
     or (v_p->>'met_fit_units')::int <> 2
     or v_p->>'met_build' not like 'E_NO_TIMBER:%'
     or v_p->'met_refusal' is distinct from 'null'::jsonb or not (v_p->>'met_met')::boolean, true) then
    raise exception '0133 self-assert FAIL: a requirement did not refuse / pass as written: %', v_p;
  end if;
  -- a merchant, lit: her loadout mounts through the same core; her hull reads the same lit as dark
  if coalesce((v_p->>'npc_fit')::int < 1 or v_p->'npc_units' is distinct from v_p->'npc_pattern'
     or v_p->'npc_lit_stats' is distinct from v_p->'npc_dark_stats'
     or v_p->'npc_lit_bonuses' is distinct from '[]'::jsonb, true) then
    raise exception '0133 self-assert FAIL: a merchant''s loadout did not mount lit, or her hull read differently lit: %', v_p;
  end if;
  if exists (select 1 from public.players where auth_uid = '00000000-0133-4000-8000-000000000001' or company_name = 'Prova Mercante 0133')
     or public.skills_bite_on() or (select count(*) from public.skill_requirements) <> 0
     or public.wc_int('fleet_ship_max') = 40 then
    raise exception '0133 self-assert FAIL: the probe world was not rolled back';
  end if;

  -- (l) MERCHANT READS, DARK ≈ BEFORE: each the faster of two passes; dark ≤ before × 1.15 + 50 ms (the
  --     arrivals sweep's budget is 10 s, and prod is already near it)
  for h in select b.what, b.ms as before_ms, a.ms as after_ms from reads_0133 b
             join reads_0133 a on a.what = b.what and a.phase = 'after' where b.phase = 'before' loop
    if h.after_ms > h.before_ms * 1.15 + 50 then
      raise exception '0133 self-assert FAIL: the merchant % read regressed dark: % ms → % ms', h.what, h.before_ms, h.after_ms;
    end if;
  end loop;
end $$;

-- ── 7. LAST: drop item_level_asks, the FKs to skills — one short retried step, NOWAIT, fixed order ─
create temp table swap_0133 (what text, ms numeric, at timestamptz) on commit drop;
insert into swap_0133 (what, ms, at)
select 'last', pg_temp.locked_0133($last$
  -- 1. item_kinds, then item_level_asks (its FK triggers live on item_kinds) — NOWAIT: never wait holding a lock
  lock table public.item_kinds in access exclusive mode nowait;
  lock table public.item_level_asks in access exclusive mode nowait;
  drop table public.item_level_asks;
  -- 2. SHARE ROW EXCLUSIVE on skills, NOWAIT: the two FKs to skills(code)
  lock table public.skills in share row exclusive mode nowait;
  alter table public.skill_effects add constraint skill_effects_skill_code_fkey
    foreign key (skill_code) references public.skills(code);
  alter table public.skill_requirements add constraint skill_requirements_skill_code_fkey
    foreign key (skill_code) references public.skills(code);
$last$, 'the last step (drop item_level_asks; FKs to skills)'), clock_timestamp();

-- ── SELF-ASSERT (light: catalogue reads) ───────────────────────────────────────────────────────
do $$
declare
  r       record;
  v_notes text := '';
  v_p     jsonb := (select j from probe_0133);
begin
  if to_regclass('public.item_level_asks') is not null then
    raise exception '0133 self-assert FAIL: item_level_asks is still there';
  end if;
  if (select count(*) from pg_constraint
       where conname in ('skill_effects_skill_code_fkey', 'skill_requirements_skill_code_fkey') and contype = 'f') <> 2
     or exists (select 1 from pg_constraint where conrelid = 'public.skill_effects'::regclass and confrelid = 'public.ships'::regclass) then
    raise exception '0133 self-assert FAIL: the foreign keys are not as the header says';
  end if;

  for r in select b.what, b.ms as before_ms, a.ms as after_ms, l.ms as lit_ms, b.hulls
             from reads_0133 b
             join reads_0133 a on a.what = b.what and a.phase = 'after'
             left join lit_reads_0133 l on l.what = b.what
            where b.phase = 'before' order by b.what desc loop
    v_notes := v_notes || format('%s over %s merchant hull(s) (faster of 2) %s ms before → %s ms dark → %s ms lit; ',
                                 r.what, r.hulls, r.before_ms, r.after_ms, r.lit_ms);
  end loop;

  raise notice '0133 self-assert ok: A SKILL MAKES THE SHIP BETTER (dark: skills_bite false). DARK = THE PRE-IMAGE — STATS: %. BUDGETS + SHIP_VIEW: % (ship_view = the pre-image plus bonuses = []). COMPANY EFFECTS: % = the pre-image (player_skill_bonus over skill_effects). OFFICER BONUSES: % = the pre-image. CAPS / REFUSALS / YARDS: % — every company''s hull cap is ship_max, no requirement refuses any company any hull or item, every yard and workshop answer = the pre-image plus needs = null. CATALOGUE: % (company rows mirror skills.effect / pct_per_level; hull rows = every line''s two traits × its sizes). RETIRED: %, dropped in the last step (ship_fittings_retired_0132 left for a later migration). ACADEMY: world.skills reads skill_effects, = the pre-image as text. Eleven bodies reverse to their pre-images, ACLs unmoved; ship_slots / skill_level / skill_level_at / ship_racks / class_budget untouched; skills / ship_classes / item_kinds / class_profile / ship_lines unmoved; no new body reads is_npc; no new entry point, the new tables and functions server-only. PROBE (own company, rolled back) — DARK: trained skills + planted requirements moved nothing (build: %; cap refusal: %). LIT: PRT Medium Hulls III → nau sighting % → %, speed % → % (+12%% / +6%%, rounded to the stat''s scale, nothing else; the barca unmoved), listed as "Portuguese Medium Hulls III · +12%% sighting / +6%% speed"; Deck Management II → Deck 56 → 61; Gun Drill II → two guns 16 → 14 Hands; Command II → officer bonus % → %, hull cap % → % (a % refused: %); requirements: %, figures %; %; the yard serves "%", the workshop "%"; met → FIT on, BUILD stops at the shed as dark. A merchant lit: her loadout mounted (% units = her pattern) and her hull read the same lit as dark. READS: %RE-MEASURE ON PROD BEFORE THROWING skills_bite (arrivals budget 10 s). LOCKS: nothing anyone waits on before §7; ships never locked; the last step (NOWAIT) % ms; held % ms from it to the end of the file.',
    (select v from proven_0133 where k = 'stats'), (select v from proven_0133 where k = 'budget'),
    (select v from proven_0133 where k = 'company'), (select v from proven_0133 where k = 'officers'),
    (select v from proven_0133 where k = 'caps'), (select v from proven_0133 where k = 'catalogue'),
    (select v from proven_0133 where k = 'retired'),
    v_p->>'dark_build', v_p->>'dark_cap_refusal',
    v_p->'dark_nau'->>'sighting', v_p->'lit_nau'->>'sighting', v_p->'dark_nau'->>'speed', v_p->'lit_nau'->>'speed',
    v_p->>'dark_officer', v_p->>'lit_officer', v_p->>'dark_ship_max', v_p->>'lit_ship_max',
    public.wc_int('ship_max') + 3, v_p->>'lit_cap_refusal',
    v_p->>'lit_build', v_p->>'lit_build_figures', v_p->>'lit_fit',
    v_p->'lit_yard_nau'->>'needs', v_p->>'lit_ws_sails', v_p->>'npc_fit',
    v_notes, (select ms from swap_0133 where what = 'last'),
    round(extract(epoch from clock_timestamp() - (select at from swap_0133 where what = 'last')) * 1000, 1);
end $$;
